import Foundation

/// Amostrador de memória do processo (NF-06).
///
/// Duas métricas, de propósito:
///
/// - `resident` (`mach_task_basic_info.resident_size`) é a que o Spike 7 usou para
///   reportar os 643 MB. Está aqui para que os números sejam comparáveis com aquele
///   relatório, e só por isso.
/// - `footprint` (`task_vm_info.phys_footprint`) é a que o iOS de fato cobra: é ela
///   que o jetsam olha para decidir se mata o app. Modelo Core ML entra por mapeamento
///   de arquivo, então `resident` pode subir e descer conforme o kernel expulsa
///   páginas limpas sem que a pressão real mude. **O veredito do gate sai do footprint.**
///
/// A amostragem roda numa thread própria porque o pico pode acontecer no meio de uma
/// `predict()` — medir só antes e depois perderia exatamente o instante que interessa.
final class MemoryProbe {

    struct Sample {
        var residentMB: Double
        var footprintMB: Double
    }

    private var thread: Thread?
    private let lock = NSLock()
    private var peak = Sample(residentMB: 0, footprintMB: 0)
    private var running = false

    /// Intervalo de amostragem. 3 ms é curto o bastante para pegar o pico de uma
    /// predição de 40 ms e barato o bastante para não competir com o modelo.
    private let intervalMicroseconds: UInt32 = 3_000

    static func current() -> Sample {
        Sample(residentMB: residentMB(), footprintMB: footprintMB())
    }

    static func residentMB() -> Double {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(
            MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size)
        let result: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }
        return Double(info.resident_size) / (1024 * 1024)
    }

    static func footprintMB() -> Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }
        return Double(info.phys_footprint) / (1024 * 1024)
    }

    func start() {
        running = true
        let thread = Thread { [weak self] in
            guard let self else { return }
            while self.running {
                self.record(Self.current())
                usleep(self.intervalMicroseconds)
            }
        }
        thread.qualityOfService = .userInitiated
        thread.start()
        self.thread = thread
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

    /// Pico desde o último `resetPeak()`.
    var peakSample: Sample {
        lock.lock()
        defer { lock.unlock() }
        return peak
    }

    /// Zera o acumulador para medir a próxima etapa isoladamente.
    /// Reinicia no valor corrente, não em zero — o pico de uma etapa nunca é menor
    /// que a memória com que ela começou.
    func resetPeak() {
        let now = Self.current()
        lock.lock()
        peak = now
        lock.unlock()
    }
}
