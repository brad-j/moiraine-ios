// One conversation, live: its event stream from gaidin kept by the transcript reducer, sending to it and stopping it,
// and the app's own notes and errors placed in its log after the entry they followed. From moiraine's
// src/conversation/stream.ts and view.tsx.
import MoiraineCore
import Observation
import SwiftUI

/// A line the app says in the log itself, after the entry it followed, until the conversation is left.
struct LocalLine: Identifiable, Hashable {
	let id: Int
	let after: Int
	let kind: LineKind
	let text: String
}

@MainActor @Observable
final class ConversationModel {
	let agent: String
	/// A thread, job run or conversation another agent started; the agent's home without it.
	let id: Int?

	private(set) var transcript = Transcript()
	private(set) var connected = false
	/// There's a transcript to show: gaidin has sent its snapshot.
	private(set) var ready = false
	private(set) var local: [LocalLine] = []
	/// Where the message went when it forked a job run or another agent's conversation.
	private(set) var movedTo: Int?

	@ObservationIgnored private let client: GaidinClient
	@ObservationIgnored private weak var app: AppModel?
	@ObservationIgnored private var stream: Task<Void, Never>?
	@ObservationIgnored private var count = 0
	@ObservationIgnored private var backgroundedAt: Date?

	init(agent: String, id: Int?, client: GaidinClient, app: AppModel) {
		self.agent = agent
		self.id = id
		self.client = client
		self.app = app
	}

	func open() {
		stream?.cancel()
		connected = false
		let url = client.eventsURL(agent: agent, conversation: id)
		stream = Task { [weak self] in
			for await update in EventStream.open(url) {
				guard let self else { return }
				self.receive(update)
			}
		}
	}

	func close() {
		stream?.cancel()
		stream = nil
	}

	/// A phone suspends the app and its stream with it: back in front, a stream that has been away long enough to
	/// have dropped without saying so is opened again at once.
	func phase(_ phase: ScenePhase) {
		switch phase {
		case .background:
			backgroundedAt = .now
		case .active:
			if !connected || (backgroundedAt.map { Date.now.timeIntervalSince($0) > 20 } ?? false) { open() }
			backgroundedAt = nil
		default:
			break
		}
	}

	private func receive(_ update: StreamUpdate) {
		switch update {
		case .connected:
			connected = true
		case .disconnected:
			connected = false
		case .event(let event):
			transcript.apply(event)
			switch event {
			case .snapshot:
				ready = true
				Task { await app?.loadApprovals() }
			case .runEnd:
				Task {
					await app?.loadBudget()
					await app?.loadThreads(agent)
				}
			case .approvalsChanged:
				Task { await app?.loadApprovals() }
			case .taskFailed(let kind, let message):
				say(.error, "\(kind) failed: \(message)")
			default:
				break
			}
		}
	}

	func say(_ kind: LineKind, _ text: String) {
		// The same error twice in a row is said once.
		if kind == .error, let last = local.last, last.kind == .error, last.text == text { return }
		count += 1
		local.append(LocalLine(id: count, after: transcript.lastEntryId, kind: kind, text: text))
	}

	/// Sends `content`. Throws, after saying why in the log, when gaidin didn't take it, so the prompt keeps the text.
	func send(_ content: String) async throws {
		do {
			let sent = try await client.message(MessageBody(content: content, agent: agent, conversation: id))
			// gaidin takes a message as the answer when the agent is waiting on a question.
			if sent.answered == true { say(.sys, "Taken as the answer to the question; the run goes on.") }
			if let id, sent.conversation != id { movedTo = sent.conversation }
		} catch {
			say(.error, error.localizedDescription)
			throw error
		}
	}

	func stop() async {
		guard transcript.running else { return say(.sys, "Nothing is running.") }
		do {
			_ = try await client.abort(AbortBody(agent: agent, conversation: id))
		} catch {
			say(.error, error.localizedDescription)
		}
	}

	func snooze(_ taskId: Int, minutes: Int) async {
		do {
			let answer = try await client.snooze(SnoozeBody(id: taskId, minutes: minutes))
			say(.sys, "Snoozed until \(Format.when(Format.date(answer.at))).")
		} catch {
			say(.error, error.localizedDescription)
		}
	}

	/// What the owner sent in this conversation, oldest first.
	var mine: (Entry) -> Bool {
		let id = id
		return { id == nil || $0.conversationId == id }
	}
}
