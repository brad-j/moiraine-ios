// Requests to gaidin's HTTP API. On the tailnet, `tailscale serve` puts HTTPS in front of gaidin and adds the owner's
// login, which gaidin checks; the app sends nothing of its own to sign in. gaidin turns away a POST from another site
// by its Origin header, which the app doesn't send, and by a body that isn't JSON, which the app's never are.
import Foundation

public struct GaidinError: Error, Sendable, Hashable, LocalizedError {
	public var status: Int?
	/// What gaidin said, or what went wrong on the way.
	public var message: String

	public init(status: Int?, message: String) {
		self.status = status
		self.message = message
	}

	public var errorDescription: String? { message }

	/// What the owner can do about it, for the answers that mean the app never reached gaidin as the owner.
	public var advice: String? {
		switch status {
		case 403: "gaidin didn't let this device in. Check that Tailscale is on and signed in as gaidin's owner."
		case 502, 503, 504: "Tailscale reached the machine, but gaidin isn't answering. It may be restarting."
		default: nil
		}
	}
}

public struct GaidinClient: Sendable {
	public var base: URL
	let session: URLSession

	public init(base: URL, session: URLSession = .shared) {
		self.base = base
		self.session = session
	}

	/// An address as the owner types it: a full URL, or a tailnet name, which gets https://.
	public static func address(_ typed: String) -> URL? {
		var text = typed.trimmingCharacters(in: .whitespacesAndNewlines)
		while text.hasSuffix("/") { text.removeLast() }
		guard !text.isEmpty, !text.contains(" ") else { return nil }
		if !text.contains("://") { text = "https://\(text)" }
		guard let url = URL(string: text), let scheme = url.scheme, ["http", "https"].contains(scheme), url.host() != nil else { return nil }
		return url
	}

	public func url(_ path: String, _ query: [String: String] = [:]) -> URL {
		var components = URLComponents(url: base.appending(path: path), resolvingAgainstBaseURL: false)!
		if !query.isEmpty { components.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) } }
		return components.url!
	}

	public func get<T: Decodable>(_ path: String, _ query: [String: String] = [:], as type: T.Type = T.self) async throws -> T {
		var request = URLRequest(url: url(path, query))
		request.cachePolicy = .reloadIgnoringLocalCacheData
		return try await send(request)
	}

	public func post<T: Decodable>(_ path: String, _ body: some Encodable, as type: T.Type = T.self) async throws -> T {
		var request = URLRequest(url: url(path))
		request.httpMethod = "POST"
		request.setValue("application/json", forHTTPHeaderField: "Content-Type")
		request.httpBody = try JSONEncoder().encode(body)
		return try await send(request)
	}

	private func send<T: Decodable>(_ request: URLRequest) async throws -> T {
		let (data, response) = try await transport(request)
		let status = (response as? HTTPURLResponse)?.statusCode ?? 0
		guard (200..<300).contains(status) else {
			let text = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
			throw GaidinError(status: status, message: text.isEmpty ? "gaidin answered \(status)." : text)
		}
		do {
			return try JSONDecoder().decode(T.self, from: data)
		} catch {
			throw GaidinError(status: status, message: "gaidin's answer to \(request.url?.path() ?? "a request") didn't read: \(error)")
		}
	}

	private func transport(_ request: URLRequest) async throws -> (Data, URLResponse) {
		do {
			return try await session.data(for: request)
		} catch let error as URLError {
			throw GaidinError(status: nil, message: Self.describe(error))
		}
	}

	static func describe(_ error: URLError) -> String {
		switch error.code {
		case .cannotFindHost, .dnsLookupFailed: "Can't find that machine. Check the address, and that Tailscale is on."
		case .cannotConnectToHost, .networkConnectionLost, .notConnectedToInternet, .timedOut: "Can't reach gaidin. Check that Tailscale is on."
		case .secureConnectionFailed, .serverCertificateUntrusted, .serverCertificateHasBadDate: "The secure connection failed. Is the address the machine's tailnet name?"
		default: error.localizedDescription
		}
	}

	// MARK: Routes

	public func version() async throws -> Version { try await get("/api/version") }
	public func agents() async throws -> [Agent] { try await get("/api/agents") }
	public func activity() async throws -> [AgentActivity] { try await get("/api/agents/activity") }
	public func approvals() async throws -> [Approval] { try await get("/api/approvals") }
	public func budget() async throws -> Budget? { try await get("/api/budget") }
	public func settings(agent: String) async throws -> Settings { try await get("/api/settings", ["agent": agent]) }

	public func conversations(agent: String, before: Int? = nil) async throws -> ConversationPage {
		var query = ["agent": agent]
		if let before { query["before"] = String(before) }
		return try await get("/api/conversations", query)
	}

	public func conversation(_ id: Int) async throws -> ConversationDetail { try await get("/api/conversation", ["id": String(id)]) }

	public func message(_ body: MessageBody) async throws -> MessageAnswer { try await post("/api/message", body) }
	public func startThread(_ body: ThreadBody) async throws -> ThreadAnswer { try await post("/api/threads/start", body) }
	public func abort(_ body: AbortBody) async throws -> Ok { try await post("/api/abort", body) }
	public func decide(_ body: DecideBody) async throws -> Ok { try await post("/api/approvals/decide", body) }
	public func answer(_ body: AnswerBody) async throws -> Ok { try await post("/api/approvals/answer", body) }
	public func snooze(_ body: SnoozeBody) async throws -> SnoozeAnswer { try await post("/api/reminders/snooze", body) }

	/// Where an agent's picture is; the address changes with the picture's name.
	public func avatarURL(_ agent: Agent) -> URL? {
		guard let avatar = agent.avatar else { return nil }
		return url("/api/agents/avatar", ["id": agent.id, "v": avatar])
	}

	/// A conversation's event stream: `conversation` by id, or the agent's home.
	public func eventsURL(agent: String, conversation: Int?) -> URL {
		conversation.map { url("/events", ["conversation": String($0)]) } ?? url("/events", ["agent": agent])
	}

	/// The whole app's events: the approvals, runs starting and ending, and conversations changing.
	public var appEventsURL: URL {
		var components = URLComponents(url: base.appending(path: "/events"), resolvingAgainstBaseURL: false)!
		components.percentEncodedQuery = "all"
		return components.url!
	}
}
