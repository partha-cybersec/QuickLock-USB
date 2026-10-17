# Security Policy

## Supported versions

| Version | Supported |
|---------|-----------|
| 2.x     | ✅ Yes |
| 1.x (batch + wmic script) | ❌ No. Please upgrade. |

## Threat model

**QuickLock-USB is designed to protect against:**
- Someone using your unlocked PC after you walk away. Removing the key locks the session.
- Someone who knows your password but doesn't have your key (with **Strict mode** on).
- A different USB drive being used as the key. Detection uses a 512-bit random secret (only its SHA-256 hash is stored) plus the volume serial number, not the drive letter.

**It does NOT protect against:**
- An attacker who copies the hidden key file **and** spoofs the volume serial number.
- Booting another operating system or removing the disk. Use **BitLocker** for data at rest.
- A user who is already signed in stopping the program (it runs as your user, by design, with no admin rights).
- Malware already running on the PC.

## Data stored

| Where | What |
|---|---|
| USB: `\.quicklock\key.bin` | 64 random bytes (the secret). Hidden and read-only. |
| PC: `%LOCALAPPDATA%\QuickLock\config.json` | SHA-256 hash of the secret, the volume serial, and your settings. |
| PC: `%LOCALAPPDATA%\QuickLock\quicklock.log` | Lock and unlock events with timestamps. No secrets. |

Nothing is sent over the network.

## Reporting a vulnerability

Please **do not** open a public issue. Use GitHub's private reporting instead:
**Security tab → Report a vulnerability** on this repository.

Include the steps to reproduce, your Windows version, and the impact. You can expect a reply within 7 days.
