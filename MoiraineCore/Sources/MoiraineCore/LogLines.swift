// A conversation as the log draws it: the owner's messages, the answers, and each tool call and stretch of thinking
// folded to a line, with two or more such steps in a row gathered into one. Each line has a gutter: the time an
// exchange started and who wrote it, the agent by name and a tool call by the tool's. Ported from moiraine's
// src/conversation/log.tsx, as data for the view to draw.
import Foundation

/// Who or what wrote a line, which sets its gutter's label and color.
public enum LineKind: String, Sendable, Hashable {
	/// The owner, or a speaker.
	case you
	/// The agent's words.
	case agent
	/// A job's prompt, or another agent's message, in a conversation they started.
	case prompt
	case tool
	case think
	case summary
	case remind
	case job
	case sys
	case stopped
	case error
}

public enum ToolStatus: String, Sendable, Hashable {
	case done, error, running, waiting
	case noResult = "no result"

	public var settled: Bool { self == .done || self == .error || self == .noResult }
	public var failed: Bool { self == .error || self == .noResult }
}

public enum LineBody: Sendable, Hashable {
	case said(Format.Said)
	/// An answer's Markdown; `live` while it's being written.
	case answer(String, live: Bool)
	/// Thinking, a tool call or a summary, folded: its one line, and what opening it shows.
	case fold(summary: String, sections: [FoldSection], status: ToolStatus?, tail: String?)
	case text(String)
	/// A reminder that fired, with what to snooze it by.
	case reminder(text: String, failure: String?, taskId: Int?)
	/// A job's report: its title above it.
	case job(title: String, failure: String?)
}

public struct FoldSection: Sendable, Hashable {
	public var label: String?
	public var text: String
}

public struct LogLine: Sendable, Hashable, Identifiable {
	public var id: String
	public var kind: LineKind
	public var label: String
	public var body: LineBody
	/// The first line of an exchange, which has a little room above it.
	public var start = false
	/// The exchange's time in the gutter, short, and in full.
	public var time: String?
	public var fullTime: String?
	/// A tool call or thinking, which gathers with the steps beside it.
	public var step: (name: String, status: ToolStatus)? {
		get { stepName.map { ($0, stepStatus ?? .done) } }
		set {
			stepName = newValue?.name
			stepStatus = newValue?.status
		}
	}

	var stepName: String?
	var stepStatus: ToolStatus?

	public init(id: String, kind: LineKind, label: String, body: LineBody) {
		self.id = id
		self.kind = kind
		self.label = label
		self.body = body
	}

	public var isStep: Bool { stepName != nil }
}

/// What the log shows: a line, or steps in a row as one line naming them.
public enum LogItem: Sendable, Hashable, Identifiable {
	case line(LogLine)
	case steps(id: String, [LogLine])

	public var id: String {
		switch self {
		case .line(let line): line.id
		case .steps(let id, _): id
		}
	}
}

public struct LogOptions: Sendable, Hashable {
	/// The agent answering, whose name is beside its words.
	public var speaker: String
	/// Who the user messages are from: the owner (nil), a job's prompts ("job") or another agent's ("agent").
	public var prompts: String?

	public init(speaker: String, prompts: String? = nil) {
		self.speaker = speaker
		self.prompts = prompts
	}
}

public enum LogLines {
	/// The lines for `transcript`'s entries that `include` keeps, oldest first, and, when `live`, the answer still coming
	/// in at the end.
	public static func lines(_ transcript: Transcript, include: (Entry) -> Bool = { _ in true }, options: LogOptions, live: Bool, today: Date = .now) -> [LogLine] {
		let entries = transcript.ordered
		var results: [String: (content: [Part], isError: Bool)] = [:]
		for entry in entries {
			for case .toolResult(let callId, _, let content, let isError) in entry.model ?? [] { results[callId] = (content, isError) }
		}
		var lines: [LogLine] = []
		for entry in entries where include(entry) {
			let more = entryLines(transcript, entry, results, before: &lines, options: options, today: today)
			lines.append(contentsOf: more)
		}
		if live, let partial = transcript.partial {
			lines.append(contentsOf: blockLines(transcript, partial.content, key: answerKey(partial, "partial"), results, live: true, options: options))
		}
		// Sent, and the agent hasn't written anything back yet: its line, with the caret, so the owner sees it's begun.
		if live, transcript.running, let last = lines.last?.kind, last == .you || last == .prompt {
			lines.append(LogLine(id: "coming", kind: .agent, label: options.speaker, body: .answer("", live: true)))
		}
		// Two answers can't start in the same millisecond in one conversation, but an id given twice would mix them up.
		var seen = Set<String>()
		return lines.map { line in
			var line = line
			while seen.contains(line.id) { line.id += "'" }
			seen.insert(line.id)
			return line
		}
	}

	/// `lines`, with two or more steps in a row gathered into one item.
	public static func items(_ lines: [LogLine]) -> [LogItem] {
		var items: [LogItem] = []
		var index = 0
		while index < lines.count {
			var end = index
			while end < lines.count, lines[end].isStep { end += 1 }
			if end - index >= 2 {
				let run = Array(lines[index..<end])
				items.append(.steps(id: "steps:\(run[0].id)", run))
				index = end
			} else {
				items.append(.line(lines[index]))
				index += 1
			}
		}
		return items
	}

	/// Steps in a row, summed up: running or waiting while one is, and how many failed.
	public static func stepsState(_ lines: [LogLine]) -> (live: ToolStatus?, failed: Int, names: [String]) {
		let statuses = lines.compactMap(\.stepStatus)
		let live: ToolStatus? = statuses.contains(.running) ? .running : statuses.contains(.waiting) ? .waiting : nil
		var names: [String] = []
		for name in lines.compactMap(\.stepName) where !names.contains(name) { names.append(name) }
		return (live, statuses.filter(\.failed).count, names)
	}

	/// An answer's key: when its request started, which it has from its first word to its entry, so its lines keep their
	/// place, and stay open, as the answer being written becomes the entry.
	static func answerKey(_ message: AssistantMessage, _ fallback: String) -> String {
		message.timestamp.map { "a\(Int($0))" } ?? fallback
	}

	static func blockLines(_ transcript: Transcript, _ blocks: [Block], key: String, _ results: [String: (content: [Part], isError: Bool)], live: Bool, options: LogOptions) -> [LogLine] {
		var out: [LogLine] = []
		for (index, block) in blocks.enumerated() {
			let id = "\(key):\(index)"
			switch block {
			case .text(let text) where !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty:
				out.append(LogLine(id: id, kind: .agent, label: options.speaker, body: .answer(text, live: live)))
			case .thinking(let text, let redacted):
				// A model with thinking off can still send an empty block.
				if !redacted, text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { continue }
				let preview = redacted ? "redacted" : text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
				var line = LogLine(id: id, kind: .think, label: "think", body: .fold(summary: preview, sections: [FoldSection(label: nil, text: redacted ? "Redacted by the provider." : text)], status: nil, tail: nil))
				line.step = ("thinking", .done)
				out.append(line)
			case .toolCall(let callId, let name, let arguments):
				let result = results[callId]
				let run = transcript.tools[callId]
				let status: ToolStatus = result.map { $0.isError ? .error : .done } ?? (run != nil ? .running : transcript.running ? .waiting : .noResult)
				let output = result.map { Format.text(of: $0.content) } ?? run?.output ?? ""
				let input = name == "bash" ? (arguments["command"]?.stringValue ?? arguments.jsonText) : pretty(arguments)
				var sections = [FoldSection(label: "input", text: input)]
				if result != nil || run != nil { sections.append(FoldSection(label: "output", text: output.isEmpty ? "(no output)" : output)) }
				let tail = status == .running && !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? lastLines(output, 6) : nil
				// Keyed by the call, so it stays open when the answer being written becomes an entry.
				var line = LogLine(id: callId, kind: .tool, label: name, body: .fold(summary: Format.argsSummary(name, arguments), sections: sections, status: status, tail: tail))
				line.step = (name, status)
				out.append(line)
			default:
				continue
			}
		}
		return out
	}

	static func entryLines(_ transcript: Transcript, _ entry: Entry, _ results: [String: (content: [Part], isError: Bool)], before lines: inout [LogLine], options: LogOptions, today: Date) -> [LogLine] {
		var out: [LogLine] = []
		let key = String(entry.id)
		var starts = false
		var time: String?
		let data = entry.data ?? .null
		switch entry.kind {
		case "gaidin.reminder-fired":
			starts = true
			let failure = data["delivered"] == .bool(true) ? nil : "push failed: \(data["error"]?.stringValue ?? "")"
			let taskId: Int? = if case .number(let id) = data["taskId"] { Int(id) } else { nil }
			out.append(LogLine(id: key, kind: .remind, label: "remind", body: .reminder(text: data["text"]?.stringValue ?? "", failure: failure, taskId: taskId)))
		case "gaidin.job-reported":
			starts = true
			let failure = data["delivered"] == .bool(true) ? nil : "not delivered: \(data["error"]?.stringValue ?? "")"
			out.append(LogLine(id: key, kind: .job, label: "job", body: .job(title: data["title"]?.stringValue ?? "", failure: failure)))
			out.append(LogLine(id: "\(key):report", kind: .agent, label: options.speaker, body: .answer(data["text"]?.stringValue ?? "", live: false)))
		case "gaidin.stopped":
			// The note a stop leaves for the model says the same as the "Stopped." above it, and more.
			let text = "Stopped. \(options.speaker) will drop that request unless you ask again."
			if let last = lines.indices.last, lines[last].kind == .stopped {
				lines[last].body = .text(text)
			} else {
				out.append(LogLine(id: key, kind: .stopped, label: "sys", body: .text(text)))
			}
			return out
		case "pi.compaction":
			// What the model reads from here on instead of the messages above.
			let summary = (entry.model ?? []).map { if case .user(let content, _) = $0 { Format.text(of: content) } else { "" } }.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
			out.append(LogLine(id: key, kind: .summary, label: "summary", body: .fold(summary: "Older messages summarised; the model reads this summary instead of them", sections: [FoldSection(label: nil, text: summary.isEmpty ? "(no summary text)" : summary)], status: nil, tail: nil)))
			return out
		default:
			break
		}
		for (n, message) in (entry.model ?? []).enumerated() {
			switch message {
			case .user(let content, _):
				if entry.kind == "pi.user" {
					let said = Format.ownerMessage(content)
					starts = true
					time = said.time
					if let prompts = options.prompts {
						out.append(LogLine(id: "\(key):\(n)", kind: .prompt, label: prompts, body: .said(said)))
					} else {
						// What a speaker heard is from whoever was in the room, so it's labeled with the speaker.
						out.append(LogLine(id: "\(key):\(n)", kind: .you, label: said.speaker ?? "you", body: .said(said)))
					}
				} else {
					out.append(LogLine(id: "\(key):\(n)", kind: .sys, label: "note", body: .text("\(entry.kind): \(Format.splitStamp(Format.text(of: content)).text)")))
				}
			case .assistant(let assistant):
				out.append(contentsOf: blockLines(transcript, assistant.content, key: answerKey(assistant, key), results, live: false, options: options))
				if assistant.stopReason == "error" { out.append(LogLine(id: "\(key):error", kind: .error, label: "error", body: .text(assistant.errorMessage ?? "The model returned an error."))) }
				if assistant.stopReason == "aborted" { out.append(LogLine(id: "\(key):aborted", kind: .stopped, label: "sys", body: .text("Stopped."))) }
			case .toolResult, .other:
				continue
			}
		}
		if starts, !out.isEmpty {
			out[0].start = true
			if let time {
				out[0].time = Format.shortStamp(time, today: today)
				out[0].fullTime = time
			}
		}
		return out
	}

	static func pretty(_ value: JSONValue) -> String {
		let encoder = JSONEncoder()
		encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
		return (try? encoder.encode(value)).map { String(decoding: $0, as: UTF8.self) } ?? value.jsonText
	}

	static func lastLines(_ text: String, _ count: Int) -> String {
		var trimmed = text
		while trimmed.last?.isWhitespace == true { trimmed.removeLast() }
		return trimmed.components(separatedBy: "\n").suffix(count).joined(separator: "\n")
	}
}
