import AppKit
import QuickLookThumbnailing
import FinderWheelCore

struct ReorderItem: Identifiable, Equatable {
    let id = UUID()
    let url: URL
}

@MainActor
@Observable
final class ReorderModel {
    var items: [ReorderItem]
    var thumbnails: [UUID: NSImage] = [:]

    init(urls: [URL]) {
        items = Reorder.naturalOrder(urls).map { ReorderItem(url: $0) }
    }

    func move(id: UUID, onto targetID: UUID) {
        guard let item = items.first(where: { $0.id == id }),
              let target = items.first(where: { $0.id == targetID }) else { return }
        items = Reorder.move(item, onto: target, in: items)
    }

    func loadThumbnails() async {
        for item in items {
            let request = QLThumbnailGenerator.Request(fileAt: item.url, size: CGSize(width: 72, height: 92),
                                                       scale: 2, representationTypes: .thumbnail)
            if let representation = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request) {
                thumbnails[item.id] = representation.nsImage
            }
        }
    }
}
