import Foundation

/// Turns messages into bytes and back, one JSON object per line.
///
/// TCP hands over a byte stream, not messages: a read can carry half a message
/// or three of them, so the decoder keeps whatever comes after the last newline
/// until the rest arrives. JSON never contains a raw newline, which is what
/// makes the delimiter safe.
struct RemoteControllerCodec {

    /// A peer that never sends a newline must not be able to grow the buffer
    /// without end. Well past the longest message we send, which is a hello
    /// carrying a device name.
    static let maxLineLength = 4096

    private var buffer = Data()

    static func encode(_ message: RemoteControllerMessage) -> Data? {
        guard var data = try? JSONEncoder().encode(message) else { return nil }
        data.append(UInt8(ascii: "\n"))
        return data
    }

    /// Appends the bytes just read and returns every message they completed.
    /// A line that does not decode is dropped rather than closing the link, a
    /// peer one version ahead may simply know a message we do not.
    mutating func decode(_ data: Data) -> [RemoteControllerMessage] {
        buffer.append(data)
        var messages: [RemoteControllerMessage] = []
        let decoder = JSONDecoder()

        while let newline = buffer.firstIndex(of: UInt8(ascii: "\n")) {
            let line = buffer[buffer.startIndex..<newline]
            buffer = Data(buffer[buffer.index(after: newline)...])
            guard let message = try? decoder.decode(RemoteControllerMessage.self, from: line) else { continue }
            messages.append(message)
        }

        if buffer.count > Self.maxLineLength {
            buffer.removeAll(keepingCapacity: false)
        }
        return messages
    }
}
