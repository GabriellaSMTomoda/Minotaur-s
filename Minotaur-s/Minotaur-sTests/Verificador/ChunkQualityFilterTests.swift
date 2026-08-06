//
//  ChunkQualityFilterTests.swift
//  Minotaur-sTests
//
//  Created by Claude Code on 03/08/26.
//

import Foundation
import Testing
@testable import Minotaur_s

/// DT-33 — chunks sem valor proposicional não viram premissa do NLI.
///
/// Os casos de descarte são **texto real**, colhido da investigação pós-Fase 5 nos chunks que
/// de fato chegaram ao `NLIService` em produção. Não são exemplos inventados para caber na
/// regra: cada um foi premissa de uma inferência que entrou na contagem da RF-08.3.
///
/// Os casos de *manutenção* são igualmente reais e importam tanto quanto: são as premissas dos
/// pares adversariais em que o modelo erra. Elas precisam continuar chegando ao NLI — o
/// problema delas é o julgamento do modelo (ressalva em §3.2, Spike 7), não a qualidade do
/// chunk. Um filtro que "consertasse" o veredito descartando-as estaria escondendo o defeito.
struct ChunkQualityFilterTests {

    // MARK: - Casos reais de descarte

    @Test("Byline com carimbo de data no meio da navegação é descartada")
    func realBylineIsRejected() {
        // Chegou ao NLI como premissa. A duplicação de "Navegue direto pelo app" é do texto
        // extraído, não erro de transcrição.
        let chunk = "Navegue direto pelo app Navegue direto pelo app Por Giulia Vidale — São Paulo 27/04/2023 15h57"

        #expect(ChunkQualityFilter.rejection(for: chunk) == .navigation)
    }

    @Test("Sobra de bloco de navegação é descartada")
    func navigationLeftoverIsRejected() {
        #expect(ChunkQualityFilter.rejection(for: "Fim do Mais lidas") == .navigation)
    }

    @Test("Título de Web Story, único chunk de uma fonte inteira, é descartado")
    func webStoryTitleIsRejected() {
        // Esta foi a fonte que votou `entailment` para "Brasileiro encontrou cura do câncer."
        // tendo como única premissa o título da página — sobre um mosaico de torcida.
        let chunk = "Title: Torcida do Bahia faz mosaico para Everton Ribeiro após cura do câncer | Web Stories CNN Brasil"

        #expect(ChunkQualityFilter.rejection(for: chunk) == .pageTitle)
    }

    @Test("Byline com legenda de foto não sobra corpo e é descartada")
    func bylineWithPhotoCreditIsRejected() {
        // Similaridade 0,5371 — entrou no top-3 da RF-06.6 por repetir "Terra".
        let chunk = "Por Eli Elster* 10/12/2025 04h01 Atualizado Imagem do planeta Terra — Foto: ESA/NASA"

        // Descartado por comprimento, mas só depois de removido byline, carimbo e crédito: o
        // chunk cru tem 84 caracteres e passaria folgado por um piso de comprimento ingênuo.
        #expect(chunk.count > ChunkQualityFilter.minimumCharacters)
        #expect(ChunkQualityFilter.rejection(for: chunk) == .tooShort)
    }

    @Test("Manchete nominal sem verbo é descartada")
    func verblessHeadlineIsRejected() {
        #expect(ChunkQualityFilter.rejection(for: "Balanço do mercado imobiliário no primeiro semestre de 2025") == .noVerb)
    }

    // MARK: - O que precisa continuar passando

    /// Premissas reais dos pares adversariais do Spike 7. Todas têm proposição verificável — o
    /// erro nelas é do modelo, não do chunk.
    @Test("Premissas reais dos pares adversariais continuam chegando ao NLI", arguments: [
        "Algumas teorias da conspiração que afirmam que a Terra é plana continuam se espalhando. Estas são algumas maneiras simples de comprovar que a Terra é redonda e rebater essas ideias dos terraplanistas.",
        "Pode parecer mentira, mas em pleno século 21 ainda é necessário insistir que a Terra é redonda, algo que se sabe há mais de 2 mil anos.",
        "Se a Terra fosse plana e você olhasse para longe, veria a mesma paisagem se estivesse no chão ou na copa da árvore.",
        "A vacinação contra a gripe pode reduzir significativamente o risco de infarto e AVC (acidente vascular cerebral), explicou o Dr. Roberto Kalil.",
        "\"A vacina para a gripe se torna extremamente importante ao reduzir de 20% a 30% a incidência de infarto e acidente vascular cerebral\", afirmou Dr. Kalil.",
        "A vacinação contra o vírus Influenza tem como principal objetivo proteger a população da gripe. No entanto, há benefícios secundários: a proteção contra infartos e acidentes vasculares cerebrais (AVC).",
        "A prefeitura informou que o novo hospital municipal será inaugurado apenas em 2027.",
        "O IBGE divulgou que a taxa de desemprego caiu para 6,2% no trimestre encerrado em maio.",
    ])
    func adversarialPremisesSurvive(_ chunk: String) {
        #expect(ChunkQualityFilter.rejection(for: chunk) == nil)
    }

    @Test("Parágrafo com crédito de foto no fim é mantido — o crédito não invalida o corpo")
    func paragraphWithTrailingCreditSurvives() {
        // A regra remove o crédito para *medir* o corpo; não reprova o chunk por tê-lo. Reprovar
        // custaria um parágrafo inteiro de evidência por causa de quatro palavras de legenda.
        let chunk = "O Ministério da Saúde confirmou que a campanha de vacinação começa na segunda-feira em todo o país. Foto: Marcelo Camargo/Agência Brasil"

        #expect(ChunkQualityFilter.rejection(for: chunk) == nil)
    }

    @Test("Parágrafo assinado por repórter é mantido")
    func paragraphWithBylineSurvives() {
        let chunk = "Por Ana Maria Souza — O relatório aponta que a taxa de desocupação recuou pelo terceiro trimestre consecutivo, segundo dados divulgados nesta quinta-feira."

        #expect(ChunkQualityFilter.rejection(for: chunk) == nil)
    }

    @Test("\"Por\" iniciando oração causal não é confundido com byline")
    func causalPorIsNotAByline() {
        let chunk = "Por causa da greve dos caminhoneiros, o abastecimento de combustível ficou comprometido em várias capitais."

        #expect(ChunkQualityFilter.rejection(for: chunk) == nil)
    }

    @Test("Matéria sobre publicidade não é confundida com bloco de anúncio")
    func advertisingArticleSurvives() {
        // Por isso o marcador é a frase inteira "Continua depois da publicidade", e não o
        // substantivo solto: "publicidade" tem uso jornalístico corrente.
        let chunk = "O mercado de publicidade digital cresceu 12% no primeiro semestre, segundo levantamento divulgado pela associação do setor."

        #expect(ChunkQualityFilter.rejection(for: chunk) == nil)
        #expect(ChunkQualityFilter.rejection(for: "Continua depois da publicidade") == .navigation)
    }

    @Test("Título com barra vertical mas pontuação de frase é tratado como texto, não título")
    func pipedSentenceIsNotAPageTitle() {
        let chunk = "O levantamento cobriu três estados | Bahia, Sergipe e Alagoas | e ouviu 2.400 pessoas ao longo de maio."

        #expect(ChunkQualityFilter.rejection(for: chunk) == nil)
    }

    // MARK: - `keeping`

    @Test("keeping preserva a ordem e remove só os chunks sem proposição")
    func keepingPreservesOrder() {
        let chunks = [
            "Navegue direto pelo app Por Giulia Vidale — São Paulo 27/04/2023 15h57",
            "A vacinação contra a gripe pode reduzir significativamente o risco de infarto e AVC.",
            "Fim do Mais lidas",
            "O estudo acompanhou 12 mil pacientes ao longo de quatro anos, segundo os pesquisadores.",
        ]

        #expect(ChunkQualityFilter.keeping(chunks) == [chunks[1], chunks[3]])
    }

    @Test("Artigo cujo único chunk é ruído sai sem nenhum chunk")
    func noiseOnlyArticleKeepsNothing() {
        // O caso do Web Story: sem chunk restante, o artigo não vira fonte válida.
        let chunks = ["Title: Torcida do Bahia faz mosaico para Everton Ribeiro após cura do câncer | Web Stories CNN Brasil"]

        #expect(ChunkQualityFilter.keeping(chunks).isEmpty)
    }

    // MARK: - Integração com o chunker (RF-06.1)

    @Test("Linha de navegação não contamina o parágrafo seguinte pela sobreposição")
    func navigationDoesNotLeakIntoTheNextChunk() {
        // Sem o filtro por parágrafo, "Fim do Mais lidas" viraria a sobreposição do chunk
        // seguinte e derrubaria com ele o parágrafo legítimo de baixo.
        let text = """
        A vacinação contra a gripe pode reduzir significativamente o risco de infarto e AVC, \
        explicou o cardiologista responsável pelo estudo.
        Fim do Mais lidas
        O levantamento acompanhou 12 mil pacientes ao longo de quatro anos e foi publicado \
        nesta quinta-feira em uma revista científica.
        """

        let chunks = ChunkQualityFilter.keeping(TextChunker().chunks(from: text))

        #expect(chunks.count == 2)
        #expect(chunks.allSatisfy { !$0.contains("Mais lidas") })
        #expect(chunks.contains { $0.contains("12 mil pacientes") })
        #expect(chunks.contains { $0.contains("risco de infarto") })
    }
}
