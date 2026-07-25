"""
20 afirmações/temas distintos, variados em assunto (política, economia,
esportes, saúde, clima, internacional, tecnologia, justiça), simulando
entradas reais de usuário no fluxo RF-01/RF-02. Nenhuma reivindica ser
verdadeira ou falsa — o spike testa estabilidade de busca, não veredito.
"""

CLAIMS = [
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

assert len(CLAIMS) == 20

# Stopwords PT-BR mínimas para a extração de keywords do spike (RF-02.2
# segue [EM ABERTO] na spec — esta é só uma heurística descartável para
# gerar queries realistas, não uma decisão de implementação).
STOPWORDS_PT = {
    "a", "o", "as", "os", "de", "da", "do", "das", "dos", "em", "no", "na",
    "nos", "nas", "para", "por", "com", "sem", "sobre", "e", "ou", "que",
    "se", "um", "uma", "uns", "umas", "ao", "aos", "à", "às", "é", "foi",
    "ser", "sua", "seu", "suas", "seus", "à", "após", "última", "último",
    "novo", "nova",
}


def extract_keywords(claim: str, max_words: int = 8) -> str:
    words = claim.split()
    kept = [w for w in words if w.lower().strip(".,") not in STOPWORDS_PT]
    return " ".join(kept[:max_words])
