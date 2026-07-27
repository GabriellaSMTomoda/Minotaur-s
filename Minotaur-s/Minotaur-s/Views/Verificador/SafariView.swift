//
//  SafariView.swift
//  Minotaur-s
//
//  Created by Claude Code on 26/07/26.
//

import SafariServices
import SwiftUI

/// `SFSafariViewController` embrulhado para SwiftUI (RF-09.3).
///
/// O requisito pede `SFSafariViewController` especificamente, não `openURL`: o artigo abre
/// dentro do app, com a barra de endereço visível — o usuário vê de que veículo é a página que
/// está lendo, o que sustenta a atribuição da RF-09.4 e a independência da NF-14.
struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let configuration = SFSafariViewController.Configuration()
        configuration.entersReaderIfAvailable = false

        let controller = SFSafariViewController(url: url, configuration: configuration)
        controller.preferredControlTintColor = UIColor(named: "azul")
        return controller
    }

    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}
