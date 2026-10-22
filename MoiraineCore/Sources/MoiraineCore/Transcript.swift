// The app's copy of a conversation, rebuilt from gaidin's event stream: a snapshot, then a batch of events per commit.
// It only keeps state; the conversation view draws it. Ported from moiraine's src/transcript.ts.
import Foundation

/// A running tool call and its output so far.
public struct ToolRun: Sendable, Hashable {
	public var callId: String
	public var name: String
	public var output: String
}

public struct Transcript: Sendable, Hashable {
	public var entries: [Int: Entry] = [:]
	/// The assistant message being generated.
	public var partial: AssistantMessage?
	/// Running tool calls, by tool call id.
	public var tools: [String: ToolRun] = [:]
	public var running = false
	/// Why the model is being asked again, while it is.
	public var retry: String?
	public var usage: UsageState?
	/// The conversation's model and thinking level.
	public var agent: AgentState?

	public init() {}

	/// The entries, oldest first.
	public var ordered: [Entry] {
		entries.values.sorted { $0.id < $1.id }
	}

	public var lastEntryId: Int {
		entries.keys.max() ?? 0
	}

	public mutating func apply(_ event: StreamEvent) {
		switch event {
		case .snapshot(let snapshot):
			// A (re)connection may have missed changes, so everything is replaced.
			entries = Dictionary(snapshot.entries.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
			partial = snapshot.partial
			tools = Dictionary(
				snapshot.tools.filter { $0.status == "running" }.map { ($0.callId, ToolRun(callId: $0.callId, name: $0.name, output: $0.output ?? "")) },
				uniquingKeysWith: { _, last in last }
			)
			running = snapshot.running
			usage = snapshot.usage
			agent = snapshot.agent
		case .runStart:
			running = true
		case .runEnd:
			running = false
			partial = nil
			retry = nil
		case .messageStart(let message):
			if case .assistant(let assistant) = message { partial = assistant }
		case .messageUpdate(let changes):
			guard var message = partial else { break }
			for change in changes { message.apply(change) }
			partial = message
		case .messageEnd(let entry):
			partial = nil
			entries[entry.id] = entry
		case .toolStart(let callId, let name):
			tools[callId] = ToolRun(callId: callId, name: name, output: "")
		case .toolUpdate(let callId, let change):
			guard var run = tools[callId], let change else { break }
			switch change {
			case .set(let text):
				run.output = text
			case .trimAndAppend(let trimStart, let append):
				// gaidin counts in UTF-16 units, as JavaScript does.
				let units = Array(run.output.utf16)
				run.output = String(decoding: units.dropFirst(min(trimStart, units.count)), as: UTF16.self) + append
			}
			tools[callId] = run
		case .toolEnd(let callId, let entry):
			tools[callId] = nil
			if let entry { entries[entry.id] = entry }
		case .entryAppended(let entry):
			entries[entry.id] = entry
		case .usageChanged(let usage):
			self.usage = usage
		case .agentChanged(let agent):
			self.agent = agent
		case .retryStart(let message):
			retry = "retrying: \(message)"
		case .retryEnd:
			retry = nil
		case .taskFailed, .approvalsChanged, .activityChanged, .conversationsChanged, .other:
			break
		}
	}
}

extension AssistantMessage {
	mutating func apply(_ change: MessageChange) {
		switch change {
		case .block(let index, let block):
			set(index, block)
		case .textDelta(let index, let delta):
			if index < content.count, case .text(let text) = content[index] { content[index] = .text(text + delta) }
		case .thinkingDelta(let index, let delta):
			if index < content.count, case .thinking(let text, let redacted) = content[index] { content[index] = .thinking(text + delta, redacted: redacted) }
		case .toolCallDelta(let index, let path, let delta):
			guard index < content.count, case .toolCall(let id, let name, var arguments) = content[index] else { break }
			_ = arguments.append(delta, at: path[...])
			content[index] = .toolCall(id: id, name: name, arguments: arguments)
		case .message(let message):
			content = message.content
		case .other:
			break
		}
	}

	/// Puts `block` at `index`, as JavaScript's array assignment does, filling a gap with empty text.
	private mutating func set(_ index: Int, _ block: Block) {
		while content.count < index { content.append(.text("")) }
		if index < content.count { content[index] = block } else { content.append(block) }
	}
}
