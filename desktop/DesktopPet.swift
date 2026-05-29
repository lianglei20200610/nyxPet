import Cocoa
import WebKit

struct SkillConfig: Decodable {
    let id: String
    let name: String
    let icon: String
    let command: String
    let args: [String]
    let timeoutSeconds: Double?
    let outputLimit: Int?
}

struct PetState: Codable {
    var mood: Int
    var weight: Int
    var hair: Int
    var money: Int
    var currentActivity: String

    static let initial = PetState(mood: 70, weight: 50, hair: 100, money: 0, currentActivity: "待机")
}

final class PetStateStore {
    private let stateURL: URL
    private(set) var state: PetState

    init(root: URL) {
        stateURL = root.appendingPathComponent("data/pet-state.json")
        state = Self.load(from: stateURL)
    }

    func apply(action: String) -> String {
        switch action {
        case "work":
            state.money += 50
            state.mood = clamp(state.mood - 4)
            state.hair = clamp(state.hair - 1)
            state.currentActivity = "工作"
            save()
            return "工作完成\n金币 +50\n心情 -4"
        case "meeting":
            state.money += 20
            state.mood = clamp(state.mood - 8)
            state.hair = clamp(state.hair - 2)
            state.currentActivity = "开会"
            save()
            return "会议结束\n金币 +20\n心情 -8，发量 -2"
        default:
            return "未知行动\n\(action)"
        }
    }

    func save() {
        do {
            try FileManager.default.createDirectory(
                at: stateURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try JSONEncoder.prettyPrinted.encode(state)
            try data.write(to: stateURL, options: .atomic)
        } catch {
            print("Failed to save pet state: \(error)")
        }
    }

    private static func load(from url: URL) -> PetState {
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(PetState.self, from: data)
        } catch {
            return .initial
        }
    }

    private func clamp(_ value: Int) -> Int {
        min(100, max(0, value))
    }
}

extension JSONEncoder {
    static var prettyPrinted: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

final class PetMessageHandler: NSObject, WKScriptMessageHandler {
    weak var window: NSWindow?
    weak var webView: WKWebView?
    let root: URL
    let skills: [SkillConfig]
    let stateStore: PetStateStore

    init(window: NSWindow?, webView: WKWebView?, root: URL, skills: [SkillConfig], stateStore: PetStateStore) {
        self.window = window
        self.webView = webView
        self.root = root
        self.skills = skills
        self.stateStore = stateStore
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "pet" else {
            return
        }

        if let action = message.body as? String, action == "drag" {
            dragWindow()
            return
        }

        guard let body = message.body as? [String: Any],
              let action = body["action"] as? String else {
            return
        }

        switch action {
        case "drag":
            dragWindow()
        case "runSkill":
            guard let skillId = body["skillId"] as? String else {
                sendSkillResult("缺少技能 ID", label: "小技能")
                return
            }
            runSkill(id: skillId)
        case "petAction":
            guard let actionId = body["actionId"] as? String else {
                sendSpeech("缺少行动 ID", label: "行动")
                return
            }
            applyPetAction(actionId)
        default:
            break
        }
    }

    private func dragWindow() {
        guard let window, let event = NSApp.currentEvent else {
            return
        }

        window.performDrag(with: event)
    }

    private func runSkill(id: String) {
        guard let skill = skills.first(where: { $0.id == id }) else {
            sendSkillResult("找不到这个小技能\n\(id)", label: "小技能")
            return
        }

        guard let validationError = validateSkill(skill) else {
            startSkill(skill)
            return
        }

        sendSkillResult(validationError, label: skill.name)
    }

    private func startSkill(_ skill: SkillConfig) {
        let process = Process()
        let output = Pipe()
        let error = Pipe()
        let outputLimit = skill.outputLimit ?? 500

        process.executableURL = resolvedURL(for: skill.command)
        process.arguments = skill.args.map(resolveArgument)
        process.currentDirectoryURL = root
        process.standardOutput = output
        process.standardError = error

        do {
            try process.run()
        } catch {
            sendSkillResult("脚本启动失败\n\(error.localizedDescription)", label: skill.name)
            return
        }

        let timeout = skill.timeoutSeconds ?? 10
        let timeoutTask = DispatchWorkItem {
            if process.isRunning {
                process.terminate()
            }
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: timeoutTask)

        process.terminationHandler = { [weak self] process in
            timeoutTask.cancel()
            let stdout = output.fileHandleForReading.readDataToEndOfFile()
            let stderr = error.fileHandleForReading.readDataToEndOfFile()
            let stdoutText = String(data: stdout, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let stderrText = String(data: stderr, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

            let result: String
            if process.terminationStatus == 0 {
                result = stdoutText.isEmpty ? "脚本运行完成\n没有输出内容" : self?.limited(stdoutText, to: outputLimit) ?? stdoutText
            } else if process.terminationReason == .uncaughtSignal && process.terminationStatus == 15 {
                result = "脚本运行超时\n已在 \(Int(timeout)) 秒后停止"
            } else {
                let detail = stderrText.isEmpty ? "退出码 \(process.terminationStatus)" : stderrText
                result = "脚本运行失败\n\(self?.limited(detail, to: outputLimit) ?? detail)"
            }

            DispatchQueue.main.async {
                self?.sendSkillResult(result, label: skill.name)
            }
        }
    }

    private func validateSkill(_ skill: SkillConfig) -> String? {
        guard skill.command == "/usr/bin/python3" || skill.command == "python3" else {
            return "技能配置被拦截\n当前只允许使用 python3"
        }

        guard let script = skill.args.first else {
            return "技能配置错误\n缺少脚本路径"
        }

        let scriptURL = URL(fileURLWithPath: resolveArgument(script)).standardizedFileURL
        let skillsURL = root.appendingPathComponent("skills").standardizedFileURL

        guard scriptURL.path.hasPrefix(skillsURL.path + "/") else {
            return "技能配置被拦截\n脚本必须放在 skills/ 目录"
        }

        guard FileManager.default.fileExists(atPath: scriptURL.path) else {
            return "找不到脚本\n\(script)"
        }

        return nil
    }

    private func limited(_ text: String, to limit: Int) -> String {
        guard text.count > limit else {
            return text
        }

        return String(text.prefix(limit)) + "\n..."
    }

    private func applyPetAction(_ actionId: String) {
        let message = stateStore.apply(action: actionId)
        sendSpeech(message, label: stateStore.state.currentActivity)
        sendState()
    }

    private func resolvedURL(for command: String) -> URL {
        if command.hasPrefix("/") {
            return URL(fileURLWithPath: command)
        }

        return root.appendingPathComponent(command)
    }

    private func resolveArgument(_ argument: String) -> String {
        if argument.hasPrefix("/") {
            return argument
        }

        if argument.hasPrefix("skills/") || argument.hasPrefix("./") {
            return root.appendingPathComponent(argument).path
        }

        return argument
    }

    func sendState() {
        guard let payload = try? JSONEncoder().encode(stateStore.state),
              let json = String(data: payload, encoding: .utf8) else {
            return
        }

        webView?.evaluateJavaScript("window.petStateUpdated(\(json));")
    }

    private func sendSpeech(_ text: String, label: String) {
        sendSkillResult(text, label: label)
    }

    private func sendSkillResult(_ text: String, label: String) {
        guard let payload = try? JSONSerialization.data(withJSONObject: ["text": text, "label": label]),
              let json = String(data: payload, encoding: .utf8) else {
            return
        }

        webView?.evaluateJavaScript("window.petSkillResult(\(json));")
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow!
    private var messageHandler: PetMessageHandler!
    private var webView: WKWebView!
    private var skills: [SkillConfig] = []
    private var stateStore: PetStateStore!

    func applicationDidFinishLaunching(_ notification: Notification) {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let htmlURL = root.appendingPathComponent("desktop/desktop-pet.html")
        skills = loadSkills(root: root)
        stateStore = PetStateStore(root: root)

        let contentController = WKUserContentController()
        let config = WKWebViewConfiguration()
        config.userContentController = contentController

        webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = self
        webView.setValue(false, forKey: "drawsBackground")
        webView.loadFileURL(htmlURL, allowingReadAccessTo: root)

        window = NSWindow(
            contentRect: NSRect(x: 120, y: 180, width: 520, height: 620),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.hasShadow = false
        window.isMovableByWindowBackground = true
        window.contentView = webView
        window.makeKeyAndOrderFront(nil)

        messageHandler = PetMessageHandler(window: window, webView: webView, root: root, skills: skills, stateStore: stateStore)
        contentController.add(messageHandler, name: "pet")

        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    private func loadSkills(root: URL) -> [SkillConfig] {
        let skillsURL = root.appendingPathComponent("skills/skills.json")

        do {
            let data = try Data(contentsOf: skillsURL)
            return try JSONDecoder().decode([SkillConfig].self, from: data)
        } catch {
            print("Failed to load skills.json: \(error)")
            return []
        }
    }
}

extension AppDelegate: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        let items = skills.map { skill in
            [
                "id": skill.id,
                "name": skill.name,
                "icon": skill.icon
            ]
        }

        guard let payload = try? JSONSerialization.data(withJSONObject: items),
              let json = String(data: payload, encoding: .utf8) else {
            return
        }

        webView.evaluateJavaScript("window.petLoadSkills(\(json));")
        messageHandler.sendState()
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
