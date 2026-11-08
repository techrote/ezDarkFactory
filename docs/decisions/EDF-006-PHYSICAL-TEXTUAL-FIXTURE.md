# EDF-006 — selected Textual Windows Terminal operator fixture

**SOURCE/FAST-CI only; PHYSICAL-TUI PENDING.** This opt-in, inert interactive app exercises pinned Textual 8.2.8 events and first-party EDF-006 layout, divider transaction and overlays. It does not inspect factories, launch QEMU or create production host-manager authority.

## Launch in actual Windows Terminal

Use a clean exact PR #28 checkout, standard-user Windows 10/11 x64, with terminal 80x24 and 160x48 separately. In PowerShell, record source SHA/tree, Windows build, Windows Terminal version, privilege, CPython and Textual versions, lock digest and display settings. Obtain the hash-verified embeddable runtime outside the source repository:

~~~powershell
$sourceSha = git rev-parse HEAD
$sourceTree = git rev-parse 'HEAD^{tree}'
Get-ComputerInfo | Select-Object WindowsProductName, WindowsVersion, OsBuildNumber
wt --version
New-Item -ItemType Directory -Force C:\Temp\edf006-runtime | Out-Null
$python = & .\scripts\Install-Edf006TuiRuntime.ps1 -DestinationRoot C:\Temp\edf006-runtime | Select-Object -Last 1
& $python -I -c 'import sys,textual; print(sys.version.split()[0]); print(textual.__version__)'
& $python -I .\tools\edf006_physical_tui.py --interactive --receipt C:\Temp\edf006-native-1.json
~~~

Select a new absolute receipt filename outside the source repository per run. Receipt is create-only, bounded, and contains no raw keys, clipboard, factory paths, screenshots or secrets. It explicitly states UNVERIFIED_INTERACTIVE_DIAGNOSTIC and physical_tui=false, with input-to-visible-frame p95 null. Save receipt privately, not in Git. Record exact source SHA/tree and the operator/machine identity in separate redacted evidence.

## Physical operator campaign

1. At actual 80x24, verify compact rendering; open menu with m, dismiss with Escape; arm inert paste using i and paste text containing q and Ctrl+P; verify it is not dispatched as commands. Recover using Ctrl+T.
2. At actual 160x48, drag divider by mouse press/move/release: ratio changes only on release. Repeat cancelling by Escape, focus loss and active resize. If focus delivery is missing, record FAIL/UNMEASURED rather than inventing PASS.
3. Inspect actual mouse move/down/up, wheel in each direction and right click; open menu then click outside; confirm dismissal consumed without underlying tile focus change.
4. Exercise Unicode and --ascii plus truecolour, 256-colour, 16-colour, mono, high-contrast and reduced-motion settings where supported; do not claim full production theme coverage.
5. Independently check cursor, mouse selection, shell keyboard and terminal-mode restoration after ordinary q exit, and after deliberate Ctrl+X exception in a separate run.
6. Measure independent input-to-visible-frame latency under representative background collector activity (target p95 under 100 ms). Distinguish physical presentation from in-process event handling or stdout flush. Record sample method and separate composition percentiles. This fixture cannot make that timing claim.
7. Prove external shell launch/return and VM/manager lifetime separately against the accepted typed seam. This inert diagnostic does not operate a VM.

The tracked unit tests check first-party model invariants and redaction. The exact pinned runtime qualification also runs --headless-smoke against this actual Textual class, but that is FAST-CI-HEADLESS, not physical acceptance.

Keep PR #28 **Draft/HOLD**, issue #6 open and EDF-007 dependency-blocked until independently witnessed PHYSICAL-TUI evidence and exact-head automated checks qualify the entire required issue matrix.

## Cross-event transaction safety (source + pinned-runtime regression)

The selected Textual fixture now treats modal opening as a capture-cancellation
boundary, rejects a second down during a live divider transaction, and dismisses
old-coordinate overlays on terminal resize. The headless integration exercises
the **actual Textual mouse/key/resize event bridge**, including an interleaving
in which a menu opens during a drag and the old mouse-up arrives afterwards.
Source regression tests additionally cover duplicate down and stale overlay
hit geometry.

During the physical campaign, repeat that sequence with a real pointer:
hold the divider, move it, open the menu with the keyboard, then release the
mouse. The stored ratio must remain unchanged. Repeat with a resize while the
menu is open; no unreachable modal must retain input focus. Record failures
as observed physical failures, not as headless successes. None of these
regressions changes the `UNVERIFIED_INTERACTIVE_DIAGNOSTIC` receipt class or
supplies external input-to-presented-frame timing.

## Top-modal input and context-menu safety (source and headless only)

While a menu is visible, typing `m`, `i` or `q` must not open another
menu, toggle the background paste field or quit the fixture. Paste into a
previously armed field is refused while a modal is visible; pasted contents
are neither retained nor displayed. Escape dismisses exactly one menu.

At 160x48, right-click near the inspector tile's lower-right corner.
The context menu must appear for the pointed tile, entirely inside the
viewport. Right-click inside the menu must not open another one; right-click
outside must dismiss without focusing the underlying tile. A *subsequent*
right-click may legitimately open the newly targeted tile's context menu.

The reducer and selected Textual Pilot tests exercise these transitions,
but they remain SOURCE / FAST-CI-HEADLESS. In actual Windows Terminal,
independently check right-click delivery and native selection behavior.
No PHYSICAL-TUI acceptance or input-to-visible-frame measurement is implied.
