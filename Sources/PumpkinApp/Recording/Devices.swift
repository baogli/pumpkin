// Adapted from baogli/able-recorder (MIT); see THIRD_PARTY_NOTICES.md.
import AppKit
import CoreAudio
import AudioToolbox

struct RecorderError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

struct InputDevice {
    let id: AudioDeviceID
    let uid: String
    let name: String
    let channels: Int
    let rate: Double
    var isAudient: Bool { name.lowercased().contains("audient") || name.lowercased().contains("id14") }
}

enum Devices {
    static func string(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr else { return "" }
        return value?.takeRetainedValue() as String? ?? ""
    }
    static func rate(_ id: AudioDeviceID) -> Double {
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyNominalSampleRate, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var value: Double = 0; var size = UInt32(MemoryLayout<Double>.size)
        AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value)
        return value
    }
    static func alive(_ id: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyDeviceIsAlive, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var value: UInt32 = 0; var size: UInt32 = 4
        return AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr && value != 0
    }
    static func inputs() -> [InputDevice] {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &ids) == noErr else { return [] }
        return ids.compactMap { id in
            var addr = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreamConfiguration, mScope: kAudioDevicePropertyScopeInput, mElement: kAudioObjectPropertyElementMain)
            var bytes: UInt32 = 0
            guard AudioObjectGetPropertyDataSize(id, &addr, 0, nil, &bytes) == noErr, bytes > 0 else { return nil }
            let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(bytes), alignment: MemoryLayout<AudioBufferList>.alignment)
            defer { raw.deallocate() }
            guard AudioObjectGetPropertyData(id, &addr, 0, nil, &bytes, raw) == noErr else { return nil }
            let list = UnsafeMutableAudioBufferListPointer(raw.assumingMemoryBound(to: AudioBufferList.self))
            let channels = list.reduce(0) { $0 + Int($1.mNumberChannels) }
            guard channels > 0 else { return nil }
            return InputDevice(id: id, uid: string(id, kAudioDevicePropertyDeviceUID), name: string(id, kAudioObjectPropertyName), channels: channels, rate: rate(id))
        }.sorted { a, b in a.isAudient != b.isAudient ? a.isAudient : a.name < b.name }
    }
}
