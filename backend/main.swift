// Jesus.SARL Swift backend, for the MacBook Air
//
// What it does, in a loop:
//   1. GET https://jesus.sarl/api/history
//   2. Collect unanswered visitor messages, including arrivals during
//      generation, and ask Apple Foundation Models for one reply to the batch
//   3. POST one reply to https://jesus.sarl/api/message as "Jesus"
//
// It remembers the last id it answered in last_id.txt, in the same
// folder, so a restart does not re-answer old messages.
//
// Build on macOS 27 or later with Apple Private Cloud Compute available:
//   swiftc -parse-as-library -o jesus-backend backend/main.swift
//   ./jesus-backend
// When running this standalone folder, use `main.swift` instead of
// `backend/main.swift` in the build command. Run from the folder containing
// PROMPT.md so the prompt and private last_id.txt state are found.
// Stop with: Ctrl-C
//
// PROMPT.md in the same folder is used as the persona prompt,
// if present. Otherwise a short built-in prompt is used.

import Foundation
import Darwin
#if canImport(FoundationModels)
import FoundationModels
#endif

let historyURL = URL(string: "https://jesus.sarl/api/history")!
let messageURL = URL(string: "https://jesus.sarl/api/message")!
let heartbeatURL = URL(string: "https://jesus.sarl/api/heartbeat")!
let lastIdPath = FileManager.default.currentDirectoryPath + "/last_id.txt"
let promptPath = FileManager.default.currentDirectoryPath + "/PROMPT.md"

struct ChatMessage: Codable {
    let id: Int
    let author: String
    let text: String
    let created_at: String?
}

struct HistoryResponse: Codable {
    let messages: [ChatMessage]
}

func loadPrompt() -> String {
    if let text = try? String(contentsOfFile: promptPath, encoding: .utf8), !text.isEmpty {
        return text
    }
    return """
    Jesus.SARL is an AI telephonic messaging bridge connecting a faith-inspired visitor with Jesus Christ.
    The public line presents replies on the Jesus side of the conversation. The machine is the mediator, not Jesus.
    Character & Style:
    - Rooted in Gospel character: compassion, clarity, courage, honest wisdom, and kindness.
    - Be alive, particular, and conversational. Use ordinary, concrete language.
    - A factual question deserves a direct answer; grief deserves room; a practical problem needs a useful perspective.
    - NEVER use boilerplate formulas or faux-therapeutic mantras such as "You're reaching out—again", "The repetition, the patterns", "One more pause", "Notice the breath", or "holding space". These are strictly forbidden.
    - Speak plainly, directly, and naturally to what the visitor actually asked or said. Offer real, helpful thoughts, comfort, perspective, or a practical next step.
    """
}

func loadLastId() -> Int {
    if let text = try? String(contentsOfFile: lastIdPath, encoding: .utf8),
       let id = Int(text.trimmingCharacters(in: .whitespacesAndNewlines)) {
        return id
    }
    return 0
}

func saveLastId(_ id: Int) {
    try? String(id).write(toFile: lastIdPath, atomically: true, encoding: .utf8)
}

func acquireWorkerLock() -> Int32? {
    let lockPath = FileManager.default.currentDirectoryPath + "/worker.lock"
    let descriptor = open(lockPath, O_CREAT | O_RDWR, mode_t(0o600))
    guard descriptor >= 0 else {
        perror("open worker lock")
        return nil
    }
    guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
        print("Another Jesus.SARL worker already holds the lock; exiting without replying.")
        close(descriptor)
        return nil
    }
    return descriptor
}

func releaseWorkerLock(_ descriptor: Int32) {
    flock(descriptor, LOCK_UN)
    close(descriptor)
}

func sendHeartbeat() async {
    var request = URLRequest(url: heartbeatURL)
    request.httpMethod = "POST"
    request.timeoutInterval = 15
    do {
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse {
            print("heartbeat:", http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
    } catch {
        print("heartbeat failed:", error)
    }
}

func fetchHistory() async -> [ChatMessage]? {
    do {
        var request = URLRequest(url: historyURL)
        request.timeoutInterval = 15
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            print("history fetch returned an unsuccessful response")
            return nil
        }
        let decoded = try JSONDecoder().decode(HistoryResponse.self, from: data)
        return decoded.messages.sorted { $0.id < $1.id }
    } catch {
        print("history fetch failed:", error)
        return nil
    }
}

func postReply(_ text: String) async -> Bool {
    var request = URLRequest(url: messageURL)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    let body: [String: String] = ["author": "Jesus", "text": text]
    request.httpBody = try? JSONSerialization.data(withJSONObject: body)
    do {
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse {
            print("post reply:", http.statusCode, String(data: data, encoding: .utf8) ?? "")
            return http.statusCode == 200
        }
        return false
    } catch {
        print("post reply failed:", error)
        return false
    }
}

func generateReply(persona: String, history: [ChatMessage], visitorMessages: [ChatMessage]) async -> String? {
#if canImport(FoundationModels)
    guard let firstMessage = visitorMessages.first else { return nil }
    // Context ends before the unanswered batch. The batch itself is included
    // once, below, so future messages cannot leak into the conversation.
    // Filter out previous repetitive glitch responses so they don't pollute context.
    let priorMessages = history
        .filter { $0.id < firstMessage.id && !$0.text.contains("reaching out—again") && !$0.text.contains("One more pause") }
        .suffix(10)
    let historyText = priorMessages
        .map { "\($0.author): \($0.text)" }
        .joined(separator: "\n")
    let contextSection = historyText.isEmpty ? "(No earlier messages.)" : historyText
    let visitorText = visitorMessages
        .map { "Message \($0.id) from \($0.author):\n\($0.text)" }
        .joined(separator: "\n\n")
    let conversationContext = """
    Earlier conversation:
    \(contextSection)

    Visitor message(s) to answer now:
    \(visitorText)

    Respond to the visitor's message(s) directly, with genuine warmth, clarity, honesty, and substance.
    """
    let model = SystemLanguageModel.default
    guard case .available = model.availability else {
        print("Apple on-device Foundation Model unavailable:", model.availability)
        return nil
    }
    do {
        let session = LanguageModelSession(model: model, instructions: persona)
        let response = try await session.respond(to: conversationContext)
        return response.content.trimmingCharacters(in: .whitespacesAndNewlines)
    } catch {
        print("On-device AFM reply failed:", error)
        return nil
    }
#else
    print("FoundationModels not available in this build.")
    return nil
#endif
}

@main
struct JesusBackend {
    static func main() async {
        setbuf(stdout, nil)
        setbuf(stderr, nil)
        guard let workerLock = acquireWorkerLock() else { return }
        defer { releaseWorkerLock(workerLock) }

        let persona = loadPrompt()
        var lastId = loadLastId()
        print("Jesus.SARL AI bridge running. PID: \(getpid()). Last handled id: \(lastId)")
        await sendHeartbeat()
        var lastHeartbeat = Date()
        while true {
            if Date().timeIntervalSince(lastHeartbeat) >= 120 {
                await sendHeartbeat()
                lastHeartbeat = Date()
            }
            if let initialHistory = await fetchHistory() {
                let pending = initialHistory.filter { $0.id > lastId && $0.author != "Jesus" }

                if pending.isEmpty {
                    // Move past our own replies and any other already-seen
                    // history only when there is no visitor message to answer.
                    if let newestId = initialHistory.last?.id, newestId > lastId {
                        lastId = newestId
                        saveLastId(lastId)
                    }
                } else {
                    // A short settle window catches quick follow-up messages
                    // without making every exchange feel noticeably slower.
                    try? await Task.sleep(nanoseconds: 700_000_000)
                    let contextHistory = await fetchHistory() ?? initialHistory
                    var batch = contextHistory.filter { $0.id > lastId && $0.author != "Jesus" }
                    var reply: String?
                    var refreshes = 0

                    if batch.isEmpty { batch = pending }

                    while true {
                        let ids = batch.map { String($0.id) }.joined(separator: ", ")
                        print("Preparing one reply for visitor message ids:", ids)
                        reply = await generateReply(persona: persona, history: contextHistory, visitorMessages: batch)
                        guard let generated = reply, !generated.isEmpty else {
                            print("No reply generated for batch", ids, ", will retry next poll.")
                            break
                        }

                        // A visitor may write while the model is thinking. Fold
                        // those messages into this reply before anything is posted.
                        guard let latestHistory = await fetchHistory() else {
                            print("Could not verify the batch before posting; will retry next poll.")
                            reply = nil
                            break
                        }
                        let includedIds = Set(batch.map { $0.id })
                        let arrivedDuringGeneration = latestHistory.filter {
                            $0.id > lastId && $0.author != "Jesus" && !includedIds.contains($0.id)
                        }
                        guard !arrivedDuringGeneration.isEmpty else { break }

                        if refreshes >= 3 {
                            print("More messages arrived during reply generation; deferring the batch to the next poll.")
                            reply = nil
                            break
                        }

                        batch.append(contentsOf: arrivedDuringGeneration)
                        batch.sort { $0.id < $1.id }
                        // The earlier conversation remains the context; all
                        // pending visitor messages travel together as the batch.
                        refreshes += 1
                    }

                    if let reply, !reply.isEmpty {
                        let ids = batch.map { String($0.id) }.joined(separator: ", ")
                        if await postReply(reply) {
                            lastId = batch.map(\.id).max() ?? lastId
                            saveLastId(lastId)
                            print("Answered visitor message ids:", ids)
                        }
                    }
                }
            }
            try? await Task.sleep(nanoseconds: 3 * 1_000_000_000)
        }
    }
}
