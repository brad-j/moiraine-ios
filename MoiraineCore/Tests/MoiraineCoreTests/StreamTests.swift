import Foundation
import Testing
@testable import MoiraineCore

@Suite struct SSEParserTests {
	@Test func eventsEndAtBlankLinesAndPingsAreSkipped() {
		let text = ": ping\n\ndata: {\"type\":\"run_start\"}\n\ndata: one\ndata: two\n\n"
		#expect(SSEParser.events(in: text) == ["{\"type\":\"run_start\"}", "one\ntwo"])
	}

	@Test func carriageReturnsAndOtherFieldsAreIgnored() {
		var parser = SSEParser()
		#expect(parser.feed("event: message\r") == nil)
		#expect(parser.feed("id: 4\r") == nil)
		#expect(parser.feed("data:tight\r") == nil)
		#expect(parser.feed("\r") == "tight")
		#expect(parser.feed("") == nil)
	}

	@Test func anEventCutOffHasNoData() {
		#expect(SSEParser.events(in: "data: {\"type\":") == [])
	}
}

@Suite struct DecodingTests {
	@Test func gaidinsOwnEventsDecode() throws {
		#expect(try StreamEvent.decode(Data(#"{"type":"approvals_changed"}"#.utf8)) == .approvalsChanged)
		#expect(try StreamEvent.decode(Data(#"{"type":"activity_changed","agent":"verin"}"#.utf8)) == .activityChanged(agent: "verin"))
		#expect(try StreamEvent.decode(Data(#"{"type":"conversations_changed","agent":"verin"}"#.utf8)) == .conversationsChanged(agent: "verin"))
	}

	@Test func anUnknownEventOrBlockIsKeptAsOther() throws {
		#expect(try StreamEvent.decode(Data(#"{"type":"something_new","x":1}"#.utf8)) == .other(type: "something_new"))
		let start = try StreamEvent.decode(Data(#"{"type":"message_start","message":{"role":"assistant","content":[{"type":"hologram"}],"timestamp":5}}"#.utf8))
		guard case .messageStart(.assistant(let message)) = start else { Issue.record("not an assistant message"); return }
		#expect(message.content == [.other(type: "hologram")])
	}

	@Test func aStringContentIsOneTextPart() throws {
		let message = try JSONDecoder().decode(Message.self, from: Data(#"{"role":"user","content":"[Thu 2026-10-22 18:23 GMT-4] hello","timestamp":1}"#.utf8))
		#expect(message == .user(content: [.text("[Thu 2026-10-22 18:23 GMT-4] hello")], timestamp: 1))
	}

	@Test func aBudgetOfNullIsNone() throws {
		#expect(try JSONDecoder().decode(Budget?.self, from: Data("null".utf8)) == nil)
	}

	@Test func everyRecordedEventDecodesAsAKnownKind() throws {
		for name in ["whole", "streaming"] {
			for data in try Fixtures.stream(name) {
				let event = try StreamEvent.decode(Data(data.utf8))
				// turn_start, turn_end and submission are pi-durable's and the app has no use for them.
				if case .other(let type) = event { #expect(["turn_start", "turn_end", "submission"].contains(type), "\(name): \(type)") }
			}
		}
	}
}

@Suite struct TranscriptTests {
	/// Reducing the stream arrives where gaidin's own snapshot is at the end.
	@Test(arguments: ["whole", "streaming"]) func theStreamConvergesOnGaidinsSnapshot(name: String) throws {
		let transcript = try Fixtures.transcript(name)
		let final = try Fixtures.final(name)
		#expect(transcript.ordered == final.entries)
		#expect(!transcript.running)
		#expect(transcript.partial == nil)
		#expect(transcript.tools.isEmpty)
		#expect(transcript.usage == final.usage)
	}

	@Test func deltasBuildTheAnswerAsItStreams() throws {
		var transcript = Transcript()
		var lengths: [Int] = []
		for data in try Fixtures.stream("streaming") {
			transcript.apply(try StreamEvent.decode(Data(data.utf8)))
			if case .text(let text)? = transcript.partial?.content.first { lengths.append(text.count) }
		}
		#expect(lengths.count > 3)
		// Within one answer the text only grows.
		#expect(zip(lengths, lengths.dropFirst()).contains { $0 < $1 })
	}

	@Test func aToolsOutputIsTrimmedInUTF16UnitsAndAppended() {
		var transcript = Transcript()
		transcript.apply(.toolStart(callId: "c", name: "bash"))
		transcript.apply(.toolUpdate(callId: "c", .set("é😀abc")))
		// 😀 is two UTF-16 units: trimming 3 leaves "abc".
		transcript.apply(.toolUpdate(callId: "c", .trimAndAppend(trimStart: 3, append: "d")))
		#expect(transcript.tools["c"]?.output == "abcd")
		transcript.apply(.toolEnd(callId: "c", entry: nil))
		#expect(transcript.tools.isEmpty)
	}

	@Test func toolCallArgumentsStreamAtTheirPath() {
		var transcript = Transcript()
		transcript.apply(.messageStart(.assistant(AssistantMessage(content: [], timestamp: 1))))
		transcript.apply(.messageUpdate([.block(index: 0, .toolCall(id: "t", name: "bash", arguments: .object([:]))), .toolCallDelta(index: 0, path: [.key("command")], "ls "), .toolCallDelta(index: 0, path: [.key("command")], "-la")]))
		#expect(transcript.partial?.content == [.toolCall(id: "t", name: "bash", arguments: .object(["command": .string("ls -la")]))])
	}

	@Test func aSnapshotReplacesEverything() throws {
		var transcript = try Fixtures.transcript("whole")
		transcript.apply(.snapshot(Snapshot(entries: [], running: true, partial: nil, tools: [ToolSlot(callId: "x", name: "bash", status: "running", output: "hi")], agent: nil, usage: nil)))
		#expect(transcript.entries.isEmpty)
		#expect(transcript.running)
		#expect(transcript.tools["x"]?.output == "hi")
	}
}
