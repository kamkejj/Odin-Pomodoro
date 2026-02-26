import SwiftUI
import Foundation

// Struct representing the settings matching Odin side
struct Settings: Codable {
    var work: Float
    var short_break: Float
    var long_break: Float
}

@main
struct SettingsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    var body: some Scene {
        WindowGroup("OPT Settings") {
            SettingsView()
        }
        .windowStyle(HiddenTitleBarWindowStyle())
        // Keep window fixed size if you want
        .commands {
            CommandGroup(replacing: .newItem) {} // Removes "New Window" menu
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
    // Close app when window is closed
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
}

struct SettingsView: View {
    @State private var settings = Settings(work: 25.0, short_break: 5.0, long_break: 15.0)
    
    var settingsURL: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".pomodoro_settings.json")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Odin Pomodoro Timer Settings")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            VStack(alignment: .leading, spacing: 15) {
                HStack {
                    Text("Work Duration (min):")
                        .frame(width: 150, alignment: .leading)
                    TextField("", value: $settings.work, formatter: NumberFormatter())
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .frame(width: 60)
                }
                
                HStack {
                    Text("Short Break (min):")
                        .frame(width: 150, alignment: .leading)
                    TextField("", value: $settings.short_break, formatter: NumberFormatter())
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .frame(width: 60)
                }
                
                HStack {
                    Text("Long Break (min):")
                        .frame(width: 150, alignment: .leading)
                    TextField("", value: $settings.long_break, formatter: NumberFormatter())
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .frame(width: 60)
                }
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
            
            HStack {
                Spacer()
                Button("Cancel") {
                    NSApplication.shared.terminate(nil)
                }
                .keyboardShortcut(.cancelAction)
                
                Button("Save") {
                    saveSettings()
                    NSApplication.shared.terminate(nil)
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 350)
        .onAppear {
            loadSettings()
        }
    }
    
    private func loadSettings() {
        if let data = try? Data(contentsOf: settingsURL) {
            if let decoded = try? JSONDecoder().decode(Settings.self, from: data) {
                settings = decoded
            }
        }
    }
    
    private func saveSettings() {
        if let encoded = try? JSONEncoder().encode(settings) {
            try? encoded.write(to: settingsURL)
        }
    }
}
