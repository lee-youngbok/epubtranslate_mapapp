import Foundation
import SwiftSoup

let xml = """
<?xml version="1.0"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0">
  <metadata>
    <dc:title>Test Book</dc:title>
  </metadata>
</package>
"""
do {
    let doc = try SwiftSoup.parse(xml, "", Parser.xmlParser())
    print("Parsed OK")
    let elements = try doc.select("metadata dc\\:title")
    print("Select OK: \(try elements.first()?.text() ?? "none")")
} catch {
    print("Error: \(error)")
}
