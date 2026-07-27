# -*- coding: utf-8 -*-
"""
Dataset de teste do SPIKE 1 (validação de modelos em PT-BR).

Cada par tem:
  - chunk:     trecho REAL de uma notícia brasileira (premissa do NLI)
  - afirmacao: afirmação escrita à mão (hipótese do NLI)
  - esperado:  rótulo esperado ("entailment" | "contradiction" | "neutral")
  - fonte:     URL do artigo original de onde o chunk foi copiado

Fontes reais (Agência Brasil / EBC, coletadas em 2026-07-24):
  A) EUA impõem nova tarifa de 12,5% a produtos brasileiros
  B) Subsídio de R$ 0,44 por litro da gasolina é prorrogado por 30 dias
  C) Pilotos da Voepass não relatavam falhas nas aeronaves, diz Cenipa

Os chunks são parágrafos copiados verbatim das reportagens. As afirmações
foram escritas à mão para cobrir os 3 casos com clareza (não casos ambíguos).
"""

# --- Artigo A: tarifa dos EUA -------------------------------------------------
FONTE_A = "https://agenciabrasil.ebc.com.br/economia/noticia/2026-07/eua-impoem-nova-tarifa-de-125-produtos-brasileiros"

A1 = ("Os Estados Unidos anunciaram nesta quinta-feira (23) a aplicação de uma "
      "nova sobretaxa de 12,5% sobre produtos brasileiros, sob a alegação de que "
      "o Brasil não adota mecanismos eficazes para impedir a importação de "
      "mercadorias produzidas com trabalho forçado. A medida entra em vigor na "
      "madrugada desta sexta-feira (24).")

A2 = ("A nova tarifa substitui a taxa global temporária de 10% aplicada desde "
      "fevereiro e se soma à sobretaxa de 25% sobre produtos brasileiros, em vigor "
      "desde o último dia 22. Com isso, parte das exportações do Brasil para o "
      "mercado estadunidense poderá enfrentar tributação de até 37,5%.")

A3 = ("Segundo o governo estadunidense, o Brasil integra o grupo de 54 países que "
      "não proíbem nem fiscalizam de forma efetiva a entrada de produtos fabricados "
      "com trabalho forçado em seus mercados internos.")

# --- Artigo B: subsídio da gasolina ------------------------------------------
FONTE_B = "https://agenciabrasil.ebc.com.br/economia/noticia/2026-07/subsidio-de-r-044-por-litro-da-gasolina-pode-ser-prorrogado"

B1 = ("O agravamento da guerra no Oriente Médio fez o governo prorrogar o subsídio "
      "de R$ 0,44 por litro da gasolina. Em vigor desde 25 de maio, o benefício "
      "acabaria no sábado (25) e foi estendido por 30 dias a partir de domingo (26).")

B2 = ("O ministro da Fazenda, Dario Durigan, assinou nesta quinta-feira (23) à noite "
      "a portaria com a extensão do subsídio, criado para reduzir os impactos do "
      "conflito no Oriente Médio sobre os preços dos combustíveis no Brasil.")

B3 = ("O subsídio de R$ 1,12 por litro do diesel continua em vigor. No último dia 16, "
      "o Congresso Nacional prorrogou, por 60 dias, a Medida Provisória 1.363, que "
      "instituiu a subvenção.")

# --- Artigo C: acidente da Voepass -------------------------------------------
FONTE_C = "https://agenciabrasil.ebc.com.br/geral/noticia/2026-07/pilotos-da-voepass-nao-relatavam-falhas-nas-aeronaves-diz-cenipa"

C1 = ("Falhas no sistema, alertas ignorados, revisões mecânicas insuficientes e uma "
      "cultura organizacional de não reportar falhas em voos anteriores estão entre "
      "as causas da queda da aeronave PS-VPB, da Voepass, em 2024.")

C2 = ("No dia 9 de agosto de 2024, o turboélice da marca francesa ATR, da empresa "
      "Voepass, caiu em Vinhedo, município vizinho de Campinas, no interior de São "
      "Paulo, vindo de Cascavel, no Paraná. A aeronave seguia para Guarulhos (SP). "
      "Foram 62 mortos no acidente, sendo 4 deles tripulantes.")

C3 = ("Na ocasião, um representante da empresa afirmou que a aeronave havia passado "
      "por manutenção de rotina antes do voo e não apresentava nenhum problema "
      "técnico. As investigações, no entanto, mostraram \"várias fragilidades nas "
      "atividades de manutenção\".")


# --- Pares de teste (20 no total; ≥15 exigidos) ------------------------------
PAIRS = [
    # ===== ENTAILMENT (8) =====
    {"chunk": A1, "afirmacao": "Os Estados Unidos criaram uma nova sobretaxa de 12,5% sobre produtos do Brasil.", "esperado": "entailment", "fonte": FONTE_A},
    {"chunk": A2, "afirmacao": "Com a nova tarifa, produtos brasileiros podem ser taxados em até 37,5% nos EUA.", "esperado": "entailment", "fonte": FONTE_A},
    {"chunk": B1, "afirmacao": "O governo prorrogou por 30 dias o subsídio de R$ 0,44 por litro da gasolina.", "esperado": "entailment", "fonte": FONTE_B},
    {"chunk": B2, "afirmacao": "O ministro da Fazenda, Dario Durigan, assinou a portaria que estendeu o subsídio.", "esperado": "entailment", "fonte": FONTE_B},
    {"chunk": B3, "afirmacao": "O subsídio do diesel é de R$ 1,12 por litro.", "esperado": "entailment", "fonte": FONTE_B},
    {"chunk": C1, "afirmacao": "Falhas de manutenção e alertas ignorados estão entre as causas da queda do avião da Voepass.", "esperado": "entailment", "fonte": FONTE_C},
    {"chunk": C2, "afirmacao": "O acidente com a aeronave da Voepass deixou 62 mortos.", "esperado": "entailment", "fonte": FONTE_C},
    {"chunk": C2, "afirmacao": "A queda do avião da Voepass aconteceu em Vinhedo, no interior de São Paulo.", "esperado": "entailment", "fonte": FONTE_C},

    # ===== CONTRADICTION (7) =====
    {"chunk": A1, "afirmacao": "A nova sobretaxa dos Estados Unidos sobre produtos brasileiros é de apenas 5%.", "esperado": "contradiction", "fonte": FONTE_A},
    {"chunk": A1, "afirmacao": "A nova tarifa americana sobre produtos brasileiros só entra em vigor no ano que vem.", "esperado": "contradiction", "fonte": FONTE_A},
    {"chunk": B1, "afirmacao": "O subsídio da gasolina foi encerrado e não será renovado.", "esperado": "contradiction", "fonte": FONTE_B},
    {"chunk": B2, "afirmacao": "Quem assinou a portaria do subsídio foi o presidente do Banco Central.", "esperado": "contradiction", "fonte": FONTE_B},
    {"chunk": C2, "afirmacao": "O acidente da Voepass não deixou nenhuma vítima fatal.", "esperado": "contradiction", "fonte": FONTE_C},
    {"chunk": C2, "afirmacao": "O avião da Voepass caiu na cidade do Rio de Janeiro.", "esperado": "contradiction", "fonte": FONTE_C},
    {"chunk": C3, "afirmacao": "As investigações confirmaram que a manutenção da aeronave estava perfeita.", "esperado": "contradiction", "fonte": FONTE_C},

    # ===== NEUTRAL (5) =====
    {"chunk": A3, "afirmacao": "O Brasil é o maior exportador de café do mundo.", "esperado": "neutral", "fonte": FONTE_A},
    {"chunk": A2, "afirmacao": "O dólar fechou em queda frente ao real nesta sexta-feira.", "esperado": "neutral", "fonte": FONTE_A},
    {"chunk": B2, "afirmacao": "O preço do gás de cozinha subiu 10% na cidade de São Paulo.", "esperado": "neutral", "fonte": FONTE_B},
    {"chunk": B3, "afirmacao": "A Petrobras anunciou lucro recorde no último trimestre.", "esperado": "neutral", "fonte": FONTE_B},
    {"chunk": C2, "afirmacao": "A Voepass vai lançar novas rotas internacionais para a Europa.", "esperado": "neutral", "fonte": FONTE_C},
]
