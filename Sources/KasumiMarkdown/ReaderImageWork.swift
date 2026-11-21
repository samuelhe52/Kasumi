import Foundation

/// One operation per key. A canceled waiter leaves immediately; the operation
/// is canceled when its last waiter leaves and cannot then publish cache state.
final class ReaderImageWork<Key: Hashable & Sendable, Value: Sendable>: @unchecked Sendable {
    enum Result: Sendable {
        case cached(Value)
        case loaded(Value)
    }

    private final class Flight {
        let id = UUID()
        let priority = Task.currentPriority
        let operation: @Sendable () async -> Value
        let publish: @Sendable (Value) -> Void
        var task: Task<Void, Never>?
        var waiters: [UUID: CheckedContinuation<Result?, Never>]

        init(
            operation: @escaping @Sendable () async -> Value, publish: @escaping @Sendable (Value) -> Void,
            waiter: UUID, continuation: CheckedContinuation<Result?, Never>
        ) {
            self.operation = operation
            self.publish = publish
            waiters = [waiter: continuation]
        }
    }

    private let lock = NSLock()
    private var flights: [Key: Flight] = [:]
    private var queued: [Key] = []
    private var running = 0
    private let limit: Int

    init(limit: Int = 4) { self.limit = limit }

    func run(
        _ key: Key, cached: @escaping @Sendable () -> Value?, operation: @escaping @Sendable () async -> Value,
        publish: @escaping @Sendable (Value) -> Void
    ) async -> Result? {
        let waiter = UUID()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                lock.withLock {
                    if Task.isCancelled {
                        continuation.resume(returning: nil)
                    } else if let value = cached() {
                        continuation.resume(returning: .cached(value))
                    } else if let flight = flights[key] {
                        flight.waiters[waiter] = continuation
                    } else {
                        let flight = Flight(
                            operation: operation, publish: publish, waiter: waiter, continuation: continuation)
                        flights[key] = flight
                        if running < limit {
                            start(flight, for: key)
                        } else {
                            queued.append(key)
                        }
                    }
                }
            }
        } onCancel: {
            self.cancel(waiter, for: key)
        }
    }

    private func start(_ flight: Flight, for key: Key) {
        let id = flight.id
        let operation = flight.operation
        running += 1
        flight.task = Task.detached(priority: flight.priority) {
            let result = await operation()
            self.finish(key, id: id, result: result)
        }
    }

    private func finish(_ key: Key, id: UUID, result: Value) {
        let flight: Flight? = lock.withLock {
            running -= 1
            let finished = flights[key]?.id == id ? flights.removeValue(forKey: key) : nil
            finished?.publish(result)
            if !queued.isEmpty {
                let next = queued.removeFirst()
                if let flight = flights[next] { start(flight, for: next) }
            }
            return finished
        }
        guard let flight else { return }
        for continuation in flight.waiters.values {
            continuation.resume(returning: .loaded(result))
        }
    }

    private func cancel(_ waiter: UUID, for key: Key) {
        let canceled: (CheckedContinuation<Result?, Never>?, Task<Void, Never>?) = lock.withLock {
            guard let flight = flights[key], let continuation = flight.waiters.removeValue(forKey: waiter)
            else { return (nil, nil) }
            guard flight.waiters.isEmpty else { return (continuation, nil) }
            flights.removeValue(forKey: key)
            if flight.task == nil, let index = queued.firstIndex(of: key) { queued.remove(at: index) }
            return (continuation, flight.task)
        }
        canceled.1?.cancel()
        canceled.0?.resume(returning: nil)
    }
}

/// Strict entry and byte limits. Drawing reads without touching recency or
/// performing any I/O. Work admission touches recency instead.
final class ReaderImageLRU<Key: Hashable & Sendable, Value: Sendable>: @unchecked Sendable {
    private struct Entry {
        let value: Value
        let cost: Int
    }

    private let lock = NSLock()
    private let countLimit: Int
    private let byteLimit: Int
    private var entries: [Key: Entry] = [:]
    private var recency: [Key] = []
    private var totalCost = 0

    init(countLimit: Int, byteLimit: Int = 0) {
        self.countLimit = countLimit
        self.byteLimit = byteLimit
    }

    func value(for key: Key) -> Value? { lock.withLock { entries[key]?.value } }

    func touch(_ key: Key) -> Value? {
        lock.withLock {
            guard let entry = entries[key], let index = recency.firstIndex(of: key) else { return nil }
            recency.append(recency.remove(at: index))
            return entry.value
        }
    }

    func snapshot() -> [Key: Value] { lock.withLock { entries.mapValues(\.value) } }

    func insert(_ value: Value, for key: Key, cost: Int = 0) {
        guard cost <= byteLimit else { return }
        lock.withLock {
            if let replaced = entries.removeValue(forKey: key), let index = recency.firstIndex(of: key) {
                totalCost -= replaced.cost
                recency.remove(at: index)
            }
            while totalCost + cost > byteLimit || recency.count >= countLimit {
                totalCost -= entries.removeValue(forKey: recency.removeFirst())!.cost
            }
            entries[key] = Entry(value: value, cost: cost)
            totalCost += cost
            recency.append(key)
        }
    }
}
