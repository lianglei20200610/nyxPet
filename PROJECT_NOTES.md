# Desktop Pet Game Notes

## Project Goal

Build a macOS desktop pet / lightweight companion game. The pet lives in a floating transparent desktop window, supports simple interactions, and can run local Python scripts as "small skills" with the output shown in the pet's speech bubble.

## Current Character Direction

- Main character reference: `assets/character/main-character-reference.jpg`
- The character should stay faithful to this image:
  - chibi proportions
  - blond hair
  - blue eyes
  - white outfit
- Do not add unrelated new design features unless explicitly requested.

## Current Features

- Browser idle preview: `animations/idle-preview.html`
- Desktop app shell:
  - `desktop/DesktopPet.swift`
  - `desktop/desktop-pet.html`
- Transparent floating macOS window using AppKit + WebKit.
- Idle animation using the approved character image.
- Click the pet to open a small menu.
- Built-in interaction buttons:
  - work
  - meeting
- Config-driven skill buttons loaded from `skills/skills.json`.
- Clicking a skill runs a configured command and shows stdout in the speech bubble.

## How To Run

From the project root:

```bash
./desktop/run-desktop-pet.sh
```

The script compiles the Swift desktop shell and launches `build/DesktopPet`.

If Swift tries to write module cache outside the project, keep using the existing script; it sets the module cache under `build/ModuleCache`.

## Skill System

Skill config lives in:

```text
skills/skills.json
```

Current example:

```json
[
  {
    "id": "test",
    "name": "测试脚本",
    "icon": "✨",
    "command": "/usr/bin/python3",
    "args": ["skills/test_skill.py"]
  }
]
```

The current test script is:

```text
skills/test_skill.py
```

Expected flow:

```text
Launch pet -> read skills/skills.json -> generate skill menu buttons -> click skill -> run command -> show stdout in bubble
```

## Verified So Far

- Swift desktop shell compiles with:

```bash
swiftc -module-cache-path build/ModuleCache desktop/DesktopPet.swift -o build/DesktopPet -framework Cocoa -framework WebKit
```

- Test script runs with:

```bash
/usr/bin/python3 skills/test_skill.py
```

- Desktop app launch smoke test passed. macOS may print service logs, but the app does not immediately crash.

## Next Steps

1. Add safety limits for skill execution:
   - only allow scripts inside `skills/`
   - timeout long-running scripts
   - show stderr cleanly
2. Add support for the real overtime script.
3. Add persistent pet stats:
   - mood
   - weight
   - hair
   - money
4. Add action settlement:
   - work earns money
   - meeting earns less and lowers mood
   - eating changes mood and weight
   - exercise reduces weight
5. Improve desktop UX:
   - close / settings menu
   - remember window position
   - optional always-on-top toggle
6. Later, consider packaging into a normal `.app`.

## Sync Plan

Use a private Git repository to move between home and work machines.

Typical workflow:

```bash
git pull
# work
git add .
git commit -m "Describe the change"
git push
```

Keep generated build outputs ignored. Commit source files, character assets, skill configs, and notes.

