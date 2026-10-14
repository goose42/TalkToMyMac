import XCTest
@testable import TalkToMyMacCore

// Ported from BetterWispr's CoreTests.
final class VoiceCommandsTests: XCTestCase {
    func testVoiceCommandsInsertPunctuationAndBacktrack() {
        XCTAssertEqual(VoiceCommands.apply("hello comma world"), "hello, world")
        XCTAssertEqual(VoiceCommands.apply("Hello, comma, how are you"), "Hello, how are you")
        XCTAssertEqual(VoiceCommands.apply("thanks add a comma see you soon"), "thanks, see you soon")
        XCTAssertEqual(VoiceCommands.apply("is it done question mark"), "is it done?")
        XCTAssertEqual(VoiceCommands.apply("first new line second"), "first\nSecond")
        XCTAssertEqual(VoiceCommands.apply("Send it Monday. Sorry, remove that. Send it Tuesday."), "Send it Tuesday.")
        XCTAssertEqual(VoiceCommands.apply("Let's meet at 5, sorry, remove that, let's meet at 6"), "Let's meet at 6")
        XCTAssertEqual(VoiceCommands.apply("Hi team. Ship it today scratch that tomorrow"), "Hi team. Tomorrow")
        XCTAssertEqual(VoiceCommands.apply("Please remove that file"), "Please remove that file")
        XCTAssertEqual(VoiceCommands.apply("I love the Oxford comma"), "I love the Oxford comma")
        XCTAssertEqual(VoiceCommands.apply("the period ended"), "the period ended")
        XCTAssertEqual(VoiceCommands.apply("Exclamatory mark."), "!")
        XCTAssertEqual(VoiceCommands.apply("Hyphen."), "-")
        XCTAssertEqual(VoiceCommands.apply("colon"), ":")
        XCTAssertEqual(VoiceCommands.apply("dash"), "–")
    }

    func testVoiceCommandsTurnAtTheRateIntoMentions() {
        XCTAssertEqual(VoiceCommands.apply("ping at the rate KV about it"), "ping @KV about it")
        XCTAssertEqual(VoiceCommands.apply("ask at sign Sam"), "ask @Sam")
        XCTAssertEqual(VoiceCommands.apply("growing at the rate of 5 percent"), "growing at the rate of 5%")
    }

    func testVoiceCommandsWriteSpokenNumbersAsDigits() {
        let expected = [
            "The budget is two hundred and fifty thousand dollars.": "The budget is 250,000 dollars.",
            "We have one hundred people and two hundred chairs.": "We have 100 people and 200 chairs.",
            "one hundred or two hundred": "100 or 200",
            "one hundred and two hundred": "100 and 200",
            "from zero to twenty seven": "from zero to 27",
            "twenty-seven": "27",
            "Two hundred people came.": "200 people came.",
            "It cost two hundred.": "It cost 200.",
            "I waited ten minutes": "I waited 10 minutes",
            "one thousand two hundred": "1200",
            "two thousand twenty six": "2026",
            "one million two hundred thousand": "1,200,000",
            "five million": "5 million",
            "two point five million": "2.5 million",
            "The value is three point five.": "The value is 3.5.",
            "Update the changelog for zero point one point one.": "Update the changelog for 0.1.1.",
            "a hundred and fifty": "150",
            "It has one hundred K views.": "It has 100K views.",
            "Growth was ten percent this year, almost twenty five percentage.": "Growth was 10% this year, almost 25%.",
            "five percent": "5%",
            "5 percent": "5%",
            "5 per cent": "5%",
            "fifty percent.": "50%.",
            "twenty, thirty": "20, 30",
            "I have one lakh followers.": "I have 1 lakh followers.",
            "The flat costs fifty lakhs.": "The flat costs 50 lakhs.",
            "We raised two lakh fifty thousand rupees.": "We raised 2,50,000 rupees.",
            "The budget is one crore twenty lakh.": "The budget is 1,20,00,000.",
            "Revenue was two point five crore.": "Revenue was 2.5 crore.",
            "It costs twelve hundred dollars.": "It costs 1200 dollars.",
            "twenty five hundred": "2500",
            "I have over ten thousand hundred followers.": "I have over 10,000 hundred followers.",
            "Ten thousand one lakh.": "10,000 1 lakh.",
            "five thousand million": "5000 million",
        ]
        for (spoken, written) in expected {
            XCTAssertEqual(VoiceCommands.apply(spoken), written)
        }
        let unchanged = [
            "one of them", "no one", "at one point we", "two or three", "give me five minutes", "at one point we left",
            "a hundred times", "a thousand thanks", "what percentage of users", "nineteen ninety nine", "fifty fifty",
            "eleven thirty", "twenty first century", "call 5 5 5 now",
        ]
        for text in unchanged {
            XCTAssertEqual(VoiceCommands.apply(text), text)
        }
    }

    func testVoiceCommandsWriteSpokenSymbols() {
        let expected = [
            "Ping at the rate K V about it.": "Ping @KV about it.",
            "At the rate k v.": "@kv.",
            "At the rate.": "@",
            "at sign": "@",
            "at symbol": "@",
            "Send it to kartik at the rate gmail dot com.": "Send it to kartik@gmail.com.",
            "Send it to Kardich at the rategmail.com.": "Send it to Kardich@gmail.com.",
            "Send it to Kardak at the rategmail. com": "Send it to Kardak@gmail.com",
            "visit example dot com": "visit example.com",
            "Book it on mysite dot in.": "Book it on mysite.in.",
            "Post it with hashtag launch day.": "Post it with #launch day.",
            "hash tag launch": "#launch",
            "Check issue hash forty two.": "Check issue #42.",
            "Hash.": "#",
            "Hashtag.": "#",
            "hash sign": "#",
            "hash symbol": "#",
            "Percentage.": "%",
            "Percent.": "%",
            "percent sign": "%",
            "percentage sign": "%",
        ]
        for (spoken, written) in expected {
            XCTAssertEqual(VoiceCommands.apply(spoken), written)
        }
        for text in [
            "the interest at the rate is high", "the dot com bubble", "a red dot in the corner",
            "Sales fell. Net income rose.",
            "We need to hash out a plan using a hash map.",
        ] {
            XCTAssertEqual(VoiceCommands.apply(text), text)
        }
    }

}
