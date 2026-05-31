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

    require(isinstance(skills, list), "skills.json must be a list")
    require(isinstance(actions, list), "actions.json must be a list")
    require(actions, "actions.json must contain at least one action")

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
    ]
    for callback in required_callbacks:
        require(callback in html, f"missing browser callback: {callback}")

    required_messages = [
        'action: "runSkill"',
        'action: "petAction"',
        'action: "toggleAlwaysOnTop"',
        'action: "toggleStats"',
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


def check_swift_build():
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
    check_swift_build()
    print("SMOKE_CHECK=pass")
    print(f"skills={skill_count} actions={action_count}")


if __name__ == "__main__":
    main()
