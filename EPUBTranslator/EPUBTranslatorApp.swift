import SwiftUI

@main
struct EPUBTranslatorApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                #if os(macOS)
                .frame(minWidth: 900, minHeight: 550)
                #endif
        }
        #if os(macOS)
        .windowStyle(.titleBar)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1100, height: 750)
        #endif
    }
}
