//
//  SearchResultItem.swift
//  Minotaur-s
//
//  Created by Claude Code on 26/07/26.
//

import Foundation

/// Um resultado devolvido pelo provedor de busca (Tavily, via proxy — RF-04.2).
///
/// Os campos espelham o formato de resposta documentado no Spike 5. `raw_content` existe na
/// API mas volta sempre `null` sem `include_raw_content`, que não é pedido nesta fase — por
/// isso não está modelado aqui.
///
/// Vive em `Models/` porque atravessa dois serviços: a busca o produz e o `ArticleExtractor`
/// consome o `content` como fallback da RF-05.3.
struct SearchResultItem: Decodable, Equatable {
    /// Título da página, exibido na lista de fontes (RF-09.2).
    let title: String

    /// URL direta do artigo — a Tavily não usa redirecionador (ao contrário do DDG).
    let url: String

    /// Snippet devolvido pela busca, de 100 a ~2.200 caracteres.
    ///
    /// **Só é usado como fallback** quando a extração própria render menos de 200 caracteres
    /// (RF-05.3 / DT-23). Nunca substitui uma extração bem-sucedida.
    let content: String

    /// Score de relevância (0–1) atribuído pelo provedor. Não participa do veredito — a
    /// relevância que conta no pipeline é a similaridade de cosseno da RF-06.5.
    let score: Double?

    /// `url` convertida, ou `nil` se a string não for um URL absoluto — caso em que o
    /// resultado é descartado pelo filtro de allowlist (RF-03.5).
    var resolvedURL: URL? { URL(string: url) }
}
