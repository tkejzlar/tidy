// TestHelpers.swift — Foundation utilities for tests (no Testing import here)
import Foundation

func makeTemporaryDirectory(prefix: String) -> String {
    NSTemporaryDirectory() + "\(prefix)-\(UUID().uuidString)"
}

func removeItem(atPath path: String) {
    try? FileManager.default.removeItem(atPath: path)
}

func createDirectory(atPath path: String) throws {
    try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
}

func createFile(atPath path: String) {
    FileManager.default.createFile(atPath: path, contents: nil)
}

func createFile(atPath path: String, contents: Data) {
    FileManager.default.createFile(atPath: path, contents: contents)
}

func createFile(atPath path: String, text: String) {
    FileManager.default.createFile(atPath: path, contents: Data(text.utf8))
}

func fileExists(atPath path: String) -> Bool {
    FileManager.default.fileExists(atPath: path)
}

func makeTempFilePath(prefix: String, extension ext: String) -> String {
    NSTemporaryDirectory() + "\(prefix)-\(UUID().uuidString).\(ext)"
}

func writeText(_ text: String, toFile path: String) throws {
    try (text as NSString).write(toFile: path, atomically: true, encoding: String.Encoding.utf8.rawValue)
}

func makeURL(string: String) -> URL {
    URL(string: string)!
}

/// Creates a minimal DOCX file at the given path containing the supplied text.
func createMinimalDOCX(at path: String, text: String) throws {
    let tmpDir = NSTemporaryDirectory() + "docx-\(UUID().uuidString)"
    try FileManager.default.createDirectory(atPath: tmpDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(atPath: tmpDir) }

    // word/document.xml
    let wordDir = tmpDir + "/word"
    try FileManager.default.createDirectory(atPath: wordDir, withIntermediateDirectories: true)
    let documentXML = """
    <?xml version="1.0" encoding="UTF-8"?>
    <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
      <w:body><w:p><w:r><w:t>\(text)</w:t></w:r></w:p></w:body>
    </w:document>
    """
    try documentXML.write(toFile: wordDir + "/document.xml", atomically: true, encoding: .utf8)

    // [Content_Types].xml
    let contentTypes = """
    <?xml version="1.0" encoding="UTF-8"?>
    <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
      <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
      <Default Extension="xml" ContentType="application/xml"/>
      <Override PartName="/word/document.xml"
        ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
    </Types>
    """
    try contentTypes.write(toFile: tmpDir + "/[Content_Types].xml", atomically: true, encoding: .utf8)

    // Zip into a .docx using ditto (no --keepParent so contents are at root of archive)
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
    process.arguments = ["-c", "-k", "--sequesterRsrc", tmpDir, path]
    try process.run()
    process.waitUntilExit()
}
