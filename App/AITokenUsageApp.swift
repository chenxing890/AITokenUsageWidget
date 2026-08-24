import SwiftUI
import UserNotifications

@main
struct AITokenUsageApp: App {
    init() {
        // 请求通知授权：用量超阈值时由小组件扩展发送系统通知
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    var body: some Scene {
        WindowGroup {
            SettingsView()
                // .defaultSize 需 macOS 13，改用 onAppear 中直接设窗口大小（兼容 macOS 12）
                .onAppear {
                    DispatchQueue.main.async {
                        NSApp.windows.first?.setContentSize(NSSize(width: 860, height: 640))
                    }
                }
        }
        .windowStyle(.automatic)
    }
}
