//
//  dadosNoticias.swift
//  Minotaur-s
//
//  Created by Gabriella San Martino Tomoda on 19/08/25.
//

//    Columns            Description
//    URL               Check article web address
//    Author            Initiative id.
//    datePublished     Check publication date
//    claimReviewed     Claim analyzed
//    reviewBody        Check text
//    Title             Title of the article
//    ratingValue       Numerical classification
//    bestRating        Lenght of the scale
//    alternativeName   Text label

import Foundation

struct Fact: Identifiable {
    let id = UUID()
    let url: String
    let autor: String
    let data: String
    let motivo: String
    let resumo: String
    let titulo: String
    let binario: String
    let assunto: String
}


