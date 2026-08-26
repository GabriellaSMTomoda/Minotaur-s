//
//  Minotaur_sApp.swift
//  Minotaur-s
//
//  Created by Gabriella San Martino Tomoda on 18/08/25.

import AppIntents
import Foundation
import SwiftUI


 @main
 struct Minotaur_sApp: App {

#if DEBUG
     init() {
         // Estado determinístico para o teste de UI da primeira execução. Este caminho só
         // existe em builds Debug e só age quando o runner passa o argumento explicitamente.
         if ProcessInfo.processInfo.arguments.contains("-reset-verifier-privacy-notice") {
             UserDefaults.standard.removeObject(
                 forKey: VerificationPrivacyNoticeStore.defaultsKey
             )
         }
     }
#endif
     
     var body: some Scene {
         WindowGroup {
             ContentView()
         }
     }
 }
