import Foundation
import Network

/// NOTE4 broadcasts a tiny datagram after a button action. The Mac performs
/// one status read in response instead of polling the device while idle.
final class DeviceWakeListener {
    private let queue = DispatchQueue(label: "ink-reminders.note4-wake")
    private var listener: NWListener?
    private let onWake: @Sendable () -> Void

    init(onWake: @escaping @Sendable () -> Void) {
        self.onWake = onWake
    }

    func start() {
        guard listener == nil else { return }
        do {
            let listener = try NWListener(using: .udp, on: 48271)
            listener.newConnectionHandler = { [weak self] connection in
                guard let self else { return }
                connection.start(queue: self.queue)
                self.receive(on: connection)
            }
            listener.stateUpdateHandler = { [weak self] state in
                if case .failed = state { self?.listener = nil }
            }
            listener.start(queue: queue)
            self.listener = listener
        } catch {
            listener = nil
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    private func receive(on connection: NWConnection) {
        connection.receiveMessage { [weak self] data, _, _, _ in
            defer { connection.cancel() }
            guard let self, let data,
                  String(data: data, encoding: .utf8)?.hasPrefix("EINK_NOTE4_EVENT") == true else { return }
            self.onWake()
        }
    }
}
