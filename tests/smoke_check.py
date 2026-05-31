#!/usr/bin/env python3
import json
import re
import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def fail(message):
    raise SystemExit(f"SMOKE_CHECK=fail\n{message}")


def read_json(path):
    with path.open(encoding="utf-8") as handle:
        return json.load(handle)


def require(condition, message):
    if not condition:
        fail(message)


def check_configs():
    skills = read_json(ROOT / "skills" / "skills.json")
    actions = read_json(ROOT / "actions" / "actions.json")
    economy = read_json(ROOT / "actions" / "economy.json")
    life_events = read_json(ROOT / "actions" / "life-events.json")

    require(isinstance(skills, list), "skills.json must be a list")
    require(isinstance(actions, list), "actions.json must be a list")
    require(actions, "actions.json must contain at least one action")
    require(isinstance(life_events, list), "life-events.json must be a list")
    require(len(life_events) >= 100, "life-events.json must contain at least 100 life events")
    require(economy.get("dailyIncome") == 500, "economy.json dailyIncome should model a 500 yuan workday")
    require(isinstance(economy.get("fixedExpenses"), list), "economy.json fixedExpenses must be a list")
    require(isinstance(economy.get("randomExpenses"), list), "economy.json randomExpenses must be a list")

    for index, expense in enumerate(economy["fixedExpenses"]):
        for field in ["id", "name", "category", "amount"]:
            require(field in expense, f"fixedExpenses[{index}] missing {field}")
        require(expense["amount"] <= 0, f"fixedExpenses[{index}] amount should be a deduction")

    for index, expense in enumerate(economy["randomExpenses"]):
        for field in ["id", "name", "category", "minAmount", "maxAmount", "chance"]:
            require(field in expense, f"randomExpenses[{index}] missing {field}")
        require(expense["minAmount"] <= expense["maxAmount"], f"randomExpenses[{index}] minAmount must be <= maxAmount")
        require(expense["maxAmount"] <= 0, f"randomExpenses[{index}] should be a deduction")
        require(0 <= expense["chance"] <= 1, f"randomExpenses[{index}] chance must be between 0 and 1")
    require(len(economy["randomExpenses"]) >= 8, "economy.json should include a realistic random expense pool")

    event_ids = set()
    for index, event in enumerate(life_events):
        for field in ["id", "name", "category", "message", "chance", "minMoneyDelta", "maxMoneyDelta", "moodDelta", "healthDelta"]:
            require(field in event, f"lifeEvents[{index}] missing {field}")
        require(event["id"] not in event_ids, f"duplicate life event id: {event['id']}")
        event_ids.add(event["id"])
        require(0 <= event["chance"] <= 1, f"lifeEvents[{index}] chance must be between 0 and 1")
        require(event["minMoneyDelta"] <= event["maxMoneyDelta"], f"lifeEvents[{index}] minMoneyDelta must be <= maxMoneyDelta")

    skill_ids = set()
    for index, skill in enumerate(skills):
        for field in ["id", "name", "icon", "command", "args"]:
            require(field in skill, f"skills[{index}] missing {field}")

        require(skill["id"] not in skill_ids, f"duplicate skill id: {skill['id']}")
        skill_ids.add(skill["id"])
        require(
            skill["command"] in {"/usr/bin/python3", "python3"},
            f"skills[{index}] command is blocked by DesktopPet validator: {skill['command']}",
        )
        require(skill["args"], f"skills[{index}] missing script argument")

        script_arg = skill["args"][0]
        require(script_arg.startswith("skills/"), f"skills[{index}] script must live under skills/: {script_arg}")
        require((ROOT / script_arg).is_file(), f"skills[{index}] script not found: {script_arg}")

    action_ids = set()
    required_action_fields = [
        "id",
        "name",
        "icon",
        "category",
        "durationSeconds",
        "moodDelta",
        "weightDelta",
        "hairDelta",
        "healthDelta",
        "moneyDelta",
        "startMessage",
        "finishMessage",
    ]
    for index, action in enumerate(actions):
        for field in required_action_fields:
            require(field in action, f"actions[{index}] missing {field}")

        require(action["id"] not in action_ids, f"duplicate action id: {action['id']}")
        action_ids.add(action["id"])
        require(action["durationSeconds"] > 0, f"actions[{index}] durationSeconds must be positive")

    return len(skills), len(actions)


def check_html_contract():
    html = (ROOT / "desktop" / "desktop-pet.html").read_text(encoding="utf-8")

    required_callbacks = [
        "window.petSkillResult",
        "window.petStateUpdated",
        "window.petSettingsUpdated",
        "window.petLoadActions",
        "window.petLoadSkills",
        "window.petActivityStarted",
        "window.petActivityEnded",
        "window.petLedgerResult",
        "window.petEventLogResult",
        "window.petQueueEventMessages",
    ]
    for callback in required_callbacks:
        require(callback in html, f"missing browser callback: {callback}")

    required_messages = [
        'action: "runSkill"',
        'action: "petAction"',
        'action: "toggleAlwaysOnTop"',
        'action: "toggleStats"',
        'action: "showLedger"',
        'action: "showEvents"',
        'action: "quit"',
        'postMessage("drag")',
    ]
    for message in required_messages:
        require(message in html, f"missing WebKit message path: {message}")

    required_pet_contract = [
        "sprite-pet",
        "spritesheet.webp",
        "spriteStates",
        "playSpriteState",
        "--sprite-col",
        "--sprite-row",
        "setPetMode",
        "is-working",
        "is-food",
        "is-exercise",
        "is-entertainment",
        "is-skill",
    ]
    for item in required_pet_contract:
        require(item in html, f"missing Codex pet display contract: {item}")

    forbidden_sprite_contract = [
        "@keyframes sprite-idle",
        "@keyframes sprite-work",
        "@keyframes sprite-exercise",
        "@keyframes sprite-food",
        "@keyframes sprite-entertainment",
        "@keyframes sprite-skill",
    ]
    for item in forbidden_sprite_contract:
        require(item not in html, f"spritesheet frames must be discrete JS frame switches, not CSS scrolling: {item}")

    require("-webkit-app-region: drag" in html, "desktop HTML must expose an Electron drag region")
    require("-webkit-app-region: no-drag" in html, "desktop HTML must mark controls as no-drag for Electron")
    require("暂无事件记录" in html, "event log empty state must not reuse ledger empty state")
    require("function showEvents" in html, "desktop HTML must render event log separately from ledger")
    require(".pet {" in html and "-webkit-app-region: drag" in html, "pet body should be draggable")

    asset_refs = re.findall(r'(?:url\([\"\']?([^\"\')]+)[\"\']?\)|<img[^>]+src="([^"]+)")', html)
    asset_refs = [css_ref or img_ref for css_ref, img_ref in asset_refs]
    require(asset_refs, "desktop HTML must reference at least one image asset")
    for ref in asset_refs:
        require((ROOT / "desktop" / ref).resolve().is_file(), f"missing CSS image asset: {ref}")

    pet_manifest = ROOT / "assets" / "codex-pets" / "goku-forms" / "pet.json"
    pet_spritesheet = ROOT / "assets" / "codex-pets" / "goku-forms" / "spritesheet.webp"
    require(pet_manifest.is_file(), "missing goku-forms pet.json")
    require(pet_spritesheet.is_file(), "missing goku-forms spritesheet.webp")

    manifest = read_json(pet_manifest)
    require(manifest.get("id") == "goku-forms", "goku-forms pet.json has wrong id")
    require(manifest.get("spritesheetPath") == "spritesheet.webp", "goku-forms pet.json has wrong spritesheetPath")


def check_electron_shell():
    package_json = read_json(ROOT / "package.json")
    require(package_json.get("main") == "desktop/electron/main.js", "package.json main must point to Electron main process")
    scripts = package_json.get("scripts", {})
    require(scripts.get("start:electron") == "electron .", "package.json missing start:electron script")
    require("dist:mac" in scripts and "dist:win" in scripts, "package.json missing cross-platform packaging scripts")
    require("electron" in package_json.get("devDependencies", {}), "package.json missing Electron devDependency")
    require("electron-builder" in package_json.get("devDependencies", {}), "package.json missing electron-builder devDependency")

    main_js = (ROOT / "desktop" / "electron" / "main.js").read_text(encoding="utf-8")
    preload_js = (ROOT / "desktop" / "electron" / "preload.js").read_text(encoding="utf-8")

    main_contract = [
        "BrowserWindow",
        'ipcMain.on("pet-message"',
        "desktop-pet.html",
        "economy.json",
        "life-events.json",
        "settleDailyBudget",
        "lastSettlementDate",
        "ledger.json",
        "events.json",
        "applyLifeEvent",
        "healthSensitive",
        "watchEventLog",
        "fs.watchFile",
        "recordLedgerEntry",
        "ledgerSummary",
        "eventSummary",
        "ledgerMonthlyStats",
        "actionBlockReason",
        "applyDerivedStateEffects",
        "petLoadSkills",
        "petLoadActions",
        "petStateUpdated",
        "petSettingsUpdated",
        "setAlwaysOnTop",
        "process.platform === \"win32\"",
        "py",
    ]
    for item in main_contract:
        require(item in main_js, f"Electron main process missing contract: {item}")
    require("debtMoodPenalty" in main_js, "Electron shell must apply mood pressure when money is negative")
    require("debtInfo" in main_js, "Electron shell must expose debt levels")
    require("Math.max(0, state.money +" not in main_js, "Electron shell must allow negative money balances")
    for debug_action in ["debugTriggerEvent", "debugIncome", "debugSick", "resetSave", "exportData"]:
        require(debug_action not in main_js, f"debug action should not ship in production shell: {debug_action}")

    preload_contract = [
        "contextBridge.exposeInMainWorld",
        "messageHandlers",
        "postMessage",
        "pet-message",
    ]
    for item in preload_contract:
        require(item in preload_js, f"Electron preload missing WebKit bridge contract: {item}")

    gitignore = (ROOT / ".gitignore").read_text(encoding="utf-8")
    require("node_modules/" in gitignore, ".gitignore must ignore node_modules/")


def check_swift_build():
    swift = (ROOT / "desktop" / "DesktopPet.swift").read_text(encoding="utf-8")
    for item in ["EconomyConfig", "LifeEventConfig", "LedgerEntry", "LifeEventLogEntry", "settleDailyBudget", "lastSettlementDate", "data/ledger.json", "data/events.json", "recordLedgerEntry", "applyLifeEvent", "healthSensitive", "newEventMessages", "startEventLogPolling"]:
        require(item in swift, f"Swift desktop shell missing economy persistence contract: {item}")
    require("debtMoodPenalty" in swift, "Swift desktop shell must apply mood pressure when money is negative")
    require("max(0, state.money +" not in swift, "Swift desktop shell must allow negative money balances")

    build_dir = ROOT / "build"
    module_cache = build_dir / "ModuleCache"
    build_dir.mkdir(exist_ok=True)
    module_cache.mkdir(exist_ok=True)

    command = [
        "swiftc",
        "-module-cache-path",
        str(module_cache),
        "desktop/DesktopPet.swift",
        "-o",
        "build/DesktopPet",
        "-framework",
        "Cocoa",
        "-framework",
        "WebKit",
    ]
    subprocess.run(command, cwd=ROOT, check=True)


def main():
    skill_count, action_count = check_configs()
    check_html_contract()
    check_electron_shell()
    check_swift_build()
    print("SMOKE_CHECK=pass")
    print(f"skills={skill_count} actions={action_count}")


if __name__ == "__main__":
    main()
