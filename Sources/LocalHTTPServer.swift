import Foundation
import Darwin

struct HTTPReply {
    let code: Int
    let body: String
}

final class LocalHTTPServer {
    private let port: UInt16
    private let router: (HTTPRequestLine) -> HTTPReply
    private var serverSocket: Int32 = -1
    private let queue = DispatchQueue(label: "dev.touchbarkitt.http", qos: .utility)

    init(port: UInt16, router: @escaping (HTTPRequestLine) -> HTTPReply) {
        self.port = port
        self.router = router
    }

    func start() throws {
        let socketFile = socket(AF_INET, SOCK_STREAM, 0)
        guard socketFile >= 0 else { throw socketError("No se pudo crear el socket") }

        var reuse: Int32 = 1
        setsockopt(socketFile, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = in_port_t(port).bigEndian
        address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))

        let bindResult = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { addressPointer in
                Darwin.bind(socketFile, addressPointer, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0 else {
            Darwin.close(socketFile)
            throw socketError("No se pudo utilizar 127.0.0.1:\(port)")
        }
        guard listen(socketFile, 16) == 0 else {
            Darwin.close(socketFile)
            throw socketError("No se pudo escuchar el puerto")
        }

        serverSocket = socketFile
        queue.async { [weak self] in self?.acceptConnections() }
    }

    func stop() {
        guard serverSocket >= 0 else { return }
        let previous = serverSocket
        serverSocket = -1
        shutdown(previous, SHUT_RDWR)
        Darwin.close(previous)
    }

    private func acceptConnections() {
        while serverSocket >= 0 {
            let client = accept(serverSocket, nil, nil)
            if client < 0 { break }
            DispatchQueue.global(qos: .utility).async { [weak self] in
                self?.handle(client)
                Darwin.close(client)
            }
        }
    }

    private func handle(_ socketFile: Int32) {
        var buffer = [UInt8](repeating: 0, count: 8192)
        let bytes = buffer.withUnsafeMutableBytes { data in
            Darwin.read(socketFile, data.baseAddress, data.count)
        }
        guard bytes > 0 else { return }
        let requestText = String(decoding: buffer.prefix(bytes), as: UTF8.self)
        let firstLine = requestText.components(separatedBy: "\r\n").first ?? ""
        let reply: HTTPReply

        if let request = HTTPRequestLine.parse(firstLine) {
            var routed: HTTPReply?
            let routeRequest = router
            DispatchQueue.main.sync { routed = routeRequest(request) }
            reply = routed ?? HTTPReply(code: 500, body: "{\"error\":\"internal\"}")
        } else {
            reply = HTTPReply(code: 400, body: "{\"error\":\"bad_request\"}")
        }

        let reason = reply.code == 200 ? "OK" : (reply.code == 404 ? "Not Found" : "Bad Request")
        let responseBody = Data(reply.body.utf8)
        let header = "HTTP/1.1 \(reply.code) \(reason)\r\nContent-Type: application/json; charset=utf-8\r\nContent-Length: \(responseBody.count)\r\nConnection: close\r\nCache-Control: no-store\r\n\r\n"
        let data = Data(header.utf8) + responseBody
        data.withUnsafeBytes { bytes in
            guard let base = bytes.baseAddress else { return }
            var sent = 0
            while sent < data.count {
                let count = Darwin.write(socketFile, base.advanced(by: sent), data.count - sent)
                if count <= 0 { break }
                sent += count
            }
        }
    }

    private func socketError(_ message: String) -> Error {
        NSError(domain: "TouchBarKITT", code: Int(errno), userInfo: [NSLocalizedDescriptionKey: message])
    }
}
