import AppKit
import SwiftUI

@MainActor
enum Toast {
    private static var panel: NSPanel?
    private static var dismissTask: Task<Void, Never>?

    static func show(title: String, body message: String? = nil, icon: String = "exclamationmark.triangle.fill", tint: Color = .orange, duration: TimeInterval = 2.4) {
        dismissTask?.cancel()
        let view = ToastView(title: title, message: message, icon: icon, tint: tint)
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: 360, height: message == nil ? 64 : 84)

        let p: NSPanel
        if let existing = panel {
            existing.contentView = host
            existing.setContentSize(host.frame.size)
            p = existing
        } else {
            p = NSPanel(contentRect: host.frame,
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
        }

        if let screen = NSScreen.main {
            let frame = screen.visibleFrame
            let x = frame.midX - host.frame.width / 2
            let y = frame.maxY - host.frame.height - 24
            p.setFrameOrigin(NSPoint(x: x, y: y))
        }
        p.orderFrontRegardless()

        dismissTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            await MainActor.run { dismiss() }
        }
    }

    static func dismiss() {
        panel?.orderOut(nil)
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
