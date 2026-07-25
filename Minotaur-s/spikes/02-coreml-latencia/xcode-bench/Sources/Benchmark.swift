import CoreML
import Foundation

/// SPIKE 2c — harness estendido: além de medir latência/RAM, VERIFICA se os
/// logits produzidos no device batem com a referência PyTorch (do manifest).
/// "Converte sem erro" != "executa correto" — este é o gate do Filtro 2.

/// Especificação de um candidato NLI, lida de manifest.json (gerado por
/// convert_and_reference.py). Campos opcionais cobrem candidatos que não
/// converteram.
struct ModelSpec: Decodable {
    let short: String
    let id: String
    let converts: Bool
    let int8_mb: Double?
    let id2label: [String: String]?
    let input_ids: [Int]?
    let attention_mask: [Int]?
    let seq_len: Int?
    let pytorch_logits: [Double]?
}

struct Manifest: Decodable {
    let models: [ModelSpec]
}

/// Resultado de uma medição + verificação de correção de um candidato.
struct BenchResult: Identifiable {
    let id = UUID()
    let model: String
    let units: String
    let loaded: Bool
    let ran: Bool
    let error: String?
    // correção
    let logits: [Double]
    let cosVsRef: Double
    let argmaxMatch: Bool
    let expectedArgmax: Int
    let gotArgmax: Int
    // latência
    let seqLen: Int
    let runs: Int
    let meanMs: Double
    let medianMs: Double
    let minMs: Double
    let maxMs: Double
    // memória
    let ramBeforeMB: Double
    let ramPeakMB: Double
}

/// Memória residente do processo (MB) via `mach_task_basic_info` (NF-06).
func currentResidentMemoryMB() -> Double {
    var info = mach_task_basic_info()
    var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size)
    let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
        }
    }
    guard kerr == KERN_SUCCESS else { return 0 }
    return Double(info.resident_size) / (1024 * 1024)
}

func argmax(_ a: [Double]) -> Int {
    guard var best = a.first else { return -1 }
    var idx = 0
    for (i, v) in a.enumerated() where v > best { best = v; idx = i }
    return idx
}

func cosine(_ a: [Double], _ b: [Double]) -> Double {
    guard a.count == b.count, !a.isEmpty else { return .nan }
    var dot = 0.0, na = 0.0, nb = 0.0
    for i in 0..<a.count { dot += a[i]*b[i]; na += a[i]*a[i]; nb += b[i]*b[i] }
    return dot / (sqrt(na)*sqrt(nb) + 1e-9)
}

enum Benchmark {

    static func loadManifest() -> Manifest? {
        guard let url = Bundle.main.url(forResource: "manifest", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Manifest.self, from: data)
    }

    static func loadModel(baseName: String, computeUnits: MLComputeUnits) throws -> MLModel {
        let cfg = MLModelConfiguration()
        cfg.computeUnits = computeUnits
        if let url = Bundle.main.url(forResource: baseName, withExtension: "mlmodelc") {
            return try MLModel(contentsOf: url, configuration: cfg)
        }
        if let url = Bundle.main.url(forResource: baseName, withExtension: "mlpackage") {
            let compiled = try MLModel.compileModel(at: url)
            return try MLModel(contentsOf: compiled, configuration: cfg)
        }
        throw NSError(domain: "bench", code: 404, userInfo: [NSLocalizedDescriptionKey:
            "Modelo \(baseName) não encontrado no bundle."])
    }

    static func makeInput(ids: [Int], mask: [Int]) throws -> MLDictionaryFeatureProvider {
        let n = ids.count
        let idsArr = try MLMultiArray(shape: [1, NSNumber(value: n)], dataType: .int32)
        let maskArr = try MLMultiArray(shape: [1, NSNumber(value: n)], dataType: .int32)
        for i in 0..<n {
            idsArr[i] = NSNumber(value: Int32(ids[i]))
            maskArr[i] = NSNumber(value: Int32(mask[i]))
        }
        return try MLDictionaryFeatureProvider(dictionary: [
            "input_ids": MLFeatureValue(multiArray: idsArr),
            "attention_mask": MLFeatureValue(multiArray: maskArr),
        ])
    }

    /// Extrai os logits (Double) da saída "logits" do modelo.
    static func extractLogits(_ out: MLFeatureProvider) -> [Double] {
        guard let fv = out.featureValue(for: "logits"),
              let arr = fv.multiArrayValue else { return [] }
        var v: [Double] = []
        v.reserveCapacity(arr.count)
        for i in 0..<arr.count { v.append(arr[i].doubleValue) }
        return v
    }

    /// Roda 1 predição de correção (logits vs ref) + N predições cronometradas.
    static func run(spec: ModelSpec, units: MLComputeUnits, unitsLabel: String,
                    runs: Int = 50, warmup: Int = 5) -> BenchResult {
        let ramBefore = currentResidentMemoryMB()
        var ramPeak = ramBefore
        let ref = spec.pytorch_logits ?? []
        let expected = ref.isEmpty ? -1 : argmax(ref)

        func fail(_ stage: String, _ err: Error, loaded: Bool) -> BenchResult {
            BenchResult(model: spec.short, units: unitsLabel, loaded: loaded, ran: false,
                        error: "\(stage): \(err)", logits: [], cosVsRef: .nan,
                        argmaxMatch: false, expectedArgmax: expected, gotArgmax: -1,
                        seqLen: spec.seq_len ?? 0, runs: 0, meanMs: 0, medianMs: 0,
                        minMs: 0, maxMs: 0, ramBeforeMB: ramBefore, ramPeakMB: ramPeak)
        }

        let model: MLModel
        do { model = try loadModel(baseName: "\(spec.short)_int8", computeUnits: units) }
        catch { return fail("load", error, loaded: false) }

        guard let ids = spec.input_ids, let mask = spec.attention_mask else {
            return fail("input", NSError(domain: "bench", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "sem input no manifest"]), loaded: true)
        }

        let input: MLDictionaryFeatureProvider
        do { input = try makeInput(ids: ids, mask: mask) }
        catch { return fail("makeInput", error, loaded: true) }
        ramPeak = max(ramPeak, currentResidentMemoryMB())

        // Predição de CORREÇÃO (a que pode crashar / falhar em runtime).
        let logits: [Double]
        do {
            let out = try model.prediction(from: input)
            logits = extractLogits(out)
            ramPeak = max(ramPeak, currentResidentMemoryMB())
        } catch { return fail("predict", error, loaded: true) }

        let got = logits.isEmpty ? -1 : argmax(logits)
        let cos = (ref.count == logits.count && !ref.isEmpty) ? cosine(logits, ref) : .nan
        let match = (expected >= 0 && expected == got)

        // Latência (só se a predição de correção rodou).
        for _ in 0..<warmup {
            _ = try? model.prediction(from: input)
            ramPeak = max(ramPeak, currentResidentMemoryMB())
        }
        var times: [Double] = []
        times.reserveCapacity(runs)
        for _ in 0..<runs {
            let t0 = DispatchTime.now().uptimeNanoseconds
            _ = try? model.prediction(from: input)
            let t1 = DispatchTime.now().uptimeNanoseconds
            times.append(Double(t1 - t0) / 1_000_000.0)
            ramPeak = max(ramPeak, currentResidentMemoryMB())
        }
        let sorted = times.sorted()
        let mean = times.isEmpty ? 0 : times.reduce(0, +) / Double(times.count)

        return BenchResult(
            model: spec.short, units: unitsLabel, loaded: true, ran: true, error: nil,
            logits: logits, cosVsRef: cos, argmaxMatch: match,
            expectedArgmax: expected, gotArgmax: got,
            seqLen: spec.seq_len ?? ids.count, runs: runs, meanMs: mean,
            medianMs: sorted.isEmpty ? 0 : sorted[sorted.count/2],
            minMs: sorted.first ?? 0, maxMs: sorted.last ?? 0,
            ramBeforeMB: ramBefore, ramPeakMB: ramPeak)
    }

    /// Linha estruturada, parseável do console (setbuf(stdout,nil) garante flush).
    static func printLine(_ r: BenchResult) {
        func f(_ x: Double) -> String { String(format: "%.4f", x) }
        let logitsStr = r.logits.map { String(format: "%.4f", $0) }.joined(separator: ",")
        let errStr = (r.error ?? "").replacingOccurrences(of: "\"", with: "'")
            .replacingOccurrences(of: "\n", with: " ")
        print("BENCHLINE {"
            + "\"model\":\"\(r.model)\",\"units\":\"\(r.units)\","
            + "\"loaded\":\(r.loaded),\"ran\":\(r.ran),"
            + "\"logits\":[\(logitsStr)],"
            + "\"cos\":\(f(r.cosVsRef)),\"argmax_match\":\(r.argmaxMatch),"
            + "\"expected_argmax\":\(r.expectedArgmax),\"got_argmax\":\(r.gotArgmax),"
            + "\"seq\":\(r.seqLen),\"runs\":\(r.runs),"
            + "\"median_ms\":\(f(r.medianMs)),\"mean_ms\":\(f(r.meanMs)),"
            + "\"min_ms\":\(f(r.minMs)),\"max_ms\":\(f(r.maxMs)),"
            + "\"ram_before_mb\":\(f(r.ramBeforeMB)),\"ram_peak_mb\":\(f(r.ramPeakMB)),"
            + "\"error\":\"\(errStr)\"}")
    }
}
