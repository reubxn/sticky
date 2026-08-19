//
//  leanring_buddyTests.swift
//  leanring-buddyTests
//
//  Created by thorfinn on 3/2/26.
//

import Testing
import Foundation
@testable import leanring_buddy

struct leanring_buddyTests {

    @Test func firstPermissionRequestUsesSystemPromptOnly() async throws {
        let presentationDestination = WindowPositionManager.permissionRequestPresentationDestination(
            hasPermissionNow: false,
            hasAttemptedSystemPrompt: false
        )

        #expect(presentationDestination == .systemPrompt)
    }

    @Test func repeatedPermissionRequestOpensSystemSettings() async throws {
        let presentationDestination = WindowPositionManager.permissionRequestPresentationDestination(
            hasPermissionNow: false,
            hasAttemptedSystemPrompt: true
        )

        #expect(presentationDestination == .systemSettings)
    }

    @Test func knownGrantedScreenRecordingPermissionSkipsTheGate() async throws {
        let shouldTreatPermissionAsGranted = WindowPositionManager.shouldTreatScreenRecordingPermissionAsGrantedForSessionLaunch(
            hasScreenRecordingPermissionNow: false,
            hasPreviouslyConfirmedScreenRecordingPermission: true
        )

        #expect(shouldTreatPermissionAsGranted)
    }

    @Test func openAIModelSelectionRoutesToOpenAI() {
        let modelKind = ModelPickerKind.fromModelId("gpt-5.2-2025-12-11")

        #expect(modelKind == .chatGPT)
        #expect(modelKind.provider == .openAI)
    }

    @Test func chatGPTIsTheDefaultForMissingOrUnknownPreferences() {
        #expect(ModelPickerKind.defaultModelId == "gpt-5.2-2025-12-11")
        #expect(ModelPickerKind.fromModelId("unknown-model") == .chatGPT)
        #expect(ModelPickerKind.preferenceKey == "selectedAIModel")
    }

    @Test func existingClaudeModelSelectionsRemainAvailable() {
        let claudeModelIds = [
            "claude-haiku-4-5-20251001",
            "claude-sonnet-4-6",
            "claude-opus-4-7",
        ]

        for modelId in claudeModelIds {
            #expect(ModelPickerKind.fromModelId(modelId).provider == .anthropic)
        }
    }

    @Test func personalAccountProvisioningResponseDecodesConvexSnapshot() throws {
        let fixture = """
        {
          "didCreate": true,
          "snapshot": {
            "profileId": "profiles:1",
            "profileDisplayName": "Sticky User",
            "workspaceId": "workspaces:1",
            "workspaceName": "Sticky User's Workspace",
            "businessType": null,
            "membershipId": "workspaceMembers:1",
            "personaId": "personas:1",
            "personaDisplayName": "Sticky User",
            "personaSetupState": "notStarted",
            "personaCurrentVersion": 0
          }
        }
        """

        let response = try JSONDecoder().decode(
            PersonalAccountProvisioningResponse.self,
            from: Data(fixture.utf8)
        )

        #expect(response.didCreate)
        #expect(response.snapshot.workspaceId == "workspaces:1")
        #expect(response.snapshot.businessType == nil)
        #expect(response.snapshot.personaSetupState == .notStarted)
        #expect(response.snapshot.personaCurrentVersion == 0)
    }

}
