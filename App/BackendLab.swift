import SwiftUI
import WebKit

struct Lesson: Codable, Identifiable {
    let id: String
    let title: String
    let minutes: Int
    let theory: String
    let explanation: String
    let expectedResult: String
    let sampleCode: String
    let task: String
    let starter: String
    let hint: String
    let cases: [TestCase]
    let terminal: String?
    let module: String?
    let node: NodeLab?
}

struct TestCase: Codable {
    let args: [JSONValue]
    let expected: JSONValue
}

enum JSONValue: Codable {
    case null, bool(Bool), number(Double), string(String), array([JSONValue]), object([String: JSONValue])

    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer()
        if value.decodeNil() { self = .null }
        else if let bool = try? value.decode(Bool.self) { self = .bool(bool) }
        else if let number = try? value.decode(Double.self) { self = .number(number) }
        else if let string = try? value.decode(String.self) { self = .string(string) }
        else if let array = try? value.decode([JSONValue].self) { self = .array(array) }
        else { self = .object(try value.decode([String: JSONValue].self)) }
    }

    func encode(to encoder: Encoder) throws {
        var value = encoder.singleValueContainer()
        switch self {
        case .null: try value.encodeNil()
        case .bool(let bool): try value.encode(bool)
        case .number(let number): try value.encode(number)
        case .string(let string): try value.encode(string)
        case .array(let array): try value.encode(array)
        case .object(let object): try value.encode(object)
        }
    }
}

struct Check: Codable {
    let ok: Bool
    let message: String
}

@MainActor
final class Runner: NSObject, ObservableObject, WKNavigationDelegate {
    @Published private(set) var ready = false
    @Published private(set) var problem: String?
    private let browser = WKWebView()

    init(enabled: Bool) {
        super.init()
        guard enabled else { return }
        browser.navigationDelegate = self
        guard let html = Bundle.main.url(forResource: "Runner", withExtension: "html") else {
            problem = "Не найден файл среды выполнения."
            return
        }
        browser.loadFileURL(html, allowingReadAccessTo: html)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        ready = true
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        problem = error.localizedDescription
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        problem = error.localizedDescription
    }

    func check(code: String, cases: [TestCase]) async throws -> [Check] {
        let encoded = try JSONEncoder().encode(cases)
        let args = try JSONSerialization.jsonObject(with: encoded)
        let result = try await browser.callAsyncJavaScript(
            "return await runLesson(code, cases);",
            arguments: ["code": code, "cases": args],
            in: nil,
            contentWorld: .page
        )
        guard let rows = result as? [[String: Any]] else { throw CocoaError(.coderReadCorrupt) }
        return try JSONDecoder().decode([Check].self, from: JSONSerialization.data(withJSONObject: rows))
    }
}

@main
struct BackendLabApp: App {
    private let lessons: [Lesson]

    init() {
        if let url = Bundle.main.url(forResource: "Lessons", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode([Lesson].self, from: data) {
            lessons = decoded
        } else {
            lessons = []
        }
    }

    var body: some Scene {
        WindowGroup { CourseView(lessons: lessons) }
    }
}

struct CourseView: View {
    let lessons: [Lesson]
    @AppStorage("done") private var done = ""
    @State private var token = ""
    private var modules: [String] {
        lessons.reduce(into: []) { modules, lesson in
            let name = lesson.module ?? "JavaScript для API"
            if !modules.contains(name) { modules.append(name) }
        }
    }
    private var completed: Set<String> { Set(done.split(separator: ",").map(String.init)) }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("От React к backend").font(.title2.bold())
                        Text("Изучай все уроки без подключения. Для автоматической проверки лабораторных Node.js можно подключить Ubuntu.")
                            .foregroundStyle(.secondary)
                        ProgressView(value: Double(lessons.filter { completed.contains($0.id) }.count),
                                     total: Double(max(lessons.count, 1)))
                        Text("Пройдено \(lessons.filter { completed.contains($0.id) }.count) из \(lessons.count)")
                            .font(.caption.monospacedDigit())
                    }.padding(.vertical, 8)
                }
                if lessons.isEmpty { Text("Не удалось загрузить уроки.") }
                ForEach(modules, id: \.self) { module in
                    Section(module) {
                        ForEach(lessons.filter { ($0.module ?? "JavaScript для API") == module }) { lesson in
                            NavigationLink {
                                LessonView(lesson: lesson, completed: completed.contains(lesson.id), token: $token) {
                                    done = completed.union([lesson.id]).sorted().joined(separator: ",")
                                }
                            } label: {
                                Label {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(lesson.title)
                                        Text("\(lesson.minutes) мин").font(.caption).foregroundStyle(.secondary)
                                    }
                                } icon: {
                                    Image(systemName: completed.contains(lesson.id) ? "checkmark.circle.fill" : "terminal")
                                        .foregroundStyle(completed.contains(lesson.id) ? Color.green : Color.accentColor)
                                }.padding(.vertical, 4)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Node Backend Lab")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    NavigationLink {
                        ConnectionView(token: $token)
                    } label: {
                        Image(systemName: "desktopcomputer")
                            .accessibilityLabel("Подключить Ubuntu")
                    }
                }
            }
        }
    }
}

@MainActor
struct LessonView: View {
    let lesson: Lesson
    let completed: Bool
    let markDone: () -> Void
    @AppStorage private var code: String
    @AppStorage("runner.host") private var host = ""
    @Binding private var token: String
    @StateObject private var runner: Runner
    @StateObject private var assignmentSpeech = AssignmentSpeech()
    @State private var running = false
    @State private var results: [Check] = []
    @State private var error: String?
    @State private var nodeResult: NodeResult?

    init(lesson: Lesson, completed: Bool, token: Binding<String>, markDone: @escaping () -> Void) {
        self.lesson = lesson
        self.completed = completed
        self.markDone = markDone
        _token = token
        _runner = StateObject(wrappedValue: Runner(enabled: lesson.node == nil))
        _code = AppStorage(wrappedValue: lesson.starter, "code.\(lesson.id)")
    }

    private var passed: Bool {
        if lesson.node != nil { return nodeResult?.ok == true }
        return !lesson.cases.isEmpty && results.count == lesson.cases.count && results.allSatisfy(\.ok)
    }

    var body: some View {
        Form {
            Section("Теория") {
                lessonText("Теория", lesson.theory)
            }
            Section("Задание") {
                lessonText("Задание", lesson.task)
                DisclosureGroup("Подсказка") {
                    lessonText("Подсказка", lesson.hint)
                }
            }
            Section(lesson.node == nil ? "Редактор JavaScript" : "Редактор Node.js") {
                if lesson.node != nil {
                    Text("Без подключения можно написать решение и сверить его с разбором ниже.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                TextEditor(text: $code)
                    .font(.system(.body, design: .monospaced))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .frame(minHeight: 180)
                    .accessibilityLabel("Код решения")
                    .disabled(running)
                    .onChange(of: code) { _ in
                        results = []
                        nodeResult = nil
                        error = nil
                    }
                LessonTextActions(title: "Твой код", text: code, speech: assignmentSpeech)
                    .disabled(code.isEmpty)
                if let lab = lesson.node {
                    ShareLink(item: code + "\n\n" + lab.verification) {
                        Label("Поделиться кодом с тестами", systemImage: "square.and.arrow.up")
                    }
                    DisclosureGroup("Автопроверка через Ubuntu") {
                        NavigationLink("Настроить подключение") { ConnectionView(token: $token) }
                        checkButton
                    }
                } else {
                    checkButton
                }
            }
            if let report = verificationReport {
                Section("Результат проверки") {
                    lessonText("Результат проверки", report)
                }
            }
            Section("Разбор решения") {
                DisclosureGroup("Показать разбор и пример") {
                    lessonText("Объяснение решения", lesson.explanation)
                    Text("Ожидаемый результат").font(.headline)
                    lessonText("Ожидаемый результат", lesson.expectedResult)
                    Text("Пример кода").font(.headline)
                    lessonText("Пример кода", lesson.sampleCode, monospaced: true)
                }
            }
            if let terminal = lesson.terminal {
                Section("Дополнительно на Ubuntu") {
                    lessonText("Команды для Ubuntu", terminal)
                }
            }
            Section {
                Button(completed ? "Урок пройден" : (passed ? "Отметить урок пройденным" : "Отметить после самопроверки"), action: markDone)
                    .disabled(completed || (!passed && lesson.node == nil))
                if lesson.node != nil && !completed && !passed {
                    Text("Эта отметка сохраняет прогресс. Для результата тестов запусти автопроверку.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .onDisappear { assignmentSpeech.stop() }
        .navigationTitle(lesson.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if assignmentSpeech.state != .idle {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        assignmentSpeech.stop()
                    } label: {
                        Label("Остановить озвучку", systemImage: "stop.circle")
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func lessonText(_ title: String, _ text: String, monospaced: Bool = false) -> some View {
        Text(text)
            .font(monospaced ? .system(.footnote, design: .monospaced) : .body)
            .textSelection(.enabled)
        LessonTextActions(title: title, text: text, speech: assignmentSpeech)
    }

    private var verificationReport: String? {
        if let problem = runner.problem ?? error { return problem }
        if let nodeResult {
            let summary = nodeResult.ok ? "Тесты пройдены." : "Проверка завершилась ошибкой."
            return nodeResult.output.isEmpty ? summary : summary + "\n\n" + nodeResult.output
        }
        guard !results.isEmpty else { return nil }
        let count = results.filter(\.ok).count
        let details = results.enumerated().map { index, check in
            "Тест \(index + 1). \(check.message)"
        }
        return (["Пройдено тестов: \(count) из \(lesson.cases.count)."] + details).joined(separator: "\n\n")
    }

    private var checkButton: some View {
        Button(running ? "Проверяем…" : "Проверить код") {
            running = true
            results = []
            nodeResult = nil
            error = nil
            let submitted = code
            Task {
                defer { running = false }
                do {
                    if let lab = lesson.node {
                        nodeResult = try await NodeRunner.check(code: submitted, lab: lab, host: host, token: token)
                    } else {
                        results = try await runner.check(code: submitted, cases: lesson.cases)
                    }
                } catch {
                    self.error = error.localizedDescription
                }
            }
        }.disabled((lesson.node == nil && !runner.ready) || running ||
                   code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }
}
