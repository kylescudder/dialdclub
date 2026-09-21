import XCTest
@testable import Diald

final class PushGatewayConfigurationTests: XCTestCase {
    func testEmptyOrMissingURLDisablesGateway() {
        XCTAssertNil(PushGatewayConfiguration.make(rawURL: nil, applicationID: "diald"))
        XCTAssertNil(PushGatewayConfiguration.make(rawURL: "", applicationID: "diald"))
        XCTAssertNil(PushGatewayConfiguration.make(rawURL: "   ", applicationID: "diald"))
    }

    func testMalformedURLDisablesGateway() {
        XCTAssertNil(PushGatewayConfiguration.make(rawURL: "not a url", applicationID: "diald"))
        XCTAssertNil(PushGatewayConfiguration.make(rawURL: "ftp://push.example.com", applicationID: "diald"))
        XCTAssertNil(PushGatewayConfiguration.make(rawURL: "https:///missing-host", applicationID: "diald"))
    }

    func testMissingOrInvalidApplicationIDDisablesGateway() {
        XCTAssertNil(PushGatewayConfiguration.make(rawURL: "https://push.example.com", applicationID: nil))
        XCTAssertNil(PushGatewayConfiguration.make(rawURL: "https://push.example.com", applicationID: ""))
        XCTAssertNil(PushGatewayConfiguration.make(rawURL: "https://push.example.com", applicationID: "Diald"))
        XCTAssertNil(PushGatewayConfiguration.make(rawURL: "https://push.example.com", applicationID: "d"))
    }

    func testValidConfigurationIsParsedExactly() throws {
        let configuration = try XCTUnwrap(PushGatewayConfiguration.make(
            rawURL: "https://push.example.com/base/",
            applicationID: "diald"
        ))

        XCTAssertEqual(configuration.baseURL.absoluteString, "https://push.example.com/base/")
        XCTAssertEqual(configuration.applicationID, "diald")
    }

    func testTransportSelectionUsesExactlyOneConfiguredPath() {
        XCTAssertEqual(PushRegistrationTransportKind.selected(for: nil), .legacy)
        let configuration = PushGatewayConfiguration(
            baseURL: URL(string: "https://push.example.com")!,
            applicationID: "diald"
        )
        XCTAssertEqual(PushRegistrationTransportKind.selected(for: configuration), .gateway)
    }
}
