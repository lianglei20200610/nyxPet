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
  lastSettlementDate: null
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
    durationSeconds: action.durationSeconds
  });
}

function sendActivityEnded() {
  sendJavaScript("window.petActivityEnded();");
}

function bootstrapRenderer() {
  const publicSkills = skills.map(({ id, name, icon }) => ({ id, name, icon }));
  const publicActions = actions.map(({ id, name, icon, category, durationSeconds }) => ({
    id,
    name,
    icon,
    category,
    durationSeconds
  }));

  sendCallback("petLoadSkills", publicSkills);
  sendCallback("petLoadActions", publicActions);
  sendState();
  sendSettings();
  if (dailySettlementMessage) {
    sendSkillResult(dailySettlementMessage, "今日收支");
  }
  if (dailyEventMessages.length > 0) {
    sendCallback("petQueueEventMessages", dailyEventMessages);
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
  if (money >= 0) return { level: "none", label: "无负债", moodPenalty: 0 };
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
      severity: entry.severity || eventSeverity(entry)
    }));
}

function recordEventEntry({ date, category, name, message, moneyDelta, moodDelta, healthDelta, source, refId, index = 0 }) {
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
    severity: eventSeverity({ moneyDelta, moodDelta, healthDelta })
  });
  writeJson(eventLogPath, eventLog);
}

function eventBubbleMessage(entry) {
  return {
    label: (entry.severity || eventSeverity(entry)) === "urgent" ? `紧急 · ${entry.category || "生活事件"}` : entry.category || "生活事件",
    text: `${entry.message || entry.name}\n金钱 ${signed(entry.moneyDelta || 0)} 心情 ${signed(entry.moodDelta || 0)} 健康 ${signed(entry.healthDelta || 0)}`,
    severity: entry.severity || eventSeverity(entry)
  };
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
    sendCallback("petQueueEventMessages", newEntries.slice(-5).map(eventBubbleMessage));
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

function effectiveEventChance(event) {
  const baseChance = Number(event.chance || 0);
  if (!event.healthSensitive) {
    return baseChance;
  }
  const health = Number(state.health ?? 75);
  const multiplier = 1 + Math.max(0, 80 - health) / 25;
  return Math.min(0.8, baseChance * multiplier);
}

function shouldApplyLifeEvent(event, day) {
  const value = (stableSeed(`${day}${event.id}life`) % 10000) / 10000;
  return value < effectiveEventChance(event);
}

function lifeEventMoney(event, day) {
  const lower = Math.min(Number(event.minMoneyDelta || 0), Number(event.maxMoneyDelta || 0));
  const upper = Math.max(Number(event.minMoneyDelta || 0), Number(event.maxMoneyDelta || 0));
  if (lower === upper) {
    return lower;
  }
  return lower + (stableSeed(`${day}${event.id}money`) % (upper - lower + 1));
}

function applyLifeEvent(event, day, index) {
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
      source: "lifeEvent",
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
    source: "lifeEvent",
    refId: event.id,
    index
  });

  dailyEventMessages.push({
    label: event.category || "生活事件",
    text: `${event.message || event.name}\n金钱 ${signed(moneyDelta)} 心情 ${signed(moodDelta)} 健康 ${signed(healthDelta)}`,
    severity: eventSeverity({ moneyDelta, moodDelta, healthDelta })
  });
}

function settleDailyBudget() {
  const today = dayString(new Date());
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

    let eventCount = 0;
    for (const [index, event] of (lifeEvents || []).entries()) {
      if (eventCount >= 3) {
        break;
      }
      if (shouldApplyLifeEvent(event, day)) {
        const beforeMoney = state.money;
        applyLifeEvent(event, day, index);
        dayTotal += state.money - beforeMoney;
        eventCount += 1;
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
