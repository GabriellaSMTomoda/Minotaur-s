//
//  DateFormatterStorage.swift
//  Minotaur-s
//
//  Created by Gabriella San Martino Tomoda on 15/09/25.
//

import Foundation

class DateFormatterStorage {
    static let shared = DateFormatterStorage()
    
    private let formatter: DateFormatter
    
    private init() {
        formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd" // só dia, sem hora
        formatter.locale = Locale(identifier: "pt_BR")
        formatter.timeZone = TimeZone.current
    }
    
    func stringFromDate(_ date: Date) -> String {
        return formatter.string(from: date)
    }
    
    func dateFromString(_ string: String) -> Date? {
        return formatter.date(from: string)
    }
}




