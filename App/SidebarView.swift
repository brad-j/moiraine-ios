// The sidebar, which on a phone is the drawer: the rail of agents, each its avatar and its name in small mono, a pulsing
// dot while it works and an amber count of what waits on the owner, the one shown marked in its color; and beside it
// the agent's column: its name and job, + thread, Home, then its threads under day groups. From moiraine's
// src/sidebar.tsx. The column's pages (Schedule, Memory, Skills, Settings) and System's are the web app's for now.
import MoiraineCore
import SwiftUI

struct SidebarView: View {
	@Environment(AppModel.self) private var app
	/// The agent whose column is shown, which may differ from the open conversation's while the owner looks around.
	@Binding var shown: String?
	let close: () -> Void

	var body: some View {
		HStack(spacing: 0) {
			Rail(shown: $shown)
			if let agent = shown.flatMap(app.agent) {
				Column(agent: agent, close: close)
			}
		}
		.background(Palette.paper2.ignoresSafeArea())
	}
}

private struct Rail: View {
	@Environment(AppModel.self) private var app
	@Binding var shown: String?

	var body: some View {
		ScrollView(showsIndicators: false) {
			VStack(spacing: Space.x2s) {
				ForEach(app.roster) { agent in
					RailAgent(agent: agent, current: agent.id == shown) {
						shown = agent.id
						Task { await app.loadThreads(agent.id) }
					}
				}
			}
			.padding(.vertical, Space.sm)
		}
		.frame(width: Metrics.rail)
		.background {
			Palette.paper0
				.overlay(alignment: .trailing) { Rectangle().fill(Palette.rule).frame(width: Metrics.hairline) }
				.ignoresSafeArea()
		}
	}
}

private struct RailAgent: View {
	@Environment(AppModel.self) private var app
	let agent: Agent
	let current: Bool
	let choose: () -> Void

	var body: some View {
		let color = Palette.agent(app.color(agent))
		let waiting = app.waiting(for: agent)
		let running = app.activity[agent.id]?.running ?? false
		Button(action: choose) {
			VStack(spacing: Space.x2s) {
				AvatarView(agent: agent, size: 36, quiet: !current)
					.padding(3)
					.overlay {
						if current { RoundedRectangle(cornerRadius: 42 * 0.28, style: .continuous).strokeBorder(color, lineWidth: 1.5) }
					}
					.overlay(alignment: .bottomTrailing) {
						if running {
							PulsingDot(size: 9).padding(2).background(Palette.paper0, in: Circle()).offset(x: 2, y: 2)
						}
					}
					.overlay(alignment: .topTrailing) {
						if waiting > 0 {
							Text("\(waiting)")
								.font(Typography.mono(10, .medium))
								.foregroundStyle(Palette.accentInk)
								.padding(.horizontal, 5)
								.frame(minWidth: 16, minHeight: 16)
								.background(Palette.warn, in: Capsule())
								.overlay(Capsule().strokeBorder(Palette.paper0, lineWidth: 2))
								.offset(x: 6, y: -5)
						}
					}
				Text(agent.name)
					.font(Typography.meta)
					.foregroundStyle(current ? color : Palette.ink3)
					.lineLimit(1)
					.padding(.horizontal, Space.x3s)
			}
			.frame(width: Metrics.rail)
			.padding(.vertical, Space.x2s)
			.overlay(alignment: .leading) {
				if current { Rectangle().fill(color).frame(width: 3) }
			}
			.contentShape(Rectangle())
		}
		.buttonStyle(.plain)
		.accessibilityLabel(([agent.name, running ? "working" : nil, waiting > 0 ? "\(waiting) waiting on you" : nil] as [String?]).compactMap(\.self).joined(separator: ", "))
		.accessibilityAddTraits(current ? .isSelected : [])
	}
}

private struct Column: View {
	@Environment(AppModel.self) private var app
	let agent: Agent
	let close: () -> Void

	var body: some View {
		let threads = app.threads[agent.id] ?? []
		VStack(alignment: .leading, spacing: 0) {
			VStack(alignment: .leading, spacing: Space.x2s) {
				HStack {
					Text(agent.name).font(Typography.sans(Typography.sizeBase, .semibold)).foregroundStyle(Palette.agent(app.color(agent)))
					Spacer()
					Button {
						go(.newThread(agent: agent.id))
					} label: {
						Text("+ thread").font(Typography.chrome)
					}
					.buttonStyle(.quiet)
					.accessibilityLabel("New thread with \(agent.name)")
				}
				if !agent.job.isEmpty {
					Text(agent.job).font(Typography.readingSmall).foregroundStyle(Palette.ink3).lineLimit(2)
				}
			}
			.padding(.horizontal, Space.md)
			.padding(.top, Space.md)
			.padding(.bottom, Space.sm)
			.hairlineBelow()
			ScrollView {
				LazyVStack(alignment: .leading, spacing: 0) {
					ThreadRow(title: "Home", detail: homeDetail, began: nil, at: nil, current: app.route == .home(agent: agent.id)) {
						go(.home(agent: agent.id))
					}
					ForEach(groups(threads), id: \.name) { group in
						Text(group.name)
							.font(Typography.meta)
							.foregroundStyle(Palette.ink3)
							.padding(.horizontal, Space.md)
							.padding(.top, Space.md)
							.padding(.bottom, Space.x2s)
						ForEach(group.items) { thread in
							ThreadRow(title: Format.oneLine(thread.title).isEmpty ? "(no message)" : Format.oneLine(thread.title), detail: nil, began: thread.began, at: thread.lastAt, current: app.route == .thread(agent: agent.id, id: thread.id)) {
								go(.thread(agent: agent.id, id: thread.id))
							}
						}
					}
				}
				.padding(.vertical, Space.xs)
			}
			Spacer(minLength: 0)
			ServerFoot()
		}
		.frame(maxWidth: .infinity)
		.background(Palette.paper2)
	}

	/// The home conversation's newest message, under Home.
	private var homeDetail: String? {
		guard let last = app.activity[agent.id]?.last, last.place == "main" else { return nil }
		return Format.oneLine(last.text)
	}

	private func go(_ route: Route) {
		app.route = route
		close()
	}

	private func groups(_ threads: [ConversationSummary]) -> [(name: String, items: [ConversationSummary])] {
		let names = ["today", "this week", "older"]
		let grouped = Dictionary(grouping: threads) { Format.ageGroup(Format.date($0.lastAt ?? $0.startedAt ?? 0)) }
		return names.compactMap { name in grouped[name].map { (name, $0) } }
	}
}

private struct ThreadRow: View {
	let title: String
	let detail: String?
	/// Where it began, for a thread.
	let began: String?
	let at: Double?
	let current: Bool
	let open: () -> Void

	var body: some View {
		Button(action: open) {
			VStack(alignment: .leading, spacing: Space.x3s) {
				HStack(spacing: Space.xs) {
					Text(title).font(Typography.sans(Typography.sizeSm, current ? .medium : .regular)).foregroundStyle(current ? Palette.ink : Palette.ink2).lineLimit(1)
					Spacer(minLength: 0)
					if let at { Text(Format.lastSeen(Format.date(at))).font(Typography.meta).foregroundStyle(Palette.ink3) }
				}
				if let began {
					IconLabel(Places.label(began), icon: Places.icon(began), size: 12, spacing: Space.x2s)
						.font(Typography.meta)
						.foregroundStyle(began == "job" ? Palette.ok : began == "agent" ? Palette.warn : Palette.ink3)
				} else if let detail, !detail.isEmpty {
					Text(detail).font(Typography.meta).foregroundStyle(Palette.ink3).lineLimit(1)
				}
			}
			.padding(.horizontal, Space.sm)
			.padding(.vertical, Space.xs)
			.frame(maxWidth: .infinity, alignment: .leading)
			.background(current ? Palette.paper4 : .clear, in: RoundedRectangle(cornerRadius: Radius.sm))
			.padding(.horizontal, Space.xs)
			.contentShape(Rectangle())
		}
		.buttonStyle(.plain)
		.accessibilityAddTraits(current ? .isSelected : [])
	}
}

/// The machine the app talks to, and changing it.
private struct ServerFoot: View {
	@Environment(AppModel.self) private var app
	@State private var confirming = false

	var body: some View {
		HStack(spacing: Space.xs) {
			Circle().fill(app.problem == nil ? Palette.ok : Palette.warn).frame(width: 6, height: 6)
			Text(app.server?.host() ?? "").font(Typography.meta).foregroundStyle(Palette.ink3).lineLimit(1).truncationMode(.middle)
			Spacer(minLength: 0)
			Button(confirming ? "Sure?" : "Change") {
				if confirming {
					app.forgetServer()
				} else {
					confirming = true
					Task {
						try? await Task.sleep(for: .seconds(4))
						confirming = false
					}
				}
			}
			.font(Typography.meta)
			.buttonStyle(.quiet)
		}
		.padding(.horizontal, Space.md)
		.padding(.vertical, Space.xs)
		.hairlineAbove()
	}
}
