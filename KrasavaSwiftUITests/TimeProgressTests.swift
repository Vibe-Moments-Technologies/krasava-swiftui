@testable import KrasavaSwiftUI
import Foundation
import Testing

@Suite("Прогресс временных интервалов")
struct TimeProgressTests {
    private let start = TimeOfDay(hour: 10, minute: 30)
    private let end = TimeOfDay(hour: 10, minute: 40)

    @Test("Прогресс внутри интервала считается по минутам")
    func insideInterval() {
        #expect(TimeProgress.fraction(start: start, end: end, nowMinutes: 630) == 0)
        #expect(TimeProgress.fraction(start: start, end: end, nowMinutes: 635) == 0.5)
    }

    @Test("До и после интервала прогресса нет")
    func outsideInterval() {
        #expect(TimeProgress.fraction(start: start, end: end, nowMinutes: 629) == nil)
        #expect(TimeProgress.fraction(start: start, end: end, nowMinutes: 640) == nil)
    }

    @Test("Нулевой интервал не делит на ноль")
    func zeroLength() {
        #expect(TimeProgress.fraction(start: start, end: start, nowMinutes: 630) == nil)
    }
}