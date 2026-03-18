import Testing
@testable import TidyCore

@Suite("SourceCategoryMappings")
struct SourceCategoryMappingsTests {
    let mapper = SourceCategoryMapper()

    @Test("github.com maps to developer")
    func github() { #expect(mapper.categorize(domain: "github.com") == .developer) }

    @Test("gitlab.com maps to developer")
    func gitlab() { #expect(mapper.categorize(domain: "gitlab.com") == .developer) }

    @Test("drive.google.com maps to googleDrive")
    func googleDrive() { #expect(mapper.categorize(domain: "drive.google.com") == .googleDrive) }

    @Test("docs.google.com maps to googleDrive")
    func googleDocs() { #expect(mapper.categorize(domain: "docs.google.com") == .googleDrive) }

    @Test("slack-files.com maps to slack")
    func slackFiles() { #expect(mapper.categorize(domain: "slack-files.com") == .slack) }

    @Test("files.slack.com maps to slack")
    func slackCDN() { #expect(mapper.categorize(domain: "files.slack.com") == .slack) }

    @Test("mail.google.com maps to email")
    func gmail() { #expect(mapper.categorize(domain: "mail.google.com") == .email) }

    @Test("unknown domain maps to browser")
    func unknownDomain() { #expect(mapper.categorize(domain: "example.com") == .browser) }

    @Test("categorize from URL extracts domain")
    func fromURL() {
        let url = makeURL(string: "https://github.com/user/repo/releases/download/v1.0/app.zip")
        #expect(mapper.categorize(url: url) == .developer)
    }

    @Test("subdomains match parent patterns")
    func subdomain() {
        #expect(mapper.categorize(domain: "objects.githubusercontent.com") == .developer)
    }
}
