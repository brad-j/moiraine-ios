// The app's state across conversations: which gaidin, the roster, what each agent is up to, the requests waiting on
// the owner, each agent's threads and the day's spend. gaidin's app-wide event stream (/events?all) says when any of
// them changed, and they're asked for again then, and when the app comes back to the front.
import MoiraineCore
import Observation
import SwiftUI

/// Where the conversation column is.
enum Route: Hashable {
	case home(agent: String)
	case thread(agent: String, id: Int)
	/// A thread about to start: it begins with the first message.
	case newThread(agent: String)

	var agent: String {
		switch self {
		case .home(let agent), .thread(let agent, _), .newThread(let agent): agent
		}
	}
}

@MainActor @Observable
final class AppModel {
	private static let serverKey = "server"
	private static let draftsKey = "drafts"

	/// gaidin's address, as the owner gave it; nil until they have.
	private(set) var server: URL?
	private(set) var client: GaidinClient?
	/// Why gaidin can't be reached, while it can't.
	private(set) var problem: GaidinError?
	/// The protocol the gaidin answering speaks, when it isn't this build's.
	private(set) var otherProtocol: Int?
	private(set) var loaded = false

	private(set) var agents: [Agent] = []
	private(set) var activity: [String: AgentActivity] = [:]
	private(set) var approvals: [Approval] = []
	private(set) var budget: Budget?
	private(set) var threads: [String: [ConversationSummary]] = [:]

	var route: Route?
	/// The prompt's text not yet sent, by conversation, kept on the device.
	private var drafts: [String: String]

	@ObservationIgnored private var appStream: Task<Void, Never>?

	init() {
		drafts = UserDefaults.standard.dictionary(forKey: Self.draftsKey) as? [String: String] ?? [:]
		if let saved = UserDefaults.standard.string(forKey: Self.serverKey), let url = URL(string: saved) { use(url) }
	}

	/// The agents shown in the rail: not archived, the default agent first.
	var roster: [Agent] { agents.filter { $0.archived == nil } }

	func agent(_ id: String) -> Agent? { agents.first { $0.id == id } }

	func color(_ agent: Agent) -> AgentColor { AgentColor.of(agent, in: agents) }

	/// The agent whose conversation asks: its own, or the default agent's when it doesn't say.
	func agent(of approval: Approval) -> Agent? {
		approval.agent.flatMap(agent) ?? agents.first
	}

	/// What waits on the owner from `agent`.
	func waiting(for agent: Agent) -> Int {
		approvals.filter { (self.agent(of: $0)?.id ?? "") == agent.id }.count
	}

	// MARK: Server

	/// Checks `typed` answers as gaidin before keeping it.
	func connect(to typed: String) async throws {
		guard let url = GaidinClient.address(typed) else { throw GaidinError(status: nil, message: "That isn't an address. Give the machine's tailnet name, like gaidin.example.ts.net.") }
		let version = try await GaidinClient(base: url).version()
		UserDefaults.standard.set(url.absoluteString, forKey: Self.serverKey)
		use(url)
		otherProtocol = version.protocolVersion == PROTOCOL ? nil : version.protocolVersion
	}

	func forgetServer() {
		UserDefaults.standard.removeObject(forKey: Self.serverKey)
		appStream?.cancel()
		appStream = nil
		server = nil
		client = nil
		agents = []
		approvals = []
		threads = [:]
		route = nil
		loaded = false
	}

	private func use(_ url: URL) {
		server = url
		client = GaidinClient(base: url)
		openAppStream()
		Task { await refresh() }
	}

	// MARK: Loading

	/// Everything again, as after the app comes back to the front.
	func refresh() async {
		guard let client else { return }
		do {
			async let version = client.version()
			async let agents = client.agents()
			async let activity = client.activity()
			async let approvals = client.approvals()
			async let budget = client.budget()
			let (v, roster) = try await (version, agents)
			otherProtocol = v.protocolVersion == PROTOCOL ? nil : v.protocolVersion
			self.agents = roster
			self.activity = Dictionary((try await activity).map { ($0.agent, $0) }, uniquingKeysWith: { _, last in last })
			self.approvals = try await approvals
			self.budget = try await budget
			problem = nil
			loaded = true
			if route == nil, let first = self.roster.first { route = .home(agent: first.id) }
			if let route { await loadThreads(route.agent) }
		} catch let error as GaidinError {
			problem = error
		} catch {
			problem = GaidinError(status: nil, message: "\(error)")
		}
	}

	func loadApprovals() async {
		guard let client, let answer = try? await client.approvals() else { return }
		approvals = answer
	}

	func loadActivity() async {
		guard let client, let answer = try? await client.activity() else { return }
		activity = Dictionary(answer.map { ($0.agent, $0) }, uniquingKeysWith: { _, last in last })
	}

	func loadBudget() async {
		guard let client, let answer = try? await client.budget() else { return }
		budget = answer
	}

	/// The agent's threads, job runs and conversations other agents started, newest first: the first page.
	func loadThreads(_ agent: String) async {
		guard let client, let page = try? await client.conversations(agent: agent) else { return }
		threads[agent] = page.items
	}

	func summary(agent: String, id: Int) -> ConversationSummary? {
		threads[agent]?.first { $0.id == id }
	}

	// MARK: Requests

	func decide(_ approval: Approval, _ decision: Decision) async throws {
		guard let client else { return }
		defer { Task { await loadApprovals() } }
		_ = try await client.decide(DecideBody(id: approval.id, decision: decision))
	}

	func answer(_ approval: Approval, _ text: String) async throws {
		guard let client else { return }
		defer { Task { await loadApprovals() } }
		_ = try await client.answer(AnswerBody(id: approval.id, answer: text))
	}

	// MARK: Drafts

	func draft(_ key: String) -> String { drafts[key] ?? "" }

	func keepDraft(_ key: String, _ text: String) {
		drafts[key] = text.isEmpty ? nil : text
		UserDefaults.standard.set(drafts, forKey: Self.draftsKey)
	}

	// MARK: The app's events

	private func openAppStream() {
		appStream?.cancel()
		guard let client else { return }
		let url = client.appEventsURL
		appStream = Task { [weak self] in
			for await update in EventStream.open(url) {
				guard let self else { return }
				switch update {
				case .connected:
					// What changed while it was closed isn't known, so everything is asked for again.
					if problem != nil || loaded { await refresh() }
				case .disconnected(let error, _):
					problem = error
				case .event(let event):
					await heard(event)
				}
			}
		}
	}

	private func heard(_ event: StreamEvent) async {
		switch event {
		case .approvalsChanged: await loadApprovals()
		case .activityChanged:
			await loadActivity()
			await loadBudget()
		case .conversationsChanged(let agent): await loadThreads(agent)
		default: break
		}
	}

	/// Back in the front: a phone suspends the app and its streams with it.
	func cameForward() {
		guard client != nil else { return }
		openAppStream()
		Task { await refresh() }
	}
}
