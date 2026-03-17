import Testing
@testable import TidyCore

@Suite("InvocationPolicy")
struct InvocationPolicyTests {
    let policy = InvocationPolicy()

    @Test("skips DMG and PKG")
    func skipInstallers() {
        #expect(policy.shouldInvoke(extension: "dmg", patternConfidence: nil, isScreenshot: false) == false)
        #expect(policy.shouldInvoke(extension: "pkg", patternConfidence: nil, isScreenshot: false) == false)
    }

    @Test("skips screenshots")
    func skipScreenshots() {
        #expect(policy.shouldInvoke(extension: "png", patternConfidence: nil, isScreenshot: true) == false)
    }

    @Test("skips high confidence (>85)")
    func skipHighConfidence() {
        #expect(policy.shouldInvoke(extension: "pdf", patternConfidence: 90, isScreenshot: false) == false)
    }

    @Test("invokes for PDF with no patterns")
    func invokeForPDF() {
        #expect(policy.shouldInvoke(extension: "pdf", patternConfidence: nil, isScreenshot: false) == true)
    }

    @Test("invokes for low confidence (<50)")
    func invokeLowConfidence() {
        #expect(policy.shouldInvoke(extension: "pdf", patternConfidence: 30, isScreenshot: false) == true)
    }

    @Test("invokes for non-screenshot PNG")
    func invokeForAmbiguousPNG() {
        #expect(policy.shouldInvoke(extension: "png", patternConfidence: nil, isScreenshot: false) == true)
    }

    @Test("invokes for unknown file type")
    func invokeForNewType() {
        #expect(policy.shouldInvoke(extension: "xyz", patternConfidence: nil, isScreenshot: false) == true)
    }

    @Test("medium confidence: text-extractable yes, others no")
    func mediumConfidence() {
        #expect(policy.shouldInvoke(extension: "zip", patternConfidence: 60, isScreenshot: false) == false)
        #expect(policy.shouldInvoke(extension: "pdf", patternConfidence: 60, isScreenshot: false) == true)
    }
}
