import Foundation
import Testing
@testable import ServerCore

@Suite("Remote installation assessments")
struct RemoteInstallationPlanningTests {
    private func report() -> [String: Any] {
        let hash = String(repeating: "a", count: 64)
        return ["reviewBinding":hash,"service":"example","repository":"Funico-NV/example","version":"1.0.0",
            "archiveSHA256":hash,"definitionSHA256":hash,"signingKeySHA256":hash,"profile":"application","backend":"systemd",
            "serviceUser":"funico-example","unit":"funico-example.service","installRoot":"/opt/funico/example",
            "environmentFile":"/etc/funico/example/environment","executable":"bin/Example","arguments":["serve"],
            "readinessURL":"http://127.0.0.1:8080/health","requiresMigration":false,
            "settings":[["name":"API_TOKEN","type":"string","required":true,"secret":true,"source":"missing"]],
            "issues":["requiredConfigurationMissing"],"reviewable":false,"applySupported":false,"requiredBeforeApply":["verifyEveryExtractedFile"]]
    }
    @Test func commandAndResultRoundTripWithoutActivatingAnything() throws {
        let artifact = ReleaseArtifact(platform: .linuxX86_64, archiveURL: URL(string:"https://manager.test/archive")!,
            checksumURL: URL(string:"https://manager.test/checksum")!, signatureURL: URL(string:"https://manager.test/signature")!)
        let request = InstallationPlanRequest(service:"example",version:"1.0.0",repository:"Funico-NV/example",artifact:artifact)
        try request.validate()
        let command = AgentCommand.planInstallation(request)
        #expect(try JSONDecoder().decode(AgentCommand.self, from: JSONEncoder().encode(command)) == command)
        #expect(command.service == "example" && AgentCommand.listInstallationCandidates.service == nil)
        let assessment = try JSONDecoder().decode(ServiceInstallationAssessment.self, from: JSONSerialization.data(withJSONObject:report()))
        let result = CommandResult(command:"test",installationCandidates:[],installationAssessment:assessment)
        #expect(try JSONDecoder().decode(CommandResult.self, from: JSONEncoder().encode(result)) == result)
        #expect(!assessment.applySupported && !assessment.reviewable)
    }
    @Test func applyingOrIncoherentReportsAreRefused() throws {
        for key in ["applySupported","reviewable","reviewBinding","repository"] {
            var object = report()
            if key == "applySupported" || key == "reviewable" { object[key] = true }
            else { object[key] = "invalid" }
            #expect(throws:(any Error).self) { try JSONDecoder().decode(ServiceInstallationAssessment.self,from:JSONSerialization.data(withJSONObject:object)) }
        }
    }
    @Test func unknownSettingValuesAreNotRelayed() throws {
        var object=report()
        object["settings"]=[["name":"API_TOKEN","type":"string","required":true,"secret":true,"source":"missing","value":"private-value-marker"]]
        let assessment=try JSONDecoder().decode(ServiceInstallationAssessment.self,from:JSONSerialization.data(withJSONObject:object))
        #expect(!String(decoding:try JSONEncoder().encode(assessment),as:UTF8.self).contains("private-value-marker"))
        let legacy=Data(#"{"command":"old","completedAt":0}"#.utf8)
        #expect(try JSONDecoder().decode(CommandResult.self,from:legacy).installationAssessment == nil)
    }
}
