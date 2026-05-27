import SwiftUI

enum SettingsPane: Hashable {
    case openRouter
    case preset(UUID)
}

// MARK: - Shared visual primitives

struct PaneHeader: View {
    let icon: String
    let title: String
    let subtitle: String?
    let trailing: AnyView?

    init(icon: String, title: String, subtitle: String? = nil, trailing: AnyView? = nil) {
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 26))
                .foregroundStyle(.tint)
                .symbolRenderingMode(.hierarchical)
                .frame(width: 44, height: 44)
                .background(.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.title2.weight(.semibold))
                if let subtitle = subtitle {
                    Text(subtitle).font(.callout).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if let trailing = trailing { trailing }
        }
    }
}

struct Card<Content: View>: View {
    let title: String?
    let icon: String?
    @ViewBuilder var content: () -> Content

    init(_ title: String? = nil, icon: String? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.icon = icon
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let title = title {
                HStack(spacing: 6) {
                    if let icon = icon {
                        Image(systemName: icon)
                            .imageScale(.small)
                            .foregroundStyle(.secondary)
                    }
                    Text(title)
                        .font(.system(size: 11, weight: .semibold))
                        .textCase(.uppercase)
                        .foregroundStyle(.secondary)
                        .tracking(0.4)
                }
                .padding(.horizontal, 4)
                .padding(.bottom, 8)
            }
            content()
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(Color.primary.opacity(0.07), lineWidth: 1)
                )
        }
    }
}

struct CalloutCard<Content: View>: View {
    let tint: Color
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(tint.opacity(0.25), lineWidth: 1)
            )
    }
}

struct SettingsView: View {
    @Environment(PresetStore.self) private var store
    @State private var selection: SettingsPane? = .openRouter
    @State private var models: [OpenRouterModel] = []
    @State private var modelsLoading = false
    @State private var modelsError: String?

    var body: some View {
        NavigationSplitView(columnVisibility: .constant(.all)) {
            sidebar
                .frame(minWidth: 320, idealWidth: 360, maxWidth: 460)
                .navigationSplitViewColumnWidth(min: 320, ideal: 360, max: 460)
                .toolbar(removing: .sidebarToggle)
        } detail: {
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .toolbarBackground(.automatic, for: .windowToolbar)
        }
        .frame(minWidth: 920, minHeight: 580)
        .task { await loadModels() }
        .onChange(of: store.apiKey) { _, _ in
            Task { await loadModels() }
        }
        .onChange(of: store.baseURL) { _, _ in
            Task { await loadModels() }
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        List(selection: $selection) {
            Section("Service") {
                Label("OpenRouter", systemImage: "key.fill")
                    .symbolRenderingMode(.hierarchical)
                    .tag(SettingsPane.openRouter)
            }

            Section("Actions") {
                ForEach(store.presets) { preset in
                    sidebarRow(preset)
                        .tag(SettingsPane.preset(preset.id))
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            sidebarFooter
        }
    }

    private var sidebarFooter: some View {
        HStack(spacing: 0) {
            Button {
                let new = store.addPreset()
                selection = .preset(new.id)
            } label: {
                Image(systemName: "plus")
                    .frame(width: 28, height: 22)
            }
            .help("Add Action")

            Button {
                if case .preset(let id) = selection,
                   let preset = store.presets.first(where: { $0.id == id }) {
                    store.remove(preset)
                    selection = .openRouter
                }
            } label: {
                Image(systemName: "minus")
                    .frame(width: 28, height: 22)
            }
            .help("Delete selected Action")
            .disabled({
                if case .preset = selection { return false } else { return true }
            }())

            Spacer()
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(.bar)
        .overlay(Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 0.5), alignment: .top)
    }

    @ViewBuilder
    private func sidebarRow(_ preset: Preset) -> some View {
        HStack(spacing: 10) {
            Text(preset.name)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let hk = preset.hotkey {
                Text(shortcutString(hk))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 4))
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - Detail

    @ViewBuilder
    private var detail: some View {
        switch selection {
        case .openRouter, .none:
            OpenRouterPane(models: $models,
                           modelsLoading: $modelsLoading,
                           modelsError: $modelsError,
                           reload: { Task { await loadModels() } })
        case .preset(let id):
            if let idx = store.presets.firstIndex(where: { $0.id == id }) {
                PresetPane(preset: bindingForPreset(at: idx),
                           onDelete: { deletePreset(id: id) })
                    .id(id)
            } else {
                ContentUnavailableView("Action removed",
                                       systemImage: "tray",
                                       description: Text("Select an item from the sidebar."))
            }
        }
    }

    private func bindingForPreset(at index: Int) -> Binding<Preset> {
        Binding(
            get: { store.presets[index] },
            set: { store.update($0) }
        )
    }

    private func deletePreset(id: UUID) {
        guard let preset = store.presets.first(where: { $0.id == id }) else { return }
        store.remove(preset)
        selection = .openRouter
    }

    private func loadModels() async {
        modelsLoading = true
        modelsError = nil
        do {
            let list = try await OpenRouter.listModels(baseURL: store.baseURL, apiKey: store.apiKey)
            self.models = list.sorted { ($0.name ?? $0.id) < ($1.name ?? $1.id) }
            self.modelsLoading = false
        } catch {
            self.modelsError = error.localizedDescription
            self.modelsLoading = false
        }
    }
}

// MARK: - OpenRouter pane

struct OpenRouterPane: View {
    @Environment(PresetStore.self) private var store
    @Binding var models: [OpenRouterModel]
    @Binding var modelsLoading: Bool
    @Binding var modelsError: String?
    let reload: () -> Void

    @State private var filter = ""
    @State private var sort: ModelSort = .name

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                PaneHeader(icon: "bolt.horizontal.fill",
                           title: "Service",
                           subtitle: "Cloud or local. Any OpenAI-compatible endpoint.")

                AccessibilityStatusRow()

                LaunchAtLoginCard()

                Card("Provider", icon: "server.rack") {
                    VStack(alignment: .leading, spacing: 10) {
                        Picker("Provider", selection: Binding(
                            get: { store.preset },
                            set: { store.updateServicePreset($0) }
                        )) {
                            ForEach(ServicePreset.allCases) { p in
                                Label(p.title, systemImage: p.symbol).tag(p)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()

                        Text(store.preset.subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        HStack(spacing: 8) {
                            Text("Base URL")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(width: 70, alignment: .leading)
                            TextField("https://example.com/v1", text: Binding(
                                get: { store.baseURL },
                                set: { store.updateBaseURL($0) }
                            ))
                            .textFieldStyle(.roundedBorder)
                            .disableAutocorrection(true)
                            .textCase(.lowercase)
                        }
                    }
                }

                if store.preset.needsAPIKey || store.preset == .custom {
                    Card(store.preset == .openRouter ? "OpenRouter API Key" : "API Key (optional)",
                         icon: "lock.shield") {
                        VStack(alignment: .leading, spacing: 8) {
                            SecureField(store.preset == .openRouter ? "sk-or-…" : "leave blank if not needed",
                                        text: Binding(
                                            get: { store.apiKey },
                                            set: { store.updateAPIKey($0) }
                                        ))
                            .textFieldStyle(.roundedBorder)
                            .controlSize(.large)
                            Text(apiKeyHint)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } else {
                    Card("API Key", icon: "lock.shield") {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Text("Not needed for \(store.preset.title) — caip talks to the local server directly.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Card("Default Model", icon: "cpu") {
                    VStack(alignment: .leading, spacing: 10) {
                        Picker("Model", selection: Binding(
                            get: { store.defaultModel },
                            set: { store.updateDefaultModel($0) }
                        )) {
                            if !models.contains(where: { $0.id == store.defaultModel }) {
                                Text(store.defaultModel).tag(store.defaultModel)
                            }
                            ForEach(filtered) { m in
                                Text(modelMenuLabel(m, sort: sort)).tag(m.id)
                            }
                        }
                        .controlSize(.large)
                        .labelsHidden()

                        HStack(spacing: 8) {
                            HStack(spacing: 6) {
                                Image(systemName: "magnifyingglass").foregroundStyle(.tertiary)
                                TextField("Search models", text: $filter)
                                    .textFieldStyle(.plain)
                                if !filter.isEmpty {
                                    Button { filter = "" } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundStyle(.tertiary)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(Color(NSColor.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.primary.opacity(0.08)))

                            Menu {
                                Picker("Sort by", selection: $sort) {
                                    ForEach(ModelSort.allCases) { s in
                                        Text(s.title).tag(s)
                                    }
                                }
                            } label: {
                                Label(sort.title, systemImage: "arrow.up.arrow.down")
                                    .font(.caption)
                            }
                            .menuStyle(.borderlessButton)
                            .fixedSize()

                            Button { reload() } label: {
                                Image(systemName: "arrow.clockwise")
                                    .symbolEffect(.rotate, options: modelsLoading ? .repeat(.continuous) : .nonRepeating)
                            }
                            .buttonStyle(.borderless)
                            .help("Refresh models list")
                        }

                        Group {
                            if let err = modelsError {
                                Label(err, systemImage: "exclamationmark.triangle")
                                    .foregroundStyle(.red)
                            } else if modelsLoading {
                                HStack(spacing: 6) {
                                    ProgressView().controlSize(.small)
                                    Text("Loading…")
                                }
                            } else {
                                Text("\(models.count) models. Price shown as $/1M tokens (in / out).")
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(28)
            .frame(maxWidth: 580, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var apiKeyHint: String {
        switch store.preset {
        case .openRouter:
            return "Get a key at openrouter.ai/keys."
        case .custom:
            return "Provide one if your endpoint requires Bearer auth."
        case .ollama, .lmStudio, .jan:
            return "Optional. Most local servers don't require a key."
        }
    }

    private var filtered: [OpenRouterModel] {
        var list = models
        if !filter.isEmpty {
            let q = filter.lowercased()
            list = list.filter { ($0.name ?? "").lowercased().contains(q) || $0.id.lowercased().contains(q) }
        }
        return sortModels(list, by: sort)
    }
}

// MARK: - Preset pane

struct PresetPane: View {
    @Binding var preset: Preset
    let onDelete: () -> Void
    @Environment(PresetStore.self) private var store

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                PaneHeader(icon: "sparkle",
                           title: preset.name.isEmpty ? "New Action" : preset.name,
                           subtitle: preset.hotkey.map { shortcutString($0) } ?? "No shortcut yet")

                Card("Title", icon: "textformat") {
                    TextField("Name", text: $preset.name)
                        .textFieldStyle(.roundedBorder)
                        .controlSize(.large)
                }

                Card("Prompt", icon: "text.alignleft") {
                    VStack(alignment: .leading, spacing: 6) {
                        TextEditor(text: $preset.prompt)
                            .font(.system(.body, design: .monospaced))
                            .frame(minHeight: 180)
                            .scrollContentBackground(.hidden)
                            .padding(8)
                            .background(Color(NSColor.textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.primary.opacity(0.10)))
                        Text("Use `{selectedText}` or `{s}` to insert the selected text.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Card("Shortcut", icon: "keyboard") {
                    HStack {
                        HotkeyRecorder(hotkey: $preset.hotkey)
                            .frame(width: 260, height: 30)
                        Spacer()
                    }
                }
            }
            .padding(28)
            .frame(maxWidth: 580, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .toolbar {
            ToolbarItem(placement: .destructiveAction) {
                Button(role: .destructive, action: onDelete) {
                    Label("Delete", systemImage: "trash")
                }
                .help("Delete this action")
            }
        }
    }
}

// MARK: - Accessibility

struct AccessibilityStatusRow: View {
    @State private var trusted: Bool = AccessibilityCheck.isGranted()
    @State private var timer: Timer?
    @State private var showingResetHint = false

    var body: some View {
        CalloutCard(tint: trusted ? .green : .orange) {
            HStack(spacing: 12) {
                Image(systemName: trusted ? "checkmark.shield.fill" : "exclamationmark.shield.fill")
                    .font(.system(size: 20))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(trusted ? .green : .orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text(trusted ? "Accessibility access granted" : "Accessibility access required")
                        .font(.headline)
                    Text(trusted
                         ? "caip can read your selection and paste results."
                         : "caip needs this to send ⌘C and ⌘V on your behalf.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if !trusted {
                    Button("Open Settings") { openAccessibilityPane() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.regular)
                }
                Menu {
                    Button("Re-check") { recheck() }
                    Button("Reset & re-grant…") { showingResetHint = true }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
        }
        .onAppear { startPolling() }
        .onDisappear { stopPolling() }
        .alert("Reset Accessibility entry?", isPresented: $showingResetHint) {
            Button("Cancel", role: .cancel) {}
            Button("Reset", role: .destructive) { resetAndReopen() }
        } message: {
            Text("Runs `tccutil reset Accessibility net.variant.caip` and reopens the Accessibility pane so you can re-add caip.")
        }
    }

    private func openAccessibilityPane() {
        AppDelegate.requestAccessibility()
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    private func resetAndReopen() {
        let task = Process()
        task.launchPath = "/usr/bin/tccutil"
        task.arguments = ["reset", "Accessibility", "net.variant.caip"]
        try? task.run()
        task.waitUntilExit()
        recheck()
        openAccessibilityPane()
    }

    private func recheck() { trusted = AccessibilityCheck.isGranted() }

    private func startPolling() {
        stopPolling()
        timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { _ in
            let now = AccessibilityCheck.isGranted()
            if now != trusted {
                DispatchQueue.main.async { trusted = now }
            }
        }
    }

    private func stopPolling() {
        timer?.invalidate()
        timer = nil
    }
}

struct LaunchAtLoginCard: View {
    @State private var enabled = LoginItem.isEnabled
    @State private var status = LoginItem.statusDescription
    @State private var timer: Timer?

    var body: some View {
        Card("Startup", icon: "power.circle") {
            HStack(spacing: 12) {
                Image(systemName: enabled ? "power.circle.fill" : "power.circle")
                    .font(.system(size: 18))
                    .foregroundStyle(enabled ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                    .symbolRenderingMode(.hierarchical)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Launch at Login")
                        .font(.system(size: 13, weight: .medium))
                    Text(status)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("", isOn: Binding(
                    get: { enabled },
                    set: { newValue in
                        LoginItem.setEnabled(newValue)
                        refresh()
                    }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
            }
        }
        .onAppear {
            refresh()
            timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
                DispatchQueue.main.async { refresh() }
            }
        }
        .onDisappear {
            timer?.invalidate()
            timer = nil
        }
    }

    private func refresh() {
        enabled = LoginItem.isEnabled
        status = LoginItem.statusDescription
    }
}

enum AccessibilityCheck {
    static func isGranted() -> Bool {
        if !AXIsProcessTrusted() { return false }
        let system = AXUIElementCreateSystemWide()
        var focused: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focused)
        return result == .success || result == .noValue
    }
}

// MARK: - Sort helpers

enum ModelSort: String, CaseIterable, Identifiable {
    case name, priceAsc, contextDesc, newest
    var id: String { rawValue }
    var title: String {
        switch self {
        case .name: return "Name"
        case .priceAsc: return "Price (low → high)"
        case .contextDesc: return "Context (large → small)"
        case .newest: return "Newest"
        }
    }
}

func sortModels(_ models: [OpenRouterModel], by mode: ModelSort) -> [OpenRouterModel] {
    switch mode {
    case .name:
        return models.sorted { ($0.name ?? $0.id).localizedCaseInsensitiveCompare($1.name ?? $1.id) == .orderedAscending }
    case .priceAsc:
        return models.sorted {
            (($0.combinedPrice ?? .greatestFiniteMagnitude), ($0.name ?? $0.id)) <
            (($1.combinedPrice ?? .greatestFiniteMagnitude), ($1.name ?? $1.id))
        }
    case .contextDesc:
        return models.sorted { ($0.contextLength ?? 0) > ($1.contextLength ?? 0) }
    case .newest:
        return models.sorted { ($0.createdAt ?? 0) > ($1.createdAt ?? 0) }
    }
}

func describePrice(_ m: OpenRouterModel) -> String {
    guard let p = m.promptPrice, let c = m.completionPrice else { return "—" }
    return String(format: "$%.2f / $%.2f / 1M", p * 1_000_000, c * 1_000_000)
}

func describeContext(_ m: OpenRouterModel) -> String {
    guard let ctx = m.contextLength, ctx > 0 else { return "—" }
    if ctx >= 1_000_000 { return String(format: "%.1fM", Double(ctx) / 1_000_000) }
    if ctx >= 1_000 { return "\(ctx / 1000)k" }
    return "\(ctx)"
}

func modelMenuLabel(_ m: OpenRouterModel, sort: ModelSort) -> String {
    let base = m.name ?? m.id
    switch sort {
    case .name, .newest: return base
    case .priceAsc: return "\(base)  ·  \(describePrice(m))"
    case .contextDesc: return "\(base)  ·  \(describeContext(m)) ctx"
    }
}

func shortcutString(_ hk: Hotkey) -> String {
    var s = ""
    let m = NSEvent.ModifierFlags(rawValue: UInt(hk.modifierFlags))
    if m.contains(.control) { s += "⌃" }
    if m.contains(.option) { s += "⌥" }
    if m.contains(.shift) { s += "⇧" }
    if m.contains(.command) { s += "⌘" }
    s += KeyName.string(for: UInt16(hk.keyCode))
    return s
}
