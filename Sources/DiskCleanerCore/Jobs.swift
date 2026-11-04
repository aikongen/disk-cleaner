import Foundation

public actor JobStore {
    private let directory: URL
    private let capacityURL: URL
    public init(directory: URL, capacityURL: URL = URL(fileURLWithPath: "/")) { self.directory = directory; self.capacityURL = capacityURL }
    public func jobs() throws -> [CleanupJob] { try DiskFile(directory: directory, name: "jobs.json", fallback: JobLedger()).read { $0.jobs } }
    public func get(id: UUID) throws -> CleanupJob {
        guard let job = try jobs().first(where: { $0.id == id }) else { throw CoreError.missingJob }
        guard job.status == .queued && Date().timeIntervalSince(job.createdAt) > 60 else { return job }
        do { return try ledger { ledger in
            guard let index = ledger.jobs.firstIndex(where: { $0.id == id }) else { throw CoreError.missingJob }
            if ledger.jobs[index].status == .queued {
                ledger.jobs[index].status = .interrupted
                ledger.jobs[index].message = "Worker did not finish; outcome is unknown"
            }
            return ledger.jobs[index]
        } } catch InventoryOperationError.busy { return job }
    }
    public func enqueue(targetBytes: Int64, key: String, requester: String = "agent") async throws -> CleanupJob {
        while true {
            do { return try enqueueUnlocked(targetBytes: targetBytes, key: key, requester: requester) }
            catch InventoryOperationError.busy {
                try Task.checkCancellation()
                try await Task.sleep(for: .milliseconds(200))
            }
        }
    }
    private func enqueueUnlocked(targetBytes: Int64, key: String, requester: String) throws -> CleanupJob {
        guard targetBytes > 0, !key.isEmpty, key.utf8.count <= 256 else { throw CoreError.invalidRequest }
        return try ledger { ledger in
            if let prior = ledger.jobs.first(where: { $0.key == key }) {
                guard prior.targetBytes == targetBytes else { throw CoreError.idempotencyConflict }
                return prior
            }
            let job = CleanupJob(key: key, targetBytes: targetBytes, status: .queued, message: "Waiting for capacity check", requester: requester)
            ledger.jobs.append(job)
            return job
        }
    }
    public func request(targetBytes: Int64, requester: String = "Disk Cleaner") async throws -> CleanupJob {
        let job = try await enqueue(targetBytes: targetBytes, key: UUID().uuidString, requester: requester)
        return try await run(id: job.id)
    }
    public func run(id: UUID) async throws -> CleanupJob {
        while true {
            do { return try runUnlocked(id: id) }
            catch InventoryOperationError.busy {
                try Task.checkCancellation()
                try await Task.sleep(for: .milliseconds(200))
            }
        }
    }
    private func runUnlocked(id: UUID) throws -> CleanupJob {
        // Both operation and ledger locks cover this no-provider capacity check.
        try ledger { ledger in
            guard let index = ledger.jobs.firstIndex(where: { $0.id == id }) else { throw CoreError.missingJob }
            guard ledger.jobs[index].status == .queued else { return ledger.jobs[index] }
            if Date().timeIntervalSince(ledger.jobs[index].createdAt) > 60 {
                ledger.jobs[index].status = .interrupted
                ledger.jobs[index].message = "Worker did not finish; outcome is unknown"
                return ledger.jobs[index]
            }
            do {
                let available = try capacityAt(capacityURL).availableBytes
                ledger.jobs[index].beforeBytes = available
                ledger.jobs[index].afterBytes = available
                if available >= ledger.jobs[index].targetBytes {
                    ledger.jobs[index].status = .completed
                    ledger.jobs[index].message = "Requested available space already present; no cleanup performed"
                } else {
                    ledger.jobs[index].status = .insufficient
                    ledger.jobs[index].message = "No cleanup rule is enabled; more space is needed"
                }
            } catch {
                ledger.jobs[index].status = .failed
                ledger.jobs[index].message = "Could not measure available space: \(error.localizedDescription)"
            }
            return ledger.jobs[index]
        }
    }
    public func fail(id: UUID, reason: String) async throws {
        while true {
            do { try failUnlocked(id: id, reason: reason); return }
            catch InventoryOperationError.busy {
                try Task.checkCancellation()
                try await Task.sleep(for: .milliseconds(200))
            }
        }
    }
    private func failUnlocked(id: UUID, reason: String) throws {
        try ledger { ledger in
            guard let index = ledger.jobs.firstIndex(where: { $0.id == id }) else { throw CoreError.missingJob }
            if ledger.jobs[index].status == .queued { ledger.jobs[index].status = .failed; ledger.jobs[index].message = reason }
        }
    }
    private func ledger<T>(_ body: (inout JobLedger) throws -> T) throws -> T {
        try StoreOperationLock.withExclusive(directory: directory) {
            try DiskFile(directory: directory, name: "jobs.json", fallback: JobLedger()).locked(body)
        }
    }
}
