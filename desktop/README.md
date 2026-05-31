# Desktop Pet Prototype

This project has two desktop shells that share the same pet UI:

- macOS native shell: `desktop/DesktopPet.swift`
- Windows/macOS cross-platform shell: `desktop/electron/main.js`

## Run

### Cross-platform Electron shell

Install Node.js LTS first. Then run:

```bash
npm install
npm run start:electron
```

On macOS you can also use:

```bash
./desktop/run-electron-pet.sh
```

On Windows PowerShell:

```powershell
powershell -ExecutionPolicy Bypass -File .\desktop\run-electron-pet.ps1
```

### macOS native shell

Build the macOS native prototype:

```bash
mkdir -p build/ModuleCache
swiftc -module-cache-path build/ModuleCache \
  desktop/DesktopPet.swift \
  -o build/DesktopPet \
  -framework Cocoa \
  -framework WebKit
```

Run it from the project root so the app can resolve local assets:

```bash
./build/DesktopPet
```

Or use:

```bash
./desktop/run-desktop-pet.sh
```

## Current Features

- Transparent floating desktop window
- Character idle animation
- Click pet to open a small interaction menu
- Work, meeting, and skill buttons
- Loads skill buttons from `skills/skills.json`
- Runs configured Python skills and shows stdout in the speech bubble
- Drag the empty window area to move the pet
- Electron shell runs on Windows and macOS
- Persists money, mood, weight, hair, health, and daily settlement state in `data/pet-state.json`
- Records every income and expense in `data/ledger.json`
- Records notable life events in `data/events.json`
- Supports debt levels, action limits, and monthly ledger stats in the Electron shell

## Economy Config

Daily salary and recurring expenses live in `actions/economy.json`. The current
baseline models an ordinary salaried worker:

- Daily income: 500
- Fixed daily deductions: mortgage, child education, family meals, commute, utilities
- Random daily deductions: small miscellaneous costs and occasional family support

The app only settles a date once. When it starts after one or more missed days,
it applies each missed day's salary and expenses, saves the new state, and shows
a "今日收支" summary bubble.

Health slowly declines during daily settlement. Exercise and healthy leisure can
raise it, while overtime, sickness, bad sleep, and some random events reduce it.
Lower health increases the probability of health-sensitive medical events.
If money falls below zero, the pet enters debt. Income first offsets the negative
balance, and debt pressure reduces mood during settlement. Severe debt can block
some optional spending actions, while very low health can block exercise.

## Ledger

The ledger lives in `data/ledger.json`. Each entry records:

- Date
- Income or expense type
- Category
- Name
- Amount
- Balance after the transaction
- Source, such as daily settlement or pet action

Open the settings menu and click `账` to view the latest ledger entries in the
speech bubble. Ledger bubbles stay visible longer, are scrollable, and render
income in green and expenses in red.

Click `统` to view the current month's income, expense, net balance, and category
totals.

## Life Events

Random life events live in `actions/life-events.json`. The current set contains
100+ ordinary life events, including sickness, weddings, family support, work
pressure, bonuses, traffic, home repair, entertainment, financial surprises, and
small mood events. When missed days are settled on launch, occurred events are
saved to `data/events.json` and replayed quickly through speech bubbles.

Open the settings menu and click `事` to view recent event records.

## Packaging

Electron packaging scripts are available after installing dependencies:

```bash
npm install
npm run dist:mac
npm run dist:win
```

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

On Windows, the Electron shell maps `/usr/bin/python3` and `python3` to the
Python launcher command `py`, so the same `skills/skills.json` can be shared
between macOS and Windows.
