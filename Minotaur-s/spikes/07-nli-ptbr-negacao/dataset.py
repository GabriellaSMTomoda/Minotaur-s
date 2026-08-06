# -*- coding: utf-8 -*-
"""
SPIKE 7 — Conjunto de teste.

Tudo aqui é TEXTO REAL. As premissas são chunks que de fato chegaram ao
`NLIService` em produção, colhidos pela investigação instrumentada pós-Fase 5
(pipeline real: proxy Cloudflare no ar, URLSession de verdade, os dois
.mlpackage do bundle). Não há par sintético construído para caber numa regra.

Por que isso importa: os 90% de acurácia PT-BR da DT-18 foram medidos em pares
LIMPOS (Spike 1). Foi exatamente validar em pares limpos que produziu o risco
materializado em 7.1. O conjunto abaixo é adversarial por natureza, porque o
texto que uma fonte confiável publica sobre uma alegação falsa é quase sempre a
alegação repetida com uma refutação por perto — o pior caso possível para um
modelo que decide por sobreposição lexical.

Três grupos:
  A  `ADVERSARIAIS`   os 10 pares que separaram os modelos na investigação
                      (8 falhas reais + 2 controles que o pipeline acertou).
  B  `PRODUCAO`       chunks adicionais dos MESMOS 3 claims que falharam em
                      produção, incluindo o único que o pipeline acertou.
  C  `CLAIMS_CURTOS`  item aberto 25 — o uso real predominante é frase única e
                      curta, e o veredito oscila com a redação.
"""

# --------------------------------------------------------------------------
# GRUPO A — os 10 pares adversariais
# --------------------------------------------------------------------------
# (premissa real do artigo, afirmação do usuário, rótulo correto, fonte)
#
# "contradiction/neutral" em um dos casos não é indecisão: a frase é um
# antecedente contrafactual ("Se a Terra fosse plana…"). Ela não afirma nem nega
# a hipótese isoladamente, então neutral é defensável e entailment é
# indefensável. O acerto exige apenas NÃO responder entailment.
ADVERSARIAIS = [
    ("Algumas teorias da conspiração que afirmam que a Terra é plana continuam se espalhando. "
     "Estas são algumas maneiras simples de comprovar que a Terra é redonda e rebater essas "
     "ideias dos terraplanistas.",
     "A Terra é plana.", "contradiction", "BBC"),
    ("Pode parecer mentira, mas em pleno século 21 ainda é necessário insistir que a Terra é "
     "redonda, algo que se sabe há mais de 2 mil anos. Algumas teorias da conspiração que "
     "afirmam que a Terra é plana continuam se espalhando.",
     "A Terra é plana.", "contradiction", "BBC"),
    ("Se a Terra fosse plana e você olhasse para longe, veria a mesma paisagem se estivesse no "
     "chão ou na copa da árvore.",
     "A Terra é plana.", "contradiction/neutral", "BBC"),
    ("A vacinação contra a gripe pode reduzir significativamente o risco de infarto e AVC "
     "(acidente vascular cerebral), explicou o Dr. Roberto Kalil.",
     "Vacina da gripe causa infarto.", "contradiction", "CNN Brasil"),
    ("\"A vacina para a gripe se torna extremamente importante ao reduzir de 20% a 30% a "
     "incidência de infarto e acidente vascular cerebral\", afirmou Dr. Kalil.",
     "Vacina da gripe causa infarto.", "contradiction", "CNN Brasil"),
    ("A vacinação contra o vírus Influenza tem como principal objetivo proteger a população da "
     "gripe. No entanto, há benefícios secundários: a proteção contra infartos e acidentes "
     "vasculares cerebrais (AVC).",
     "Vacina da gripe causa infarto.", "contradiction", "Metrópoles"),
    ("Tilt no câncer: pesquisador brasileiro descobre forma inovadora de tratar a doença",
     "Brasileiro encontrou cura do câncer.", "neutral", "Metrópoles"),
    ("Quem é Marc Abreu, médico brasileiro que diz curar Alzheimer, Parkinson e câncer nos EUA",
     "Brasileiro encontrou cura do câncer.", "neutral", "G1/Fantástico"),
    # Controles: o pipeline acertou os dois. Servem de piso — um modelo que os
    # erre está pior que o atual, por melhor que vá no resto.
    ("A prefeitura informou que o novo hospital municipal será inaugurado apenas em 2027.",
     "O hospital municipal foi inaugurado neste ano.", "contradiction", "controle"),
    ("O IBGE divulgou que a taxa de desemprego caiu para 6,2% no trimestre encerrado em maio.",
     "A taxa de desemprego caiu para 6,2%.", "entailment", "controle"),
]


# --------------------------------------------------------------------------
# GRUPO B — chunks adicionais dos 3 claims que falharam em produção
# --------------------------------------------------------------------------
# O caso do O Globo é o mais informativo do conjunto: foi a ÚNICA fonte rotulada
# corretamente nas três verificações, e perdeu a votação da RF-08.3 por 4×1.
PRODUCAO = [
    ("Médicos ouvidos pela reportagem pedem cautela: não existe base científica que justifique "
     "o uso deste tratamento, que custa R$ 200 mil e não passou por ensaio clínico.",
     "Brasileiro encontrou cura do câncer.", "contradiction", "O Globo"),
    ("O paciente estava em estágio avançado da doença e, graças a uma terapia inédita "
     "desenvolvida por um pesquisador brasileiro, o quadro foi revertido.",
     "Brasileiro encontrou cura do câncer.", "neutral", "Metrópoles"),
    ("Vacina da gripe reduz de 20 a 30% a incidência de infarto",
     "Vacina da gripe causa infarto.", "contradiction", "CNN Brasil (título)"),
    ("Um ex-terraplanista contou como mudou de ideia: \"falei: pessoal, não tem como a Terra ser "
     "plana\", disse ele ao relembrar o experimento que o convenceu.",
     "A Terra é plana.", "contradiction", "BBC"),
    ("A Terra não é plana, e sim aproximadamente esférica, ligeiramente achatada nos polos.",
     "A Terra é plana.", "contradiction", "El País"),
]


# --------------------------------------------------------------------------
# GRUPO C — claims curtos de frase única (item aberto 25)
# --------------------------------------------------------------------------
# O uso real predominante é frase única e curta. Na investigação, "A Terra é
# plana." deu CONFIRMADO e "A Terra é plana e a NASA esconde isso das pessoas."
# deu DIVERGENTES — mesmo pipeline, mesmas fontes, redação diferente.
#
# Cada entrada repete a MESMA premissa real com redações diferentes do mesmo
# claim. O que se mede aqui não é só acerto: é ESTABILIDADE — o rótulo deve ser
# o mesmo nas variantes, porque o fato alegado é o mesmo.
CLAIMS_CURTOS = [
    {
        "grupo": "terra-plana",
        "premissa": ("Algumas teorias da conspiração que afirmam que a Terra é plana continuam "
                     "se espalhando. Estas são algumas maneiras simples de comprovar que a Terra "
                     "é redonda e rebater essas ideias dos terraplanistas."),
        "esperado": "contradiction",
        "variantes": [
            "A Terra é plana.",
            "A Terra é plana",
            "Terra plana",
            "A Terra é plana e a NASA esconde isso das pessoas.",
            "Cientistas confirmaram que a Terra é plana.",
        ],
    },
    {
        "grupo": "vacina-infarto",
        "premissa": ("A vacinação contra a gripe pode reduzir significativamente o risco de "
                     "infarto e AVC (acidente vascular cerebral), explicou o Dr. Roberto Kalil."),
        "esperado": "contradiction",
        "variantes": [
            "Vacina da gripe causa infarto.",
            "Vacina da gripe causa infarto",
            "A vacina da gripe aumenta o risco de infarto.",
            "Tomar a vacina da gripe provoca ataque cardíaco.",
        ],
    },
    {
        "grupo": "desemprego",
        "premissa": ("O IBGE divulgou que a taxa de desemprego caiu para 6,2% no trimestre "
                     "encerrado em maio."),
        "esperado": "entailment",
        "variantes": [
            "A taxa de desemprego caiu para 6,2%.",
            "O desemprego caiu.",
            "O desemprego caiu para 6,2% no trimestre encerrado em maio, segundo o IBGE.",
        ],
    },
]


# --------------------------------------------------------------------------
# Negações (caminho (b))
# --------------------------------------------------------------------------
# Negação escrita à mão, para separar a QUALIDADE DO SINAL do CUSTO DE GERAR a
# negação. Se o sinal não funcionar nem com negação perfeita, não há por que
# discutir como gerá-la automaticamente. Ver `negacao.py`.
NEGACOES = {
    "A Terra é plana.": "A Terra não é plana.",
    "Vacina da gripe causa infarto.": "Vacina da gripe não causa infarto.",
    "Brasileiro encontrou cura do câncer.": "Nenhum brasileiro encontrou cura do câncer.",
    "O hospital municipal foi inaugurado neste ano.":
        "O hospital municipal não foi inaugurado neste ano.",
    "A taxa de desemprego caiu para 6,2%.": "A taxa de desemprego não caiu para 6,2%.",
}


def todos_os_pares():
    """Grupos A + B achatados em (premissa, hipótese, esperado, fonte, grupo)."""
    saida = [(p, h, e, f, "A") for (p, h, e, f) in ADVERSARIAIS]
    saida += [(p, h, e, f, "B") for (p, h, e, f) in PRODUCAO]
    return saida


def acertou(obtido: str, esperado: str) -> bool:
    """`esperado` pode listar mais de um rótulo aceitável, separado por '/'."""
    return obtido.lower() in [x.strip().lower() for x in esperado.split("/")]
