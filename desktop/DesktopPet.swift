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

struct PetActionConfig: Decodable {
    let id: String
    let name: String
    let icon: String
    let category: String
    let durationSeconds: Double
    let moodDelta: Int
    let weightDelta: Int
    let hairDelta: Int
    let moneyDelta: Int
    let startMessage: String
    let finishMessage: String
}

struct PetState: Codable {
    var mood: Int
    var weight: Int
    var hair: Int
    var money: Int
    var currentActivity: String

    static let initial = PetState(mood: 70, weight: 50, hair: 100, money: 0, currentActivity: "待机")
}

struct PetSettings: Codable {
    var windowX: Double
    var windowY: Double
    var windowWidth: Double
    var windowHeight: Double
    var alwaysOnTop: Bool
    var showStats: Bool

    static let initial = PetSettings(windowX: 120, windowY: 180, windowWidth: 520, windowHeight: 620, alwaysOnTop: true, showStats: true)

    var frame: NSRect {
        NSRect(x: windowX, y: windowY, width: windowWidth, height: windowHeight)
    }
}

final class PetSettingsStore {
    private let settingsURL: URL
    private(set) var settings: PetSettings

    init(root: URL) {
        settingsURL = root.appendingPathComponent("data/pet-settings.json")
        settings = Self.load(from: settingsURL)
    }

    func save(windowFrame: NSRect) {
        settings = PetSettings(
            windowX: windowFrame.origin.x,
            windowY: windowFrame.origin.y,
            windowWidth: windowFrame.size.width,
            windowHeight: windowFrame.size.height,
            alwaysOnTop: settings.alwaysOnTop,
            showStats: settings.showStats
        )
        save()
    }

    func setAlwaysOnTop(_ enabled: Bool) {
        settings.alwaysOnTop = enabled
        save()
    }

    func setShowStats(_ enabled: Bool) {
        settings.showStats = enabled
        save()
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(
                at: settingsURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try JSONEncoder.prettyPrinted.encode(settings)
            try data.write(to: settingsURL, options: .atomic)
        } catch {
            print("Failed to save pet settings: \(error)")
        }
    }

    private static func load(from url: URL) -> PetSettings {
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(PetSettings.self, from: data)
        } catch {
            return .initial
        }
    }
}

final class PetStateStore {
    private let stateURL: URL
    private(set) var state: PetState

    init(root: URL) {
        stateURL = root.appendingPathComponent("data/pet-state.json")
        state = Self.load(from: stateURL)
    }

    func start(action: PetActionConfig) {
        state.currentActivity = action.name
        save()
    }

    func finish(action: PetActionConfig) -> String {
        state.money = max(0, state.money + action.moneyDelta)
        state.mood = clamp(state.mood + action.moodDelta)
        state.weight = clamp(state.weight + action.weightDelta)
        state.hair = clamp(state.hair + action.hairDelta)
        state.currentActivity = "待机"
        save()
        return action.finishMessage + "\n" + effectSummary(for: action)
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

    private func effectSummary(for action: PetActionConfig) -> String {
        var parts: [String] = []
        if action.moneyDelta != 0 {
            parts.append("金钱 \(signed(action.moneyDelta))")
        }
        if action.moodDelta != 0 {
            parts.append("心情 \(signed(action.moodDelta))")
        }
        if action.weightDelta != 0 {
            parts.append("体重 \(signed(action.weightDelta))")
        }
        if action.hairDelta != 0 {
            parts.append("发量 \(signed(action.hairDelta))")
        }

        return parts.isEmpty ? "属性没有变化" : parts.joined(separator: "\n")
    }

    private func signed(_ value: Int) -> String {
        value > 0 ? "+\(value)" : "\(value)"
    }
}

extension JSONEncoder {
    static var prettyPrinted: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

protocol PetWebViewDelegate: AnyObject {
    func showContextMenu(at point: NSPoint)
}

final class PetWebView: WKWebView {
    weak var petDelegate: PetWebViewDelegate?

    override func rightMouseDown(with event: NSEvent) {
        petDelegate?.showContextMenu(at: event.locationInWindow)
    }
}

final class PetMessageHandler: NSObject, WKScriptMessageHandler {
    weak var window: NSWindow?
    weak var webView: WKWebView?
    let root: URL
    let skills: [SkillConfig]
    let actions: [PetActionConfig]
    let stateStore: PetStateStore
    let settingsStore: PetSettingsStore
    private var activeAction: PetActionConfig?

    init(window: NSWindow?, webView: WKWebView?, root: URL, skills: [SkillConfig], actions: [PetActionConfig], stateStore: PetStateStore, settingsStore: PetSettingsStore) {
        self.window = window
        self.webView = webView
        self.root = root
        self.skills = skills
        self.actions = actions
        self.stateStore = stateStore
        self.settingsStore = settingsStore
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
        case "toggleAlwaysOnTop":
            toggleAlwaysOnTop()
        case "toggleStats":
            toggleStats()
        case "quit":
            quit()
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
        guard activeAction == nil else {
            sendSpeech("现在正在忙\n等当前行动结束再来吧", label: stateStore.state.currentActivity)
            return
        }

        guard let action = actions.first(where: { $0.id == actionId }) else {
            sendSpeech("找不到这个行动\n\(actionId)", label: "行动")
            return
        }

        activeAction = action
        stateStore.start(action: action)
        sendSpeech(action.startMessage, label: action.name)
        sendState()
        sendActivityStarted(action)

        DispatchQueue.main.asyncAfter(deadline: .now() + action.durationSeconds) { [weak self] in
            self?.finishPetAction(action)
        }
    }

    private func finishPetAction(_ action: PetActionConfig) {
        guard activeAction?.id == action.id else {
            return
        }

        activeAction = nil
        let message = stateStore.finish(action: action)
        sendSpeech(message, label: action.name)
        sendState()
        sendActivityEnded()
    }

    private func toggleAlwaysOnTop() {
        guard let window else {
            return
        }

        let nextValue = window.level != .floating
        window.level = nextValue ? .floating : .normal
        settingsStore.setAlwaysOnTop(nextValue)
        sendSettings()
        sendSpeech(nextValue ? "已开启置顶" : "已关闭置顶", label: "设置")
    }

    private func toggleStats() {
        let nextValue = !settingsStore.settings.showStats
        settingsStore.setShowStats(nextValue)
        sendSettings()
        sendSpeech(nextValue ? "已显示状态面板" : "已隐藏状态面板", label: "设置")
    }

    private func quit() {
        if let window {
            settingsStore.save(windowFrame: window.frame)
        }
        NSApp.terminate(nil)
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

    func sendActivityStarted(_ action: PetActionConfig) {
        let item: [String: Any] = [
            "id": action.id,
            "name": action.name,
            "durationSeconds": action.durationSeconds
        ]

        guard let payload = try? JSONSerialization.data(withJSONObject: item),
              let json = String(data: payload, encoding: .utf8) else {
            return
        }

        webView?.evaluateJavaScript("window.petActivityStarted(\(json));")
    }

    func sendActivityEnded() {
        webView?.evaluateJavaScript("window.petActivityEnded();")
    }

    func sendSettings() {
        guard let payload = try? JSONEncoder().encode(settingsStore.settings),
              let json = String(data: payload, encoding: .utf8) else {
            return
        }

        webView?.evaluateJavaScript("window.petSettingsUpdated(\(json));")
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
    private var webView: PetWebView!
    private var skills: [SkillConfig] = []
    private var actions: [PetActionConfig] = []
    private var stateStore: PetStateStore!
    private var settingsStore: PetSettingsStore!

    func applicationDidFinishLaunching(_ notification: Notification) {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let htmlURL = root.appendingPathComponent("desktop/desktop-pet.html")
        skills = loadSkills(root: root)
        actions = loadActions(root: root)
        stateStore = PetStateStore(root: root)
        settingsStore = PetSettingsStore(root: root)

        let contentController = WKUserContentController()
        let config = WKWebViewConfiguration()
        config.userContentController = contentController

        webView = PetWebView(frame: .zero, configuration: config)
        webView.petDelegate = self
        webView.navigationDelegate = self
        webView.setValue(false, forKey: "drawsBackground")
        webView.loadFileURL(htmlURL, allowingReadAccessTo: root)

        window = NSWindow(
            contentRect: settingsStore.settings.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = settingsStore.settings.alwaysOnTop ? .floating : .normal
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.hasShadow = false
        window.isMovableByWindowBackground = true
        window.contentView = webView
        window.delegate = self
        window.makeKeyAndOrderFront(nil)

        messageHandler = PetMessageHandler(window: window, webView: webView, root: root, skills: skills, actions: actions, stateStore: stateStore, settingsStore: settingsStore)
        contentController.add(messageHandler, name: "pet")

        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationWillTerminate(_ notification: Notification) {
        settingsStore.save(windowFrame: window.frame)
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

    private func loadActions(root: URL) -> [PetActionConfig] {
        let actionsURL = root.appendingPathComponent("actions/actions.json")

        do {
            let data = try Data(contentsOf: actionsURL)
            return try JSONDecoder().decode([PetActionConfig].self, from: data)
        } catch {
            print("Failed to load actions.json: \(error)")
            return []
        }
    }
}

extension AppDelegate: PetWebViewDelegate {
    func showContextMenu(at point: NSPoint) {
        let menu = NSMenu()
        let pinTitle = settingsStore.settings.alwaysOnTop ? "关闭置顶" : "开启置顶"
        menu.addItem(NSMenuItem(title: pinTitle, action: #selector(toggleAlwaysOnTopFromMenu), keyEquivalent: ""))
        let statsTitle = settingsStore.settings.showStats ? "隐藏状态面板" : "显示状态面板"
        menu.addItem(NSMenuItem(title: statsTitle, action: #selector(toggleStatsFromMenu), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "退出", action: #selector(quitFromMenu), keyEquivalent: "q"))
        NSMenu.popUpContextMenu(menu, with: NSApp.currentEvent ?? NSEvent(), for: webView)
    }

    @objc private func toggleAlwaysOnTopFromMenu() {
        let nextValue = window.level != .floating
        window.level = nextValue ? .floating : .normal
        settingsStore.setAlwaysOnTop(nextValue)
        messageHandler.sendSettings()
    }

    @objc private func toggleStatsFromMenu() {
        settingsStore.setShowStats(!settingsStore.settings.showStats)
        messageHandler.sendSettings()
    }

    @objc private func quitFromMenu() {
        settingsStore.save(windowFrame: window.frame)
        NSApp.terminate(nil)
    }
}

extension AppDelegate: NSWindowDelegate {
    func windowDidMove(_ notification: Notification) {
        settingsStore.save(windowFrame: window.frame)
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
        sendActions()
        messageHandler.sendState()
        messageHandler.sendSettings()
    }

    private func sendActions() {
        let items = actions.map { action in
            [
                "id": action.id,
                "name": action.name,
                "icon": action.icon,
                "category": action.category,
                "durationSeconds": action.durationSeconds
            ] as [String: Any]
        }

        guard let payload = try? JSONSerialization.data(withJSONObject: items),
              let json = String(data: payload, encoding: .utf8) else {
            return
        }

        webView.evaluateJavaScript("window.petLoadActions(\(json));")
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
