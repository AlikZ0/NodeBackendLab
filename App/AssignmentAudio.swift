import AVFoundation
import SwiftUI
import UIKit

@MainActor
final class AssignmentSpeech: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    enum State: Equatable {
        case idle
        case playing
        case paused
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var error: String?
    @Published private(set) var section: String?

    private let synthesizer = AVSpeechSynthesizer()
    private var current: ObjectIdentifier?

    override init() {
        super.init()
        synthesizer.usesApplicationAudioSession = false
        synthesizer.delegate = self
    }

    func toggle(_ assignment: String, section: String) {
        if self.section != section { stop() }
        switch state {
        case .idle:
            self.section = section
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
        let wasSpeaking = current != nil
        current = nil
        section = nil
        error = nil
        state = .idle
        if wasSpeaking { synthesizer.stopSpeaking(at: .immediate) }
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
            self.section = nil
            self.state = .idle
        }
    }
}

@MainActor
struct LessonTextActions: View {
    let title: String
    let text: String
    @ObservedObject var speech: AssignmentSpeech

    private var control: (title: String, icon: String) {
        switch speech.section == title ? speech.state : .idle {
        case .idle: return ("Прослушать", "speaker.wave.2")
        case .playing: return ("Пауза", "pause.fill")
        case .paused: return ("Продолжить", "play.fill")
        }
    }

    var body: some View {
        Button {
            speech.toggle(text, section: title)
        } label: {
            Label(control.title, systemImage: control.icon)
        }
        .accessibilityHint(title)
        Button {
            UIPasteboard.general.string = text
            UIAccessibility.post(notification: .announcement, argument: "Скопировано")
        } label: {
            Label("Копировать", systemImage: "doc.on.doc")
        }
        .accessibilityHint(title)
        if speech.section == title && speech.state != .idle {
            Button {
                speech.stop()
            } label: {
                Label("Остановить", systemImage: "stop.fill")
            }
        }
        if speech.section == title, let error = speech.error {
            Text(error)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}
