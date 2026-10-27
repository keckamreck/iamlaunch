import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

#if canImport(Darwin)
let unixStreamSocketType = SOCK_STREAM
#else
let unixStreamSocketType = Int32(SOCK_STREAM.rawValue)
#endif

/// A minimal blocking client for a Unix domain stream socket.
final class UnixSocket {
    private(set) var fileDescriptor: Int32

    init(fileDescriptor: Int32) {
        self.fileDescriptor = fileDescriptor
        #if canImport(Darwin)
        // Report writes to a closed socket as errors instead of killing the app with SIGPIPE.
        var on: Int32 = 1
        setsockopt(fileDescriptor, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
        #endif
    }

    deinit {
        close()
    }

    static func connect(path: String) throws -> UnixSocket {
        var address = try makeAddress(path: path)
        let fd = systemSocket()
        guard fd >= 0 else { throw IPCError.system("socket: \(errnoDescription())") }
        let socket = UnixSocket(fileDescriptor: fd)
        let result = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                systemConnect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard result == 0 else { throw IPCError.system("connect \(path): \(errnoDescription())") }
        return socket
    }

    static func makeAddress(path: String) throws -> sockaddr_un {
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8)
        guard bytes.count < MemoryLayout.size(ofValue: address.sun_path) else {
            throw IPCError.system("Socket-Pfad zu lang: \(path)")
        }
        withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: bytes) }
        #if canImport(Darwin)
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        #endif
        return address
    }

    func write(_ data: Data) throws {
        try data.withUnsafeBytes { (buffer: UnsafeRawBufferPointer) in
            guard let base = buffer.baseAddress else { return }
            var offset = 0
            while offset < buffer.count {
                let written = systemSend(fileDescriptor, base + offset, buffer.count - offset)
                if written < 0 {
                    if errno == EINTR { continue }
                    throw IPCError.connectionClosed
                }
                offset += written
            }
        }
    }

    /// Returns the bytes that are available, or empty data once the peer has closed the socket.
    func read(maxLength: Int = 64 * 1024) throws -> Data {
        var buffer = [UInt8](repeating: 0, count: maxLength)
        while true {
            let count = buffer.withUnsafeMutableBytes { systemRead(fileDescriptor, $0.baseAddress!, maxLength) }
            if count < 0 {
                if errno == EINTR { continue }
                throw IPCError.connectionClosed
            }
            return Data(buffer[0..<count])
        }
    }

    /// Waits until data (or end of stream) can be read; returns false on timeout.
    func waitUntilReadable(timeout: TimeInterval) throws -> Bool {
        var descriptor = pollfd(fd: fileDescriptor, events: Int16(POLLIN), revents: 0)
        let milliseconds = Int32(max(0, min(timeout, 60)) * 1000)
        while true {
            let result = systemPoll(&descriptor, milliseconds)
            if result < 0 {
                if errno == EINTR { continue }
                throw IPCError.system("poll: \(errnoDescription())")
            }
            return result > 0
        }
    }

    func close() {
        guard fileDescriptor >= 0 else { return }
        systemClose(fileDescriptor)
        fileDescriptor = -1
    }
}

// The system calls live at file scope so they don't clash with the
// methods of the same name on UnixSocket.

func errnoDescription() -> String {
    String(cString: strerror(errno))
}

private func systemSocket() -> Int32 {
    socket(AF_UNIX, unixStreamSocketType, 0)
}

private func systemConnect(_ fd: Int32, _ address: UnsafePointer<sockaddr>, _ length: socklen_t) -> Int32 {
    connect(fd, address, length)
}

private func systemSend(_ fd: Int32, _ bytes: UnsafeRawPointer, _ count: Int) -> Int {
    #if canImport(Darwin)
    return send(fd, bytes, count, 0)
    #else
    return send(fd, bytes, count, Int32(MSG_NOSIGNAL))
    #endif
}

private func systemRead(_ fd: Int32, _ bytes: UnsafeMutableRawPointer, _ count: Int) -> Int {
    recv(fd, bytes, count, 0)
}

private func systemPoll(_ descriptor: UnsafeMutablePointer<pollfd>, _ timeout: Int32) -> Int32 {
    poll(descriptor, 1, timeout)
}

private func systemClose(_ fd: Int32) {
    _ = close(fd)
}
