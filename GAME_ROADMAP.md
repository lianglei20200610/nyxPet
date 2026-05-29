# Desktop Pet Roadmap

## Current Sprint

1. Skill stability
   - Restrict executable skills to local Python scripts under `skills/`.
   - Stop scripts that run longer than the configured timeout.
   - Show Python stderr or timeout messages in the speech bubble.
   - Trim long output so the bubble stays readable.

2. Real overtime skill integration
   - Put the real script under `skills/`, for example `skills/overtime.py`.
   - Add an entry in `skills/skills.json`.
   - Keep output short and speech-bubble friendly.

3. Pet stats
   - Persist mood, weight, hair, and money in `data/pet-state.json`.
   - Show stats in the desktop pet window.
   - Let work and meeting actions update stats.

## Near-Term Gameplay

1. Action settlement
   - Current implemented actions: work, meeting, meal, drink, exercise, badminton, cycling, guandan, alcohol, buffet.
   - Next: tune action costs and rewards after playtesting.
   - Each action should have duration, cost or reward, and stat effects.

2. Timed activities
   - Implemented: actions enter a running state and settle after a timer.
   - Next: persist in-progress activities across app restarts.

3. Menu structure
   - Implemented: root menu groups work, food, exercise, and skills.
   - Implemented: second-level submenu shows concrete actions or skills.
   - Next: improve labels/tooltips and add categories as actions grow.

4. Better state UI
   - Add a compact panel for current activity, remaining time, mood, weight, hair, and money.
   - Make the panel collapsible later if it gets too busy.

## Desktop App Polish

1. Implemented: remember window position.
2. Implemented: settings menu with quit control.
3. Implemented: always-on-top toggle.
4. Add right-click menu.
5. Add optional launch-at-login.
6. Package as a normal `.app`.

## Content And Assets

1. Preserve the approved main character image.
2. Add lightweight animations for:
   - work
   - meeting
   - eating
   - exercise
   - happy
   - tired
3. Add item icons for shop and action menus.

## Shop

1. Food and drink items affect mood and weight.
2. Decorations cost money.
3. Later, add outfit or accessory variants only if they stay faithful to the approved character direction.

## Development Rhythm

Before starting work on another computer:

```bash
git pull
```

After finishing a useful chunk:

```bash
git add .
git commit -m "Describe the change"
git push
```
