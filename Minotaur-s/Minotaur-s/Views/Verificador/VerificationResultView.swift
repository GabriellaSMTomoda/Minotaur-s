//
//  VerificationResultView.swift
//  Minotaur-s
//
//  Created by Claude Code on 26/07/26.
//

import SwiftUI

/// Tela de resultado da verificação (RF-09).
///
/// **A ordem dos elementos é requisito, não estética.** O aviso de limitação fica fora da
/// `ScrollView`, fixo no topo: a CA-11 exige que ele esteja visível *sem rolagem*, para
/// qualquer veredito e em qualquer tamanho de tela. Tudo o mais rola por baixo dele.
struct VerificationResultView: View {
    let result: VerificationResult

    /// Artigo aberto no `SFSafariViewController` (RF-09.3). `nil` = nenhum.
    @State private var openArticle: ArticleLink?

    var body: some View {
        VStack(spacing: 0) {
            limitationWarning

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    verdictCard
                    claimCard

                    if result.sources.isEmpty {
                        emptySourcesNotice
                    } else {
                        sourcesSection
                    }

                    consultedDomainsSection
                    independenceNotice
                }
                .padding()
            }
        }
        .background(Color("background").ignoresSafeArea())
        .navigationTitle("Resultado")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color("azul"), for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .sheet(item: $openArticle) { article in
            SafariView(url: article.url)
                .ignoresSafeArea()
        }
    }

    // MARK: - Aviso de limitação (RF-09.5 / CA-11)

    private var limitationWarning: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(VerificationPresentation.limitationWarning)
                .font(.footnote)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(.thinMaterial)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Veredito (RF-09.1)

    private var verdictCard: some View {
        let style = VerificationPresentation.style(for: result.verdict)

        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: style.systemImage)
                    .font(.title)
                    .foregroundStyle(style.tint)
                Text(style.title)
                    .font(.title2)
                    .bold()
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text(style.subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            // CA-05: o resultado diz quantas fontes foram efetivamente analisadas — as
            // descartadas por paywall, timeout ou irrelevância não entram na conta.
            Text(sourceCountText)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(style.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(style.tint.opacity(0.35), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
    }

    private var sourceCountText: String {
        switch result.sources.count {
        case 0: return "Nenhuma fonte analisada."
        case 1: return "1 fonte analisada."
        default: return "\(result.sources.count) fontes analisadas."
        }
    }

    private var claimCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Afirmação verificada")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(result.claim)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Fontes (RF-09.2 / RF-09.3 / RF-09.4)

    private var sourcesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Fontes analisadas")
                .font(.headline)

            ForEach(result.sources, id: \.url) { source in
                sourceCard(source)
            }
        }
    }

    private func sourceCard(_ source: SourceResult) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Nome do veículo + rótulo individual (RF-09.2).
            HStack(alignment: .firstTextBaseline) {
                Text(source.domain)
                    .font(.caption)
                    .bold()
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                labelBadge(source.label)
            }

            Text(source.title)
                .font(.callout)
                .bold()
                .fixedSize(horizontal: false, vertical: true)

            // Trecho que motivou o rótulo, com atribuição explícita (RF-09.4 / CA-10 / NF-12).
            if !source.excerpt.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("“\(VerificationPresentation.excerptText(source.excerpt))”")
                        .font(.footnote)
                        .italic()
                        .fixedSize(horizontal: false, vertical: true)
                    Text(VerificationPresentation.attributionText(domain: source.domain))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(.leading, 8)
                .overlay(alignment: .leading) {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.35))
                        .frame(width: 2)
                }
            }

            // Score de confiança (RF-09.2).
            Text(VerificationPresentation.confidenceText(source.confidence))
                .font(.caption2)
                .foregroundStyle(.secondary)

            // Link para o artigo original (RF-09.2 / RF-09.4). Presente sempre, inclusive
            // quando o card inteiro já é tocável: a CA-10 pede link explícito junto do trecho.
            Label("Ler no site do veículo", systemImage: "safari")
                .font(.footnote)
                .foregroundStyle(Color("azul"))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
        .contentShape(Rectangle())
        // RF-09.3: tocar na fonte abre o artigo original no SFSafariViewController.
        .onTapGesture { openArticle = ArticleLink(source: source) }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Abre o artigo original de \(source.domain).")
    }

    private func labelBadge(_ label: NLILabel) -> some View {
        Text(VerificationPresentation.title(for: label))
            .font(.caption2)
            .bold()
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                VerificationPresentation.tint(for: label).opacity(0.18),
                in: Capsule()
            )
            .foregroundStyle(VerificationPresentation.tint(for: label))
    }

    private var emptySourcesNotice: some View {
        Text("Nenhum artigo dos veículos consultados pôde ser analisado para essa afirmação.")
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Domínios consultados (RF-09.6 / CA-02)

    /// Aparece em **todo** veredito, inclusive quando não há fonte alguma: é justamente no
    /// `NAO_ENCONTRADO` que a CA-02 exige informar o que foi consultado.
    private var consultedDomainsSection: some View {
        DisclosureGroup {
            Text(result.consultedDomains.joined(separator: ", "))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 4)
        } label: {
            Text("Domínios consultados (\(result.consultedDomains.count))")
                .font(.subheadline)
                .bold()
        }
        .padding()
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
    }

    private var independenceNotice: some View {
        Text(VerificationPresentation.independenceNotice)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// URL de artigo pronta para o `sheet(item:)` (RF-09.3).
///
/// Fonte cuja `url` não seja absoluta não chega até aqui — o filtro de allowlist já a descarta
/// (RF-03.5) —, mas o inicializador falível evita que um dado inesperado vire crash.
private struct ArticleLink: Identifiable {
    let id: String
    let url: URL

    init?(source: SourceResult) {
        guard let url = URL(string: source.url) else { return nil }
        self.id = source.url
        self.url = url
    }
}

#Preview("Confirmado") {
    NavigationStack {
        VerificationResultView(
            result: VerificationResult(
                id: UUID(),
                claim: "O desemprego caiu para 6,2% no trimestre encerrado em maio.",
                createdAt: Date(),
                verdict: .confirmado,
                consultedDomains: ["g1.globo.com", "estadao.com.br", "bbc.com"],
                sources: [
                    SourceResult(
                        url: "https://g1.globo.com/economia/desemprego",
                        domain: "g1.globo.com",
                        title: "Desemprego cai a 6,2% no trimestre encerrado em maio",
                        label: .entailment,
                        confidence: 0.93,
                        similarity: 0.81,
                        excerpt: "A taxa de desocupação ficou em 6,2%, segundo o levantamento divulgado nesta quinta-feira."
                    )
                ]
            )
        )
    }
}

#Preview("Não encontrado") {
    NavigationStack {
        VerificationResultView(
            result: VerificationResult(
                id: UUID(),
                claim: "Uma afirmação que nenhum veículo confiável cobriu nesta semana.",
                createdAt: Date(),
                verdict: .naoEncontrado,
                consultedDomains: ["g1.globo.com", "estadao.com.br"],
                sources: []
            )
        )
    }
}
