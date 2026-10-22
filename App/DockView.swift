// Requests waiting on the owner, from every agent, as lines above the composer: a call to allow on the warn's wash with
// its bar where the log's hairline runs, or a question or a hand-over on the accent's. From moiraine's
// src/conversation/dock.tsx. Making a rule from a request and taking a browser over are the web app's for now.
import MoiraineCore
import SwiftUI

struct DockView: View {
	@Environment(AppModel.self) private var app
	/// The composer is there to type an answer into.
	var typed = true
	@State private var busy = false
	@State private var failed: String?

	var body: some View {
		if !app.approvals.isEmpty || failed != nil {
			VStack(alignment: .leading, spacing: 0) {
				if let failed {
					Text(failed).font(Typography.readingSmall).foregroundStyle(Palette.bad).padding(.horizontal, Space.md).padding(.vertical, Space.x2s)
				}
				ForEach(app.approvals) { request in
					card(request)
				}
			}
		}
	}

	private func attempt(_ work: @escaping () async throws -> Void) {
		failed = nil
		busy = true
		Task {
			do { try await work() } catch { failed = error.localizedDescription }
			busy = false
		}
	}

	@ViewBuilder private func card(_ request: Approval) -> some View {
		let asks = !request.isCall
		VStack(alignment: .leading, spacing: Space.xs) {
			HStack(spacing: Space.xs) {
				if let agent = app.agent(of: request) {
					Button {
						app.route = request.conversationId == agent.home ? .home(agent: agent.id) : .thread(agent: agent.id, id: request.conversationId)
					} label: {
						HStack(spacing: Space.x2s + 2) {
							AvatarView(agent: agent, size: 20)
							Text(agent.name).font(Typography.sans(Typography.sizeSm, .medium)).foregroundStyle(Palette.agent(app.color(agent)))
						}
					}
					.buttonStyle(.plain)
					.accessibilityHint(request.conversationId == agent.home ? "Opens \(agent.name)'s home conversation" : "Opens \(agent.name)'s thread")
				}
				Label(kindText(request), systemImage: request.isQuestion ? "questionmark.circle" : request.isHandover ? "macwindow" : "exclamationmark.shield")
					.font(Typography.readingSmall)
					.foregroundStyle(Palette.ink2)
					.labelStyle(.titleAndIcon)
				if request.isCall || request.isHandover {
					Text(request.isHandover ? (request.profile ?? "") : request.tool).font(Typography.code).foregroundStyle(Palette.ink)
				}
			}
			Text(request.summary).font(Typography.sans(Typography.sizeBase)).foregroundStyle(Palette.ink).textSelection(.enabled)
			if let detail = request.detail { DetailFold(detail: detail) }
			buttons(request)
			Text(waits(request)).font(Typography.meta).foregroundStyle(Palette.ink3)
		}
		.padding(.horizontal, Space.md)
		.padding(.vertical, Space.sm)
		.frame(maxWidth: .infinity, alignment: .leading)
		.background(asks ? Palette.accentWash : Palette.warnWash)
		.overlay(alignment: .leading) { Rectangle().fill(asks ? Palette.accent : Palette.warn).frame(width: 2) }
		.hairlineBelow()
	}

	private func kindText(_ request: Approval) -> String {
		request.isQuestion ? "asks" : request.isHandover ? "asks you to take over" : "wants to use"
	}

	private func waits(_ request: Approval) -> String {
		let until = "waits until \(Format.when(Format.date(request.expiresAt)))"
		return request.isQuestion && typed ? "or type your answer below · \(until)" : until
	}

	@ViewBuilder private func buttons(_ request: Approval) -> some View {
		if request.isQuestion {
			FlowButtons {
				ForEach(request.choices ?? [], id: \.self) { choice in
					Button(choice) { attempt { try await app.answer(request, choice) } }.buttonStyle(.secondary)
				}
			}
			.disabled(busy)
		} else if request.isHandover {
			FlowButtons {
				Button("Done") { attempt { try await app.decide(request, .once) } }.buttonStyle(.secondary)
				Button("Can't") { attempt { try await app.decide(request, .deny) } }.buttonStyle(.danger)
			}
			.disabled(busy)
			Text("Take it over in the web app; the iPhone app can't show a browser yet.").font(Typography.readingSmall).foregroundStyle(Palette.ink3)
		} else {
			FlowButtons {
				Button("Allow once") { attempt { try await app.decide(request, .once) } }.buttonStyle(.primary)
				if let always = request.always {
					Button(always.label) { attempt { try await app.decide(request, .always) } }.buttonStyle(.secondary)
				}
				Button("Deny") { attempt { try await app.decide(request, .deny) } }.buttonStyle(.danger)
			}
			.disabled(busy)
		}
	}
}

/// More than a line can hold, such as a diff, folded under "all of it".
private struct DetailFold: View {
	let detail: String
	@State private var open = false

	var body: some View {
		VStack(alignment: .leading, spacing: Space.x2s) {
			Button(open ? "less" : "all of it") { withAnimation(.medium) { open.toggle() } }
				.font(Typography.meta)
				.foregroundStyle(Palette.ink3)
				.buttonStyle(.plain)
			if open {
				ScrollView([.horizontal, .vertical]) {
					Text(detail).font(Typography.code).foregroundStyle(Palette.ink2).fixedSize().textSelection(.enabled).padding(Space.xs)
				}
				.frame(maxHeight: 240)
				.background(Palette.paper2, in: RoundedRectangle(cornerRadius: Radius.md))
			}
		}
	}
}

/// Buttons in a row that wraps when they don't fit.
struct FlowButtons<Content: View>: View {
	@ViewBuilder let content: Content

	var body: some View {
		FlowLayout(spacing: Space.xs) { content }
	}
}

struct FlowLayout: Layout {
	var spacing: CGFloat

	func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
		let rows = arrange(proposal.width ?? .infinity, subviews)
		return CGSize(width: proposal.width ?? rows.map(\.width).max() ?? 0, height: rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0)))
	}

	func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
		var y = bounds.minY
		for row in arrange(bounds.width, subviews) {
			var x = bounds.minX
			for index in row.indices {
				let size = subviews[index].sizeThatFits(.unspecified)
				subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
				x += size.width + spacing
			}
			y += row.height + spacing
		}
	}

	private func arrange(_ width: CGFloat, _ subviews: Subviews) -> [(indices: [Int], width: CGFloat, height: CGFloat)] {
		var rows: [(indices: [Int], width: CGFloat, height: CGFloat)] = []
		for (index, subview) in subviews.enumerated() {
			let size = subview.sizeThatFits(.unspecified)
			if let last = rows.last, last.width + spacing + size.width <= width {
				rows[rows.count - 1].indices.append(index)
				rows[rows.count - 1].width += spacing + size.width
				rows[rows.count - 1].height = max(last.height, size.height)
			} else {
				rows.append(([index], size.width, size.height))
			}
		}
		return rows
	}
}
