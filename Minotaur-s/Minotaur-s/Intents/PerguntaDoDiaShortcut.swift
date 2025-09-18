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
                "Mostre a pergunta no dia no \(.applicationName)",

                "Qual é a pergunta do dia do \(.applicationName)",
                "Qual é a pergunta no dia no \(.applicationName)",
                
                "Qual a pergunta do dia do \(.applicationName)",
                "Qual a pergunta no dia no \(.applicationName)",
                
                "Qual a pergunta do  \(.applicationName)",
                "Qual a pergunta no  \(.applicationName)",
                
                "Qual é a notícia do dia do \(.applicationName)",
                "Qual é a notícia do dia no \(.applicationName)",

                "Qual é a notícia do \(.applicationName)",
                "Qual é a notícia no \(.applicationName)",

                "Qual a notícia do \(.applicationName)",
                "Qual a notícia no \(.applicationName)",

                "Pergunta do dia no \(.applicationName)",
                "Pergunta do dia do \(.applicationName)",

                
                "Me mostre a notícia do dia do \(.applicationName)",
                "Me mostre a notícia do dia no \(.applicationName)",

                
                "Quero a pergunta de hoje no \(.applicationName)",
                "Quero a pergunta de hoje do \(.applicationName)",

                
                "Diga a pergunta do dia do \(.applicationName)",
                "Diga a pergunta do dia no \(.applicationName)",

                
                "Qual é a fake news do dia no \(.applicationName)",
                "Qual é a verdade ou farsa do dia no \(.applicationName)",
                
                
                "Abrir pergunta do dia no \(.applicationName)",
                "Abrir pergunta do dia do \(.applicationName)",

                
                "Checar notícia do dia no \(.applicationName)",
                "Checar notícia do dia do \(.applicationName)",

                "Ver a pergunta de hoje do \(.applicationName)",
                "Ver a pergunta de hoje no \(.applicationName)",

                "Me diga a pergunta no \(.applicationName)",
                "Me diga a pergunta do \(.applicationName)",

                "Notícia do dia no \(.applicationName)",
                "Notícia do dia do \(.applicationName)",

                "Qual é a manchete do dia no \(.applicationName)",
                "Qual é a manchete do dia do \(.applicationName)",

                "Abrir notícia no \(.applicationName)",
                "Abrir notícia do \(.applicationName)",

                "Qual notícia está no \(.applicationName)",
                "O que o \(.applicationName) tem hoje",
                
                "pergunta do \(.applicationName)",
                "pergunta no \(.applicationName)",

            ],

            shortTitle: "Mostrar pergunta do dia",
            systemImageName: "newspaper"
        ),
        
        // Responder pergunta
        AppShortcut(
            intent: ResponderPerguntaIntent(),
            phrases: [
                "Minha resposta é \(\.$resposta) no \(.applicationName)",
                "Eu respondo \(\.$resposta) no \(.applicationName)",
                "Acho que é \(\.$resposta) no \(.applicationName)",
                "eu acho que é \(\.$resposta) no \(.applicationName)",
                "A noticia é \(\.$resposta) no \(.applicationName)",
                "É \(\.$resposta) no \(.applicationName)",
                "Eu digo que é \(\.$resposta) no \(.applicationName)",
                "Minha escolha é \(\.$resposta) no \(.applicationName)",
                "Eu confirmo \(\.$resposta) no \(.applicationName)",
                "Respondo que é \(\.$resposta) no \(.applicationName)",
                "Eu penso que é \(\.$resposta) no \(.applicationName)",
                "Eu acredito que seja \(\.$resposta) no \(.applicationName)",

                "No \(.applicationName) é \(\.$resposta)",
                "A resposta é \(\.$resposta) no \(.applicationName)",
                "Estou escolhendo \(\.$resposta) no \(.applicationName)",
                "Eu escolho \(\.$resposta) no \(.applicationName)",
                "Quero responder \(\.$resposta) no \(.applicationName)",
                "Registrar resposta \(\.$resposta) no \(.applicationName)",
                "Marcar como \(\.$resposta) no \(.applicationName)",
                "Eu digo \(\.$resposta) no \(.applicationName)",
                "Coloco \(\.$resposta) no \(.applicationName)",
                "Vou de \(\.$resposta) no \(.applicationName)",

                "Confirmo que é \(\.$resposta) no \(.applicationName)",
                "Minha opinião é \(\.$resposta) no \(.applicationName)",
                "Eu respondo que é \(\.$resposta) no \(.applicationName)",
                "Eu marco \(\.$resposta) no \(.applicationName)",
                "Responder \(\.$resposta) no \(.applicationName)",
                "Defino \(\.$resposta) no \(.applicationName)",
                "Eu considero que é \(\.$resposta) no \(.applicationName)",
                "Estou certo de que é \(\.$resposta) no \(.applicationName)",
                "Acredito que é \(\.$resposta) no \(.applicationName)",
                "Eu aposto que é \(\.$resposta) no \(.applicationName)"
            ],

            shortTitle: "Responder pergunta",
            systemImageName: "checkmark.circle"
        )
    ]
}

// DELETAR PRIMEIRA LINHA DO BANCO
