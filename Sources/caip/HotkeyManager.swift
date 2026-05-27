import AppKit
import Carbon.HIToolbox

final class HotkeyManager {
    private var refs: [UUID: EventHotKeyRef] = [:]
    private var handlers: [UInt32: (UUID, () -> Void)] = [:]
    private var nextId: UInt32 = 1
    private var eventHandler: EventHandlerRef?
    private let signature: OSType = OSType(0x63616970) // 'caip'

    init() {
        installHandler()
    }

    deinit {
        if let handler = eventHandler {
            RemoveEventHandler(handler)
        }
    }

    private func installHandler() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetEventDispatcherTarget(), { (_, event, userData) -> OSStatus in
            guard let event = event, let userData = userData else { return noErr }
            var hkID = EventHotKeyID()
            let status = GetEventParameter(event,
                                           EventParamName(kEventParamDirectObject),
                                           EventParamName(typeEventHotKeyID),
                                           nil,
                                           MemoryLayout<EventHotKeyID>.size,
                                           nil,
                                           &hkID)
            if status == noErr {
                let mgr = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
                mgr.dispatch(id: hkID.id)
            }
            return noErr
        }, 1, &spec, selfPtr, &eventHandler)
    }

    private func dispatch(id: UInt32) {
        guard let entry = handlers[id] else { return }
        DispatchQueue.main.async { entry.1() }
    }

    func register(id: UUID, keyCode: UInt32, modifiers: UInt32, action: @escaping () -> Void) {
        let hotkeyID = EventHotKeyID(signature: signature, id: nextId)
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(keyCode, modifiers, hotkeyID, GetEventDispatcherTarget(), 0, &ref)
        guard status == noErr, let ref = ref else { return }
        refs[id] = ref
        handlers[nextId] = (id, action)
        nextId += 1
    }

    func unregisterAll() {
        for (_, ref) in refs {
            UnregisterEventHotKey(ref)
        }
        refs.removeAll()
        handlers.removeAll()
    }
}
