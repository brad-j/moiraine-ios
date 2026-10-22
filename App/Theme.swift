// moiraine's design system (github.com/brad-j/moiraine, design.md and tokens.css), in SwiftUI. The colors are the
// tokens' OKLCH values as they're written there, converted here, so a change to tokens.css is copied as it is.
import MoiraineCore
import SwiftUI

extension Color {
	/// An OKLCH color, as CSS writes it: lightness 0 to 1, chroma, hue in degrees.
	init(oklch l: Double, _ c: Double, _ h: Double, opacity: Double = 1) {
		let a = c * cos(h * .pi / 180)
		let b = c * sin(h * .pi / 180)
		let l_ = l + 0.3963377774 * a + 0.2158037573 * b
		let m_ = l - 0.1055613458 * a - 0.0638541728 * b
		let s_ = l - 0.0894841775 * a - 1.2914855480 * b
		let (lc, mc, sc) = (l_ * l_ * l_, m_ * m_ * m_, s_ * s_ * s_)
		let linear = [
			4.0767416621 * lc - 3.3077115913 * mc + 0.2309699292 * sc,
			-1.2684380046 * lc + 2.6097574011 * mc - 0.3413193965 * sc,
			-0.0041960863 * lc - 0.7034186147 * mc + 1.7076147010 * sc,
		]
		let srgb = linear.map { v in
			let v = min(max(v, 0), 1)
			return v <= 0.0031308 ? 12.92 * v : 1.055 * pow(v, 1 / 2.4) - 0.055
		}
		self.init(.sRGB, red: srgb[0], green: srgb[1], blue: srgb[2], opacity: opacity)
	}
}

/// tokens.css's colors.
enum Palette {
	/// Surfaces, darkest first: the agents' rail, the canvas, the threads' column and code, fills, pressed or current.
	static let paper0 = Color(oklch: 0.155, 0, 0)
	static let paper = Color(oklch: 0.182, 0, 0)
	static let paper2 = Color(oklch: 0.21, 0, 0)
	static let paper3 = Color(oklch: 0.265, 0, 0)
	static let paper4 = Color(oklch: 0.30, 0, 0)
	static let rule = Color(oklch: 0.29, 0, 0)
	static let rule2 = Color(oklch: 0.36, 0, 0)

	static let ink = Color(oklch: 0.94, 0, 0)
	static let ink2 = Color(oklch: 0.77, 0, 0)
	static let ink3 = Color(oklch: 0.63, 0, 0)

	/// One accent: live state, the current item, focus, the primary action.
	static let accent = Color(oklch: 0.80, 0.11, 225)
	static let accentStrong = Color(oklch: 0.86, 0.09, 222)
	static let accentInk = Color(oklch: 0.17, 0.03, 235)
	static let accentWash = Color(oklch: 0.80, 0.11, 225, opacity: 0.12)
	static let accentLine = Color(oklch: 0.80, 0.11, 225, opacity: 0.45)

	static let ok = Color(oklch: 0.78, 0.11, 165)
	static let warn = Color(oklch: 0.83, 0.12, 85)
	static let warnWash = Color(oklch: 0.83, 0.12, 85, opacity: 0.08)
	static let warnLine = Color(oklch: 0.83, 0.12, 85, opacity: 0.45)
	static let bad = Color(oklch: 0.71, 0.15, 22)
	static let badWash = Color(oklch: 0.71, 0.15, 22, opacity: 0.1)
	static let scrim = Color(oklch: 0.08, 0, 0, opacity: 0.6)
	static let shadow = Color(oklch: 0.05, 0, 0, opacity: 0.5)

	/// The agents' colors, which say which agent a thing is and only that, at the accent's lightness.
	static func agent(_ color: AgentColor) -> Color {
		switch color {
		case .ice: Color(oklch: 0.80, 0.11, 225)
		case .blue: Color(oklch: 0.76, 0.12, 268)
		case .violet: Color(oklch: 0.76, 0.13, 300)
		case .orchid: Color(oklch: 0.78, 0.13, 330)
		case .pink: Color(oklch: 0.81, 0.09, 2)
		case .teal: Color(oklch: 0.80, 0.11, 192)
		case .lime: Color(oklch: 0.85, 0.14, 125)
		case .silver: Color(oklch: 0.83, 0, 0)
		}
	}

	/// An agent color's wash, for its avatar's ground.
	static func agentWash(_ color: AgentColor) -> Color {
		agent(color).opacity(0.16)
	}
}

/// tokens.css's type: Fira Sans for reading, Fira Code for technical text and the chrome. The sizes are its rem
/// sizes at 16 points, and follow Dynamic Type.
enum Typography {
	static func sans(_ size: CGFloat, _ weight: Font.Weight = .regular, relativeTo style: Font.TextStyle = .body) -> Font {
		let name = switch weight {
		case .medium: "FiraSans-Medium"
		case .semibold, .bold: "FiraSans-SemiBold"
		default: "FiraSans-Regular"
		}
		return .custom(name, size: size, relativeTo: style)
	}

	static func mono(_ size: CGFloat, _ weight: Font.Weight = .regular, relativeTo style: Font.TextStyle = .body) -> Font {
		Font.custom("Fira Code", size: size, relativeTo: style).weight(weight)
	}

	/// --text-2xs to --text-lg.
	static let size2xs: CGFloat = 11
	static let sizeXs: CGFloat = 12
	static let sizeSm: CGFloat = 13
	static let sizeBase: CGFloat = 15
	static let sizeMd: CGFloat = 16
	static let sizeLg: CGFloat = 18

	/// Prose in answers: --text-md at line-height 1.65.
	static let reading = sans(sizeMd)
	static let readingStrong = sans(sizeMd, .semibold)
	static let readingItalic = Font.custom("FiraSans-Italic", size: sizeMd, relativeTo: .body)
	static let readingLineSpacing: CGFloat = sizeMd * 0.65
	static let readingSmall = sans(sizeSm, relativeTo: .footnote)
	static let readingSmallStrong = sans(sizeSm, .semibold, relativeTo: .footnote)
	static let label = sans(sizeSm, .medium, relativeTo: .footnote)
	static let title = sans(sizeLg, .semibold, relativeTo: .headline)
	static func heading(_ level: Int) -> Font {
		sans(level <= 1 ? sizeLg : sizeMd, .semibold, relativeTo: .headline)
	}

	/// The log's gutter, the status line, tags and times.
	static let gutter = mono(sizeXs, relativeTo: .caption)
	static let meta = mono(size2xs, relativeTo: .caption2)
	static let code = mono(sizeSm, relativeTo: .footnote)
	static let inlineCode = mono(sizeBase - 1, relativeTo: .body)
	static let chrome = mono(sizeSm, relativeTo: .footnote)
}

/// tokens.css's 4-point spacing scale, radii and sizes.
enum Space {
	static let x3s: CGFloat = 2
	static let x2s: CGFloat = 4
	static let xs: CGFloat = 8
	static let sm: CGFloat = 12
	static let md: CGFloat = 16
	static let lg: CGFloat = 24
	static let xl: CGFloat = 32
}

enum Radius {
	static let sm: CGFloat = 4
	static let md: CGFloat = 6
	static let lg: CGFloat = 8
}

enum Metrics {
	static let rail: CGFloat = 64
	static let sidebar: CGFloat = 252
	/// The log's gutter on a phone: who wrote the line, without the time.
	static let gutterWho: CGFloat = 64
	static let hairline: CGFloat = 1
}

extension Animation {
	/// --ease-out at --dur-short, for color.
	static let short = Animation.timingCurve(0.16, 1, 0.3, 1, duration: 0.12)
	/// --ease-out at --dur-med, for the drawer and things moving into place.
	static let medium = Animation.timingCurve(0.16, 1, 0.3, 1, duration: 0.2)
}

// MARK: - The button voice

/// Primary: accent fill, accent-ink text, 500 weight. Secondary: a rule-2 border. Danger: bad text, bad wash pressed.
/// Quiet: ink-3 text, a fill pressed.
struct VoiceButtonStyle: ButtonStyle {
	enum Voice { case primary, secondary, danger, quiet }

	var voice: Voice
	var wide = false
	@Environment(\.isEnabled) private var enabled

	func makeBody(configuration: Configuration) -> some View {
		configuration.label
			.font(Typography.sans(Typography.sizeSm, .medium, relativeTo: .footnote))
			.lineLimit(1)
			.foregroundStyle(foreground)
			.padding(.horizontal, voice == .quiet ? Space.xs : Space.sm)
			.frame(minHeight: 36)
			.frame(maxWidth: wide ? .infinity : nil)
			.background(background(pressed: configuration.isPressed), in: RoundedRectangle(cornerRadius: Radius.sm))
			.overlay {
				if voice == .secondary { RoundedRectangle(cornerRadius: Radius.sm).strokeBorder(Palette.rule2, lineWidth: Metrics.hairline) }
			}
			.opacity(enabled ? 1 : 0.5)
			.contentShape(Rectangle())
			.animation(.short, value: configuration.isPressed)
	}

	private var foreground: Color {
		switch voice {
		case .primary: Palette.accentInk
		case .secondary: Palette.ink
		case .danger: Palette.bad
		case .quiet: Palette.ink3
		}
	}

	private func background(pressed: Bool) -> Color {
		switch voice {
		case .primary: pressed ? Palette.accentStrong : Palette.accent
		case .secondary: pressed ? Palette.paper3 : .clear
		case .danger: pressed ? Palette.badWash : .clear
		case .quiet: pressed ? Palette.paper3 : .clear
		}
	}
}

extension ButtonStyle where Self == VoiceButtonStyle {
	static var primary: VoiceButtonStyle { VoiceButtonStyle(voice: .primary) }
	static var secondary: VoiceButtonStyle { VoiceButtonStyle(voice: .secondary) }
	static var danger: VoiceButtonStyle { VoiceButtonStyle(voice: .danger) }
	static var quiet: VoiceButtonStyle { VoiceButtonStyle(voice: .quiet) }
}

/// A status chip: mono in a hairline box.
struct Tag: View {
	let text: String
	var color: Color = Palette.ink3

	var body: some View {
		Text(text)
			.font(Typography.meta)
			.foregroundStyle(color)
			.lineLimit(1)
			.padding(.horizontal, Space.x2s + 1)
			.padding(.vertical, Space.x3s)
			.overlay(RoundedRectangle(cornerRadius: Radius.sm).strokeBorder(Palette.rule2, lineWidth: Metrics.hairline))
	}
}

extension View {
	/// A hairline under the view, in the rule color.
	func hairlineBelow(_ color: Color = Palette.rule) -> some View {
		overlay(alignment: .bottom) { Rectangle().fill(color).frame(height: Metrics.hairline) }
	}
}
