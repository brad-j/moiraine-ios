// The log's rows, as moiraine draws them: a gutter with who wrote the line, right-aligned in mono, then the line
// beside a hairline that runs the log's length. On a phone the gutter leaves out the time, which a row gives in its
// accessibility label instead. Tool calls and thinking fold to a line; steps in a row gather into one.
import MoiraineCore
import SwiftUI

/// What a row can do beyond showing: snooze a fired reminder.
struct RowActions {
	var snooze: (_ taskId: Int, _ minutes: Int) -> Void = { _, _ in }
}

struct LogRow: View {
	let line: LogLine
	/// The agent's color, for its name in the gutter.
	let agentColor: Color
	var actions = RowActions()
	/// Inside gathered steps: no room above, the label on the left.
	var nested = false
	@Binding var opened: Set<String>

	var body: some View {
		HStack(alignment: .firstTextBaseline, spacing: 0) {
			Text(line.label)
				.font(Typography.gutter)
				.foregroundStyle(labelColor)
				.lineLimit(1)
				.truncationMode(.tail)
				.frame(width: nested ? 72 : Metrics.gutterWho, alignment: nested ? .leading : .trailing)
				.padding(.trailing, nested ? 0 : Space.sm)
				.accessibilityLabel(accessibilityName)
			content
				.padding(.leading, nested ? 0 : Space.sm)
				.padding(.top, topPadding)
				.padding(.bottom, line.kind == .agent ? Space.xs : Space.x3s)
				.frame(maxWidth: .infinity, alignment: .leading)
				.overlay(alignment: .leading) {
					if !nested { Rectangle().fill(Palette.rule).frame(width: Metrics.hairline).padding(.top, -1) }
				}
		}
	}

	private var topPadding: CGFloat {
		if nested { return Space.x3s }
		if line.start { return Space.lg }
		return line.kind == .agent ? Space.xs : Space.x3s
	}

	private var accessibilityName: String {
		([line.label, line.fullTime.map { "at \($0)" }] as [String?]).compactMap(\.self).joined(separator: ", ")
	}

	private var labelColor: Color {
		switch line.kind {
		case .you: Palette.ink
		case .agent: agentColor
		case .prompt, .job: Palette.ok
		case .remind: Palette.warn
		case .error: Palette.bad
		case .tool:
			if case .fold(_, _, let status, _) = line.body, status?.failed == true { Palette.bad } else { Palette.ink3 }
		default: Palette.ink3
		}
	}

	@ViewBuilder private var content: some View {
		switch line.body {
		case .said(let said):
			SaidView(said: said, color: line.kind == .prompt ? Palette.ink2 : Palette.ink)
		case .answer(let text, let live):
			RevealingAnswer(id: line.id, text: text, live: live)
		case .fold(let summary, let sections, let status, let tail):
			Fold(id: line.id, summary: summary, prose: line.kind == .think || line.kind == .summary, sections: sections, status: status, tail: tail, opened: $opened)
		case .text(let text):
			Text(text)
				.font(line.kind == .error ? Typography.readingSmall : Typography.readingSmall)
				.foregroundStyle(line.kind == .error ? Palette.bad : line.kind == .stopped ? Palette.ink3 : Palette.ink2)
				.textSelection(.enabled)
		case .reminder(let text, let failure, let taskId):
			VStack(alignment: .leading, spacing: Space.x2s) {
				Text(text).font(Typography.sans(Typography.sizeBase, .medium)).foregroundStyle(Palette.warn)
				if let failure { Text(failure).font(Typography.readingSmall).foregroundStyle(Palette.bad) }
				if let taskId {
					HStack(spacing: Space.x2s) {
						Button("snooze 10 min") { actions.snooze(taskId, 10) }
						Button("1 h") { actions.snooze(taskId, 60) }
					}
					.buttonStyle(.quiet)
				}
			}
		case .job(let title, let failure):
			VStack(alignment: .leading, spacing: Space.x2s) {
				Text(title).font(Typography.sans(Typography.sizeBase, .medium)).foregroundStyle(Palette.ink)
				if let failure { Text(failure).font(Typography.readingSmall).foregroundStyle(Palette.bad) }
			}
		}
	}
}

/// A message to the agent: its text, the images that went with it, and where its other files were saved.
private struct SaidView: View {
	let said: Format.Said
	let color: Color

	var body: some View {
		VStack(alignment: .leading, spacing: Space.xs) {
			if !said.text.isEmpty {
				Text(said.text).font(Typography.reading).foregroundStyle(color).textSelection(.enabled)
			}
			ForEach(Array(said.images.enumerated()), id: \.offset) { n, image in
				if let data = Data(base64Encoded: image.data), let picture = UIImage(data: data) {
					Image(uiImage: picture)
						.resizable()
						.scaledToFit()
						.frame(maxWidth: 240, maxHeight: 200, alignment: .leading)
						.clipShape(RoundedRectangle(cornerRadius: Radius.sm))
						.overlay(RoundedRectangle(cornerRadius: Radius.sm).strokeBorder(Palette.rule2, lineWidth: Metrics.hairline))
						.accessibilityLabel("Image \(n + 1) sent with the message")
				}
			}
			ForEach(said.files, id: \.self) { file in
				Text("↳ \(file)").font(Typography.readingSmall).foregroundStyle(Palette.ink3)
			}
		}
	}
}

/// Thinking or a tool call in a line, opened for all of it. A running tool shows the end of its output unopened.
struct Fold: View {
	let id: String
	let summary: String
	/// Thinking and summaries read as prose; a tool call's arguments are mono.
	let prose: Bool
	let sections: [FoldSection]
	let status: ToolStatus?
	let tail: String?
	@Binding var opened: Set<String>

	var body: some View {
		let open = opened.contains(id)
		VStack(alignment: .leading, spacing: Space.x2s) {
			Button {
				withAnimation(.medium) {
					if open { opened.remove(id) } else { opened.insert(id) }
				}
			} label: {
				HStack(alignment: .firstTextBaseline, spacing: Space.xs) {
					Icon(.caretRight, size: 12)
						.foregroundStyle(Palette.ink3)
						.rotationEffect(.degrees(open ? 90 : 0))
					Text(summary)
						.font(prose ? Typography.readingSmall : Typography.gutter)
						.foregroundStyle(Palette.ink3)
						.lineLimit(1)
						.frame(maxWidth: .infinity, alignment: .leading)
					if let status { StatusMark(status: status) }
				}
				.frame(minHeight: 28)
				.contentShape(Rectangle())
			}
			.buttonStyle(.plain)
			.accessibilityHint(open ? "Folds it" : "Shows all of it")
			if open {
				VStack(alignment: .leading, spacing: Space.xs) {
					ForEach(Array(sections.enumerated()), id: \.offset) { _, section in
						VStack(alignment: .leading, spacing: Space.x2s) {
							if let label = section.label { Text(label).font(Typography.meta).foregroundStyle(Palette.ink3) }
							ScrollView(.horizontal, showsIndicators: false) {
								Text(section.text)
									.font(prose ? Typography.readingSmall : Typography.code)
									.foregroundStyle(Palette.ink2)
									.textSelection(.enabled)
									.fixedSize(horizontal: !prose, vertical: true)
									.frame(maxWidth: .infinity, alignment: .leading)
							}
						}
					}
				}
				.padding(Space.sm)
				.background(Palette.paper2, in: RoundedRectangle(cornerRadius: Radius.md))
			} else if let tail {
				Text(tail).font(Typography.code).foregroundStyle(Palette.ink3).lineLimit(6)
			}
		}
	}
}

/// A tool call's state: done, failed, waiting to run, or a pulsing dot while it runs.
struct StatusMark: View {
	let status: ToolStatus

	var body: some View {
		HStack(spacing: Space.x2s) {
			switch status {
			case .running: PulsingDot()
			case .done: Icon(.check, weight: .bold, size: 12)
			case .error, .noResult: Icon(.x, weight: .bold, size: 12)
			case .waiting: Icon(.hourglass, size: 12)
			}
			Text(status.rawValue).font(Typography.gutter)
		}
		.foregroundStyle(color)
		.fixedSize()
	}

	private var color: Color {
		switch status {
		case .done: Palette.ok
		case .running: Palette.accent
		case .waiting: Palette.warn
		case .error, .noResult: Palette.bad
		}
	}
}

/// The only looping animation: the running pulse on a live status dot. Reduced motion holds it still.
struct PulsingDot: View {
	var size: CGFloat = 6
	var color: Color = Palette.accent
	@Environment(\.accessibilityReduceMotion) private var reduceMotion
	@State private var dim = false

	var body: some View {
		Circle()
			.fill(color)
			.frame(width: size, height: size)
			.opacity(dim ? 0.35 : 1)
			.onAppear {
				guard !reduceMotion else { return }
				withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) { dim = true }
			}
	}
}

/// Steps in a row as one line naming them; open by itself while one is running or waiting, until the owner toggles it.
struct StepsRow: View {
	let id: String
	let lines: [LogLine]
	let agentColor: Color
	@Binding var opened: Set<String>
	/// Folded by the owner while one was live.
	@State private var closedByOwner = false

	var body: some View {
		let state = LogLines.stepsState(lines)
		let open = opened.contains(id) || (state.live != nil && !closedByOwner)
		HStack(alignment: .firstTextBaseline, spacing: 0) {
			Text("steps")
				.font(Typography.gutter)
				.foregroundStyle(state.failed > 0 ? Palette.bad : Palette.ink3)
				.frame(width: Metrics.gutterWho, alignment: .trailing)
				.padding(.trailing, Space.sm)
				.accessibilityHidden(true)
			VStack(alignment: .leading, spacing: Space.x2s) {
				Button {
					withAnimation(.medium) {
						if open {
							opened.remove(id)
							closedByOwner = true
						} else {
							opened.insert(id)
							closedByOwner = false
						}
					}
				} label: {
					HStack(alignment: .firstTextBaseline, spacing: Space.xs) {
						Icon(.caretRight, size: 12)
							.foregroundStyle(Palette.ink3)
							.rotationEffect(.degrees(open ? 90 : 0))
						Text("\(lines.count) steps").font(Typography.sans(Typography.sizeSm, .medium)).foregroundStyle(Palette.ink2)
						Text(state.names.joined(separator: ", "))
							.font(Typography.readingSmall)
							.foregroundStyle(Palette.ink3)
							.lineLimit(1)
							.frame(maxWidth: .infinity, alignment: .leading)
						if let live = state.live {
							StatusMark(status: live)
						} else {
							Text(state.failed > 0 ? "\(state.failed) failed" : "done")
								.font(Typography.gutter)
								.foregroundStyle(state.failed > 0 ? Palette.bad : Palette.ok)
						}
					}
					.frame(minHeight: 28)
					.contentShape(Rectangle())
				}
				.buttonStyle(.plain)
				if open {
					VStack(alignment: .leading, spacing: 0) {
						ForEach(lines) { line in
							LogRow(line: line, agentColor: agentColor, nested: true, opened: $opened)
						}
					}
				}
			}
			.padding(.leading, Space.sm)
			.padding(.vertical, Space.x3s)
			.frame(maxWidth: .infinity, alignment: .leading)
			.overlay(alignment: .leading) { Rectangle().fill(Palette.rule).frame(width: Metrics.hairline).padding(.top, -1) }
		}
	}
}
