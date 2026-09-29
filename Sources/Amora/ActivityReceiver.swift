import Darwin
import Foundation

@MainActor
final class ActivityReceiver {
    private struct Client {
        var buffer = Data()
        let deadline: Date
    }

    private var listener: Int32 = -1
    private var lockDescriptor: Int32 = -1
    private var clients: [Int32: Client] = [:]
    private var timer: Timer?
    private var socketPath: String?
    private let directory: URL
    /// How long one hook connection may stay open. A hook sends its single line at once.
    private let clientTimeout: TimeInterval
    private let receive: (ActivityEvent) -> Void

    init(
        directory: URL = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Application Support/Pet", directoryHint: .isDirectory),
        clientTimeout: TimeInterval = 1,
        receive: @escaping (ActivityEvent) -> Void
    ) {
        self.directory = directory
        self.clientTimeout = clientTimeout
        self.receive = receive
    }

    func start() throws {
        guard listener == -1 else { return }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let path = directory.appending(path: "pet.sock").path
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        let bytes = Array(path.utf8CString)
        guard bytes.count <= MemoryLayout.size(ofValue: address.sun_path) else {
            throw POSIXError(.ENAMETOOLONG)
        }
        withUnsafeMutableBytes(of: &address.sun_path) { target in
            target.copyBytes(from: bytes.map { UInt8(bitPattern: $0) })
        }
        let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else { throw error() }
        let lock = open(directory.appending(path: "pet.lock").path, O_CREAT | O_RDWR | O_NOFOLLOW, S_IRUSR | S_IWUSR)
        guard lock >= 0 else {
            let failure = error()
            close(descriptor)
            throw failure
        }
        var ownsPath = false
        do {
            guard flock(lock, LOCK_EX | LOCK_NB) == 0 else { throw error() }
            var metadata = stat()
            if lstat(path, &metadata) == 0 {
                guard metadata.st_mode & S_IFMT == S_IFSOCK, metadata.st_uid == getuid() else {
                    throw POSIXError(.EEXIST)
                }
                guard unlink(path) == 0 else { throw error() }
            } else if errno != ENOENT {
                throw error()
            }
            guard fcntl(descriptor, F_SETFL, O_NONBLOCK) != -1 else { throw error() }
            let result = withUnsafePointer(to: &address) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    Darwin.bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
                }
            }
            guard result == 0 else { throw error() }
            ownsPath = true
            guard chmod(path, S_IRUSR | S_IWUSR) == 0 else { throw error() }
            guard listen(descriptor, 16) == 0 else { throw error() }
            listener = descriptor
            lockDescriptor = lock
            socketPath = path
            timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.poll() }
            }
        } catch {
            close(descriptor)
            if ownsPath { unlink(path) }
            close(lock)
            throw error
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        for descriptor in clients.keys { close(descriptor) }
        clients.removeAll()
        if listener >= 0 { close(listener) }
        listener = -1
        if let socketPath { unlink(socketPath) }
        socketPath = nil
        if lockDescriptor >= 0 { close(lockDescriptor) }
        lockDescriptor = -1
    }

    private func poll() {
        for _ in 0..<16 where clients.count < 16 {
            let descriptor = accept(listener, nil, nil)
            guard descriptor >= 0 else { break }
            guard fcntl(descriptor, F_SETFL, O_NONBLOCK) != -1 else {
                close(descriptor)
                continue
            }
            clients[descriptor] = Client(deadline: Date().addingTimeInterval(clientTimeout))
        }
        for descriptor in clients.keys.sorted() {
            guard var client = clients[descriptor] else { continue }
            var bytes = [UInt8](repeating: 0, count: 1024)
            let count = read(descriptor, &bytes, bytes.count)
            if count > 0 {
                client.buffer.append(contentsOf: bytes.prefix(count))
                while let newline = client.buffer.firstIndex(of: 10) {
                    let line = Data(client.buffer[..<newline])
                    client.buffer.removeSubrange(...newline)
                    if line.count <= 1024, let event = ActivityEvent.decode(line) {
                        receive(event)
                    }
                }
            }
            let failed = count < 0 && errno != EAGAIN && errno != EWOULDBLOCK && errno != EINTR
            if count == 0 || failed || client.buffer.count > 1024 || client.deadline < Date() {
                close(descriptor)
                clients.removeValue(forKey: descriptor)
            } else {
                clients[descriptor] = client
            }
        }
    }

    private func error() -> POSIXError {
        POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
}
