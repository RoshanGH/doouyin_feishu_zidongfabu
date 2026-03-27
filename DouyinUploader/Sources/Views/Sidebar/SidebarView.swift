import SwiftUI

struct SidebarView: View {
    @Binding var selection: SidebarItem?

    var body: some View {
        List(selection: $selection) {
            Section {
                ForEach(SidebarItem.allCases.filter { $0 != .settings }) { item in
                    Label(item.rawValue, systemImage: item.icon)
                        .tag(item)
                }
            }

            Section {
                Label(SidebarItem.settings.rawValue, systemImage: SidebarItem.settings.icon)
                    .tag(SidebarItem.settings)
            }
        }
        .listStyle(.sidebar)
        .frame(minWidth: 200)
    }
}
