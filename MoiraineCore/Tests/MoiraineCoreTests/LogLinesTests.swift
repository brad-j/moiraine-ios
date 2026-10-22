import Foundation
import Testing
@testable import MoiraineCore

@Suite struct LogLinesTests {
	let options = LogOptions(speaker: "gaidin")
	/// The day the fixtures were recorded, so the gutter shows times rather than dates.
	let recorded = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 22, hour: 20))!

	@Test func theRecordedConversationReadsAsTheLogDoes() throws {
		let lines = LogLines.lines(try Fixtures.transcript("whole"), options: options, live: true, today: recorded)
		let read = lines.map { "\($0.kind.rawValue) \($0.label)" }
		#expect(read == [
			"you you", "agent gaidin",
			"you you", "agent gaidin",
			"you you", "tool fetch_url", "agent gaidin",
			"you you", "tool ask_owner", "agent gaidin",
		])
		#expect(lines[0].start)
		#expect(lines[0].time?.wholeMatch(of: /\d\d:\d\d/) != nil)
		guard case .said(let said) = lines[0].body else { Issue.record("not the owner's message"); return }
		#expect(said.text == "hello")
		guard case .fold(let summary, _, let status, _) = lines[5].body else { Issue.record("not a fold"); return }
		#expect(summary.hasPrefix("http://site.test:"))
		#expect(status == .done)
	}

	@Test func aRunThatHasntAnsweredShowsTheAgentsLineComing() {
		var transcript = Transcript()
		transcript.apply(.snapshot(Snapshot(entries: [Entry(id: 1, conversationId: 1, kind: "pi.user", model: [.user(content: [.text("[Thu 2026-10-22 18:23 GMT-4] hi")], timestamp: 1)])], running: true, partial: nil, tools: [], agent: nil, usage: nil)))
		let lines = LogLines.lines(transcript, options: options, live: true, today: recorded)
		#expect(lines.last?.id == "coming")
		#expect(lines.last?.body == .answer("", live: true))
		#expect(LogLines.lines(transcript, options: options, live: false).last?.kind == .you)
	}

	@Test func stepsInARowGatherIntoOne() {
		let call = { (id: String) in Block.toolCall(id: id, name: "bash", arguments: .object(["command": .string("ls")])) }
		var transcript = Transcript()
		transcript.apply(.snapshot(Snapshot(entries: [Entry(id: 2, conversationId: 1, kind: "pi.assistant", model: [.assistant(AssistantMessage(content: [.thinking("hmm", redacted: false), call("a"), call("b"), .text("done")], timestamp: 9))])], running: true, partial: nil, tools: [ToolSlot(callId: "b", name: "bash", status: "running", output: "x\n")], agent: nil, usage: nil)))
		let lines = LogLines.lines(transcript, options: options, live: true)
		let items = LogLines.items(lines)
		#expect(items.count == 2)
		guard case .steps(_, let steps) = items[0] else { Issue.record("not gathered"); return }
		#expect(steps.count == 3)
		let state = LogLines.stepsState(steps)
		#expect(state.live == .running)
		#expect(state.names == ["thinking", "bash"])
		// A call with no result and no slot while the run goes on is waiting to run.
		#expect(steps[1].stepStatus == .waiting)
	}

	@Test func aJobsReportIsItsTitleThenTheAnswer() {
		var transcript = Transcript()
		transcript.apply(.entryAppended(Entry(id: 3, conversationId: 1, kind: "gaidin.job-reported", model: nil, data: .object(["title": .string("Morning briefing"), "text": .string("**Sunny**"), "delivered": .bool(true)]))))
		let lines = LogLines.lines(transcript, options: options, live: false)
		#expect(lines.map(\.body) == [.job(title: "Morning briefing", failure: nil), .answer("**Sunny**", live: false)])
		#expect(lines[0].start)
	}

	@Test func aStopsNoteReplacesTheStoppedLineAboveIt() {
		var transcript = Transcript()
		transcript.apply(.entryAppended(Entry(id: 4, conversationId: 1, kind: "pi.assistant", model: [.assistant(AssistantMessage(content: [], timestamp: 3, stopReason: "aborted"))])))
		transcript.apply(.entryAppended(Entry(id: 5, conversationId: 1, kind: "gaidin.stopped", model: nil, data: nil)))
		let lines = LogLines.lines(transcript, options: options, live: false)
		#expect(lines.count == 1)
		#expect(lines[0].body == .text("Stopped. gaidin will drop that request unless you ask again."))
	}
}
