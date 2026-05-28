import Cocoa
import WebKit

struct SkillConfig: Decodable {
    let id: String
    let name: String
    let icon: String
    let command: String
    let args: [String]
}

final class PetMessageHandler: NSObject, WKScriptMessageHandler {
    weak var window: NSWindow?
    weak var webView: WKWebView?
    let root: URL
    let skills: [SkillConfig]

    init(window: NSWindow?, webView: WKWebView?, root: URL, skills: [SkillConfig]) {
        self.window = window
        self.webView = webView
        self.root = root
        self.skills = skills
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

        let process = Process()
        let output = Pipe()
        let error = Pipe()

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

        process.terminationHandler = { [weak self] process in
            let stdout = output.fileHandleForReading.readDataToEndOfFile()
            let stderr = error.fileHandleForReading.readDataToEndOfFile()
            let stdoutText = String(data: stdout, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let stderrText = String(data: stderr, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

            let result: String
            if process.terminationStatus == 0 {
                result = stdoutText.isEmpty ? "脚本运行完成\n没有输出内容" : stdoutText
            } else {
                result = "脚本运行失败\n\(stderrText.isEmpty ? "退出码 \(process.terminationStatus)" : stderrText)"
            }

            DispatchQueue.main.async {
                self?.sendSkillResult(result, label: skill.name)
            }
        }
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

    func applicationDidFinishLaunching(_ notification: Notification) {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let htmlURL = root.appendingPathComponent("desktop/desktop-pet.html")
        skills = loadSkills(root: root)

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

        messageHandler = PetMessageHandler(window: window, webView: webView, root: root, skills: skills)
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
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
