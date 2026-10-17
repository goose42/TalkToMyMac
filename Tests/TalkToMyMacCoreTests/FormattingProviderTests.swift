import XCTest
@testable import TalkToMyMacCore

final class FormattingProviderTests: XCTestCase {

    // Apple's model needs no setup; remote providers need at least an API key.
    func testOnlyRemoteProvidersHaveAConfigurationPage() {
        XCTAssertFalse(FormattingProvider.appleOnDevice.hasConfiguration)
        XCTAssertTrue(FormattingProvider.groq.hasConfiguration)
        XCTAssertTrue(FormattingProvider.openRouter.hasConfiguration)
    }

    func testConfigurableProvidersListsThemInOrder() {
        XCTAssertEqual(FormattingProvider.configurable, [.groq, .openRouter])
    }
}
