import Foundation
import XCTest
import DynamicStageXCore

private final class DXTestCounter {
    private let lock = NSLock()
    private var count = 0
    func increment() {
        lock.lock()
        count += 1
        lock.unlock()
    }
    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }
}

final class DXLifetimeTests: XCTestCase {
    func testCancellationExactlyOnceIncludingReentry() {
        var calls = 0
        var cancellation: DXCancellation?
        cancellation = DXCancellation {
            calls += 1
            XCTAssertTrue(cancellation?.isCancelled == true)
            XCTAssertFalse(cancellation?.cancel() == true)
        }
        XCTAssertFalse(cancellation?.isCancelled == true)
        XCTAssertTrue(cancellation?.cancel() == true)
        XCTAssertFalse(cancellation?.cancel() == true)
        cancellation = nil
        XCTAssertEqual(calls, 1)
    }

    func testConcurrentCancellationClaimsOnlyOneAction() {
        let counter = DXTestCounter()
        let cancellation = DXCancellation { counter.increment() }
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 8
        for _ in 0..<100 { queue.addOperation { _ = cancellation.cancel() } }
        queue.waitUntilAllOperationsAreFinished()
        XCTAssertEqual(counter.value, 1)
        XCTAssertTrue(cancellation.isCancelled)
    }

    func testBoundedOwnershipRejectsOverflowAndClosesInReverseOrder() {
        var calls: [Int] = []
        let bag = DXResourceBag(capacity: 2)
        let one = DXCancellation { calls.append(1) }
        let two = DXCancellation { calls.append(2) }
        let rejected = DXCancellation { calls.append(3) }
        XCTAssertTrue(bag.insert(one))
        XCTAssertTrue(bag.insert(one))
        XCTAssertEqual(bag.count, 1)
        XCTAssertTrue(bag.insert(two))
        XCTAssertFalse(bag.insert(rejected))
        XCTAssertTrue(rejected.isCancelled)
        XCTAssertEqual(calls, [3])
        XCTAssertEqual(bag.count, 2)
        XCTAssertTrue(bag.close())
        XCTAssertEqual(calls, [3, 2, 1])
        XCTAssertEqual(bag.count, 0)
        XCTAssertTrue(bag.isClosed)
        XCTAssertFalse(bag.close())
        XCTAssertFalse(bag.insert(DXCancellation { calls.append(4) }))
        XCTAssertEqual(calls, [3, 2, 1, 4])
    }

    func testRemoveCancelsOnlyOwnedResourceAndReturnsCapacity() {
        var calls = 0
        let bag = DXResourceBag(capacity: 1)
        let one = DXCancellation { calls += 1 }
        let other = DXCancellation { calls += 10 }
        XCTAssertTrue(bag.insert(one))
        XCTAssertFalse(bag.removeAndCancel(other))
        XCTAssertFalse(other.isCancelled)
        XCTAssertTrue(bag.removeAndCancel(one))
        XCTAssertEqual(calls, 1)
        XCTAssertFalse(bag.removeAndCancel(one))
        XCTAssertTrue(bag.insert(other))
        XCTAssertTrue(bag.close())
        XCTAssertEqual(calls, 11)
    }

    func testCloseClearsOwnershipBeforeReentrantCleanup() {
        let bag = DXResourceBag()
        var calls = 0
        let cancellation = DXCancellation {
            XCTAssertTrue(bag.isClosed)
            XCTAssertEqual(bag.count, 0)
            XCTAssertFalse(bag.close())
            XCTAssertFalse(bag.insert(DXCancellation { calls += 1 }))
            calls += 1
        }
        XCTAssertTrue(bag.insert(cancellation))
        XCTAssertTrue(bag.close())
        XCTAssertEqual(calls, 2)
    }

    func testConcurrentInsertAndCloseDoNotLoseCleanup() {
        let bag = DXResourceBag(capacity: 8)
        let counter = DXTestCounter()
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 8
        for _ in 0..<100 {
            queue.addOperation { _ = bag.insert(DXCancellation { counter.increment() }) }
        }
        queue.addOperation { _ = bag.close() }
        queue.waitUntilAllOperationsAreFinished()
        bag.close()
        XCTAssertEqual(counter.value, 100)
        XCTAssertEqual(bag.count, 0)
    }

    func testDeinitCancellationAndCapacityClamping() {
        var calls = 0
        var lease: DXCancellation? = DXCancellation { calls += 1 }
        XCTAssertNotNil(lease)
        lease = nil
        XCTAssertEqual(calls, 1)
        var bag: DXResourceBag? = DXResourceBag()
        XCTAssertTrue(bag?.insert(DXCancellation { calls += 1 }) == true)
        bag = nil
        XCTAssertEqual(calls, 2)
        XCTAssertEqual(DXResourceBag(capacity: Int.max).capacity, DXResourceBag.maximumCapacity)
        let empty = DXResourceBag(capacity: -1)
        XCTAssertEqual(empty.capacity, 0)
        XCTAssertFalse(empty.insert(DXCancellation { calls += 1 }))
        XCTAssertEqual(calls, 3)
    }
}
