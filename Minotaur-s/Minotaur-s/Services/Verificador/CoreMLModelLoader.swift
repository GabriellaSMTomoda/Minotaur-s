//
//  CoreMLModelLoader.swift
//  Minotaur-s
//
//  Created by Claude Code on 26/07/26.
//

import CoreML
import Foundation

/// Carrega os modelos Core ML do bundle, tolerando as duas formas em que eles podem chegar lá.
///
/// O Xcode normalmente compila um `.mlpackage` para `.mlmodelc` na hora do build, e é esse o
/// caminho preferido — compilar em runtime custa segundos na primeira execução. Mas os
/// modelos deste projeto não são versionados (ver `scripts/sync-models.sh`), então há
/// cenários reais em que o `.mlpackage` chega cru ao bundle. Tentar as duas formas evita que
/// a feature morra por uma diferença de empacotamento.
enum CoreMLModelLoader {

    /// - Throws: `VerificationError.modelLoadFailed` (RF-10.3) — sempre essa categoria, para
    ///   que a UI mostre a mensagem específica de modelo indisponível em vez de erro genérico
    ///   (RF-10.4). A causa mais provável é `scripts/sync-models.sh` nunca ter rodado.
    static func load(
        resource: String,
        configuration: MLModelConfiguration,
        bundle: Bundle = .main
    ) throws -> MLModel {
        if let compiled = bundle.url(forResource: resource, withExtension: "mlmodelc"),
           let model = try? MLModel(contentsOf: compiled, configuration: configuration) {
            return model
        }

        if let package = bundle.url(forResource: resource, withExtension: "mlpackage"),
           let compiled = try? MLModel.compileModel(at: package),
           let model = try? MLModel(contentsOf: compiled, configuration: configuration) {
            return model
        }

        throw VerificationError.modelLoadFailed
    }
}
