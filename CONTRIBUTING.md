# Contributing to EMSuiteUI

Thank you for your interest. Bug reports, questions, documentation fixes and pull requests are welcome.

## Build and test

EMSuiteUI is a Swift package, still named `MacEMUI` in its `Package.swift` until the module rename (Swift 6.2 or newer; macOS only: SwiftUI, Metal and a little AppKit).

```bash
swift build
swift test -c release --parallel
```

Tests use XCTest and Swift Testing. The Metal tests need a GPU and are skipped on a machine without one. Do not run
`swift build --build-tests -c release`.

## Snapshot tests

`ShellSnapshotTesting` draws a SwiftUI view into a window at a fixed size, in light and dark, at 2x, and compares it with the
PNG committed under `__Snapshots__/<test file>/<name>.<light|dark>.png` beside the test (`Tests/ShellSnapshotTests`). The
apps use the same library for their rooms. Pictures differ between macOS versions and Macs, so the references are the ones
CI draws on GitHub's macos-26 runner, and a test compares only where `SNAPSHOTS=1` is set (that CI leg; it skips
elsewhere). A picture that is new or differs from its reference fails the test; CI puts it on the `pr-pictures` branch under
`<PR number>/snapshots/` and shows it in one comment on the pull request, which is the PR's picture. Review it there, then
commit it beside the test (from that branch: `git fetch origin pr-pictures` and `git checkout FETCH_HEAD -- <PR>/snapshots`,
moved into `__Snapshots__/`). A deliberate change replaces the reference in the same PR.

## Scope

EMSuiteUI is the window shell, controls and Metal image view that two apps share. A helper only one app uses belongs in
that app. There are no numerics here; ImagoCore gives `ScaleBarMath`, and the shared EDS room calls SpectroKit, FormatoKit and ImagoFilters for
every number it shows.

## Pull requests

- Keep each pull request focused, with tests that fail before the change and pass after it.
- Public API is semver (0.x may break). A break gets a `CHANGELOG.md` entry with a Migration paragraph.
- SwiftUI first; AppKit only where SwiftUI cannot do the job, with a comment saying why.

## Reporting issues

Please include what you did, what you saw and what you expected. For security problems, see
[`SECURITY.md`](SECURITY.md).

By contributing you agree that your contribution is licensed under the GPL-3.0-only (see [`LICENSE`](LICENSE)).
