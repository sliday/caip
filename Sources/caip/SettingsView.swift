import SwiftUI

enum SettingsPane: Hashable {
    case openRouter
    case preset(UUID)
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
                .navigationSplitViewColumnWidth(min: 220, ideal: 240, max: 280)
        } detail: {
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 780, minHeight: 520)
        .task { await loadModels() }
        .onChange(of: store.apiKey) { _, _ in
            Task { await loadModels() }
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        List(selection: $selection) {
            Section {
                Label("OpenRouter", systemImage: "key.fill")
                    .symbolRenderingMode(.hierarchical)
                    .tag(SettingsPane.openRouter)
            } header: {
                Text("Service")
            }

            Section {
                ForEach(store.presets) { preset in
                    sidebarRow(preset)
                        .tag(SettingsPane.preset(preset.id))
                }
            } header: {
                HStack {
                    Text("Actions")
                    Spacer()
                    Button {
                        let new = store.addPreset()
                        selection = .preset(new.id)
                    } label: {
                        Image(systemName: "plus")
                            .imageScale(.small)
                    }
                    .buttonStyle(.borderless)
                    .help("Add Action")
                }
            }
        }
        .listStyle(.sidebar)
    }

    @ViewBuilder
    private func sidebarRow(_ preset: Preset) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkle")
                .foregroundStyle(.tint)
                .symbolRenderingMode(.hierarchical)
            Text(preset.name).lineLimit(1)
            Spacer()
            if let hk = preset.hotkey {
                Text(shortcutString(hk))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(.thickMaterial, in: RoundedRectangle(cornerRadius: 4))
            }
        }
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
            let list = try await OpenRouter.listModels(apiKey: store.apiKey)
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
                header
                AccessibilityStatusRow()
                apiKeySection
                defaultModelSection
            }
            .padding(28)
            .frame(maxWidth: 560, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "key.fill")
                .font(.system(size: 28))
                .foregroundStyle(.tint)
                .symbolRenderingMode(.hierarchical)
                .padding(10)
                .background(.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 2) {
                Text("OpenRouter").font(.title2.weight(.semibold))
                Text("Bring your own key. caip uses it for every action.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private var apiKeySection: some View {
        GroupBox(label: Label("API Key", systemImage: "key").labelStyle(.titleOnly).font(.headline)) {
            VStack(alignment: .leading, spacing: 8) {
                SecureField("sk-or-…", text: Binding(
                    get: { store.apiKey },
                    set: { store.updateAPIKey($0) }
                ))
                .textFieldStyle(.roundedBorder)
                .controlSize(.large)
                HStack(spacing: 4) {
                    Image(systemName: "lock.shield").imageScale(.small)
                    Text("Stored in this app's preferences. Get a key at openrouter.ai/keys.")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        }
    }

    private var defaultModelSection: some View {
        GroupBox(label: Label("Default Model", systemImage: "cpu").labelStyle(.titleOnly).font(.headline)) {
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
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))

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
            .padding(.vertical, 4)
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
            VStack(alignment: .leading, spacing: 20) {
                header

                GroupBox(label: Label("Title", systemImage: "textformat").labelStyle(.titleOnly).font(.headline)) {
                    TextField("Name", text: $preset.name)
                        .textFieldStyle(.roundedBorder)
                        .controlSize(.large)
                }

                GroupBox(label: Label("Prompt", systemImage: "text.alignleft").labelStyle(.titleOnly).font(.headline)) {
                    VStack(alignment: .leading, spacing: 6) {
                        TextEditor(text: $preset.prompt)
                            .font(.system(.body, design: .monospaced))
                            .frame(minHeight: 180)
                            .padding(8)
                            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.secondary.opacity(0.15)))
                        HStack(spacing: 4) {
                            Image(systemName: "info.circle").imageScale(.small)
                            Text("Use `{selectedText}` or `{s}` to insert the selected text.")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }

                GroupBox(label: Label("Shortcut", systemImage: "keyboard").labelStyle(.titleOnly).font(.headline)) {
                    HStack {
                        HotkeyRecorder(hotkey: $preset.hotkey)
                            .frame(width: 260, height: 28)
                        Spacer()
                    }
                    .padding(.vertical, 4)
                }
            }
            .padding(28)
            .frame(maxWidth: 600, alignment: .leading)
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

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "sparkle")
                .font(.system(size: 28))
                .foregroundStyle(.tint)
                .symbolRenderingMode(.hierarchical)
                .padding(10)
                .background(.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 2) {
                Text(preset.name.isEmpty ? "New Action" : preset.name)
                    .font(.title2.weight(.semibold))
                if let hk = preset.hotkey {
                    Text(shortcutString(hk))
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.secondary)
                } else {
                    Text("No shortcut yet").foregroundStyle(.secondary).font(.callout)
                }
            }
            Spacer()
        }
    }
}

// MARK: - Accessibility

struct AccessibilityStatusRow: View {
    @State private var trusted: Bool = AccessibilityCheck.isGranted()
    @State private var timer: Timer?
    @State private var showingResetHint = false

    var body: some View {
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
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(trusted ? Color.green.opacity(0.08) : Color.orange.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder((trusted ? Color.green : Color.orange).opacity(0.25), lineWidth: 1)
        )
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
