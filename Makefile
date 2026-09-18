APP := build/Study Hamster.app

.PHONY: app run dev check snapshots clean

## Build the double-clickable app into build/
app:
	bash scripts/build-app.sh

## Build the app, quit any running copy, and launch the fresh one
run: app
	-@pkill -x StudyHamster
	open "$(APP)"

## Run straight from source (no .app bundle; handy while developing)
dev:
	swift run StudyHamster

## Self-checks for the pomodoro/timer/window logic
check:
	swift run HamsterChecks

## Render the hamster's poses and bubbles to PNGs in snapshots/
snapshots:
	swift run HamsterSnapshots snapshots

clean:
	rm -rf .build build snapshots
