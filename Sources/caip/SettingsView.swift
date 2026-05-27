import SwiftUI

enum SettingsTab: Hashable {
    case actions
    case apiKey
}

struct EditorTarget: Identifiable, Equatable {
    let id: UUID
}

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
            (($0.combinedPrice ?? .greatestFiniteMagnitude),
             ($0.name ?? $0.id)) <
            (($1.combinedPrice ?? .greatestFiniteMagnitude),
             ($1.name ?? $1.id))
        }
    case .contextDesc:
        return models.sorted { ($0.contextLength ?? 0) > ($1.contextLength ?? 0) }
    case .newest:
        return models.sorted { ($0.createdAt ?? 0) > ($1.createdAt ?? 0) }
    }
}

func describePrice(_ m: OpenRouterModel) -> String {
    guard let p = m.promptPrice, let c = m.completionPrice else { return "—" }
    // Display per 1M tokens: $X in / $Y out
    let inUSD = p * 1_000_000
    let outUSD = c * 1_000_000
    return String(format: "$%.2f / $%.2f / 1M", inUSD, outUSD)
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
    case .name:
        return base
    case .priceAsc:
        return "\(base)  ·  \(describePrice(m))"
    case .contextDesc:
        return "\(base)  ·  \(describeContext(m)) ctx"
    case .newest:
        return base
    }
}

struct SettingsView: View {
    @EnvironmentObject var store: PresetStore
    @State private var models: [OpenRouterModel] = []
    @State private var modelsLoading = false
    @State private var modelsError: String?
    @State private var search = ""
    @State private var editorTarget: EditorTarget?
    @State private var defaultModelFilter = ""
    @State private var defaultModelSort: ModelSort = .name

    var body: some View {
        TabView {
            actionsTab
                .padding(20)
                .tabItem { Label("Actions", systemImage: "bolt.fill") }

            openRouterTab
                .padding(20)
                .tabItem { Label("OpenRouter", systemImage: "network") }
        }
        .frame(width: 540, height: 460)
        .task { await loadModels() }
        .sheet(item: $editorTarget) { target in
            if let idx = store.presets.firstIndex(where: { $0.id == target.id }) {
                PresetEditor(preset: bindingForPreset(at: idx),
                             onClose: { editorTarget = nil },
                             onDelete: {
                                 if let p = store.presets.first(where: { $0.id == target.id }) {
                                     store.remove(p)
                                 }
                                 editorTarget = nil
                             })
                .environmentObject(store)
                .frame(minWidth: 540, minHeight: 540)
            } else {
                VStack {
                    Text("Action no longer exists.").foregroundStyle(.secondary)
                    Button("Close") { editorTarget = nil }
                }
                .padding(40)
            }
        }
    }

    // MARK: - Actions tab

    private var actionsTab: some View {
        VStack(alignment: .leading, spacing: 8) {
            listHeader
            ScrollView {
                actionList
                    .padding(.bottom, 4)
            }
        }
    }

    private var listHeader: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.tertiary)
                TextField("Search", text: $search)
                    .textFieldStyle(.plain)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color(NSColor.controlBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(NSColor.separatorColor)))

            Spacer()
            Button {
                let new = Preset(name: "New Action", prompt: Preset.defaultPrompt, model: store.defaultModel, hotkey: nil)
                store.presets.append(new)
                store.save()
                editorTarget = EditorTarget(id: new.id)
            } label: {
                Label("Add Action", systemImage: "plus")
            }
            .controlSize(.regular)
        }
    }

    private var filteredPresets: [Preset] {
        guard !search.isEmpty else { return store.presets }
        let q = search.lowercased()
        return store.presets.filter {
            $0.name.lowercased().contains(q) || $0.model.lowercased().contains(q)
        }
    }

    @ViewBuilder
    private var actionList: some View {
        if filteredPresets.isEmpty {
            HStack {
                Spacer()
                VStack(spacing: 6) {
                    Image(systemName: "tray").font(.title)
                        .foregroundStyle(.secondary)
                    Text(store.presets.isEmpty ? "No actions yet. Click Create Action."
                                               : "No matches for \"\(search)\"")
                        .foregroundStyle(.secondary)
                        .font(.callout)
                }
                Spacer()
            }
            .padding(.vertical, 30)
        } else {
            VStack(spacing: 8) {
                ForEach(filteredPresets) { preset in
                    ActionRow(preset: preset) {
                        editorTarget = EditorTarget(id: preset.id)
                    }
                }
            }
        }
    }

    // MARK: - OpenRouter tab

    private var openRouterTab: some View {
        Form {
            Section {
                AccessibilityStatusRow()
            } header: {
                Text("Permissions")
            }

            Section {
                SecureField("API Key", text: Binding(
                    get: { store.apiKey },
                    set: { store.updateAPIKey($0) }
                ))
            } header: {
                Text("API Key")
            } footer: {
                Text("Stored in this app's preferences. Get a key at openrouter.ai/keys.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section {
                Picker("Model", selection: Binding(
                    get: { store.defaultModel },
                    set: { store.updateDefaultModel($0) }
                )) {
                    if !models.contains(where: { $0.id == store.defaultModel }) {
                        Text(store.defaultModel).tag(store.defaultModel)
                    }
                    ForEach(filteredDefaultModels) { m in
                        Text(modelMenuLabel(m, sort: defaultModelSort)).tag(m.id)
                    }
                }

                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.tertiary)
                    TextField("Search models", text: $defaultModelFilter)
                        .textFieldStyle(.plain)
                    if !defaultModelFilter.isEmpty {
                        Button { defaultModelFilter = "" } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                        }
                        .buttonStyle(.plain)
                    }
                    Divider().frame(height: 16)
                    Menu {
                        Picker("Sort by", selection: $defaultModelSort) {
                            ForEach(ModelSort.allCases) { s in
                                Text(s.title).tag(s)
                            }
                        }
                    } label: {
                        Label("Sort: \(defaultModelSort.title)", systemImage: "arrow.up.arrow.down")
                            .font(.caption)
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    Button {
                        Task { await loadModels() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.borderless)
                    .help("Refresh models list")
                }
            } header: {
                Text("Default Model")
            } footer: {
                VStack(alignment: .leading, spacing: 2) {
                    if modelsLoading {
                        HStack { ProgressView().controlSize(.small); Text("Loading…") }
                    } else if let err = modelsError {
                        Text(err).foregroundStyle(.red)
                    } else {
                        Text("\(models.count) models. Price shown as $/1M tokens (in / out).")
                    }
                    Text("This model is used for every action.")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(.top, 4)
    }

    private var filteredDefaultModels: [OpenRouterModel] {
        var list = models
        if !defaultModelFilter.isEmpty {
            let q = defaultModelFilter.lowercased()
            list = list.filter { ($0.name ?? "").lowercased().contains(q) || $0.id.lowercased().contains(q) }
        }
        return sortModels(list, by: defaultModelSort)
    }

    // MARK: - helpers

    private func bindingForPreset(at index: Int) -> Binding<Preset> {
        Binding(
            get: { store.presets[index] },
            set: { store.update($0) }
        )
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

// MARK: - Row

struct ActionRow: View {
    let preset: Preset
    let onOpen: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 10) {
                Image(systemName: "sparkle")
                    .foregroundStyle(.tint)
                    .frame(width: 18)
                Text(preset.name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.primary)
                Spacer()
                shortcutBadge
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(hover
                          ? Color(NSColor.controlBackgroundColor).opacity(0.7)
                          : Color(NSColor.controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color(NSColor.separatorColor), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }

    @ViewBuilder
    private var shortcutBadge: some View {
        if let hk = preset.hotkey {
            Text(shortcutString(hk))
                .font(.system(size: 11, design: .monospaced))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(RoundedRectangle(cornerRadius: 5).fill(Color(NSColor.windowBackgroundColor)))
                .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color(NSColor.separatorColor)))
        } else {
            Text("No shortcut")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
    }
}

struct AccessibilityStatusRow: View {
    @State private var trusted: Bool = AccessibilityCheck.isGranted()
    @State private var timer: Timer?
    @State private var showingResetHint = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: trusted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(trusted ? .green : .orange)
                    .imageScale(.large)
                VStack(alignment: .leading, spacing: 2) {
                    Text(trusted ? "Accessibility access granted" : "Accessibility access required")
                        .font(.system(size: 13, weight: .medium))
                    Text(trusted
                         ? "caip can read your selection and paste results."
                         : "caip needs this to send ⌘C and ⌘V on your behalf.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if trusted {
                    Button("Re-check") { recheck() }
                        .controlSize(.small)
                } else {
                    Button("Open System Settings") {
                        openAccessibilityPane()
                    }
                    Menu {
                        Button("Re-check now") { recheck() }
                        Divider()
                        Button("Reset & re-grant…") { showingResetHint = true }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }
            }
            if !trusted {
                Text("If caip is already toggled on in the list but this still shows orange, the binary signature changed (ad-hoc rebuild). Use **Reset & re-grant** to clear and re-add.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onAppear { startPolling() }
        .onDisappear { stopPolling() }
        .alert("Reset Accessibility entry?", isPresented: $showingResetHint) {
            Button("Cancel", role: .cancel) {}
            Button("Reset", role: .destructive) { resetAndReopen() }
        } message: {
            Text("This runs `tccutil reset Accessibility net.variant.caip` and reopens the Accessibility pane so you can re-add caip. macOS will prompt for your password.")
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

    private func recheck() {
        trusted = AccessibilityCheck.isGranted()
    }

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
    /// Functional check: try to read system-wide AX. AXIsProcessTrusted() can lie about
    /// stale TCC entries; this actually attempts to use AX.
    static func isGranted() -> Bool {
        if !AXIsProcessTrusted() { return false }
        let system = AXUIElementCreateSystemWide()
        var focused: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focused)
        // .success or .noValue both indicate we *can* query the AX tree
        return result == .success || result == .noValue
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

// MARK: - Editor sheet

struct PresetEditor: View {
    @Binding var preset: Preset
    let onClose: () -> Void
    let onDelete: () -> Void

    @EnvironmentObject var store: PresetStore
    @State private var draft: Preset

    init(preset: Binding<Preset>,
         onClose: @escaping () -> Void,
         onDelete: @escaping () -> Void) {
        self._preset = preset
        self.onClose = onClose
        self.onDelete = onDelete
        self._draft = State(initialValue: preset.wrappedValue)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("AI Action").font(.title3.weight(.semibold))
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 8)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    field("Title") {
                        TextField("Name", text: $draft.name)
                            .textFieldStyle(.roundedBorder)
                    }

                    field("Prompt") {
                        TextEditor(text: $draft.prompt)
                            .font(.system(.body, design: .monospaced))
                            .frame(minHeight: 180)
                            .padding(6)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color(NSColor.textBackgroundColor))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .strokeBorder(Color(NSColor.separatorColor))
                            )
                        Text("Use {selectedText} or {s} to insert the selected text.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    field("Shortcut") {
                        HotkeyRecorder(hotkey: $draft.hotkey)
                            .frame(width: 200, height: 26)
                    }
                }
                .padding(20)
            }

            Divider()

            HStack {
                Button(role: .destructive) {
                    onDelete()
                } label: { Text("Delete") }

                Spacer()

                Button("Cancel") { onClose() }
                    .keyboardShortcut(.cancelAction)

                Button("Save") {
                    preset = draft
                    store.update(draft)
                    onClose()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
    }

    @ViewBuilder
    private func field(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
            content()
        }
    }
}
