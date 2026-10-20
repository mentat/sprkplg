# Contributing to SparkPlug

Thanks for helping. SparkPlug is deliberately small. It is a task list beside the Mac's own calendars,
with no accounts, no servers and no network, and changes should keep it that way.

## Getting set up

```sh
brew install xcodegen
make test      # the core package's tests, then the app's
make demo      # the app on sample data, without touching your calendars or tasks
```

`project.yml` is the project file. Run `make project` (or any `make` target) after changing it, and
don't commit `SparkPlug.xcodeproj`.

## Where things go

- **Rules belong in `Core/`** (`SparkPlugCore`): grouping, layout, what Focus targets, when a block
  is over. These are pure functions over plain values, and each change comes with a test in
  `Core/Tests`.
- **State changes belong in `App/AppModel.swift`.** Views call its methods and never edit the
  library themselves. Behaviour that spans the model, the clock and the calendar gets a test in
  `AppTests/` against `FakeCalendarService`.
- **EventKit stays in `App/Calendar/EventKitCalendarService.swift`.** SparkPlug writes only its own
  copies of blocks (marked with a `sparkplug://task/<id>` URL) and only to the calendar chosen in
  Settings. Please keep it that way.

## Style

- Swift 6 language mode with strict concurrency. The build treats warnings as errors.
- Match the surrounding code: doc comments on types and anything not obvious, no comments that
  restate the code.
- UI copy is short and plain, in sentence case, and says what happens rather than how.

## Pull requests

- Keep each one focused, and say what changed for someone using the app.
- `make test` passes.
- For UI changes, include a before and after screenshot (`make demo` gives a stable sample day).
