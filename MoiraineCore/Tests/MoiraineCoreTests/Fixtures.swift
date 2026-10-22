import Foundation
@testable import MoiraineCore

/// The recorded streams in fixtures/ (scripts/record-fixtures.ts).
enum Fixtures {
	static let directory = URL(filePath: #filePath).deletingLastPathComponent().appending(path: "../../../fixtures").standardizedFileURL

	/// Each event's data in `<name>.sse`, as it came.
	static func stream(_ name: String) throws -> [String] {
		SSEParser.events(in: try String(contentsOf: directory.appending(path: "\(name).sse"), encoding: .utf8))
	}

	/// The snapshot gaidin sent a second connection, once the recording was done.
	static func final(_ name: String) throws -> Snapshot {
		let event = try StreamEvent.decode(try Data(contentsOf: directory.appending(path: "\(name).final.json")))
		guard case .snapshot(let snapshot) = event else { throw CocoaError(.fileReadCorruptFile) }
		return snapshot
	}

	/// The stream reduced, from its snapshot on.
	static func transcript(_ name: String) throws -> Transcript {
		var transcript = Transcript()
		for data in try stream(name) { transcript.apply(try StreamEvent.decode(Data(data.utf8))) }
		return transcript
	}
}
