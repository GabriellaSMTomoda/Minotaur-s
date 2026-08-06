import CoreML
import Foundation

enum ArchitectureGate {
    struct NLIInput: Decodable {
        let input_ids: [Int]
        let attention_mask: [Int]
        let token_type_ids: [Int]
    }

    struct Article: Decodable {
        let embedding_inputs: [[Int]]
        let nli_inputs: [NLIInput]
    }

    struct WorstCase: Decodable {
        let nli_inputs: [NLIInput]
    }

    struct Workload: Decodable {
        let articles: [Article]
        let worst_case: WorstCase
    }

    struct Probe: Decodable {
        let kind: String
        let input_ids: [Int]
        let attention_mask: [Int]
        let token_type_ids: [Int]
        let expected_coreml_logits: [Double]
    }

    struct ProbeFixture: Decodable {
        let variants: [String: [Probe]]
    }

    struct PairInput {
        let ids: [Int]
        let mask: [Int]
        let types: [Int]
    }

    struct StageResult {
        let stage: String
        let detail: String
        let current: MemoryProbe.Sample
        let peak: MemoryProbe.Sample
        let elapsedMs: Double
        let predictions: Int
        let medianMs: Double
        let meanMs: Double
        let minMs: Double
        let maxMs: Double
    }

    static func resource<T: Decodable>(_ name: String, as: T.Type) -> T? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "json"),
              let data = try? Data(contentsOf: url)
        else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    static func loadModel(_ resource: String) throws -> MLModel {
        let configuration = MLModelConfiguration()
        configuration.computeUnits = .cpuOnly
        guard let url = Bundle.main.url(forResource: resource, withExtension: "mlmodelc")
        else {
            throw NSError(domain: "spike9", code: 404, userInfo: [
                NSLocalizedDescriptionKey: "\(resource).mlmodelc ausente"
            ])
        }
        return try MLModel(contentsOf: url, configuration: configuration)
    }

    static func array(_ values: [Int]) throws -> MLMultiArray {
        let result = try MLMultiArray(
            shape: [1, NSNumber(value: values.count)], dataType: .int32)
        for index in values.indices {
            result[index] = NSNumber(value: Int32(values[index]))
        }
        return result
    }

    static func embeddingInput(_ ids: [Int]) throws -> MLDictionaryFeatureProvider {
        try MLDictionaryFeatureProvider(dictionary: [
            "input_ids": MLFeatureValue(multiArray: try array(ids)),
            "attention_mask": MLFeatureValue(
                multiArray: try array([Int](repeating: 1, count: ids.count))),
        ])
    }

    static func nliInput(_ pair: PairInput) throws -> MLDictionaryFeatureProvider {
        try MLDictionaryFeatureProvider(dictionary: [
            "input_ids": MLFeatureValue(multiArray: try array(pair.ids)),
            "attention_mask": MLFeatureValue(multiArray: try array(pair.mask)),
            "token_type_ids": MLFeatureValue(multiArray: try array(pair.types)),
        ])
    }

    static func fit(_ input: NLIInput, length: Int?) -> PairInput {
        guard let length else {
            return PairInput(
                ids: input.input_ids, mask: input.attention_mask, types: input.token_type_ids)
        }

        func resized(_ values: [Int], padding: Int) -> [Int] {
            var result = Array(values.prefix(length))
            if result.count < length {
                result += [Int](repeating: padding, count: length - result.count)
            }
            return result
        }
        return PairInput(
            ids: resized(input.input_ids, padding: 0),
            mask: resized(input.attention_mask, padding: 0),
            types: resized(input.token_type_ids, padding: 0))
    }

    static func exactLength(_ input: NLIInput, length: Int) -> PairInput {
        // Para benchmark arquitetural, a semântica dos ids não importa. O pior caso do
        // fixture tem 512 tokens reais; prefixes fornecem buffers válidos nos shapes menores.
        let prefix = fit(input, length: length)
        return PairInput(
            ids: prefix.ids,
            mask: [Int](repeating: 1, count: length),
            types: prefix.types)
    }

    static func freeDiskMB() -> Int {
        let home = URL(fileURLWithPath: NSHomeDirectory())
        if let values = try? home.resourceValues(
            forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
           let available = values.volumeAvailableCapacityForImportantUsage {
            return Int(available / 1024 / 1024)
        }
        if let attributes = try? FileManager.default.attributesOfFileSystem(
            forPath: NSHomeDirectory()),
           let available = attributes[.systemFreeSize] as? NSNumber {
            return Int(available.int64Value / 1024 / 1024)
        }
        return -1
    }

    static func milliseconds(since start: UInt64) -> Double {
        Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
    }

    static func stats(_ values: [Double]) -> (Double, Double, Double, Double) {
        guard !values.isEmpty else { return (0, 0, 0, 0) }
        let sorted = values.sorted()
        return (
            sorted[sorted.count / 2],
            values.reduce(0, +) / Double(values.count),
            sorted.first ?? 0,
            sorted.last ?? 0)
    }

    static func cosine(_ lhs: [Double], _ rhs: [Double]) -> Double {
        let dot = zip(lhs, rhs).map { $0.0 * $0.1 }.reduce(0, +)
        let left = sqrt(lhs.map { $0 * $0 }.reduce(0, +))
        let right = sqrt(rhs.map { $0 * $0 }.reduce(0, +))
        return dot / max(left * right, 1e-12)
    }

    static func logits(_ output: MLFeatureProvider?) -> [Double] {
        guard let values = output?.featureValue(for: "logits")?.multiArrayValue else { return [] }
        return (0..<values.count).map { values[$0].doubleValue }
    }

    static func run(
        scenario: String,
        variant: String,
        fixedLength: Int?,
        log: @escaping (String) -> Void
    ) -> String {
        let freeDisk = freeDiskMB()
        let probe = MemoryProbe()
        probe.start()
        defer { probe.stop() }

        func mark(
            _ stage: String,
            _ detail: String,
            elapsed: Double = 0,
            predictions: Int = 0,
            times: [Double] = []
        ) {
            let (median, mean, minimum, maximum) = stats(times)
            let current = MemoryProbe.current()
            let sampledPeak = probe.peakSample
            // Em etapas mais curtas que o intervalo de 3 ms, a leitura síncrona pode
            // chegar depois da última amostra. O pico nunca pode ser menor que o atual.
            let peak = MemoryProbe.Sample(
                residentMB: max(current.residentMB, sampledPeak.residentMB),
                footprintMB: max(current.footprintMB, sampledPeak.footprintMB))
            let result = StageResult(
                stage: stage,
                detail: detail,
                current: current,
                peak: peak,
                elapsedMs: elapsed,
                predictions: predictions,
                medianMs: median,
                meanMs: mean,
                minMs: minimum,
                maxMs: maximum)
            log(line(result, variant: variant, scenario: scenario, freeDisk: freeDisk))
        }

        probe.resetPeak()
        mark("baseline", "processo sem modelos")
        if scenario == "preflight" { return "preflight concluído" }

        guard let workload = resource("fixture", as: Workload.self) else {
            mark("error", "fixture.json ausente")
            return "erro: fixture"
        }

        probe.resetPeak()
        var started = DispatchTime.now().uptimeNanoseconds
        let embeddings: MLModel
        do { embeddings = try loadModel("Embeddings_int8") }
        catch {
            mark("error", "falha ao carregar embeddings: \(error)")
            return "erro: embeddings"
        }
        mark("load_embeddings", ".cpuOnly", elapsed: milliseconds(since: started))

        probe.resetPeak()
        started = DispatchTime.now().uptimeNanoseconds
        let nli: MLModel
        do { nli = try loadModel("NLI_Selected") }
        catch {
            mark("error", "falha ao carregar NLI: \(error)")
            return "erro: NLI"
        }
        mark(
            "load_nli", ".cpuOnly; embeddings vivo; fixed=\(fixedLength.map(String.init) ?? "none")",
            elapsed: milliseconds(since: started))

        if scenario == "parity" {
            let fixtureName = ProcessInfo.processInfo.environment["GATE_FIXTURE"]
                ?? "device_fixture"
            guard let fixture = resource(fixtureName, as: ProbeFixture.self),
                  let probes = fixture.variants[variant]
            else {
                mark("error", "sondas ausentes para \(variant)")
                return "erro: sondas"
            }
            for item in probes {
                let pair = PairInput(
                    ids: item.input_ids,
                    mask: item.attention_mask,
                    types: item.token_type_ids)
                let output = try? nli.prediction(from: nliInput(pair))
                let actual = logits(output)
                let similarity = cosine(actual, item.expected_coreml_logits)
                let expectedArgmax = item.expected_coreml_logits.enumerated().max {
                    $0.element < $1.element
                }?.offset ?? -1
                let actualArgmax = actual.enumerated().max { $0.element < $1.element }?.offset ?? -1
                log(parityLine(
                    variant: variant,
                    kind: item.kind,
                    sequenceLength: pair.ids.count,
                    expected: item.expected_coreml_logits,
                    actual: actual,
                    cosine: similarity,
                    expectedArgmax: expectedArgmax,
                    actualArgmax: actualArgmax))
            }
            return "paridade concluída"
        }

        if scenario.hasPrefix("len-") {
            guard let requested = Int(scenario.dropFirst(4)),
                  let source = workload.worst_case.nli_inputs.first
            else {
                mark("error", "comprimento inválido")
                return "erro: comprimento"
            }
            if let fixedLength, fixedLength != requested {
                mark("error", "modelo fixo \(fixedLength), entrada pedida \(requested)")
                return "erro: shape incompatível"
            }
            let pair = exactLength(source, length: requested)
            let provider: MLDictionaryFeatureProvider
            do { provider = try nliInput(pair) }
            catch {
                mark("error", "entrada inválida: \(error)")
                return "erro: entrada"
            }

            probe.resetPeak()
            let coldStart = DispatchTime.now().uptimeNanoseconds
            _ = try? nli.prediction(from: provider)
            mark(
                "latency_cold", "1 par; seq=\(requested)",
                elapsed: milliseconds(since: coldStart), predictions: 1)

            // Segunda passada de aquecimento; a mediana abaixo mede o shape já compilado.
            _ = try? nli.prediction(from: provider)
            probe.resetPeak()
            var times: [Double] = []
            started = DispatchTime.now().uptimeNanoseconds
            for _ in 0..<9 {
                let one = DispatchTime.now().uptimeNanoseconds
                _ = try? nli.prediction(from: provider)
                times.append(milliseconds(since: one))
            }
            mark(
                "latency_warm", "9 pares; seq=\(requested); ambos modelos vivos",
                elapsed: milliseconds(since: started), predictions: times.count, times: times)
            _ = embeddings // mantém referência viva até o fim da medição.
            return "latência concluída"
        }

        guard scenario == "real" else {
            mark("error", "cenário desconhecido")
            return "erro: cenário"
        }

        let embeddingInputs = workload.articles.flatMap { $0.embedding_inputs }
        let nliInputs = workload.articles.flatMap { $0.nli_inputs }.map {
            fit($0, length: fixedLength)
        }

        probe.resetPeak()
        started = DispatchTime.now().uptimeNanoseconds
        var embeddingTimes: [Double] = []
        for ids in embeddingInputs {
            guard let provider = try? embeddingInput(ids) else { continue }
            let one = DispatchTime.now().uptimeNanoseconds
            _ = try? embeddings.prediction(from: provider)
            embeddingTimes.append(milliseconds(since: one))
        }
        mark(
            "embeddings_180", "carga real",
            elapsed: milliseconds(since: started),
            predictions: embeddingTimes.count,
            times: embeddingTimes)

        probe.resetPeak()
        started = DispatchTime.now().uptimeNanoseconds
        var nliTimes: [Double] = []
        for pair in nliInputs {
            guard let provider = try? nliInput(pair) else { continue }
            let one = DispatchTime.now().uptimeNanoseconds
            _ = try? nli.prediction(from: provider)
            nliTimes.append(milliseconds(since: one))
        }
        mark(
            "nli_15", "carga real; comprimentos=" + nliInputs.map { String($0.ids.count) }.joined(separator: ","),
            elapsed: milliseconds(since: started),
            predictions: nliTimes.count,
            times: nliTimes)

        probe.resetPeak()
        started = DispatchTime.now().uptimeNanoseconds
        for ids in embeddingInputs {
            if let provider = try? embeddingInput(ids) {
                _ = try? embeddings.prediction(from: provider)
            }
        }
        for pair in nliInputs {
            if let provider = try? nliInput(pair) {
                _ = try? nli.prediction(from: provider)
            }
        }
        mark(
            "second_verification", "mesma carga com modelos quentes",
            elapsed: milliseconds(since: started),
            predictions: embeddingInputs.count + nliInputs.count)
        return "carga real concluída"
    }

    static func line(
        _ result: StageResult, variant: String, scenario: String, freeDisk: Int
    ) -> String {
        func f(_ value: Double) -> String { String(format: "%.1f", value) }
        return "GATELINE {"
            + "\"variant\":\"\(variant)\",\"scenario\":\"\(scenario)\","
            + "\"stage\":\"\(result.stage)\",\"detail\":\"\(result.detail)\","
            + "\"free_disk_mb\":\(freeDisk),"
            + "\"resident_mb\":\(f(result.current.residentMB)),"
            + "\"footprint_mb\":\(f(result.current.footprintMB)),"
            + "\"peak_resident_mb\":\(f(result.peak.residentMB)),"
            + "\"peak_footprint_mb\":\(f(result.peak.footprintMB)),"
            + "\"elapsed_ms\":\(f(result.elapsedMs)),"
            + "\"predictions\":\(result.predictions),"
            + "\"median_ms\":\(f(result.medianMs)),"
            + "\"mean_ms\":\(f(result.meanMs)),"
            + "\"min_ms\":\(f(result.minMs)),\"max_ms\":\(f(result.maxMs))}"
    }

    static func parityLine(
        variant: String,
        kind: String,
        sequenceLength: Int,
        expected: [Double],
        actual: [Double],
        cosine: Double,
        expectedArgmax: Int,
        actualArgmax: Int
    ) -> String {
        func vector(_ values: [Double]) -> String {
            values.map { String(format: "%.6f", $0) }.joined(separator: ",")
        }
        return "PARITYLINE {"
            + "\"variant\":\"\(variant)\",\"kind\":\"\(kind)\","
            + "\"sequence_length\":\(sequenceLength),"
            + "\"expected\":[\(vector(expected))],\"actual\":[\(vector(actual))],"
            + "\"cosine\":\(String(format: "%.6f", cosine)),"
            + "\"expected_argmax\":\(expectedArgmax),\"actual_argmax\":\(actualArgmax)}"
    }
}
