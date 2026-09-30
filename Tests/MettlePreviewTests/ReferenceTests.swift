#if os(macOS)
import XCTest
@testable import MettlePreview

final class ReferenceTests: XCTestCase {
    func testReferenceGalleryHasImagesCreditsAndExternalURLs() {
        let items = MotionReference.curated
        XCTAssertEqual(items.count, 4)
        XCTAssertEqual(Set(items.map(\.id)).count, 4)
        for item in items {
            XCTAssertFalse(item.creator.isEmpty)
            XCTAssertEqual(item.source.scheme, "https")
            XCTAssertEqual(item.source.host, "rive.app")
            XCTAssertNotNil(item.thumbnail, "Missing credited thumbnail for \(item.id)")
            XCTAssertTrue(item.limitation.hasPrefix("Reference only."))
        }
    }
    func testReferencesNeverBecomeNativePlaybackAssets() {
        let session = PreviewSession(examples: [])
        session.referencesVisible = true
        XCTAssertNil(session.renderer)
        XCTAssertNil(session.document)
        XCTAssertFalse(session.hasMotion)
        XCTAssertFalse(session.playback.isPlaying)
        session.close()
        XCTAssertFalse(session.referencesVisible)
    }
}
#endif
