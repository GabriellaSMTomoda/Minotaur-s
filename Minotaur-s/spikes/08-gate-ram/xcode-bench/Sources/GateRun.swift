import CoreML
import Foundation

/// SPIKE 8 — GATE DA FASE 6 (item aberto 27): pico de RAM com os DOIS modelos vivos.
///
/// O que este harness responde: o app cabe em 1 GB (NF-06) carregando o modelo de
/// embeddings (113 MB) e o `plue_bertimbau` (320 MB) ao mesmo tempo, rodando a carga
/// de uma verificação real?
///
/// **Os dois modelos ficam vivos, de propósito.** É o que o
/// `VerificationPipeline.loadFromBundle` faz hoje: constrói `EmbeddingService` e
/// `NLIService` juntos, antes da primeira verificação, e os mantém pela vida da tela.
///
/// As sequências vêm de `fixture.json` (ver make_fixture.py): texto de artigo real,
/// chunkado pelas regras do `TextChunker` e tokenizado pelos tokenizadores reais dos
/// dois modelos. Chegam aqui como ids porque o tokenizador WordPiece em Swift é
/// trabalho da Etapa 2 — e o custo de RAM de uma predição é função do COMPRIMENTO da
/// sequência, não de quais ids ela carrega.
///
/// **Um cenário por lançamento** (`GATE_SCENARIO`), em processo novo. Memória de Core ML
/// é pegajosa: o que uma fase aloca contamina a leitura da seguinte, e foi por medir tudo
/// num processo só que a primeira rodada não soube dizer se o crescimento vinha dos
/// embeddings ou do NLI.
enum GateRun {

    // MARK: - Fixture

    struct NLIInput: Decodable {
        let input_ids: [Int]
        let attention_mask: [Int]
        let token_type_ids: [Int]
        let claim: String
    }

    /// Par no formato do modelo em produção hoje (XLM-R, sem `token_type_ids`).
    struct NLIAtualInput: Decodable {
        let input_ids: [Int]
        let attention_mask: [Int]
        let claim: String
    }

    struct Article: Decodable {
        let index: Int
        let embedding_inputs: [[Int]]
        let nli_inputs: [NLIInput]
        let nli_atual_inputs: [NLIAtualInput]
    }

    struct WorstCase: Decodable {
        let embedding_input: [Int]
        let nli_inputs: [NLIInput]
    }

    struct Fixture: Decodable {
        let articles: [Article]
        let worst_case: WorstCase
    }

    // MARK: - Resultado

    struct StageResult {
        let stage: String
        let detail: String
        let residentMB: Double
        let footprintMB: Double
        let peakResidentMB: Double
        let peakFootprintMB: Double
        let elapsedMs: Double
        let predictions: Int
        let medianPredictionMs: Double
    }

    // MARK: - Carregamento

    static func loadFixture() -> Fixture? {
        guard let url = Bundle.main.url(forResource: "fixture", withExtension: "json"),
              let data = try? Data(contentsOf: url)
        else { return nil }
        return try? JSONDecoder().decode(Fixture.self, from: data)
    }

    static func loadModel(resource: String) throws -> MLModel {
        let configuration = MLModelConfiguration()
        // `.cpuOnly` é a configuração do app (DT-18) e a que o Spike 7 mediu: mais
        // rápida que `.all` neste perfil e com metade da RAM (643 MB contra 1.154 MB).
        configuration.computeUnits = .cpuOnly

        if let compiled = Bundle.main.url(forResource: resource, withExtension: "mlmodelc") {
            return try MLModel(contentsOf: compiled, configuration: configuration)
        }
        if let package = Bundle.main.url(forResource: resource, withExtension: "mlpackage") {
            let compiled = try MLModel.compileModel(at: package)
            return try MLModel(contentsOf: compiled, configuration: configuration)
        }
        throw NSError(domain: "gate", code: 404, userInfo: [
            NSLocalizedDescriptionKey: "modelo \(resource) não está no bundle"
        ])
    }

    // MARK: - Entradas

    private static func array(_ values: [Int]) throws -> MLMultiArray {
        let arr = try MLMultiArray(shape: [1, NSNumber(value: values.count)], dataType: .int32)
        for index in values.indices { arr[index] = NSNumber(value: Int32(values[index])) }
        return arr
    }

    /// `input_ids` + `attention_mask`, sem padding — idêntico a `EmbeddingService.embedding(for:)`.
    static func embeddingInput(ids: [Int]) throws -> MLDictionaryFeatureProvider {
        try MLDictionaryFeatureProvider(dictionary: [
            "input_ids": MLFeatureValue(multiArray: try array(ids)),
            "attention_mask": MLFeatureValue(multiArray: try array([Int](repeating: 1, count: ids.count))),
        ])
    }

    /// Par de NLI já achatado, para que o roteiro não conheça a diferença entre o modelo
    /// novo (BERT, 3 entradas) e o atual (XLM-R, 2 entradas).
    struct PairInput {
        let ids: [Int]
        let mask: [Int]
        /// `nil` no modelo atual; presente no BERTimbau.
        let types: [Int]?
    }

    /// Entrada do NLI, com a TERCEIRA entrada quando o modelo é BERT.
    ///
    /// `token_type_ids` não é opcional no BERTimbau: sem ele o modelo roda e devolve
    /// logits errados sem erro nenhum (Spike 7, FILTRO 1). Aqui isso importa porque o
    /// buffer do segmento também ocupa memória — medir a interface errada mediria outro
    /// modelo.
    static func nliInput(_ input: PairInput) throws -> MLDictionaryFeatureProvider {
        var features: [String: MLFeatureValue] = [
            "input_ids": MLFeatureValue(multiArray: try array(input.ids)),
            "attention_mask": MLFeatureValue(multiArray: try array(input.mask)),
        ]
        if let types = input.types {
            features["token_type_ids"] = MLFeatureValue(multiArray: try array(types))
        }
        return try MLDictionaryFeatureProvider(dictionary: features)
    }

    static func median(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        return sorted[sorted.count / 2]
    }

    /// Espaço livre em disco (MB).
    ///
    /// Não é curiosidade: o Core ML grava em disco o plano compilado de cada shape que
    /// encontra, e os modelos deste projeto foram convertidos com `RangeDim`, ou seja,
    /// cada comprimento de sequência novo é um shape novo. Sem disco para o cache, a
    /// especialização acontece em memória, a cada predição. Foi por falta de espaço que
    /// duas medições do Spike 7 abortaram ("LLVM ERROR: IO failure on output stream").
    static func freeDiskMB() -> Int {
        let url = URL(fileURLWithPath: NSHomeDirectory())
        if let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
           let important = values.volumeAvailableCapacityForImportantUsage {
            return Int(important / (1024 * 1024))
        }
        if let attributes = try? FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory()),
           let free = attributes[.systemFreeSize] as? NSNumber {
            return Int(free.int64Value / (1024 * 1024))
        }
        return -1
    }

    private static func msSince(_ start: UInt64) -> Double {
        Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000.0
    }

    // MARK: - Roteiro

    /// Cenário lido de `GATE_SCENARIO`:
    ///
    /// - `real`   — a carga do gate: 180 embeddings reais, depois 15 pares reais, em fases
    ///              separadas para saber de quem é a memória.
    /// - `fixed`  — mesma carga com UM comprimento só. Isola a hipótese de que o custo vem
    ///              de o Core ML especializar o grafo por shape (os modelos foram
    ///              convertidos com `RangeDim`, então cada comprimento novo é um shape novo).
    /// - `release`— 180 embeddings, LIBERA o modelo de embeddings, depois os 15 pares.
    ///              Quantifica a mitigação prevista no item 27 sem implementá-la no app.
    /// - `worst`  — tudo no teto de 512 tokens.
    /// - `atual`  — mesma carga com o modelo NLI de HOJE (`L6`, DT-18 revisada 1ª vez).
    ///              Linha de comparação: quanto do pico é da troca e quanto já existia.
    static func run(scenario: String, log: @escaping (String) -> Void) -> [StageResult] {
        var results: [StageResult] = []
        let probe = MemoryProbe()
        probe.start()
        defer { probe.stop() }

        func mark(_ stage: String, _ detail: String, elapsedMs: Double = 0,
                  predictions: Int = 0, times: [Double] = []) {
            let now = MemoryProbe.current()
            let peak = probe.peakSample
            let result = StageResult(
                stage: stage, detail: detail,
                residentMB: now.residentMB, footprintMB: now.footprintMB,
                peakResidentMB: peak.residentMB, peakFootprintMB: peak.footprintMB,
                elapsedMs: elapsedMs, predictions: predictions,
                medianPredictionMs: median(times))
            results.append(result)
            log(line(result))
        }

        probe.resetPeak()
        mark("baseline", "cenário=\(scenario), disco livre \(freeDiskMB()) MB, "
             + "processo sem modelo carregado")

        guard let fixture = loadFixture() else {
            mark("erro", "fixture.json ausente ou ilegível")
            return results
        }

        // 1. Embeddings.
        probe.resetPeak()
        var start = DispatchTime.now().uptimeNanoseconds
        var embeddings: MLModel?
        do { embeddings = try loadModel(resource: "Embeddings_int8") }
        catch {
            mark("erro", "falha ao carregar embeddings: \(error)")
            return results
        }
        mark("load_embeddings", "Embeddings_int8 .cpuOnly", elapsedMs: msSince(start))

        // 2. NLI, SEM soltar o de embeddings — os dois vivos é a pergunta do item 27.
        let nliResource = scenario == "atual" ? "L6_int8" : "plue_bertimbau_int8"
        probe.resetPeak()
        start = DispatchTime.now().uptimeNanoseconds
        let nli: MLModel
        do { nli = try loadModel(resource: nliResource) }
        catch {
            mark("erro", "falha ao carregar \(nliResource): \(error)")
            return results
        }
        mark("load_nli", "\(nliResource) .cpuOnly (embeddings ainda vivo)",
             elapsedMs: msSince(start))

        // 3. Entradas do cenário.
        func pairs(_ inputs: [NLIInput]) -> [PairInput] {
            inputs.map { PairInput(ids: $0.input_ids, mask: $0.attention_mask, types: $0.token_type_ids) }
        }

        let embeddingInputs: [[Int]]
        let nliInputs: [PairInput]
        switch scenario {
        case "worst":
            embeddingInputs = Array(repeating: fixture.worst_case.embedding_input, count: 180)
            nliInputs = pairs((0..<15).map {
                fixture.worst_case.nli_inputs[$0 % fixture.worst_case.nli_inputs.count]
            })
        case "fixed":
            // Um comprimento só, tirado da carga real (o 1º chunk do 1º artigo e o 1º par).
            let one = fixture.articles[0].embedding_inputs[0]
            embeddingInputs = Array(repeating: one, count: 180)
            nliInputs = Array(repeating: pairs([fixture.articles[0].nli_inputs[0]])[0], count: 15)
        case "atual":
            embeddingInputs = fixture.articles.flatMap { $0.embedding_inputs }
            nliInputs = fixture.articles.flatMap { $0.nli_atual_inputs }.map {
                PairInput(ids: $0.input_ids, mask: $0.attention_mask, types: nil)
            }
        default:
            embeddingInputs = fixture.articles.flatMap { $0.embedding_inputs }
            nliInputs = pairs(fixture.articles.flatMap { $0.nli_inputs })
        }

        // 4. Fase de embeddings, isolada.
        probe.resetPeak()
        start = DispatchTime.now().uptimeNanoseconds
        var embeddingTimes: [Double] = []
        for ids in embeddingInputs {
            guard let input = try? embeddingInput(ids: ids) else { continue }
            let t0 = DispatchTime.now().uptimeNanoseconds
            _ = try? embeddings?.prediction(from: input)
            embeddingTimes.append(msSince(t0))
        }
        mark("fase_embeddings", "\(embeddingTimes.count) chunks", elapsedMs: msSince(start),
             predictions: embeddingTimes.count, times: embeddingTimes)

        // 5. Cenário `release`: solta o modelo de embeddings antes do NLI.
        //    É MEDIÇÃO da mitigação do item 27, não implementação dela — o desenho do
        //    `VerificationPipeline` não é alterado por este spike.
        if scenario == "release" {
            probe.resetPeak()
            embeddings = nil
            // Uma volta do autorelease pool para que o que foi liberado apareça na conta.
            autoreleasepool { }
            usleep(500_000)
            mark("apos_liberar_embeddings", "modelo de embeddings desalocado")
        }

        // 6. Fase de NLI, isolada.
        probe.resetPeak()
        start = DispatchTime.now().uptimeNanoseconds
        var nliTimes: [Double] = []
        var firstLogits: [Double] = []
        for pair in nliInputs {
            guard let input = try? nliInput(pair) else { continue }
            let t0 = DispatchTime.now().uptimeNanoseconds
            let output = try? nli.prediction(from: input)
            nliTimes.append(msSince(t0))
            if firstLogits.isEmpty, let array = output?.featureValue(for: "logits")?.multiArrayValue {
                firstLogits = (0..<array.count).map { array[$0].doubleValue }
            }
        }
        mark("fase_nli", "\(nliTimes.count) pares · logits do 1º: "
             + firstLogits.map { String(format: "%.3f", $0) }.joined(separator: ","),
             elapsedMs: msSince(start), predictions: nliTimes.count, times: nliTimes)

        // 7. Segunda verificação seguida: confirma se a memória volta ao patamar ou cresce.
        probe.resetPeak()
        start = DispatchTime.now().uptimeNanoseconds
        for ids in embeddingInputs {
            guard let input = try? embeddingInput(ids: ids) else { continue }
            _ = try? embeddings?.prediction(from: input)
        }
        for pair in nliInputs {
            guard let input = try? nliInput(pair) else { continue }
            _ = try? nli.prediction(from: input)
        }
        mark("segunda_verificacao", "carga repetida com os modelos quentes",
             elapsedMs: msSince(start), predictions: embeddingInputs.count + nliInputs.count)

        return results
    }

    /// Linha estruturada e parseável do console (o app roda com `setbuf(stdout, nil)`).
    static func line(_ r: StageResult) -> String {
        func f(_ x: Double) -> String { String(format: "%.1f", x) }
        return "RAMLINE {"
            + "\"stage\":\"\(r.stage)\",\"detail\":\"\(r.detail)\","
            + "\"resident_mb\":\(f(r.residentMB)),\"footprint_mb\":\(f(r.footprintMB)),"
            + "\"peak_resident_mb\":\(f(r.peakResidentMB)),\"peak_footprint_mb\":\(f(r.peakFootprintMB)),"
            + "\"elapsed_ms\":\(f(r.elapsedMs)),\"predictions\":\(r.predictions),"
            + "\"median_ms\":\(f(r.medianPredictionMs))}"
    }
}
