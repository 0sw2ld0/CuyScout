import XCTest
@testable import CuyScoutCore

final class SigningTeamsTests: XCTestCase {
    private func team(_ id: String, certificate: Bool = true, selected: Bool = false, free: Bool = false) -> SigningTeam {
        SigningTeam(id: id, name: "Equipo \(id)", isFree: free, hasCertificate: certificate, isXcodeSelected: selected)
    }

    func testReadsXcodeAccountsAndLastSelectedTeam() throws {
        let preferences: [String: Any] = [
            "IDEProvisioningTeamByIdentifier": [
                "cuenta-1": [
                    ["teamID": "AAAAA11111", "teamName": "Ejemplo S.A.", "isFreeProvisioningTeam": false, "teamType": "Company/Organization"],
                    ["teamID": "BBBBB22222", "teamName": "Persona Ejemplo (Personal Team)", "isFreeProvisioningTeam": true, "teamType": "Individual"]
                ]
            ],
            "IDEProvisioningTeamManagerLastSelectedTeamID": "AAAAA11111"
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: preferences, format: .binary, options: 0)
        let parsed = try XCTUnwrap(SigningTeams.xcodeTeams(fromPreferences: data))
        XCTAssertEqual(parsed.selected, "AAAAA11111")
        XCTAssertEqual(parsed.teams.map(\.id), ["AAAAA11111", "BBBBB22222"])
        XCTAssertEqual(parsed.teams.map(\.isFree), [false, true])
    }

    func testMergePutsTeamsThatCanSignFirst() {
        let merged = SigningTeams.merge(
            xcode: [("AAAAA11111", "Sin certificado", false), ("BBBBB22222", "Con certificado", true)],
            selected: nil,
            certificates: [("BBBBB22222", ""), ("CCCCC33333", "Solo llavero")]
        )
        XCTAssertEqual(merged.map(\.id), ["BBBBB22222", "CCCCC33333", "AAAAA11111"])
        XCTAssertEqual(merged[0].name, "Con certificado")
        XCTAssertTrue(merged[0].isFree)
        XCTAssertEqual(merged[1].name, "Solo llavero")
        XCTAssertFalse(merged[2].hasCertificate)
    }

    func testPreferredUsesOnlyTeamOrXcodeSelection() {
        XCTAssertEqual(SigningTeams.preferred(in: [team("AAAAA11111"), team("BBBBB22222", certificate: false)])?.id, "AAAAA11111")
        XCTAssertEqual(SigningTeams.preferred(in: [team("AAAAA11111"), team("BBBBB22222", selected: true)])?.id, "BBBBB22222")
        XCTAssertNil(SigningTeams.preferred(in: [team("AAAAA11111"), team("BBBBB22222")]))
        XCTAssertEqual(SigningTeams.preferred(in: [team("AAAAA11111", certificate: false)])?.id, "AAAAA11111")
        XCTAssertNil(SigningTeams.preferred(in: []))
    }

    func testEnvironmentOverridesDetection() {
        XCTAssertEqual(SigningTeams.resolve(environment: ["CUYSCOUT_DEVELOPMENT_TEAM": "ZZZZZ99999"], detect: { [self.team("AAAAA11111")] }), "ZZZZZ99999")
        XCTAssertEqual(SigningTeams.resolve(environment: [:], detect: { [self.team("AAAAA11111")] }), "AAAAA11111")
        XCTAssertNil(SigningTeams.resolve(environment: [:], detect: { [] }))
    }

    func testOnlyDevelopmentCertificatesCount() {
        XCTAssertTrue(SigningTeams.isDevelopmentCertificate("Apple Development: Persona Ejemplo (XXXXXXXXXX)"))
        XCTAssertTrue(SigningTeams.isDevelopmentCertificate("iPhone Developer: Persona Ejemplo (XXXXXXXXXX)"))
        XCTAssertFalse(SigningTeams.isDevelopmentCertificate("Apple Distribution: Ejemplo S.A. (XXXXXXXXXX)"))
        XCTAssertFalse(SigningTeams.isDevelopmentCertificate("Developer ID Application: Ejemplo S.A. (XXXXXXXXXX)"))
    }

    func testDoctorReportsDetectedOrAmbiguousTeams() {
        XCTAssertTrue(SimulatorController.signingTeamCheck(environment: [:], detect: { [self.team("AAAAA11111")] }).available)
        let ambiguous = SimulatorController.signingTeamCheck(environment: [:], detect: { [self.team("AAAAA11111"), self.team("BBBBB22222")] })
        XCTAssertFalse(ambiguous.available)
        XCTAssertTrue(ambiguous.detail.contains("2 equipos"))
        XCTAssertFalse(SimulatorController.signingTeamCheck(environment: [:], detect: { [] }).available)
    }
}
