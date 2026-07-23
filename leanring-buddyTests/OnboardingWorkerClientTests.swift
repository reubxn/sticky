import Foundation
import Testing

#if canImport(ConvexMobile)
import ConvexMobile
#endif

@testable import leanring_buddy

@MainActor
struct OnboardingWorkerClientTests {
    private let context = OnboardingWorkerOperationContext(
        clerkUserID: "clerk-user-1",
        authGeneration: 7,
        workspaceID: "workspaces:1",
        personaID: "personas:1"
    )

    @Test
    func chatUsesDeterministicExactBytesAndBoundTicket() async throws {
        let issuer = MockOnboardingTicketIssuer()
        let bodySource = TestBodySource(
            chunks: [Data("data: done\n\n".utf8)]
        )
        let loader = MockOnboardingWorkerLoader(
            responses: [
                response(
                    contentType: "text/event-stream; charset=utf-8",
                    source: bodySource
                )
            ]
        )
        let client = try makeClient(issuer: issuer, loader: loader)

        _ = try await client.streamChat(
            OnboardingChatRequest(
                text: "hello",
                clientTurnId: "turn-1"
            )
        )

        let issuedRequest = try #require(issuer.requests.first)
        let workerRequest = try #require(await loader.requests.first)
        let expectedBody = Data(
            #"{"clientTurnId":"turn-1","text":"hello"}"#.utf8
        )
        #expect(workerRequest.httpBody == expectedBody)
        #expect(
            issuedRequest.requestBodyDigest
                == OnboardingWorkerClient.sha256Hex(expectedBody)
        )
        #expect(issuedRequest.requestBodyByteCount == expectedBody.count)
        #expect(issuedRequest.scope == .chat)
        #expect(issuedRequest.personaId == context.personaID)
        #expect(
            workerRequest.value(forHTTPHeaderField: "Authorization")
                == "StickyTicket \(issuer.issuedTokens[0])"
        )
        #expect(workerRequest.url?.path == "/v1/onboarding/chat")

        let jsonObject = try #require(
            try JSONSerialization.jsonObject(with: expectedBody)
                as? [String: Any]
        )
        #expect(Set(jsonObject.keys) == ["clientTurnId", "text"])
    }

    @Test
    func everyOperationIssuesAFreshTicket() async throws {
        let issuer = MockOnboardingTicketIssuer()
        let loader = MockOnboardingWorkerLoader(
            responses: [
                response(
                    contentType: "audio/mpeg",
                    source: TestBodySource(chunks: [])
                ),
                response(
                    contentType: "audio/mpeg",
                    source: TestBodySource(chunks: [])
                ),
            ]
        )
        let client = try makeClient(issuer: issuer, loader: loader)

        _ = try await client.streamTextToSpeech(
            OnboardingTTSRequest(text: "one")
        )
        _ = try await client.streamTextToSpeech(
            OnboardingTTSRequest(text: "two")
        )

        #expect(issuer.requests.count == 2)
        let requests = await loader.requests
        #expect(requests.count == 2)
        #expect(issuer.requests.allSatisfy { $0.scope == .textToSpeech })
        #expect(
            requests.allSatisfy { $0.url?.path == "/v1/onboarding/tts" }
        )
        #expect(
            requests[0].value(forHTTPHeaderField: "Authorization")
                != requests[1].value(forHTTPHeaderField: "Authorization")
        )
        #expect(issuer.issuedTokens.count == 2)
        #expect(Set(issuer.issuedTokens).count == 2)
    }

    @Test
    func transcriptionBindsTheExactEmptyBody() async throws {
        let issuer = MockOnboardingTicketIssuer()
        let loader = MockOnboardingWorkerLoader(
            responses: [
                response(
                    contentType: "application/json",
                    source: TestBodySource(
                        chunks: [Data(#"{"token":"temporary"}"#.utf8)]
                    )
                )
            ]
        )
        let client = try makeClient(issuer: issuer, loader: loader)

        let response = try await client.transcriptionToken()

        #expect(response.token == "temporary")
        let issuedRequest = try #require(issuer.requests.first)
        #expect(issuedRequest.scope == .transcription)
        #expect(issuedRequest.requestBodyByteCount == 0)
        #expect(
            issuedRequest.requestBodyDigest
                == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
        )
        let workerRequest = try #require(await loader.requests.first)
        #expect(workerRequest.httpBody == Data())
        #expect(
            workerRequest.value(forHTTPHeaderField: "Content-Type") == nil
        )
        #expect(
            workerRequest.url?.path
                == "/v1/onboarding/transcribe-token"
        )
    }

    #if canImport(ConvexMobile)
    @Test
    func convexTicketByteCountUsesNumberWireEncoding() throws {
        let request = OnboardingTicketIssueRequest(
            personaId: "personas:1",
            scope: .chat,
            requestBodyDigest: String(repeating: "a", count: 64),
            requestBodyByteCount: 42
        )
        let arguments = ConvexOnboardingTicketIssuer.arguments(for: request)
        let byteCountArgument = try #require(
            arguments["requestBodyByteCount"] ?? nil
        )
        let encodedArgument = try byteCountArgument.convexEncode()

        #expect(encodedArgument == "42")
        #expect(!encodedArgument.contains("$integer"))
    }
    #endif

    @Test
    func rejectsScopeMismatchBeforeWorkerRequest() async throws {
        let issuer = MockOnboardingTicketIssuer(
            responseScopes: [.textToSpeech]
        )
        let loader = MockOnboardingWorkerLoader(responses: [])
        let client = try makeClient(issuer: issuer, loader: loader)

        await #expect(throws: OnboardingWorkerClientError.invalidResponse) {
            _ = try await client.streamChat(
                OnboardingChatRequest(
                    text: "hello",
                    clientTurnId: "turn-1"
                )
            )
        }
        #expect(await loader.requests.isEmpty)
    }

    @Test
    func rejectsExpiredAndNearExpiryTicketsBeforeWorkerRequest() async throws {
        for expiresAt in [999_999.0, 1_002_000.0] {
            let issuer = MockOnboardingTicketIssuer(
                responseExpiries: [expiresAt]
            )
            let loader = MockOnboardingWorkerLoader(responses: [])
            let client = try makeClient(
                issuer: issuer,
                loader: loader,
                nowMilliseconds: 1_000_000
            )

            await #expect(
                throws: OnboardingWorkerClientError.invalidResponse
            ) {
                _ = try await client.transcriptionToken()
            }
            #expect(await loader.requests.isEmpty)
        }
    }

    @Test
    func acceptsTicketBeyondDispatchMargin() async throws {
        let issuer = MockOnboardingTicketIssuer(
            responseExpiries: [1_002_001]
        )
        let loader = MockOnboardingWorkerLoader(
            responses: [
                response(
                    contentType: "application/json",
                    source: TestBodySource(
                        chunks: [Data(#"{"token":"temporary"}"#.utf8)]
                    )
                )
            ]
        )
        let client = try makeClient(
            issuer: issuer,
            loader: loader,
            nowMilliseconds: 1_000_000
        )

        _ = try await client.transcriptionToken()

        #expect(await loader.requests.count == 1)
    }

    @Test
    func rejectsUnexpectedContentTypeAndCancelsBody() async throws {
        let source = TestBodySource(chunks: [Data("not audio".utf8)])
        let client = try makeClient(
            issuer: MockOnboardingTicketIssuer(),
            loader: MockOnboardingWorkerLoader(
                responses: [
                    response(
                        contentType: "application/json",
                        source: source
                    )
                ]
            )
        )

        await #expect(throws: OnboardingWorkerClientError.invalidResponse) {
            _ = try await client.streamTextToSpeech(
                OnboardingTTSRequest(text: "hello")
            )
        }
        #expect(await source.wasCancelled)
    }

    @Test
    func capsTranscriptionResponseWithoutDecodingIt() async throws {
        let source = TestBodySource(
            chunks: [Data(repeating: 65, count: 16_385)]
        )
        let client = try makeClient(
            issuer: MockOnboardingTicketIssuer(),
            loader: MockOnboardingWorkerLoader(
                responses: [
                    response(
                        contentType: "application/json",
                        source: source
                    )
                ]
            )
        )

        await #expect(throws: OnboardingWorkerClientError.responseTooLarge) {
            _ = try await client.transcriptionToken()
        }
        #expect(await source.wasCancelled)
    }

    @Test
    func rejectsOversizedDeclaredStreamBeforeReading() async throws {
        let source = TestBodySource(chunks: [Data([1, 2, 3])])
        let oversizedResponse = OnboardingWorkerHTTPResponse(
            statusCode: 200,
            headers: [
                "Content-Type": "audio/mpeg",
                "Content-Length": "10485761",
            ],
            body: OnboardingWorkerBody(
                nextChunk: {
                    try await source.nextChunk()
                },
                cancel: {
                    await source.cancel()
                }
            )
        )
        let client = try makeClient(
            issuer: MockOnboardingTicketIssuer(),
            loader: MockOnboardingWorkerLoader(
                responses: [oversizedResponse]
            )
        )

        await #expect(throws: OnboardingWorkerClientError.responseTooLarge) {
            _ = try await client.streamTextToSpeech(
                OnboardingTTSRequest(text: "hello")
            )
        }
        #expect(await source.readCount == 0)
        #expect(await source.wasCancelled)
    }

    @Test
    func returnsSanitizedStatusErrorAndBoundsErrorBody() async throws {
        let source = TestBodySource(
            chunks: [
                Data(repeating: 65, count: 3_000),
                Data(repeating: 66, count: 3_000),
                Data("secret backend details".utf8),
            ]
        )
        let client = try makeClient(
            issuer: MockOnboardingTicketIssuer(),
            loader: MockOnboardingWorkerLoader(
                responses: [
                    response(
                        statusCode: 403,
                        contentType: "application/json",
                        source: source
                    )
                ]
            )
        )

        await #expect(throws: OnboardingWorkerClientError.requestDenied) {
            _ = try await client.transcriptionToken()
        }
        #expect(await source.readCount == 2)
        #expect(await source.wasCancelled)
    }

    @Test
    func invalidContextBeforeIssueStopsImmediately() async throws {
        let issuer = MockOnboardingTicketIssuer()
        let validity = SequencedContextValidity(results: [false])
        let client = try makeClient(
            issuer: issuer,
            loader: MockOnboardingWorkerLoader(responses: []),
            validity: validity
        )

        await #expect(
            throws: OnboardingWorkerClientError.contextInvalidated
        ) {
            _ = try await client.transcriptionToken()
        }
        #expect(issuer.requests.isEmpty)
    }

    @Test
    func invalidContextAfterIssueDiscardsTicket() async throws {
        let issuer = MockOnboardingTicketIssuer()
        let loader = MockOnboardingWorkerLoader(responses: [])
        let validity = SequencedContextValidity(results: [true, false])
        let client = try makeClient(
            issuer: issuer,
            loader: loader,
            validity: validity
        )

        await #expect(
            throws: OnboardingWorkerClientError.contextInvalidated
        ) {
            _ = try await client.transcriptionToken()
        }
        #expect(issuer.requests.count == 1)
        #expect(await loader.requests.isEmpty)
    }

    @Test
    func invalidContextAfterWorkerResponseCancelsBody() async throws {
        let source = TestBodySource(
            chunks: [Data(#"{"token":"temporary"}"#.utf8)]
        )
        let validity = SequencedContextValidity(
            results: [true, true, false]
        )
        let client = try makeClient(
            issuer: MockOnboardingTicketIssuer(),
            loader: MockOnboardingWorkerLoader(
                responses: [
                    response(
                        contentType: "application/json",
                        source: source
                    )
                ]
            ),
            validity: validity
        )

        await #expect(
            throws: OnboardingWorkerClientError.contextInvalidated
        ) {
            _ = try await client.transcriptionToken()
        }
        #expect(await source.wasCancelled)
        #expect(await source.readCount == 0)
    }

    @Test
    func invalidContextDuringStreamCancelsRemainingBody() async throws {
        let source = TestBodySource(
            chunks: [
                Data("data: first\n\n".utf8),
                Data("data: second\n\n".utf8),
            ]
        )
        let validity = SequencedContextValidity(
            results: [true, true, true, true, false]
        )
        let client = try makeClient(
            issuer: MockOnboardingTicketIssuer(),
            loader: MockOnboardingWorkerLoader(
                responses: [
                    response(
                        contentType: "text/event-stream",
                        source: source
                    )
                ]
            ),
            validity: validity
        )
        let stream = try await client.streamChat(
            OnboardingChatRequest(
                text: "hello",
                clientTurnId: "turn-1"
            )
        )
        var iterator = stream.makeAsyncIterator()

        let first = try await iterator.next()
        #expect(first?.data == "first")
        await #expect(
            throws: OnboardingWorkerClientError.contextInvalidated
        ) {
            _ = try await iterator.next()
        }
        #expect(await source.wasCancelled)
    }

    @Test
    func invalidationWhileChunkIsPendingDoesNotEmitEvent() async throws {
        let signal = OnboardingWorkerInvalidationSignal()
        let source = PendingChunkSource()
        let pendingResponse = OnboardingWorkerHTTPResponse(
            statusCode: 200,
            headers: ["Content-Type": "text/event-stream"],
            body: OnboardingWorkerBody(
                nextChunk: {
                    try await source.nextChunk()
                }
            )
        )
        let client = try makeClient(
            issuer: MockOnboardingTicketIssuer(),
            loader: MockOnboardingWorkerLoader(
                responses: [pendingResponse]
            ),
            invalidationSignal: signal
        )
        let stream = try await client.streamChat(
            OnboardingChatRequest(
                text: "hello",
                clientTurnId: "turn-pending"
            )
        )
        var iterator = stream.makeAsyncIterator()
        let nextEventTask = Task {
            try await iterator.next()
        }
        #expect(
            await waitUntil {
                source.hasPendingContinuation
            }
        )

        signal.invalidate()
        source.fulfill(Data("data: must-not-escape\n\n".utf8))

        await #expect(
            throws: OnboardingWorkerClientError.contextInvalidated
        ) {
            _ = try await nextEventTask.value
        }
    }

    @Test
    func explicitStreamCancellationCancelsUnderlyingResponse() async throws {
        let signal = OnboardingWorkerInvalidationSignal()
        let source = TestBodySource(
            chunks: [Data(repeating: 1, count: 100)]
        )
        let client = try makeClient(
            issuer: MockOnboardingTicketIssuer(),
            loader: MockOnboardingWorkerLoader(
                responses: [
                    response(
                        contentType: "audio/mpeg",
                        source: source
                    )
                ]
            ),
            invalidationSignal: signal
        )
        let stream = try await client.streamTextToSpeech(
            OnboardingTTSRequest(text: "hello")
        )

        await stream.cancel()

        #expect(await source.wasCancelled)
        #expect(signal.registrationCount == 0)
    }

    @Test
    func generationInvalidationImmediatelyCancelsDormantStream() async throws {
        let signal = OnboardingWorkerInvalidationSignal()
        let source = TestBodySource(
            chunks: [Data(repeating: 1, count: 8_192)]
        )
        let cancellationProbe = ImmediateCancellationProbe()
        let dormantResponse = OnboardingWorkerHTTPResponse(
            statusCode: 200,
            headers: ["Content-Type": "audio/mpeg"],
            body: OnboardingWorkerBody(
                nextChunk: {
                    try await source.nextChunk()
                },
                cancel: {
                    await source.cancel()
                },
                cancelImmediately: {
                    cancellationProbe.cancel()
                }
            )
        )
        let client = try makeClient(
            issuer: MockOnboardingTicketIssuer(),
            loader: MockOnboardingWorkerLoader(
                responses: [dormantResponse]
            ),
            invalidationSignal: signal
        )
        let stream = try await client.streamTextToSpeech(
            OnboardingTTSRequest(text: "hello")
        )

        signal.invalidate()

        #expect(cancellationProbe.wasCancelled)
        var iterator = stream.makeAsyncIterator()
        await #expect(
            throws: OnboardingWorkerClientError.contextInvalidated
        ) {
            _ = try await iterator.next()
        }
    }

    @Test
    func generationInvalidationCancelsInFlightRequest() async throws {
        let signal = OnboardingWorkerInvalidationSignal()
        let loader = BlockingOnboardingWorkerLoader()
        let client = try makeClient(
            issuer: MockOnboardingTicketIssuer(),
            loader: loader,
            invalidationSignal: signal
        )
        let requestTask = Task {
            try await client.transcriptionToken()
        }
        while !(await loader.hasStarted) {
            await Task.yield()
        }

        signal.invalidate()

        await #expect(
            throws: OnboardingWorkerClientError.contextInvalidated
        ) {
            _ = try await requestTask.value
        }
        #expect(await loader.observedCancellation)
    }

    @Test
    func accountSwitchSignalCancelsAllRegisteredOperations() {
        let signal = OnboardingWorkerInvalidationSignal()
        let firstCancellation = ImmediateCancellationProbe()
        let secondCancellation = ImmediateCancellationProbe()
        let firstRegistration = signal.register {
            firstCancellation.cancel()
        }
        let secondRegistration = signal.register {
            secondCancellation.cancel()
        }

        signal.invalidate()

        #expect(firstRegistration != nil)
        #expect(secondRegistration != nil)
        #expect(firstCancellation.wasCancelled)
        #expect(secondCancellation.wasCancelled)
        #expect(signal.invalidated)
        #expect(signal.register(cancellation: {}) == nil)
    }

    @Test
    func parsesChunkedSSEFieldsWithDemandDrivenReads() async throws {
        let source = TestBodySource(
            chunks: [
                Data(": keep-alive\r\n".utf8),
                Data("event: delta\r\ndata: first\r\n".utf8),
                Data("data: second\r\nid: event-1\r\n\r\n".utf8),
                Data("data: final\n\n".utf8),
            ]
        )
        let client = try makeClient(
            issuer: MockOnboardingTicketIssuer(),
            loader: MockOnboardingWorkerLoader(
                responses: [
                    response(
                        contentType: "text/event-stream",
                        source: source
                    )
                ]
            )
        )
        let stream = try await client.streamChat(
            OnboardingChatRequest(
                text: "hello",
                clientTurnId: "turn-1"
            )
        )
        var iterator = stream.makeAsyncIterator()

        let first = try await iterator.next()
        #expect(first?.event == "delta")
        #expect(first?.data == "first\nsecond")
        #expect(first?.id == "event-1")
        #expect(await source.readCount == 3)

        let second = try await iterator.next()
        #expect(second?.data == "final")
        #expect(try await iterator.next() == nil)
    }

    @Test
    func bufferedSecondEventCannotEscapeAfterInvalidation() async throws {
        let signal = OnboardingWorkerInvalidationSignal()
        let source = TestBodySource(
            chunks: [
                Data("data: first\n\ndata: second\n\n".utf8)
            ]
        )
        let cancellationProbe = ImmediateCancellationProbe()
        let bufferedResponse = OnboardingWorkerHTTPResponse(
            statusCode: 200,
            headers: ["Content-Type": "text/event-stream"],
            body: OnboardingWorkerBody(
                nextChunk: {
                    try await source.nextChunk()
                },
                cancel: {
                    await source.cancel()
                },
                cancelImmediately: {
                    cancellationProbe.cancel()
                }
            )
        )
        let client = try makeClient(
            issuer: MockOnboardingTicketIssuer(),
            loader: MockOnboardingWorkerLoader(
                responses: [bufferedResponse]
            ),
            invalidationSignal: signal
        )
        let stream = try await client.streamChat(
            OnboardingChatRequest(
                text: "hello",
                clientTurnId: "turn-buffered"
            )
        )
        var iterator = stream.makeAsyncIterator()

        let first = try await iterator.next()
        #expect(first?.data == "first")

        signal.invalidate()

        await #expect(
            throws: OnboardingWorkerClientError.contextInvalidated
        ) {
            _ = try await iterator.next()
        }
        #expect(cancellationProbe.wasCancelled)
        #expect(await source.wasCancelled)
        #expect(signal.registrationCount == 0)
    }

    @Test
    func parsesEarliestMixedSSEDelimiterWithoutReordering() async throws {
        let source = TestBodySource(
            chunks: [
                Data("data: first\r".utf8),
                Data("\ndata: one\n\rdata: second\r".utf8),
                Data("\rdata: third\n\n".utf8),
            ]
        )
        let client = try makeClient(
            issuer: MockOnboardingTicketIssuer(),
            loader: MockOnboardingWorkerLoader(
                responses: [
                    response(
                        contentType: "text/event-stream",
                        source: source
                    )
                ]
            )
        )
        let stream = try await client.streamChat(
            OnboardingChatRequest(
                text: "hello",
                clientTurnId: "turn-mixed"
            )
        )
        var iterator = stream.makeAsyncIterator()

        #expect(try await iterator.next()?.data == "first\none")
        #expect(try await iterator.next()?.data == "second")
        #expect(try await iterator.next()?.data == "third")
    }

    @Test
    func parsesCROnlyDelimiterSplitAcrossChunks() async throws {
        let source = TestBodySource(
            chunks: [
                Data("event: delta\rdata: first\r".utf8),
                Data("\rdata: second\r".utf8),
                Data("\r".utf8),
            ]
        )
        let client = try makeClient(
            issuer: MockOnboardingTicketIssuer(),
            loader: MockOnboardingWorkerLoader(
                responses: [
                    response(
                        contentType: "text/event-stream",
                        source: source
                    )
                ]
            )
        )
        let stream = try await client.streamChat(
            OnboardingChatRequest(
                text: "hello",
                clientTurnId: "turn-cr"
            )
        )
        var iterator = stream.makeAsyncIterator()

        let first = try await iterator.next()
        #expect(first?.event == "delta")
        #expect(first?.data == "first")
        #expect(try await iterator.next()?.data == "second")
    }

    @Test
    func productionLoaderDeliversMultiKilobyteChunks() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MultiKilobyteURLProtocol.self]
        let loader = URLSessionOnboardingWorkerLoader(
            configuration: configuration
        )
        let request = URLRequest(
            url: URL(string: "https://worker.example/audio")!
        )

        let response = try await loader.response(for: request)
        let firstChunk = try #require(
            try await response.body.nextChunk()
        )

        #expect(response.statusCode == 200)
        #expect(firstChunk.count == 8_192)
        #expect(try await response.body.nextChunk() == nil)
    }

    @Test
    func droppingBufferedAudioStreamCancelsAndUnregisters() async throws {
        let signal = OnboardingWorkerInvalidationSignal()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [BufferedAudioURLProtocol.self]
        let loader = URLSessionOnboardingWorkerLoader(
            configuration: configuration
        )
        let client = try makeClient(
            issuer: MockOnboardingTicketIssuer(),
            loader: loader,
            invalidationSignal: signal
        )
        var stream: OnboardingWorkerByteStream? =
            try await client.streamTextToSpeech(
                OnboardingTTSRequest(text: "hello")
            )
        #expect(stream != nil)
        #expect(
            await waitUntil {
                loader.suspendedTaskCount == 1
            }
        )
        #expect(signal.registrationCount == 1)

        stream = nil

        #expect(
            await waitUntil {
                BufferedAudioURLProtocol.cancellationProbe.wasCancelled
                    && loader.activeTaskCount == 0
            }
        )
        #expect(signal.registrationCount == 0)
    }

    @Test
    func droppingBufferedChatStreamCancelsAndUnregisters() async throws {
        let signal = OnboardingWorkerInvalidationSignal()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [BufferedChatURLProtocol.self]
        let loader = URLSessionOnboardingWorkerLoader(
            configuration: configuration
        )
        let client = try makeClient(
            issuer: MockOnboardingTicketIssuer(),
            loader: loader,
            invalidationSignal: signal
        )
        var stream: OnboardingChatEventStream? =
            try await client.streamChat(
                OnboardingChatRequest(
                    text: "hello",
                    clientTurnId: "turn-drop"
                )
            )
        #expect(stream != nil)
        #expect(
            await waitUntil {
                loader.suspendedTaskCount == 1
            }
        )
        #expect(signal.registrationCount == 1)

        stream = nil

        #expect(
            await waitUntil {
                BufferedChatURLProtocol.cancellationProbe.wasCancelled
                    && loader.activeTaskCount == 0
            }
        )
        #expect(signal.registrationCount == 0)
    }

    @Test
    func drainingThresholdResumesBeforeCancellation() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ThresholdOrderingURLProtocol.self]
        let loader = URLSessionOnboardingWorkerLoader(
            configuration: configuration
        )
        let response = try await loader.response(
            for: URLRequest(
                url: URL(string: "https://worker.example/threshold")!
            )
        )
        #expect(
            await waitUntil {
                loader.suspendedTaskCount == 1
            }
        )

        let firstChunk = try await response.body.nextChunk()
        let secondChunk = try await response.body.nextChunk()

        #expect(firstChunk?.count == 16_384)
        #expect(secondChunk?.count == 16_384)
        #expect(
            await waitUntil {
                loader.suspendedTaskCount == 0
            }
        )
        await response.body.cancel()
        #expect(
            await waitUntil {
                ThresholdOrderingURLProtocol.cancellationProbe.wasCancelled
                    && loader.activeTaskCount == 0
            }
        )
    }

    @Test
    func validatesHTTPSOriginOnly() {
        #expect(
            OnboardingWorkerClient.validatedHTTPSOrigin(
                URL(string: "https://worker.example")!
            ) == URL(string: "https://worker.example")
        )
        #expect(
            OnboardingWorkerClient.validatedHTTPSOrigin(
                URL(string: "http://worker.example")!
            ) == nil
        )
        #expect(
            OnboardingWorkerClient.validatedHTTPSOrigin(
                URL(string: "https://worker.example/path")!
            ) == nil
        )
        #expect(
            OnboardingWorkerClient.validatedHTTPSOrigin(
                URL(string: "https://user@worker.example")!
            ) == nil
        )
        #expect(
            OnboardingWorkerClient.validatedHTTPSOrigin(
                URL(string: "https://worker.example:443")!
            ) == URL(string: "https://worker.example:443")
        )
        #expect(
            OnboardingWorkerClient.validatedHTTPSOrigin(
                URL(string: "https://worker.example:1")!
            ) == URL(string: "https://worker.example:1")
        )
        #expect(
            OnboardingWorkerClient.validatedHTTPSOrigin(
                URL(string: "https://worker.example:65535")!
            ) == URL(string: "https://worker.example:65535")
        )
        #expect(
            OnboardingWorkerClient.validatedHTTPSOrigin(
                URL(string: "https://worker.example:0")!
            ) == nil
        )
        #expect(
            OnboardingWorkerClient.validatedHTTPSOrigin(
                URL(string: "https://worker.example:")!
            ) == nil
        )
        #expect(
            OnboardingWorkerClient.validatedHTTPSOrigin(
                URL(string: "https://worker.example:65536")!
            ) == nil
        )
    }

    private func makeClient(
        issuer: MockOnboardingTicketIssuer,
        loader: any OnboardingWorkerURLLoading,
        validity: SequencedContextValidity = SequencedContextValidity(
            results: [true]
        ),
        invalidationSignal: OnboardingWorkerInvalidationSignal =
            OnboardingWorkerInvalidationSignal(),
        nowMilliseconds: Double = 1_000_000
    ) throws -> OnboardingWorkerClient {
        try OnboardingWorkerClient(
            baseURL: URL(string: "https://worker.example")!,
            context: context,
            ticketIssuer: issuer,
            urlLoader: loader,
            invalidationSignal: invalidationSignal,
            currentTimeMilliseconds: {
                nowMilliseconds
            },
            contextValidityCheck: { operationContext in
                await validity.check(operationContext)
            }
        )
    }

    private func response(
        statusCode: Int = 200,
        contentType: String,
        source: TestBodySource
    ) -> OnboardingWorkerHTTPResponse {
        OnboardingWorkerHTTPResponse(
            statusCode: statusCode,
            headers: ["Content-Type": contentType],
            body: OnboardingWorkerBody(
                nextChunk: {
                    try await source.nextChunk()
                },
                cancel: {
                    await source.cancel()
                }
            )
        )
    }

    private func waitUntil(
        _ condition: @escaping @Sendable () -> Bool
    ) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(2))
        while clock.now < deadline {
            if condition() {
                return true
            }
            await Task.yield()
        }
        return condition()
    }
}

@MainActor
private final class MockOnboardingTicketIssuer: OnboardingTicketIssuing {
    private(set) var requests: [OnboardingTicketIssueRequest] = []
    private(set) var issuedTokens: [String] = []
    private var responseScopes: [OnboardingWorkerScope]
    private var responseExpiries: [Double]

    init(
        responseScopes: [OnboardingWorkerScope] = [],
        responseExpiries: [Double] = []
    ) {
        self.responseScopes = responseScopes
        self.responseExpiries = responseExpiries
    }

    func issueOnboardingTicket(
        _ request: OnboardingTicketIssueRequest
    ) async throws -> OnboardingTicketIssueResponse {
        requests.append(request)
        let ticketCharacter = String(
            UnicodeScalar(65 + requests.count - 1)!
        )
        let token = String(repeating: ticketCharacter, count: 43)
        issuedTokens.append(token)
        let responseScope = responseScopes.isEmpty
            ? request.scope
            : responseScopes.removeFirst()
        let expiresAt = responseExpiries.isEmpty
            ? 9_999_999_999_999
            : responseExpiries.removeFirst()
        return OnboardingTicketIssueResponse(
            token: token,
            scope: responseScope,
            expiresAt: expiresAt,
            policyVersion: 1
        )
    }
}

private actor MockOnboardingWorkerLoader: OnboardingWorkerURLLoading {
    private(set) var requests: [URLRequest] = []
    private var responses: [OnboardingWorkerHTTPResponse]

    init(responses: [OnboardingWorkerHTTPResponse]) {
        self.responses = responses
    }

    func response(
        for request: URLRequest
    ) async throws -> OnboardingWorkerHTTPResponse {
        requests.append(request)
        guard !responses.isEmpty else {
            throw OnboardingWorkerClientError.serviceUnavailable
        }
        return responses.removeFirst()
    }
}

private actor BlockingOnboardingWorkerLoader: OnboardingWorkerURLLoading {
    private(set) var hasStarted = false
    private(set) var observedCancellation = false

    func response(
        for request: URLRequest
    ) async throws -> OnboardingWorkerHTTPResponse {
        hasStarted = true
        do {
            try await Task.sleep(for: .seconds(60))
            throw OnboardingWorkerClientError.serviceUnavailable
        } catch is CancellationError {
            observedCancellation = true
            throw CancellationError()
        }
    }
}

private actor TestBodySource {
    private var chunks: [Data]
    private(set) var wasCancelled = false
    private(set) var readCount = 0

    init(chunks: [Data]) {
        self.chunks = chunks
    }

    func nextChunk() throws -> Data? {
        if wasCancelled {
            throw CancellationError()
        }
        guard !chunks.isEmpty else { return nil }
        readCount += 1
        return chunks.removeFirst()
    }

    func cancel() {
        wasCancelled = true
        chunks.removeAll()
    }
}

nonisolated private final class PendingChunkSource: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Data?, Error>?
    private var pendingData: Data?

    var hasPendingContinuation: Bool {
        lock.lock()
        let hasPendingContinuation = continuation != nil
        lock.unlock()
        return hasPendingContinuation
    }

    func nextChunk() async throws -> Data? {
        try await withCheckedThrowingContinuation { continuation in
            lock.lock()
            if let pendingData {
                self.pendingData = nil
                lock.unlock()
                continuation.resume(returning: pendingData)
                return
            }
            self.continuation = continuation
            lock.unlock()
        }
    }

    func fulfill(_ data: Data) {
        lock.lock()
        let continuation = continuation
        self.continuation = nil
        if continuation == nil {
            pendingData = data
        }
        lock.unlock()
        continuation?.resume(returning: data)
    }
}

private actor SequencedContextValidity {
    private let results: [Bool]
    private var checkCount = 0

    init(results: [Bool]) {
        self.results = results
    }

    func check(
        _ context: OnboardingWorkerOperationContext
    ) -> Bool {
        defer { checkCount += 1 }
        guard checkCount < results.count else {
            return results.last ?? false
        }
        return results[checkCount]
    }
}

nonisolated private final class ImmediateCancellationProbe:
    @unchecked Sendable {
    private let lock = NSLock()
    private var isCancelled = false

    var wasCancelled: Bool {
        lock.lock()
        let wasCancelled = isCancelled
        lock.unlock()
        return wasCancelled
    }

    func cancel() {
        lock.lock()
        isCancelled = true
        lock.unlock()
    }
}

nonisolated private final class MultiKilobyteURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(
        for request: URLRequest
    ) -> URLRequest {
        request
    }

    override func startLoading() {
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: [
                "Content-Type": "audio/mpeg",
                "Content-Length": "8192",
            ]
        )!
        client?.urlProtocol(
            self,
            didReceive: response,
            cacheStoragePolicy: .notAllowed
        )
        client?.urlProtocol(
            self,
            didLoad: Data(repeating: 7, count: 8_192)
        )
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

nonisolated private final class BufferedAudioURLProtocol: URLProtocol {
    static let cancellationProbe = ImmediateCancellationProbe()

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(
        for request: URLRequest
    ) -> URLRequest {
        request
    }

    override func startLoading() {
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "audio/mpeg"]
        )!
        client?.urlProtocol(
            self,
            didReceive: response,
            cacheStoragePolicy: .notAllowed
        )
        client?.urlProtocol(
            self,
            didLoad: Data(repeating: 7, count: 40_960)
        )
    }

    override func stopLoading() {
        Self.cancellationProbe.cancel()
    }
}

nonisolated private final class BufferedChatURLProtocol: URLProtocol {
    static let cancellationProbe = ImmediateCancellationProbe()

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(
        for request: URLRequest
    ) -> URLRequest {
        request
    }

    override func startLoading() {
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "text/event-stream"]
        )!
        client?.urlProtocol(
            self,
            didReceive: response,
            cacheStoragePolicy: .notAllowed
        )
        client?.urlProtocol(
            self,
            didLoad: Data(repeating: 65, count: 40_960)
        )
    }

    override func stopLoading() {
        Self.cancellationProbe.cancel()
    }
}

nonisolated private final class ThresholdOrderingURLProtocol: URLProtocol {
    static let cancellationProbe = ImmediateCancellationProbe()

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(
        for request: URLRequest
    ) -> URLRequest {
        request
    }

    override func startLoading() {
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "audio/mpeg"]
        )!
        client?.urlProtocol(
            self,
            didReceive: response,
            cacheStoragePolicy: .notAllowed
        )
        client?.urlProtocol(
            self,
            didLoad: Data(repeating: 9, count: 32_768)
        )
    }

    override func stopLoading() {
        Self.cancellationProbe.cancel()
    }
}
