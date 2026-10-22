// Times, money and tool calls in words, and reading the owner's messages. Ported from moiraine's src/format.ts.
import Foundation

public enum Format {
	/// "$0.042" under a dollar, "$3.10" from one.
	public static func money(_ dollars: Double) -> String {
		String(format: dollars < 1 ? "$%.3f" : "$%.2f", dollars)
	}

	/// An agent's badge letter: the first of its name.
	public static func initial(_ name: String) -> String {
		name.trimmingCharacters(in: .whitespaces).first.map { String($0).uppercased() } ?? "?"
	}

	/// The owner's messages start with the local time in brackets ("[Sat 2026-10-10 19:31 GMT-4] "); apart from the text.
	public static func splitStamp(_ text: String) -> (time: String?, text: String) {
		guard text.hasPrefix("["), let close = text.firstIndex(of: "]") else { return (nil, text) }
		let after = text.index(after: close)
		guard after < text.endIndex, text[after] == " " else { return (nil, text) }
		let time = String(text[text.index(after: text.startIndex)..<close])
		guard !time.isEmpty else { return (nil, text) }
		return (time, String(text[text.index(after: after)...]))
	}

	/// "Sat 2026-10-10 19:31 GMT-4" (gaidin's src/time.ts) as "19:31" on `today`'s date, or "Oct 10" another day.
	public static func shortStamp(_ stamp: String, today: Date = .now, calendar: Calendar = .current) -> String {
		let parts = stamp.split(separator: " ")
		guard parts.count >= 3 else { return stamp }
		let date = parts[1].split(separator: "-").compactMap { Int($0) }
		guard date.count == 3, parts[2].count == 5, parts[2].contains(":") else { return stamp }
		let now = calendar.dateComponents([.year, .month, .day], from: today)
		if date[0] == now.year, date[1] == now.month, date[2] == now.day { return String(parts[2]) }
		guard let day = calendar.date(from: DateComponents(year: date[0], month: date[1], day: date[2])) else { return stamp }
		return day.formatted(.dateTime.month(.abbreviated).day())
	}

	public static func text(of parts: [Part]) -> String {
		parts.map { part in
			switch part {
			case .text(let text): text
			case .image: "[image]"
			case .other(let type): "[\(type)]"
			}
		}.joined()
	}

	/// An owner's message, apart: its text without the stamp, the images that went with it, where its other files were
	/// saved (from the note gaidin adds, "[Files from the app: a is saved as uploads/x (...); ...]"), and, for what a
	/// speaker heard, the speaker ("[spoken] (kitchen speaker) ...").
	public struct Said: Sendable, Hashable {
		public var time: String?
		public var speaker: String?
		public var text: String
		public var images: [ImageData]
		public var files: [String]
	}

	public struct ImageData: Sendable, Hashable {
		public var data: String
		public var mimeType: String
	}

	public static func ownerMessage(_ parts: [Part]) -> Said {
		let whole = parts.map { if case .text(let text) = $0 { text } else { "" } }.joined()
		let images = parts.compactMap { if case .image(let data, let mimeType) = $0 { ImageData(data: data, mimeType: mimeType) } else { nil } }
		var body = whole
		var files: [String] = []
		if let note = whole.firstMatch(of: #/\n\n\[Files from [^:]+: ([\s\S]*?)\. Read them with the file tools[\s\S]*\]$/#) {
			files = note.1.components(separatedBy: "; ")
			body = String(whole[..<note.range.lowerBound])
		}
		let (time, text) = splitStamp(body)
		if let heard = text.firstMatch(of: #/^\[spoken\] \(([a-z][a-z0-9-]*) speaker\) /#) {
			return Said(time: time, speaker: String(heard.1), text: String(text[heard.range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines), images: images, files: files)
		}
		return Said(time: time, speaker: nil, text: text.trimmingCharacters(in: .whitespacesAndNewlines), images: images, files: files)
	}

	/// A message on one line: no stamp, no note of files, no runs of space.
	public static func oneLine(_ text: String) -> String {
		var body = splitStamp(text).text
		if let note = body.firstMatch(of: #/\n\n\[Files from [\s\S]*\]$/#) { body = String(body[..<note.range.lowerBound]) }
		return body.split(whereSeparator: \.isWhitespace).joined(separator: " ")
	}

	/// A tool call in a line: the command, path, URL or text it was given.
	public static func argsSummary(_ name: String, _ args: JSONValue) -> String {
		let field = { (key: String) in args[key]?.stringValue }
		if name == "bash", let command = field("command") { return command }
		if name.wholeMatch(of: #/(read|write|remove)_skill/#) != nil, let skill = field("name") { return "\(skill)/\(field("file") ?? "SKILL.md")" }
		if let path = field("path") { return path }
		if let url = field("url") { return url }
		if name == "remind" {
			let at = field("at") ?? args["inMinutes"].map { "in \($0.jsonText) min" } ?? ""
			return "\(field("text") ?? "") \(at)"
		}
		if let title = field("title") { return title }
		if let text = field("text") { return text }
		let json = args.jsonText
		return json == "{}" ? "" : json
	}

	/// The sidebar's group for something last active at `at`: today, the six days before, or older.
	public static func ageGroup(_ at: Date, now: Date = .now, calendar: Calendar = .current) -> String {
		let start = calendar.startOfDay(for: now)
		if at >= start { return "today" }
		return at >= start.addingTimeInterval(-6 * 86_400) ? "this week" : "older"
	}

	/// When something last happened, short: the time today, "Yesterday", a weekday this week, or a date.
	public static func lastSeen(_ at: Date, now: Date = .now, calendar: Calendar = .current) -> String {
		let start = calendar.startOfDay(for: now)
		if at >= start { return at.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits)) }
		if at >= start.addingTimeInterval(-86_400) { return "Yesterday" }
		if at >= start.addingTimeInterval(-6 * 86_400) { return at.formatted(.dateTime.weekday(.abbreviated)) }
		return at.formatted(.dateTime.month(.abbreviated).day())
	}

	/// "Thu, Oct 22, 18:30", for when a request stops waiting.
	public static func when(_ at: Date) -> String {
		at.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
	}

	/// Milliseconds since 1970, as gaidin gives times.
	public static func date(_ milliseconds: Double) -> Date {
		Date(timeIntervalSince1970: milliseconds / 1000)
	}
}
