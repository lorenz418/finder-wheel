import SwiftUI
import FinderWheelCore

struct MenuBarView: View {
    let controller: AppController

    var body: some View {
        let jobs = controller.jobCenter
        VStack(alignment: .leading, spacing: 10) {
            if let problem = controller.permissionProblem {
                Label(problem, systemImage: "exclamationmark.triangle")
                    .font(.callout)
                Button("Open Automation Settings") { controller.openAutomationSettings() }
                Divider()
            }
            if jobs.jobs.isEmpty {
                Text("No recent jobs")
                    .foregroundStyle(.secondary)
                Text("Select files in Finder and hold \(controller.hotkeyLabel).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(jobs.jobs) { job in
                            JobRow(job: job) { jobs.cancel(job.id) }
                        }
                    }
                }
                .frame(maxHeight: 320)
            }
            Divider()
            Button("Quit Finder Wheel") { NSApplication.shared.terminate(nil) }
        }
        .padding(14)
        .frame(width: 300)
        .onAppear { jobs.clearWarning() }
    }
}

private struct JobRow: View {
    let job: JobCenter.Job
    let cancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(job.title).font(.callout.weight(.medium))
                Spacer()
                switch job.state {
                case .running:
                    Button("Cancel", action: cancel).controlSize(.small)
                case .cancelled:
                    Text("Cancelled").font(.caption).foregroundStyle(.secondary)
                case .finished:
                    Text(summary).font(.caption).foregroundStyle(.secondary)
                }
            }
            if job.state == .running {
                ProgressView(value: job.progress)
            }
            ForEach(job.notes) { note in
                Label("\(note.file): \(note.message)", systemImage: note.isFailure ? "exclamationmark.triangle" : "arrow.uturn.right")
                    .font(.caption)
                    .foregroundStyle(note.isFailure ? Color.primary : Color.secondary)
            }
        }
    }

    private var summary: String {
        let made = job.outputs.count
        return made == 1 ? "1 item created" : "\(made) items created"
    }
}
