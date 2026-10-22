// moiraine on iPhone: gaidin's agents, their conversations and what they wait on the owner for, natively. A client of
// gaidin's HTTP API over the tailnet, as moiraine's web app is.
import SwiftUI

@main
struct MoiraineApp: App {
	@State private var app = AppModel()

	var body: some Scene {
		WindowGroup {
			RootView()
				.environment(app)
				.preferredColorScheme(.dark)
				.tint(Palette.accent)
		}
	}
}
