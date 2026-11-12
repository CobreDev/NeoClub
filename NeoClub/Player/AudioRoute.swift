import AVFoundation
import UIKit

/// The current audio output, with the glyph Apple Music shows for it on its AirPlay button: AirPods for AirPods,
/// a car for CarPlay, a HomePod for a HomePod, and the plain AirPlay glyph for the phone's own speaker.
struct AudioRoute: Equatable {
    let name: String
    let symbol: String
    /// The phone's own speaker or earpiece (Apple Music shows no label under the button then).
    let isBuiltIn: Bool

    /// The name to show under the button, if any.
    var label: String? { isBuiltIn ? nil : name }

    static var current: AudioRoute {
        guard let out = AVAudioSession.sharedInstance().currentRoute.outputs.first else {
            return AudioRoute(name: "iPhone", symbol: airPlay, isBuiltIn: true)
        }
        let builtIn = out.portType == .builtInSpeaker || out.portType == .builtInReceiver
        return AudioRoute(name: out.portName, symbol: builtIn ? airPlay : symbol(for: out), isBuiltIn: builtIn)
    }

    static let airPlay = available("airplay.audio", "airplayaudio")

    /// iOS doesn't say which AirPods (or speaker) a route is, only its type and name, so the model is read from the
    /// name the way it comes out of the box ("Cooper's AirPods Pro"); renamed devices get the generic glyph.
    private static func symbol(for out: AVAudioSessionPortDescription) -> String {
        let name = out.portName.lowercased()
        switch out.portType {
        case .bluetoothA2DP, .bluetoothHFP, .bluetoothLE:
            if name.contains("airpods max") { return available("airpods.max", "airpodsmax", "headphones") }
            if name.contains("airpods pro") { return available("airpods.pro", "headphones") }
            if name.contains("airpods") { return available("airpods.gen3", "airpods", "headphones") }
            if name.contains("beats") { return available("beats.headphones", "headphones") }
            if name.contains("homepod") { return homePod(name) }
            return "headphones"
        case .headphones, .usbAudio:
            return "headphones"
        case .carAudio:
            return "car.fill"
        case .airPlay:
            if name.contains("homepod") { return homePod(name) }
            if name.contains("tv") { return available("appletv.fill", airPlay) }
            return available("hifispeaker.fill", airPlay)
        case .HDMI:
            return available("tv", airPlay)
        default:
            return airPlay
        }
    }

    private static func homePod(_ name: String) -> String {
        name.contains("mini") ? available("homepod.mini.fill", "homepod.fill", airPlay) : available("homepod.fill", airPlay)
    }

    /// The first of these SF Symbols this iOS has.
    private static func available(_ names: String...) -> String {
        names.first { UIImage(systemName: $0) != nil } ?? "airplayaudio"
    }
}
