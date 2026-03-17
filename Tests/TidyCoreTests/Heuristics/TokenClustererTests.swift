import Testing
@testable import TidyCore

@Suite("TokenClusterer")
struct TokenClustererTests {
    @Test("builds token sets from folder contents")
    func tokenExtraction() throws {
        let root = makeTemporaryDirectory(prefix: "tidy-tokens")
        let financeDir = "\(root)/Finance"
        try createDirectory(atPath: financeDir)
        createFile(atPath: "\(financeDir)/invoice-march-2026.pdf")
        createFile(atPath: "\(financeDir)/receipt-amazon.pdf")
        createFile(atPath: "\(financeDir)/tax-return-2025.pdf")
        defer { removeItem(atPath: root) }
        let clusterer = TokenClusterer()
        let clusters = clusterer.buildClusters(roots: [root])
        let financeCluster = clusters.first { $0.folderPath.hasSuffix("Finance") }
        #expect(financeCluster != nil)
        #expect(financeCluster!.tokens.contains("invoice"))
        #expect(financeCluster!.tokens.contains("receipt"))
        #expect(financeCluster!.tokens.contains("tax"))
    }

    @Test("scores token overlap")
    func overlapScoring() {
        let clusterer = TokenClusterer()
        let cluster = TokenCluster(folderPath: "/Finance", tokens: Set(["invoice", "receipt", "tax", "statement", "bank"]))
        let score = clusterer.overlapScore(candidateTokens: ["invoice", "march"], cluster: cluster)
        #expect(score == 0.5)
    }
}
