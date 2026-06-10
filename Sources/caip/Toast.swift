import AppKit
import SwiftUI

@MainActor
enum Toast {
    private static var panel: NSPanel?
    private static var dismissTask: Task<Void, Never>?

    enum Position { case topCenter, topRight, bottomRight }

    static func show(title: String, body message: String? = nil, icon: String = "exclamationmark.triangle.fill", tint: Color = .orange, duration: TimeInterval = 2.4) {
        let host = NSHostingView(rootView: ToastView(title: title, message: message, icon: icon, tint: tint))
        host.frame = NSRect(x: 0, y: 0, width: 360, height: message == nil ? 64 : 84)
        present(host: host, position: .topCenter, sticky: false, duration: duration)
    }

    /// Compact pill that stays up while a prompt runs. Lives top-right, where the
    /// menubar icon would be — a stand-in for people who hide the menubar.
    static func showProgress(title: String) {
        let host = fittingHost(ProgressPill(title: title, icon: "sparkle", tint: .accentColor, pulsing: true))
        present(host: host, position: .topRight, sticky: true, duration: 0)
    }

    static func resolveProgress(title: String = "Done") {
        let host = fittingHost(ProgressPill(title: title, icon: "checkmark.circle.fill", tint: .green, pulsing: false))
        present(host: host, position: .topRight, sticky: false, duration: 0.9)
    }

    static func dismiss() {
        dismissTask?.cancel()
        panel?.orderOut(nil)
    }

    private static func fittingHost<V: View>(_ view: V) -> NSHostingView<V> {
        let host = NSHostingView(rootView: view)
        host.layoutSubtreeIfNeeded()
        host.frame = NSRect(origin: .zero, size: host.fittingSize)
        return host
    }

    private static func present(host: NSView, position: Position, sticky: Bool, duration: TimeInterval) {
        dismissTask?.cancel()

        // Build a fresh panel each time. Reusing one and resizing/swapping its SwiftUI
        // host re-runs constraint updates on a borderless window and AppKit throws
        // (NSWindow _postWindowNeedsUpdateConstraints) — crashes on the second toast.
        panel?.orderOut(nil)
        let p = NSPanel(contentRect: host.frame,
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered,
                        defer: false)
        p.isFloatingPanel = true
        p.level = .floating
        p.hidesOnDeactivate = false
        p.becomesKeyOnlyIfNeeded = true
        p.backgroundColor = .clear
        p.isOpaque = false
        p.hasShadow = true
        p.contentView = host
        panel = p

        if let screen = NSScreen.main {
            let f = screen.visibleFrame
            let w = host.frame.width, h = host.frame.height
            let origin: NSPoint
            switch position {
            case .topCenter:   origin = NSPoint(x: f.midX - w / 2, y: f.maxY - h - 24)
            case .topRight:    origin = NSPoint(x: f.maxX - w - 16, y: f.maxY - h - 8)
            case .bottomRight: origin = NSPoint(x: f.maxX - w - 16, y: f.minY + 24)
            }
            p.setFrameOrigin(origin)
        }
        p.orderFrontRegardless()

        if !sticky {
            dismissTask = Task {
                try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
                await MainActor.run { dismiss() }
            }
        }
    }
}

private struct ProgressPill: View {
    let title: String
    let icon: String
    let tint: Color
    let pulsing: Bool
    @State private var dim = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(tint)
                .font(.system(size: 13, weight: .semibold))
                .opacity(pulsing && dim ? 0.35 : 1)
                .animation(pulsing ? .easeInOut(duration: 0.7).repeatForever(autoreverses: true) : .default, value: dim)
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(Capsule().fill(.regularMaterial))
        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.08), lineWidth: 1))
        .padding(4)
        .onAppear { if pulsing { dim = true } }
    }
}

private struct ToastView: View {
    let title: String
    let message: String?
    let icon: String
    let tint: Color

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(tint)
                .font(.system(size: 18, weight: .semibold))
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                if let message = message {
                    Text(message)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.regularMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .padding(2)
    }
}
