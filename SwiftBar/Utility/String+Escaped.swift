import Foundation

extension String {
    func escaped() -> Self {
        guard contains(" ") else { return self }
        return "'\(self)'"
    }
}
