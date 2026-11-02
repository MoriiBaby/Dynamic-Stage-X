import Foundation

/// Owns one synchronous, prompt cleanup action. Thread-safe; cancellation is exactly once.
public final class DXCancellation {
    private let lock = NSLock()
    private var action: (() -> Void)?

    public init(_ action: @escaping () -> Void) {
        self.action = action
    }

    /// True once cleanup has been claimed, not necessarily completed on a different thread.
    public var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return action == nil
    }

    @discardableResult
    public func cancel() -> Bool {
        lock.lock()
        let pending = action
        action = nil
        lock.unlock()
        guard let cleanup = pending else { return false }
        // Never execute arbitrary client code under the lock; cancellation may reenter.
        cleanup()
        return true
    }

    deinit { cancel() }
}

/// Bounded, terminal ownership scope. Main-queue cleanup must be called from the main queue.
/// The bag itself is thread-safe, but does not move callbacks to another queue.
public final class DXResourceBag {
    public static let maximumCapacity = 256
    public let capacity: Int
    private let lock = NSLock()
    private var resources: [DXCancellation] = []
    private var closed = false

    public init(capacity: Int = 64) {
        self.capacity = min(max(capacity, 0), Self.maximumCapacity)
    }

    /// Number of retained leases; externally cancelled leases remain until removed/closed.
    public var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return resources.count
    }

    public var isClosed: Bool {
        lock.lock()
        defer { lock.unlock() }
        return closed
    }

    /// Rejected ownership is cancelled immediately, not silently leaked.
    @discardableResult
    public func insert(_ resource: DXCancellation) -> Bool {
        lock.lock()
        if !closed && !resource.isCancelled {
            if resources.contains(where: { $0 === resource }) {
                lock.unlock()
                return true
            }
            if resources.count < capacity {
                resources.append(resource)
                lock.unlock()
                return true
            }
        }
        lock.unlock()
        resource.cancel()
        return false
    }

    @discardableResult
    public func removeAndCancel(_ resource: DXCancellation) -> Bool {
        lock.lock()
        guard let index = resources.firstIndex(where: { $0 === resource }) else {
            lock.unlock()
            return false
        }
        let owned = resources.remove(at: index)
        lock.unlock()
        owned.cancel()
        return true
    }

    @discardableResult
    public func close() -> Bool {
        lock.lock()
        guard !closed else {
            lock.unlock()
            return false
        }
        closed = true
        let owned = resources
        resources.removeAll(keepingCapacity: false)
        lock.unlock()
        for resource in owned.reversed() { resource.cancel() }
        return true
    }

    deinit { close() }
}
