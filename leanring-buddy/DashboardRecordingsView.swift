//
//  DashboardRecordingsView.swift
//  leanring-buddy
//
//  "Recordings" tab — every teach-mode press the user has made,
//  newest first, showing the spoken transcript and (when one was
//  extracted) the principle that came out the other side. Read from
//  DashboardRecordingHistoryStore (JSON-on-disk).
//
//  For the hackathon MVP, the teach pipeline doesn't yet write to
//  this store automatically — so this view will be empty on first
//  launch. We've documented the integration point in
//  CompanionManager so a follow-up pass can wire it in. The view
//  itself is fully functional once data lands.
//

import SwiftUI

struct DashboardRecordingsView: View {
    @State private var loadedRecordings: [DashboardRecording] = []

    var body: some View {
        DashboardContentScrollContainer {
            DashboardSectionHeader(
                eyebrow: "RECORDINGS",
                title: "Every teach moment, archived.",
                subtitle: "Each recording is one press of teach mode — what you said, what Sticky pulled out, and whether you kept it."
            ) {
                Button(action: refreshRecordings) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 11, weight: .bold))
                        Text("Refresh")
                            .font(.system(size: 12, weight: .semibold))
                    }
                }
                .buttonStyle(InteractivePressStyle(pressScale: 0.96))
                .pointerCursor()
                .foregroundColor(ElevenLabsBrand.Colors.inkSecondary)
            }

            if loadedRecordings.isEmpty {
                emptyStateCard
            } else {
                ForEach(loadedRecordings) { recording in
                    recordingCard(recording)
                }
            }
        }
        .onAppear { refreshRecordings() }
    }

    private var emptyStateCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("No recordings yet")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(ElevenLabsBrand.Colors.ink)
            Text("Hold ctrl+option in Teach mode to record a moment. The transcript and any extracted principle will appear here.")
                .font(.system(size: 12))
                .foregroundColor(ElevenLabsBrand.Colors.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(ElevenLabsBrand.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: ElevenLabsBrand.Radius.card, style: .continuous)
                .fill(ElevenLabsBrand.Colors.paperRecessed)
        )
        .overlay(
            RoundedRectangle(cornerRadius: ElevenLabsBrand.Radius.card, style: .continuous)
                .stroke(ElevenLabsBrand.Colors.hairline, lineWidth: 1)
        )
    }

    private func recordingCard(_ recording: DashboardRecording) -> some View {
        VStack(alignment: .leading, spacing: ElevenLabsBrand.Spacing.sm) {
            HStack {
                Text(recording.recordedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(ElevenLabsBrand.Colors.inkSecondary)

                Spacer()

                statusBadge(forRecording: recording)

                Button(action: {
                    DashboardRecordingHistoryStore.deleteRecording(id: recording.id)
                    refreshRecordings()
                }) {
                    Image(systemName: "trash")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(ElevenLabsBrand.Colors.inkSecondary)
                }
                .buttonStyle(InteractivePressStyle(pressScale: 0.92))
                .pointerCursor()
                .nativeTooltip("Delete this recording")
            }

            Text(recording.transcript)
                .font(.system(size: 13))
                .foregroundColor(ElevenLabsBrand.Colors.ink)
                .fixedSize(horizontal: false, vertical: true)

            if let principle = recording.extractedPrinciple {
                VStack(alignment: .leading, spacing: 4) {
                    Text("EXTRACTED PRINCIPLE")
                        .font(.system(size: 9, weight: .bold))
                        .tracking(0.4)
                        .foregroundColor(ElevenLabsBrand.Colors.inkTertiary)

                    Text(principle.statement)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(ElevenLabsBrand.Colors.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 4)
            }
        }
        .padding(ElevenLabsBrand.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: ElevenLabsBrand.Radius.card, style: .continuous)
                .fill(ElevenLabsBrand.Colors.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: ElevenLabsBrand.Radius.card, style: .continuous)
                .stroke(ElevenLabsBrand.Colors.hairline, lineWidth: 1)
        )
    }

    private func statusBadge(forRecording recording: DashboardRecording) -> some View {
        let label: String
        if recording.extractedPrinciple == nil {
            label = "No principle"
        } else if recording.wasApproved {
            label = "Saved"
        } else {
            label = "Skipped"
        }
        return Text(label.uppercased())
            .font(.system(size: 9, weight: .bold))
            .tracking(0.4)
            .foregroundColor(ElevenLabsBrand.Colors.inkTertiary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                Capsule().fill(ElevenLabsBrand.Colors.paperRecessed)
            )
    }

    private func refreshRecordings() {
        loadedRecordings = DashboardRecordingHistoryStore.loadAllRecordings()
    }
}
