import Foundation
import Testing
@testable import Minotaur_s

struct VerificationPrivacyTests {

    @Test("Instalação nova mostra o aviso até o reconhecimento explícito")
    func freshInstallAndAcknowledgement() throws {
        let (defaults, suiteName) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = VerificationPrivacyNoticeStore(defaults: defaults)

        #expect(store.shouldShowNotice)

        store.acknowledgeNotice()

        #expect(!store.shouldShowNotice)
        #expect(
            defaults.integer(forKey: VerificationPrivacyNoticeStore.defaultsKey)
                == VerificationPrivacyNoticeStore.currentVersion
        )
    }

    @Test("Uma versão nova reapresenta o aviso sem apagar o reconhecimento anterior")
    func newNoticeVersionShowsAgain() throws {
        let (defaults, suiteName) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let firstVersion = VerificationPrivacyNoticeStore(defaults: defaults, noticeVersion: 1)
        firstVersion.acknowledgeNotice()
        #expect(!firstVersion.shouldShowNotice)

        let secondVersion = VerificationPrivacyNoticeStore(defaults: defaults, noticeVersion: 2)
        #expect(secondVersion.shouldShowNotice)
        #expect(defaults.integer(forKey: VerificationPrivacyNoticeStore.defaultsKey) == 1)

        secondVersion.acknowledgeNotice()
        #expect(!secondVersion.shouldShowNotice)
    }

    @Test("Aviso descreve a primeira frase e usa o limite real da busca")
    func noticeMatchesSearchContract() {
        let notice = VerificationPrivacyPresentation.noticeMessage.lowercased()

        #expect(notice.contains("primeira frase"))
        #expect(notice.contains("\(SearchQueryBuilder.maxQueryLength) caracteres"))
        #expect(notice.contains("tavily"))
        #expect(notice.contains("core ml"))
        #expect(notice.contains("não mantém histórico"))
    }

    @Test("Política cobre provedores, dados locais, ausência de tracking e contato")
    func policyHasRequiredDisclosures() {
        let policy = ([VerificationPrivacyPresentation.introduction]
            + VerificationPrivacyPresentation.sections.map(\.body))
            .joined(separator: " ")
            .lowercased()

        let requiredTerms = [
            "primeira frase",
            "cloudflare",
            "tavily",
            "endereço ip",
            "core ml",
            "progresso necessário ao quiz",
            "não possui anúncios",
            "não rastreia",
            "não mantêm cópia das verificações",
            VerificationPrivacyPresentation.contactEmail.lowercased(),
        ]

        for term in requiredTerms {
            #expect(policy.contains(term), "A política não contém: \(term)")
        }
    }

    @Test("Bundle contém manifesto próprio com coleta, tracking e UserDefaults corretos")
    func bundledPrivacyManifest() throws {
        let url = try #require(
            Bundle.main.url(forResource: "PrivacyInfo", withExtension: "xcprivacy")
        )
        let data = try Data(contentsOf: url)
        let root = try #require(
            try PropertyListSerialization.propertyList(from: data, format: nil)
                as? [String: Any]
        )

        #expect(root["NSPrivacyTracking"] as? Bool == false)
        #expect((root["NSPrivacyTrackingDomains"] as? [String])?.isEmpty == true)

        let collected = try #require(
            root["NSPrivacyCollectedDataTypes"] as? [[String: Any]]
        )
        let collectedTypes = Set(collected.compactMap {
            $0["NSPrivacyCollectedDataType"] as? String
        })
        #expect(collectedTypes == [
            "NSPrivacyCollectedDataTypeOtherUserContent",
            "NSPrivacyCollectedDataTypeSearchHistory",
        ])

        for item in collected {
            #expect(item["NSPrivacyCollectedDataTypeLinked"] as? Bool == false)
            #expect(item["NSPrivacyCollectedDataTypeTracking"] as? Bool == false)
            #expect(item["NSPrivacyCollectedDataTypePurposes"] as? [String] == [
                "NSPrivacyCollectedDataTypePurposeAppFunctionality"
            ])
        }

        let accessed = try #require(
            root["NSPrivacyAccessedAPITypes"] as? [[String: Any]]
        )
        #expect(accessed.count == 1)
        #expect(
            accessed[0]["NSPrivacyAccessedAPIType"] as? String
                == "NSPrivacyAccessedAPICategoryUserDefaults"
        )
        #expect(accessed[0]["NSPrivacyAccessedAPITypeReasons"] as? [String] == ["CA92.1"])
    }

    private func isolatedDefaults() throws -> (UserDefaults, String) {
        let suiteName = "VerificationPrivacyTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        return (defaults, suiteName)
    }
}
