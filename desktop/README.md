# Desktop Pet Prototype

This is the first native desktop shell for the pet.

## Run

Build the macOS prototype:

```bash
swiftc desktop/DesktopPet.swift -o build/DesktopPet -framework Cocoa -framework WebKit
```

Run it from the project root so the app can resolve local assets:

```bash
./build/DesktopPet
```

## Current Features

- Transparent floating desktop window
- Character idle animation
- Click pet to open a small interaction menu
- Work, meeting, and skill buttons
- Loads skill buttons from `skills/skills.json`
- Runs configured Python skills and shows stdout in the speech bubble
- Drag the empty window area to move the pet

## Skill Config

Add skill entries to `skills/skills.json`:

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

The desktop shell loads these entries on launch, adds one menu button per skill,
and runs the configured command when that button is clicked.
