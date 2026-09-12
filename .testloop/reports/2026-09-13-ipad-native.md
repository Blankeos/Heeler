# testloop — 2026-09-13 — ipad-native (iPad first-class acceptance)

**Verdict:** accepted with three fixes; screen-dependent items not exercised · **Rounds:** 2 · **Branch:** `feat/ipad-native`

Acceptance of the six-package iPad round (target-lanes, input-chrome,
drop-composer, split-presentation, keyboard-commands, multiwindow) merged onto
`feat/ipad-native` from `main@f241466`. The GUI tester (Codex computer-use)
could not run because the Mac screen was locked, so the driver executed every
step at device level with `idb` and `simctl`; items that need the Simulator
window itself were not exercised and are listed below.

## Covered

- iPad Pro 13-inch (M5), portrait: empty state, form-sized Hosts / Settings /
  New Agent sheets, Composer menus, Attach Links popover, the whole hardware
  keyboard command table (⌘1–9, ⌘[ ⌘], ⌘F, ⌘N, ⌘,, ⌘⇧H, ⌘E, ⌘↩, ⌘W), key
  pass-through to the agent TUI (Ctrl-C, Esc, arrows, letters), ⌘+ / ⌘−,
  the hardware-keyboard shortcut strip, Open in New Window, input in the second
  window, same-Host terminal handover between windows, scene restoration after
  background + terminate.
- iPad mini (A17 Pro): onboarding with a fresh Device Key, sheets, sidebar
  overlay, Attach Links popover, strip, Composer with the software keyboard.
- iPhone 17 regression: onboarding, full-height Hosts sheet, Attach Links as a
  sheet, Composer with the software keyboard, Direct-input strip.
- Unit gates: targeted suites after each fix; full `make test` on the final SHA
  (see Verification).

## Found & fixed

- **No ⌘ command fired while the terminal had focus (Direct input).**
  libghostty's `UITerminalView.pressesBegan` never calls `super`, so UIKit never
  reached the scene's key commands: ⌘E could not return to the Composer, ⌘1–9,
  ⌘N, ⌘W were dead. `TerminalScreenView` now routes ⌘ chords other than the
  zoom pair to the next responder and keeps everything without ⌘ on the
  Ghostty path (`8100904`, `Sources/Heeler/Terminal/TerminalScreenView.swift`,
  test `commandChordsBypassGhosttyExceptZoom`).
- **Attach Links popover detached from its chip.** The `.popover` sat on the
  whole detail view, so on iPad it rendered top-centre with the list
  off-screen. It is now attached to the Composer chip and to the Direct-input
  floating button, sharing one origin state (`67767ee`,
  `Sources/Heeler/Console/AgentTerminalView.swift`, `AgentComposerView.swift`,
  test `attachLinksPopoverPresentsOnlyFromTheControlThatOpenedIt`).
- **Terminal drawn at 2/3 size after the first software-keyboard raise on the
  iPad Pro.** libghostty derives a wrong `contentsScale` from the old IOSurface
  after a resize and only corrects it on the next render tick; an idle Composer
  never ticks. `HeelerTerminalView` now re-runs layout 0.1 s and 0.5 s after a
  bounds change so the sublayer scale is reasserted (`247dafd` + test fixup
  `e8f1049`, `TerminalScreenView.swift`, tests
  `everyTerminalSizeChangeSchedulesOneScaleSettle`,
  `scaleSettleFollowUpsRunInOrderAfterTheChange`). Manual re-check: see
  Verification.

## Still open

- **Trust alert dropped after Save (pre-existing on main).** Saving the Add
  Host form presents `Trust this Host?` while the form sheet is still
  dismissing; UIKit logs `Attempt to present … which is already presenting` and
  the alert is lost, leaving `The host key is not trusted` until the Host is
  reopened. Reproduced on iPad Pro, iPad mini and iPhone 17;
  `Sources/Heeler/Hosts/` is untouched since the base, so it is not an iPad
  regression. Worth an issue.
- **⌘W falls through to iPadOS Close Window.** When the app's ⌘W is disabled
  (sheet open, nothing selected) the system closes the window; with a single
  window the app quits. Behaviour of every multi-scene app, but the app-level
  ⌘W (close Agent view) shares the chord. Decision needed on whether to keep
  ⌘W.
- **Simulator shows the hardware strip everywhere.** `GCKeyboard.coalesced` is
  never nil on the Simulator, so the software-keyboard strip variant (Esc, Tab,
  arrows) is only covered by unit tests; real devices without a keyboard keep
  it.
- **Cosmetic:** on the iPad mini in portrait the sidebar overlay's bottom edge
  is drawn over the Direct-input strip as two rounded light blocks.

## Not exercised (Mac screen locked, no Simulator window)

Rotation / landscape reflow, pointer hover, the hold-⌘ shortcut overview,
the I/O > Keyboard menu toggle (replaced by the `ConnectHardwareKeyboard`
preference + Simulator restart, which affects only the software keyboard),
Stage Manager / Split View window resize and `Take Over Here` (both windows
are never visible at once without them), cross-app drag of text or images
into the Composer.

## Verification

- Targeted suites (checker, iPhone 17): 81 tests / 6 suites on `67767ee`;
  214 tests / 7 suites on `e8f1049`, all green.
- iPad Pro manual re-check of fix 3: PASS on two fresh launches (full-size
  terminal at 0.7 s, 3 s and 10 s after the first keyboard raise, and after a
  second raise).
- Code review of the three fixes (codex, read-only): ACCEPT, no blocking
  findings; N1 notes that ⌘C / ⌘V / ⌘A in Direct input now travel the
  responder chain and have no runtime evidence yet (static trace: ⌘V still goes
  through the existing paste review, ⌘C through Ghostty's selection copy, ⌘A
  has no handler).
- Full `make test` on `e8f1049`: the first attempt died before any test
  launched (`Mach error -308, server died`) because the driver restarted
  Simulator.app during the run; the rerun result is recorded below.
- Full `make test` rerun on `e8f1049`: app suite 1797 tests / 169 suites, HeelerSSH package suites 49 tests (15 executed, 34 skipped as before), all green; tree clean, HEAD unchanged.
- `make build-sim` for iPad Pro 13-inch (M5) and iPad mini (A17 Pro):
  BUILD SUCCEEDED on `e8f1049`; Info.plist has UIDeviceFamily 1+2, all four
  iPad orientations, `UIApplicationSupportsMultipleScenes` true, activity type
  `dev.bybee.heeler.agent`, version 0.1.7 (19).
- `scripts/run-ci-ios-tests.sh` default simulator: `iPhone 17` (unchanged).

## Artifacts

- Results: `.testloop/test-results.md` (rounds 1 and 2), archived under
  `.testloop/iterations/ipad-native-round-1/` and `-round-2/`.
- Evidence: `.testloop/evidence/round-1/`, `.testloop/evidence/round-2/`.
- Fleet round directory (briefs, verdicts, checks, manifest):
  `$TMPDIR/herdr-fleet-ipad-native/`.
