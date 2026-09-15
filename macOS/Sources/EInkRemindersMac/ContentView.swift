import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        HStack(alignment: .top, spacing: 24) {
            settingsPanel
                .frame(width: 300)

            displayPanel
                .frame(width: 610)
        }
        .padding(24)
        .frame(width: 982, height: 630)
        .background(Color(nsColor: .windowBackgroundColor))
        .task { await model.prepare() }
    }

    private var settingsPanel: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 5) {
                Label("墨水屏提醒事项", systemImage: "checklist")
                    .font(.title2.bold())
                Text("完全联动 Apple 提醒事项、Mac 与 iPhone")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 12) {
                Text("连接设置")
                    .font(.headline)

                Text("设备地址")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Group {
                    if ProcessInfo.processInfo.environment["EINK_MAC_UI_PREVIEW_PATH"] != nil {
                        Text(model.deviceURL)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        TextField("例如 192.168.1.42", text: $model.deviceURL)
                            .textFieldStyle(.plain)
                    }
                }
                .padding(.horizontal, 9)
                .frame(height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color(nsColor: .textBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(Color.primary.opacity(0.16))
                )

                Text("提醒事项列表")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Picker("", selection: $model.selectedCalendarId) {
                    Text("请选择").tag(String?.none)
                    ForEach(model.calendars, id: \.id) { calendar in
                        Text(calendar.title).tag(String?.some(calendar.id))
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)

                Divider()

                Toggle("自动同步", isOn: $model.automaticSync)
                HStack {
                    Text("同步周期")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Picker("同步周期", selection: $model.automaticSyncInterval) {
                        ForEach(AutomaticSyncInterval.allCases) { interval in
                            Text(interval.title).tag(interval)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 116)
                    .disabled(!model.automaticSync)
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.primary.opacity(0.08))
            )

            Button {
                Task { await model.sync(force: true) }
            } label: {
                HStack {
                    if model.isSyncing {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "arrow.triangle.2.circlepath")
                    }
                    Text(model.isSyncing ? "正在同步…" : "立即同步")
                    Spacer()
                }
                .padding(.vertical, 5)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(model.isSyncing)

            VStack(alignment: .leading, spacing: 6) {
                Text("同步状态")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(model.statusText)
                    .font(.callout)
                    .foregroundStyle(model.statusText.hasPrefix("同步失败") ? .red : .primary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            Text("NOTE4：上/下选择 · OK 确认 · 长按上键设置")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var displayPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("墨水屏预览")
                        .font(.headline)
                    Text("同步到设备后的实际黑白布局")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Label(
                    model.isSyncing ? "正在同步" : "实时预览",
                    systemImage: model.isSyncing ? "arrow.triangle.2.circlepath" : "circle.fill"
                )
                .font(.caption.weight(.medium))
                .foregroundStyle(model.isSyncing ? Color.accentColor : Color.green)
            }

            EInkDisplayViewport(
                reminders: model.reminders,
                view: model.activeView,
                emptyState: model.emptyState,
                isSyncing: model.isSyncing,
                displayWidth: model.displayWidth,
                displayHeight: model.displayHeight
            )

            HStack {
                Label("\(model.displayWidth) × \(model.displayHeight)", systemImage: "rectangle")
                Spacer()
                Text("共 \(model.activeViewTotalCount) 项")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }
}

struct EInkDisplayViewport: View {
    let reminders: [ReminderItem]
    let view: DeviceReminderView
    let emptyState: ReminderEmptyState
    let isSyncing: Bool
    let displayWidth: Int
    let displayHeight: Int

    private var preview: CGImage? {
        try? ZectrixDisplayRenderer.previewImage(
            reminders, view: view, emptyState: emptyState
        )
    }

    private var aspectRatio: CGFloat {
        CGFloat(displayWidth) / CGFloat(max(displayHeight, 1))
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color(nsColor: .darkGray), .black],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            ZStack {
                Color.white
                if let preview {
                    Image(decorative: preview, scale: 1)
                        .resizable()
                        .interpolation(.none)
                        .aspectRatio(aspectRatio, contentMode: .fit)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            .padding(18)

            if isSyncing {
                VStack(spacing: 9) {
                    ProgressView()
                        .controlSize(.small)
                    Text("正在发送到墨水屏")
                        .font(.caption.weight(.medium))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .shadow(radius: 12, y: 4)
            }
        }
        .aspectRatio(aspectRatio, contentMode: .fit)
        .shadow(color: .black.opacity(0.20), radius: 18, y: 8)
        .accessibilityLabel("墨水屏提醒事项预览")
    }
}
