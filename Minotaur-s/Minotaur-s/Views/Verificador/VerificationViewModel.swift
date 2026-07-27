//
//  VerificationViewModel.swift
//  Minotaur-s
//
//  Created by Claude Code on 26/07/26.
//

import Foundation

/// Dono do pipeline **fora da main thread**.
///
/// `VerificationPipeline` guarda os dois serviços de Core ML, que não são `Sendable` — não
/// podem morar num tipo `@MainActor` sem arrastar a inferência para a main thread (NF-04).
/// Um `actor` resolve os dois problemas de uma vez: o estado isolado pode ser não-`Sendable` e
/// tudo que roda aqui roda no executor de fundo.
///
/// Também é onde o modelo é carregado uma única vez: `loadFromBundle` lê 216 MB de
/// `.mlpackage` (§3.2), custo que não se paga a cada verificação.
actor VerificationRunner {
    private let makePipeline: @Sendable () throws -> VerificationPipeline
    private var pipeline: VerificationPipeline?

    init(makePipeline: @escaping @Sendable () throws -> VerificationPipeline) {
        self.makePipeline = makePipeline
    }

    /// Pipeline de produção, com os modelos do bundle.
    static func production() -> VerificationRunner {
        VerificationRunner { try VerificationPipeline.loadFromBundle() }
    }

    /// Carrega os modelos, se ainda não estiverem carregados.
    ///
    /// - Throws: `VerificationError.modelLoadFailed` (RF-10.3). Chamar isto antes da primeira
    ///   verificação é o que permite bloquear a funcionalidade com mensagem própria em vez de
    ///   o usuário descobrir o problema depois de esperar a busca inteira.
    func prepare() throws {
        guard pipeline == nil else { return }
        do {
            pipeline = try makePipeline()
        } catch {
            throw error as? VerificationError ?? .modelLoadFailed
        }
    }

    func verify(
        claim: String,
        onProgress: @escaping VerificationPipeline.ProgressHandler
    ) async throws -> VerificationResult {
        try prepare()
        guard let pipeline else { throw VerificationError.modelLoadFailed }
        return try await pipeline.verify(claim: claim, onProgress: onProgress)
    }
}

/// Estado da tela de verificação: entrada, progresso, resultado e erro.
///
/// A `View` não conhece o pipeline; ela lê estas propriedades e chama três métodos
/// (`prepare`, `verify`, `cancel`). Toda regra de "o que aparece na tela" que dá para testar
/// sem SwiftUI está aqui ou em `VerificationPresentation` — as `View`s ficam com layout.
///
/// Nada é persistido: o resultado vive nesta instância e morre com ela (§5).
@MainActor
final class VerificationViewModel: ObservableObject {

    /// Texto digitado pelo usuário (RF-01.1).
    ///
    /// **Nunca é limpo pelo modelo de tela**, nem ao cancelar (CA-09: "retorna à tela inicial
    /// com o texto preservado") nem ao concluir — quem apaga é o usuário.
    @Published var claimText: String = ""

    /// Etapa corrente (RF-01.4). `nil` quando não há verificação em andamento.
    @Published private(set) var stage: VerificationStage?

    /// Resultado da última verificação, enquanto a tela de resultado está aberta (RF-09).
    @Published private(set) var result: VerificationResult?

    /// Erro categorizado da última tentativa (RF-10.4). Nunca é uma mensagem genérica.
    @Published private(set) var failure: VerificationError?

    /// Falso quando os modelos não carregam: a verificação fica bloqueada, mas o app continua
    /// funcionando (RF-10.3).
    @Published private(set) var isAvailable: Bool = true

    private let runner: VerificationRunner
    private var runningTask: Task<Void, Never>?

    init(runner: VerificationRunner = .production()) {
        self.runner = runner
    }

    /// Se há verificação em andamento — comanda o indicador de progresso e o botão Cancelar
    /// (RF-01.4 / RF-01.5).
    var isVerifying: Bool { stage != nil }

    /// Validação da entrada (RF-01.2 / CA-03).
    var validation: VerificationPresentation.ClaimValidation {
        VerificationPresentation.validate(claim: claimText)
    }

    /// Se o botão "Verificar notícia" está habilitado.
    ///
    /// Três condições, não uma: texto válido (CA-03), nenhuma verificação em andamento e
    /// modelos carregados (RF-10.3).
    var canVerify: Bool { validation.allowsVerification && !isVerifying && isAvailable }

    // MARK: - Ciclo de vida

    /// Carrega os modelos antecipadamente, fora da main thread (RF-10.3 / NF-04).
    ///
    /// Chamado quando a tela aparece: carregar 216 MB só no toque do botão somaria segundos ao
    /// orçamento de 15 s da NF-03, e uma falha de carregamento só apareceria depois de o
    /// usuário já ter escrito e esperado.
    func prepare() async {
        guard isAvailable, !isVerifying else { return }
        do {
            try await runner.prepare()
        } catch {
            handle(error)
        }
    }

    // MARK: - Verificação

    /// Dispara a verificação completa (RF-01.3).
    ///
    /// Ignora o toque se a entrada não é válida ou se já há verificação em andamento — a tela
    /// desabilita o botão nesses casos, mas o modelo não depende disso para se proteger.
    func verify() {
        guard canVerify else { return }

        let claim = claimText.trimmingCharacters(in: .whitespacesAndNewlines)
        failure = nil
        result = nil
        stage = .searching

        // O handler é montado aqui, e não dentro do `Task`, para capturar `self` uma única vez:
        // capturar de novo lá dentro seria referência a variável capturada em código
        // concorrente (erro no modo Swift 6).
        let onProgress = progressHandler()

        // O `Task` herda o isolamento do `MainActor`, então `finish` é chamado direto; quem
        // sai da main thread é o `verify` do coordenador, que é uma função não-isolada.
        runningTask = Task { [weak self, runner] in
            do {
                let verification = try await runner.verify(claim: claim, onProgress: onProgress)
                self?.finish(with: verification)
            } catch {
                self?.finish(withError: error)
            }
        }
    }

    /// Handler de progresso do pipeline (RF-01.4).
    ///
    /// Chega do executor de fundo, então salta para o `MainActor` antes de tocar em estado de
    /// UI. `nonisolated` porque a closure precisa ser `@Sendable`.
    private nonisolated func progressHandler() -> VerificationPipeline.ProgressHandler {
        { [weak self] stage in
            Task { @MainActor in
                // Depois de cancelar, um progresso atrasado não pode reacender o indicador
                // que a tela já apagou.
                guard let self, self.isVerifying else { return }
                self.stage = stage
            }
        }
    }

    /// Cancela a verificação em andamento (RF-01.5 / CA-09).
    ///
    /// Cancelar o `Task` propaga para o `withThrowingTaskGroup` da extração e para o
    /// `URLSession`, abortando os downloads pendentes; as checagens de cancelamento do
    /// coordenador impedem qualquer inferência adicional. Aqui só resta desfazer o estado de
    /// UI — **sem tocar em `claimText`** (CA-09).
    func cancel() {
        runningTask?.cancel()
        runningTask = nil
        stage = nil
        failure = nil
    }

    /// Fecha a tela de resultado e volta à entrada (RF-09).
    func dismissResult() {
        result = nil
    }

    /// Descarta a mensagem de erro sem repetir a verificação (RF-10).
    func dismissError() {
        failure = nil
    }

    // MARK: - Conclusão

    private func finish(with verification: VerificationResult) {
        // Cancelamento que chegou entre o fim do pipeline e este ponto: a tela já voltou ao
        // estado inicial, e mostrar o resultado agora contrariaria a CA-09.
        guard isVerifying else { return }
        runningTask = nil
        stage = nil
        result = verification
    }

    private func finish(withError error: Error) {
        guard isVerifying else { return }
        runningTask = nil
        stage = nil
        handle(error)
    }

    /// Traduz o erro para estado de tela (RF-10.4).
    ///
    /// `CancellationError` não vira mensagem: cancelar é escolha do usuário, não falha
    /// (CA-09). Qualquer outro erro cai numa categoria da `VerificationError` — o `else` é
    /// `.searchRequestFailed` e não um caso genérico porque o pipeline já garante categoria
    /// para tudo que lança, e a categoria mais provável de um erro inesperado é a de rede.
    private func handle(_ error: Error) {
        if error is CancellationError { return }

        let categorized = error as? VerificationError ?? .searchRequestFailed
        failure = categorized

        if categorized == .modelLoadFailed {
            // RF-10.3: bloqueia a funcionalidade, sem derrubar o app.
            isAvailable = false
        }
    }
}
