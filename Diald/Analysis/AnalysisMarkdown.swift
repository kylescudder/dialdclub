import Foundation

enum AnalysisMarkdown {
    static func render(_ report: String) -> AttributedString {
        // Text renders inline attributes, but not Markdown block presentation
        // intents. Keep line breaks and list markers in the displayed text.
        (try? AttributedString(
            markdown: report,
            options: .init(
                interpretedSyntax: .inlineOnlyPreservingWhitespace,
                failurePolicy: .returnPartiallyParsedIfPossible
            )
        )) ?? AttributedString(report)
    }
}
