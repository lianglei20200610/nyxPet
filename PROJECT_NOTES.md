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
- Skill execution has basic stability controls:
  - only local `python3` skills are allowed
  - scripts must live under `skills/`
  - timed-out scripts are stopped
  - long output is trimmed
- Pet stats are saved in `data/pet-state.json`.
- Work and meeting update mood, hair, and money.
- Gameplay actions are loaded from `actions/actions.json`.
- Actions support duration, start message, finish message, and stat deltas.
- The pet shows a small activity progress panel while actions are running.
- The interaction menu is grouped by category, with a compact second-level submenu for actions and skills.

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
    "args": ["skills/test_skill.py"],
    "timeoutSeconds": 10,
    "outputLimit": 500
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

## Action System

Action config lives in:

```text
actions/actions.json
```

Each action includes:

- `id`
- `name`
- `icon`
- `category`
- `durationSeconds`
- `moodDelta`
- `weightDelta`
- `hairDelta`
- `moneyDelta`
- `startMessage`
- `finishMessage`

Current actions:

- work
- meeting
- meal
- drink
- exercise

To add the real overtime script, copy it into `skills/`, for example:

```text
skills/overtime.py
```

Then add another entry to `skills/skills.json`.

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

1. Add support for the real overtime script.
2. Add more actions:
   - badminton
   - cycling
   - card game
   - alcohol
   - buffet
3. Improve desktop UX:
   - close / settings menu
   - remember window position
   - optional always-on-top toggle
4. Later, consider packaging into a normal `.app`.

More planning details live in `GAME_ROADMAP.md`.

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
