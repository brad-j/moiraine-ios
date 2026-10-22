import Foundation
import Testing
@testable import MoiraineCore

@Suite struct FormatTests {
	@Test func theStampComesApart() {
		#expect(Format.splitStamp("[Thu 2026-10-22 18:23 GMT-4] hello").time == "Thu 2026-10-22 18:23 GMT-4")
		#expect(Format.splitStamp("[Thu 2026-10-22 18:23 GMT-4] hello").text == "hello")
		#expect(Format.splitStamp("[link] text").time == "link")
		#expect(Format.splitStamp("no stamp").time == nil)
	}

	@Test func aStampIsATimeTodayOrADate() {
		let today = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 22, hour: 20))!
		#expect(Format.shortStamp("Thu 2026-10-22 18:23 GMT-4", today: today) == "18:23")
		#expect(Format.shortStamp("Sat 2026-10-10 19:31 GMT-4", today: today) != "19:31")
		#expect(Format.shortStamp("not a stamp", today: today) == "not a stamp")
	}

	@Test func anOwnersMessageLosesItsNoteOfFiles() {
		let text = "[Thu 2026-10-22 18:23 GMT-4] see these\n\n[Files from the app: a.pdf is saved as uploads/a.pdf (2 KB); b.txt is saved as uploads/b.txt (1 KB). Read them with the file tools.]"
		let said = Format.ownerMessage([.text(text), .image(data: "AAAA", mimeType: "image/png")])
		#expect(said.text == "see these")
		#expect(said.files == ["a.pdf is saved as uploads/a.pdf (2 KB)", "b.txt is saved as uploads/b.txt (1 KB)"])
		#expect(said.images == [Format.ImageData(data: "AAAA", mimeType: "image/png")])
		#expect(Format.oneLine(text) == "see these")
	}

	@Test func whatASpeakerHeardIsTheSpeakers() {
		let said = Format.ownerMessage([.text("[Thu 2026-10-22 18:23 GMT-4] [spoken] (kitchen speaker) what's the weather")])
		#expect(said.speaker == "kitchen")
		#expect(said.text == "what's the weather")
	}

	@Test func aToolCallSaysWhatItWasGiven() {
		#expect(Format.argsSummary("bash", .object(["command": .string("ls -la")])) == "ls -la")
		#expect(Format.argsSummary("read_skill", .object(["name": .string("homelab")])) == "homelab/SKILL.md")
		#expect(Format.argsSummary("remind", .object(["text": .string("stretch"), "inMinutes": .number(0)])) == "stretch in 0 min")
		#expect(Format.argsSummary("ask_owner", .object([:])) == "")
	}

	@Test func money() {
		#expect(Format.money(0.0421) == "$0.042")
		#expect(Format.money(3.1) == "$3.10")
	}

	@Test func anAddressIsAURLOrATailnetName() {
		#expect(GaidinClient.address("gaidin.example.ts.net")?.absoluteString == "https://gaidin.example.ts.net")
		#expect(GaidinClient.address(" http://127.0.0.1:8420/ ")?.absoluteString == "http://127.0.0.1:8420")
		#expect(GaidinClient.address("ftp://x") == nil)
		#expect(GaidinClient.address("") == nil)
		let client = GaidinClient(base: GaidinClient.address("gaidin.example.ts.net")!)
		#expect(client.appEventsURL.absoluteString == "https://gaidin.example.ts.net/events?all")
		#expect(client.eventsURL(agent: "gaidin", conversation: nil).absoluteString == "https://gaidin.example.ts.net/events?agent=gaidin")
		#expect(client.eventsURL(agent: "gaidin", conversation: 39).absoluteString == "https://gaidin.example.ts.net/events?conversation=39")
	}

	@Test func colorsGoByPlaceUntilOneIsChosen() {
		let agent = { (id: String, color: String?) in Agent(id: id, name: id, job: "", home: 1, avatar: nil, color: color, archived: nil) }
		let roster = [agent("gaidin", nil), agent("verin", nil), agent("siuan", "lime")]
		#expect(AgentColor.of(roster[0], in: roster) == .ice)
		#expect(AgentColor.of(roster[1], in: roster) == .blue)
		#expect(AgentColor.of(roster[2], in: roster) == .lime)
	}
}
