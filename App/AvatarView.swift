// An agent's avatar: a rounded square (28% corners) with its picture, or its initial on its color's wash. In the rail,
// every agent but the one shown has its initial on the paper's fill instead.
import MoiraineCore
import SwiftUI

struct AvatarView: View {
	@Environment(AppModel.self) private var app
	let agent: Agent
	var size: CGFloat = 24
	/// The rail's quiet look, for an agent that isn't the one shown.
	var quiet = false

	var body: some View {
		let shape = RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
		let color = app.color(agent)
		ZStack {
			if let url = app.client?.avatarURL(agent) {
				AsyncImage(url: url) { phase in
					if let image = phase.image { image.resizable().scaledToFill() } else { monogram(color) }
				}
			} else {
				monogram(color)
			}
		}
		.frame(width: size, height: size)
		.clipShape(shape)
		.accessibilityHidden(true)
	}

	private func monogram(_ color: AgentColor) -> some View {
		Text(Format.initial(agent.name))
			.font(Typography.sans(size * 0.46, .semibold))
			.foregroundStyle(quiet ? Palette.ink2 : Palette.agent(color))
			.frame(maxWidth: .infinity, maxHeight: .infinity)
			.background(quiet ? Palette.paper3 : Palette.agentWash(color))
	}
}
