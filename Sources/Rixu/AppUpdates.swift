import SwiftUI
#if RIXU_OTA
import Sparkle
#endif

@MainActor
final class AppUpdates {
    let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    static let releases = URL(string: "https://github.com/Merenguelkl/rixu/releases/latest")!

    #if RIXU_OTA
    private let controller = SPUStandardUpdaterController(
        startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil
    )

    var updater: SPUUpdater { controller.updater }
    #endif

    func start() {
        #if RIXU_OTA
        controller.startUpdater()
        #endif
    }
}

struct UpdateSettings: View {
    let updates: AppUpdates

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("软件更新").font(.headline)
                Spacer()
                if let version = updates.version {
                    Text("版本 \(version)").monospacedDigit().foregroundStyle(.secondary)
                }
            }
            #if RIXU_OTA
            SparkleUpdateControls(updater: updates.updater)
            #else
            Link("查看 GitHub 最新版", destination: AppUpdates.releases)
            #endif
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.primary.opacity(0.045), in: .rect(cornerRadius: 12))
    }
}

#if RIXU_OTA
private struct SparkleUpdateControls: View {
    let updater: SPUUpdater
    @State private var canCheck = false
    @State private var automaticChecks = false
    @State private var automaticInstallation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("自动检查更新", isOn: Binding(
                get: { automaticChecks },
                set: { updater.automaticallyChecksForUpdates = $0 }
            ))
            Toggle("自动下载并安装", isOn: Binding(
                get: { automaticInstallation },
                set: { updater.automaticallyDownloadsUpdates = $0 }
            ))
            .disabled(!automaticChecks)

            Button("检查更新…") { updater.checkForUpdates() }
                .disabled(!canCheck)
        }
        .toggleStyle(.switch)
        .onReceive(updater.publisher(for: \.canCheckForUpdates)) { canCheck = $0 }
        .onReceive(updater.publisher(for: \.automaticallyChecksForUpdates)) { automaticChecks = $0 }
        .onReceive(updater.publisher(for: \.automaticallyDownloadsUpdates)) { automaticInstallation = $0 }
    }
}
#endif
