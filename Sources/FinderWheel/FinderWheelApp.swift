import SwiftUI
import FinderWheelCore

@main
struct FinderWheelApp: App {
    @State private var controller = AppController()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(controller: controller)
        } label: {
            let jobs = controller.jobCenter
            Image(nsImage: StatusIcon.image(progress: jobs.isRunning ? jobs.overallProgress : nil,
                                            warning: jobs.hasWarning || controller.permissionProblem != nil))
        }
        .menuBarExtraStyle(.window)
    }
}
