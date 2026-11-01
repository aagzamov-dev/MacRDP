import Foundation

final class KerioProfileNames: NSObject, XMLParserDelegate {
    private var names: Set<String> = []
    private var path: [String] = []
    private var label = ""

    static func readNames(from url: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".kerio/vpnclient/user.cfg")) -> Set<String>? {
        guard let stream = InputStream(url: url) else { return nil }
        let parser = XMLParser(stream: stream)
        let delegate = KerioProfileNames()
        parser.delegate = delegate
        parser.shouldResolveExternalEntities = false
        return parser.parse() ? delegate.names : nil
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        path.append(elementName)
        if elementName == "description" { label = "" }
    }
    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if path.suffix(2).elementsEqual(["connection", "description"]), label.count < 1024 { label += string }
    }
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        if path.suffix(2).elementsEqual(["connection", "description"]) {
            let name = label.trimmingCharacters(in: .whitespacesAndNewlines)
            if !name.isEmpty { names.insert(name) }
            label = ""
        }
        if !path.isEmpty { path.removeLast() }
    }
}
