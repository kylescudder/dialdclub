import XCTest
@testable import Diald

final class AnalysisMarkdownTests: XCTestCase {
    func testKeepsSectionsAndNumberedStepsSeparate() {
        let report = """
        **WHAT IS WORKING**
        Your strongest recipe scores **4/5**.

        **ISSUES TO WATCH**
        Keep the recipe stable.

        **NEXT THREE BREWS**
        1. Repeat the baseline.
        2. Adjust one variable.
        3. Repeat the better result.

        **TRACK NEXT**
        Log the grind setting.
        """

        let rendered = AnalysisMarkdown.render(report)

        XCTAssertEqual(String(rendered.characters), report.replacingOccurrences(of: "**", with: ""))
        let heading = rendered.range(of: "WHAT IS WORKING")!
        XCTAssertEqual(rendered[heading].inlinePresentationIntent, .stronglyEmphasized)
    }

    func testKeepsPlainReportLineBreaksAndBullets() {
        let report = """
        WHAT IS WORKING
        • Average rating: 4.0/5.
        • Espresso is the strongest method.

        NEXT THREE BREWS
        1. Repeat the baseline.
        2. Change only grind.
        """

        XCTAssertEqual(String(AnalysisMarkdown.render(report).characters), report)
    }

    func testRendersInlineFormattingWithinListItems() {
        let rendered = AnalysisMarkdown.render("1. Keep **dose** stable.\n2. Try *one* change; see [notes](https://example.com/notes).")

        XCTAssertEqual(String(rendered.characters), "1. Keep dose stable.\n2. Try one change; see notes.")
        let bold = rendered.range(of: "dose")!
        let emphasis = rendered.range(of: "one")!
        let link = rendered.range(of: "notes")!
        XCTAssertEqual(rendered[bold].inlinePresentationIntent, .stronglyEmphasized)
        XCTAssertEqual(rendered[emphasis].inlinePresentationIntent, .emphasized)
        XCTAssertEqual(rendered[link].link, URL(string: "https://example.com/notes"))
    }
}
