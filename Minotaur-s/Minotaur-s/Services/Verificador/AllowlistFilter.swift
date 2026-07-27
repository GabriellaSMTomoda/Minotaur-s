//
//  AllowlistFilter.swift
//  Minotaur-s
//
//  Created by Claude Code on 26/07/26.
//

import Foundation

/// Filtro local de resultados de busca contra a allowlist de `TrustedDomain` (RF-03.5).
///
/// Este filtro é **obrigatório, não defesa em profundidade**: o Spike 5 confirmou que o
/// `include_domains` da Tavily deixa vazar domínios de fora da lista em 4 de 20 buscas
/// (20%), incluindo 2 casos em que 100% dos resultados vieram de fora (Wikipédia,
/// dicionários, sites sem relação jornalística).
enum AllowlistFilter {

    /// Número máximo de fontes que seguem para o pipeline de análise (RF-04.3).
    ///
    /// A contrapartida desse limite — pedir 8 a 10 resultados à API (`max_results`) para
    /// truncar depois do filtro (DT-19) — é responsabilidade do serviço de busca, não deste
    /// filtro. A ordem importa: filtrar primeiro, truncar depois.
    static let maxAcceptedSources = 5

    // MARK: - Correspondência de domínio

    /// Host do URL em forma canônica: minúsculas, sem ponto final.
    ///
    /// O prefixo `www.` é preservado aqui — quem o descarta é `canonical(_:)`, no momento
    /// da comparação. Isso mantém o host original disponível para diagnóstico.
    static func normalizedHost(from url: URL) -> String? {
        guard let host = url.host(percentEncoded: false), !host.isEmpty else { return nil }
        var normalized = host.lowercased()
        while normalized.hasSuffix(".") {
            normalized.removeLast()
        }
        return normalized.isEmpty ? nil : normalized
    }

    /// Forma usada na comparação: minúsculas, sem ponto final e **sem o prefixo `www.`**.
    ///
    /// Descartar `www.` é necessário nos dois lados desde a DT-28, que gravou duas entradas
    /// pelo host real que serve o conteúdo (`www.band.com.br`, `www.agencialupa.org`). Sem
    /// isso, o casamento por sufixo aceitaria `www.band.com.br` mas rejeitaria `band.com.br`
    /// — exatamente o tipo de falha de correspondência que a DT-28 veio corrigir. Só o
    /// primeiro `www.` cai: `www.www.exemplo.com` não é um host que se queira normalizar.
    private static func canonical(_ value: String) -> String {
        var normalized = value.lowercased()
        while normalized.hasSuffix(".") {
            normalized.removeLast()
        }
        if normalized.hasPrefix("www.") {
            normalized.removeFirst(4)
        }
        return normalized
    }

    /// Entrada da allowlist que corresponde ao host, ou `nil` se nenhuma corresponder.
    ///
    /// A correspondência é por sufixo (`host == domain` ou `host` termina em `.domain`),
    /// conforme DT-20: subdomínios de um domínio confiável continuam confiáveis, incluindo
    /// órgãos menores em `*.gov.br`. O ponto na comparação é o que impede `evilgov.br` de
    /// casar com `gov.br`.
    ///
    /// Havendo mais de uma correspondência, vence a entrada mais longa (a mais específica),
    /// para que o domínio reportado ao usuário (RF-09.6) seja determinístico.
    ///
    /// Devolve a entrada da allowlist **como ela está escrita** (com `www.`, se for o caso),
    /// não a forma canônica: é esse valor que identifica o veículo em `SourceResult.domain`
    /// e na lista de domínios consultados.
    static func matchedDomain(forHost host: String) -> String? {
        let normalized = canonical(host)
        guard !normalized.isEmpty else { return nil }

        return TrustedDomain.allowlist
            .filter {
                let entry = canonical($0)
                return normalized == entry || normalized.hasSuffix("." + entry)
            }
            .max { canonical($0).count < canonical($1).count }
    }

    /// Entrada da allowlist que corresponde ao URL, ou `nil` se nenhuma corresponder.
    /// Usada para preencher `SourceResult.domain` (RF-03.3) e a lista de domínios
    /// consultados (RF-09.6).
    static func matchedDomain(for url: URL) -> String? {
        guard let host = normalizedHost(from: url) else { return nil }
        return matchedDomain(forHost: host)
    }

    static func isAllowed(_ url: URL) -> Bool {
        matchedDomain(for: url) != nil
    }

    /// Sobrecarga para URL em string — formato em que a Tavily devolve o campo `url`.
    /// String que não for um URL absoluto com host é tratada como não permitida.
    static func isAllowed(urlString: String) -> Bool {
        guard let url = URL(string: urlString) else { return false }
        return isAllowed(url)
    }

    // MARK: - Filtragem de resultados

    /// Descarta resultados fora da allowlist e só então trunca (RF-03.5 seguido de RF-04.3).
    ///
    /// Genérica sobre o tipo do resultado, via closure de acesso ao URL, para não acoplar o
    /// filtro ao formato de resposta do provedor de busca. A ordem de ranking original é
    /// preservada.
    ///
    /// - Parameters:
    ///   - items: resultados na ordem devolvida pelo provedor de busca.
    ///   - url: extrai o URL de um resultado; `nil` descarta o resultado.
    ///   - limit: quantos resultados sobrevivem ao final. Padrão `maxAcceptedSources`.
    static func filter<T>(
        _ items: [T],
        url: (T) -> URL?,
        limit: Int = maxAcceptedSources
    ) -> [T] {
        guard limit > 0 else { return [] }
        var accepted: [T] = []
        accepted.reserveCapacity(min(limit, items.count))

        for item in items {
            guard let itemURL = url(item), isAllowed(itemURL) else { continue }
            accepted.append(item)
            if accepted.count == limit { break }
        }
        return accepted
    }
}
