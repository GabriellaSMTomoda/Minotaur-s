import SwiftUI

/// Aviso obrigatório apresentado na primeira entrada do Verificador.
struct VerificationPrivacyNoticeView: View {
    let acknowledge: () -> Void
    @State private var isShowingPolicy = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Image(systemName: "hand.raised.fill")
                        .font(.largeTitle)
                        .foregroundStyle(Color("azul"))
                        .accessibilityHidden(true)

                    Text(VerificationPrivacyPresentation.noticeTitle)
                        .font(.title2.bold())
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier("verificationPrivacyNoticeTitle")

                    Text(VerificationPrivacyPresentation.noticeMessage)
                        .font(.body)
                        .fixedSize(horizontal: false, vertical: true)

                    Button {
                        isShowingPolicy = true
                    } label: {
                        Label("Ler política de privacidade", systemImage: "doc.text")
                    }
                    .accessibilityIdentifier("verificationPrivacyNoticePolicyLink")
                }
                .frame(maxWidth: 680, alignment: .leading)
                .padding()
                .frame(maxWidth: .infinity)
            }
            .safeAreaInset(edge: .bottom) {
                Button("Entendi e continuar", action: acknowledge)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .tint(Color("azul"))
                    .frame(maxWidth: 680)
                    .frame(minHeight: 44)
                    .padding()
                    .background(.bar)
                    .accessibilityHint("Registra que você leu o aviso e abre o Verificador.")
                    .accessibilityIdentifier("verificationPrivacyAcknowledgeButton")
            }
            .navigationTitle("Privacidade")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(isPresented: $isShowingPolicy) {
                VerificationPrivacyPolicyView()
                    .navigationBarBackButtonHidden(true)
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button {
                                isShowingPolicy = false
                            } label: {
                                Label("Voltar ao aviso", systemImage: "chevron.backward")
                            }
                            .accessibilityIdentifier("verificationPrivacyPolicyBackButton")
                        }
                    }
            }
        }
        .interactiveDismissDisabled()
    }
}

/// Conteúdo permanente e offline da política, reutilizado no aviso e na sheet do toolbar.
struct VerificationPrivacyPolicyView: View {
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                Text(VerificationPrivacyPresentation.policyTitle)
                    .font(.title.bold())
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("verificationPrivacyPolicyTitle")

                Text("Em vigor desde \(VerificationPrivacyPresentation.effectiveDate)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Text(VerificationPrivacyPresentation.introduction)
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)

                ForEach(VerificationPrivacyPresentation.sections) { section in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(section.title)
                            .font(.headline)
                            .accessibilityAddTraits(.isHeader)
                        Text(section.body)
                            .font(.body)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("Políticas dos provedores")
                        .font(.headline)
                        .accessibilityAddTraits(.isHeader)

                    Link("Privacidade da Tavily", destination: VerificationPrivacyPresentation.tavilyPrivacyURL)
                    Link("Privacidade da Cloudflare", destination: VerificationPrivacyPresentation.cloudflarePrivacyURL)
                    Link("Privacidade da Apple", destination: VerificationPrivacyPresentation.applePrivacyURL)
                    Link(
                        "Contato: \(VerificationPrivacyPresentation.contactEmail)",
                        destination: URL(string: "mailto:\(VerificationPrivacyPresentation.contactEmail)")!
                    )
                }
            }
            .frame(maxWidth: 680, alignment: .leading)
            .padding()
            .frame(maxWidth: .infinity)
        }
        .background(Color("background").ignoresSafeArea())
        .navigationTitle(VerificationPrivacyPresentation.policyTitle)
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Contêiner dispensável usado quando a política é aberta pelo botão permanente.
struct VerificationPrivacyPolicySheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VerificationPrivacyPolicyView()
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Concluído") { dismiss() }
                    }
                }
        }
    }
}

#Preview("Aviso") {
    VerificationPrivacyNoticeView(acknowledge: {})
}

#Preview("Política — texto grande e escuro") {
    NavigationStack {
        VerificationPrivacyPolicyView()
    }
    .preferredColorScheme(.dark)
    .environment(\.dynamicTypeSize, .accessibility2)
}
