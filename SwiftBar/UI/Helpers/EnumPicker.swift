import SwiftUI

public struct EnumPicker<T: Hashable & CaseIterable, V: View>: View {
    @Binding public var selected: T
    public var title: String?

    public let mapping: (T) -> V

    public var body: some View {
        Picker(selection: $selected, label: Text(title ?? "")) {
            ForEach(Array(T.allCases), id: \.self) {
                mapping($0).tag($0)
            }
        }
    }
}

public extension EnumPicker where T: RawRepresentable, T.RawValue == String, V == Text {
    init(selected: Binding<T>, title: String? = nil) {
        self.init(selected: selected, title: title) {
            Text($0.rawValue)
        }
    }
}
