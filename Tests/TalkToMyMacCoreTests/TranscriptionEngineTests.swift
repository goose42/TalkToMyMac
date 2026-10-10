import XCTest
@testable import TalkToMyMacCore

final class TranscriptionEngineTests: XCTestCase {

    // Raw values and model IDs are persisted (UserDefaults, the metrics table), so they
    // must never change.
    func testRawValuesAreStable() {
        XCTAssertEqual(TranscriptionEngine.appleOnDevice.rawValue, "appleOnDevice")
        XCTAssertEqual(TranscriptionEngine.parakeetTDTv3.rawValue, "parakeetTDTv3")
    }

    func testModelIDsAreStable() {
        XCTAssertEqual(TranscriptionEngine.appleOnDevice.modelID, "apple-on-device")
        XCTAssertEqual(TranscriptionEngine.parakeetTDTv3.modelID, "parakeet-tdt-0.6b-v3")
    }

    func testDefaultIsApple() {
        XCTAssertEqual(TranscriptionEngine.default, .appleOnDevice)
    }

    func testOnlyParakeetNeedsADownload() {
        XCTAssertFalse(TranscriptionEngine.appleOnDevice.isExternal)
        XCTAssertTrue(TranscriptionEngine.parakeetTDTv3.isExternal)
    }

    func testEngineForModelIDRoundTrips() {
        for engine in TranscriptionEngine.allCases {
            XCTAssertEqual(TranscriptionEngine(modelID: engine.modelID), engine)
        }
        XCTAssertNil(TranscriptionEngine(modelID: "unknown"))
    }

    // MARK: resolve

    func testResolveUsesAppleWhenAppleSelected() {
        XCTAssertEqual(TranscriptionEngine.resolve(selected: .appleOnDevice, externalState: .ready), .appleOnDevice)
    }

    func testResolveUsesExternalModelOnceReady() {
        XCTAssertEqual(TranscriptionEngine.resolve(selected: .parakeetTDTv3, externalState: .ready), .parakeetTDTv3)
    }

    func testResolveFallsBackToAppleUntilExternalModelIsReady() {
        let notReady: [ExternalModelState] = [.notDownloaded, .downloading, .downloaded, .loading, .failed("boom")]
        for state in notReady {
            XCTAssertEqual(TranscriptionEngine.resolve(selected: .parakeetTDTv3, externalState: state),
                           .appleOnDevice, "\(state)")
        }
    }

    // MARK: ExternalModelState

    func testIsOnDisk() {
        XCTAssertFalse(ExternalModelState.notDownloaded.isOnDisk)
        XCTAssertFalse(ExternalModelState.downloading.isOnDisk)
        XCTAssertTrue(ExternalModelState.downloaded.isOnDisk)
        XCTAssertTrue(ExternalModelState.loading.isOnDisk)
        XCTAssertTrue(ExternalModelState.ready.isOnDisk)
        XCTAssertFalse(ExternalModelState.failed("x").isOnDisk)
    }
}
