import Foundation

enum PersonaSetupState: String, Decodable, Equatable {
    case notStarted
    case essentials
    case interview
    case complete

    var statusText: String {
        switch self {
        case .notStarted:
            return "Persona setup has not started"
        case .essentials:
            return "Persona essentials are in progress"
        case .interview:
            return "Persona interview is in progress"
        case .complete:
            return "Persona setup is complete"
        }
    }
}

struct PersonalAccountBootstrapSnapshot: Decodable, Equatable {
    let profileId: String
    let profileDisplayName: String
    let workspaceId: String
    let workspaceName: String
    let businessType: String?
    let membershipId: String
    let personaId: String
    let personaDisplayName: String
    let personaSetupState: PersonaSetupState
    let personaCurrentVersion: Double
}

struct PersonalAccountProvisioningResponse: Decodable, Equatable {
    let didCreate: Bool
    let snapshot: PersonalAccountBootstrapSnapshot
}
