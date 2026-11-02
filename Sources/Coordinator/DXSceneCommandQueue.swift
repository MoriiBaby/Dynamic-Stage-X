import Foundation
import CoreGraphics

/// One private system mutation at a time. Pending geometry updates coalesce by real Scene
/// identity; a superseded caller is still completed once so no DispatchGroup is stranded.
final class DXSceneCommandQueue {
    static let supersededDomain = "com.tsangbaby.dynamicstagex.command"
    private struct Command {
        let key: String
        let run: (@escaping (Error?) -> Void) -> Void
        let completion: (Error?) -> Void
    }
    private var pending: [Command] = []
    private var running = false
    private var suspended = false

    func resume() {
        dispatchPrecondition(condition: .onQueue(.main))
        suspended = false
        drain()
    }

    func cancelPending() {
        dispatchPrecondition(condition: .onQueue(.main))
        suspended = true
        let abandoned = pending
        pending.removeAll()
        abandoned.forEach { $0.completion(Self.superseded()) }
    }

    func apply(frame: CGRect, to handle: DXSystemSceneHandle, bridge: DXSystemBridge,
               completion: @escaping (Error?) -> Void) {
        enqueue(key: "geometry/" + handle.sceneIdentifier, run: { done in
            bridge.apply(frame: frame, to: handle) { done($0) }
        }, completion: completion)
    }

    func focus(_ handle: DXSystemSceneHandle, bridge: DXSystemBridge,
               completion: @escaping (Error?) -> Void) {
        enqueue(key: "focus", run: { done in bridge.focus(handle) { done($0) } }, completion: completion)
    }

    private func enqueue(key: String, run: @escaping (@escaping (Error?) -> Void) -> Void,
                         completion: @escaping (Error?) -> Void) {
        dispatchPrecondition(condition: .onQueue(.main))
        guard !suspended else { completion(Self.superseded()); return }
        let replaced = pending.filter { $0.key == key }
        pending.removeAll { $0.key == key }
        let command = Command(key: key, run: run, completion: completion)
        guard pending.count < 8 else { completion(Self.superseded()); return }
        pending.append(command)
        replaced.forEach { $0.completion(Self.superseded()) }
        drain()
    }

    private func drain() {
        guard !running, !suspended, !pending.isEmpty else { return }
        running = true
        let command = pending.removeFirst()
        var completed = false
        command.run { [weak self] error in
            guard let self = self, !completed else { return }
            completed = true
            self.running = false
            command.completion(error)
            self.drain()
        }
    }

    private static func superseded() -> NSError {
        NSError(domain: supersededDomain, code: 1,
                userInfo: [NSLocalizedDescriptionKey: "操作已被更新的会话状态替代"])
    }
}
