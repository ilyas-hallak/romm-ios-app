import Testing
import Foundation
@testable import romm

@MainActor
struct CoverPrefetchWindowTests {

    private struct Item: Identifiable {
        let id: Int
        let cover: String?
    }

    /// Collects what the window handed to the image pipeline instead of downloading anything.
    private final class PrefetchRecorder {
        private(set) var batches: [[URL]] = []

        var requestedIndices: Set<Int> {
            Set(batches.flatMap { $0 }.compactMap(Self.index(of:)))
        }

        func record(_ urls: [URL]) {
            batches.append(urls)
        }

        static func index(of url: URL) -> Int? {
            Int(url.deletingPathExtension().lastPathComponent)
        }
    }

    private func makeItems(_ count: Int, coverAt: (Int) -> Bool = { _ in true }) -> [Item] {
        (0..<count).map { Item(id: $0, cover: coverAt($0) ? "https://romm.example.com/covers/\($0).png" : nil) }
    }

    /// Window of 10 items, so the refill step is 5 and the assertions stay readable.
    private func makeWindow(_ recorder: PrefetchRecorder) -> CoverPrefetchWindow {
        CoverPrefetchWindow(windowSize: 10, prefetch: { urls, _ in recorder.record(urls) })
    }

    @Test func updateWarmsTheStartOfTheList() {
        let recorder = PrefetchRecorder()
        let window = makeWindow(recorder)

        window.update(with: makeItems(100)) { $0.cover }

        #expect(recorder.batches.count == 1)
        #expect(recorder.requestedIndices == Set(0...9))
    }

    @Test func scrollingForwardExtendsTheWindow() {
        let recorder = PrefetchRecorder()
        let window = makeWindow(recorder)
        window.update(with: makeItems(100)) { $0.cover }

        window.itemAppeared(id: 5)
        window.itemAppeared(id: 20)

        #expect(recorder.batches.count == 3)
        // The window reaches ahead of the appearing cell and keeps a small backwards margin.
        #expect(recorder.requestedIndices.contains(30))
        #expect(recorder.requestedIndices.isSuperset(of: Set(15...30)))
    }

    @Test func smallMovementsDoNotTriggerAnotherPrefetch() {
        let recorder = PrefetchRecorder()
        let window = makeWindow(recorder)
        window.update(with: makeItems(100)) { $0.cover }
        let batchesAfterUpdate = recorder.batches.count

        // Everything below the refill step of 5 is already covered by the current window.
        window.itemAppeared(id: 1)
        window.itemAppeared(id: 2)
        window.itemAppeared(id: 3)

        #expect(recorder.batches.count == batchesAfterUpdate)
    }

    @Test func jumpingBackwardsPrefetchesTheLowerRangeAgain() {
        // The regression this window was rebuilt for: with a high-water mark, jumping to index 60
        // and back to index 10 left the whole range in between unloaded for good.
        let recorder = PrefetchRecorder()
        let window = makeWindow(recorder)
        window.update(with: makeItems(100)) { $0.cover }

        window.itemAppeared(id: 60)
        let batchesAfterJump = recorder.batches.count
        window.itemAppeared(id: 10)

        #expect(recorder.batches.count == batchesAfterJump + 1)
        #expect(Set(recorder.batches.last!.compactMap(PrefetchRecorder.index(of:))) == Set(5...20))
    }

    @Test func itemsWithoutACoverAreSkipped() {
        let recorder = PrefetchRecorder()
        let window = makeWindow(recorder)

        window.update(with: makeItems(20, coverAt: { $0.isMultiple(of: 2) })) { $0.cover }

        #expect(recorder.requestedIndices == Set([0, 2, 4, 6, 8]))
    }

    @Test func unknownItemIDsAreIgnored() {
        let recorder = PrefetchRecorder()
        let window = makeWindow(recorder)
        window.update(with: makeItems(100)) { $0.cover }
        let batchesAfterUpdate = recorder.batches.count

        window.itemAppeared(id: 4242)

        #expect(recorder.batches.count == batchesAfterUpdate)
    }

    @Test func resetRestoresTheInitialState() {
        let recorder = PrefetchRecorder()
        let window = makeWindow(recorder)
        window.update(with: makeItems(100)) { $0.cover }
        window.itemAppeared(id: 60)

        window.reset()
        // Nothing is known anymore, so a reported cell cannot be located.
        window.itemAppeared(id: 60)
        let batchesAfterReset = recorder.batches.count

        // And a fresh list starts warming at the top again.
        window.update(with: makeItems(100)) { $0.cover }

        #expect(recorder.batches.count == batchesAfterReset + 1)
        #expect(Set(recorder.batches.last!.compactMap(PrefetchRecorder.index(of:))) == Set(0...9))
    }
}
