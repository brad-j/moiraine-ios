// gaidin's event streams (text/event-stream): one `data:` line of JSON per event, and a `: ping` comment every 25
// seconds. gaidin starts every connection with a snapshot, so a stream that drops is opened again and catches up.
import Foundation

/// Server-sent events, from lines: the data of each event, once the blank line after it comes.
public struct SSEParser: Sendable {
	private var data: [String] = []

	public init() {}

	/// Takes one line without its line break; returns an event's data when the line ends one.
	public mutating func feed(_ line: String) -> String? {
		let line = line.hasSuffix("\r") ? String(line.dropLast()) : line
		if line.isEmpty {
			defer { data = [] }
			return data.isEmpty ? nil : data.joined(separator: "\n")
		}
		if line.hasPrefix(":") { return nil }
		let (field, value) = Self.split(line)
		if field == "data" { data.append(value) }
		return nil
	}

	static func split(_ line: String) -> (String, String) {
		guard let colon = line.firstIndex(of: ":") else { return (line, "") }
		var value = line[line.index(after: colon)...]
		if value.first == " " { value = value.dropFirst() }
		return (String(line[..<colon]), String(value))
	}

	/// Every event's data in `text`, a stream as it was recorded.
	public static func events(in text: String) -> [String] {
		var parser = SSEParser()
		return text.split(separator: "\n", omittingEmptySubsequences: false).compactMap { parser.feed(String($0)) }
	}
}

/// What a stream says while it's open.
public enum StreamUpdate: Sendable {
	case connected
	case event(StreamEvent)
	/// The stream dropped or couldn't open; it tries again after `retryIn` seconds.
	case disconnected(GaidinError, retryIn: Double)
}

/// An event stream that opens itself again when it drops, waiting longer each time, from a second up to 15.
public enum EventStream {
	public static let firstRetry = 1.0
	public static let longestRetry = 15.0

	public static func open(_ url: URL, session: URLSession = EventStream.session) -> AsyncStream<StreamUpdate> {
		AsyncStream { continuation in
			let task = Task {
				var wait = firstRetry
				while !Task.isCancelled {
					do {
						try await read(url, session: session) { update in
							if case .connected = update { wait = firstRetry }
							continuation.yield(update)
						}
						// gaidin closed it, as when it restarts.
						continuation.yield(.disconnected(GaidinError(status: nil, message: "gaidin closed the stream."), retryIn: wait))
					} catch is CancellationError {
						break
					} catch let error as GaidinError {
						continuation.yield(.disconnected(error, retryIn: wait))
					} catch let error as URLError where error.code == .cancelled {
						break
					} catch let error as URLError {
						continuation.yield(.disconnected(GaidinError(status: nil, message: GaidinClient.describe(error)), retryIn: wait))
					} catch {
						continuation.yield(.disconnected(GaidinError(status: nil, message: "\(error)"), retryIn: wait))
					}
					try? await Task.sleep(for: .seconds(wait))
					wait = min(wait * 2, longestRetry)
				}
				continuation.finish()
			}
			continuation.onTermination = { _ in task.cancel() }
		}
	}

	/// A session for streams: no cache, and long enough between bytes for gaidin's 25-second pings.
	public static let session: URLSession = {
		let configuration = URLSessionConfiguration.default
		configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
		configuration.timeoutIntervalForRequest = 60
		configuration.timeoutIntervalForResource = .infinity
		return URLSession(configuration: configuration)
	}()

	private static func read(_ url: URL, session: URLSession, _ yield: (StreamUpdate) -> Void) async throws {
		var request = URLRequest(url: url)
		request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
		let (bytes, response) = try await session.bytes(for: request)
		let status = (response as? HTTPURLResponse)?.statusCode ?? 0
		guard status == 200 else {
			var text = ""
			for try await line in bytes.lines {
				text += line
				if text.count > 500 { break }
			}
			throw GaidinError(status: status, message: text.isEmpty ? "gaidin answered \(status)." : text)
		}
		yield(.connected)
		var parser = SSEParser()
		var line: [UInt8] = []
		// Byte by byte, since a blank line ends an event and `lines` leaves blank lines out.
		for try await byte in bytes {
			guard byte == UInt8(ascii: "\n") else {
				line.append(byte)
				continue
			}
			let text = String(decoding: line, as: UTF8.self)
			line.removeAll(keepingCapacity: true)
			guard let data = parser.feed(text) else { continue }
			// An event this build can't read is skipped; the next snapshot puts the transcript right.
			if let event = try? StreamEvent.decode(Data(data.utf8)) { yield(.event(event)) }
		}
	}
}
