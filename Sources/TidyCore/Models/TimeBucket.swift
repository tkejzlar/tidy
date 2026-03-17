// Sources/TidyCore/Models/TimeBucket.swift
import Foundation

public enum TimeBucket: String, Codable, Sendable {
    case morning, midday, afternoon, evening, night

    /// Initialize from hour (0–23)
    public init(hour: Int) {
        switch hour {
        case 6..<12:  self = .morning
        case 12..<14: self = .midday
        case 14..<18: self = .afternoon
        case 18..<22: self = .evening
        default:      self = .night     // 22–5
        }
    }

    /// Initialize from a Date, using current calendar
    public init(date: Date) {
        let hour = Calendar.current.component(.hour, from: date)
        self.init(hour: hour)
    }
}
