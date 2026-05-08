//
//  PersonaTasteFileStore.swift
//  leanring-buddy
//
//  Reads and writes per-teammate TASTE.md files. These are the
//  canonical source of truth for each persona's identity, soul prose,
//  and taste principles — same file the team commits to git, the same
//  file Claude Code or any other agent can read directly. Persona
//  bundles are no longer Swift literals; they're parsed from these
//  markdown files at load time.
//
//  Each teammate has one file at:
//
//      leanring-buddy/personas/<id>/TASTE.md            (bundled with app)
//      ~/Library/Application Support/com.learning-buddy.clicky/
//          personas/<id>/TASTE.md                       (hot-swap override)
//
//  The bundled copy is the demo default; the hot-swap copy lets a user
//  edit a teammate's taste without rebuilding the app and is also where
//  teach-mode appends new principles for the local owner (Phase 2 — the
//  writer here is wired but not yet called from the teach pipeline).
//
//  =============================================================
//  TASTE.md format
//  =============================================================
//
//      # {DisplayName} — {Role}
//
//      <!-- @persona id={id} voice={elevenLabsVoiceId} accent={hex} avatar={filename} -->
//
//      ## Soul
//
//      {free-form personality prose, any length, any number of paragraphs}
//
//      ## Taste
//
//      ### {Domain}
//
//      - **{statement, ends with a period}**
//        *(confidence 0.XX · tag1, tag2)*
//        {evidence prose, single line or wrapped}
//
//      - **{another statement}**
//        *(confidence ...)*
//        ...
//
//      ### {Another Domain}
//
//      ...
//
//  Domains are case-insensitive; valid values map onto `TasteDomain`
//  (general / design / writing / code). Unknown domains fall back to
//  `.general` with a console warning.
//
//  Principle ids are derived from a slug of the statement (first ~6
//  meaningful words, lowercase, hyphenated). Editing a statement
//  changes its id — that's intentional; if the wording moved enough
//  to alter the slug, it's effectively a new principle.
//
//  =============================================================
//

import Foundation

enum PersonaTasteFileStoreError: Error, LocalizedError {
    case fileMissing(personaId: String)
    case readFailed(personaId: String, underlying: Error)
    case writeFailed(personaId: String, underlying: Error)
    case missingHeader(personaId: String)
    case missingMetadata(personaId: String)

    var errorDescription: String? {
        switch self {
        case .fileMissing(let id):
            return "TASTE.md missing for persona '\(id)'."
        case .readFailed(let id, let underlying):
            return "Couldn't read TASTE.md for '\(id)': \(underlying.localizedDescription)"
        case .writeFailed(let id, let underlying):
            return "Couldn't write TASTE.md for '\(id)': \(underlying.localizedDescription)"
        case .missingHeader(let id):
            return "TASTE.md for '\(id)' is missing the '# Name — Role' H1 line."
        case .missingMetadata(let id):
            return "TASTE.md for '\(id)' is missing the '<!-- @persona ... -->' metadata line."
        }
    }
}

enum PersonaTasteFileStore {
    /// Subdirectory inside the app bundle / Application Support where
    /// per-teammate folders live. Each teammate gets its own folder
    /// containing TASTE.md plus (optionally) an avatar image.
    private static let personasDirectoryName = "personas"
    private static let tasteFileName = "TASTE.md"
    private static let applicationSupportSubdirectoryName = "com.learning-buddy.clicky"

    // MARK: - Public read API

    /// Loads a single persona bundle by id. Tries the hot-swap path
    /// (Application Support) first so user-edited files override the
    /// bundled defaults, then falls back to the bundled copy. Throws
    /// `.fileMissing` when neither location has the file.
    static func loadBundle(forId personaId: String) throws -> PersonaBundle {
        let resolvedFileURL = try resolveTasteFileURL(forId: personaId)

        let fileContents: String
        do {
            fileContents = try String(contentsOf: resolvedFileURL, encoding: .utf8)
        } catch {
            throw PersonaTasteFileStoreError.readFailed(personaId: personaId, underlying: error)
        }

        return try parseTasteMarkdown(fileContents, personaId: personaId)
    }

    /// Loads every persona bundle whose folder + TASTE.md is present.
    /// Pulls the directory listing from the bundle first, then unions in
    /// any extra ids found in Application Support (for user-added
    /// teammates that aren't shipped with the binary).
    static func loadAllAvailableBundles() -> [PersonaBundle] {
        let bundleIds = personaIdsInBundle()
        let hotSwapIds = personaIdsInApplicationSupport()
        let allKnownIds = orderedUnion(primary: bundleIds, secondary: hotSwapIds)

        return allKnownIds.compactMap { personaId in
            do {
                return try loadBundle(forId: personaId)
            } catch {
                print("⚠️ PersonaTasteFileStore: failed to load '\(personaId)': \(error)")
                return nil
            }
        }
    }

    // MARK: - Public write API (used by teach mode in Phase 2)

    /// Appends a single principle to the persona's TASTE.md, writing
    /// always to the Application Support copy (so the bundled default
    /// stays clean and the user's edits persist across reinstalls). If
    /// the principle's domain section already exists in the file, the
    /// new bullet is added at the bottom of that section; otherwise a
    /// new domain section is appended just before EOF.
    ///
    /// Throws on filesystem errors; logs and returns false if the
    /// persona has no existing TASTE.md to extend (we don't auto-create
    /// a brand new file from a single bullet — too lossy on metadata).
    @discardableResult
    static func appendPrinciple(
        _ newPrinciple: TastePrinciple,
        toPersonaId personaId: String
    ) throws -> Bool {
        // Load the existing file (prefers hot-swap, falls back to
        // bundle) so we can re-render a complete document. We always
        // *write* to Application Support — the bundled copy is read-
        // only at runtime anyway.
        let existingFileURL = try resolveTasteFileURL(forId: personaId)
        let existingContents: String
        do {
            existingContents = try String(contentsOf: existingFileURL, encoding: .utf8)
        } catch {
            throw PersonaTasteFileStoreError.readFailed(personaId: personaId, underlying: error)
        }

        let updatedContents = appendPrincipleToMarkdown(
            existingContents,
            newPrinciple: newPrinciple
        )

        let writeURL = try applicationSupportTasteFileURL(forId: personaId)
        try ensureParentDirectoryExists(for: writeURL)
        do {
            try updatedContents.write(to: writeURL, atomically: true, encoding: .utf8)
        } catch {
            throw PersonaTasteFileStoreError.writeFailed(personaId: personaId, underlying: error)
        }

        return true
    }

    // MARK: - File location resolution

    /// Returns the URL of the TASTE.md the loader should read for the
    /// given persona id. Hot-swap path wins; bundled path is the
    /// fallback.
    private static func resolveTasteFileURL(forId personaId: String) throws -> URL {
        if let hotSwapURL = applicationSupportTasteFileURLIfExists(forId: personaId) {
            return hotSwapURL
        }
        if let bundledURL = bundledTasteFileURL(forId: personaId) {
            return bundledURL
        }
        throw PersonaTasteFileStoreError.fileMissing(personaId: personaId)
    }

    /// Bundled TASTE.md URL for a persona, or nil if the app wasn't
    /// built with that persona. Resolved via Bundle.main resource
    /// lookup, which the synchronized folder reference picks up
    /// automatically.
    private static func bundledTasteFileURL(forId personaId: String) -> URL? {
        // The directory structure inside the bundle Resources mirrors
        // the source layout: Resources/personas/<id>/TASTE.md
        let subdirectoryPath = "\(personasDirectoryName)/\(personaId)"
        return Bundle.main.url(
            forResource: "TASTE",
            withExtension: "md",
            subdirectory: subdirectoryPath
        )
    }

    /// Application Support TASTE.md URL — created on demand. Returns
    /// the URL whether the file exists or not so write paths can use
    /// it directly.
    private static func applicationSupportTasteFileURL(forId personaId: String) throws -> URL {
        guard let applicationSupportDirectoryURL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            throw PersonaTasteFileStoreError.writeFailed(
                personaId: personaId,
                underlying: NSError(domain: "PersonaTasteFileStore", code: -1, userInfo: [NSLocalizedDescriptionKey: "Application Support directory unavailable"])
            )
        }

        return applicationSupportDirectoryURL
            .appendingPathComponent(applicationSupportSubdirectoryName, isDirectory: true)
            .appendingPathComponent(personasDirectoryName, isDirectory: true)
            .appendingPathComponent(personaId, isDirectory: true)
            .appendingPathComponent(tasteFileName, isDirectory: false)
    }

    /// Convenience — returns the hot-swap URL only if the file actually
    /// exists. Used by the read path so we can fall through to the
    /// bundled copy without throwing.
    private static func applicationSupportTasteFileURLIfExists(forId personaId: String) -> URL? {
        guard let url = try? applicationSupportTasteFileURL(forId: personaId),
              FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }
        return url
    }

    /// Returns the persona ids the bundled copy of the app ships with,
    /// by listing the bundle's `personas/` resource directory. Empty
    /// list when the bundle has no personas folder.
    private static func personaIdsInBundle() -> [String] {
        guard let resourceURL = Bundle.main.resourceURL else { return [] }
        let personasURL = resourceURL.appendingPathComponent(personasDirectoryName, isDirectory: true)
        return listSubdirectoryNames(at: personasURL)
    }

    /// Returns the persona ids found in Application Support (i.e. ones
    /// the user has installed locally without the app shipping them).
    private static func personaIdsInApplicationSupport() -> [String] {
        guard let applicationSupportDirectoryURL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            return []
        }
        let personasURL = applicationSupportDirectoryURL
            .appendingPathComponent(applicationSupportSubdirectoryName, isDirectory: true)
            .appendingPathComponent(personasDirectoryName, isDirectory: true)
        return listSubdirectoryNames(at: personasURL)
    }

    /// Generic subdirectory enumerator — returns the names of immediate
    /// child directories at the given URL, or [] if the URL doesn't
    /// exist or isn't a directory.
    private static func listSubdirectoryNames(at directoryURL: URL) -> [String] {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        return entries.compactMap { entry in
            let resourceValues = try? entry.resourceValues(forKeys: [.isDirectoryKey])
            return (resourceValues?.isDirectory == true) ? entry.lastPathComponent : nil
        }
    }

    /// Stable union — ids in `primary` appear first in their original
    /// order, then any ids in `secondary` not already present.
    private static func orderedUnion(primary: [String], secondary: [String]) -> [String] {
        var seen = Set<String>()
        var union: [String] = []
        for id in primary where !seen.contains(id) {
            seen.insert(id)
            union.append(id)
        }
        for id in secondary where !seen.contains(id) {
            seen.insert(id)
            union.append(id)
        }
        return union
    }

    /// Creates the parent directory of the given file URL if it
    /// doesn't yet exist. Used by the write path so the first time a
    /// persona's TASTE.md is written to Application Support, the
    /// `personas/<id>/` chain gets built.
    private static func ensureParentDirectoryExists(for fileURL: URL) throws {
        let parentDirectoryURL = fileURL.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: parentDirectoryURL.path) {
            try FileManager.default.createDirectory(
                at: parentDirectoryURL,
                withIntermediateDirectories: true,
                attributes: nil
            )
        }
    }

    // MARK: - Markdown parsing

    /// Parses a TASTE.md document into a PersonaBundle. Defensive — bad
    /// principle entries are skipped with a console warning rather than
    /// failing the whole file, since a malformed bullet shouldn't
    /// prevent the rest of a teammate's taste from loading.
    private static func parseTasteMarkdown(_ markdown: String, personaId: String) throws -> PersonaBundle {
        let allLines = markdown.components(separatedBy: .newlines)

        // ---- Header (display name + role) ---------------------------------
        guard let headerLine = allLines.first(where: { $0.hasPrefix("# ") && !$0.hasPrefix("## ") }) else {
            throw PersonaTasteFileStoreError.missingHeader(personaId: personaId)
        }
        let (displayName, role) = parseDisplayNameAndRole(fromH1: headerLine)

        // ---- Metadata comment line ----------------------------------------
        guard let metadataLine = allLines.first(where: { $0.contains("@persona") && $0.contains("<!--") }) else {
            throw PersonaTasteFileStoreError.missingMetadata(personaId: personaId)
        }
        let metadata = parseMetadataAttributes(fromCommentLine: metadataLine)
        let voiceId = metadata["voice"] ?? ""
        let accentHex = metadata["accent"] ?? "#1F6FEB"
        let avatarFilename = metadata["avatar"]
        // If the TASTE.md names an avatar file but that file isn't actually
        // present (bundled photos were intentionally excluded from this repo),
        // fall back to initials over the accent color so the picker stays
        // legible instead of showing an empty pale circle.
        let resolvedAvatar: PersonaAvatar = {
            if let filename = avatarFilename,
               PersonaImageLoader.bundledOrDiskImage(forFilename: filename) != nil {
                return .imageFile(filename: filename)
            }
            return .initials(text: Self.initialsForFallback(displayName: displayName), hexColor: accentHex)
        }()

        // ---- Soul section (free prose between '## Soul' and next H2) ------
        let soulProse = extractH2Section(named: "Soul", from: allLines)

        // ---- Taste section: principles grouped by H3 domain ---------------
        let tasteSectionLines = extractH2SectionLines(named: "Taste", from: allLines)
        let principles = parsePrinciples(fromTasteSectionLines: tasteSectionLines, authorId: personaId)

        return PersonaBundle(
            id: personaId,
            displayName: displayName,
            role: role,
            avatar: resolvedAvatar,
            accentColorHex: accentHex,
            soul: soulProse,
            voiceId: voiceId,
            taste: TasteProfile(
                userId: personaId,
                principles: principles,
                updatedAt: Date()
            )
        )
    }

    /// Splits "# Magdalena — Co-Founder · Middle Bridge" into
    /// ("Magdalena", "Co-Founder · Middle Bridge"). Tolerates both em-
    /// dash (—) and en-dash (–) and a plain hyphen as separators since
    /// the file is hand-edited and the user might type any of them.
    /// Picks 1–2 letters to render inside the circular avatar when no
    /// real photo is available. Uses the first letter of the first two
    /// whitespace-separated tokens in the display name (so "Magdalena
    /// Brzezińska" → "MB"); falls back to the first character alone for
    /// single-word names, and a neutral "?" for empty input.
    private static func initialsForFallback(displayName: String) -> String {
        let tokens = displayName
            .split(whereSeparator: { $0.isWhitespace })
            .map { String($0) }
        let firstLetters = tokens.prefix(2).compactMap { $0.first.map { String($0) } }
        let combined = firstLetters.joined().uppercased()
        return combined.isEmpty ? "?" : combined
    }

    private static func parseDisplayNameAndRole(fromH1 line: String) -> (displayName: String, role: String?) {
        let withoutHashes = line
            .replacingOccurrences(of: "# ", with: "")
            .trimmingCharacters(in: .whitespaces)

        let possibleSeparators: [String] = [" — ", " – ", " - "]
        for separator in possibleSeparators {
            if let separatorRange = withoutHashes.range(of: separator) {
                let displayName = String(withoutHashes[..<separatorRange.lowerBound]).trimmingCharacters(in: .whitespaces)
                let role = String(withoutHashes[separatorRange.upperBound...]).trimmingCharacters(in: .whitespaces)
                return (displayName, role.isEmpty ? nil : role)
            }
        }
        return (withoutHashes, nil)
    }

    /// Parses `<!-- @persona id=foo voice=bar accent=#hex avatar=baz -->`
    /// into a string→string map. Tolerates trailing spaces and the
    /// closing `-->` token. Quoted values are not supported (unnecessary
    /// for current attributes).
    private static func parseMetadataAttributes(fromCommentLine line: String) -> [String: String] {
        // Trim the comment markers and the @persona tag so we're left
        // with a flat "k1=v1 k2=v2 ..." string.
        var inner = line
        for token in ["<!--", "-->", "@persona"] {
            inner = inner.replacingOccurrences(of: token, with: "")
        }
        inner = inner.trimmingCharacters(in: .whitespaces)

        var attributes: [String: String] = [:]
        for token in inner.split(separator: " ") {
            let parts = token.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else { continue }
            let key = String(parts[0]).trimmingCharacters(in: .whitespaces)
            let value = String(parts[1]).trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty else { continue }
            attributes[key] = value
        }
        return attributes
    }

    /// Returns all lines belonging to the named H2 section (between
    /// `## Soul` and the next `## ` line, exclusive). Soul sections are
    /// returned as a single trimmed prose block; that's what callers
    /// want for both injection into Claude prompts and Soul rendering.
    private static func extractH2Section(named sectionName: String, from allLines: [String]) -> String {
        let sectionLines = extractH2SectionLines(named: sectionName, from: allLines)
        return sectionLines
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Same but returns the raw lines (used for the Taste section where
    /// we need to walk H3 sub-headers).
    private static func extractH2SectionLines(named sectionName: String, from allLines: [String]) -> [String] {
        let sectionHeader = "## \(sectionName)"
        guard let startIndex = allLines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == sectionHeader }) else {
            return []
        }
        var collected: [String] = []
        for line in allLines[(startIndex + 1)...] {
            if line.hasPrefix("## ") && !line.hasPrefix("### ") {
                break
            }
            collected.append(line)
        }
        return collected
    }

    /// Walks the Taste section lines and emits a TastePrinciple for
    /// every well-formed bullet entry. Bullets must follow the
    /// three-line shape:
    ///
    ///     - **{statement}**
    ///       *(confidence 0.XX · tag1, tag2)*
    ///       {evidence prose}
    ///
    /// Evidence may span multiple wrapped lines until the next blank
    /// line / next bullet / next H3 header.
    private static func parsePrinciples(fromTasteSectionLines tasteLines: [String], authorId: String) -> [TastePrinciple] {
        var principles: [TastePrinciple] = []
        var currentDomain: TasteDomain = .general
        var lineIndex = 0

        while lineIndex < tasteLines.count {
            let rawLine = tasteLines[lineIndex]
            let trimmedLine = rawLine.trimmingCharacters(in: .whitespaces)

            // Domain header (### General / ### Design / etc)
            if trimmedLine.hasPrefix("### ") {
                let domainLabel = String(trimmedLine.dropFirst(4)).trimmingCharacters(in: .whitespaces)
                currentDomain = mapDomainLabelToTasteDomain(domainLabel)
                lineIndex += 1
                continue
            }

            // Bullet start: '- **statement**'
            if trimmedLine.hasPrefix("- **") && trimmedLine.contains("**") {
                if let parsed = consumePrincipleBlock(
                    startingAt: lineIndex,
                    in: tasteLines,
                    domain: currentDomain,
                    authorId: authorId
                ) {
                    principles.append(parsed.principle)
                    lineIndex = parsed.consumedThroughLineIndex + 1
                    continue
                }
            }

            lineIndex += 1
        }

        return principles
    }

    /// Parses one bullet entry starting at `startLineIndex`. Returns
    /// nil if the bullet is malformed (in which case the caller skips
    /// it and continues). On success, returns the principle plus the
    /// final line index that was consumed (so the caller can advance).
    private static func consumePrincipleBlock(
        startingAt startLineIndex: Int,
        in lines: [String],
        domain: TasteDomain,
        authorId: String
    ) -> (principle: TastePrinciple, consumedThroughLineIndex: Int)? {
        let firstLine = lines[startLineIndex].trimmingCharacters(in: .whitespaces)
        guard let statement = extractBoldSegment(from: firstLine) else { return nil }

        var confidenceValue: Double = 0.5
        var tagList: [String] = []
        var evidenceLines: [String] = []
        var lastConsumedLineIndex = startLineIndex

        var lookaheadIndex = startLineIndex + 1
        while lookaheadIndex < lines.count {
            let lookaheadLine = lines[lookaheadIndex].trimmingCharacters(in: .whitespaces)

            // Stop conditions: next bullet, next H3, next H2, blank line
            // followed by a structural marker.
            if lookaheadLine.hasPrefix("- **") || lookaheadLine.hasPrefix("### ") || lookaheadLine.hasPrefix("## ") {
                break
            }

            // Confidence + tags line
            if lookaheadLine.hasPrefix("*(") && lookaheadLine.hasSuffix(")*") {
                let inner = String(lookaheadLine.dropFirst(2).dropLast(2))
                let (parsedConfidence, parsedTags) = parseConfidenceAndTags(fromInnerString: inner)
                confidenceValue = parsedConfidence ?? confidenceValue
                tagList = parsedTags
                lastConsumedLineIndex = lookaheadIndex
                lookaheadIndex += 1
                continue
            }

            // Empty line just before next entry — accept as a soft stop
            if lookaheadLine.isEmpty && !evidenceLines.isEmpty {
                break
            }

            // Otherwise treat as evidence prose
            if !lookaheadLine.isEmpty {
                evidenceLines.append(lookaheadLine)
                lastConsumedLineIndex = lookaheadIndex
            }
            lookaheadIndex += 1
        }

        let principleId = slugIdentifier(forStatement: statement, authorId: authorId)
        let evidence = evidenceLines.joined(separator: " ")
        let principle = TastePrinciple(
            id: principleId,
            domain: domain,
            statement: statement,
            confidence: confidenceValue,
            evidence: evidence.isEmpty ? [] : [evidence],
            tags: tagList,
            approved: true,
            authorId: authorId,
            createdAt: Date(),
            updatedAt: Date()
        )

        return (principle, lastConsumedLineIndex)
    }

    /// Extracts the bold segment from a line like '- **Some statement.**
    /// Other prose'. Returns nil if there's no closing '**'.
    private static func extractBoldSegment(from line: String) -> String? {
        guard let openRange = line.range(of: "**") else { return nil }
        let afterOpen = line[openRange.upperBound...]
        guard let closeRange = afterOpen.range(of: "**") else { return nil }
        return String(afterOpen[..<closeRange.lowerBound]).trimmingCharacters(in: .whitespaces)
    }

    /// Parses the inner of `(confidence 0.92 · mvp, iteration)` into
    /// (0.92, ["mvp", "iteration"]). Tolerates either '·' or '-' as
    /// the separator and missing components.
    private static func parseConfidenceAndTags(fromInnerString inner: String) -> (Double?, [String]) {
        let separators: [String] = [" · ", " — ", " - "]
        var confidencePart = inner
        var tagsPart: String? = nil

        for separator in separators {
            if let range = inner.range(of: separator) {
                confidencePart = String(inner[..<range.lowerBound])
                tagsPart = String(inner[range.upperBound...])
                break
            }
        }

        let confidenceValue: Double? = {
            // Strip "confidence" prefix if present, then parse the
            // remaining numeric token.
            let normalized = confidencePart
                .replacingOccurrences(of: "confidence", with: "")
                .trimmingCharacters(in: .whitespaces)
            return Double(normalized)
        }()

        let tagList: [String] = (tagsPart ?? "")
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        return (confidenceValue, tagList)
    }

    /// Maps the domain label as written in the file ("General",
    /// "Design", etc.) to the existing `TasteDomain` enum. Falls back
    /// to `.general` with a warning so a typo in the file doesn't
    /// silently lose principles.
    private static func mapDomainLabelToTasteDomain(_ label: String) -> TasteDomain {
        switch label.lowercased() {
        case "design": return .design
        case "writing", "copy": return .writing
        case "code", "engineering": return .code
        case "general": return .general
        default:
            print("⚠️ PersonaTasteFileStore: unknown domain label '\(label)', defaulting to .general")
            return .general
        }
    }

    /// Slug-derived stable id for a principle, prefixed with the
    /// author so collisions across teammates can't happen. Takes the
    /// first 6 meaningful words of the statement, lowercases, joins
    /// with hyphens. "Ship the smallest thing that proves the idea"
    /// → "reuban-ship-the-smallest-thing-that-proves".
    private static func slugIdentifier(forStatement statement: String, authorId: String) -> String {
        let allowedCharacters = CharacterSet.lowercaseLetters.union(.decimalDigits)
        let words = statement
            .lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .map { word -> String in
                let scalars = word.unicodeScalars.filter { allowedCharacters.contains($0) }
                return String(String.UnicodeScalarView(scalars))
            }
            .filter { !$0.isEmpty }
        let firstWords = words.prefix(6)
        let slugBody = firstWords.joined(separator: "-")
        return "\(authorId)-\(slugBody)"
    }

    // MARK: - Markdown rendering (writer)

    /// Re-renders the markdown after appending a single principle. The
    /// strategy: find the matching H3 domain block; if it exists, walk
    /// to the end of its bullet list and insert the new bullet
    /// immediately before the next structural marker. If it doesn't,
    /// append a brand-new H3 block at the end of the file.
    private static func appendPrincipleToMarkdown(
        _ existingMarkdown: String,
        newPrinciple: TastePrinciple
    ) -> String {
        let domainLabel = displayLabelForDomain(newPrinciple.domain)
        let bullet = renderPrincipleBullet(newPrinciple)

        var lines = existingMarkdown.components(separatedBy: "\n")
        let domainHeaderLine = "### \(domainLabel)"

        if let domainHeaderIndex = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == domainHeaderLine }) {
            // Walk forward to find the right insertion point: just
            // before the next H3 / H2 / EOF.
            var insertionIndex = lines.count
            for searchIndex in (domainHeaderIndex + 1)..<lines.count {
                let line = lines[searchIndex]
                if line.hasPrefix("## ") || line.hasPrefix("### ") {
                    insertionIndex = searchIndex
                    break
                }
            }
            // Trim trailing blank lines inside the section before
            // inserting so the bullet sits flush with the previous one.
            while insertionIndex > domainHeaderIndex + 1
                && lines[insertionIndex - 1].trimmingCharacters(in: .whitespaces).isEmpty {
                insertionIndex -= 1
            }
            lines.insert(contentsOf: ["", bullet], at: insertionIndex)
        } else {
            // No matching domain section — append a new H3 block at EOF.
            // Make sure we don't double up on trailing newlines.
            while !lines.isEmpty && lines.last!.trimmingCharacters(in: .whitespaces).isEmpty {
                lines.removeLast()
            }
            lines.append(contentsOf: ["", "### \(domainLabel)", "", bullet, ""])
        }

        return lines.joined(separator: "\n")
    }

    /// Inverse of `mapDomainLabelToTasteDomain` — display-cased label
    /// the writer uses when emitting H3 headers.
    private static func displayLabelForDomain(_ domain: TasteDomain) -> String {
        switch domain {
        case .general: return "General"
        case .design: return "Design"
        case .writing: return "Writing"
        case .code: return "Code"
        }
    }

    /// Renders one principle as the three-line bullet shape the parser
    /// expects. Confidence is formatted to two decimals; tags are joined
    /// with ", "; evidence is whichever value is in the first slot
    /// (multiple evidence entries are collapsed to one paragraph for
    /// the markdown — they were a single freeform field anyway).
    private static func renderPrincipleBullet(_ principle: TastePrinciple) -> String {
        let confidenceFormatted = String(format: "%.2f", principle.confidence)
        let tagsJoined = principle.tags.isEmpty ? "—" : principle.tags.joined(separator: ", ")
        let evidenceProse = principle.evidence.first ?? ""

        var bulletLines: [String] = []
        bulletLines.append("- **\(principle.statement)**")
        bulletLines.append("  *(confidence \(confidenceFormatted) · \(tagsJoined))*")
        if !evidenceProse.isEmpty {
            bulletLines.append("  \(evidenceProse)")
        }
        return bulletLines.joined(separator: "\n")
    }
}
