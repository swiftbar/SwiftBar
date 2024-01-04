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

extension String {
    var URLEncoded: String {
        let unreservedChars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~/:"
        let unreservedCharsSet = CharacterSet(charactersIn: unreservedChars)
        let encodedString = addingPercentEncoding(withAllowedCharacters: unreservedCharsSet)!
        return encodedString
    }
}

extension String {
    var isEnclosedInQuotes: Bool {
        hasPrefix("'") && hasSuffix("'")
    }

    var needsShellQuoting: Bool {
        let specialCharacters = " \t\n\"'`$\\|&;()<>[]*?{}!^~#%"
        let shellOperators = ["&&", "||", ";", "|", "<", ">"]

        // Check if the string is exactly a logical operator
        if shellOperators.contains(self) {
            return false
        }

        return rangeOfCharacter(from: CharacterSet(charactersIn: specialCharacters)) != nil
    }

    func quoteIfNeeded() -> String {
        guard needsShellQuoting else { return self }
        return isEnclosedInQuotes ? self : "\'\(replacingOccurrences(of: "'", with: "'\\''"))\'"
    }
}
