import XCTest
@testable import Diald

final class LocalBrewAnalysisTests: XCTestCase {
    private let ownerID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    private let beanID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!

    func testReportSummarisesRatingsAndBestBrewLocally() {
        let report = LocalBrewAnalysis(
            brews: [
                makeBrew(index: 0, rating: 3, seconds: 25),
                makeBrew(index: 1, rating: 5, seconds: 31)
            ],
            beans: [makeBean()],
            includeNotes: true
        ).makeReport()

        XCTAssertTrue(report.text.contains("average rating is 4.0/5"))
        XCTAssertTrue(report.text.contains("rated 5/5"))
        XCTAssertTrue(report.text.contains("North Star Ethiopia"))
        XCTAssertFalse(report.text.localizedCaseInsensitiveContains("API key"))
        XCTAssertFalse(report.text.localizedCaseInsensitiveContains("provider"))
    }

    func testExcludedNotesDoNotInfluenceRecommendations() {
        let report = LocalBrewAnalysis(
            brews: [makeBrew(index: 0, rating: 3, seconds: 25, notes: "Very sour and watery")],
            beans: [makeBean()],
            includeNotes: false
        ).makeReport()

        XCTAssertFalse(report.text.contains("under-extraction"))
        XCTAssertFalse(report.modelPrompt.contains("Very sour and watery"))
    }

    func testComparableHighRatedBrewsProduceSingleVariableExperiment() {
        let report = LocalBrewAnalysis(
            brews: [
                makeBrew(index: 0, rating: 2, seconds: 20),
                makeBrew(index: 1, rating: 3, seconds: 22),
                makeBrew(index: 2, rating: 4, seconds: 35),
                makeBrew(index: 3, rating: 5, seconds: 37)
            ],
            beans: [makeBean()],
            includeNotes: true
        ).makeReport()

        XCTAssertTrue(report.text.contains("4–5 star Espresso brews ran about 15 seconds longer"))
        XCTAssertTrue(report.text.contains("extend extraction by about 15 seconds"))
        XCTAssertTrue(report.text.contains("holding everything else steady"))
    }

    private func makeBean() -> CoffeeBean {
        CoffeeBean(
            id: beanID,
            ownerID: ownerID,
            name: "Ethiopia",
            roaster: "North Star",
            origin: "Ethiopia",
            process: "Washed",
            variety: nil,
            roastLevel: .light,
            roastDate: nil,
            tastingNotes: nil,
            archivedAt: nil,
            createdAt: nil,
            updatedAt: nil,
            deletedAt: nil
        )
    }

    private func makeBrew(
        index: Int,
        rating: Int?,
        seconds: Int,
        notes: String? = nil
    ) -> BrewSession {
        BrewSession(
            id: UUID(),
            ownerID: ownerID,
            beanID: beanID,
            method: .espresso,
            title: "Test espresso",
            doseGrams: 18,
            yieldGrams: 36,
            waterGrams: nil,
            grindSetting: "12",
            waterTemperatureC: 93,
            extractionSeconds: seconds,
            rating: rating,
            acidity: nil,
            sweetness: nil,
            body: nil,
            clarity: nil,
            notes: notes,
            brewedAt: Date(timeIntervalSince1970: Double(index) * 86_400),
            createdAt: nil,
            updatedAt: nil,
            deletedAt: nil
        )
    }
}
