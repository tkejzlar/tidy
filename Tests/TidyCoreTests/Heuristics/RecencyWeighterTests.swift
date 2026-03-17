import Testing
@testable import TidyCore

@Suite("RecencyWeighter")
struct RecencyWeighterTests {
    @Test("today's weight is near 1.0")
    func today() {
        let weighter = RecencyWeighter()
        let weight = weighter.weight(daysSinceLastUse: 0)
        #expect(weight > 0.99)
    }

    @Test("weight decays exponentially at 0.95^days")
    func decay() {
        let weighter = RecencyWeighter()
        let w7 = weighter.weight(daysSinceLastUse: 7)
        let w30 = weighter.weight(daysSinceLastUse: 30)
        let w365 = weighter.weight(daysSinceLastUse: 365)
        #expect(w7 > w30)
        #expect(w30 > w365)
        #expect(abs(w7 - 0.6983) < 0.001)
        #expect(abs(w30 - 0.2146) < 0.001)
    }
}
