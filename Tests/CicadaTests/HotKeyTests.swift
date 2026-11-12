import AppKit
import Carbon.HIToolbox
import Testing
@testable import Cicada

/// Deliver only in-process Carbon events: no physical key injection or audio capture.
@Suite(.serialized) struct HotKeyTests {
    @MainActor private func send(_ kind: UInt32, id: UInt32) throws -> OSStatus {
        var raw: EventRef?
        #expect(CreateEvent(nil, OSType(kEventClassKeyboard), kind, GetCurrentEventTime(), 0, &raw) == noErr)
        let event = try #require(raw)
        defer { ReleaseEvent(event) }
        var identifier = EventHotKeyID(signature: OSType(0x4C535542), id: id)
        #expect(SetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                  MemoryLayout<EventHotKeyID>.size, &identifier) == noErr)
        return SendEventToEventTarget(event, GetApplicationEventTarget())
    }

    @MainActor @Test func multipleHandlersRouteToTheMatchingID() throws {
        _ = NSApplication.shared
        let first = HotKey(id: 101, shortcut: .defaultTalk)
        let second = HotKey(id: 102, shortcut: .defaultToggle)
        let dictation = HotKey(id: 103, shortcut: .defaultDictation)
        var downs: [UInt32] = []
        var ups: [UInt32] = []
        first.onDown = { downs.append(101) }
        second.onDown = { downs.append(102) }
        dictation.onDown = { downs.append(103) }
        first.onUp = { ups.append(101) }
        second.onUp = { ups.append(102) }
        dictation.onUp = { ups.append(103) }
        for id: UInt32 in [101, 102, 103] {
            #expect(try send(UInt32(kEventHotKeyPressed), id: id) == noErr)
            #expect(try send(UInt32(kEventHotKeyReleased), id: id) == noErr)
        }
        #expect(downs == [101, 102, 103])
        #expect(ups == [101, 102, 103])
        withExtendedLifetime((first, second, dictation)) {}
    }

    @MainActor @Test func unknownIDDoesNotInvokeAnotherShortcut() throws {
        _ = NSApplication.shared
        let hotkey = HotKey(id: 104, shortcut: .defaultDictation)
        var calls = 0
        hotkey.onDown = { calls += 1 }
        hotkey.onUp = { calls += 1 }
        _ = try send(UInt32(kEventHotKeyPressed), id: 999)
        _ = try send(UInt32(kEventHotKeyReleased), id: 999)
        #expect(calls == 0)
        withExtendedLifetime(hotkey) {}
    }

    @MainActor @Test func separatePressReleaseCyclesRemainUsable() throws {
        _ = NSApplication.shared
        let hotkey = HotKey(id: 105, shortcut: .defaultDictation)
        var downs = 0
        var ups = 0
        hotkey.onDown = { downs += 1 }
        hotkey.onUp = { ups += 1 }
        for _ in 0..<3 {
            _ = try send(UInt32(kEventHotKeyPressed), id: 105)
            _ = try send(UInt32(kEventHotKeyReleased), id: 105)
        }
        #expect(downs == 3)
        #expect(ups == 3)
        withExtendedLifetime(hotkey) {}
    }
}
