const { app, BrowserWindow, Menu, ipcMain } = require("electron");
const { spawn } = require("child_process");
const fs = require("fs");
const path = require("path");

const root = path.resolve(__dirname, "..", "..");
const dataDir = path.join(root, "data");
const settingsPath = path.join(dataDir, "pet-settings.json");
const statePath = path.join(dataDir, "pet-state.json");
const ledgerPath = path.join(dataDir, "ledger.json");
const eventLogPath = path.join(dataDir, "events.json");
const economyPath = path.join(root, "actions", "economy.json");
const lifeEventsPath = path.join(root, "actions", "life-events.json");

const initialSettings = {
  windowX: 120,
  windowY: 180,
  windowWidth: 520,
  windowHeight: 620,
  alwaysOnTop: true,
  showStats: true
};

const initialState = {
  mood: 70,
  weight: 50,
  hair: 100,
  health: 75,
  money: 500000,
  currentActivity: "待机",
  lastSettlementDate: null,
  pendingEvents: []
};

let mainWindow;
let skills = [];
let actions = [];
let economy = { dailyIncome: 500, fixedExpenses: [], randomExpenses: [] };
let lifeEvents = [];
let settings = { ...initialSettings };
let state = { ...initialState };
let ledger = [];
let eventLog = [];
let announcedEventIds = new Set();
let activeActionId = null;
let dailySettlementMessage = null;
let dailyEventMessages = [];

function publishState() {
  writeJson(statePath, state);
  sendState();
}

function readJson(filePath, fallback) {
  try {
    return JSON.parse(fs.readFileSync(filePath, "utf8"));
  } catch {
    return fallback;
  }
}

function writeJson(filePath, value) {
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
  fs.writeFileSync(filePath, `${JSON.stringify(value, null, 2)}\n`, "utf8");
}

function loadRuntimeData() {
  skills = readJson(path.join(root, "skills", "skills.json"), []);
  actions = readJson(path.join(root, "actions", "actions.json"), []);
  economy = { ...economy, ...readJson(economyPath, {}) };
  lifeEvents = readJson(lifeEventsPath, []);
  settings = { ...initialSettings, ...readJson(settingsPath, {}) };
  state = { ...initialState, ...readJson(statePath, {}) };
  if (!Array.isArray(state.pendingEvents)) {
    state.pendingEvents = [];
  }
  ledger = readJson(ledgerPath, []);
  if (!Array.isArray(ledger)) {
    ledger = [];
  }
  eventLog = readJson(eventLogPath, []);
  if (!Array.isArray(eventLog)) {
    eventLog = [];
  }
  dailySettlementMessage = settleDailyBudget();
  announcedEventIds = new Set(eventLog.map((entry) => entry.id));
}

function sendJavaScript(expression) {
  if (!mainWindow || mainWindow.isDestroyed()) {
    return;
  }
  mainWindow.webContents.executeJavaScript(expression).catch((error) => {
    console.error("Failed to send pet update:", error);
  });
}

function sendCallback(name, payload) {
  sendJavaScript(`window.${name}(${JSON.stringify(payload)});`);
}

function sendSkillResult(text, label = "小技能") {
  sendCallback("petSkillResult", { text, label });
}

function sendState() {
  sendCallback("petStateUpdated", { ...state, debt: debtInfo() });
}

function sendSettings() {
  sendCallback("petSettingsUpdated", settings);
}

function sendActivityStarted(action) {
  sendCallback("petActivityStarted", {
    id: action.id,
    name: action.name,
    durationSeconds: action.durationSeconds,
    mode: action.mode || action.category,
    spriteState: action.spriteState || ""
  });
}

function sendActivityEnded() {
  sendJavaScript("window.petActivityEnded();");
}

function bootstrapRenderer() {
  const publicSkills = skills.map(({ id, name, icon }) => ({ id, name, icon }));
  const publicActions = actions.map((action) => ({
    id: action.id,
    name: action.name,
    icon: action.icon,
    category: action.category,
    durationSeconds: action.durationSeconds,
    mode: action.mode,
    spriteState: action.spriteState,
    moneyDelta: action.moneyDelta,
    moodDelta: action.moodDelta,
    healthDelta: action.healthDelta
  }));

  sendCallback("petLoadSkills", publicSkills);
  sendCallback("petLoadActions", publicActions);
  sendState();
  sendSettings();
  if (dailySettlementMessage) {
    sendSkillResult(dailySettlementMessage, "今日收支");
  }
  if (dailyEventMessages.length > 0) {
    sendCallback("petQueueEventMessages", paceEventMessages(dailyEventMessages));
  }
}

function clamp(value) {
  return Math.min(100, Math.max(0, value));
}

function debtMoodPenalty() {
  if (state.money >= 0) {
    return 0;
  }
  return -Math.min(12, Math.max(1, Math.ceil(Math.abs(state.money) / 5000)));
}

function debtInfo() {
  const money = Number(state.money || 0);
  if (money > 0) return { level: "none", label: "现金正常", moodPenalty: 0 };
  if (money === 0) return { level: "zero", label: "现金为 0", moodPenalty: 0 };
  if (money > -10000) return { level: "light", label: "轻微透支", moodPenalty: -2 };
  if (money > -50000) return { level: "pressure", label: "压力负债", moodPenalty: -6 };
  return { level: "severe", label: "严重负债", moodPenalty: -12 };
}

function applyDerivedStateEffects() {
  const debt = debtInfo();
  if (debt.moodPenalty < 0) {
    state.mood = clamp(state.mood + debt.moodPenalty);
  }
  if (state.health < 30) {
    state.mood = clamp(state.mood - 3);
  }
  if (state.mood < 20) {
    state.health = clamp(state.health - 1);
  }
  return debt;
}

function signed(value) {
  return value > 0 ? `+${value}` : `${value}`;
}

function ledgerId(date, source, id, index = 0) {
  return `${date}:${source}:${id}:${index}`;
}

function recordLedgerEntry({ date, type, category, name, amount, source, refId, index = 0 }) {
  if (amount === 0) {
    return;
  }
  const id = ledgerId(date, source, refId || name, index);
  if (ledger.some((entry) => entry.id === id)) {
    return;
  }
  ledger.push({
    id,
    date,
    type,
    category,
    name,
    amount,
    balanceAfter: state.money,
    source
  });
  writeJson(ledgerPath, ledger);
}

function ledgerSummary(limit = 8) {
  return ledger
    .slice(-limit)
    .reverse()
    .map((entry) => ({
      date: entry.date,
      name: entry.name,
      category: entry.category,
      amount: entry.amount,
      balanceAfter: entry.balanceAfter
    }));
}

function ledgerMonthlyStats() {
  const month = dayString(new Date()).slice(0, 7);
  const rows = ledger.filter((entry) => String(entry.date || "").startsWith(month));
  const stats = { month, income: 0, expense: 0, net: 0, categories: {} };
  for (const entry of rows) {
    const amount = Number(entry.amount || 0);
    if (amount >= 0) stats.income += amount;
    else stats.expense += amount;
    const category = entry.category || "其他";
    stats.categories[category] = (stats.categories[category] || 0) + amount;
  }
  stats.net = stats.income + stats.expense;
  return stats;
}

function eventSeverity(entry) {
  const money = Math.abs(Number(entry.moneyDelta || 0));
  const mood = Math.abs(Number(entry.moodDelta || 0));
  const health = Math.abs(Number(entry.healthDelta || 0));
  if (money >= 1000 || mood >= 8 || health >= 8) return "urgent";
  if (money >= 300 || mood >= 5 || health >= 5) return "important";
  return "normal";
}

function eventSummary(limit = 24) {
  const latestEventLog = readJson(eventLogPath, []);
  if (Array.isArray(latestEventLog)) {
    eventLog = latestEventLog;
  }
  return eventLog
    .slice(-limit)
    .reverse()
    .map((entry) => ({
      date: entry.date,
      name: entry.name,
      category: entry.category,
      message: entry.message,
      moneyDelta: entry.moneyDelta,
      moodDelta: entry.moodDelta,
      healthDelta: entry.healthDelta,
      reason: entry.reason || "",
      severity: entry.severity || eventSeverity(entry)
    }));
}

function eventDebugSummary() {
  const triggerEvents = (lifeEvents || [])
    .filter((event) => event.triggers)
    .map((event) => {
      const trigger = eventTriggerMatch(event);
      return `${trigger.matched ? "↑" : "·"} ${event.name} ${(effectiveEventChance(event) * 100).toFixed(1)}%${trigger.reason ? ` ${trigger.reason}` : ""}`;
    })
    .slice(0, 8);
  const pending = Array.isArray(state.pendingEvents) ? state.pendingEvents : [];
  const pendingLines = pending.slice(0, 6).map((item) => `${item.dueDate} ${item.eventId} ${item.reason || ""}`.trim());
  const lines = [
    "事件调试",
    `金钱 ${signed(Number(state.money || 0))} 心情 ${state.mood} 健康 ${state.health}`,
    `负债 ${debtInfo().label}`,
    `待触发 ${pending.length} 个`,
    ...(pendingLines.length > 0 ? pendingLines : ["暂无待触发后续事件"]),
    "状态驱动概率",
    ...(triggerEvents.length > 0 ? triggerEvents : ["暂无状态驱动事件"])
  ];
  return lines.join("\n");
}

function recordEventEntry({ date, category, name, message, moneyDelta, moodDelta, healthDelta, source, refId, reason = "", index = 0 }) {
  const id = ledgerId(date, source, refId || name, index);
  if (eventLog.some((entry) => entry.id === id)) {
    return;
  }
  eventLog.push({
    id,
    date,
    category,
    name,
    message,
    moneyDelta,
    moodDelta,
    healthDelta,
    source,
    eventId: refId || "",
    reason,
    severity: eventSeverity({ moneyDelta, moodDelta, healthDelta })
  });
  writeJson(eventLogPath, eventLog);
}

function eventAlreadyApplied(day, eventId) {
  return eventLog.some((entry) => (
    entry.date === day
    && (entry.eventId === eventId || String(entry.id || "").includes(`:${eventId}:`))
  ));
}

function eventCategoryAlreadyApplied(day, category) {
  return eventLog.some((entry) => entry.date === day && entry.category === category);
}

function daysBetween(fromDay, toDay) {
  const from = parseDay(fromDay);
  const to = parseDay(toDay);
  if (!from || !to) {
    return Infinity;
  }
  return Math.round((to - from) / 86400000);
}

function eventBubbleMessage(entry) {
  return {
    label: (entry.severity || eventSeverity(entry)) === "urgent" ? `紧急 · ${entry.category || "生活事件"}` : entry.category || "生活事件",
    text: `${entry.message || entry.name}\n金钱 ${signed(entry.moneyDelta || 0)} 心情 ${signed(entry.moodDelta || 0)} 健康 ${signed(entry.healthDelta || 0)}`,
    severity: entry.severity || eventSeverity(entry)
  };
}

function severityRank(severity) {
  return { urgent: 3, important: 2, normal: 1 }[severity] || 1;
}

function paceEventMessages(messages, maxDetails = 3) {
  const items = (messages || [])
    .map((message, index) => ({ ...message, severity: message.severity || "normal", index }))
    .sort((left, right) => severityRank(right.severity) - severityRank(left.severity) || left.index - right.index);
  if (items.length <= maxDetails) {
    return items;
  }

  const details = [];
  const picked = new Set();
  for (const item of items) {
    if (item.severity !== "normal" && details.length < maxDetails) {
      details.push(item);
      picked.add(item.index);
    }
  }
  for (const item of items) {
    if (details.length >= maxDetails) {
      break;
    }
    if (!picked.has(item.index)) {
      details.push(item);
      picked.add(item.index);
    }
  }

  const rest = items.filter((item) => !picked.has(item.index));
  if (rest.length > 0) {
    const names = rest
      .slice(0, 4)
      .map((item) => String(item.text || "").split("\n")[0])
      .filter(Boolean)
      .join("、");
    details.push({
      label: "今日小事",
      text: `还有 ${rest.length} 件生活小事已记入事件记录${names ? `\n${names}` : ""}`,
      severity: "normal"
    });
  }
  return details.map(({ index, ...message }) => message);
}

function broadcastNewEventLogEntries() {
  const latestEventLog = readJson(eventLogPath, []);
  if (!Array.isArray(latestEventLog)) {
    return;
  }

  const newEntries = latestEventLog.filter((entry) => entry.id && !announcedEventIds.has(entry.id));
  eventLog = latestEventLog;
  for (const entry of latestEventLog) {
    if (entry.id) {
      announcedEventIds.add(entry.id);
    }
  }

  if (newEntries.length > 0) {
    sendCallback("petQueueEventMessages", paceEventMessages(newEntries.map(eventBubbleMessage)));
  }
}

function dayString(date) {
  const year = date.getFullYear();
  const month = `${date.getMonth() + 1}`.padStart(2, "0");
  const day = `${date.getDate()}`.padStart(2, "0");
  return `${year}-${month}-${day}`;
}

function parseDay(day) {
  const [year, month, date] = day.split("-").map(Number);
  if (!year || !month || !date) {
    return null;
  }
  return new Date(year, month - 1, date);
}

function addDays(date, count) {
  const next = new Date(date);
  next.setDate(next.getDate() + count);
  return next;
}

function addDaysString(day, count) {
  const parsed = parseDay(day);
  return parsed ? dayString(addDays(parsed, count)) : day;
}

function stableSeed(text) {
  let seed = 2166136261;
  for (const char of text) {
    seed ^= char.codePointAt(0);
    seed = Math.imul(seed, 16777619) >>> 0;
  }
  return seed >>> 0;
}

function shouldApplyRandomExpense(expense, day) {
  const value = (stableSeed(`${day}${expense.id}chance`) % 10000) / 10000;
  return value < Number(expense.chance || 0);
}

function randomAmount(expense, day) {
  const lower = Math.min(expense.minAmount, expense.maxAmount);
  const upper = Math.max(expense.minAmount, expense.maxAmount);
  const range = upper - lower + 1;
  return lower + (stableSeed(`${day}${expense.id}amount`) % range);
}

function debtRank(level) {
  return { none: 0, light: 1, pressure: 2, severe: 3 }[level] || 0;
}

function eventTriggerMatch(event) {
  const triggers = event.triggers || {};
  const reasons = [];

  if (Number.isFinite(Number(triggers.healthBelow)) && Number(state.health ?? 75) < Number(triggers.healthBelow)) {
    reasons.push("健康偏低");
  }
  if (Number.isFinite(Number(triggers.moodBelow)) && Number(state.mood ?? 70) < Number(triggers.moodBelow)) {
    reasons.push("心情偏低");
  }
  if (Number.isFinite(Number(triggers.moneyBelow)) && Number(state.money ?? 0) < Number(triggers.moneyBelow)) {
    reasons.push("现金紧张");
  }
  if (Number.isFinite(Number(triggers.moneyAbove)) && Number(state.money ?? 0) > Number(triggers.moneyAbove)) {
    reasons.push("现金充裕");
  }
  if (triggers.debtLevel && debtRank(debtInfo().level) >= debtRank(triggers.debtLevel)) {
    reasons.push("负债压力");
  }

  return {
    matched: reasons.length > 0,
    reason: reasons.length > 0 ? `由于${reasons.join("、")}，这件事更容易发生` : ""
  };
}

function effectiveEventChance(event) {
  let chance = Number(event.chance || 0);
  const health = Number(state.health ?? 75);
  if (event.healthSensitive) {
    chance *= 1 + Math.max(0, 80 - health) / 25;
  }
  const trigger = eventTriggerMatch(event);
  if (event.triggers) {
    chance *= trigger.matched ? 3.2 : 0.25;
  }
  return Math.min(0.8, chance);
}

function eventDiversityMultiplier(event, day) {
  let multiplier = 1;
  const recentSameEvent = eventLog.some((entry) => {
    const distance = daysBetween(entry.date, day);
    return distance > 0 && distance <= 14 && (entry.eventId === event.id || String(entry.id || "").includes(`:${event.id}:`));
  });
  if (recentSameEvent) {
    multiplier *= 0.18;
  }

  const recentSameCategoryCount = eventLog.filter((entry) => {
    const distance = daysBetween(entry.date, day);
    return distance > 0 && distance <= 3 && entry.category === event.category;
  }).length;
  if (recentSameCategoryCount > 0) {
    multiplier *= Math.max(0.35, 1 - recentSameCategoryCount * 0.22);
  }
  return multiplier;
}

function eventCalendarMultiplier(event, day) {
  const date = parseDay(day);
  if (!date) {
    return 1;
  }
  const weekday = date.getDay();
  const dayOfMonth = date.getDate();
  const category = event.category || "";
  let multiplier = 1;

  if (weekday === 0 || weekday === 6) {
    if (["娱乐", "家庭", "人情", "住房", "轻日常"].includes(category)) multiplier *= 1.45;
    if (["工作", "交通"].includes(category)) multiplier *= 0.55;
  } else {
    if (["工作", "交通", "餐饮"].includes(category)) multiplier *= 1.25;
    if (["娱乐", "家庭"].includes(category)) multiplier *= 0.9;
  }

  if (dayOfMonth <= 5) {
    if (["住房", "生活缴费", "财务", "教育"].includes(category)) multiplier *= 1.35;
  }
  if (dayOfMonth >= 25) {
    if (["财务", "生活缴费", "人情"].includes(category)) multiplier *= 1.25;
    if (["娱乐"].includes(category)) multiplier *= 0.85;
  }
  return multiplier;
}

function shouldApplyLifeEvent(event, day) {
  const value = (stableSeed(`${day}${event.id}life`) % 10000) / 10000;
  return value < effectiveEventChance(event) * eventDiversityMultiplier(event, day) * eventCalendarMultiplier(event, day);
}

function lifeEventMoney(event, day) {
  const lower = Math.min(Number(event.minMoneyDelta || 0), Number(event.maxMoneyDelta || 0));
  const upper = Math.max(Number(event.minMoneyDelta || 0), Number(event.maxMoneyDelta || 0));
  if (lower === upper) {
    return lower;
  }
  return lower + (stableSeed(`${day}${event.id}money`) % (upper - lower + 1));
}

function scheduleFollowUps(event, day, index) {
  const followUps = Array.isArray(event.followUps) ? event.followUps : [];
  if (followUps.length === 0) {
    return;
  }
  if (!Array.isArray(state.pendingEvents)) {
    state.pendingEvents = [];
  }

  for (const followUp of followUps) {
    const eventId = followUp.eventId;
    if (!eventId || !lifeEvents.some((item) => item.id === eventId)) {
      continue;
    }
    const chance = Number(followUp.chance ?? 1);
    const value = (stableSeed(`${day}${event.id}${eventId}${index}follow`) % 10000) / 10000;
    if (value >= chance) {
      continue;
    }

    const dueDate = addDaysString(day, Number(followUp.delayDays || 1));
    const id = `${dueDate}:followUp:${event.id}:${eventId}:${index}`;
    const exists = state.pendingEvents.some((item) => item.id === id);
    if (!exists) {
      state.pendingEvents.push({
        id,
        eventId,
        dueDate,
        sourceEventId: event.id,
        reason: `由「${event.name}」后续触发`
      });
    }
  }
}

function applyLifeEvent(event, day, index, source = "lifeEvent", reason = "") {
  const moneyDelta = lifeEventMoney(event, day);
  const moodDelta = Number(event.moodDelta || 0);
  const healthDelta = Number(event.healthDelta || 0);
  const weightDelta = Number(event.weightDelta || 0);
  const hairDelta = Number(event.hairDelta || 0);

  state.money += moneyDelta;
  state.mood = clamp(state.mood + moodDelta);
  state.health = clamp(Number(state.health ?? 75) + healthDelta);
  state.weight = clamp(state.weight + weightDelta);
  state.hair = clamp(state.hair + hairDelta);

  if (moneyDelta !== 0) {
    recordLedgerEntry({
      date: day,
      type: moneyDelta > 0 ? "income" : "eventExpense",
      category: event.category || "生活事件",
      name: event.name,
      amount: moneyDelta,
      source,
      refId: event.id,
      index
    });
  }

  recordEventEntry({
    date: day,
    category: event.category || "生活事件",
    name: event.name,
    message: event.message || event.name,
    moneyDelta,
    moodDelta,
    healthDelta,
    source,
    refId: event.id,
    reason,
    index
  });

  dailyEventMessages.push({
    label: event.category || "生活事件",
    text: `${event.message || event.name}\n金钱 ${signed(moneyDelta)} 心情 ${signed(moodDelta)} 健康 ${signed(healthDelta)}`,
    severity: eventSeverity({ moneyDelta, moodDelta, healthDelta })
  });

  scheduleFollowUps(event, day, index);
}

function processPendingEvents(day, limit) {
  if (!Array.isArray(state.pendingEvents)) {
    state.pendingEvents = [];
  }

  const pending = state.pendingEvents;
  const dueEvents = pending.filter((item) => item.dueDate <= day);
  state.pendingEvents = pending.filter((item) => item.dueDate > day);

  let applied = 0;
  let totalDelta = 0;
  for (const pendingEvent of dueEvents) {
    if (applied >= limit) {
      state.pendingEvents.push(pendingEvent);
      continue;
    }

    const event = lifeEvents.find((item) => item.id === pendingEvent.eventId);
    if (!event) {
      continue;
    }
    if (eventAlreadyApplied(day, event.id)) {
      continue;
    }
    const beforeMoney = state.money;
    applyLifeEvent(event, day, stableSeed(pendingEvent.id) % 10000, "followUp", pendingEvent.reason || "连续事件");
    totalDelta += state.money - beforeMoney;
    applied += 1;
  }

  state.pendingEvents.sort((a, b) => String(a.dueDate).localeCompare(String(b.dueDate)));
  return { applied, totalDelta };
}

function applyLightDailyEvent(day, index) {
  const candidates = (lifeEvents || []).filter((event) => event.category === "轻日常");
  if (candidates.length === 0 || eventCategoryAlreadyApplied(day, "轻日常")) {
    return 0;
  }
  const ordered = candidates
    .map((event) => ({ event, score: stableSeed(`${day}${event.id}lightDaily`) }))
    .sort((left, right) => left.score - right.score);

  for (const { event } of ordered) {
    if (eventAlreadyApplied(day, event.id)) {
      continue;
    }
    const beforeMoney = state.money;
    applyLifeEvent(event, day, index, "lightDaily", "无事件日补充轻日常");
    return state.money - beforeMoney;
  }
  return 0;
}

function settleDailyBudget(targetDate = new Date()) {
  const today = dayString(targetDate);
  if (!state.lastSettlementDate) {
    state.lastSettlementDate = today;
    writeJson(statePath, state);
    return null;
  }

  const lastDate = parseDay(state.lastSettlementDate);
  const todayDate = parseDay(today);
  if (!lastDate || !todayDate || lastDate >= todayDate) {
    return null;
  }

  let cursor = addDays(lastDate, 1);
  let days = 0;
  let total = 0;
  let latestRandomParts = [];
  dailyEventMessages = [];

  while (cursor <= todayDate) {
    const day = dayString(cursor);
    let dayTotal = Number(economy.dailyIncome || 0);
    latestRandomParts = [];
    state.health = clamp(Number(state.health ?? 75) - 1);

    state.money += Number(economy.dailyIncome || 0);
    recordLedgerEntry({
      date: day,
      type: "income",
      category: "工资",
      name: "日薪",
      amount: Number(economy.dailyIncome || 0),
      source: "dailySettlement",
      refId: "dailyIncome"
    });

    for (const expense of economy.fixedExpenses || []) {
      const amount = Number(expense.amount || 0);
      dayTotal += amount;
      state.money += amount;
      recordLedgerEntry({
        date: day,
        type: "fixedExpense",
        category: expense.category || "固定支出",
        name: expense.name,
        amount,
        source: "dailySettlement",
        refId: expense.id
      });
    }

    for (const [index, expense] of (economy.randomExpenses || []).entries()) {
      if (shouldApplyRandomExpense(expense, day)) {
        const amount = randomAmount(expense, day);
        dayTotal += amount;
        state.money += amount;
        recordLedgerEntry({
          date: day,
          type: "randomExpense",
          category: expense.category || "随机支出",
          name: expense.name,
          amount,
          source: "dailySettlement",
          refId: expense.id,
          index
        });
        latestRandomParts.push(`${expense.name} ${signed(amount)}`);
      }
    }

    const pendingResult = processPendingEvents(day, 3);
    let eventCount = pendingResult.applied;
    dayTotal += pendingResult.totalDelta;
    const orderedEvents = (lifeEvents || [])
      .map((event, index) => ({ event, index }))
      .sort((left, right) => stableSeed(`${day}${left.event.id}order`) - stableSeed(`${day}${right.event.id}order`));

    for (const { event, index } of orderedEvents) {
      if (eventCount >= 3) {
        break;
      }
      if (eventAlreadyApplied(day, event.id)) {
        continue;
      }
      if (eventCategoryAlreadyApplied(day, event.category || "生活事件")) {
        continue;
      }
      if (shouldApplyLifeEvent(event, day)) {
        const beforeMoney = state.money;
        applyLifeEvent(event, day, index, "lifeEvent", eventTriggerMatch(event).reason);
        dayTotal += state.money - beforeMoney;
        eventCount += 1;
      }
    }

    if (eventCount === 0) {
      const beforeMoney = state.money;
      const lightDelta = applyLightDailyEvent(day, 9000 + days);
      if (lightDelta !== 0 || state.money !== beforeMoney || eventCategoryAlreadyApplied(day, "轻日常")) {
        dayTotal += lightDelta;
      }
    }

    total += dayTotal;
    days += 1;
    cursor = addDays(cursor, 1);
  }

  const debtPenalty = debtMoodPenalty();
  state.mood = clamp(state.mood + (total < 0 ? -2 : 1) + debtPenalty);
  const derived = applyDerivedStateEffects();
  state.currentActivity = "待机";
  state.lastSettlementDate = today;
  writeJson(statePath, state);

  const fixedTotal = (economy.fixedExpenses || []).reduce((sum, item) => sum + Number(item.amount || 0), 0);
  const lines = [
    `已结算 ${days} 天`,
    `工资 +${Number(economy.dailyIncome || 0) * days}`,
    `固定支出 ${signed(fixedTotal * days)}`
  ];
  if (latestRandomParts.length > 0) {
    lines.push(...latestRandomParts);
  }
  lines.push(`合计 ${signed(total)}`);
  if (debtPenalty < 0) {
    lines.push(`负债压力 心情 ${signed(debtPenalty)}`);
  }
  if (derived.debt.level !== "none") {
    lines.push(`负债等级 ${derived.debt.label}`);
  }
  return lines.join("\n");
}

function debugAdvanceDay() {
  const today = dayString(new Date());
  const lastDate = parseDay(state.lastSettlementDate || today) || new Date();
  const summary = settleDailyBudget(addDays(lastDate, 1)) || "今天没有新的结算";
  publishState();
  return summary;
}

function debugSetStatePreset(preset) {
  const presets = {
    lowMood: { mood: 22, health: 58, money: Number(state.money || 0) },
    lowHealth: { mood: Number(state.mood ?? 70), health: 38, money: Number(state.money || 0) },
    debt: { mood: 34, health: Number(state.health ?? 75), money: -26000 }
  };
  const next = presets[preset];
  if (!next) {
    return "未知调试预设";
  }
  state.mood = clamp(next.mood);
  state.health = clamp(next.health);
  state.money = next.money;
  state.currentActivity = "待机";
  publishState();
  return `已设置调试状态\n金钱 ${signed(state.money)} 心情 ${state.mood} 健康 ${state.health}`;
}

function effectSummary(action) {
  const parts = [];
  if (action.moneyDelta !== 0) parts.push(`金钱 ${signed(action.moneyDelta)}`);
  if (action.moodDelta !== 0) parts.push(`心情 ${signed(action.moodDelta)}`);
  if (action.weightDelta !== 0) parts.push(`体重 ${signed(action.weightDelta)}`);
  if (action.hairDelta !== 0) parts.push(`发量 ${signed(action.hairDelta)}`);
  if (action.healthDelta !== 0) parts.push(`健康 ${signed(action.healthDelta)}`);
  return parts.length === 0 ? "属性没有变化" : parts.join("\n");
}

function validateSkill(skill) {
  if (!["/usr/bin/python3", "python3", "py", "python"].includes(skill.command)) {
    return "技能配置被拦截\n当前只允许使用 python";
  }

  const script = skill.args && skill.args[0];
  if (!script) {
    return "技能配置错误\n缺少脚本路径";
  }

  const resolvedScript = path.resolve(root, script);
  const skillsDir = path.join(root, "skills");
  if (!resolvedScript.startsWith(`${skillsDir}${path.sep}`)) {
    return "技能配置被拦截\n脚本必须放在 skills/ 目录";
  }

  if (!fs.existsSync(resolvedScript)) {
    return `找不到脚本\n${script}`;
  }

  return null;
}

function actionBlockReason(action) {
  if (Number(state.health ?? 75) < 25 && action.category === "exercise") {
    return "健康太低\n先休息或处理身体状态，再做高强度运动";
  }
  if (state.money < -50000 && action.moneyDelta < 0 && ["entertainment", "food"].includes(action.category)) {
    return "负债压力太大\n这类消费先缓一缓，等现金流恢复再说";
  }
  if (Number(state.mood ?? 70) < 15 && action.category === "work") {
    return "心情太低\n现在硬扛工作效率很差，先做点恢复心情的事";
  }
  return null;
}

function resolveCommand(command) {
  if (process.platform === "win32" && ["/usr/bin/python3", "python3"].includes(command)) {
    return "py";
  }
  return command === "/usr/bin/python3" ? "python3" : command;
}

function resolveSkillArgs(args) {
  return args.map((arg) => {
    if (arg.startsWith("skills/") || arg.startsWith("./")) {
      return path.resolve(root, arg);
    }
    return arg;
  });
}

function runSkill(skillId) {
  const skill = skills.find((item) => item.id === skillId);
  if (!skill) {
    sendSkillResult(`找不到这个小技能\n${skillId}`, "小技能");
    return;
  }

  const validationError = validateSkill(skill);
  if (validationError) {
    sendSkillResult(validationError, skill.name);
    return;
  }

  const outputLimit = skill.outputLimit || 500;
  const timeoutMs = Math.max(1, skill.timeoutSeconds || 10) * 1000;
  const child = spawn(resolveCommand(skill.command), resolveSkillArgs(skill.args), {
    cwd: root,
    shell: false,
    windowsHide: true
  });

  let stdout = "";
  let stderr = "";
  let timedOut = false;
  const timer = setTimeout(() => {
    timedOut = true;
    child.kill();
  }, timeoutMs);

  child.stdout.on("data", (chunk) => {
    stdout += chunk.toString("utf8");
  });

  child.stderr.on("data", (chunk) => {
    stderr += chunk.toString("utf8");
  });

  child.on("error", (error) => {
    clearTimeout(timer);
    sendSkillResult(`脚本启动失败\n${error.message}`, skill.name);
  });

  child.on("close", (code) => {
    clearTimeout(timer);
    const limit = (text) => (text.length > outputLimit ? `${text.slice(0, outputLimit)}\n...` : text);
    if (timedOut) {
      sendSkillResult(`脚本运行超时\n已在 ${Math.round(timeoutMs / 1000)} 秒后停止`, skill.name);
      return;
    }

    const cleanStdout = stdout.trim();
    const cleanStderr = stderr.trim();
    if (code === 0) {
      sendSkillResult(cleanStdout ? limit(cleanStdout) : "脚本运行完成\n没有输出内容", skill.name);
      return;
    }

    sendSkillResult(`脚本运行失败\n${limit(cleanStderr || `退出码 ${code}`)}`, skill.name);
  });
}

function applyPetAction(actionId) {
  if (activeActionId) {
    sendSkillResult("现在正在忙\n等当前行动结束再来吧", state.currentActivity);
    return;
  }

  const action = actions.find((item) => item.id === actionId);
  if (!action) {
    sendSkillResult(`找不到这个行动\n${actionId}`, "行动");
    return;
  }

  const blockReason = actionBlockReason(action);
  if (blockReason) {
    sendSkillResult(blockReason, "行动受限");
    return;
  }

  activeActionId = action.id;
  state.currentActivity = action.name;
  writeJson(statePath, state);
  sendSkillResult(action.startMessage, action.name);
  sendState();
  sendActivityStarted(action);

  setTimeout(() => {
    if (activeActionId !== action.id) {
      return;
    }

    activeActionId = null;
    state.money += action.moneyDelta;
    state.mood = clamp(state.mood + action.moodDelta);
    state.weight = clamp(state.weight + action.weightDelta);
    state.hair = clamp(state.hair + action.hairDelta);
    state.health = clamp(Number(state.health ?? 75) + Number(action.healthDelta || 0));
    applyDerivedStateEffects();
    state.currentActivity = "待机";
    writeJson(statePath, state);
    recordLedgerEntry({
      date: dayString(new Date()),
      type: action.moneyDelta >= 0 ? "income" : "expense",
      category: action.category,
      name: action.name,
      amount: action.moneyDelta,
      source: "petAction",
      refId: `${action.id}:${Date.now()}`
    });
    sendSkillResult(`${action.finishMessage}\n${effectSummary(action)}`, action.name);
    sendState();
    sendActivityEnded();
  }, Math.max(1, action.durationSeconds) * 1000);
}

function saveWindowFrame() {
  if (!mainWindow || mainWindow.isDestroyed()) {
    return;
  }
  const bounds = mainWindow.getBounds();
  settings.windowX = bounds.x;
  settings.windowY = bounds.y;
  settings.windowWidth = bounds.width;
  settings.windowHeight = bounds.height;
  writeJson(settingsPath, settings);
}

function toggleAlwaysOnTop() {
  settings.alwaysOnTop = !settings.alwaysOnTop;
  mainWindow.setAlwaysOnTop(settings.alwaysOnTop, "floating");
  writeJson(settingsPath, settings);
  sendSettings();
  sendSkillResult(settings.alwaysOnTop ? "已开启置顶" : "已关闭置顶", "设置");
}

function toggleStats() {
  settings.showStats = !settings.showStats;
  writeJson(settingsPath, settings);
  sendSettings();
  sendSkillResult(settings.showStats ? "已显示状态面板" : "已隐藏状态面板", "设置");
}

function showContextMenu() {
  const menu = Menu.buildFromTemplate([
    {
      label: settings.alwaysOnTop ? "关闭置顶" : "开启置顶",
      click: toggleAlwaysOnTop
    },
    {
      label: settings.showStats ? "隐藏状态面板" : "显示状态面板",
      click: toggleStats
    },
    { type: "separator" },
    {
      label: "退出",
      click: () => app.quit()
    }
  ]);
  menu.popup({ window: mainWindow });
}

function createWindow() {
  mainWindow = new BrowserWindow({
    x: Math.round(settings.windowX),
    y: Math.round(settings.windowY),
    width: Math.round(settings.windowWidth),
    height: Math.round(settings.windowHeight),
    frame: false,
    transparent: true,
    resizable: true,
    hasShadow: false,
    skipTaskbar: true,
    alwaysOnTop: settings.alwaysOnTop,
    webPreferences: {
      preload: path.join(__dirname, "preload.js"),
      contextIsolation: true,
      nodeIntegration: false
    }
  });

  mainWindow.setAlwaysOnTop(settings.alwaysOnTop, "floating");
  mainWindow.loadFile(path.join(root, "desktop", "desktop-pet.html"));
  mainWindow.once("ready-to-show", bootstrapRenderer);
  mainWindow.on("move", saveWindowFrame);
  mainWindow.on("resize", saveWindowFrame);
  mainWindow.webContents.on("context-menu", showContextMenu);
}

function watchEventLog() {
  fs.mkdirSync(dataDir, { recursive: true });
  fs.watchFile(eventLogPath, { interval: 1200 }, broadcastNewEventLogEntries);
}

ipcMain.on("pet-message", (_event, body) => {
  const action = typeof body === "string" ? body : body && body.action;
  if (!action) {
    return;
  }

  if (action === "runSkill") runSkill(body.skillId);
  if (action === "petAction") applyPetAction(body.actionId);
  if (action === "toggleAlwaysOnTop") toggleAlwaysOnTop();
  if (action === "toggleStats") toggleStats();
  if (action === "showLedger") sendCallback("petLedgerResult", { entries: ledgerSummary(24) });
  if (action === "showEvents") sendCallback("petEventLogResult", { entries: eventSummary(24) });
  if (action === "showLedgerStats") sendCallback("petLedgerStatsResult", { stats: ledgerMonthlyStats() });
  if (action === "showEventDebug") sendSkillResult(eventDebugSummary(), "事件调试");
  if (action === "debugAdvanceDay") sendSkillResult(debugAdvanceDay(), "推进一天");
  if (action === "debugSetStatePreset") sendSkillResult(debugSetStatePreset(body.preset), "调试状态");
  if (action === "quit") app.quit();
});

app.whenReady().then(() => {
  loadRuntimeData();
  createWindow();
  watchEventLog();
});

app.on("before-quit", () => {
  fs.unwatchFile(eventLogPath, broadcastNewEventLogEntries);
  saveWindowFrame();
});

app.on("window-all-closed", () => {
  app.quit();
});
