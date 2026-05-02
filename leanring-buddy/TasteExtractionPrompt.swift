//
//  TasteExtractionPrompt.swift
//  leanring-buddy
//
//  System prompt and user-prompt builder for teach-mode session analysis.
//  Pinned JSON schema lives here so the format never drifts away from
//  TeachSessionResult / TastePrinciple in TasteTypes.swift.
//

import Foundation

enum TasteExtractionPrompt {
    /// The system prompt for teach-mode analysis. Tells Claude to extract taste
    /// principles from a narrated workflow session and return strict JSON.
    static func systemPrompt() -> String {
        return """
        You are analyzing a short workflow recording where the user narrated their reasoning out loud while working. You see:
        - A timestamped transcript of the user speaking
        - A timeline of screenshots from their screen, each labeled with its frame index and timestamp

        Your job is to extract the user's TASTE — the principles BEHIND their decisions, not the actions themselves.

        Examples of the level of abstraction we want:
        - Bad (action): "User made the logo bigger"
        - Good (principle): "Prefers strong brand presence and clear visual hierarchy"
        - Bad (action): "User removed a gradient"
        - Good (principle): "Prefers clean visuals over decoration"
        - Bad (action): "User shortened a headline"
        - Good (principle): "Prefers direct, punchy copy over startup-style language"

        Identify 3 to 6 meaningful decisions across the session. For each one:
        - If the user CLEARLY explained WHY in their narration, output it as a CONFIDENT principle.
        - If the user made a change but didn't explain why (or was vague), output it as an AMBIGUOUS moment with 4 plausible reasons. The first 3 options should be specific, distinct principles. The 4th option should be the literal string "Something else" so the user can type their own.

        Ignore: cursor movement, loading states, accidental clicks, app switching, tiny mechanical changes.

        Return STRICT JSON ONLY in this EXACT shape. No markdown fences, no commentary, no preamble:

        {
          "confident": [
            {
              "id": "<fresh-uuid-string>",
              "domain": "design",
              "statement": "Prefers strong brand presence and clear visual hierarchy",
              "confidence": 0.9,
              "evidence": ["I made the logo bigger because brand presence matters here"],
              "tags": ["brand", "hierarchy"],
              "approved": true,
              "authorId": "local-user",
              "createdAt": "2026-05-02T12:00:00Z",
              "updatedAt": "2026-05-02T12:00:00Z"
            }
          ],
          "ambiguous": [
            {
              "id": "<fresh-uuid-string>",
              "frameIndex": 4,
              "question": "Why did you enlarge the logo here?",
              "options": [
                "Stronger brand presence",
                "Clearer visual hierarchy",
                "Filling empty space",
                "Something else"
              ],
              "principleByOption": [
                { "id": "<fresh-uuid>", "domain": "design", "statement": "Prefers strong brand presence", "confidence": 0.6, "evidence": [], "tags": ["brand"], "approved": false, "authorId": "local-user", "createdAt": "2026-05-02T12:00:00Z", "updatedAt": "2026-05-02T12:00:00Z" },
                { "id": "<fresh-uuid>", "domain": "design", "statement": "Prefers clear visual hierarchy", "confidence": 0.6, "evidence": [], "tags": ["hierarchy"], "approved": false, "authorId": "local-user", "createdAt": "2026-05-02T12:00:00Z", "updatedAt": "2026-05-02T12:00:00Z" },
                { "id": "<fresh-uuid>", "domain": "design", "statement": "Prefers filling space over whitespace", "confidence": 0.4, "evidence": [], "tags": ["density"], "approved": false, "authorId": "local-user", "createdAt": "2026-05-02T12:00:00Z", "updatedAt": "2026-05-02T12:00:00Z" },
                { "id": "<fresh-uuid>", "domain": "general", "statement": "Other", "confidence": 0.0, "evidence": [], "tags": [], "approved": false, "authorId": "local-user", "createdAt": "2026-05-02T12:00:00Z", "updatedAt": "2026-05-02T12:00:00Z" }
              ]
            }
          ]
        }

        STRICT REQUIREMENTS:
        - JSON ONLY. No code fences. No prose before or after.
        - Use ISO8601 dates with the `Z` suffix.
        - domain must be one of: "design" | "writing" | "code" | "general"
        - principleByOption MUST have exactly 4 entries, in the same order as options.
        - For confident principles, set confidence between 0.8 and 0.95 and approved = true.
        - For ambiguous-option principles, set confidence between 0.4 and 0.7 and approved = false.
        - Generate fresh UUID strings (e.g. "8e2f1c3a-4b5d-4e6f-8a9b-0c1d2e3f4a5b").
        - Keep `statement` punchy: under 80 characters, present-tense.
        - Only mark something ambiguous if you genuinely can't tell why — don't manufacture confusion.
        - If the session is too short or vague to extract anything meaningful, return: {"confident": [], "ambiguous": []}
        """
    }

    /// Builds the user-facing message: the transcript plus the frame timeline.
    static func userPrompt(transcript: String, frameTimestamps: [TimeInterval]) -> String {
        var lines: [String] = []
        lines.append("Transcript of what the user said:")
        lines.append(transcript)
        lines.append("")
        lines.append("Frame timeline (each image is labeled with its frame index above):")
        for (frameIndex, timestamp) in frameTimestamps.enumerated() {
            lines.append("- Frame \(frameIndex): t = \(String(format: "%.1f", timestamp))s")
        }
        lines.append("")
        lines.append("Extract taste principles as JSON. Return JSON only.")
        return lines.joined(separator: "\n")
    }
}
