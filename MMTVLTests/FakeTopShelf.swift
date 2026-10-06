@testable import MMTVL

/// Serves configured shelf content per tile id and records refreshes (M7 L12).
final class FakeTopShelf: TopShelfProviding {
    var contents: [String: ShelfContent] = [:]
    var refreshes: [String?] = []

    func content(for item: LaunchItem) -> ShelfContent {
        contents[item.id] ?? .banner
    }

    func refresh(focusing item: LaunchItem?) {
        refreshes.append(item?.id)
    }
}
