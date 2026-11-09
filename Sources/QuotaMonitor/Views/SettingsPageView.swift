import SwiftUI

extension MainPanelView {
    var settingsPage: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(language.text("settings.title"))
                .font(.system(size: 22, weight: .bold, design: .monospaced))
                .kerning(-0.4)
                .foregroundStyle(PanelTheme.text)
            VStack(spacing: 14) {
                settingsCard {
                    settingsRow(title: language.text("settings.launchAtLogin"), detail: language.text("settings.launchAtLogin.detail")) {
                        Toggle("", isOn: Binding(
                            get: { loginItem.isRegistered },
                            set: { loginItem.setEnabled($0) }
                        ))
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .tint(PanelTheme.chartAccent)
                        .accessibilityLabel(language.text("settings.launchAtLogin"))
                        .accessibilityHint(language.text("settings.launchAtLogin.hint"))
                    }
                    settingsRow(title: language.text("settings.reminders"), detail: language.text("settings.reminders.detail")) {
                        Toggle("", isOn: $reminderSettings.isEnabled)
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .tint(PanelTheme.chartAccent)
                            .accessibilityLabel(language.text("settings.reminders"))
                    }
                    settingsRow(
                        title: language.text("settings.systemNotifications"),
                        detail: language.text(systemNotificationDetailKey)
                    ) {
                        Toggle("", isOn: $reminderSettings.prefersSystemNotifications)
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .tint(PanelTheme.chartAccent)
                            .disabled(!reminderSettings.isEnabled)
                            .accessibilityLabel(language.text("settings.systemNotifications"))
                    }
                    settingsRow(title: language.text("settings.language"), detail: language.text("settings.language.detail")) {
                        PanelSegmentedControl(
                            options: AppLanguage.allCases,
                            selection: $language.language
                        ) { value in
                            value == .simplifiedChinese ? "简体中文" : "English"
                        }
                    }
                    settingsRow(title: language.text("settings.appearance"), detail: language.text("settings.appearance.detail")) {
                        PanelSegmentedControl(
                            options: AppearanceMode.allCases,
                            selection: $appearanceSettings.mode
                        ) { mode in
                            switch mode {
                            case .system: language.text("appearance.system")
                            case .light: language.text("appearance.light")
                            case .dark: language.text("appearance.dark")
                            }
                        }
                    }
                    settingsRow(title: language.text("settings.dockIcon"), detail: language.text("settings.dockIcon.detail")) {
                        PanelSegmentedControl(
                            options: DockIconMode.allCases,
                            selection: $dockIconSettings.mode
                        ) { mode in
                            switch mode {
                            case .smart: language.text("settings.dockIcon.smart")
                            case .always: language.text("settings.dockIcon.always")
                            case .never: language.text("settings.dockIcon.never")
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            trustedSourcesCard
        }
    }

    private var systemNotificationDetailKey: String {
        switch reminderSettings.systemAuthorizationState {
        case .unknown, .notRequested: "settings.systemNotifications.detail"
        case .authorized: "settings.systemNotifications.authorized"
        case .denied: "settings.systemNotifications.denied"
        }
    }

    private var trustedSourcesCard: some View {
        settingsCard {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(language.text("settings.sources"))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(PanelTheme.text)
                    Text(language.text("settings.sources.detail"))
                        .font(.system(size: 10))
                        .foregroundStyle(PanelTheme.text2)
                }
                Spacer(minLength: 8)
                Text(language.text("settings.sources.summary", trustedSources.filter { $0.state == .ready }.count, trustedSources.filter { $0.state != .ready }.count))
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(PanelTheme.text2)
                    .lineLimit(1)
                Button {
                    Task { await store.refreshAll() }
                } label: {
                    Label(language.text("settings.sources.rescan"), systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityHint(language.text("settings.sources.rescan.hint"))
            }
            .padding(.horizontal, 15)
            .padding(.vertical, 12)
            sourceCapabilityTable
            if showSourceHelp {
                Text(language.text("settings.sources.help"))
                    .font(.system(size: 10))
                    .foregroundStyle(PanelTheme.text2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 15)
                    .padding(.bottom, 12)
            }
        }
    }

    private struct SourceCapabilityRow: Identifiable {
        let id: String
        let product: String
        let quotaSources: [DataSourceHealthSnapshot]
        let tokenSources: [DataSourceHealthSnapshot]

        var isInstalled: Bool {
            quotaSources.contains(where: \.isInstalled) || tokenSources.contains(where: \.isInstalled)
        }

        var sourceDetails: [DataSourceHealthSnapshot] {
            var seen = Set<DataSourceID>()
            return (quotaSources + tokenSources).filter { seen.insert($0.id).inserted }
        }

        var redactedPaths: String {
            sourceDetails.map(\.redactedPath).joined(separator: " · ")
        }

        var validRecordCount: Int {
            sourceDetails.reduce(0) { $0 + $1.validRecordCount }
        }

    }

    private var trustedSources: [DataSourceHealthSnapshot] {
        store.dataSourceHealth.filter(\.isInstalled)
    }

    private var sourceCapabilityRows: [SourceCapabilityRow] {
        let sources = store.dataSourceHealth
        let byID = Dictionary(uniqueKeysWithValues: sources.map { ($0.id, $0) })
        return DataSourceCatalog.capabilityGroups.compactMap { group in
            var quotaIDs = group.quotaSourceIDs
            if group.id == "claude", store.claudeUsesDeepSeek {
                quotaIDs.append(contentsOf: group.routeDependentQuotaSourceIDs)
            }
            let row = SourceCapabilityRow(
                id: group.id,
                product: group.nameKey.map { language.text($0) } ?? group.fallbackName,
                quotaSources: quotaIDs.compactMap { byID[$0] },
                tokenSources: group.tokenSourceIDs.compactMap { byID[$0] }
            )
            return row.isInstalled ? row : nil
        }
    }

    private var sourceCapabilityTable: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Text(language.text("settings.sources.table.product"))
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(language.text("settings.sources.table.quota"))
                    .frame(width: 72, alignment: .center)
                Text(language.text("settings.sources.table.token"))
                    .frame(width: 72, alignment: .center)
            }
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(PanelTheme.text2)
            .padding(.horizontal, 15)
            .padding(.bottom, 6)

            ForEach(sourceCapabilityRows) { row in
                HStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(row.product)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(PanelTheme.text)
                        Text(row.redactedPaths)
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(PanelTheme.text3)
                            .lineLimit(2)
                        if row.validRecordCount > 0 {
                            Text(language.text("settings.sources.table.records", row.validRecordCount))
                                .font(.system(size: 9))
                                .foregroundStyle(PanelTheme.text3)
                        }
                        capabilityReason(for: row.quotaSources, labelKey: "settings.sources.table.quota")
                        capabilityReason(for: row.tokenSources, labelKey: "settings.sources.table.token")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    capabilityCell(state: SourceCapabilityPresentation(states: row.quotaSources.map(\.state)), label: language.text("settings.sources.table.quota"))
                        .frame(width: 72)
                    capabilityCell(state: SourceCapabilityPresentation(states: row.tokenSources.map(\.state)), label: language.text("settings.sources.table.token"))
                        .frame(width: 72)
                }
                .padding(.horizontal, 15)
                .padding(.vertical, 9)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(PanelTheme.separator).frame(height: 0.5).padding(.horizontal, 15)
                }
            }

            if sourceCapabilityRows.isEmpty {
                Text(language.text("settings.sources.table.empty"))
                    .font(.system(size: 11))
                    .foregroundStyle(PanelTheme.text2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 15)
                    .padding(.vertical, 9)
            }

            Spacer(minLength: 0)
        }
    }

    private func capabilityCell(state: SourceCapabilityPresentation, label: String) -> some View {
        let description = state.reasonKey.map { language.text($0) } ?? language.text("settings.sources.table.available")
        return Image(systemName: state.symbol)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(state.color)
            .accessibilityLabel("\(label): \(description)")
    }

    @ViewBuilder private func capabilityReason(for sources: [DataSourceHealthSnapshot], labelKey: String) -> some View {
        let state = SourceCapabilityPresentation(states: sources.map(\.state))
        if let reasonKey = state.reasonKey {
            Text(language.text("settings.sources.table.reason", language.text(labelKey), language.text(reasonKey)))
                .font(.system(size: 9))
                .foregroundStyle(state.color)
                .lineLimit(2)
        }
    }

    private func settingsCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            content()
        }
        .background(PanelTheme.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private func settingsRow<Control: View>(title: String, detail: String, @ViewBuilder control: () -> Control) -> some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(PanelTheme.text)
                Text(detail)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(PanelTheme.text3)
            }
            Spacer(minLength: 8)
            control()
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 8)
        .frame(minHeight: 48)
        .overlay(alignment: .bottom) {
            Rectangle().fill(PanelTheme.separator).frame(height: 0.5).padding(.horizontal, 15)
        }
    }


}
