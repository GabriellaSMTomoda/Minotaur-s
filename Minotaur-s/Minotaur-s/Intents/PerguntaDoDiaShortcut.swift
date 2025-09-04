//
//  PerguntaDoDiaShortcut.swift
//  Minotaur-s
//
//  Created by Gabriella San Martino Tomoda on 02/09/25.
//


import AppIntents

struct AppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] = [
        
        // Pergunta do dia
        AppShortcut(
            intent: PerguntaDoDiaIntent(),
            phrases: [
                "Mostre a pergunta do dia do \(.applicationName)",
                "Mostre a pergunta do dia no \(.applicationName)",

                "Qual é a pergunta do dia do \(.applicationName)",
                "Qual é a pergunta do dia no \(.applicationName)",
                
                "Qual é a notícia do dia do \(.applicationName)",
                "Qual é a notícia do dia no \(.applicationName)",

                "Qual é a notícia do \(.applicationName)",
                "Qual é a notícia no \(.applicationName)",

            ],
            shortTitle: "Mostrar pergunta do dia",
            systemImageName: "newspaper"
        ),
        
        // Responder pergunta
        AppShortcut(
            intent: ResponderPerguntaIntent(),
            phrases: [
                "Responder a pergunta do dia no \(.applicationName)",
                "Minha resposta é \(\.$resposta) no \(.applicationName)",
                "Dizer que é \(\.$resposta) no \(.applicationName)",
                "Essa notícia é \(\.$resposta) no \(.applicationName)"
            ],
            shortTitle: "Responder pergunta",
            systemImageName: "checkmark.circle"
        )
    ]
}

// DELETAR PRIMEIRA LINHA DO BANCO
