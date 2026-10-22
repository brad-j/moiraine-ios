// Model output as Markdown, drawn as SwiftUI views: MoiraineCore's block parser, and Foundation's inline parser for
// bold, italics, code and links. Nothing in an answer is read as markup beyond that, and a link opens only when it's
// http or https. Adapted from amyrlin's MarkdownView for UIKit and moiraine's look.
import MoiraineCore
import SwiftUI
import UIKit

/// `writing` while the answer is still coming: what's shown is settled first (`Markdown.settled`), so marks left open at
/// the end wait for their close, and a still accent caret marks where it's being written.
struct MarkdownView: View {
	let source: String
	var writing = false

	var body: some View {
		let blocks = Markdown.blocks(writing ? Markdown.settled(source) : source)
		VStack(alignment: .leading, spacing: Space.sm) {
			ForEach(Array(blocks.enumerated()), id: \.offset) { index, block in
				// Equatable, so finished blocks above the one being written aren't laid out again each frame.
				BlockView(block: block, caret: writing && index == blocks.count - 1).equatable()
			}
			if writing, blocks.isEmpty { Caret() }
		}
		.frame(maxWidth: .infinity, alignment: .leading)
		.environment(\.openURL, OpenURLAction { url in
			["http", "https"].contains(url.scheme?.lowercased() ?? "") ? .systemAction : .discarded
		})
	}
}

/// The still accent caret where an answer is being written.
struct Caret: View {
	var body: some View {
		Rectangle().fill(Palette.accent).frame(width: 7, height: Typography.sizeMd + 2).accessibilityHidden(true)
	}
}

private struct BlockView: View, Equatable {
	let block: MarkdownBlock
	/// The answer is being written at this block's end.
	var caret = false

	var body: some View {
		switch block {
		case .paragraph(let text):
			Inline(text, caret: caret)
		case .heading(let level, let text):
			Text(Inline.attributed(text, strong: Typography.heading(level)) + (caret ? Inline.caretText : AttributedString()))
				.font(Typography.heading(level))
				.foregroundStyle(Palette.ink)
				.padding(.top, level <= 2 ? Space.xs : Space.x2s)
				.textSelection(.enabled)
		case .list(let items):
			VStack(alignment: .leading, spacing: Space.x2s + 2) {
				ForEach(Array(items.enumerated()), id: \.offset) { index, item in
					HStack(alignment: .firstTextBaseline, spacing: Space.xs) {
						marker(item).frame(minWidth: 14, alignment: .trailing)
						Inline(item.text, caret: caret && index == items.count - 1)
					}
					.padding(.leading, CGFloat(item.depth) * 18)
				}
			}
		case .code(let language, let code, let closed):
			CodeBlock(language: language, code: code, copyable: closed || !caret)
		case .quote(let text):
			HStack(alignment: .top, spacing: Space.sm) {
				Rectangle().fill(Palette.rule2).frame(width: 2)
				Inline(text, color: Palette.ink2, caret: caret)
			}
			.fixedSize(horizontal: false, vertical: true)
		case .table(let header, let rows):
			TableBlock(header: header, rows: rows)
		case .rule:
			Rectangle().fill(Palette.rule).frame(height: Metrics.hairline).padding(.vertical, Space.x2s)
		}
	}

	@ViewBuilder private func marker(_ item: MarkdownBlock.ListItem) -> some View {
		if let checked = item.checked {
			Icon(checked ? .checkSquare : .square, size: 14)
				.foregroundStyle(checked ? Palette.ok : Palette.ink3)
				.accessibilityLabel(checked ? "Done" : "Not done")
		} else if let number = item.number {
			Text("\(number).").font(Typography.code).foregroundStyle(Palette.ink3).monospacedDigit()
		} else {
			Text(item.depth == 0 ? "•" : "◦").font(Typography.reading).foregroundStyle(Palette.ink3)
		}
	}
}

/// A paragraph's inline Markdown: bold, italics, links, and `code` in mono.
private struct Inline: View {
	let text: String
	var color: Color = Palette.ink
	var caret = false

	init(_ text: String, color: Color = Palette.ink, caret: Bool = false) {
		self.text = text
		self.color = color
		self.caret = caret
	}

	var body: some View {
		Text(Self.attributed(text) + (caret ? Self.caretText : AttributedString()))
			.font(Typography.reading)
			.foregroundStyle(color)
			.lineSpacing(Typography.readingLineSpacing / 2)
			.textSelection(.enabled)
			.fixedSize(horizontal: false, vertical: true)
			.tint(Palette.accent)
	}

	/// The caret as the text's last character, so it sits where the words end.
	static var caretText: AttributedString {
		var caret = AttributedString("\u{2009}▌")
		caret.foregroundColor = Palette.accent
		return caret
	}

	/// `strong` is the font for **bold**, Fira Sans's semibold rather than a synthesized bold.
	static func attributed(_ text: String, strong: Font = Typography.readingStrong) -> AttributedString {
		let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
		var attributed = (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
		for run in attributed.runs {
			let intent = run.inlinePresentationIntent ?? []
			if intent.contains(.code) {
				attributed[run.range].font = Typography.inlineCode
				attributed[run.range].foregroundColor = Palette.ink
				attributed[run.range].backgroundColor = Palette.paper3
			} else if intent.contains(.stronglyEmphasized) {
				attributed[run.range].font = strong
			} else if intent.contains(.emphasized) {
				attributed[run.range].font = Typography.readingItalic
			}
			if run.link != nil { attributed[run.range].underlineStyle = .single }
		}
		return attributed
	}
}

/// A code block, with a quiet Copy in its top-right corner once it's written, which says Copied for 1.5 seconds after.
private struct CodeBlock: View {
	let language: String?
	let code: String
	var copyable = true
	@State private var copied = false

	var body: some View {
		VStack(alignment: .leading, spacing: 0) {
			HStack {
				Text(language ?? "code").font(Typography.meta).foregroundStyle(Palette.ink3)
				Spacer()
				if copyable {
					Button {
						UIPasteboard.general.string = code
						copied = true
						Task {
							try? await Task.sleep(for: .seconds(1.5))
							copied = false
						}
					} label: {
						IconLabel(copied ? "Copied" : "Copy", icon: copied ? .check : .copy, size: 12, spacing: Space.x2s)
							.font(Typography.meta)
							.foregroundStyle(copied ? Palette.ok : Palette.ink3)
					}
					.buttonStyle(.plain)
				}
			}
			.padding(.horizontal, Space.sm)
			.frame(minHeight: 30)
			Rectangle().fill(Palette.rule).frame(height: Metrics.hairline)
			ScrollView(.horizontal, showsIndicators: false) {
				Text(code)
					.font(Typography.code)
					.foregroundStyle(Palette.ink)
					.lineSpacing(3)
					.textSelection(.enabled)
					.fixedSize()
					.padding(Space.sm)
			}
		}
		.background(Palette.paper2, in: RoundedRectangle(cornerRadius: Radius.md))
		.overlay(RoundedRectangle(cornerRadius: Radius.md).strokeBorder(Palette.rule, lineWidth: Metrics.hairline))
	}
}

/// A table, which scrolls sideways when it's wider than the log.
private struct TableBlock: View {
	let header: [String]
	let rows: [[String]]

	var body: some View {
		ScrollView(.horizontal, showsIndicators: false) {
			Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 7) {
				GridRow {
					ForEach(Array(header.enumerated()), id: \.offset) { _, cell in
						Text(Inline.attributed(cell, strong: Typography.readingSmallStrong)).font(Typography.readingSmallStrong).foregroundStyle(Palette.ink2)
					}
				}
				Rectangle().fill(Palette.rule).frame(height: Metrics.hairline).gridCellUnsizedAxes(.horizontal)
				ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
					GridRow {
						ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
							Text(Inline.attributed(cell, strong: Typography.readingSmallStrong)).font(Typography.readingSmall).foregroundStyle(Palette.ink)
						}
					}
				}
			}
			.textSelection(.enabled)
			.padding(Space.sm)
		}
		.background(Palette.paper2, in: RoundedRectangle(cornerRadius: Radius.md))
		.overlay(RoundedRectangle(cornerRadius: Radius.md).strokeBorder(Palette.rule, lineWidth: Metrics.hairline))
	}
}

/// Reveals an answer still coming at RevealPace, a word at a time, rather than in the bursts gaidin sends. An answer
/// that was already there when the log opened shows whole.
struct RevealingAnswer: View {
	let id: String
	let text: String
	let live: Bool
	@Environment(\.revealLedger) private var ledger
	@Environment(\.accessibilityReduceMotion) private var reduceMotion
	@State private var clock = RevealClock()
	/// The reveal has caught up with an answer that's done, so the timeline can stop.
	@State private var done = false

	var body: some View {
		if reduceMotion {
			MarkdownView(source: text, writing: live)
		} else {
			TimelineView(.animation(paused: done)) { context in
				let shown = clock.advance(id: id, length: text.count, ledger: ledger, at: context.date)
				let writing = live || shown < text.count
				MarkdownView(source: writing ? Self.wordCut(text, shown) : text, writing: writing)
					.onChange(of: writing, initial: true) { _, now in done = !now }
			}
		}
	}

	/// `text`'s first `count` characters, back to the end of the last whole word.
	static func wordCut(_ text: String, _ count: Int) -> String {
		guard count < text.count else { return text }
		let prefix = text.prefix(count)
		guard let space = prefix.lastIndex(where: \.isWhitespace) else { return "" }
		return String(prefix[..<space])
	}
}

extension EnvironmentValues {
	/// How far each answer has been revealed, shared by the log's rows, so a row scrolled away and back resumes.
	@Entry var revealLedger: RevealLedger?
}

/// The reveal's position, a class so that advancing it each frame doesn't invalidate the view it's drawn in.
@MainActor
final class RevealClock {
	private(set) var shown = -1.0
	private var last: Date?

	func advance(id: String, length: Int, ledger: RevealLedger?, at date: Date) -> Int {
		if shown < 0 { shown = ledger?.shown(id, length: length) ?? Double(length) }
		// After a pause the timeline's first frame says nothing about how long a frame is.
		let elapsed = last.map { min(date.timeIntervalSince($0), 1.0 / 30) } ?? 1.0 / 120
		last = date
		shown = RevealPace.advance(shown, towards: length, elapsed: elapsed)
		ledger?.record(id, shown)
		return Int(shown)
	}
}
