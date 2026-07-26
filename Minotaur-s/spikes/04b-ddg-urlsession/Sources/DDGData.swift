import Foundation

// Cópia EXATA de spikes/04-ddg-scraping/domains.py (TRUSTED_DOMAINS) — mesma
// ordem, mesmo conteúdo, para que a query da fase A n_domains=3 seja
// byte-a-byte idêntica à do Spike 4 original.
enum DDGDomains {
    static let trusted: [String] = [
        "g1.globo.com",
        "oglobo.globo.com",
        "folha.uol.com.br",
        "estadao.com.br",
        "cnnbrasil.com.br",
        "veja.abril.com.br",
        "valor.globo.com",
        "exame.com",
        "r7.com",
        "terra.com.br",
        "metropoles.com",
        "poder360.com.br",
        "gzh.com.br",
        "correiobraziliense.com.br",
        "agenciabrasil.ebc.com.br",
        "otempo.com.br",
        "band.uol.com.br",
        "ge.globo.com",
        "aosfatos.org",
        "lupa.uol.com.br",
        "bbc.com",
        "dw.com",
        "elpais.com",
        "apnews.com",
        "gov.br",
        "camara.leg.br",
        "senado.leg.br",
        "stf.jus.br",
        "tse.jus.br",
        "who.int",
    ]
}

// Cópia EXATA de spikes/04-ddg-scraping/queries.py (CLAIMS + STOPWORDS_PT +
// extract_keywords) — mesma ordem, mesma heurística de extração de
// keywords, para reproduzir a mesma query-base da fase A e as mesmas 20
// buscas da fase B.
enum DDGClaims {
    static let claims: [String] = [
        "Governo federal anuncia isenção de imposto de renda para quem ganha até dois salários mínimos",
        "Banco Central decide manter taxa Selic inalterada na última reunião do Copom",
        "Seleção brasileira de futebol se classifica para as quartas de final da competição internacional",
        "OMS declara fim da emergência de saúde pública para determinada doença",
        "STF julga ação sobre marco temporal de terras indígenas",
        "Senado aprova projeto de lei sobre regulamentação de inteligência artificial no Brasil",
        "Inflação medida pelo IPCA acelera no último mês segundo dados oficiais",
        "Presidente dos Estados Unidos anuncia novas tarifas sobre produtos importados do Brasil",
        "Ibovespa fecha em alta puxado por ações de empresas de commodities",
        "Ministério da Saúde inicia campanha nacional de vacinação contra a gripe",
        "União Europeia fecha acordo comercial com o Mercosul após anos de negociação",
        "Polícia Federal deflagra operação contra fraude em benefícios do INSS",
        "Câmara dos Deputados vota reforma tributária em segundo turno",
        "Cientistas brasileiros publicam estudo sobre variante de vírus respiratório",
        "Prefeitura de São Paulo anuncia novo plano de mobilidade urbana para a capital",
        "Papa faz visita oficial ao Brasil e celebra missa campal",
        "TSE define novas regras de propaganda eleitoral para as eleições municipais",
        "Justiça determina bloqueio de bens de empresa investigada por lavagem de dinheiro",
        "Petrobras anuncia novo investimento em exploração de petróleo no pré-sal",
        "Nasa confirma data de lançamento de nova missão espacial tripulada",
    ]

    static let stopwords: Set<String> = [
        "a", "o", "as", "os", "de", "da", "do", "das", "dos", "em", "no", "na",
        "nos", "nas", "para", "por", "com", "sem", "sobre", "e", "ou", "que",
        "se", "um", "uma", "uns", "umas", "ao", "aos", "à", "às", "é", "foi",
        "ser", "sua", "seu", "suas", "seus", "após", "última", "último",
        "novo", "nova",
    ]

    static func extractKeywords(_ claim: String, maxWords: Int = 8) -> String {
        let words = claim.split(separator: " ").map(String.init)
        let kept = words.filter { word in
            let stripped = word.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ".,"))
            return !stopwords.contains(stripped)
        }
        return kept.prefix(maxWords).joined(separator: " ")
    }
}
