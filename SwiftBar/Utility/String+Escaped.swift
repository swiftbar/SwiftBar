import Foundation

extension String {
    func escaped() -> Self {
        guard self.contains(" ") else {return self}
        return "'\(self)'"
    }
}
