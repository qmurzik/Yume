import XCTest
@testable import AnimeApp

@MainActor
final class LibraryStoreTests: XCTestCase {
    private var fileURL: URL!

    override func setUp() async throws {
        fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("library-\(UUID().uuidString).json")
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: fileURL)
    }

    private let anime = SavedAnime(id: 52991, title: "Фрирен")

    private func episode(_ number: Double) -> SourceEpisode {
        SourceEpisode(source: .aniLibria, id: "e\(number)", number: number, title: nil, voice: "AniLibria", duration: 1500)
    }

    func testFavoritesPersist() {
        let store = LibraryStore(fileURL: fileURL)
        store.toggleFavorite(anime)
        XCTAssertTrue(store.isFavorite(52991))
        store.saveNow()

        let reloaded = LibraryStore(fileURL: fileURL)
        XCTAssertTrue(reloaded.isFavorite(52991))
        reloaded.toggleFavorite(anime)
        XCTAssertFalse(reloaded.isFavorite(52991))
    }

    func testProgressAndHistory() {
        let store = LibraryStore(fileURL: fileURL)
        store.updateProgress(anime: anime, episode: episode(1), position: 1450, duration: 1500, now: Date(timeIntervalSince1970: 1))
        store.updateProgress(anime: anime, episode: episode(2), position: 300, duration: 1500, now: Date(timeIntervalSince1970: 2))
        store.saveNow()

        let reloaded = LibraryStore(fileURL: fileURL)
        XCTAssertEqual(reloaded.history.count, 1, "one history entry per title")
        XCTAssertEqual(reloaded.record(for: 52991)?.episodeNumber, 2)
        XCTAssertEqual(reloaded.progress(animeID: 52991, episode: 1)?.isWatched, true)
        XCTAssertEqual(reloaded.progress(animeID: 52991, episode: 2)?.position, 300)
        XCTAssertEqual(reloaded.progress(animeID: 52991, episode: 2)?.isWatched, false)
        XCTAssertEqual(reloaded.preferredVoice(animeID: 52991), "AniLibria")
        XCTAssertEqual(reloaded.preferredSource(animeID: 52991), .aniLibria)
    }

    func testMarkUnwatched() {
        let store = LibraryStore(fileURL: fileURL)
        store.markWatched(true, anime: anime, episode: episode(3))
        XCTAssertEqual(store.progress(animeID: 52991, episode: 3)?.isWatched, true)
        store.markWatched(false, anime: anime, episode: episode(3))
        XCTAssertNil(store.progress(animeID: 52991, episode: 3))
    }

    func testCorruptFileStartsEmpty() throws {
        try Data("not json".utf8).write(to: fileURL)
        XCTAssertTrue(LibraryStore(fileURL: fileURL).history.isEmpty)
    }
}
