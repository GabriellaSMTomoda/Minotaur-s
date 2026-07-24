import CoreML
import Foundation

/// Resultado de uma medição de latência de inferência de um modelo.
struct BenchResult: Identifiable {
    let id = UUID()
    let name: String
    let seqLen: Int
    let runs: Int
    let meanMs: Double
    let medianMs: Double
    let minMs: Double
    let maxMs: Double
    let computeUnits: String
    let loaded: Bool
    let error: String?
}

/// Mede a latência de `model.prediction(...)` (só a inferência — a tokenização
/// NÃO entra aqui, coerente com as metas NF-01/NF-02 da spec, que falam de
/// "inferência de embeddings/NLI"). Usa input_ids/attention_mask sintéticos de
/// tamanho realista; os IDs não afetam a latência de forma relevante.
enum Benchmark {

    static func loadModel(baseName: String, computeUnits: MLComputeUnits) throws -> MLModel {
        let cfg = MLModelConfiguration()
        cfg.computeUnits = computeUnits

        // 1) .mlmodelc já compilado (Xcode compila o .mlpackage ao buildar).
        if let url = Bundle.main.url(forResource: baseName, withExtension: "mlmodelc") {
            return try MLModel(contentsOf: url, configuration: cfg)
        }
        // 2) fallback: .mlpackage no bundle -> compila em runtime.
        if let url = Bundle.main.url(forResource: baseName, withExtension: "mlpackage") {
            let compiled = try MLModel.compileModel(at: url)
            return try MLModel(contentsOf: compiled, configuration: cfg)
        }
        throw NSError(
            domain: "bench", code: 404,
            userInfo: [NSLocalizedDescriptionKey:
                "Modelo \(baseName) não encontrado no bundle (.mlmodelc/.mlpackage). "
                + "Rode as conversões e adicione os .mlpackage ao target."]
        )
    }

    static func makeInput(seqLen: Int) throws -> MLDictionaryFeatureProvider {
        let ids = try MLMultiArray(shape: [1, NSNumber(value: seqLen)], dataType: .int32)
        let mask = try MLMultiArray(shape: [1, NSNumber(value: seqLen)], dataType: .int32)
        for i in 0..<seqLen {
            ids[i] = NSNumber(value: Int32((i * 7 + 5) % 250_000)) // IDs plausíveis no vocab
            mask[i] = 1
        }
        return try MLDictionaryFeatureProvider(dictionary: [
            "input_ids": MLFeatureValue(multiArray: ids),
            "attention_mask": MLFeatureValue(multiArray: mask),
        ])
    }

    static func run(
        name: String, baseName: String, seqLen: Int,
        runs: Int, warmup: Int,
        computeUnits: MLComputeUnits, computeUnitsLabel: String
    ) -> BenchResult {
        do {
            let model = try loadModel(baseName: baseName, computeUnits: computeUnits)
            let input = try makeInput(seqLen: seqLen)

            for _ in 0..<warmup { _ = try model.prediction(from: input) }

            var times: [Double] = []
            times.reserveCapacity(runs)
            for _ in 0..<runs {
                let t0 = DispatchTime.now().uptimeNanoseconds
                _ = try model.prediction(from: input)
                let t1 = DispatchTime.now().uptimeNanoseconds
                times.append(Double(t1 - t0) / 1_000_000.0)
            }
            let sorted = times.sorted()
            let mean = times.reduce(0, +) / Double(times.count)
            return BenchResult(
                name: name, seqLen: seqLen, runs: runs,
                meanMs: mean, medianMs: sorted[sorted.count / 2],
                minMs: sorted.first!, maxMs: sorted.last!,
                computeUnits: computeUnitsLabel, loaded: true, error: nil
            )
        } catch {
            return BenchResult(
                name: name, seqLen: seqLen, runs: runs,
                meanMs: 0, medianMs: 0, minMs: 0, maxMs: 0,
                computeUnits: computeUnitsLabel, loaded: false,
                error: "\(error)"
            )
        }
    }
}
