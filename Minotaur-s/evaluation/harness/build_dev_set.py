"""Builds `evaluation/data/dev_claims.jsonl`: a DEVELOPMENT set, not gold.

Labels were drafted by the assistant (trivial facts) or copied from the quiz candidate whose
source is a professional outlet/fact-checker. Every record starts as
`review_status=pending_user_review` and must never be reported as a blind-test metric.
"""
import json
from datetime import datetime
from pathlib import Path

DATA = Path(__file__).resolve().parents[1] / "data"

TRUE = """Brasília é a capital do Brasil.
O Brasil é o maior país da América do Sul em área.
O real é a moeda oficial do Brasil.
A língua oficial do Brasil é o português.
O Brasil conquistou a Copa do Mundo de futebol de 2002.
Pedro Álvares Cabral chegou ao Brasil em 1500.
A Lei Áurea, que aboliu a escravidão no Brasil, foi assinada em 1888.
A independência do Brasil foi proclamada em 1822.
O Rio Amazonas deságua no Oceano Atlântico.
A Floresta Amazônica é a maior floresta tropical do mundo.
A água ferve a 100 graus Celsius ao nível do mar.
A Terra gira em torno do Sol.
Júpiter é o maior planeta do Sistema Solar.
O Cristo Redentor fica no Rio de Janeiro.
Machado de Assis escreveu Dom Casmurro.
O SUS é o sistema público de saúde do Brasil.
Pelé foi tricampeão mundial com a seleção brasileira.
Ayrton Senna foi tricampeão mundial de Fórmula 1.
O Pantanal é a maior planície alagável do mundo.
São Paulo é a cidade mais populosa do Brasil.
A Constituição brasileira atual foi promulgada em 1988.
O Brasil sediou a Copa do Mundo de futebol de 2014.
O Rio de Janeiro sediou os Jogos Olímpicos de 2016.
O Plano Real foi lançado em 1994.
Oscar Niemeyer projetou edifícios de Brasília.
A Lua é o satélite natural da Terra.
O DNA tem estrutura de dupla hélice.
O Monte Everest é a montanha mais alta do mundo.
Santos Dumont foi um pioneiro brasileiro da aviação.
O Brasil tem 26 estados e um Distrito Federal.
O Brasil é o maior produtor de café do mundo.
Salvador foi a primeira capital do Brasil.
A vacinação é a principal forma de prevenção contra a poliomielite.
O mosquito Aedes aegypti transmite a dengue.
Fumar aumenta o risco de câncer de pulmão.
Tiradentes foi executado em 1792.
A CLT foi criada no governo de Getúlio Vargas em 1943.
O Brasil faz parte do BRICS.
A Petrobras é uma empresa brasileira de petróleo.
O Rio São Francisco é conhecido como Velho Chico.""".splitlines()

FALSE = """São Paulo é a capital do Brasil.
A Terra é plana.
Vacinas causam autismo.
O Brasil venceu a Copa do Mundo de 2014.
A independência do Brasil foi proclamada em 1889.
A língua oficial do Brasil é o espanhol.
O Sol gira em torno da Terra.
Marte é o maior planeta do Sistema Solar.
O Cristo Redentor fica em Salvador.
Dom Casmurro foi escrito por José de Alencar.
A Lei Áurea foi assinada em 1922.
O homem nunca pisou na Lua.
A dengue é transmitida pelo ar, de pessoa para pessoa.
Ayrton Senna foi campeão mundial de Fórmula 1 cinco vezes.
O Brasil tem 30 estados.
Brasília foi inaugurada em 1990.
O Rio Amazonas deságua no Oceano Pacífico.
A vacina contra a Covid-19 altera o DNA humano.
O Plano Real foi lançado em 2004.
O Rio de Janeiro sediou os Jogos Olímpicos de 2012.
A água ferve a 50 graus Celsius ao nível do mar.
Fumar reduz o risco de câncer de pulmão.
O Brasil é o maior produtor de petróleo do mundo.
Pedro Álvares Cabral chegou ao Brasil em 1600.
A Constituição brasileira atual foi promulgada em 1964.
O Monte Everest fica na América do Sul.
Pelé nunca ganhou uma Copa do Mundo.
O 5G transmite o coronavírus.
Beber água sanitária cura a Covid-19.
A cloroquina é um tratamento comprovado contra a Covid-19.
O Pantanal fica na Região Nordeste do Brasil.
A urna eletrônica brasileira fica conectada à internet durante a votação.
O real foi substituído por uma moeda única do Mercosul.
Salvador nunca foi capital do Brasil.
Santos Dumont era português.
A Lua tem luz própria.""".splitlines()

# Quiz candidates with professional sources; label = quiz label unless noted.
QUIZ = {
    "CONTRADITO": ["quiz-1", "quiz-2", "quiz-3", "quiz-5", "quiz-6", "quiz-8", "quiz-13", "quiz-16", "quiz-24",
                   "quiz-56", "quiz-134", "quiz-136", "quiz-140", "quiz-141", "quiz-146", "quiz-147", "quiz-148",
                   "quiz-153", "quiz-159", "quiz-161", "quiz-162", "quiz-172"],
    "CONFIRMADO": ["quiz-29", "quiz-31", "quiz-34", "quiz-37", "quiz-38", "quiz-40", "quiz-44", "quiz-45", "quiz-50",
                   "quiz-84", "quiz-85", "quiz-87", "quiz-100", "quiz-115", "quiz-131", "quiz-145", "quiz-165",
                   "quiz-181", "quiz-185", "quiz-191", "quiz-192", "quiz-199"],
}
RELABELED = {"quiz-136": "Quiz marca CONFIRMADO, mas a fonte (gov.br Saúde com Ciência) desmente a afirmação."}


def main():
    records = []
    for i, claim in enumerate(TRUE, 1):
        records.append({"id": f"dev-true-{i:02d}", "claim": claim, "verdict": "CONFIRMADO", "group": "trivial_true",
                        "reference_date": None})
    for i, claim in enumerate(FALSE, 1):
        records.append({"id": f"dev-false-{i:02d}", "claim": claim, "verdict": "CONTRADITO", "group": "trivial_false",
                        "reference_date": None})
    quiz = {r["id"]: r for r in map(json.loads, (DATA / "pending_candidates.jsonl").read_text().splitlines())}
    for verdict, ids in QUIZ.items():
        for qid in ids:
            q = quiz[qid]
            date = datetime.strptime(q["source_date_suggestion"], "%d/%m/%Y").date().isoformat()
            records.append({"id": f"dev-{qid}", "claim": q["claim"].strip(), "verdict": verdict,
                            "group": "quiz_hoax" if verdict == "CONTRADITO" else "quiz_news",
                            "reference_date": date, "source_url": q["source_url"],
                            "note": RELABELED.get(qid)})
    for r in records:
        r.update({"origin": "dev_not_gold", "review_status": "pending_user_review", "reviewers": []})
    (DATA / "dev_claims.jsonl").write_text("".join(json.dumps(r, ensure_ascii=False) + "\n" for r in records))
    print(len(records), "records")


if __name__ == "__main__":
    main()
