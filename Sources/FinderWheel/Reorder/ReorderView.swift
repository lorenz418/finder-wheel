import SwiftUI

struct ReorderView: View {
    let model: ReorderModel
    let confirm: () -> Void
    let cancel: () -> Void

    static let itemWidth: CGFloat = 88
    static let height: CGFloat = 176

    /// Panel width for a number of items, capped so long selections scroll.
    static func width(for count: Int) -> CGFloat {
        min(CGFloat(max(count, 3)) * (itemWidth + 8) + 32, 760)
    }

    var body: some View {
        VStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(model.items.enumerated()), id: \.element.id) { index, item in
                        thumbnail(item, number: index + 1)
                    }
                }
                .padding(.horizontal, 16)
            }
            HStack {
                Text("Drag to reorder")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Cancel", action: cancel)
                    .keyboardShortcut(.cancelAction)
                Button("Combine", action: confirm)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 16)
        }
        .padding(.vertical, 12)
        .frame(width: Self.width(for: model.items.count), height: Self.height)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 24))
        .animation(.easeOut(duration: 0.15), value: model.items)
        .task { await model.loadThumbnails() }
    }

    private func thumbnail(_ item: ReorderItem, number: Int) -> some View {
        VStack(spacing: 4) {
            Group {
                if let image = model.thumbnails[item.id] {
                    Image(nsImage: image).resizable().scaledToFit()
                } else {
                    RoundedRectangle(cornerRadius: 6).fill(.quaternary)
                }
            }
            .frame(width: 72, height: 92)
            .overlay(alignment: .topLeading) {
                Text("\(number)")
                    .font(.system(size: 10, weight: .bold))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(.thinMaterial, in: Capsule())
                    .padding(3)
            }
            Text(item.url.deletingPathExtension().lastPathComponent)
                .font(.system(size: 10))
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .frame(width: Self.itemWidth)
        .draggable(item.id.uuidString)
        .dropDestination(for: String.self) { dropped, _ in
            guard let first = dropped.first, let id = UUID(uuidString: first) else { return false }
            model.move(id: id, onto: item.id)
            return true
        }
    }
}
