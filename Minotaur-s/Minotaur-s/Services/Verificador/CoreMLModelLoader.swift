//
//  CoreMLModelLoader.swift
//  Minotaur-s
//
//  Created by Claude Code on 26/07/26.
//

import CoreML
import Foundation
import OSLog

/// Carrega os modelos Core ML do bundle, tolerando as duas formas em que eles podem chegar lá.
///
/// O Xcode normalmente compila um `.mlpackage` para `.mlmodelc` na hora do build, e é esse o
/// caminho preferido — compilar em runtime custa segundos na primeira execução. Mas os
/// modelos deste projeto não são versionados (ver `scripts/sync-models.sh`), então há
/// cenários reais em que o `.mlpackage` chega cru ao bundle. Tentar as duas formas evita que
/// a feature morra por uma diferença de empacotamento.
enum CoreMLModelLoader {
    private static let logger = Logger(subsystem: "com.julia.fatoufarsa2025", category: "LocalModels")

    /// - Throws: `VerificationError.modelLoadFailed` (RF-10.3) — sempre essa categoria, para
    ///   que a UI mostre a mensagem específica de modelo indisponível em vez de erro genérico
    ///   (RF-10.4). A causa mais provável é `scripts/sync-models.sh` nunca ter rodado.
    static func load(
        resource: String,
        configuration: MLModelConfiguration,
        bundle: Bundle = .main
    ) throws -> MLModel {
        if let compiled = bundle.url(forResource: resource, withExtension: "mlmodelc") {
            do {
                return try MLModel(contentsOf: compiled, configuration: configuration)
            } catch {
                logger.error("Unable to load bundled model \(resource, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }

        if let package = bundle.url(forResource: resource, withExtension: "mlpackage") {
            do {
                let compiled = try MLModel.compileModel(at: package)
                return try MLModel(contentsOf: compiled, configuration: configuration)
            } catch {
                logger.error("Unable to compile bundled model \(resource, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }

        logger.error("Local analysis unavailable: missing or invalid asset \(resource, privacy: .public)")
        throw VerificationError.modelLoadFailed
    }
}
