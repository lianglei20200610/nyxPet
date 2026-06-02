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
    let mode: String?
    let spriteState: String?
    let durationSeconds: Double
    let moodDelta: Int
    let weightDelta: Int
    let hairDelta: Int
    let healthDelta: Int?
    let moneyDelta: Int
    let startMessage: String
    let finishMessage: String
}

struct EconomyConfig: Decodable {
    let dailyIncome: Int
    let fixedExpenses: [EconomyFixedExpense]
    let randomExpenses: [EconomyRandomExpense]
}

struct EconomyFixedExpense: Decodable {
    let id: String
    let name: String
    let category: String?
    let amount: Int
}

struct EconomyRandomExpense: Decodable {
    let id: String
    let name: String
    let category: String?
    let minAmount: Int
    let maxAmount: Int
    let chance: Double
}

struct EventTriggers: Codable {
    let healthBelow: Int?
    let moodBelow: Int?
    let moneyBelow: Int?
    let moneyAbove: Int?
    let debtLevel: String?
}

struct EventFollowUp: Codable {
    let eventId: String
    let chance: Double?
    let delayDays: Int?
}

struct PendingEvent: Codable {
    let id: String
    let eventId: String
    let dueDate: String
    let sourceEventId: String
    let reason: String
}

struct LedgerEntry: Codable {
    let id: String
    let date: String
    let type: String
    let category: String
    let name: String
    let amount: Int
    let balanceAfter: Int
    let source: String
}

struct LifeEventConfig: Decodable {
    let id: String
    let name: String
    let category: String
    let message: String
    let chance: Double
    let minMoneyDelta: Int
    let maxMoneyDelta: Int
    let moodDelta: Int
    let healthDelta: Int
    let weightDelta: Int?
    let hairDelta: Int?
    let healthSensitive: Bool?
    let triggers: EventTriggers?
    let followUps: [EventFollowUp]?
}

struct LifeEventLogEntry: Codable {
    let id: String
    let date: String
    let category: String
    let name: String
    let message: String
    let moneyDelta: Int
    let moodDelta: Int
    let healthDelta: Int
    let source: String
    let reason: String?
}

struct EventBubbleMessage: Codable {
    let label: String
    let text: String
}

struct PetState: Codable {
    var mood: Int
    var weight: Int
    var hair: Int
    var health: Int
    var money: Int
    var currentActivity: String
    var lastSettlementDate: String?
    var pendingEvents: [PendingEvent]

    static let initial = PetState(mood: 70, weight: 50, hair: 100, health: 75, money: 500000, currentActivity: "待机", lastSettlementDate: nil, pendingEvents: [])

    enum CodingKeys: String, CodingKey {
        case mood
        case weight
        case hair
        case health
        case money
        case currentActivity
        case lastSettlementDate
        case pendingEvents
    }

    init(mood: Int, weight: Int, hair: Int, health: Int, money: Int, currentActivity: String, lastSettlementDate: String?, pendingEvents: [PendingEvent]) {
        self.mood = mood
        self.weight = weight
        self.hair = hair
        self.health = health
        self.money = money
        self.currentActivity = currentActivity
        self.lastSettlementDate = lastSettlementDate
        self.pendingEvents = pendingEvents
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        mood = try container.decodeIfPresent(Int.self, forKey: .mood) ?? Self.initial.mood
        weight = try container.decodeIfPresent(Int.self, forKey: .weight) ?? Self.initial.weight
        hair = try container.decodeIfPresent(Int.self, forKey: .hair) ?? Self.initial.hair
        health = try container.decodeIfPresent(Int.self, forKey: .health) ?? Self.initial.health
        money = try container.decodeIfPresent(Int.self, forKey: .money) ?? Self.initial.money
        currentActivity = try container.decodeIfPresent(String.self, forKey: .currentActivity) ?? Self.initial.currentActivity
        lastSettlementDate = try container.decodeIfPresent(String.self, forKey: .lastSettlementDate)
        pendingEvents = try container.decodeIfPresent([PendingEvent].self, forKey: .pendingEvents) ?? []
    }
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
    private let ledgerURL: URL
    private let eventURL: URL
    private(set) var state: PetState
    private var ledger: [LedgerEntry]
    private var eventLog: [LifeEventLogEntry]
    private(set) var eventMessages: [EventBubbleMessage] = []

    init(root: URL) {
        stateURL = root.appendingPathComponent("data/pet-state.json")
        ledgerURL = root.appendingPathComponent("data/ledger.json")
        eventURL = root.appendingPathComponent("data/events.json")
        state = Self.load(from: stateURL)
        ledger = Self.loadLedger(from: ledgerURL)
        eventLog = Self.loadEventLog(from: eventURL)
    }

    func settleDailyBudget(config: EconomyConfig, lifeEvents: [LifeEventConfig]) -> String? {
        let today = Self.dayString(Date())

        guard let lastSettlementDate = state.lastSettlementDate else {
            state.lastSettlementDate = today
            save()
            return nil
        }

        guard let lastDate = Self.date(from: lastSettlementDate),
              let todayDate = Self.date(from: today),
              lastDate < todayDate else {
            return nil
        }

        var date = Calendar.current.date(byAdding: .day, value: 1, to: lastDate) ?? todayDate
        var days = 0
        var total = 0
        var latestRandomParts: [String] = []
        eventMessages = []

        while date <= todayDate {
            let day = Self.dayString(date)
            var dayTotal = config.dailyIncome
            state.health = clamp(state.health - 1)

            state.money += config.dailyIncome
            recordLedgerEntry(
                date: day,
                type: "income",
                category: "工资",
                name: "日薪",
                amount: config.dailyIncome,
                source: "dailySettlement",
                refId: "dailyIncome"
            )

            for expense in config.fixedExpenses {
                let amount = expense.amount
                dayTotal += amount
                state.money += amount
                recordLedgerEntry(
                    date: day,
                    type: "fixedExpense",
                    category: expense.category ?? "固定支出",
                    name: expense.name,
                    amount: amount,
                    source: "dailySettlement",
                    refId: expense.id
                )
            }

            latestRandomParts = []
            for (index, expense) in config.randomExpenses.enumerated() {
                if Self.shouldApplyRandomExpense(expense, day: day) {
                    let amount = Self.randomAmount(expense, day: day)
                    dayTotal += amount
                    state.money += amount
                    recordLedgerEntry(
                        date: day,
                        type: "randomExpense",
                        category: expense.category ?? "随机支出",
                        name: expense.name,
                        amount: amount,
                        source: "dailySettlement",
                        refId: expense.id,
                        index: index
                    )
                    latestRandomParts.append("\(expense.name) \(signed(amount))")
                }
            }

            let pendingResult = processPendingEvents(day: day, lifeEvents: lifeEvents, limit: 3)
            var eventCount = pendingResult.count
            dayTotal += pendingResult.totalDelta
            let orderedEvents = lifeEvents.enumerated().sorted {
                Self.stableSeed(day + $0.element.id + "order") < Self.stableSeed(day + $1.element.id + "order")
            }

            for (index, event) in orderedEvents {
                guard eventCount < 3 else {
                    break
                }
                if shouldApplyLifeEvent(event, day: day) {
                    let beforeMoney = state.money
                    applyLifeEvent(event, day: day, index: index, source: "lifeEvent", reason: eventTriggerReason(event), lifeEvents: lifeEvents)
                    dayTotal += state.money - beforeMoney
                    eventCount += 1
                }
            }

            total += dayTotal
            days += 1
            date = Calendar.current.date(byAdding: .day, value: 1, to: date) ?? todayDate.addingTimeInterval(86400)
        }

        let debtPenalty = debtMoodPenalty()
        state.mood = clamp(state.mood + (total < 0 ? -2 : 1) + debtPenalty)
        state.currentActivity = "待机"
        state.lastSettlementDate = today
        save()

        let fixedTotal = config.fixedExpenses.reduce(0) { $0 + $1.amount }
        var lines = [
            "已结算 \(days) 天",
            "工资 +\(config.dailyIncome * days)",
            "固定支出 \(signed(fixedTotal * days))"
        ]
        if !latestRandomParts.isEmpty {
            lines.append(contentsOf: latestRandomParts)
        }
        lines.append("合计 \(signed(total))")
        if debtPenalty < 0 {
            lines.append("负债压力 心情 \(signed(debtPenalty))")
        }
        return lines.joined(separator: "\n")
    }

    func start(action: PetActionConfig) {
        state.currentActivity = action.name
        save()
    }

    func finish(action: PetActionConfig) -> String {
        state.money += action.moneyDelta
        state.mood = clamp(state.mood + action.moodDelta)
        state.weight = clamp(state.weight + action.weightDelta)
        state.hair = clamp(state.hair + action.hairDelta)
        state.health = clamp(state.health + (action.healthDelta ?? 0))
        state.currentActivity = "待机"
        save()
        recordLedgerEntry(
            date: Self.dayString(Date()),
            type: action.moneyDelta >= 0 ? "income" : "expense",
            category: action.category,
            name: action.name,
            amount: action.moneyDelta,
            source: "petAction",
            refId: action.id + ":\(Int(Date().timeIntervalSince1970 * 1000))"
        )
        return action.finishMessage + "\n" + effectSummary(for: action)
    }

    func ledgerSummary(limit: Int = 8) -> String {
        guard !ledger.isEmpty else {
            return "账本还是空的\n等发生收入或支出后会记录在这里"
        }

        return ledger.suffix(limit).reversed().map { entry in
            "\(entry.date) \(entry.name) \(signed(entry.amount))，余额 \(entry.balanceAfter)"
        }.joined(separator: "\n")
    }

    func recentLedgerEntries(limit: Int = 24) -> [LedgerEntry] {
        Array(ledger.suffix(limit).reversed())
    }

    func recentEventEntries(limit: Int = 24) -> [LifeEventLogEntry] {
        eventLog = Self.loadEventLog(from: eventURL)
        return Array(eventLog.suffix(limit).reversed())
    }

    func monthlyStatsSummary() -> String {
        ledger = Self.loadLedger(from: ledgerURL)
        let month = Self.dayString(Date()).prefix(7)
        let rows = ledger.filter { $0.date.hasPrefix(month) }
        let income = rows.filter { $0.amount > 0 }.reduce(0) { $0 + $1.amount }
        let expense = rows.filter { $0.amount < 0 }.reduce(0) { $0 + $1.amount }
        let net = income + expense
        return "\(month) 统计\n收入 \(signed(income))\n支出 \(signed(expense))\n结余 \(signed(net))"
    }

    func eventIds() -> Set<String> {
        eventLog = Self.loadEventLog(from: eventURL)
        return Set(eventLog.map { $0.id })
    }

    func newEventMessages(knownIds: inout Set<String>) -> [EventBubbleMessage] {
        eventLog = Self.loadEventLog(from: eventURL)
        let newEntries = eventLog.filter { !knownIds.contains($0.id) }
        for entry in eventLog {
            knownIds.insert(entry.id)
        }

        return newEntries.suffix(5).map { entry in
            let reasonLine = entry.reason.map { "\n\($0)" } ?? ""
            return EventBubbleMessage(
                label: entry.category,
                text: "\(entry.message)\(reasonLine)\n金钱 \(signed(entry.moneyDelta)) 心情 \(signed(entry.moodDelta)) 健康 \(signed(entry.healthDelta))"
            )
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

    private static func loadLedger(from url: URL) -> [LedgerEntry] {
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode([LedgerEntry].self, from: data)
        } catch {
            return []
        }
    }

    private static func loadEventLog(from url: URL) -> [LifeEventLogEntry] {
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode([LifeEventLogEntry].self, from: data)
        } catch {
            return []
        }
    }

    private func recordLedgerEntry(date: String, type: String, category: String, name: String, amount: Int, source: String, refId: String, index: Int = 0) {
        guard amount != 0 else {
            return
        }

        let id = "\(date):\(source):\(refId):\(index)"
        guard !ledger.contains(where: { $0.id == id }) else {
            return
        }

        ledger.append(LedgerEntry(
            id: id,
            date: date,
            type: type,
            category: category,
            name: name,
            amount: amount,
            balanceAfter: state.money,
            source: source
        ))
        saveLedger()
    }

    private func saveLedger() {
        do {
            try FileManager.default.createDirectory(
                at: ledgerURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try JSONEncoder.prettyPrinted.encode(ledger)
            try data.write(to: ledgerURL, options: .atomic)
        } catch {
            print("Failed to save pet ledger: \(error)")
        }
    }

    private func recordEventEntry(date: String, category: String, name: String, message: String, moneyDelta: Int, moodDelta: Int, healthDelta: Int, source: String, refId: String, reason: String = "", index: Int = 0) {
        let id = "\(date):\(source):\(refId):\(index)"
        guard !eventLog.contains(where: { $0.id == id }) else {
            return
        }

        eventLog.append(LifeEventLogEntry(
            id: id,
            date: date,
            category: category,
            name: name,
            message: message,
            moneyDelta: moneyDelta,
            moodDelta: moodDelta,
            healthDelta: healthDelta,
            source: source,
            reason: reason.isEmpty ? nil : reason
        ))
        saveEventLog()
    }

    private func saveEventLog() {
        do {
            try FileManager.default.createDirectory(
                at: eventURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try JSONEncoder.prettyPrinted.encode(eventLog)
            try data.write(to: eventURL, options: .atomic)
        } catch {
            print("Failed to save pet event log: \(error)")
        }
    }

    private func clamp(_ value: Int) -> Int {
        min(100, max(0, value))
    }

    private func debtMoodPenalty() -> Int {
        guard state.money < 0 else {
            return 0
        }

        return -min(12, max(1, Int(ceil(Double(abs(state.money)) / 5000.0))))
    }

    private func debtLevel() -> String {
        if state.money >= 0 {
            return "none"
        }

        let debt = abs(state.money)
        if debt < 10_000 {
            return "light"
        }
        if debt < 50_000 {
            return "pressure"
        }
        return "severe"
    }

    private func debtRank(_ level: String?) -> Int {
        switch level {
        case "light":
            return 1
        case "pressure":
            return 2
        case "severe":
            return 3
        default:
            return 0
        }
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
        if (action.healthDelta ?? 0) != 0 {
            parts.append("健康 \(signed(action.healthDelta ?? 0))")
        }

        return parts.isEmpty ? "属性没有变化" : parts.joined(separator: "\n")
    }

    private func eventTriggerMatch(_ event: LifeEventConfig) -> (matched: Bool, reason: String) {
        guard let triggers = event.triggers else {
            return (false, "")
        }

        var reasons: [String] = []
        if let healthBelow = triggers.healthBelow, state.health < healthBelow {
            reasons.append("健康偏低")
        }
        if let moodBelow = triggers.moodBelow, state.mood < moodBelow {
            reasons.append("心情偏低")
        }
        if let moneyBelow = triggers.moneyBelow, state.money < moneyBelow {
            reasons.append("现金紧张")
        }
        if let moneyAbove = triggers.moneyAbove, state.money > moneyAbove {
            reasons.append("现金充裕")
        }
        if let debtLevel = triggers.debtLevel, debtRank(self.debtLevel()) >= debtRank(debtLevel) {
            reasons.append("负债压力")
        }

        let reason = reasons.isEmpty ? "" : "由于\(reasons.joined(separator: "、"))，这件事更容易发生"
        return (!reasons.isEmpty, reason)
    }

    private func eventTriggerReason(_ event: LifeEventConfig) -> String {
        eventTriggerMatch(event).reason
    }

    private func effectiveEventChance(_ event: LifeEventConfig) -> Double {
        var chance = event.chance
        if event.healthSensitive == true {
            chance *= 1 + Double(max(0, 80 - state.health)) / 25.0
        }

        if event.triggers != nil {
            chance *= eventTriggerMatch(event).matched ? 3.2 : 0.25
        }
        return min(0.8, chance)
    }

    private func shouldApplyLifeEvent(_ event: LifeEventConfig, day: String) -> Bool {
        let seed = Self.stableSeed(day + event.id + "life")
        let value = Double(seed % 10_000) / 10_000.0
        return value < effectiveEventChance(event)
    }

    private func lifeEventMoney(_ event: LifeEventConfig, day: String) -> Int {
        let lower = min(event.minMoneyDelta, event.maxMoneyDelta)
        let upper = max(event.minMoneyDelta, event.maxMoneyDelta)
        guard lower != upper else {
            return lower
        }

        let range = UInt32(upper - lower + 1)
        let offset = Int(Self.stableSeed(day + event.id + "money") % range)
        return lower + offset
    }

    private func scheduleFollowUps(_ event: LifeEventConfig, day: String, index: Int, lifeEvents: [LifeEventConfig]) {
        guard let followUps = event.followUps else {
            return
        }

        for followUp in followUps {
            guard lifeEvents.contains(where: { $0.id == followUp.eventId }) else {
                continue
            }

            let chance = followUp.chance ?? 1.0
            let seed = Self.stableSeed(day + event.id + followUp.eventId + "\(index)" + "follow")
            let value = Double(seed % 10_000) / 10_000.0
            guard value < chance else {
                continue
            }

            let dueDate = Self.addDaysString(day, count: followUp.delayDays ?? 1)
            let id = "\(dueDate):followUp:\(event.id):\(followUp.eventId):\(index)"
            guard !state.pendingEvents.contains(where: { $0.id == id }) else {
                continue
            }

            state.pendingEvents.append(PendingEvent(
                id: id,
                eventId: followUp.eventId,
                dueDate: dueDate,
                sourceEventId: event.id,
                reason: "由「\(event.name)」后续触发"
            ))
        }
    }

    private func processPendingEvents(day: String, lifeEvents: [LifeEventConfig], limit: Int) -> (count: Int, totalDelta: Int) {
        let dueEvents = state.pendingEvents.filter { $0.dueDate <= day }
        state.pendingEvents = state.pendingEvents.filter { $0.dueDate > day }

        var applied = 0
        var totalDelta = 0
        for pendingEvent in dueEvents {
            guard applied < limit else {
                state.pendingEvents.append(pendingEvent)
                continue
            }
            guard let event = lifeEvents.first(where: { $0.id == pendingEvent.eventId }) else {
                continue
            }

            let index = Int(Self.stableSeed(pendingEvent.id) % 10_000)
            let beforeMoney = state.money
            applyLifeEvent(event, day: day, index: index, source: "followUp", reason: pendingEvent.reason, lifeEvents: lifeEvents)
            totalDelta += state.money - beforeMoney
            applied += 1
        }

        state.pendingEvents.sort { $0.dueDate < $1.dueDate }
        return (applied, totalDelta)
    }

    private func applyLifeEvent(_ event: LifeEventConfig, day: String, index: Int, source: String = "lifeEvent", reason: String = "", lifeEvents: [LifeEventConfig] = []) {
        let moneyDelta = lifeEventMoney(event, day: day)
        let moodDelta = event.moodDelta
        let healthDelta = event.healthDelta
        let weightDelta = event.weightDelta ?? 0
        let hairDelta = event.hairDelta ?? 0

        state.money += moneyDelta
        state.mood = clamp(state.mood + moodDelta)
        state.health = clamp(state.health + healthDelta)
        state.weight = clamp(state.weight + weightDelta)
        state.hair = clamp(state.hair + hairDelta)

        if moneyDelta != 0 {
            recordLedgerEntry(
                date: day,
                type: moneyDelta > 0 ? "income" : "eventExpense",
                category: event.category,
                name: event.name,
                amount: moneyDelta,
                source: source,
                refId: event.id,
                index: index
            )
        }

        recordEventEntry(
            date: day,
            category: event.category,
            name: event.name,
            message: event.message,
            moneyDelta: moneyDelta,
            moodDelta: moodDelta,
            healthDelta: healthDelta,
            source: source,
            refId: event.id,
            reason: reason,
            index: index
        )

        let reasonLine = reason.isEmpty ? "" : "\n\(reason)"
        eventMessages.append(EventBubbleMessage(
            label: event.category,
            text: "\(event.message)\(reasonLine)\n金钱 \(signed(moneyDelta)) 心情 \(signed(moodDelta)) 健康 \(signed(healthDelta))"
        ))

        scheduleFollowUps(event, day: day, index: index, lifeEvents: lifeEvents)
    }

    private func signed(_ value: Int) -> String {
        value > 0 ? "+\(value)" : "\(value)"
    }

    private static func dayString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar.current
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private static func date(from day: String) -> Date? {
        let formatter = DateFormatter()
        formatter.calendar = Calendar.current
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: day)
    }

    private static func addDaysString(_ day: String, count: Int) -> String {
        guard let date = Self.date(from: day),
              let next = Calendar.current.date(byAdding: .day, value: count, to: date) else {
            return day
        }
        return Self.dayString(next)
    }

    private static func stableSeed(_ text: String) -> UInt32 {
        text.unicodeScalars.reduce(UInt32(2166136261)) { seed, scalar in
            (seed ^ UInt32(scalar.value)) &* UInt32(16777619)
        }
    }

    private static func shouldApplyRandomExpense(_ expense: EconomyRandomExpense, day: String) -> Bool {
        let seed = stableSeed(day + expense.id + "chance")
        let value = Double(seed % 10_000) / 10_000.0
        return value < expense.chance
    }

    private static func randomAmount(_ expense: EconomyRandomExpense, day: String) -> Int {
        let lower = min(expense.minAmount, expense.maxAmount)
        let upper = max(expense.minAmount, expense.maxAmount)
        let range = UInt32(upper - lower + 1)
        let offset = Int(stableSeed(day + expense.id + "amount") % range)
        return lower + offset
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
    let lifeEvents: [LifeEventConfig]
    let stateStore: PetStateStore
    let settingsStore: PetSettingsStore
    private var activeAction: PetActionConfig?

    init(window: NSWindow?, webView: WKWebView?, root: URL, skills: [SkillConfig], actions: [PetActionConfig], lifeEvents: [LifeEventConfig], stateStore: PetStateStore, settingsStore: PetSettingsStore) {
        self.window = window
        self.webView = webView
        self.root = root
        self.skills = skills
        self.actions = actions
        self.lifeEvents = lifeEvents
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
        case "showLedger":
            sendLedger()
        case "showEvents":
            sendEvents()
        case "showLedgerStats":
            sendSpeech(stateStore.monthlyStatsSummary(), label: "月度统计")
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

        if skill.command.hasPrefix("/") {
            process.executableURL = resolvedURL(for: skill.command)
            process.arguments = skill.args.map(resolveArgument)
        } else {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = [skill.command] + skill.args.map(resolveArgument)
        }
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
            "durationSeconds": action.durationSeconds,
            "mode": action.mode ?? action.category,
            "spriteState": action.spriteState ?? ""
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

    func sendLedger() {
        let entries = stateStore.recentLedgerEntries()
        guard let payload = try? JSONEncoder().encode(["entries": entries]),
              let json = String(data: payload, encoding: .utf8) else {
            return
        }

        webView?.evaluateJavaScript("window.petLedgerResult(\(json));")
    }

    func sendEvents() {
        let entries = stateStore.recentEventEntries()
        guard let payload = try? JSONEncoder().encode(["entries": entries]),
              let json = String(data: payload, encoding: .utf8) else {
            return
        }

        webView?.evaluateJavaScript("window.petEventLogResult(\(json));")
    }

    func sendEventMessages(_ messages: [EventBubbleMessage]) {
        guard !messages.isEmpty,
              let payload = try? JSONEncoder().encode(messages),
              let json = String(data: payload, encoding: .utf8) else {
            return
        }

        webView?.evaluateJavaScript("window.petQueueEventMessages(\(json));")
    }

    private func sendSpeech(_ text: String, label: String) {
        sendSkillResult(text, label: label)
    }

    func sendSkillResult(_ text: String, label: String) {
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
    private var economy: EconomyConfig!
    private var lifeEvents: [LifeEventConfig] = []
    private var dailySettlementMessage: String?
    private var stateStore: PetStateStore!
    private var settingsStore: PetSettingsStore!
    private var eventPollTimer: Timer?
    private var knownEventIds = Set<String>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let htmlURL = root.appendingPathComponent("desktop/desktop-pet.html")
        skills = loadSkills(root: root)
        actions = loadActions(root: root)
        economy = loadEconomy(root: root)
        lifeEvents = loadLifeEvents(root: root)
        stateStore = PetStateStore(root: root)
        dailySettlementMessage = stateStore.settleDailyBudget(config: economy, lifeEvents: lifeEvents)
        knownEventIds = stateStore.eventIds()
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

        messageHandler = PetMessageHandler(window: window, webView: webView, root: root, skills: skills, actions: actions, lifeEvents: lifeEvents, stateStore: stateStore, settingsStore: settingsStore)
        contentController.add(messageHandler, name: "pet")

        NSApp.activate(ignoringOtherApps: true)
        startEventLogPolling()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationWillTerminate(_ notification: Notification) {
        eventPollTimer?.invalidate()
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

    private func loadEconomy(root: URL) -> EconomyConfig {
        let economyURL = root.appendingPathComponent("actions/economy.json")

        do {
            let data = try Data(contentsOf: economyURL)
            return try JSONDecoder().decode(EconomyConfig.self, from: data)
        } catch {
            print("Failed to load economy.json: \(error)")
            return EconomyConfig(dailyIncome: 500, fixedExpenses: [], randomExpenses: [])
        }
    }

    private func loadLifeEvents(root: URL) -> [LifeEventConfig] {
        let eventsURL = root.appendingPathComponent("actions/life-events.json")

        do {
            let data = try Data(contentsOf: eventsURL)
            return try JSONDecoder().decode([LifeEventConfig].self, from: data)
        } catch {
            print("Failed to load life-events.json: \(error)")
            return []
        }
    }

    private func startEventLogPolling() {
        eventPollTimer?.invalidate()
        eventPollTimer = Timer.scheduledTimer(withTimeInterval: 1.2, repeats: true) { [weak self] _ in
            guard let self else {
                return
            }

            let messages = self.stateStore.newEventMessages(knownIds: &self.knownEventIds)
            self.messageHandler?.sendEventMessages(messages)
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
                "durationSeconds": action.durationSeconds,
                "mode": action.mode ?? action.category,
                "spriteState": action.spriteState ?? ""
            ] as [String: Any]
        }

        guard let payload = try? JSONSerialization.data(withJSONObject: items),
              let json = String(data: payload, encoding: .utf8) else {
            return
        }

        webView.evaluateJavaScript("window.petLoadActions(\(json));")
        if let dailySettlementMessage {
            messageHandler.sendSkillResult(dailySettlementMessage, label: "今日收支")
        }
        messageHandler.sendEventMessages(stateStore.eventMessages)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
