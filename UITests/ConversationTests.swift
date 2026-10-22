// The app against gaidin's faux server (scripts/dev-faux.ts, which scripts/e2e.sh starts): a scripted model that
// answers "Hello, Brad.", asks before fetching for "fetch", and asks a question for "ask". The server's conversation
// carries on from test to test, so each counts what it waits for rather than expecting a fresh log.
import XCTest

final class ConversationTests: XCTestCase {
	private var app: XCUIApplication!

	override func setUp() {
		continueAfterFailure = false
		app = XCUIApplication()
		app.launchArguments = ["-server", ProcessInfo.processInfo.environment["MOIRAINE_SERVER"] ?? "http://127.0.0.1:8420"]
		app.launch()
	}

	private func texts(_ text: String) -> XCUIElementQuery {
		app.staticTexts.matching(NSPredicate(format: "label == %@", text))
	}

	private func send(_ text: String) {
		let composer = app.textViews["composer"].exists ? app.textViews["composer"] : app.textFields["composer"]
		XCTAssertTrue(composer.waitForExistence(timeout: 10))
		composer.tap()
		composer.typeText(text)
		app.buttons["Send"].tap()
	}

	/// Waits until `query` has more than `count` matches.
	private func more(_ query: XCUIElementQuery, than count: Int, timeout: TimeInterval = 15) -> Bool {
		let grown = NSPredicate { _, _ in query.count > count }
		return XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: grown, object: nil)], timeout: timeout) == .completed
	}

	func testAMessageIsAnswered() {
		XCTAssertTrue(app.staticTexts["gaidin"].waitForExistence(timeout: 10))
		let answers = texts("Hello, Brad.")
		let before = answers.count
		send("hi there")
		XCTAssertTrue(more(texts("hi there"), than: 0))
		XCTAssertTrue(more(answers, than: before), "the answer didn't come")
	}

	func testACallIsAllowedFromTheDock() {
		let answers = texts("The page says: page text.")
		let before = answers.count
		send("fetch the page")
		let allow = app.buttons["Allow once"]
		XCTAssertTrue(allow.waitForExistence(timeout: 15), "nothing asked to be allowed")
		XCTAssertTrue(app.buttons["Always allow site.test"].exists)
		allow.tap()
		XCTAssertTrue(more(answers, than: before), "the fetch's answer didn't come")
		XCTAssertFalse(app.buttons["Allow once"].waitForExistence(timeout: 2), "the card stayed in the dock")
	}

	func testAQuestionIsAnsweredWithItsChoice() {
		send("ask me something")
		let yes = app.buttons["Yes"]
		XCTAssertTrue(yes.waitForExistence(timeout: 15), "no question came")
		XCTAssertTrue(app.buttons["No"].exists)
		yes.tap()
		XCTAssertFalse(app.buttons["Yes"].waitForExistence(timeout: 3), "the question stayed in the dock")
	}

	func testANewThreadStartsFromTheSidebar() {
		app.buttons["Agents and threads"].tap()
		let new = app.buttons["New thread with gaidin"]
		XCTAssertTrue(new.waitForExistence(timeout: 5))
		new.tap()
		XCTAssertTrue(app.staticTexts["New thread"].waitForExistence(timeout: 5))
		let title = "a thread of its own \(Int.random(in: 1000...9999))"
		send(title)
		// The thread opens, titled by its first message, with the answer in it.
		XCTAssertTrue(more(texts(title), than: 0, timeout: 15))
		XCTAssertTrue(texts("app").firstMatch.waitForExistence(timeout: 5), "the header has no origin tag")
		XCTAssertTrue(more(texts("Hello, Brad."), than: 0))
		// And it's in the sidebar.
		app.buttons["Agents and threads"].tap()
		XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", title)).firstMatch.waitForExistence(timeout: 5))
	}

	func testTheSidebarShowsTheAgentAndItsThreads() {
		XCTAssertTrue(app.buttons["Agents and threads"].waitForExistence(timeout: 10))
		app.buttons["Agents and threads"].tap()
		XCTAssertTrue(app.buttons["New thread with gaidin"].waitForExistence(timeout: 5))
		XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Home")).firstMatch.exists)
		XCTAssertTrue(app.staticTexts["127.0.0.1"].exists, "the foot doesn't name the machine")
		let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
		shot.name = "sidebar"
		shot.lifetime = .keepAlways
		add(shot)
		// A tap on the scrim closes it.
		app.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
		XCTAssertTrue(app.buttons["New thread with gaidin"].waitForNonExistence(timeout: 3))
	}
}
