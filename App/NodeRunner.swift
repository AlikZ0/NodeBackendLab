import SwiftUI

struct NodeLab: Codable {
    let verification: String
}

private struct NodeSubmission: Encodable {
    let source: String
}

struct NodeResult: Decodable {
    let ok: Bool
    let output: String
}

private struct NodeRejection: Decodable {
    let error: String
}

enum NodeRunnerError: LocalizedError {
    case address, token, response, connection, rejected(String)

    var errorDescription: String? {
        switch self {
        case .address: return "Введи локальный IPv4-адрес Ubuntu, например 192.168.1.30."
        case .token: return "Вставь код подключения из терминала Ubuntu."
        case .response: return "Сервер вернул неожиданный ответ."
        case .connection: return "Ubuntu недоступен. Проверь IP, Wi-Fi, доступ к локальной сети в настройках iPhone и запущен ли Runner на порту 4377."
        case .rejected(let message): return message
        }
    }
}

private final class NoRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

enum NodeRunner {
    static func check(code: String, lab: NodeLab, host: String, token: String) async throws -> NodeResult {
        let address = host.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = address.split(separator: ".", omittingEmptySubsequences: false)
        let octets = parts.compactMap { UInt8($0) }
        guard parts.count == 4, octets.count == 4, octets.map({ String($0) }).joined(separator: ".") == address,
              octets[0] == 10 || (octets[0] == 192 && octets[1] == 168) ||
              (octets[0] == 172 && (16...31).contains(octets[1])),
              let url = URL(string: "http://\(address):4377/run") else {
            throw NodeRunnerError.address
        }
        let password = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard password.count == 48, password.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else {
            throw NodeRunnerError.token
        }

        var request = URLRequest(url: url, timeoutInterval: 18)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(password)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(NodeSubmission(source: code + "\n\n" + lab.verification))
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForResource = 20
        let session = URLSession(configuration: configuration, delegate: NoRedirects(), delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError where [
            .cannotConnectToHost, .cannotFindHost, .timedOut, .notConnectedToInternet, .networkConnectionLost
        ].contains(error.code) {
            throw NodeRunnerError.connection
        }
        guard let http = response as? HTTPURLResponse else { throw NodeRunnerError.response }
        if http.statusCode != 200 {
            let rejection = try? JSONDecoder().decode(NodeRejection.self, from: data)
            throw NodeRunnerError.rejected(rejection?.error ?? "HTTP \(http.statusCode)")
        }
        return try JSONDecoder().decode(NodeResult.self, from: data)
    }
}

struct ConnectionView: View {
    @AppStorage("runner.host") private var host = ""
    @Binding var token: String
    @State private var checking = false
    @State private var diagnostic: String?

    var body: some View {
        Form {
            Section("Подключение") {
                TextField("Локальный IPv4 Ubuntu", text: $host)
                    .keyboardType(.numbersAndPunctuation)
                    .autocorrectionDisabled()
                SecureField("Код из терминала", text: $token)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button(checking ? "Проверяем…" : "Проверить подключение") {
                    let address = host
                    let password = token
                    checking = true
                    diagnostic = nil
                    Task {
                        defer { checking = false }
                        do {
                            let result = try await NodeRunner.check(
                                code: "console.log(process.version);", lab: NodeLab(verification: ""),
                                host: address, token: password
                            )
                            diagnostic = result.ok ? "Подключено. Node.js: " + result.output : result.output
                        } catch {
                            diagnostic = error.localizedDescription
                        }
                    }
                }
                .disabled(checking)
                if let diagnostic { Text(diagnostic).textSelection(.enabled) }
            }
            Section("На Ubuntu") {
                Text("Подключи iPhone и компьютер к одной доверенной сети Wi-Fi. В папке проекта выполни команды и введи адрес и код из терминала. Код хранится до закрытия приложения.")
                Text("docker pull node:24-bookworm-slim\nhostname -I\nnode Runner/server.mjs 192.168.1.30")
                    .font(.system(.footnote, design: .monospaced))
                    .textSelection(.enabled)
                Text("В последней команде укажи адрес своего компьютера.")
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Запуск Node.js")
        .navigationBarTitleDisplayMode(.inline)
    }
}
