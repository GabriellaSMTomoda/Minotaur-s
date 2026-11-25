import SwiftUI

struct VerificationPrivacyView: View {
    /// v3 added Wikipédia PT as a source; a new version requires a new acknowledgement.
    static let currentVersion = 3
    let requiresAcceptance: Bool
    let onContinue: () -> Void
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Label("Como sua notícia é analisada", systemImage: "hand.raised.fill")
                        .font(.title2.bold())
                    Text("A comparação com as fontes acontece neste iPhone, sem API de LLM.")
                    Text("Para localizar matérias, até três consultas de até 200 caracteres, extraídas da afirmação escolhida, passam pelo nosso proxy e pelo serviço de busca Tavily. As consultas podem conter nomes, datas e outros dados presentes no texto. Evite incluir informações pessoais ou sigilosas.")
                    Text("O app não mantém histórico das verificações. O proxy guarda somente contadores de consumo para respeitar a cota gratuita; não registra o texto, as consultas, os artigos nem os resultados. O provedor de busca trata as consultas conforme sua própria política.")
                    Link("Política de privacidade da Tavily", destination: URL(string: "https://www.tavily.com/privacy")!)
                    Text("As mesmas palavras-chave também são consultadas na Wikipédia em português pelo nosso proxy, para fatos estáveis. A Wikimedia recebe a consulta do proxy, não o endereço IP do seu iPhone.")
                    Link("Política de privacidade da Wikimedia", destination: URL(string: "https://foundation.wikimedia.org/wiki/Policy:Privacy_policy")!)
                    Text("Ao abrir matérias, o iPhone acessa os sites dos veículos. Os resultados são análises automatizadas e podem conter erros; leia sempre as fontes originais.")
                    Text("Cota gratuita: quando o limite de buscas for atingido, novas buscas ficam indisponíveis até a renovação. Nenhuma cobrança é feita pelo app.")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
            }
            .safeAreaInset(edge: .bottom) {
                Button(requiresAcceptance ? "Entendi e continuar" : "Fechar", action: onContinue)
                    .buttonStyle(.borderedProminent).controlSize(.large)
                    .frame(maxWidth: .infinity).padding().background(.bar)
            }
            .navigationTitle("Privacidade")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
