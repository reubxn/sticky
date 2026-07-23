import CryptoKit
import Foundation

#if canImport(ConvexMobile)
import ConvexMobile
#endif

nonisolated enum OnboardingWorkerScope: String, Codable, CaseIterable, Sendable {
    case chat = "onboarding_chat"
    case textToSpeech = "onboarding_tts"
    case transcription = "onboarding_transcribe"

    var requestBodyPolicy: OnboardingWorkerRequestBodyPolicy {
        switch self {
        case .chat:
            return OnboardingWorkerRequestBodyPolicy(
                minimumByteCount: 2,
                maximumByteCount: 2_304
            )
        case .textToSpeech:
            return OnboardingWorkerRequestBodyPolicy(
                minimumByteCount: 2,
                maximumByteCount: 4_096
            )
        case .transcription:
            return OnboardingWorkerRequestBodyPolicy(
                minimumByteCount: 0,
                maximumByteCount: 0
            )
        }
    }
}

nonisolated struct OnboardingWorkerRequestBodyPolicy: Equatable, Sendable {
    let minimumByteCount: Int
    let maximumByteCount: Int
}

nonisolated struct OnboardingTicketIssueRequest: Equatable, Sendable {
    let personaId: String
    let scope: OnboardingWorkerScope
    let requestBodyDigest: String
    let requestBodyByteCount: Int
}

nonisolated struct OnboardingTicketIssueResponse: Decodable, Equatable, Sendable {
    let token: String
    let scope: OnboardingWorkerScope
    let expiresAt: Double
    let policyVersion: Double
}

nonisolated struct OnboardingChatRequest: Codable, Equatable, Sendable {
    let text: String
    let clientTurnId: String
}

nonisolated struct OnboardingTTSRequest: Codable, Equatable, Sendable {
    let text: String
}

nonisolated struct OnboardingTranscriptionTokenResponse:
    Decodable, Equatable, Sendable {
    let token: String
}

nonisolated struct OnboardingChatServerSentEvent: Equatable, Sendable {
    let event: String?
    let data: String
    let id: String?
}

nonisolated struct OnboardingWorkerOperationContext: Equatable, Sendable {
    let clerkUserID: String
    let authGeneration: UInt64
    let workspaceID: String
    let personaID: String
}

nonisolated enum OnboardingWorkerClientError: Error, Equatable, Sendable {
    case configurationUnavailable
    case invalidRequest
    case contextInvalidated
    case requestDenied
    case serviceUnavailable
    case invalidResponse
    case responseTooLarge
    case cancelled
}

nonisolated final class OnboardingWorkerInvalidationSignal: @unchecked Sendable {
    nonisolated final class Registration: @unchecked Sendable {
        private let lock = NSLock()
        private weak var signal: OnboardingWorkerInvalidationSignal?
        private var registrationID: UUID?

        fileprivate init(
            signal: OnboardingWorkerInvalidationSignal,
            registrationID: UUID
        ) {
            self.signal = signal
            self.registrationID = registrationID
        }

        func unregister() {
            lock.lock()
            let registrationID = registrationID
            self.registrationID = nil
            let signal = signal
            self.signal = nil
            lock.unlock()

            if let registrationID {
                signal?.unregister(registrationID)
            }
        }

        deinit {
            unregister()
        }
    }

    private let lock = NSLock()
    private var cancellationClosures: [UUID: @Sendable () -> Void] = [:]
    private var isInvalidated = false

    func register(
        cancellation: @escaping @Sendable () -> Void
    ) -> Registration? {
        lock.lock()
        guard !isInvalidated else {
            lock.unlock()
            cancellation()
            return nil
        }
        let registrationID = UUID()
        cancellationClosures[registrationID] = cancellation
        lock.unlock()
        return Registration(
            signal: self,
            registrationID: registrationID
        )
    }

    func invalidate() {
        lock.lock()
        guard !isInvalidated else {
            lock.unlock()
            return
        }
        isInvalidated = true
        let cancellations = Array(cancellationClosures.values)
        cancellationClosures.removeAll()
        lock.unlock()

        for cancellation in cancellations {
            cancellation()
        }
    }

    var invalidated: Bool {
        lock.lock()
        let invalidated = isInvalidated
        lock.unlock()
        return invalidated
    }

    var registrationCount: Int {
        lock.lock()
        let count = cancellationClosures.count
        lock.unlock()
        return count
    }

    fileprivate func unregister(_ registrationID: UUID) {
        lock.lock()
        cancellationClosures.removeValue(forKey: registrationID)
        lock.unlock()
    }
}

@MainActor
protocol OnboardingTicketIssuing: AnyObject, Sendable {
    func issueOnboardingTicket(
        _ request: OnboardingTicketIssueRequest
    ) async throws -> OnboardingTicketIssueResponse
}

nonisolated protocol OnboardingWorkerURLLoading: Sendable {
    func response(
        for request: URLRequest
    ) async throws -> OnboardingWorkerHTTPResponse
}

nonisolated struct OnboardingWorkerHTTPResponse: Sendable {
    let statusCode: Int
    let headers: [String: String]
    let body: OnboardingWorkerBody

    func headerValue(for name: String) -> String? {
        headers.first { key, _ in
            key.caseInsensitiveCompare(name) == .orderedSame
        }?.value
    }
}

nonisolated struct OnboardingWorkerBody: Sendable {
    private let nextChunkClosure: @Sendable () async throws -> Data?
    private let cancelClosure: @Sendable () async -> Void
    private let cancelImmediatelyClosure: @Sendable () -> Void

    init(
        nextChunk: @escaping @Sendable () async throws -> Data?,
        cancel: @escaping @Sendable () async -> Void = {},
        cancelImmediately: @escaping @Sendable () -> Void = {}
    ) {
        nextChunkClosure = nextChunk
        cancelClosure = cancel
        cancelImmediatelyClosure = cancelImmediately
    }

    func nextChunk() async throws -> Data? {
        try await nextChunkClosure()
    }

    func cancel() async {
        cancelImmediatelyClosure()
        await cancelClosure()
    }

    func cancelImmediately() {
        cancelImmediatelyClosure()
    }
}

nonisolated struct OnboardingWorkerByteStream: AsyncSequence, Sendable {
    typealias Element = Data

    struct AsyncIterator: AsyncIteratorProtocol {
        let nextChunk: @Sendable () async throws -> Data?
        let lifetime: OnboardingWorkerStreamLifetime

        mutating func next() async throws -> Data? {
            try await nextChunk()
        }
    }

    private let body: OnboardingWorkerBody
    private let lifetime: OnboardingWorkerStreamLifetime

    init(
        body: OnboardingWorkerBody,
        lifetime: OnboardingWorkerStreamLifetime
    ) {
        self.body = body
        self.lifetime = lifetime
    }

    func makeAsyncIterator() -> AsyncIterator {
        AsyncIterator(
            nextChunk: {
                try await body.nextChunk()
            },
            lifetime: lifetime
        )
    }

    func cancel() async {
        lifetime.cancelImmediately()
        await body.cancel()
    }
}

nonisolated struct OnboardingChatEventStream: AsyncSequence, Sendable {
    typealias Element = OnboardingChatServerSentEvent

    struct AsyncIterator: AsyncIteratorProtocol {
        let nextEvent: @Sendable () async throws -> OnboardingChatServerSentEvent?
        let lifetime: OnboardingWorkerStreamLifetime

        mutating func next() async throws -> OnboardingChatServerSentEvent? {
            try await nextEvent()
        }
    }

    private let parser: OnboardingSSEParser
    private let lifetime: OnboardingWorkerStreamLifetime

    fileprivate init(
        parser: OnboardingSSEParser,
        lifetime: OnboardingWorkerStreamLifetime
    ) {
        self.parser = parser
        self.lifetime = lifetime
    }

    func makeAsyncIterator() -> AsyncIterator {
        AsyncIterator(
            nextEvent: {
                try await parser.nextEvent()
            },
            lifetime: lifetime
        )
    }

    func cancel() async {
        lifetime.cancelImmediately()
        await parser.cancel()
    }
}

nonisolated final class OnboardingWorkerStreamLifetime: @unchecked Sendable {
    private let lock = NSLock()
    private var cancellation: (@Sendable () -> Void)?
    private var invalidationRegistration:
        OnboardingWorkerInvalidationSignal.Registration?

    fileprivate init(
        body: OnboardingWorkerBody,
        invalidationSignal: OnboardingWorkerInvalidationSignal,
        invalidationState: OnboardingStreamInvalidationState
    ) {
        cancellation = {
            body.cancelImmediately()
        }
        invalidationRegistration = invalidationSignal.register {
            invalidationState.invalidate()
            body.cancelImmediately()
        }
    }

    func complete() {
        let registration = takeResources(shouldCancel: false).registration
        registration?.unregister()
    }

    func cancelImmediately() {
        let resources = takeResources(shouldCancel: true)
        resources.registration?.unregister()
        resources.cancellation?()
    }

    deinit {
        cancelImmediately()
    }

    private func takeResources(
        shouldCancel: Bool
    ) -> (
        registration: OnboardingWorkerInvalidationSignal.Registration?,
        cancellation: (@Sendable () -> Void)?
    ) {
        lock.lock()
        let registration = invalidationRegistration
        invalidationRegistration = nil
        let cancellation = shouldCancel ? cancellation : nil
        self.cancellation = nil
        lock.unlock()
        return (registration, cancellation)
    }
}

nonisolated final class URLSessionOnboardingWorkerLoader:
    OnboardingWorkerURLLoading,
    @unchecked Sendable {
    static let maximumChunkByteCount = 16_384
    static let maximumBufferedByteCount = 65_536

    private let delegate: OnboardingURLSessionDelegate
    private let session: URLSession

    convenience init() {
        self.init(configuration: .ephemeral)
    }

    init(configuration: URLSessionConfiguration) {
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        let delegate = OnboardingURLSessionDelegate()
        self.delegate = delegate
        session = URLSession(
            configuration: configuration,
            delegate: delegate,
            delegateQueue: nil
        )
    }

    func response(
        for request: URLRequest
    ) async throws -> OnboardingWorkerHTTPResponse {
        let taskState = OnboardingURLSessionTaskState(
            maximumChunkByteCount: Self.maximumChunkByteCount,
            maximumBufferedByteCount: Self.maximumBufferedByteCount
        )
        let task = session.dataTask(with: request)
        taskState.setTask(task)
        delegate.register(taskState, for: task.taskIdentifier)
        task.resume()

        do {
            return try await withTaskCancellationHandler {
                try await taskState.response()
            } onCancel: {
                taskState.cancel()
            }
        } catch let clientError as OnboardingWorkerClientError {
            throw clientError
        } catch {
            throw OnboardingWorkerClientError.serviceUnavailable
        }
    }

    var activeTaskCount: Int {
        delegate.activeTaskCount
    }

    var suspendedTaskCount: Int {
        delegate.suspendedTaskCount
    }
}

nonisolated private final class OnboardingURLSessionDelegate:
    NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var taskStates: [Int: OnboardingURLSessionTaskState] = [:]

    var activeTaskCount: Int {
        lock.lock()
        let count = taskStates.count
        lock.unlock()
        return count
    }

    var suspendedTaskCount: Int {
        lock.lock()
        let states = Array(taskStates.values)
        lock.unlock()
        return states.filter(\.taskIsSuspended).count
    }

    func register(
        _ taskState: OnboardingURLSessionTaskState,
        for taskIdentifier: Int
    ) {
        lock.lock()
        taskStates[taskIdentifier] = taskState
        lock.unlock()
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        guard let taskState = taskState(for: dataTask.taskIdentifier),
              let httpResponse = response as? HTTPURLResponse else {
            taskState(for: dataTask.taskIdentifier)?.fail(
                OnboardingWorkerClientError.invalidResponse
            )
            completionHandler(.cancel)
            return
        }
        let headers = httpResponse.allHeaderFields.reduce(
            into: [String: String]()
        ) { result, entry in
            guard let key = entry.key as? String else { return }
            result[key] = String(describing: entry.value)
        }
        taskState.receiveResponse(
            statusCode: httpResponse.statusCode,
            headers: headers
        )
        completionHandler(.allow)
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive data: Data
    ) {
        taskState(for: dataTask.taskIdentifier)?.receive(data)
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        removeTaskState(for: task.taskIdentifier)?.complete(error: error)
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }

    private func taskState(
        for taskIdentifier: Int
    ) -> OnboardingURLSessionTaskState? {
        lock.lock()
        let taskState = taskStates[taskIdentifier]
        lock.unlock()
        return taskState
    }

    private func removeTaskState(
        for taskIdentifier: Int
    ) -> OnboardingURLSessionTaskState? {
        lock.lock()
        let taskState = taskStates.removeValue(forKey: taskIdentifier)
        lock.unlock()
        return taskState
    }
}

nonisolated private final class OnboardingURLSessionTaskState:
    @unchecked Sendable {
    private let lock = NSLock()
    private let maximumChunkByteCount: Int
    private let maximumBufferedByteCount: Int
    private let resumeBufferedByteCount: Int
    private weak var task: URLSessionDataTask?
    private var responseValue: OnboardingWorkerHTTPResponse?
    private var responseContinuation:
        CheckedContinuation<OnboardingWorkerHTTPResponse, Error>?
    private var chunks: [Data] = []
    private var bufferedByteCount = 0
    private var chunkContinuation: CheckedContinuation<Data?, Error>?
    private var terminalError: Error?
    private var isComplete = false
    private var isTaskSuspended = false

    var taskIsSuspended: Bool {
        lock.lock()
        let suspended = isTaskSuspended
        lock.unlock()
        return suspended
    }

    init(
        maximumChunkByteCount: Int,
        maximumBufferedByteCount: Int
    ) {
        self.maximumChunkByteCount = maximumChunkByteCount
        self.maximumBufferedByteCount = maximumBufferedByteCount
        resumeBufferedByteCount = maximumBufferedByteCount / 4
    }

    func setTask(_ task: URLSessionDataTask) {
        lock.lock()
        self.task = task
        lock.unlock()
    }

    func response() async throws -> OnboardingWorkerHTTPResponse {
        try await withCheckedThrowingContinuation { continuation in
            lock.lock()
            if let responseValue {
                self.responseValue = nil
                lock.unlock()
                continuation.resume(returning: responseValue)
                return
            }
            if isComplete {
                let error = terminalError
                    ?? OnboardingWorkerClientError.invalidResponse
                lock.unlock()
                continuation.resume(throwing: error)
                return
            }
            responseContinuation = continuation
            lock.unlock()
        }
    }

    func receiveResponse(
        statusCode: Int,
        headers: [String: String]
    ) {
        let response = OnboardingWorkerHTTPResponse(
            statusCode: statusCode,
            headers: headers,
            body: OnboardingWorkerBody(
                nextChunk: { [self] in
                    try await nextChunk()
                },
                cancelImmediately: { [self] in
                    cancel()
                }
            )
        )

        lock.lock()
        guard !isComplete, responseValue == nil else {
            lock.unlock()
            return
        }
        let continuation = responseContinuation
        responseContinuation = nil
        if continuation == nil {
            responseValue = response
        }
        lock.unlock()
        continuation?.resume(returning: response)
    }

    func receive(_ data: Data) {
        guard !data.isEmpty else { return }
        var directChunk: Data?
        var continuation: CheckedContinuation<Data?, Error>?
        var shouldCancel = false

        lock.lock()
        guard !isComplete else {
            lock.unlock()
            return
        }

        var offset = 0
        if let waitingContinuation = chunkContinuation {
            let chunkLength = min(maximumChunkByteCount, data.count)
            directChunk = Data(data[offset..<(offset + chunkLength)])
            offset += chunkLength
            continuation = waitingContinuation
            chunkContinuation = nil
        }

        let remainingByteCount = data.count - offset
        if bufferedByteCount + remainingByteCount > maximumBufferedByteCount {
            shouldCancel = true
            _ = finishLocked(
                error: OnboardingWorkerClientError.responseTooLarge
            )
        } else {
            while offset < data.count {
                let chunkEnd = min(offset + maximumChunkByteCount, data.count)
                let chunk = Data(data[offset..<chunkEnd])
                chunks.append(chunk)
                bufferedByteCount += chunk.count
                offset = chunkEnd
            }
            if bufferedByteCount >= maximumBufferedByteCount / 2,
               !isTaskSuspended {
                isTaskSuspended = true
                task?.suspend()
            }
        }
        lock.unlock()

        if shouldCancel {
            continuation?.resume(
                throwing: OnboardingWorkerClientError.responseTooLarge
            )
            task?.cancel()
            return
        }
        if let directChunk {
            continuation?.resume(returning: directChunk)
        }
    }

    func complete(error: Error?) {
        lock.lock()
        guard !isComplete else {
            lock.unlock()
            return
        }
        let mappedError: Error?
        if let urlError = error as? URLError,
           urlError.code == .cancelled {
            mappedError = OnboardingWorkerClientError.cancelled
        } else if error != nil {
            mappedError = OnboardingWorkerClientError.serviceUnavailable
        } else {
            mappedError = nil
        }
        let continuations: (
            response: CheckedContinuation<OnboardingWorkerHTTPResponse, Error>?,
            chunk: CheckedContinuation<Data?, Error>?
        )
        if let mappedError {
            continuations = finishLocked(error: mappedError)
        } else {
            if isTaskSuspended {
                isTaskSuspended = false
                task?.resume()
            }
            isComplete = true
            terminalError = nil
            let responseContinuation = responseContinuation
            self.responseContinuation = nil
            let chunkContinuation = chunks.isEmpty
                ? chunkContinuation
                : nil
            if chunks.isEmpty {
                self.chunkContinuation = nil
            }
            continuations = (responseContinuation, chunkContinuation)
        }
        lock.unlock()
        continuations.response?.resume(
            throwing: mappedError
                ?? OnboardingWorkerClientError.invalidResponse
        )
        if let mappedError {
            continuations.chunk?.resume(throwing: mappedError)
        } else {
            continuations.chunk?.resume(returning: nil)
        }
    }

    func cancel() {
        lock.lock()
        guard !isComplete else {
            lock.unlock()
            return
        }
        let continuations = finishLocked(
            error: OnboardingWorkerClientError.cancelled
        )
        let task = task
        lock.unlock()
        task?.cancel()
        continuations.response?.resume(
            throwing: OnboardingWorkerClientError.cancelled
        )
        continuations.chunk?.resume(
            throwing: OnboardingWorkerClientError.cancelled
        )
    }

    func fail(_ error: OnboardingWorkerClientError) {
        lock.lock()
        guard !isComplete else {
            lock.unlock()
            return
        }
        let continuations = finishLocked(error: error)
        let task = task
        lock.unlock()
        task?.cancel()
        continuations.response?.resume(throwing: error)
        continuations.chunk?.resume(throwing: error)
    }

    private func nextChunk() async throws -> Data? {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                lock.lock()
                if !chunks.isEmpty {
                    let chunk = chunks.removeFirst()
                    bufferedByteCount -= chunk.count
                    if isTaskSuspended,
                       bufferedByteCount <= resumeBufferedByteCount {
                        isTaskSuspended = false
                        task?.resume()
                    }
                    lock.unlock()
                    continuation.resume(returning: chunk)
                    return
                }
                if isComplete {
                    let error = terminalError
                    lock.unlock()
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: nil)
                    }
                    return
                }
                chunkContinuation = continuation
                lock.unlock()
            }
        } onCancel: {
            cancel()
        }
    }

    private func finishLocked(
        error: Error?
    ) -> (
        response: CheckedContinuation<OnboardingWorkerHTTPResponse, Error>?,
        chunk: CheckedContinuation<Data?, Error>?
    ) {
        if isTaskSuspended {
            isTaskSuspended = false
            task?.resume()
        }
        isComplete = true
        terminalError = error
        chunks.removeAll()
        bufferedByteCount = 0
        let responseContinuation = responseContinuation
        self.responseContinuation = nil
        let chunkContinuation = chunkContinuation
        self.chunkContinuation = nil
        return (responseContinuation, chunkContinuation)
    }
}

#if canImport(ConvexMobile)
@MainActor
final class ConvexOnboardingTicketIssuer: OnboardingTicketIssuing {
    private let convexClient: ConvexClientWithAuth<String>

    init(convexClient: ConvexClientWithAuth<String>) {
        self.convexClient = convexClient
    }

    func issueOnboardingTicket(
        _ request: OnboardingTicketIssueRequest
    ) async throws -> OnboardingTicketIssueResponse {
        try await convexClient.action(
            "requestTickets:issueOnboarding",
            with: Self.arguments(for: request)
        )
    }

    static func arguments(
        for request: OnboardingTicketIssueRequest
    ) -> [String: ConvexEncodable?] {
        [
            "personaId": request.personaId,
            "scope": request.scope.rawValue,
            "requestBodyDigest": request.requestBodyDigest,
            "requestBodyByteCount": Double(request.requestBodyByteCount),
        ]
    }
}
#endif

actor OnboardingWorkerClient {
    typealias ContextValidityCheck =
        @MainActor @Sendable (OnboardingWorkerOperationContext) async -> Bool
    typealias CurrentTimeMilliseconds = @Sendable () -> Double

    private enum Route: String {
        case chat = "v1/onboarding/chat"
        case textToSpeech = "v1/onboarding/tts"
        case transcription = "v1/onboarding/transcribe-token"
    }

    private static let maximumErrorBodyByteCount = 4_096
    private static let maximumChatStreamByteCount = 1_048_576
    private static let maximumChatEventByteCount = 65_536
    private static let maximumAudioByteCount = 10_485_760
    private static let maximumTranscriptionResponseByteCount = 16_384
    private static let ticketDispatchMarginMilliseconds = 2_000.0
    private static let ticketPattern = try! NSRegularExpression(
        pattern: "^[A-Za-z0-9_-]{43}$"
    )
    private static let clientTurnIDPattern = try! NSRegularExpression(
        pattern: "^[A-Za-z0-9._:-]{1,128}$"
    )

    private let baseURL: URL
    private let context: OnboardingWorkerOperationContext
    private let ticketIssuer: any OnboardingTicketIssuing
    private let urlLoader: any OnboardingWorkerURLLoading
    private let contextValidityCheck: ContextValidityCheck
    private let invalidationSignal: OnboardingWorkerInvalidationSignal
    private let currentTimeMilliseconds: CurrentTimeMilliseconds

    init(
        baseURL: URL,
        context: OnboardingWorkerOperationContext,
        ticketIssuer: any OnboardingTicketIssuing,
        urlLoader: any OnboardingWorkerURLLoading = URLSessionOnboardingWorkerLoader(),
        invalidationSignal: OnboardingWorkerInvalidationSignal =
            OnboardingWorkerInvalidationSignal(),
        currentTimeMilliseconds: @escaping CurrentTimeMilliseconds = {
            Date().timeIntervalSince1970 * 1_000
        },
        contextValidityCheck: @escaping ContextValidityCheck
    ) throws {
        guard let validatedBaseURL = Self.validatedHTTPSOrigin(baseURL) else {
            throw OnboardingWorkerClientError.configurationUnavailable
        }
        self.baseURL = validatedBaseURL
        self.context = context
        self.ticketIssuer = ticketIssuer
        self.urlLoader = urlLoader
        self.invalidationSignal = invalidationSignal
        self.currentTimeMilliseconds = currentTimeMilliseconds
        self.contextValidityCheck = contextValidityCheck
    }

    func streamChat(
        _ requestBody: OnboardingChatRequest
    ) async throws -> OnboardingChatEventStream {
        try await performInvalidationBoundOperation { [self] in
            try await prepareChatStream(requestBody)
        }
    }

    private func prepareChatStream(
        _ requestBody: OnboardingChatRequest
    ) async throws -> OnboardingChatEventStream {
        guard Self.isValidChatRequest(requestBody) else {
            throw OnboardingWorkerClientError.invalidRequest
        }
        let response = try await performRequest(
            scope: .chat,
            route: .chat,
            body: try encodeDeterministically(requestBody),
            contentType: "application/json"
        )
        guard Self.normalizedMediaType(
            response.headerValue(for: "content-type")
        ) == "text/event-stream" else {
            await response.body.cancel()
            throw OnboardingWorkerClientError.invalidResponse
        }
        try await validateDeclaredContentLength(
            response,
            maximumByteCount: Self.maximumChatStreamByteCount
        )

        let invalidationState = OnboardingStreamInvalidationState()
        let lifetime = OnboardingWorkerStreamLifetime(
            body: response.body,
            invalidationSignal: invalidationSignal,
            invalidationState: invalidationState
        )
        let guardedBody = OnboardingGuardedBody(
            body: response.body,
            context: context,
            maximumByteCount: Self.maximumChatStreamByteCount,
            invalidationState: invalidationState,
            lifetime: lifetime,
            completeLifetimeOnEOF: false,
            contextValidityCheck: contextValidityCheck
        )
        let parser = OnboardingSSEParser(
            body: guardedBody,
            maximumEventByteCount: Self.maximumChatEventByteCount
        )
        return OnboardingChatEventStream(
            parser: parser,
            lifetime: lifetime
        )
    }

    func streamTextToSpeech(
        _ requestBody: OnboardingTTSRequest
    ) async throws -> OnboardingWorkerByteStream {
        try await performInvalidationBoundOperation { [self] in
            try await prepareTextToSpeechStream(requestBody)
        }
    }

    private func prepareTextToSpeechStream(
        _ requestBody: OnboardingTTSRequest
    ) async throws -> OnboardingWorkerByteStream {
        guard Self.isValidTTSRequest(requestBody) else {
            throw OnboardingWorkerClientError.invalidRequest
        }
        let response = try await performRequest(
            scope: .textToSpeech,
            route: .textToSpeech,
            body: try encodeDeterministically(requestBody),
            contentType: "application/json"
        )
        guard Self.normalizedMediaType(
            response.headerValue(for: "content-type")
        ) == "audio/mpeg" else {
            await response.body.cancel()
            throw OnboardingWorkerClientError.invalidResponse
        }
        try await validateDeclaredContentLength(
            response,
            maximumByteCount: Self.maximumAudioByteCount
        )

        let invalidationState = OnboardingStreamInvalidationState()
        let lifetime = OnboardingWorkerStreamLifetime(
            body: response.body,
            invalidationSignal: invalidationSignal,
            invalidationState: invalidationState
        )
        let guardedBody = OnboardingGuardedBody(
            body: response.body,
            context: context,
            maximumByteCount: Self.maximumAudioByteCount,
            invalidationState: invalidationState,
            lifetime: lifetime,
            completeLifetimeOnEOF: true,
            contextValidityCheck: contextValidityCheck
        )
        return OnboardingWorkerByteStream(
            body: OnboardingWorkerBody(
                nextChunk: {
                    try await guardedBody.nextChunk()
                },
                cancel: {
                    await guardedBody.cancel()
                },
                cancelImmediately: {
                    lifetime.cancelImmediately()
                }
            ),
            lifetime: lifetime
        )
    }

    func transcriptionToken() async throws
        -> OnboardingTranscriptionTokenResponse {
        try await performInvalidationBoundOperation { [self] in
            try await fetchTranscriptionToken()
        }
    }

    private func fetchTranscriptionToken() async throws
        -> OnboardingTranscriptionTokenResponse {
        let response = try await performRequest(
            scope: .transcription,
            route: .transcription,
            body: Data(),
            contentType: nil
        )
        guard Self.normalizedMediaType(
            response.headerValue(for: "content-type")
        ) == "application/json" else {
            await response.body.cancel()
            throw OnboardingWorkerClientError.invalidResponse
        }
        try await validateDeclaredContentLength(
            response,
            maximumByteCount: Self.maximumTranscriptionResponseByteCount
        )

        let invalidationState = OnboardingStreamInvalidationState()
        let lifetime = OnboardingWorkerStreamLifetime(
            body: response.body,
            invalidationSignal: invalidationSignal,
            invalidationState: invalidationState
        )
        let guardedBody = OnboardingGuardedBody(
            body: response.body,
            context: context,
            maximumByteCount: Self.maximumTranscriptionResponseByteCount,
            invalidationState: invalidationState,
            lifetime: lifetime,
            completeLifetimeOnEOF: true,
            contextValidityCheck: contextValidityCheck
        )
        let responseData = try await guardedBody.readToEnd()
        guard let object = try? JSONSerialization.jsonObject(with: responseData),
              let dictionary = object as? [String: Any],
              Set(dictionary.keys) == ["token"],
              let token = dictionary["token"] as? String,
              !token.isEmpty,
              token.utf8.count <= 4_096 else {
            throw OnboardingWorkerClientError.invalidResponse
        }
        return OnboardingTranscriptionTokenResponse(token: token)
    }

    static func validatedHTTPSOrigin(_ url: URL) -> URL? {
        guard var components = URLComponents(
            url: url,
            resolvingAgainstBaseURL: false
        ),
        components.scheme?.lowercased() == "https",
        components.host != nil,
        components.user == nil,
        components.password == nil,
        components.query == nil,
        components.fragment == nil,
        components.path.isEmpty || components.path == "/",
        !url.absoluteString
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            .hasSuffix(":"),
        components.rangeOfPort == nil
            || components.port.map({ (1...65_535).contains($0) }) == true else {
            return nil
        }
        components.path = ""
        return components.url
    }

    static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map {
            String(format: "%02x", $0)
        }.joined()
    }

    private func performRequest(
        scope: OnboardingWorkerScope,
        route: Route,
        body: Data,
        contentType: String?
    ) async throws -> OnboardingWorkerHTTPResponse {
        try Task.checkCancellation()
        guard await contextValidityCheck(context) else {
            throw OnboardingWorkerClientError.contextInvalidated
        }
        let policy = scope.requestBodyPolicy
        guard body.count >= policy.minimumByteCount,
              body.count <= policy.maximumByteCount else {
            throw OnboardingWorkerClientError.invalidRequest
        }

        let issueRequest = OnboardingTicketIssueRequest(
            personaId: context.personaID,
            scope: scope,
            requestBodyDigest: Self.sha256Hex(body),
            requestBodyByteCount: body.count
        )
        let ticket = try await ticketIssuer.issueOnboardingTicket(issueRequest)

        try Task.checkCancellation()
        guard await contextValidityCheck(context) else {
            throw OnboardingWorkerClientError.contextInvalidated
        }
        guard ticket.scope == scope,
              ticket.expiresAt.isFinite,
              ticket.expiresAt
                > currentTimeMilliseconds()
                    + Self.ticketDispatchMarginMilliseconds,
              ticket.policyVersion >= 1,
              ticket.policyVersion.isFinite,
              ticket.policyVersion.rounded(.towardZero) == ticket.policyVersion,
              Self.matches(ticket.token, pattern: Self.ticketPattern) else {
            throw OnboardingWorkerClientError.invalidResponse
        }

        var request = URLRequest(
            url: baseURL.appendingPathComponent(route.rawValue),
            cachePolicy: .reloadIgnoringLocalCacheData
        )
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue(
            "StickyTicket \(ticket.token)",
            forHTTPHeaderField: "Authorization"
        )
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        if let contentType {
            request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        }

        let response: OnboardingWorkerHTTPResponse
        do {
            response = try await urlLoader.response(for: request)
        } catch is CancellationError {
            throw OnboardingWorkerClientError.cancelled
        } catch let clientError as OnboardingWorkerClientError {
            throw clientError
        } catch {
            throw OnboardingWorkerClientError.serviceUnavailable
        }

        do {
            try Task.checkCancellation()
        } catch {
            await response.body.cancel()
            throw OnboardingWorkerClientError.cancelled
        }
        guard await contextValidityCheck(context) else {
            await response.body.cancel()
            throw OnboardingWorkerClientError.contextInvalidated
        }
        guard response.statusCode == 200 else {
            await discardBoundedErrorBody(response.body)
            if (400...499).contains(response.statusCode) {
                throw OnboardingWorkerClientError.requestDenied
            }
            throw OnboardingWorkerClientError.serviceUnavailable
        }
        return response
    }

    private func performInvalidationBoundOperation<Result: Sendable>(
        _ operation: @escaping @Sendable () async throws -> Result
    ) async throws -> Result {
        let operationTask = Task {
            try await operation()
        }
        guard let registration = invalidationSignal.register(
            cancellation: {
                operationTask.cancel()
            }
        ) else {
            operationTask.cancel()
            throw OnboardingWorkerClientError.contextInvalidated
        }
        defer {
            registration.unregister()
        }
        do {
            return try await withTaskCancellationHandler {
                try await operationTask.value
            } onCancel: {
                operationTask.cancel()
            }
        } catch is CancellationError {
            if invalidationSignal.invalidated {
                throw OnboardingWorkerClientError.contextInvalidated
            }
            throw OnboardingWorkerClientError.cancelled
        } catch OnboardingWorkerClientError.cancelled {
            if invalidationSignal.invalidated {
                throw OnboardingWorkerClientError.contextInvalidated
            }
            throw OnboardingWorkerClientError.cancelled
        }
    }

    private func validateDeclaredContentLength(
        _ response: OnboardingWorkerHTTPResponse,
        maximumByteCount: Int
    ) async throws {
        guard let contentLength = response.headerValue(
            for: "content-length"
        ) else {
            return
        }
        guard !contentLength.isEmpty,
              contentLength.utf8.allSatisfy({ $0 >= 48 && $0 <= 57 }),
              let byteCount = Int(contentLength) else {
            await response.body.cancel()
            throw OnboardingWorkerClientError.invalidResponse
        }
        guard byteCount <= maximumByteCount else {
            await response.body.cancel()
            throw OnboardingWorkerClientError.responseTooLarge
        }
    }

    private func encodeDeterministically<Value: Encodable>(
        _ value: Value
    ) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        do {
            return try encoder.encode(value)
        } catch {
            throw OnboardingWorkerClientError.invalidRequest
        }
    }

    private func discardBoundedErrorBody(
        _ body: OnboardingWorkerBody
    ) async {
        var consumedByteCount = 0
        do {
            while let chunk = try await body.nextChunk() {
                consumedByteCount += chunk.count
                if consumedByteCount > Self.maximumErrorBodyByteCount {
                    break
                }
            }
        } catch {
            // Error bodies are deliberately ignored and never surfaced.
        }
        await body.cancel()
    }

    private static func normalizedMediaType(_ contentType: String?) -> String? {
        guard let contentType else { return nil }
        let mediaType = contentType.split(
            separator: ";",
            maxSplits: 1,
            omittingEmptySubsequences: true
        ).first?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return mediaType?.isEmpty == false ? mediaType : nil
    }

    private static func isValidChatRequest(
        _ request: OnboardingChatRequest
    ) -> Bool {
        let textByteCount = request.text.utf8.count
        return !request.text.isEmpty
            && request.text.count <= 2_000
            && textByteCount <= 2_000
            && matches(request.clientTurnId, pattern: clientTurnIDPattern)
    }

    private static func isValidTTSRequest(
        _ request: OnboardingTTSRequest
    ) -> Bool {
        !request.text.isEmpty
            && request.text.count <= 4_000
            && request.text.utf8.count <= 4_000
    }

    private static func matches(
        _ value: String,
        pattern: NSRegularExpression
    ) -> Bool {
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        return pattern.firstMatch(in: value, range: range)?.range == range
    }
}

private actor OnboardingGuardedBody {
    private let body: OnboardingWorkerBody
    private let context: OnboardingWorkerOperationContext
    private let maximumByteCount: Int
    private let contextValidityCheck: OnboardingWorkerClient.ContextValidityCheck
    private let invalidationState: OnboardingStreamInvalidationState
    private let lifetime: OnboardingWorkerStreamLifetime
    private let completeLifetimeOnEOF: Bool
    private var consumedByteCount = 0
    private var isFinished = false

    init(
        body: OnboardingWorkerBody,
        context: OnboardingWorkerOperationContext,
        maximumByteCount: Int,
        invalidationState: OnboardingStreamInvalidationState,
        lifetime: OnboardingWorkerStreamLifetime,
        completeLifetimeOnEOF: Bool,
        contextValidityCheck: @escaping OnboardingWorkerClient.ContextValidityCheck
    ) {
        self.body = body
        self.context = context
        self.maximumByteCount = maximumByteCount
        self.invalidationState = invalidationState
        self.lifetime = lifetime
        self.completeLifetimeOnEOF = completeLifetimeOnEOF
        self.contextValidityCheck = contextValidityCheck
    }

    func nextChunk() async throws -> Data? {
        guard !isFinished else { return nil }
        guard !invalidationState.invalidated else {
            await cancel()
            throw OnboardingWorkerClientError.contextInvalidated
        }
        do {
            try Task.checkCancellation()
        } catch {
            await cancel()
            throw OnboardingWorkerClientError.cancelled
        }
        guard await contextValidityCheck(context) else {
            await cancel()
            throw OnboardingWorkerClientError.contextInvalidated
        }

        let chunk: Data?
        do {
            chunk = try await body.nextChunk()
        } catch is CancellationError {
            let contextWasInvalidated = await contextIsInvalidated()
            await cancel()
            if contextWasInvalidated {
                throw OnboardingWorkerClientError.contextInvalidated
            }
            throw OnboardingWorkerClientError.cancelled
        } catch let clientError as OnboardingWorkerClientError {
            let contextWasInvalidated = await contextIsInvalidated()
            await cancel()
            if contextWasInvalidated {
                throw OnboardingWorkerClientError.contextInvalidated
            }
            throw clientError
        } catch {
            let contextWasInvalidated = await contextIsInvalidated()
            await cancel()
            if contextWasInvalidated {
                throw OnboardingWorkerClientError.contextInvalidated
            }
            throw OnboardingWorkerClientError.serviceUnavailable
        }

        guard !(await contextIsInvalidated()) else {
            await cancel()
            throw OnboardingWorkerClientError.contextInvalidated
        }
        guard let chunk else {
            isFinished = true
            if completeLifetimeOnEOF {
                lifetime.complete()
            }
            return nil
        }
        consumedByteCount += chunk.count
        guard consumedByteCount <= maximumByteCount else {
            await cancel()
            throw OnboardingWorkerClientError.responseTooLarge
        }
        return chunk
    }

    func readToEnd() async throws -> Data {
        var data = Data()
        while let chunk = try await nextChunk() {
            data.append(chunk)
        }
        return data
    }

    func cancel() async {
        let shouldCancelBody = !isFinished
        isFinished = true
        lifetime.cancelImmediately()
        if shouldCancelBody {
            await body.cancel()
        }
    }

    func validateContextForBufferedDelivery() async throws {
        guard !(await contextIsInvalidated()) else {
            await cancel()
            throw OnboardingWorkerClientError.contextInvalidated
        }
    }

    func completeBufferedDelivery() {
        lifetime.complete()
    }

    private func contextIsInvalidated() async -> Bool {
        if invalidationState.invalidated {
            return true
        }
        return !(await contextValidityCheck(context))
    }
}

nonisolated fileprivate final class OnboardingStreamInvalidationState:
    @unchecked Sendable {
    private let lock = NSLock()
    private var isInvalidated = false

    var invalidated: Bool {
        lock.lock()
        let invalidated = isInvalidated
        lock.unlock()
        return invalidated
    }

    func invalidate() {
        lock.lock()
        isInvalidated = true
        lock.unlock()
    }
}

private actor OnboardingSSEParser {
    private let body: OnboardingGuardedBody
    private let maximumEventByteCount: Int
    private var buffer = Data()
    private var isFinished = false

    init(
        body: OnboardingGuardedBody,
        maximumEventByteCount: Int
    ) {
        self.body = body
        self.maximumEventByteCount = maximumEventByteCount
    }

    func nextEvent() async throws -> OnboardingChatServerSentEvent? {
        while true {
            if let eventData = removeNextEventData() {
                do {
                    if let event = try parseEvent(eventData) {
                        try await body.validateContextForBufferedDelivery()
                        return event
                    }
                } catch {
                    await cancel()
                    throw error
                }
                continue
            }
            guard !isFinished else {
                guard !buffer.isEmpty else {
                    await body.completeBufferedDelivery()
                    return nil
                }
                let finalEventData = buffer
                buffer.removeAll(keepingCapacity: false)
                do {
                    let event = try parseEvent(finalEventData)
                    if event != nil {
                        try await body.validateContextForBufferedDelivery()
                    }
                    await body.completeBufferedDelivery()
                    return event
                } catch {
                    await cancel()
                    throw error
                }
            }
            guard let chunk = try await body.nextChunk() else {
                isFinished = true
                continue
            }
            buffer.append(chunk)
            let containsCompleteEvent =
                earliestBlankLineDelimiter(in: buffer) != nil
            guard containsCompleteEvent
                    || buffer.count <= maximumEventByteCount else {
                await cancel()
                throw OnboardingWorkerClientError.responseTooLarge
            }
        }
    }

    func cancel() async {
        isFinished = true
        buffer.removeAll(keepingCapacity: false)
        await body.cancel()
    }

    private func removeNextEventData() -> Data? {
        guard let delimiterRange = earliestBlankLineDelimiter(
            in: buffer
        ) else {
            return nil
        }
        let eventData = Data(buffer[..<delimiterRange.lowerBound])
        buffer.removeSubrange(..<delimiterRange.upperBound)
        return eventData
    }

    private func earliestBlankLineDelimiter(
        in data: Data
    ) -> Range<Data.Index>? {
        var index = data.startIndex
        while index < data.endIndex {
            guard let firstEndingLength = lineEndingLength(
                in: data,
                at: index
            ) else {
                index = data.index(after: index)
                continue
            }
            let secondEndingStart = index + firstEndingLength
            if let secondEndingLength = lineEndingLength(
                in: data,
                at: secondEndingStart
            ) {
                return index..<(secondEndingStart + secondEndingLength)
            }
            index = secondEndingStart
        }
        return nil
    }

    private func lineEndingLength(
        in data: Data,
        at index: Data.Index
    ) -> Int? {
        guard index < data.endIndex else { return nil }
        switch data[index] {
        case 10:
            return 1
        case 13:
            let nextIndex = data.index(after: index)
            if nextIndex < data.endIndex, data[nextIndex] == 10 {
                return 2
            }
            return 1
        default:
            return nil
        }
    }

    private func parseEvent(
        _ eventData: Data
    ) throws -> OnboardingChatServerSentEvent? {
        guard eventData.count <= maximumEventByteCount,
              let eventText = String(data: eventData, encoding: .utf8) else {
            throw OnboardingWorkerClientError.invalidResponse
        }

        var eventName: String?
        var eventID: String?
        var dataLines: [String] = []
        for rawLine in eventText.split(
            omittingEmptySubsequences: false,
            whereSeparator: \.isNewline
        ) {
            var line = String(rawLine)
            if line.hasSuffix("\r") {
                line.removeLast()
            }
            if line.isEmpty || line.hasPrefix(":") {
                continue
            }
            let fieldParts = line.split(
                separator: ":",
                maxSplits: 1,
                omittingEmptySubsequences: false
            )
            let field = String(fieldParts[0])
            var value = fieldParts.count == 2 ? String(fieldParts[1]) : ""
            if value.hasPrefix(" ") {
                value.removeFirst()
            }
            switch field {
            case "event":
                eventName = value
            case "data":
                dataLines.append(value)
            case "id":
                guard !value.contains("\0") else {
                    throw OnboardingWorkerClientError.invalidResponse
                }
                eventID = value
            default:
                continue
            }
        }
        guard !dataLines.isEmpty else { return nil }
        return OnboardingChatServerSentEvent(
            event: eventName,
            data: dataLines.joined(separator: "\n"),
            id: eventID
        )
    }
}
