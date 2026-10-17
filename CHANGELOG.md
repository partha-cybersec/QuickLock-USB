# Changelog

## [2.0.0] - 2026-10-17

A complete rewrite in PowerShell.

### Added
- **Secure key detection:** a random secret file plus the volume serial number, instead of only checking whether `E:` exists.
- **Tray icon** with status, Pause/Resume, Lock now, Open log and Exit.
- **Strict mode:** locks again if someone signs in without the key.
- **Grace period** and a **Lock + screen off** action.
- **One-click `Setup.cmd` / `Uninstall.cmd`**, plus `-Register`, `-Install`, `-Uninstall` and `-Status` commands.
- Auto-start at sign-in through Task Scheduler. On Windows 11 it starts hidden through `conhost --headless`, with no VBScript needed.
- Settings in `config.json` that reload automatically without a restart.
- A log file that rotates automatically.
- A single-instance guard, so the program never runs twice.

### Changed
- Locks **once** per removal. The old script re-locked every 5 seconds in a loop, and also locked at start-up if the USB wasn't plugged in.
- Calls the `LockWorkStation` API directly, instead of starting PowerShell → rundll32 every time.
- Checks every 1 second instead of every 5 (configurable).

### Removed
- `wmic`, which Microsoft deprecated and removed from recent Windows 11 builds and which broke the v1 script.
- The hard-coded `E:` drive letter.
- The old "run at computer start-up" instructions. Locking needs your signed-in session, so the task now runs at sign-in.

## [1.0.0] - 2025-07

- First version: a batch file that polled `wmic` for drive `E:`, plus a VBS launcher.
