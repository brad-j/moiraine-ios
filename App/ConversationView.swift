// A conversation: an agent's home, one of its threads, or a thread about to start. A header naming it, the log, and at
// its foot the dock and the composer with the status line under it. On a phone the composer is a field across the
// screen with Send on a row of its own under it. From moiraine's src/conversation/view.tsx.
import MoiraineCore
import SwiftUI

struct ConversationScreen: View {
	@Environment(AppModel.self) private var app
	@Environment(\.scenePhase) private var scenePhase
	let agent: Agent
	let id: Int?
	/// Opens the sidebar.
	let menu: () -> Void
	@State private var model: ConversationModel?
	@State private var detail: ConversationSummary?

	var body: some View {
		VStack(spacing: 0) {
			ConversationHeader(agent: agent, summary: id == nil ? nil : summary, menu: menu)
			if let model {
				ConversationLog(model: model, agent: agent, summary: summary)
					.safeAreaInset(edge: .bottom, spacing: 0) {
						VStack(spacing: 0) {
							DockView()
							Composer(
								draftKey: id.map { "\(agent.id):t:\($0)" } ?? "\(agent.id):home",
								placeholder: placeholder,
								running: model.transcript.running,
								send: { try await model.send($0) },
								stop: { Task { await model.stop() } }
							) {
								StatusLine(model: model)
							}
						}
						.background(Palette.paper)
					}
			} else {
				Spacer()
			}
		}
		.background(Palette.paper)
		.task(id: TaskKey(agent: agent.id, id: id, client: app.client?.base)) {
			guard let client = app.client else { return }
			model?.close()
			let opened = ConversationModel(agent: agent.id, id: id, client: client, app: app)
			model = opened
			opened.open()
			if let id, app.summary(agent: agent.id, id: id) == nil { detail = try? await client.conversation(id).conversation }
		}
		.onDisappear { model?.close() }
		.onChange(of: scenePhase) { _, phase in model?.phase(phase) }
		.onChange(of: model?.movedTo) { _, moved in
			// A job run or another agent's conversation forked, and the message went to the fork.
			if let moved {
				Task { await app.loadThreads(agent.id) }
				app.route = .thread(agent: agent.id, id: moved)
			}
		}
	}

	private struct TaskKey: Hashable {
		let agent: String
		let id: Int?
		let client: URL?
	}

	private var summary: ConversationSummary? {
		id.flatMap { app.summary(agent: agent.id, id: $0) } ?? detail
	}

	private var placeholder: String {
		if app.approvals.contains(where: { $0.isQuestion && $0.conversationId == (id ?? agent.home) }) { return "Answer \(agent.name), or message it" }
		// gaidin posts what's sent here in the Slack thread too, then the answer.
		if summary?.began == "slack" { return "Message \(agent.name); it's posted in the Slack thread too" }
		return "Message \(agent.name)"
	}
}

/// A thread with `agent` that starts when the first message is sent: its home settings and memory, none of its history.
struct NewThreadScreen: View {
	@Environment(AppModel.self) private var app
	let agent: Agent
	let menu: () -> Void
	@State private var problem: String?

	var body: some View {
		VStack(spacing: 0) {
			HeaderBar(menu: menu) {
				Text("New thread").font(Typography.title).foregroundStyle(Palette.ink)
				AgentTag(agent: agent)
			}
			ScrollView {
				VStack(alignment: .leading, spacing: 0) {
					LogRow(line: LogLine(id: "about", kind: .sys, label: agent.name, body: .text("A thread of its own: \(agent.name)'s settings and memory, none of its home conversation's history.")), agentColor: Palette.agent(app.color(agent)), opened: .constant([]))
					if let problem {
						LogRow(line: LogLine(id: "problem", kind: .error, label: "error", body: .text(problem)), agentColor: Palette.bad, opened: .constant([]))
					}
				}
				.padding(.vertical, Space.sm)
				.padding(.trailing, Space.md)
			}
			.safeAreaInset(edge: .bottom, spacing: 0) {
				VStack(spacing: 0) {
					DockView(typed: false)
					Composer(draftKey: "\(agent.id):new", placeholder: "Start a thread with \(agent.name)", running: false, send: start, stop: {}) {
						Text("new thread").font(Typography.meta).foregroundStyle(Palette.ink3)
					}
				}
				.background(Palette.paper)
			}
		}
		.background(Palette.paper)
		// No conversation is open here to say when the requests change, so the dock asks again often.
		.task {
			while !Task.isCancelled {
				await app.loadApprovals()
				try? await Task.sleep(for: .seconds(5))
			}
		}
	}

	private func start(_ content: String) async throws {
		guard let client = app.client else { return }
		problem = nil
		do {
			let started = try await client.startThread(ThreadBody(content: content, agent: agent.id))
			await app.loadThreads(agent.id)
			app.route = .thread(agent: agent.id, id: started.conversation)
		} catch {
			problem = error.localizedDescription
			throw error
		}
	}
}

// MARK: - The header

struct HeaderBar<Content: View>: View {
	let menu: () -> Void
	@ViewBuilder let content: Content

	var body: some View {
		HStack(spacing: Space.xs) {
			Button(action: menu) {
				Icon(.list, size: 20).foregroundStyle(Palette.ink2).frame(width: 44, height: 44)
			}
			.accessibilityLabel("Agents and threads")
			content
			Spacer(minLength: 0)
		}
		.padding(.trailing, Space.md)
		.frame(minHeight: 52)
		.hairlineBelow()
	}
}

private struct ConversationHeader: View {
	@Environment(AppModel.self) private var app
	let agent: Agent
	let summary: ConversationSummary?
	let menu: () -> Void
	let home: Bool

	init(agent: Agent, summary: ConversationSummary?, menu: @escaping () -> Void) {
		self.agent = agent
		self.summary = summary
		self.menu = menu
		home = summary == nil
	}

	var body: some View {
		HeaderBar(menu: menu) {
			if let summary {
				Text(summary.title.isEmpty ? "(no message)" : Format.oneLine(summary.title))
					.font(Typography.title)
					.foregroundStyle(Palette.ink)
					.lineLimit(1)
				Spacer(minLength: 0)
				Tag(text: Places.label(summary.began))
			} else {
				AvatarView(agent: agent, size: 24)
				Text(agent.name).font(Typography.title).foregroundStyle(Palette.ink).lineLimit(1)
				Tag(text: "home")
			}
		}
	}
}

/// Whose conversation it is: the agent's picture and name.
struct AgentTag: View {
	@Environment(AppModel.self) private var app
	let agent: Agent

	var body: some View {
		HStack(spacing: Space.x2s) {
			AvatarView(agent: agent, size: 16)
			Text(agent.name).font(Typography.meta).foregroundStyle(Palette.agent(app.color(agent)))
		}
		.padding(.horizontal, Space.x2s + 1)
		.padding(.vertical, Space.x3s)
		.overlay(RoundedRectangle(cornerRadius: Radius.sm).strokeBorder(Palette.rule2, lineWidth: Metrics.hairline))
	}
}

/// Where a conversation began, as its label says.
enum Places {
	static func label(_ began: String) -> String {
		switch began {
		case "slack": "Slack"
		case "app": "app"
		case "voice": "speaker"
		case "job": "job run"
		case "agent": "from an agent"
		default: began
		}
	}

	static func icon(_ began: String) -> Ph {
		switch began {
		case "slack": .slackLogo
		case "voice": .speakerHigh
		case "job": .clock
		case "agent": .robot
		default: .chatCircle
		}
	}
}

// MARK: - The log

private struct ConversationLog: View {
	@Environment(AppModel.self) private var app
	let model: ConversationModel
	let agent: Agent
	let summary: ConversationSummary?
	@State private var opened: Set<String> = []
	@State private var ledger = RevealLedger()
	@State private var position = ScrollPosition(edge: .bottom)
	@State private var atEnd = true
	/// The owner's finger is on the log, or it's still moving from one: only then does it leave the end or come back.
	@State private var scrolling = false

	var body: some View {
		let options = LogOptions(speaker: agent.name, prompts: summary?.place == "job" ? "job" : summary?.place == "agent" ? "agent" : nil)
		let lines = LogLines.lines(model.transcript, include: model.mine, options: options, live: true)
		let items = LogLines.items(merge(lines, model.local))
		let color = Palette.agent(app.color(agent))
		ScrollView {
			LazyVStack(alignment: .leading, spacing: 0) {
				if let forkedAt = summary?.forkedAt, model.transcript.entries[forkedAt] != nil {
					InReplyTo(model: model, forkedAt: forkedAt, options: options, color: color)
				}
				if model.ready, items.isEmpty {
					LogRow(line: LogLine(id: "empty", kind: .sys, label: agent.name, body: .text(model.id == nil ? "No messages yet." : "Nothing in it yet.")), agentColor: color, opened: $opened)
				}
				ForEach(items) { item in
					switch item {
					case .line(let line):
						LogRow(line: line, agentColor: color, actions: RowActions(snooze: { id, minutes in Task { await model.snooze(id, minutes: minutes) } }), opened: $opened)
					case .steps(let id, let steps):
						StepsRow(id: id, lines: steps, agentColor: color, opened: $opened)
					}
				}
			}
			.padding(.top, Space.sm)
			.padding(.bottom, Space.md)
			.padding(.trailing, Space.md)
		}
		.environment(\.revealLedger, ledger)
		.scrollPosition($position)
		.defaultScrollAnchor(.bottom, for: .initialOffset)
		.scrollDismissesKeyboard(.interactively)
		.onScrollPhaseChange { _, phase in
			scrolling = phase == .interacting || phase == .decelerating
		}
		// Kept at its end while it's there, as a terminal does: an answer growing, a fold opening or a card in the dock
		// taking room keeps the end in sight. Scrolled up, new rows show the jump button instead.
		.onScrollGeometryChange(for: ScrollPlace.self) { geometry in
			let distance = geometry.contentSize.height + geometry.contentInsets.bottom - geometry.contentOffset.y - geometry.containerSize.height
			return ScrollPlace(nearEnd: distance < 48, height: geometry.contentSize.height, container: geometry.containerSize.height)
		} action: { old, now in
			if scrolling {
				atEnd = now.nearEnd
			} else if atEnd, now.height != old.height || now.container != old.container {
				position.scrollTo(edge: .bottom)
			} else if now.nearEnd {
				atEnd = true
			}
		}
		.onChange(of: model.transcript) { _, _ in
			if atEnd { position.scrollTo(edge: .bottom) }
		}
		.onChange(of: model.ready) { _, ready in
			// What was there when the log opened shows whole; only what arrives after is revealed.
			if ready { ledger.prime(lines.compactMap { if case .answer(let text, _) = $0.body { ($0.id, text.count) } else { nil } }) }
			position.scrollTo(edge: .bottom)
		}
		.overlay(alignment: .bottomTrailing) {
			if !atEnd {
				Button {
					atEnd = true
					withAnimation(.medium) { position.scrollTo(edge: .bottom) }
				} label: {
					IconLabel("new activity", icon: .arrowDown, size: 12).font(Typography.meta)
				}
				.buttonStyle(.secondary)
				.background(Palette.paper2, in: RoundedRectangle(cornerRadius: Radius.sm))
				.padding(Space.md)
				.transition(.opacity.combined(with: .offset(y: 6)))
			}
		}
		.animation(.medium, value: atEnd)
	}

	private struct ScrollPlace: Equatable {
		var nearEnd: Bool
		var height: CGFloat
		var container: CGFloat
	}

	/// The app's own lines placed after the entry they followed.
	private func merge(_ lines: [LogLine], _ local: [LocalLine]) -> [LogLine] {
		guard !local.isEmpty else { return lines }
		var out: [LogLine] = []
		var pending = local[...]
		let afterOf = { (line: LogLine) -> Int in Int(line.id.prefix { $0.isNumber }) ?? Int.max }
		for line in lines {
			let entry = afterOf(line)
			while let next = pending.first, entry != Int.max, next.after < entry {
				out.append(localLine(next))
				pending = pending.dropFirst()
			}
			out.append(line)
		}
		out.append(contentsOf: pending.map(localLine))
		return out
	}

	private func localLine(_ line: LocalLine) -> LogLine {
		LogLine(id: "local:\(line.id)", kind: line.kind, label: line.kind == .error ? "error" : "sys", body: .text(line.text))
	}
}

/// A thread's first line: the home conversation's entry it forked at.
private struct InReplyTo: View {
	let model: ConversationModel
	let forkedAt: Int
	let options: LogOptions
	let color: Color

	var body: some View {
		VStack(alignment: .leading, spacing: Space.x2s) {
			Text("in reply to").font(Typography.meta).foregroundStyle(Palette.ink3).padding(.leading, Metrics.gutterWho + Space.sm * 2)
			ForEach(LogLines.lines(model.transcript, include: { $0.id == forkedAt }, options: options, live: false)) { line in
				LogRow(line: line, agentColor: color, opened: .constant([]))
			}
		}
		.opacity(0.75)
		.padding(.bottom, Space.sm)
	}
}

// MARK: - The composer

/// The owner's next line: a field across the screen, two lines tall to start, and Send on a row of its own under it,
/// with the status line under that. What's typed and not sent is kept for the conversation.
struct Composer<Status: View>: View {
	@Environment(AppModel.self) private var app
	let draftKey: String
	let placeholder: String
	let running: Bool
	let send: (String) async throws -> Void
	let stop: () -> Void
	@ViewBuilder let status: Status
	@State private var text = ""
	@State private var sending = false
	@FocusState private var focused: Bool

	var body: some View {
		VStack(alignment: .leading, spacing: Space.xs) {
			TextField(placeholder, text: $text, axis: .vertical)
				.font(Typography.reading)
				.foregroundStyle(Palette.ink)
				.tint(Palette.accent)
				.lineLimit(2...8)
				.focused($focused)
				.accessibilityIdentifier("composer")
				.padding(.horizontal, Space.sm)
				.padding(.vertical, Space.xs + 2)
				.background(Palette.paper2, in: RoundedRectangle(cornerRadius: Radius.md))
				.overlay(RoundedRectangle(cornerRadius: Radius.md).strokeBorder(focused ? Palette.accent : Palette.rule2, lineWidth: Metrics.hairline))
				.animation(.short, value: focused)
			if running, text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
				Button(action: stop) {
					IconLabel("Stop", icon: .stop, weight: .fill).frame(maxWidth: .infinity, minHeight: 44)
				}
				.buttonStyle(VoiceButtonStyle(voice: .danger, wide: true))
				.overlay(RoundedRectangle(cornerRadius: Radius.sm).strokeBorder(Palette.bad.opacity(0.5), lineWidth: Metrics.hairline))
			} else {
				Button {
					submit()
				} label: {
					IconLabel("Send", icon: .paperPlaneRight, weight: .fill).frame(maxWidth: .infinity, minHeight: 44)
				}
				.buttonStyle(VoiceButtonStyle(voice: .primary, wide: true))
				.disabled(sending || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
			}
			HStack(spacing: Space.sm) { status }
				.font(Typography.meta)
				.frame(maxWidth: .infinity, alignment: .leading)
				.frame(minHeight: 18)
		}
		.padding(.horizontal, Space.md)
		.padding(.top, Space.sm)
		.padding(.bottom, Space.xs)
		.hairlineAbove()
		.onAppear { text = app.draft(draftKey) }
		.onChange(of: draftKey) { _, key in text = app.draft(key) }
		.onChange(of: text) { _, now in app.keepDraft(draftKey, now) }
	}

	private func submit() {
		let content = text.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !content.isEmpty, !sending else { return }
		sending = true
		text = ""
		Task {
			do {
				try await send(content)
			} catch {
				// gaidin didn't take it: the text comes back, unless something new was typed meanwhile.
				if text.isEmpty { text = content }
			}
			sending = false
		}
	}
}

extension View {
	func hairlineAbove(_ color: Color = Palette.rule) -> some View {
		overlay(alignment: .top) { Rectangle().fill(color).frame(height: Metrics.hairline) }
	}
}

/// Only what's worth a glance: the state when it isn't idle, the model, the thinking level when it's on, and the day's
/// spend against its limit, in warn from 80% and bad when stopped.
private struct StatusLine: View {
	@Environment(AppModel.self) private var app
	let model: ConversationModel

	var body: some View {
		let transcript = model.transcript
		if !model.connected, model.ready || app.problem != nil {
			Text("reconnecting").foregroundStyle(Palette.warn)
		} else if let retry = transcript.retry {
			Text(retry).foregroundStyle(Palette.warn).lineLimit(1)
		} else if transcript.running {
			HStack(spacing: Space.x2s) {
				PulsingDot()
				Text("working")
			}
			.foregroundStyle(Palette.accent)
		}
		if let modelId = transcript.agent?.model?.modelId { Text(modelId).foregroundStyle(Palette.ink3).lineLimit(1) }
		if let thinking = transcript.agent?.thinkingLevel, thinking != "off" { Text("thinking \(thinking)").foregroundStyle(Palette.ink3) }
		Spacer(minLength: 0)
		if let budget = app.budget {
			let near = !budget.stopped && budget.dailyLimit > 0 && budget.today >= budget.dailyLimit * 0.8
			Text(budget.stopped ? "stopped · \(spend(budget))" : spend(budget))
				.foregroundStyle(budget.stopped ? Palette.bad : near ? Palette.warn : Palette.ink3)
				.lineLimit(1)
		}
	}

	private func spend(_ budget: Budget) -> String {
		budget.dailyLimit > 0 ? "\(Format.money(budget.today)) of \(Format.money(budget.dailyLimit)) today" : "\(Format.money(budget.today)) today"
	}
}
