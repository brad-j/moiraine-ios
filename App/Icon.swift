// Phosphor's icons (MIT, App/Icons-LICENSE.txt), as moiraine's web app has them: regular weight, 16 points, in the
// color of the text beside them, with fill only for Send and Stop. Only the icons the app uses are kept, as SVGs in
// Assets.xcassets/Phosphor, copied from github.com/phosphor-icons/core's assets; Phosphor's Swift package carries
// every icon in every weight, which takes the asset compiler minutes on each clean build.
import SwiftUI

/// The icons the app uses, by Phosphor's names.
enum Ph: String {
	case arrowDown = "arrow-down"
	case browser
	case caretRight = "caret-right"
	case chatCircle = "chat-circle"
	case check
	case checkSquare = "check-square"
	case clock
	case copy
	case hourglass
	case list
	case paperPlaneRight = "paper-plane-right"
	case question
	case robot
	case shieldWarning = "shield-warning"
	case slackLogo = "slack-logo"
	case speakerHigh = "speaker-high"
	case square
	case stop
	case x

	enum Weight: String {
		case regular, bold, fill
	}

	/// The asset's name: `ph-<name>`, or `ph-<name>-<weight>` for the weights that are kept.
	func asset(_ weight: Weight) -> String {
		weight == .regular ? "ph-\(rawValue)" : "ph-\(rawValue)-\(weight.rawValue)"
	}
}

struct Icon: View {
	let icon: Ph
	var weight: Ph.Weight = .regular
	var size: CGFloat = 16

	init(_ icon: Ph, weight: Ph.Weight = .regular, size: CGFloat = 16) {
		self.icon = icon
		self.weight = weight
		self.size = size
	}

	var body: some View {
		Image(icon.asset(weight))
			.renderingMode(.template)
			.resizable()
			.aspectRatio(contentMode: .fit)
			.frame(width: size, height: size)
			.accessibilityHidden(true)
	}
}

/// A word with its icon before it, as a Label is drawn.
struct IconLabel: View {
	let title: String
	let icon: Ph
	var weight: Ph.Weight = .regular
	var size: CGFloat = 16
	var spacing: CGFloat = Space.x2s + 2

	init(_ title: String, icon: Ph, weight: Ph.Weight = .regular, size: CGFloat = 16, spacing: CGFloat = Space.x2s + 2) {
		self.title = title
		self.icon = icon
		self.weight = weight
		self.size = size
		self.spacing = spacing
	}

	var body: some View {
		HStack(spacing: spacing) {
			Icon(icon, weight: weight, size: size)
			Text(title)
		}
	}
}
