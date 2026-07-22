import ClerkConvex
import ClerkKit
import Combine
import ConvexMobile
import Foundation

enum ApplicationAuthenticationState: Equatable {
    case configurationMissing(message: String)
    case loading
    case signedOut
    case signingOut
    case signOutFailure(message: String)
    case failure(message: String)
    case authenticated
}

enum ProductionDataReadiness: Equatable {
    case awaitingWorkspaceProvisioning
    case ready(userID: String, authGeneration: UInt64, workspaceID: String)
}

enum WorkspaceProvisioningState: Equatable {
    case idle
    case provisioning(attempt: Int)
    case ready(PersonalAccountBootstrapSnapshot)
    case failure(message: String, attempt: Int)
}

@MainActor
final class AuthenticationManager: ObservableObject {
    static let shared = AuthenticationManager()

    private struct PendingCallback: Equatable {
        let url: URL
        let attempt: Int
        let callbackEpoch: UInt64
    }

    private static let callbackScheme = "com.reuban.sticky"
    private static let callbackHost = "callback"
    private static let maximumCallbackAttempts = 3
    private static let maximumSignOutAttempts = 3
    private static let maximumProvisioningAttempts = 3
    private static let clerkLoadTimeout = Duration.seconds(10)
    private static let convexAuthenticationTimeout = Duration.seconds(10)
    private static let signOutTimeout = Duration.seconds(10)
    private static let localDisplayNameDefaultsKeyPrefix = "localProfileDisplayName."
    private static let localRoleDefaultsKeyPrefix = "localProfileRole."
    private static let localProfilePicturePathDefaultsKeyPrefix = "localProfilePicturePath."

    @Published private(set) var authenticationState: ApplicationAuthenticationState = .loading
    @Published private(set) var productionDataReadiness: ProductionDataReadiness =
        .awaitingWorkspaceProvisioning
    @Published private(set) var workspaceProvisioningState: WorkspaceProvisioningState = .idle
    @Published private(set) var authGeneration: UInt64 = 0
    @Published private(set) var clerkUserID: String?
    @Published private(set) var clerkDisplayName: String?
    @Published private(set) var clerkEmailAddress: String?
    @Published private(set) var clerkProfileImageURL: URL?
    @Published private(set) var activeWorkspaceID: String?
    @Published private(set) var lastAuthenticationErrorMessage: String?
    @Published private(set) var localDisplayNameOverride: String?
    @Published private(set) var localRole = "Member"
    @Published private(set) var localProfilePicturePath: String?

    private(set) var convexClient: ConvexClientWithAuth<String>?

    private var isConfigured = false
    private var configuredClerkPublishableKey: String?
    private var configuredConvexDeploymentURL: String?
    private var convexClientGeneration: UInt64 = 0
    private var callbackEpoch: UInt64 = 0
    private var convexProviderTransitionCount: UInt64 = 0
    private var signOutAttempt = 0
    private var manualConvexLoginHasStarted = false
    private var observedClerkUserID: String?
    private var loadedLocalProfileUserID: String?
    private var convexAuthenticationState: AuthState<String> = .loading
    private var pendingCallbacks: [PendingCallback] = []
    private var clerkEventObservationTask: Task<Void, Never>?
    private var clerkLoadingObservationTask: Task<Void, Never>?
    private var clerkRefreshTask: Task<Void, Never>?
    private var convexAuthObservationTask: Task<Void, Never>?
    private var convexAuthenticationFailureTask: Task<Void, Never>?
    private var callbackProcessingTask: Task<Void, Never>?
    private var callbackProcessingID: UUID?
    private var convexLoginTask: Task<Void, Never>?
    private var signOutOperationTask: Task<Void, Never>?
    private var signOutTimeoutTask: Task<Void, Never>?
    private var workspaceProvisioningTask: Task<Void, Never>?

    var isSignedIn: Bool {
        authenticationState == .authenticated
    }

    var isProductionDataReady: Bool {
        guard let clerkUserID else { return false }
        guard case .ready(
            let readyUserID,
            let readyAuthGeneration,
            let readyWorkspaceID
        ) = productionDataReadiness else {
            return false
        }
        return readyUserID == clerkUserID
            && readyAuthGeneration == authGeneration
            && readyWorkspaceID == activeWorkspaceID
    }

    var canAccessProductionFeatures: Bool {
        isSignedIn && isProductionDataReady
    }

    var canRetryWorkspaceProvisioning: Bool {
        guard case .failure(_, let attempt) = workspaceProvisioningState else {
            return false
        }
        return attempt < Self.maximumProvisioningAttempts
    }

    @discardableResult
    func markCurrentAuthenticatedWorkspaceReady(workspaceID: String) -> Bool {
        let trimmedWorkspaceID = workspaceID.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard authenticationState == .authenticated,
              let clerkUserID,
              !trimmedWorkspaceID.isEmpty else {
            return false
        }

        activeWorkspaceID = trimmedWorkspaceID
        productionDataReadiness = .ready(
            userID: clerkUserID,
            authGeneration: authGeneration,
            workspaceID: trimmedWorkspaceID
        )
        return true
    }

    var displayName: String {
        if let localDisplayNameOverride, !localDisplayNameOverride.isEmpty {
            return localDisplayNameOverride
        }
        if let clerkDisplayName, !clerkDisplayName.isEmpty {
            return clerkDisplayName
        }
        return "Sticky user"
    }

    var email: String {
        clerkEmailAddress ?? ""
    }

    var localProfileStorageDirectoryName: String? {
        guard let clerkUserID else { return nil }
        return clerkUserID.map { character in
            character.isLetter || character.isNumber || character == "-"
                ? character
                : "_"
        }
        .reduce(into: "", { $0.append($1) })
    }

    private init() {}

    static func isSupportedCallbackURL(_ url: URL) -> Bool {
        guard url.scheme == callbackScheme,
              url.host == callbackHost,
              url.user == nil,
              url.password == nil,
              url.port == nil,
              url.path.isEmpty || url.path == "/"
        else {
            return false
        }
        return true
    }

    func configure() {
        guard !isConfigured else {
            retry()
            return
        }

        guard let clerkPublishableKey = AppBundleConfiguration.stringValue(
            forKey: "ClerkPublishableKey"
        ) else {
            setConfigurationMissing("ClerkPublishableKey is not configured.")
            return
        }

        guard let convexDeploymentURL = AppBundleConfiguration.stringValue(
            forKey: "ConvexDeploymentURL"
        ),
        let parsedConvexDeploymentURL = URL(string: convexDeploymentURL),
        parsedConvexDeploymentURL.scheme == "https",
        parsedConvexDeploymentURL.host != nil else {
            setConfigurationMissing("ConvexDeploymentURL must be a valid HTTPS URL.")
            return
        }

        let clerkOptions = Clerk.Options(
            keychainConfig: .init(service: "com.reuban.sticky"),
            redirectConfig: .init(
                redirectUrl: "com.reuban.sticky://callback",
                callbackUrlScheme: "com.reuban.sticky"
            )
        )
        Clerk.configure(
            publishableKey: clerkPublishableKey,
            options: clerkOptions
        )

        let clerkAuthProvider = ClerkConvexAuthProvider()
        let authenticatedConvexClient = ConvexClientWithAuth(
            deploymentUrl: convexDeploymentURL,
            authProvider: clerkAuthProvider
        )
        resetWorkspaceProvisioning()
        convexClient = authenticatedConvexClient
        convexClientGeneration &+= 1
        configuredClerkPublishableKey = clerkPublishableKey
        configuredConvexDeploymentURL = convexDeploymentURL
        isConfigured = true
        authenticationState = .loading

        observeClerkEvents()
        observeConvexAuthentication(
            authenticatedConvexClient,
            clientGeneration: convexClientGeneration
        )
        observeClerkLoading(callbackEpoch: callbackEpoch)
    }

    func retry() {
        lastAuthenticationErrorMessage = nil

        if case .signOutFailure = authenticationState {
            retrySignOut()
            return
        }

        guard isConfigured else {
            configure()
            return
        }

        guard let clerkPublishableKey = AppBundleConfiguration.stringValue(
            forKey: "ClerkPublishableKey"
        ) else {
            setConfigurationMissing("ClerkPublishableKey is not configured.")
            return
        }
        guard let convexDeploymentURL = AppBundleConfiguration.stringValue(
            forKey: "ConvexDeploymentURL"
        ),
        let parsedConvexDeploymentURL = URL(string: convexDeploymentURL),
        parsedConvexDeploymentURL.scheme == "https",
        parsedConvexDeploymentURL.host != nil else {
            setConfigurationMissing("ConvexDeploymentURL must be a valid HTTPS URL.")
            return
        }

        if clerkPublishableKey != configuredClerkPublishableKey
            || convexDeploymentURL != configuredConvexDeploymentURL {
            setFailure(
                "Runtime authentication configuration changed. Restart Sticky to apply the new values."
            )
            return
        }

        cancelRetryAndLoginTasks()
        authenticationState = .loading
        let generation = authGeneration
        let providerTransitionCount = convexProviderTransitionCount

        clerkRefreshTask = Task { [weak self] in
            guard let self else { return }
            do {
                _ = try await Clerk.shared.refreshEnvironment()
                guard self.isCurrentGeneration(generation) else { return }
                _ = try await Clerk.shared.refreshClient()
                guard self.isCurrentGeneration(generation) else { return }

                self.clerkRefreshTask = nil
                self.handleClerkReady(callbackEpoch: self.callbackEpoch)
                self.scheduleExplicitRetryLoginFallback(
                    generation: generation,
                    providerTransitionCount: providerTransitionCount
                )
            } catch {
                guard self.isCurrentGeneration(generation) else { return }
                self.clerkRefreshTask = nil
                self.setFailure("Clerk refresh failed: \(error.localizedDescription)")
            }
        }
    }

    func handleIncomingURL(_ url: URL) {
        guard Self.isSupportedCallbackURL(url) else { return }
        guard !pendingCallbacks.contains(where: { $0.url == url }) else { return }

        let callback = PendingCallback(
            url: url,
            attempt: 1,
            callbackEpoch: callbackEpoch
        )
        pendingCallbacks.append(callback)

        guard isConfigured else {
            setFailure("Authentication is not configured for this callback.")
            return
        }

        authenticationState = .loading
        if Clerk.shared.isLoaded {
            processPendingCallbacks(callbackEpoch: callback.callbackEpoch)
        } else {
            observeClerkLoading(callbackEpoch: callback.callbackEpoch)
        }
    }

    func signOut() {
        if case .signOutFailure = authenticationState {
            retrySignOut()
            return
        }
        guard authenticationState == .authenticated else { return }
        signOutAttempt = 1
        beginSignOutAttempt()
    }

    func retryProvisioning() {
        guard case .failure(_, let attempt) = workspaceProvisioningState,
              attempt < Self.maximumProvisioningAttempts else {
            return
        }
        startWorkspaceProvisioning(attempt: attempt + 1)
    }

    private func retrySignOut() {
        guard signOutAttempt < Self.maximumSignOutAttempts else {
            setSignOutFailure(
                "Sign out failed after \(Self.maximumSignOutAttempts) attempts. Restart Sticky and try again."
            )
            return
        }
        signOutAttempt += 1
        beginSignOutAttempt()
    }

    private func beginSignOutAttempt() {
        guard let convexClient else {
            setSignOutFailure("Convex authentication is not configured.")
            return
        }
        guard authenticationState != .signingOut else { return }

        invalidateCallbacks()
        resetWorkspaceProvisioning()
        activeWorkspaceID = nil
        productionDataReadiness = .awaitingWorkspaceProvisioning
        authenticationState = .loading
        advanceAuthGeneration()
        authenticationState = .signingOut
        lastAuthenticationErrorMessage = nil
        let generation = authGeneration

        signOutOperationTask?.cancel()
        signOutOperationTask = Task {
            await convexClient.logout()
        }

        signOutTimeoutTask?.cancel()
        signOutTimeoutTask = Task { [weak self] in
            try? await Task.sleep(for: Self.signOutTimeout)
            guard !Task.isCancelled, let self else { return }
            guard self.isCurrentGeneration(generation) else { return }
            guard self.authenticationState == .signingOut else { return }

            self.signOutOperationTask?.cancel()
            self.signOutOperationTask = nil
            self.setSignOutFailure(
                "Sign out attempt \(self.signOutAttempt) timed out. Protected access remains locked."
            )
        }
    }

    func updateLocalIdentity(displayName: String, role: String) {
        guard let clerkUserID else { return }

        let trimmedDisplayName = displayName.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        let trimmedRole = role.trimmingCharacters(in: .whitespacesAndNewlines)

        localDisplayNameOverride = trimmedDisplayName.isEmpty
            ? nil
            : trimmedDisplayName
        localRole = trimmedRole

        let defaults = UserDefaults.standard
        defaults.set(
            localDisplayNameOverride,
            forKey: scopedDefaultsKey(
                prefix: Self.localDisplayNameDefaultsKeyPrefix,
                clerkUserID: clerkUserID
            )
        )
        defaults.set(
            localRole,
            forKey: scopedDefaultsKey(
                prefix: Self.localRoleDefaultsKeyPrefix,
                clerkUserID: clerkUserID
            )
        )
    }

    func updateLocalProfilePicturePath(_ profilePicturePath: String?) {
        guard let clerkUserID else { return }

        localProfilePicturePath = profilePicturePath
        UserDefaults.standard.set(
            profilePicturePath,
            forKey: scopedDefaultsKey(
                prefix: Self.localProfilePicturePathDefaultsKeyPrefix,
                clerkUserID: clerkUserID
            )
        )
    }

    private func observeClerkEvents() {
        clerkEventObservationTask?.cancel()
        clerkEventObservationTask = Task { [weak self] in
            for await _ in Clerk.shared.auth.events {
                guard !Task.isCancelled, let self else { return }
                self.updateClerkProfileAndGeneration()

                if Clerk.shared.isLoaded {
                    self.processPendingCallbacks(callbackEpoch: self.callbackEpoch)
                }
                self.refreshPublishedAuthenticationState()
            }
        }
    }

    private func observeClerkLoading(callbackEpoch: UInt64) {
        clerkLoadingObservationTask?.cancel()
        clerkLoadingObservationTask = Task { [weak self] in
            let clock = ContinuousClock()
            let deadline = clock.now.advanced(by: Self.clerkLoadTimeout)

            while !Clerk.shared.isLoaded && clock.now < deadline && !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(50))
            }

            guard !Task.isCancelled, let self else { return }
            guard self.callbackEpoch == callbackEpoch else { return }
            guard Clerk.shared.isLoaded else {
                self.setFailure("Clerk did not finish loading. Retry to refresh Clerk.")
                return
            }

            self.handleClerkReady(callbackEpoch: callbackEpoch)
        }
    }

    private func handleClerkReady(callbackEpoch: UInt64) {
        guard self.callbackEpoch == callbackEpoch else { return }
        clerkLoadingObservationTask?.cancel()
        clerkLoadingObservationTask = nil
        updateClerkProfileAndGeneration()

        processPendingCallbacks(callbackEpoch: callbackEpoch)
        refreshPublishedAuthenticationState()
    }

    private func processPendingCallbacks(callbackEpoch: UInt64) {
        guard Clerk.shared.isLoaded else { return }
        guard callbackProcessingTask == nil else { return }
        guard pendingCallbacks.contains(
            where: { $0.callbackEpoch == callbackEpoch }
        ) else {
            return
        }

        let processingID = UUID()
        callbackProcessingID = processingID
        callbackProcessingTask = Task { [weak self] in
            guard let self else { return }
            defer {
                if self.callbackProcessingID == processingID {
                    self.callbackProcessingTask = nil
                    self.callbackProcessingID = nil
                    self.refreshPublishedAuthenticationState()
                }
            }

            var terminalErrorMessages: [String] = []
            while self.isCurrentCallbackOperation(
                callbackEpoch: callbackEpoch,
                processingID: processingID
            ),
                  let callbackIndex = self.pendingCallbacks.firstIndex(
                    where: { $0.callbackEpoch == callbackEpoch }
                  ) {
                let callback = self.pendingCallbacks.remove(at: callbackIndex)

                do {
                    let wasHandled = try await Clerk.shared.handle(callback.url)
                    guard self.isCurrentCallbackOperation(
                        callbackEpoch: callbackEpoch,
                        processingID: processingID
                    ) else {
                        return
                    }
                    self.updateClerkProfileAndGeneration()
                    if !wasHandled {
                        terminalErrorMessages.append(
                            "Clerk did not recognize an authentication callback."
                        )
                    }
                } catch {
                    guard self.isCurrentCallbackOperation(
                        callbackEpoch: callbackEpoch,
                        processingID: processingID
                    ) else {
                        return
                    }
                    if callback.attempt < Self.maximumCallbackAttempts {
                        self.pendingCallbacks.append(
                            PendingCallback(
                                url: callback.url,
                                attempt: callback.attempt + 1,
                                callbackEpoch: callbackEpoch
                            )
                        )
                        try? await Task.sleep(for: .milliseconds(250))
                        guard self.isCurrentCallbackOperation(
                            callbackEpoch: callbackEpoch,
                            processingID: processingID
                        ) else {
                            return
                        }
                    } else {
                        terminalErrorMessages.append(
                            "Authentication callback failed: \(error.localizedDescription)"
                        )
                    }
                }
            }

            guard self.isCurrentCallbackOperation(
                callbackEpoch: callbackEpoch,
                processingID: processingID
            ) else {
                return
            }
            if let terminalErrorMessage = terminalErrorMessages.first {
                self.setFailure(terminalErrorMessage)
            }
        }
    }

    private func observeConvexAuthentication(
        _ authenticatedConvexClient: ConvexClientWithAuth<String>,
        clientGeneration: UInt64
    ) {
        convexAuthObservationTask?.cancel()
        convexAuthObservationTask = Task { [weak self] in
            for await authState in authenticatedConvexClient.authState.values {
                guard !Task.isCancelled, let self else { return }
                guard self.convexClientGeneration == clientGeneration else { return }
                self.convexProviderTransitionCount &+= 1
                if !self.manualConvexLoginHasStarted {
                    self.convexLoginTask?.cancel()
                    self.convexLoginTask = nil
                }
                self.convexAuthenticationState = authState
                self.refreshPublishedAuthenticationState()
            }
        }
    }

    private func startWorkspaceProvisioning(attempt: Int) {
        guard attempt <= Self.maximumProvisioningAttempts,
              workspaceProvisioningTask == nil,
              authenticationState == .authenticated,
              callbackProcessingTask == nil,
              pendingCallbacks.isEmpty,
              let convexClient,
              let clerkUserID,
              case .authenticated(let authenticationToken) =
                convexAuthenticationState,
              Self.subject(fromJWT: authenticationToken) == clerkUserID else {
            return
        }

        switch workspaceProvisioningState {
        case .ready, .provisioning:
            return
        case .idle, .failure:
            break
        }

        let generation = authGeneration
        let clientGeneration = convexClientGeneration
        let provisioningUserID = clerkUserID
        workspaceProvisioningState = .provisioning(attempt: attempt)
        workspaceProvisioningTask = Task { [weak self] in
            guard let self else { return }
            do {
                let response: PersonalAccountProvisioningResponse =
                    try await convexClient.mutation("accounts:provisionCurrent")
                guard !Task.isCancelled,
                      self.authGeneration == generation,
                      self.convexClientGeneration == clientGeneration,
                      self.clerkUserID == provisioningUserID,
                      self.authenticationState == .authenticated,
                      case .authenticated = self.convexAuthenticationState else {
                    return
                }
                self.workspaceProvisioningTask = nil
                self.workspaceProvisioningState = .ready(response.snapshot)
            } catch {
                guard !Task.isCancelled,
                      self.authGeneration == generation,
                      self.convexClientGeneration == clientGeneration,
                      self.clerkUserID == provisioningUserID,
                      self.authenticationState == .authenticated else {
                    return
                }
                self.workspaceProvisioningTask = nil
                self.workspaceProvisioningState = .failure(
                    message: error.localizedDescription,
                    attempt: attempt
                )
            }
        }
    }

    private func resetWorkspaceProvisioning() {
        workspaceProvisioningTask?.cancel()
        workspaceProvisioningTask = nil
        workspaceProvisioningState = .idle
    }

    private static func subject(fromJWT token: String) -> String? {
        let tokenParts = token.split(separator: ".", omittingEmptySubsequences: false)
        guard tokenParts.count == 3 else { return nil }

        var payload = String(tokenParts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let paddingLength = (4 - payload.count % 4) % 4
        payload.append(String(repeating: "=", count: paddingLength))

        guard let payloadData = Data(base64Encoded: payload),
              let payloadObject = try? JSONSerialization.jsonObject(
                with: payloadData
              ) as? [String: Any],
              let subject = payloadObject["sub"] as? String,
              !subject.isEmpty else {
            return nil
        }
        return subject
    }

    private func scheduleExplicitRetryLoginFallback(
        generation: UInt64,
        providerTransitionCount: UInt64
    ) {
        guard isCurrentGeneration(generation) else { return }
        guard Clerk.shared.isLoaded else { return }
        guard Clerk.shared.session?.status == .active else {
            refreshPublishedAuthenticationState()
            return
        }
        guard convexLoginTask == nil else { return }

        guard let convexClient else {
            setFailure("Convex authentication is not configured.")
            return
        }

        authenticationState = .loading
        convexLoginTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled, let self else { return }
            guard self.isCurrentGeneration(generation) else { return }
            guard self.convexProviderTransitionCount == providerTransitionCount else {
                self.convexLoginTask = nil
                return
            }
            guard Clerk.shared.session?.status == .active else {
                self.convexLoginTask = nil
                self.refreshPublishedAuthenticationState()
                return
            }
            switch self.convexAuthenticationState {
            case .loading, .unauthenticated:
                break
            case .authenticated:
                self.convexLoginTask = nil
                return
            }

            self.manualConvexLoginHasStarted = true
            let result = await convexClient.loginFromCache()
            guard !Task.isCancelled else { return }
            guard self.isCurrentGeneration(generation) else { return }
            self.convexLoginTask = nil
            self.manualConvexLoginHasStarted = false

            if case .failure(let error) = result {
                if case .authenticated = self.convexAuthenticationState {
                    return
                }
                self.setFailure("Convex authentication failed: \(error.localizedDescription)")
            }
        }
    }

    private func updateClerkProfileAndGeneration() {
        let newClerkUserID = Clerk.shared.user?.id
        if newClerkUserID != observedClerkUserID {
            activeWorkspaceID = nil
            productionDataReadiness = .awaitingWorkspaceProvisioning
            switch authenticationState {
            case .signingOut, .signOutFailure:
                break
            default:
                authenticationState = .loading
            }
            observedClerkUserID = newClerkUserID
            if authenticationState == .signingOut {
                clearGenerationBoundOperations()
            } else {
                advanceAuthGeneration()
            }
        }

        guard let clerkUser = Clerk.shared.user else {
            clerkUserID = nil
            clerkDisplayName = nil
            clerkEmailAddress = nil
            clerkProfileImageURL = nil
            clearLocalProfileOverrides()
            return
        }

        let nameParts = [clerkUser.firstName, clerkUser.lastName]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        clerkUserID = clerkUser.id
        clerkDisplayName = nameParts.isEmpty
            ? clerkUser.username
            : nameParts.joined(separator: " ")
        clerkEmailAddress = clerkUser.primaryEmailAddress?.emailAddress
        clerkProfileImageURL = URL(string: clerkUser.imageUrl)

        if loadedLocalProfileUserID != clerkUser.id {
            loadLocalProfileOverrides(for: clerkUser.id)
        }
    }

    private func loadLocalProfileOverrides(for clerkUserID: String) {
        let defaults = UserDefaults.standard
        loadedLocalProfileUserID = clerkUserID
        localDisplayNameOverride = defaults.string(
            forKey: scopedDefaultsKey(
                prefix: Self.localDisplayNameDefaultsKeyPrefix,
                clerkUserID: clerkUserID
            )
        )
        localRole = defaults.string(
            forKey: scopedDefaultsKey(
                prefix: Self.localRoleDefaultsKeyPrefix,
                clerkUserID: clerkUserID
            )
        ) ?? "Member"
        localProfilePicturePath = defaults.string(
            forKey: scopedDefaultsKey(
                prefix: Self.localProfilePicturePathDefaultsKeyPrefix,
                clerkUserID: clerkUserID
            )
        )
    }

    private func clearLocalProfileOverrides() {
        loadedLocalProfileUserID = nil
        localDisplayNameOverride = nil
        localRole = "Member"
        localProfilePicturePath = nil
    }

    private func refreshPublishedAuthenticationState() {
        guard isConfigured else { return }
        if case .failure = authenticationState {
            return
        }
        if case .signOutFailure = authenticationState {
            if case .unauthenticated = convexAuthenticationState {
                completeSignOut()
            }
            return
        }
        guard Clerk.shared.isLoaded else {
            authenticationState = .loading
            return
        }

        switch convexAuthenticationState {
        case .loading:
            if authenticationState != .signingOut {
                authenticationState = .loading
            }
            if Clerk.shared.user != nil {
                scheduleConvexAuthenticationFailure(generation: authGeneration)
            } else {
                cancelConvexAuthenticationFailure()
            }
        case .unauthenticated:
            if authenticationState == .signingOut {
                completeSignOut()
            } else if Clerk.shared.user == nil {
                cancelConvexAuthenticationFailure()
                authenticationState = .signedOut
                lastAuthenticationErrorMessage = nil
            } else {
                authenticationState = .loading
                scheduleConvexAuthenticationFailure(generation: authGeneration)
            }
        case .authenticated:
            guard authenticationState != .signingOut else { return }
            guard callbackProcessingTask == nil,
                  pendingCallbacks.isEmpty else {
                authenticationState = .loading
                return
            }
            cancelConvexAuthenticationFailure()
            authenticationState = .authenticated
            lastAuthenticationErrorMessage = nil
            startWorkspaceProvisioning(attempt: 1)
        }
    }

    private func scheduleConvexAuthenticationFailure(generation: UInt64) {
        guard convexAuthenticationFailureTask == nil else { return }

        convexAuthenticationFailureTask = Task { [weak self] in
            try? await Task.sleep(for: Self.convexAuthenticationTimeout)
            guard !Task.isCancelled, let self else { return }
            guard self.isCurrentGeneration(generation) else { return }
            self.convexAuthenticationFailureTask = nil

            guard Clerk.shared.user != nil else {
                self.authenticationState = .signedOut
                return
            }
            switch self.convexAuthenticationState {
            case .loading, .unauthenticated:
                self.setFailure(
                    "Clerk signed in, but Convex did not accept the session. Check the Clerk Convex integration and retry."
                )
            case .authenticated:
                break
            }
        }
    }

    private func completeSignOut() {
        signOutOperationTask?.cancel()
        signOutOperationTask = nil
        signOutTimeoutTask?.cancel()
        signOutTimeoutTask = nil
        cancelConvexAuthenticationFailure()
        clearGenerationBoundOperations()
        activeWorkspaceID = nil
        productionDataReadiness = .awaitingWorkspaceProvisioning
        signOutAttempt = 0
        updateClerkProfileAndGeneration()
        authenticationState = .signedOut
        lastAuthenticationErrorMessage = nil
    }

    private func advanceAuthGeneration() {
        authGeneration &+= 1
        clearGenerationBoundOperations()
        cancelConvexAuthenticationFailure()
    }

    private func clearGenerationBoundOperations() {
        clerkRefreshTask?.cancel()
        clerkRefreshTask = nil
        convexLoginTask?.cancel()
        convexLoginTask = nil
        manualConvexLoginHasStarted = false
        resetWorkspaceProvisioning()
    }

    private func invalidateCallbacks() {
        callbackEpoch &+= 1
        clerkLoadingObservationTask?.cancel()
        clerkLoadingObservationTask = nil
        callbackProcessingTask?.cancel()
        callbackProcessingTask = nil
        callbackProcessingID = nil
        pendingCallbacks.removeAll()
    }

    private func cancelRetryAndLoginTasks() {
        clerkRefreshTask?.cancel()
        clerkRefreshTask = nil
        convexLoginTask?.cancel()
        convexLoginTask = nil
        manualConvexLoginHasStarted = false
    }

    private func cancelConvexAuthenticationFailure() {
        convexAuthenticationFailureTask?.cancel()
        convexAuthenticationFailureTask = nil
    }

    private func isCurrentGeneration(_ generation: UInt64) -> Bool {
        generation == authGeneration
    }

    private func isCurrentCallbackOperation(
        callbackEpoch: UInt64,
        processingID: UUID
    ) -> Bool {
        self.callbackEpoch == callbackEpoch
            && callbackProcessingID == processingID
            && !Task.isCancelled
    }

    private func setConfigurationMissing(_ message: String) {
        authenticationState = .configurationMissing(message: message)
        lastAuthenticationErrorMessage = message
    }

    private func setFailure(_ message: String) {
        cancelConvexAuthenticationFailure()
        authenticationState = .failure(message: message)
        lastAuthenticationErrorMessage = message
    }

    private func setSignOutFailure(_ message: String) {
        cancelConvexAuthenticationFailure()
        authenticationState = .signOutFailure(message: message)
        lastAuthenticationErrorMessage = message
    }

    private func scopedDefaultsKey(prefix: String, clerkUserID: String) -> String {
        "\(prefix)\(clerkUserID)"
    }
}
