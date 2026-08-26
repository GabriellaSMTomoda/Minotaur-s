import Foundation

/// Persistência mínima do aviso de privacidade do Verificador.
///
/// Guardar uma versão, em vez de um booleano, permite reapresentar o aviso se a forma de
/// tratamento da afirmação mudar no futuro. O valor fica no domínio padrão do próprio app;
/// não usa App Group, iCloud nem qualquer armazenamento remoto.
struct VerificationPrivacyNoticeStore {
    static let currentVersion = 1
    static let defaultsKey = "verificadorPrivacyNoticeVersion"

    private let defaults: UserDefaults
    private let noticeVersion: Int

    init(
        defaults: UserDefaults = .standard,
        noticeVersion: Int = VerificationPrivacyNoticeStore.currentVersion
    ) {
        precondition(noticeVersion > 0, "A versão do aviso de privacidade deve ser positiva.")
        self.defaults = defaults
        self.noticeVersion = noticeVersion
    }

    /// `true` numa instalação nova ou quando o texto obrigatório ganhou uma versão nova.
    var shouldShowNotice: Bool {
        defaults.integer(forKey: Self.defaultsKey) < noticeVersion
    }

    /// Só deve ser chamado pela ação explícita “Entendi e continuar”.
    func acknowledgeNotice() {
        defaults.set(noticeVersion, forKey: Self.defaultsKey)
    }
}
