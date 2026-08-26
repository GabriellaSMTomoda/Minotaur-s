import Foundation

/// Cópia de privacidade em um ponto testável, sem decisões de rede ou persistência na View.
enum VerificationPrivacyPresentation {
    static let noticeTitle = "Antes de verificar"
    static let policyTitle = "Política de Privacidade"
    static let effectiveDate = "26 de agosto de 2026"
    static let contactEmail = "hen.lac.sil@gmail.com"

    static var noticeMessage: String {
        """
        Para buscar fontes, o app envia ao proxy do Fato ou Farsa e à Tavily somente a primeira \
        frase da afirmação, limitada a \(SearchQueryBuilder.maxQueryLength) caracteres. A \
        Tavily pode reter essa query conforme a política dela.

        O restante do texto fica no aparelho. A comparação com as fontes usa modelos Core ML \
        locais, e o app não mantém histórico das verificações.
        """
    }

    struct PolicySection: Identifiable, Equatable {
        let title: String
        let body: String

        var id: String { title }
    }

    static let introduction = """
    Esta política explica como o Fato ou Farsa trata dados no quiz, na Pergunta do Dia e no \
    Verificador de Notícias.
    """

    static var sections: [PolicySection] {
        [
            PolicySection(
                title: "Verificador de Notícias",
                body: """
                A afirmação completa e o resultado existem apenas na memória enquanto você \
                usa o Verificador. O app não cria histórico de verificações, não sincroniza \
                esse conteúdo com iCloud e não envia o texto completo para a busca.

                Para localizar fontes, somente a primeira frase da afirmação, limitada a \
                \(SearchQueryBuilder.maxQueryLength) caracteres, é enviada por HTTPS ao proxy \
                do Minotaur-s e, em seguida, à Tavily. Embeddings e classificação NLI rodam no \
                aparelho com Core ML; nenhum serviço de nuvem produz o veredito.
                """
            ),
            PolicySection(
                title: "Proxy, Cloudflare e Tavily",
                body: """
                O proxy Cloudflare Workers existe para proteger a chave da Tavily. O código \
                do proxy não usa KV, D1 ou cache de conteúdo e não registra explicitamente o \
                corpo nem a query. A query passa pela memória do Worker para atender a busca.

                A infraestrutura da Cloudflare pode processar metadados técnicos necessários \
                à conexão, como endereço IP, horário, URL do endpoint e status da resposta, \
                conforme as práticas da Cloudflare.

                A Tavily recebe a query reduzida para retornar resultados. Sua política informa \
                que queries podem ser retidas pelo período necessário à prestação e melhoria \
                do serviço, e que partes delas podem ser usadas para melhorar respostas futuras.
                """
            ),
            PolicySection(
                title: "Sites das fontes",
                body: """
                Depois da busca, o app baixa diretamente o HTML de até cinco artigos \
                permitidos para extrair e analisar o texto. Esses sites recebem a requisição \
                normal de rede e podem processar metadados técnicos segundo suas próprias \
                políticas. A afirmação digitada não é enviada a eles.

                Quando você escolhe “Ler no site do veículo”, o artigo é aberto no navegador \
                do sistema. A navegação e eventuais cookies passam a seguir as práticas do \
                site e do Safari.
                """
            ),
            PolicySection(
                title: "Dados mantidos no aparelho",
                body: """
                O app salva localmente o progresso necessário ao quiz, a Pergunta do Dia e \
                sua data, o estado dos tutoriais e a versão reconhecida deste aviso. Esses \
                dados ficam no armazenamento privado do app e não são enviados ao proxy ou \
                à Tavily.

                Reiniciar uma partida remove o progresso correspondente. Desinstalar o app \
                remove os demais dados locais mantidos por ele.
                """
            ),
            PolicySection(
                title: "Siri e Atalhos",
                body: """
                A Pergunta do Dia e a resposta Fato ou Farsa podem ser usadas por Siri e \
                Atalhos. O app trata apenas os parâmetros necessários ao App Intent e mantém \
                a pergunta do dia localmente. O tratamento feito pelos serviços da Apple \
                segue a política de privacidade da Apple.
                """
            ),
            PolicySection(
                title: "Publicidade, rastreamento e diagnóstico",
                body: """
                O app não possui anúncios, não rastreia pessoas entre apps ou sites e não \
                integra serviços de analytics, telemetria ou crash reporting de terceiros.
                """
            ),
            PolicySection(
                title: "Retenção, escolhas e contato",
                body: """
                O Minotaur-s e seu proxy não mantêm cópia das verificações em servidor. A \
                retenção feita pela Tavily e o processamento técnico da Cloudflare seguem as \
                políticas desses provedores.

                Evite incluir dados pessoais ou sensíveis na primeira frase de uma afirmação. \
                Para dúvidas de privacidade, escreva para \(contactEmail).

                Esta política entra em vigor em \(effectiveDate). Mudanças relevantes no envio \
                da afirmação exigirão uma nova versão do aviso de primeira execução.
                """
            ),
        ]
    }

    static let tavilyPrivacyURL = URL(string: "https://www.tavily.com/privacy")!
    static let cloudflarePrivacyURL = URL(string: "https://www.cloudflare.com/privacypolicy/")!
    static let applePrivacyURL = URL(string: "https://www.apple.com/legal/privacy/")!
}
