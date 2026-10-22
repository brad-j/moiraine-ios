// An agent's color, which says which agent a thing is: the one its settings chose, from gaidin's AGENT_COLORS, or for an
// agent without one, the color at its place in the roster. The app's controls keep the accent whatever the agent.
// From moiraine's src/color.ts.
public enum AgentColor: String, Sendable, Hashable, CaseIterable {
	case ice, blue, violet, orchid, pink, teal, lime, silver

	/// `agent`'s color, given the roster it's in.
	public static func of(_ agent: Agent, in roster: [Agent]) -> AgentColor {
		if let chosen = agent.color.flatMap(AgentColor.init(rawValue:)) { return chosen }
		let place = roster.firstIndex { $0.id == agent.id } ?? 0
		return allCases[place % allCases.count]
	}
}
