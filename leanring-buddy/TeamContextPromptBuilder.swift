//
//  TeamContextPromptBuilder.swift
//  leanring-buddy
//
//  Turns a TeamContextProfile (the brief + attached files) into a short
//  prose block that gets prepended to the system prompt whenever the
//  active persona should "know" the team's context — i.e. team scope on
//  the local user, and any teammate persona (so e.g. Leonard the CEO
//  speaks with awareness of the team brief and dropped files).
//
//  Default behavior is "brief overview only": every file shows up as a
//  filename + the user-supplied one-line summary. For small text files
//  the body is inlined too so the model has something concrete to read
//  without us implementing a tool-use round trip. Once the cumulative
//  inlined body crosses `TeamContextStore.maxTotalInlinedBytes`, the
//  remaining files only show by filename + summary.
//

import Foundation

enum TeamContextPromptBuilder {
    /// Returns the prompt block, or an empty string when there's nothing
    /// to inject (no brief and no files). Caller can prepend the result
    /// directly to whatever system prompt they're building — empty string
    /// no-ops cleanly.
    static func teamContextBlock(profile: TeamContextProfile) -> String {
        let trimmedBrief = profile.brief.trimmingCharacters(in: .whitespacesAndNewlines)
        let attachedFiles = profile.attachedFiles

        if trimmedBrief.isEmpty && attachedFiles.isEmpty {
            return ""
        }

        var promptLines: [String] = []
        promptLines.append("team context — what the team is working on and shared material every persona should be aware of:")
        promptLines.append("")

        if !trimmedBrief.isEmpty {
            promptLines.append("brief:")
            promptLines.append(trimmedBrief)
            promptLines.append("")
        }

        if !attachedFiles.isEmpty {
            promptLines.append("shared files (you have a brief overview by default — only quote a file's contents when it's directly relevant to the question):")

            var totalInlinedBytesUsed: Int = 0
            for attachedFile in attachedFiles {
                let summaryText = attachedFile.summary
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let summaryDisplay = summaryText.isEmpty ? "[no summary]" : summaryText
                promptLines.append("- \(attachedFile.filename) — \(summaryDisplay)")

                // Only attempt to inline small text files, and only until
                // we hit the per-prompt budget. Everything past that is
                // still "available" to the model in the sense that it
                // knows the file exists by name and summary.
                if totalInlinedBytesUsed >= TeamContextStore.maxTotalInlinedBytes {
                    continue
                }
                guard attachedFile.isPlainText else { continue }
                guard let inlinedFileBody = TeamContextStore
                    .readInlinedTextBody(forAttachedFile: attachedFile) else {
                    continue
                }

                let bytesAddedByThisFile = inlinedFileBody.utf8.count
                let bytesRemainingInBudget = TeamContextStore.maxTotalInlinedBytes - totalInlinedBytesUsed
                if bytesAddedByThisFile > bytesRemainingInBudget {
                    // Not enough room for the whole (already-truncated)
                    // body — skip rather than mid-line clip again.
                    continue
                }
                promptLines.append("  --- begin \(attachedFile.filename) ---")
                promptLines.append(inlinedFileBody)
                promptLines.append("  --- end \(attachedFile.filename) ---")
                totalInlinedBytesUsed += bytesAddedByThisFile
            }
            promptLines.append("")
        }

        promptLines.append("treat this as background — don't recite it back at the user, just let it shape what you say. if a file is listed but its contents weren't shown above, you know the file exists and have the summary; if the user asks about it, say what's in your overview and offer to look at it more closely.")

        return promptLines.joined(separator: "\n")
    }
}
