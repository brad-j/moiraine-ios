// What gaidin's HTTP API answers and takes, for the routes the app uses (gaidin's src/web.ts, `Gets` and `Posts`).
// Fields the app doesn't read are left out; decoding ignores them.
import Foundation

/// The protocol version this build is written against. gaidin raises it when an answer or a body changes shape, and
/// the app says so when the gaidin it talks to speaks another.
public let PROTOCOL = 18

public struct Version: Sendable, Hashable, Decodable {
	public var protocolVersion: Int

	enum CodingKeys: String, CodingKey {
		case protocolVersion = "protocol"
	}
}

/// An agent on the roster (gaidin's AgentEntry).
public struct Agent: Sendable, Hashable, Decodable, Identifiable {
	public var id: String
	public var name: String
	/// One line saying what it's for.
	public var job: String
	/// Its home conversation's id.
	public var home: Int
	/// Its picture's file name, when it has one; the address changes with it.
	public var avatar: String?
	/// The color it was given, one of AgentColor's.
	public var color: String?
	public var archived: Double?
}

/// What an agent is up to: whether a run of its is going, and its newest message.
public struct AgentActivity: Sendable, Hashable, Decodable {
	public struct Last: Sendable, Hashable, Decodable {
		public var at: Double
		public var text: String
		public var role: String
		public var conversation: Int
		public var place: String
	}

	public var agent: String
	public var running: Bool
	public var last: Last?
}

/// A request waiting on the owner: a tool call to allow, a question, or a browser profile to take over.
public struct Approval: Sendable, Hashable, Decodable, Identifiable {
	public struct Always: Sendable, Hashable, Decodable {
		public var kind: String
		public var value: String
		/// The button, such as "Always allow site.test".
		public var label: String
	}

	public var id: String
	public var conversationId: Int
	/// The agent whose conversation asks. Absent: the default agent.
	public var agent: String?
	public var tool: String
	/// One line: what the call does, or the question.
	public var summary: String
	public var detail: String?
	/// "question" or "handover"; absent for a call to allow.
	public var kind: String?
	public var profile: String?
	public var choices: [String]?
	public var always: Always?
	public var createdAt: Double
	public var expiresAt: Double
	public var status: String

	public var isQuestion: Bool { kind == "question" }
	public var isHandover: Bool { kind == "handover" }
	public var isCall: Bool { kind == nil }
}

/// A thread, job run or conversation another agent started (gaidin's ConversationSummary).
public struct ConversationSummary: Sendable, Hashable, Decodable, Identifiable {
	public var id: Int
	/// "thread", "job" or "agent".
	public var place: String
	public var agent: String
	/// For a thread, where it began: "slack", "app", "voice", "job" or "agent".
	public var origin: String?
	/// A job run's job, or a thread's first message.
	public var title: String
	/// The last answer in it.
	public var preview: String
	public var startedAt: Double?
	public var lastAt: Double?
	public var messages: Int?
	/// For a thread: the home conversation's entry it forked at.
	public var forkedAt: Int?

	/// Where it began, as its label says: a thread's origin, or its place.
	public var began: String {
		place == "thread" ? (origin ?? "slack") : place
	}
}

public struct ConversationPage: Sendable, Hashable, Decodable {
	public var items: [ConversationSummary]
	/// The cursor for the next page, when there's more.
	public var next: Int?
}

/// `/api/conversation?id=`: a thread and its transcript as the event stream starts it.
public struct ConversationDetail: Sendable, Hashable, Decodable {
	public var conversation: ConversationSummary
	public var snapshot: Snapshot
}

public struct Settings: Sendable, Hashable, Decodable {
	public struct Tool: Sendable, Hashable, Decodable {
		public var name: String
		public var enabled: Bool
	}

	public var model: String
	public var models: [String]
	public var thinkingLevel: String
	public var instructions: String
	public var tools: [Tool]
}

/// Spend against the limits; gaidin answers null when there's no budget.
public struct Budget: Sendable, Hashable, Decodable {
	public var today: Double
	public var month: Double
	public var dailyLimit: Double
	public var monthlyLimit: Double
	public var stopped: Bool
	public var reason: String?
}

// MARK: - Bodies

public struct MessageBody: Sendable, Encodable {
	public var content: String
	public var requestId: String
	public var agent: String
	public var conversation: Int?
	public var files: [String]?

	public init(content: String, requestId: String = UUID().uuidString.lowercased(), agent: String, conversation: Int?, files: [String]? = nil) {
		self.content = content
		self.requestId = requestId
		self.agent = agent
		self.conversation = conversation
		self.files = files
	}
}

public struct MessageAnswer: Sendable, Hashable, Decodable {
	/// The message was taken as the answer to the agent's question.
	public var answered: Bool?
	/// Where the message went: the conversation, or a fork of a job run or another agent's conversation.
	public var conversation: Int
}

public struct ThreadBody: Sendable, Encodable {
	public var content: String
	public var requestId: String
	public var agent: String

	public init(content: String, requestId: String = UUID().uuidString.lowercased(), agent: String) {
		self.content = content
		self.requestId = requestId
		self.agent = agent
	}
}

public struct ThreadAnswer: Sendable, Hashable, Decodable {
	public var conversation: Int
}

public struct AbortBody: Sendable, Encodable {
	public var agent: String
	public var conversation: Int?

	public init(agent: String, conversation: Int?) {
		self.agent = agent
		self.conversation = conversation
	}
}

public enum Decision: String, Sendable, Encodable {
	case once, always, deny
}

public struct DecideBody: Sendable, Encodable {
	public var id: String
	public var decision: Decision

	public init(id: String, decision: Decision) {
		self.id = id
		self.decision = decision
	}
}

public struct AnswerBody: Sendable, Encodable {
	public var id: String
	public var answer: String

	public init(id: String, answer: String) {
		self.id = id
		self.answer = answer
	}
}

public struct SnoozeBody: Sendable, Encodable {
	public var id: Int
	public var minutes: Int

	public init(id: Int, minutes: Int) {
		self.id = id
		self.minutes = minutes
	}
}

public struct SnoozeAnswer: Sendable, Hashable, Decodable {
	public var at: Double
}

public struct Ok: Sendable, Hashable, Decodable {
	public var ok: Bool
}
