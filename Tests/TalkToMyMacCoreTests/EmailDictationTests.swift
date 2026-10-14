import XCTest
@testable import TalkToMyMacCore

// Ported from BetterWispr's CoreTests.
final class EmailDictationTests: XCTestCase {
    func testEmailDictationLaysOutGreetingBodyAndSignOff() {
        XCTAssertEqual(EmailDictation.compose("Write an email to Sarah saying I will be on holiday tomorrow. Thanks. Best regards, Cardic."), "Hi Sarah,\n\nI will be on holiday tomorrow. Thanks.\n\nBest regards,\nCardic")
        XCTAssertEqual(EmailDictation.compose("Draft an email to John that the report is ready, kind regards, cardic."), "Hi John,\n\nThe report is ready.\n\nKind regards,\nCardic")
        XCTAssertEqual(EmailDictation.compose("write an email to priya patel saying that the deploy is done"), "Hi Priya Patel,\n\nThe deploy is done.")
        XCTAssertEqual(EmailDictation.compose("Write an email to the team, saying lunch is at noon. Cheers, Kartik."), "Hi Team,\n\nLunch is at noon.\n\nCheers,\nKartik")
        XCTAssertEqual(EmailDictation.compose("Write an email to Sam saying I'm out today. Thanks."), "Hi Sam,\n\nI'm out today.\n\nThanks")
        XCTAssertEqual(EmailDictation.compose("Write an email to Sam saying thanks."), "Hi Sam,\n\nThanks.")
        XCTAssertEqual(EmailDictation.compose("Write an email to Sam saying I'm out. Thanks, see you soon."), "Hi Sam,\n\nI'm out. Thanks, see you soon.")
    }

    func testEmailDictationIgnoresOrdinaryDictation() {
        XCTAssertEqual(EmailDictation.compose("I will write an email to Sarah saying I'm late."), nil)
        XCTAssertEqual(EmailDictation.compose("Write an email to Sarah."), nil)
        XCTAssertEqual(EmailDictation.compose("Send the report to Sarah saying it is done."), nil)
        XCTAssertEqual(EmailDictation.compose("I live in Delhi."), nil)
    }
}
