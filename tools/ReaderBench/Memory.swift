import Darwin
import Foundation

enum BenchmarkMemory {
    static func read() throws -> [String: UInt64] {
        var info = task_vm_info_data_t()
        let capacity = MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size
        var count = mach_msg_type_number_t(capacity)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: capacity) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        let minimumBytes =
            MemoryLayout<task_vm_info_data_t>.offset(of: \.ledger_phys_footprint_peak)! + MemoryLayout<Int64>.size
        guard result == KERN_SUCCESS, Int(count) * MemoryLayout<integer_t>.size >= minimumBytes else {
            throw NSError(domain: "BenchmarkMemory", code: Int(result))
        }
        var usage = rusage()
        guard getrusage(RUSAGE_SELF, &usage) == 0 else { throw CocoaError(.fileReadUnknown) }
        return [
            "physicalFootprintBytes": info.phys_footprint,
            "peakPhysicalFootprintBytes": UInt64(max(0, info.ledger_phys_footprint_peak)),
            "residentBytes": info.resident_size,
            "peakResidentBytes": UInt64(usage.ru_maxrss)
        ]
    }
}
