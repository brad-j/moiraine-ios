// A conversation as gaidin's event stream (/events) carries it: pi-durable's entries, messages and agent events, and
// gaidin's own events beside them (web.ts StreamEvent). Decoding is lenient where the protocol can grow: an event,
// block or message part of a kind this build doesn't know is kept as `other`, never a failure.
import Foundation

/// A part of an assistant message.
public enum Block: Sendable, Hashable {
	case text(String)
	case thinking(String, redacted: Bool)
	case toolCall(id: String, name: String, arguments: JSONValue)
	case other(type: String)
}

/// A part of the owner's message or a tool's result: text or an image.
public enum Part: Sendable, Hashable {
	case text(String)
	case image(data: String, mimeType: String)
	case other(type: String)
}

public struct AssistantMessage: Sendable, Hashable {
	public var content: [Block]
	/// When its request started, which it keeps from its first word to its entry.
	public var timestamp: Double?
	public var stopReason: String?
	public var errorMessage: String?
	public var model: String?
}

public enum Message: Sendable, Hashable {
	case user(content: [Part], timestamp: Double?)
	case assistant(AssistantMessage)
	case toolResult(toolCallId: String, toolName: String, content: [Part], isError: Bool)
	case other(role: String)
}

/// An entry of the conversation: a message, a tool's result, or gaidin's bookkeeping (`kind` says which).
public struct Entry: Sendable, Hashable, Identifiable {
	public var id: Int
	public var conversationId: Int
	public var kind: String
	public var model: [Message]?
	public var data: JSONValue?
}

public struct ModelRef: Sendable, Hashable, Decodable {
	public var provider: String
	public var modelId: String
}

/// The conversation's model and thinking level (pi-durable's `pi.agent`).
public struct AgentState: Sendable, Hashable, Decodable {
	public var model: ModelRef?
	public var thinkingLevel: String?
}

/// What a conversation has cost, by model and by tool. Only the total of each is read.
public struct UsageState: Sendable, Hashable, Decodable {
	public struct Bucket: Sendable, Hashable, Decodable {
		public struct Cost: Sendable, Hashable, Decodable {
			public var total: Double
		}

		public var cost: Cost?
	}

	public var models: [String: Bucket]
	public var tools: [String: Bucket]

	/// Dollars, across every model and tool.
	public var total: Double {
		(models.values.map { $0.cost?.total ?? 0 } + tools.values.map { $0.cost?.total ?? 0 }).reduce(0, +)
	}
}

/// A tool call of the current round, as the snapshot has it.
public struct ToolSlot: Sendable, Hashable, Decodable {
	public var callId: String
	public var name: String
	public var status: String
	public var output: String?
}

public struct Snapshot: Sendable, Hashable {
	public var entries: [Entry]
	/// Whether a run is going.
	public var running: Bool
	/// The assistant message being generated, if one is.
	public var partial: AssistantMessage?
	public var tools: [ToolSlot]
	public var agent: AgentState?
	public var usage: UsageState?
}

/// One change to the assistant message being generated.
public enum MessageChange: Sendable, Hashable {
	/// A block started or replaced whole (`text_start`, `thinking_start`, `toolcall_start`, `block`).
	case block(index: Int, Block)
	case textDelta(index: Int, String)
	case thinkingDelta(index: Int, String)
	/// Appends to the string at `path` inside a tool call's arguments.
	case toolCallDelta(index: Int, path: [PathComponent], String)
	/// The whole message, replaced.
	case message(AssistantMessage)
	case other
}

/// A tool's running output: a trim of its front and an append, or its replacement.
public enum OutputChange: Sendable, Hashable {
	case set(String)
	case trimAndAppend(trimStart: Int, append: String)
}

public enum StreamEvent: Sendable, Hashable {
	case snapshot(Snapshot)
	case runStart
	case runEnd
	case messageStart(Message)
	case messageUpdate([MessageChange])
	case messageEnd(Entry)
	case toolStart(callId: String, name: String)
	case toolUpdate(callId: String, OutputChange?)
	case toolEnd(callId: String, entry: Entry?)
	case entryAppended(Entry)
	case agentChanged(AgentState)
	case usageChanged(UsageState)
	case retryStart(String)
	case retryEnd
	case taskFailed(kind: String, message: String)
	/// gaidin's: the requests waiting on the owner changed.
	case approvalsChanged
	/// gaidin's, on /events?all: one of an agent's runs started or ended.
	case activityChanged(agent: String)
	/// gaidin's, on /events?all: an agent's conversations or their order changed.
	case conversationsChanged(agent: String)
	case other(type: String)

	/// Reads one event's JSON, as gaidin sends it in a `data:` line.
	public static func decode(_ data: Data) throws -> StreamEvent {
		try JSONDecoder().decode(StreamEvent.self, from: data)
	}
}

// MARK: - Decoding

private struct AnyKey: CodingKey {
	var stringValue: String
	var intValue: Int?
	init(_ string: String) { stringValue = string }
	init?(stringValue: String) { self.stringValue = stringValue }
	init?(intValue: Int) {
		stringValue = String(intValue)
		self.intValue = intValue
	}
}

private extension KeyedDecodingContainer where K == AnyKey {
	func value<T: Decodable>(_ key: String, as type: T.Type = T.self) throws -> T {
		try decode(T.self, forKey: AnyKey(key))
	}

	func optional<T: Decodable>(_ key: String, as type: T.Type = T.self) throws -> T? {
		try decodeIfPresent(T.self, forKey: AnyKey(key))
	}

	func has(_ key: String) -> Bool {
		contains(AnyKey(key))
	}
}

extension Block: Decodable {
	public init(from decoder: any Decoder) throws {
		let c = try decoder.container(keyedBy: AnyKey.self)
		let type: String = try c.value("type")
		switch type {
		case "text": self = .text(try c.optional("text") ?? "")
		case "thinking": self = .thinking(try c.optional("thinking") ?? "", redacted: try c.optional("redacted") ?? false)
		case "toolCall": self = .toolCall(id: try c.value("id"), name: try c.value("name"), arguments: try c.optional("arguments") ?? .object([:]))
		default: self = .other(type: type)
		}
	}
}

extension Part: Decodable {
	public init(from decoder: any Decoder) throws {
		let c = try decoder.container(keyedBy: AnyKey.self)
		let type: String = try c.value("type")
		switch type {
		case "text": self = .text(try c.optional("text") ?? "")
		case "image": self = .image(data: try c.value("data"), mimeType: try c.value("mimeType"))
		default: self = .other(type: type)
		}
	}

	/// Content that's a string or an array of parts.
	fileprivate static func list(_ c: KeyedDecodingContainer<AnyKey>, _ key: String) throws -> [Part] {
		if let text = try? c.decodeIfPresent(String.self, forKey: AnyKey(key)) { return [.text(text)] }
		return try c.optional(key) ?? []
	}
}

extension AssistantMessage: Decodable {
	public init(from decoder: any Decoder) throws {
		let c = try decoder.container(keyedBy: AnyKey.self)
		content = try c.optional("content") ?? []
		timestamp = try c.optional("timestamp")
		stopReason = try c.optional("stopReason")
		errorMessage = try c.optional("errorMessage")
		model = try c.optional("model")
	}
}

extension Message: Decodable {
	public init(from decoder: any Decoder) throws {
		let c = try decoder.container(keyedBy: AnyKey.self)
		let role: String = try c.value("role")
		switch role {
		case "user": self = .user(content: try Part.list(c, "content"), timestamp: try c.optional("timestamp"))
		case "assistant": self = .assistant(try AssistantMessage(from: decoder))
		case "toolResult":
			self = .toolResult(toolCallId: try c.value("toolCallId"), toolName: try c.optional("toolName") ?? "", content: try Part.list(c, "content"), isError: try c.optional("isError") ?? false)
		default: self = .other(role: role)
		}
	}
}

extension Entry: Decodable {
	public init(from decoder: any Decoder) throws {
		let c = try decoder.container(keyedBy: AnyKey.self)
		id = try c.value("id")
		conversationId = try c.value("conversationId")
		kind = try c.value("kind")
		model = try c.optional("model")
		data = try c.optional("data")
	}
}

extension Snapshot: Decodable {
	public init(from decoder: any Decoder) throws {
		let c = try decoder.container(keyedBy: AnyKey.self)
		entries = try c.optional("entries") ?? []
		running = c.has("run")
		if c.has("generation") {
			let generation = try c.nestedContainer(keyedBy: AnyKey.self, forKey: AnyKey("generation"))
			partial = try generation.optional("message")
		} else {
			partial = nil
		}
		tools = try c.optional("tools") ?? []
		agent = try c.optional("agent")
		usage = try c.optional("usage")
	}
}

extension MessageChange: Decodable {
	public init(from decoder: any Decoder) throws {
		let c = try decoder.container(keyedBy: AnyKey.self)
		let type: String = try c.value("type")
		switch type {
		case "text_start", "thinking_start", "toolcall_start", "block": self = .block(index: try c.value("contentIndex"), try c.value("block"))
		case "text_delta": self = .textDelta(index: try c.value("contentIndex"), try c.value("delta"))
		case "thinking_delta": self = .thinkingDelta(index: try c.value("contentIndex"), try c.value("delta"))
		case "toolcall_delta": self = .toolCallDelta(index: try c.value("contentIndex"), path: try c.value("path"), try c.value("delta"))
		case "message": self = .message(try c.value("message"))
		default: self = .other
		}
	}
}

extension StreamEvent: Decodable {
	public init(from decoder: any Decoder) throws {
		let c = try decoder.container(keyedBy: AnyKey.self)
		let type: String = try c.value("type")
		switch type {
		case "snapshot": self = .snapshot(try Snapshot(from: decoder))
		case "run_start": self = .runStart
		case "run_end": self = .runEnd
		case "message_start": self = .messageStart(try c.value("message"))
		case "message_update": self = .messageUpdate(try c.optional("changes") ?? [])
		case "message_end": self = .messageEnd(try c.value("entry"))
		case "tool_execution_start": self = .toolStart(callId: try c.value("toolCallId"), name: try c.value("toolName"))
		case "tool_execution_update":
			var change: OutputChange?
			if c.has("output") {
				let output = try c.nestedContainer(keyedBy: AnyKey.self, forKey: AnyKey("output"))
				if let set: String = try output.optional("set") {
					change = .set(set)
				} else {
					change = .trimAndAppend(trimStart: try output.optional("trimStart") ?? 0, append: try output.optional("append") ?? "")
				}
			}
			self = .toolUpdate(callId: try c.value("toolCallId"), change)
		case "tool_execution_end": self = .toolEnd(callId: try c.value("toolCallId"), entry: try c.optional("entry"))
		case "entry_appended": self = .entryAppended(try c.value("entry"))
		case "agent_changed": self = .agentChanged(try c.value("agent"))
		case "usage_changed": self = .usageChanged(try c.value("usage"))
		case "auto_retry_start": self = .retryStart(try c.optional("errorMessage") ?? "")
		case "auto_retry_end": self = .retryEnd
		case "task_failed": self = .taskFailed(kind: try c.optional("kind") ?? "task", message: try c.optional("message") ?? "")
		case "approvals_changed": self = .approvalsChanged
		case "activity_changed": self = .activityChanged(agent: try c.value("agent"))
		case "conversations_changed": self = .conversationsChanged(agent: try c.value("agent"))
		default: self = .other(type: type)
		}
	}
}
