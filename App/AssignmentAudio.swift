import AVFoundation
import SwiftUI

@MainActor
final class AssignmentSpeech: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    enum State: Equatable {
        case idle
        case playing
        case paused
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var error: String?

    private let synthesizer = AVSpeechSynthesizer()
    private var current: ObjectIdentifier?

    override init() {
        super.init()
        synthesizer.usesApplicationAudioSession = false
        synthesizer.delegate = self
    }

    func toggle(_ assignment: String) {
        switch state {
        case .idle:
            error = nil
            let voice = AVSpeechSynthesisVoice(language: "ru-RU")
                ?? AVSpeechSynthesisVoice.speechVoices().first { $0.language.hasPrefix("ru-") }
            guard let voice else {
                error = "Русский голос недоступен. Добавь его в настройках озвучивания iPhone."
                return
            }
            let utterance = AVSpeechUtterance(string: assignment)
            utterance.voice = voice
            utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.9
            current = ObjectIdentifier(utterance)
            state = .playing
            synthesizer.speak(utterance)
        case .playing:
            if synthesizer.pauseSpeaking(at: .immediate) { state = .paused }
        case .paused:
            if synthesizer.continueSpeaking() { state = .playing }
        }
    }

    func stop() {
        guard current != nil else { return }
        current = nil
        state = .idle
        synthesizer.stopSpeaking(at: .immediate)
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        finish(ObjectIdentifier(utterance))
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        finish(ObjectIdentifier(utterance))
    }

    private nonisolated func finish(_ utterance: ObjectIdentifier) {
        Task { @MainActor [weak self] in
            guard let self, self.current == utterance else { return }
            self.current = nil
            self.state = .idle
        }
    }
}

@MainActor
struct AssignmentAudio: View {
    let text: String
    @ObservedObject var speech: AssignmentSpeech

    private var control: (title: String, icon: String) {
        switch speech.state {
        case .idle: return ("Прослушать задание", "speaker.wave.2")
        case .playing: return ("Пауза", "pause.fill")
        case .paused: return ("Продолжить", "play.fill")
        }
    }

    var body: some View {
        Button {
            speech.toggle(text)
        } label: {
            Label(control.title, systemImage: control.icon)
        }
        if speech.state != .idle {
            Button {
                speech.stop()
            } label: {
                Label("Остановить", systemImage: "stop.fill")
            }
        }
        if let error = speech.error {
            Text(error)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}
