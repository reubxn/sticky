//
//  ChatMarkdownRenderer.swift
//  leanring-buddy
//
//  Lightweight markdown renderer for chat bubbles. SwiftUI's built-in
//  `Text(AttributedString(markdown:))` handles inline formatting (bold,
//  italic, inline code, links) but ignores anything block-level —
//  fenced code blocks just collapse onto one line, lists lose their
//  bullets, headings vanish.
//
//  This renderer splits the message text into block-level chunks
//  (fenced code, ordered/unordered list, blockquote, heading,
//  paragraph) and renders each with the right SwiftUI view, then hands
//  inline formatting inside paragraphs/list items off to AttributedString.
//
//  Designed to work mid-stream: a half-written ``` block renders as a
//  code block as soon as the opening fence arrives, so the user sees
//  code formatting take effect as Claude types it.
//

import AppKit
import SwiftUI

// MARK: - Block model

/// One block-level element parsed out of a markdown string. Block-level
/// here is deliberately small — only the elements that need their own
/// SwiftUI view because inline AttributedString can't represent them.
enum ChatMarkdownBlock: Equatable {
    /// One paragraph of running text. Inline markdown inside (bold,
    /// italic, links, inline code) is handled by AttributedString.
    case paragraph(String)

    /// A fenced code block. `languageHint` may be empty if the user
    /// didn't write a language after the opening ```.
    case codeBlock(text: String, languageHint: String)

    /// A bulleted or numbered list. Each item is its own paragraph
    /// (inline markdown applies inside).
    case unorderedList(items: [String])
    case orderedList(items: [String])

    /// A blockquote. Treated as a single paragraph; inline markdown
    /// inside is honored.
    case blockquote(String)

    /// An ATX-style heading. `level` is 1–6; we visually clamp very
    /// small headings to a readable minimum.
    case heading(level: Int, text: String)
}

// MARK: - Parser

enum ChatMarkdownParser {
    /// Splits a markdown string into top-level blocks. Returns blocks in
    /// document order. Empty input → empty array.
    ///
    /// Streaming-safety: an unclosed ``` fence at the end of input is
    /// treated as an in-progress code block whose content is everything
    /// since the opening fence. This makes the assistant bubble render
    /// code formatting *as it arrives*, instead of waiting for the
    /// closing fence to land before switching from paragraph → code.
    static func parse(_ markdownText: String) -> [ChatMarkdownBlock] {
        guard !markdownText.isEmpty else { return [] }

        var parsedBlocks: [ChatMarkdownBlock] = []
        let normalizedLines = markdownText
            .replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n")

        var lineIndex = 0
        while lineIndex < normalizedLines.count {
            let currentLine = normalizedLines[lineIndex]
            let trimmedLine = currentLine.trimmingCharacters(in: .whitespaces)

            // --- Fenced code block ---
            if trimmedLine.hasPrefix("```") {
                let openingFenceLine = trimmedLine
                let languageHint = String(openingFenceLine.dropFirst(3))
                    .trimmingCharacters(in: .whitespaces)

                lineIndex += 1
                var collectedCodeLines: [String] = []
                var didFindClosingFence = false

                while lineIndex < normalizedLines.count {
                    let codeLine = normalizedLines[lineIndex]
                    if codeLine.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                        didFindClosingFence = true
                        lineIndex += 1
                        break
                    }
                    collectedCodeLines.append(codeLine)
                    lineIndex += 1
                }

                let codeBlockText = collectedCodeLines.joined(separator: "\n")
                parsedBlocks.append(
                    .codeBlock(text: codeBlockText, languageHint: languageHint)
                )

                // If we hit EOF without a closing fence, the streamed
                // response just hasn't finished yet — render what we
                // have. Don't downgrade to a paragraph.
                _ = didFindClosingFence
                continue
            }

            // --- Heading (ATX) ---
            if let headingMatch = parseATXHeading(trimmedLine) {
                parsedBlocks.append(
                    .heading(level: headingMatch.level, text: headingMatch.text)
                )
                lineIndex += 1
                continue
            }

            // --- Blank line — block separator ---
            if trimmedLine.isEmpty {
                lineIndex += 1
                continue
            }

            // --- Blockquote ---
            if trimmedLine.hasPrefix(">") {
                var quoteLines: [String] = []
                while lineIndex < normalizedLines.count {
                    let quoteCandidate = normalizedLines[lineIndex]
                        .trimmingCharacters(in: .whitespaces)
                    guard quoteCandidate.hasPrefix(">") else { break }
                    let strippedQuoteLine = String(quoteCandidate.dropFirst())
                        .trimmingCharacters(in: .whitespaces)
                    quoteLines.append(strippedQuoteLine)
                    lineIndex += 1
                }
                parsedBlocks.append(.blockquote(quoteLines.joined(separator: " ")))
                continue
            }

            // --- Unordered list ---
            if isUnorderedListMarker(trimmedLine) {
                var unorderedItems: [String] = []
                while lineIndex < normalizedLines.count {
                    let listCandidate = normalizedLines[lineIndex]
                        .trimmingCharacters(in: .whitespaces)
                    guard isUnorderedListMarker(listCandidate) else { break }
                    let itemText = stripUnorderedListMarker(listCandidate)
                    unorderedItems.append(itemText)
                    lineIndex += 1
                }
                parsedBlocks.append(.unorderedList(items: unorderedItems))
                continue
            }

            // --- Ordered list ---
            if isOrderedListMarker(trimmedLine) {
                var orderedItems: [String] = []
                while lineIndex < normalizedLines.count {
                    let listCandidate = normalizedLines[lineIndex]
                        .trimmingCharacters(in: .whitespaces)
                    guard isOrderedListMarker(listCandidate) else { break }
                    let itemText = stripOrderedListMarker(listCandidate)
                    orderedItems.append(itemText)
                    lineIndex += 1
                }
                parsedBlocks.append(.orderedList(items: orderedItems))
                continue
            }

            // --- Paragraph (consume contiguous non-blank lines) ---
            var paragraphLines: [String] = [currentLine]
            lineIndex += 1
            while lineIndex < normalizedLines.count {
                let nextLine = normalizedLines[lineIndex]
                let nextTrimmed = nextLine.trimmingCharacters(in: .whitespaces)
                // A paragraph ends at any block-starting cue.
                if nextTrimmed.isEmpty
                    || nextTrimmed.hasPrefix("```")
                    || nextTrimmed.hasPrefix(">")
                    || isUnorderedListMarker(nextTrimmed)
                    || isOrderedListMarker(nextTrimmed)
                    || parseATXHeading(nextTrimmed) != nil {
                    break
                }
                paragraphLines.append(nextLine)
                lineIndex += 1
            }
            parsedBlocks.append(
                .paragraph(paragraphLines.joined(separator: " "))
            )
        }

        return parsedBlocks
    }

    // MARK: - Pattern helpers

    private static func parseATXHeading(_ trimmedLine: String) -> (level: Int, text: String)? {
        guard trimmedLine.hasPrefix("#") else { return nil }
        var hashCount = 0
        for character in trimmedLine {
            if character == "#" { hashCount += 1 } else { break }
        }
        // ATX requires 1–6 hashes followed by a space.
        guard hashCount >= 1, hashCount <= 6 else { return nil }
        let afterHashes = trimmedLine.dropFirst(hashCount)
        guard afterHashes.first == " " else { return nil }
        let headingText = afterHashes
            .trimmingCharacters(in: .whitespaces)
        return (level: hashCount, text: headingText)
    }

    private static func isUnorderedListMarker(_ trimmedLine: String) -> Bool {
        guard !trimmedLine.isEmpty else { return false }
        let firstCharacter = trimmedLine.first!
        guard firstCharacter == "-" || firstCharacter == "*" || firstCharacter == "+" else {
            return false
        }
        // Marker must be followed by a space, otherwise this is just a
        // paragraph that happens to start with a dash (e.g. "-1°C").
        let afterMarker = trimmedLine.dropFirst()
        return afterMarker.first == " "
    }

    private static func stripUnorderedListMarker(_ trimmedLine: String) -> String {
        return String(trimmedLine.dropFirst())
            .trimmingCharacters(in: .whitespaces)
    }

    /// Matches "1. foo", "12) foo", etc. Returns true only if the prefix
    /// is digits followed by . or ) followed by a space.
    private static func isOrderedListMarker(_ trimmedLine: String) -> Bool {
        var digitCount = 0
        for character in trimmedLine {
            if character.isNumber {
                digitCount += 1
            } else {
                break
            }
        }
        guard digitCount > 0 else { return false }
        let afterDigits = trimmedLine.dropFirst(digitCount)
        guard let separatorCharacter = afterDigits.first,
              separatorCharacter == "." || separatorCharacter == ")" else {
            return false
        }
        let afterSeparator = afterDigits.dropFirst()
        return afterSeparator.first == " "
    }

    private static func stripOrderedListMarker(_ trimmedLine: String) -> String {
        var digitCount = 0
        for character in trimmedLine {
            if character.isNumber {
                digitCount += 1
            } else {
                break
            }
        }
        // Drop digits + "." or ")" + leading space
        return String(trimmedLine.dropFirst(digitCount + 1))
            .trimmingCharacters(in: .whitespaces)
    }
}

// MARK: - Renderer view

/// Renders a markdown string as a vertical stack of block views. Inline
/// formatting inside paragraphs / list items / blockquotes is delegated
/// to AttributedString so bold, italic, inline code, and links work
/// without us reimplementing inline parsing.
struct ChatMarkdownView: View {
    let markdownText: String
    /// Parsed once per text change. Cheap enough to do inline (the
    /// parser walks the string once), and SwiftUI re-renders this view
    /// on every streaming chunk anyway.
    private var parsedBlocks: [ChatMarkdownBlock] {
        ChatMarkdownParser.parse(markdownText)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(parsedBlocks.enumerated()), id: \.offset) { _, block in
                blockView(for: block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func blockView(for block: ChatMarkdownBlock) -> some View {
        switch block {
        case .paragraph(let paragraphText):
            inlineText(paragraphText)
                .font(.system(size: 13))
                .foregroundColor(.primary)
                .textSelection(.enabled)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)

        case .codeBlock(let codeText, let languageHint):
            ChatMarkdownCodeBlockView(
                codeText: codeText,
                languageHint: languageHint
            )

        case .unorderedList(let items):
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, itemText in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("•")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                            .frame(width: 10, alignment: .leading)
                        inlineText(itemText)
                            .font(.system(size: 13))
                            .foregroundColor(.primary)
                            .textSelection(.enabled)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

        case .orderedList(let items):
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(items.enumerated()), id: \.offset) { itemIndex, itemText in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("\(itemIndex + 1).")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                            .frame(minWidth: 16, alignment: .leading)
                        inlineText(itemText)
                            .font(.system(size: 13))
                            .foregroundColor(.primary)
                            .textSelection(.enabled)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

        case .blockquote(let quoteText):
            HStack(alignment: .top, spacing: 8) {
                Rectangle()
                    .fill(Color.secondary.opacity(0.4))
                    .frame(width: 2)
                inlineText(quoteText)
                    .font(.system(size: 13).italic())
                    .foregroundColor(.secondary)
                    .textSelection(.enabled)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }

        case .heading(let level, let headingText):
            inlineText(headingText)
                .font(.system(size: headingFontSize(forLevel: level), weight: .semibold))
                .foregroundColor(.primary)
                .textSelection(.enabled)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 2)
        }
    }

    /// Renders inline markdown by converting the source string into an
    /// AttributedString with `inlineOnlyPreservingWhitespace` so newlines
    /// don't get collapsed but block elements aren't re-parsed (we
    /// already handled them at the block level).
    /// Falls back to plain Text if conversion fails so a malformed
    /// inline span never blanks out a whole bubble.
    private func inlineText(_ rawText: String) -> Text {
        if let inlineAttributed = try? AttributedString(
            markdown: rawText,
            options: AttributedString.MarkdownParsingOptions(
                interpretedSyntax: .inlineOnlyPreservingWhitespace
            )
        ) {
            return Text(inlineAttributed)
        }
        return Text(rawText)
    }

    private func headingFontSize(forLevel level: Int) -> CGFloat {
        // Cap headings to a chat-bubble-friendly range. H1 in a small
        // bubble looks absurd if we use the full system heading sizes.
        switch level {
        case 1: return 17
        case 2: return 16
        case 3: return 15
        default: return 14
        }
    }
}

// MARK: - Code block view

/// Code block with monospaced font, neutral background, and a copy
/// button in the top-right corner. Wraps wide lines instead of
/// horizontally scrolling, since the chat bubble has a fixed max width.
struct ChatMarkdownCodeBlockView: View {
    let codeText: String
    let languageHint: String

    @State private var didJustCopy: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Always render the header strip so the copy button has a
            // stable home regardless of whether a language hint was
            // supplied.
            codeBlockHeader

            ScrollView(.horizontal, showsIndicators: false) {
                Text(codeText)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.primary)
                    .textSelection(.enabled)
                    .multilineTextAlignment(.leading)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(NSColor.textBackgroundColor).opacity(0.6))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.secondary.opacity(0.2), lineWidth: 0.5)
        )
    }

    private var codeBlockHeader: some View {
        HStack(spacing: 6) {
            if !languageHint.isEmpty {
                Text(languageHint.lowercased())
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button(action: copyCodeToClipboard) {
                HStack(spacing: 3) {
                    Image(systemName: didJustCopy ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 10, weight: .medium))
                    Text(didJustCopy ? "Copied" : "Copy")
                        .font(.system(size: 10, weight: .medium))
                }
                .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help("Copy this code block to the clipboard")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.secondary.opacity(0.06))
        .overlay(
            Rectangle()
                .fill(Color.secondary.opacity(0.15))
                .frame(height: 0.5),
            alignment: .bottom
        )
    }

    private func copyCodeToClipboard() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(codeText, forType: .string)
        didJustCopy = true
        // Reset the "Copied" affordance after a short delay so the user
        // can copy the same block again later if they want to.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            didJustCopy = false
        }
    }
}
