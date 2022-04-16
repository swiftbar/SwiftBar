import Foundation

extension String {
    func escaped() -> Self {
        guard contains(" ") else { return self }
        return "'\(self)'"
    }
}

extension String {
    func getURL() -> URL? {
        if let url = URL(string: self) {
            return url
        }

        var characterSet = CharacterSet.urlHostAllowed
        characterSet.formUnion(.urlPathAllowed)
        if let str = addingPercentEncoding(withAllowedCharacters: characterSet) {
            return URL(string: str)
        }

        return nil
    }
}
