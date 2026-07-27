//
//  Verificador.swift
//  Minotaur-s
//
//  Created by Claude Code on 26/07/26.
//

import SwiftUI

/// Tela de entrada da feature "Verificar Notícia" (RF-01).
///
/// Só entrada, validação, progresso, cancelar e banner de erro — o resultado é uma tela
/// própria (`VerificationResultView`), e toda a lógica de busca/extração/embeddings/NLI vive
/// no `VerificationPipeline`, por trás do `VerificationViewModel`. Esta `View` não conhece
/// nenhum dos dois diretamente, só o modelo de tela.
struct VerificadorView: View {
    @StateObject private var viewModel = VerificationViewModel()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if !viewModel.isAvailable {
                        unavailableBanner
                    }

                    if let stage = viewModel.stage {
                        progressIndicator(for: stage)
                    }

                    GroupBox("Sua Notícia") {
                        TextField("Cole ou digite a notícia aqui", text: $viewModel.claimText, axis: .vertical)
                            .lineLimit(4...8)
                            .disabled(viewModel.isVerifying)
                    }

                    // RF-01.2 / CA-03: motivo da desabilitação, visível junto ao campo.
                    if let message = viewModel.validation.message {
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    actionButtons

                    if let failure = viewModel.failure {
                        errorBanner(for: failure)
                    }

                    Spacer(minLength: 0)
                }
                .padding()
            }
            .background(Color("background").ignoresSafeArea())
            .navigationTitle("Verificar Notícia")
            .toolbarBackground(Color("azul"), for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .navigationDestination(isPresented: resultPresented) {
                if let result = viewModel.result {
                    VerificationResultView(result: result)
                }
            }
        }
        // Carrega os modelos ao abrir a tela, fora da main thread (RF-10.3 / NF-04) — não no
        // toque do botão, que somaria segundos ao orçamento da NF-03.
        .task { await viewModel.prepare() }
    }

    // MARK: - Navegação para o resultado (RF-09)

    /// `result` é `private(set)`: a `View` não pode escrever nele diretamente, só ler e pedir
    /// ao view model para fechar via `dismissResult()` — daí o binding manual em vez de
    /// `$viewModel.result`.
    private var resultPresented: Binding<Bool> {
        Binding(
            get: { viewModel.result != nil },
            set: { isPresented in
                if !isPresented { viewModel.dismissResult() }
            }
        )
    }

    // MARK: - Progresso (RF-01.4)

    private func progressIndicator(for stage: VerificationStage) -> some View {
        HStack(spacing: 8) {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle())
            Text(VerificationPresentation.progressTitle(for: stage))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
        .padding(.vertical, 4)
        .transition(.opacity)
    }

    // MARK: - Ações (RF-01.3 / RF-01.5 / CA-09)

    private var actionButtons: some View {
        HStack {
            if viewModel.isVerifying {
                Button("Cancelar") {
                    viewModel.cancel()
                }
                .font(.headline)
            }

            Spacer()

            Button {
                viewModel.verify()
            } label: {
                Label("Verificar notícia", systemImage: "globe")
                    .labelStyle(.titleAndIcon)
            }
            .font(.headline)
            .bold()
            .foregroundColor(Color.white)
            .frame(height: 48)
            .frame(minWidth: 160)
            .background(Color("azul"))
            .cornerRadius(20)
            .accessibilityLabel("Verificar notícia")
            .accessibilityHint("Toque para verificar essa notícia contra fontes confiáveis.")
            .disabled(!viewModel.canVerify)
        }
    }

    // MARK: - Indisponibilidade do modelo (RF-10.3)

    /// Diferente do banner de erro abaixo, este **não é dispensável**: uma vez que o
    /// carregamento do modelo falha, `isAvailable` fica falso pelo resto da sessão (não há
    /// caminho de volta), então o aviso precisa continuar visível mesmo depois que o usuário
    /// dispensa a mensagem de erro transitória.
    private var unavailableBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
            Text(VerificationPresentation.presentation(for: .modelLoadFailed).message)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
    }

    // MARK: - Erro (RF-10 / CA-08)

    private func errorBanner(for error: VerificationError) -> some View {
        let presentation = VerificationPresentation.presentation(for: error)

        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: presentation.systemImage).foregroundStyle(.red)
                Text(presentation.title)
                    .font(.subheadline)
                    .bold()
            }
            Text(presentation.message)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                // RF-10.1: só oferece repetir quando repetir pode mudar o resultado.
                if presentation.isRetriable {
                    Button("Tentar novamente") {
                        viewModel.dismissError()
                        viewModel.verify()
                    }
                    .font(.footnote)
                }
                Button("Dispensar") {
                    viewModel.dismissError()
                }
                .font(.footnote)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
    }
}

#Preview {
    VerificadorView()
}
