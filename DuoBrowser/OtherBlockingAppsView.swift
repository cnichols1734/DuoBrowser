import SwiftUI

struct OtherBlockingAppsView: View {
    var body: some View {
        List {
            Section {
                Text("Some blocking apps can filter connections across your iPhone. Turn on that protection in the blocking app; it can work alongside DuoBrowser’s built-in filters.")
            }
            Section {
                guide("AdGuard", detail: "Enable DNS protection and choose an ad-blocking DNS server.",
                      url: "https://adguard.com/en/support/adguard_for_ios/doesnt_block_ads/in_other_browsers.html")
                guide("Adblock Plus", detail: "Its Premium app has a separate DNS setup for blocking in apps.",
                      url: "https://help.adblockplus.org/adblock-plus-help-center/enable-ad-blocking-in-apps-in-the-adblock-plus-for-ios-app")
                guide("Wipr 2", detail: "Open Wipr → More → Filtr. This optional add-on filters URLs across apps.",
                      url: "https://kaylees.site/wipr-help.html#what-is-filtr")
                guide("1Blocker", detail: "Open Privacy → Apps → Block In-App Trackers. This filters tracker connections, not every ad.",
                      url: "https://support.1blocker.com/en/articles/9313591-in-app-tracking-filter-overview")
            } header: {
                Text("System-wide Options")
            } footer: {
                Text("These links open each developer’s setup guide. DuoBrowser can’t detect whether another app’s filter is active or change its settings.")
            }
            Section("Safari Extensions") {
                Text("Safari extensions and their settings don’t transfer to DuoBrowser. AdBlock Pro’s Safari extension, for example, works in Safari.")
                Text("System-wide filters can block some connections here, but they don’t provide a Safari extension’s page cleanup. Some ads may remain.")
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Other Blocking Apps")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func guide(_ title: String, detail: String, url: String) -> some View {
        Link(destination: URL(string: url)!) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 12) {
                    Text(title).font(.body.weight(.medium))
                    Spacer(minLength: 8)
                    Image(systemName: "arrow.up.right").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                }
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
            }
            .foregroundStyle(.primary).padding(.vertical, 6)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).contentShape(Rectangle())
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens the developer’s setup guide")
    }
}
