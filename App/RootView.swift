// The frame: the conversation takes the screen, and the sidebar comes out over it as a drawer, from the menu button or
// a swipe right from the screen's left edge, and goes with a swipe left or a tap on the scrim. Notices that gaidin
// can't be reached, or speaks another protocol, sit at the top. Before there's a gaidin, the screen asks for one.
import MoiraineCore
import SwiftUI

struct RootView: View {
	@Environment(AppModel.self) private var app
	@Environment(\.scenePhase) private var scenePhase

	var body: some View {
		Group {
			if app.server == nil {
				ConnectView()
			} else {
				Frame()
			}
		}
		.background(Palette.paper.ignoresSafeArea())
		.onChange(of: scenePhase) { old, phase in
			if phase == .active, old == .background { app.cameForward() }
		}
	}
}

private struct Frame: View {
	@Environment(AppModel.self) private var app
	@Environment(\.accessibilityReduceMotion) private var reduceMotion
	@State private var open = false
	/// How far a finger has pulled the drawer, from where it was.
	@State private var drag: CGFloat = 0
	@State private var shown: String?

	var body: some View {
		GeometryReader { geometry in
			let width = min(geometry.size.width - 56, Metrics.rail + Metrics.sidebar + 40)
			let offset = min(max((open ? 0 : -width) + drag, -width), 0)
			let progress = 1 + offset / width
			ZStack(alignment: .leading) {
				VStack(spacing: 0) {
					Notices()
					conversation
				}
				.overlay(alignment: .leading) {
					// A strip at the left edge that a swipe right pulls the drawer out from.
					Color.clear.frame(width: 20).contentShape(Rectangle()).gesture(pull(width))
				}
				if open || drag > 0 {
					Palette.scrim
						.opacity(progress)
						.ignoresSafeArea()
						.onTapGesture { set(false) }
						.accessibilityAddTraits(.isButton)
						.accessibilityLabel("Close the sidebar")
						.transition(.opacity)
				}
				// Only while it's out, or a finger is pulling it, so VoiceOver doesn't read it off the screen.
				if open || drag > 0 {
					SidebarView(shown: $shown) { set(false) }
						.frame(width: width)
						.shadow(color: Palette.shadow.opacity(progress), radius: 16)
						.offset(x: offset)
						.gesture(pull(width))
						.transition(.move(edge: .leading))
				}
			}
		}
		.onChange(of: app.route?.agent) { _, agent in shown = agent }
		.onAppear { shown = app.route?.agent }
	}

	@ViewBuilder private var conversation: some View {
		if let route = app.route, let agent = app.agent(route.agent) {
			switch route {
			case .home:
				ConversationScreen(agent: agent, id: nil, menu: { set(true) }).id(route)
			case .thread(_, let id):
				ConversationScreen(agent: agent, id: id, menu: { set(true) }).id(route)
			case .newThread:
				NewThreadScreen(agent: agent, menu: { set(true) }).id(route)
			}
		} else if app.loaded {
			ContentUnavailableView { IconLabel("No agents", icon: .robot) } description: { Text("gaidin answered with no agents on its roster.") }
		} else {
			VStack(spacing: Space.sm) {
				ProgressView().tint(Palette.accent)
				Text("Asking gaidin").font(Typography.meta).foregroundStyle(Palette.ink3)
			}
			.frame(maxWidth: .infinity, maxHeight: .infinity)
		}
	}

	private func set(_ now: Bool) {
		if now { shown = app.route?.agent ?? shown }
		withAnimation(reduceMotion ? nil : .medium) {
			open = now
			drag = 0
		}
	}

	/// Follows the finger, and once let go settles by how far and how fast it went.
	private func pull(_ width: CGFloat) -> some Gesture {
		DragGesture(minimumDistance: 12)
			.onChanged { value in
				guard abs(value.translation.width) > abs(value.translation.height) else { return }
				drag = value.translation.width
			}
			.onEnded { value in
				let projected = value.predictedEndTranslation.width
				let opening = open ? projected > -width / 2 : projected > width / 2
				set(opening)
			}
	}
}

/// What's wrong with the connection, in a warn strip, until gaidin answers again.
private struct Notices: View {
	@Environment(AppModel.self) private var app

	var body: some View {
		VStack(spacing: 0) {
			if let problem = app.problem {
				strip("Can't reach gaidin: \(problem.advice ?? problem.message)")
			}
			if let other = app.otherProtocol {
				strip("gaidin speaks protocol \(other) and this app \(PROTOCOL). Update \(other > PROTOCOL ? "the app" : "gaidin") before relying on it.")
			}
		}
	}

	private func strip(_ text: String) -> some View {
		Text(text)
			.font(Typography.readingSmall)
			.foregroundStyle(Palette.warn)
			.frame(maxWidth: .infinity, alignment: .leading)
			.padding(.horizontal, Space.md)
			.padding(.vertical, Space.xs)
			.background(Palette.warnWash)
			.hairlineBelow(Palette.warnLine)
	}
}

/// The first screen: which gaidin, by the machine's tailnet name.
struct ConnectView: View {
	@Environment(AppModel.self) private var app
	@State private var address = ""
	@State private var checking = false
	@State private var problem: String?
	@FocusState private var focused: Bool

	var body: some View {
		VStack(alignment: .leading, spacing: Space.md) {
			Spacer()
			Text("moiraine").font(Typography.mono(Typography.sizeLg, .medium)).foregroundStyle(Palette.accent)
			Text("Which gaidin?").font(Typography.title).foregroundStyle(Palette.ink)
			Text("Its machine's tailnet name, as `tailscale serve` puts it on the tailnet. Tailscale needs to be on, signed in as gaidin's owner.")
				.font(Typography.readingSmall)
				.foregroundStyle(Palette.ink2)
			TextField("gaidin.example.ts.net", text: $address)
				.font(Typography.mono(Typography.sizeBase))
				.foregroundStyle(Palette.ink)
				.tint(Palette.accent)
				.textInputAutocapitalization(.never)
				.autocorrectionDisabled()
				.keyboardType(.URL)
				.submitLabel(.go)
				.focused($focused)
				.onSubmit(check)
				.padding(.horizontal, Space.sm)
				.frame(minHeight: 44)
				.background(Palette.paper2, in: RoundedRectangle(cornerRadius: Radius.md))
				.overlay(RoundedRectangle(cornerRadius: Radius.md).strokeBorder(focused ? Palette.accent : Palette.rule2, lineWidth: Metrics.hairline))
			if let problem {
				Text(problem).font(Typography.readingSmall).foregroundStyle(Palette.bad)
			}
			Button(action: check) {
				Text(checking ? "Asking gaidin" : "Connect").frame(maxWidth: .infinity, minHeight: 44)
			}
			.buttonStyle(VoiceButtonStyle(voice: .primary, wide: true))
			.disabled(checking || address.trimmingCharacters(in: .whitespaces).isEmpty)
			Spacer()
			Spacer()
		}
		.padding(.horizontal, Space.lg)
		.frame(maxWidth: 520)
		.frame(maxWidth: .infinity)
		.onAppear { focused = true }
	}

	private func check() {
		problem = nil
		checking = true
		Task {
			do {
				try await app.connect(to: address)
			} catch let error as GaidinError {
				problem = error.advice ?? error.message
			} catch {
				problem = error.localizedDescription
			}
			checking = false
		}
	}
}
