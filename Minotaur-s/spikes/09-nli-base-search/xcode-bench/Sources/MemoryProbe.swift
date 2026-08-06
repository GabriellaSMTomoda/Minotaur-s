import Foundation

final class MemoryProbe {
    struct Sample {
        var residentMB: Double
        var footprintMB: Double
    }

    private var thread: Thread?
    private let lock = NSLock()
    private var peak = Sample(residentMB: 0, footprintMB: 0)
    private var running = false
    private let intervalMicroseconds: UInt32 = 3_000

    static func current() -> Sample {
        Sample(residentMB: residentMB(), footprintMB: footprintMB())
    }

    static func residentMB() -> Double {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(
            MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size)
        let status: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        guard status == KERN_SUCCESS else { return 0 }
        return Double(info.resident_size) / 1024 / 1024
    }

    static func footprintMB() -> Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let status: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        guard status == KERN_SUCCESS else { return 0 }
        return Double(info.phys_footprint) / 1024 / 1024
    }

    func start() {
        running = true
        let worker = Thread { [weak self] in
            guard let self else { return }
            while self.running {
                self.record(Self.current())
                usleep(self.intervalMicroseconds)
            }
        }
        worker.qualityOfService = .userInitiated
        worker.start()
        thread = worker
    }

    func stop() {
        running = false
        thread = nil
    }

    private func record(_ sample: Sample) {
        lock.lock()
        peak.residentMB = max(peak.residentMB, sample.residentMB)
        peak.footprintMB = max(peak.footprintMB, sample.footprintMB)
        lock.unlock()
    }

    var peakSample: Sample {
        lock.lock()
        defer { lock.unlock() }
        return peak
    }

    func resetPeak() {
        let now = Self.current()
        lock.lock()
        peak = now
        lock.unlock()
    }
}
