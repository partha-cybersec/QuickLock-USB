# QuickLock-USB 🔒

**Turn any USB drive into a physical key for your Windows PC.**
Pull the USB out and Windows locks instantly. Plug it back in and protection re-arms.

![Platform](https://img.shields.io/badge/platform-Windows%2010%20%7C%2011-blue)
![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B-5391FE)
![Version](https://img.shields.io/badge/version-2.0.0-green)

---

## ✨ Features

| Feature | What it means for you |
|---|---|
| ⚡ **Instant lock** | Windows locks within about 1 second of removing the key. |
| 🔑 **Real key check** | The USB is identified by a hidden random secret file plus the drive's serial number, **not** by drive letter. Another USB stick on `E:` will not unlock anything. |
| 🧠 **Smart arming** | Never locks at start-up. Protection turns on only after the key is seen, and locks once per removal (no lock loop). |
| 🛡️ **Strict mode** *(optional)* | If someone signs in with your password but **without** the key, the PC locks again. |
| ⏱️ **Grace period** *(optional)* | Wait a few seconds before locking, so a quick re-plug doesn't lock you out. |
| 🖥️ **Screen off** *(optional)* | Lock and switch the monitor off at the same time. |
| 🟦 **Tray icon** | Shows the status. Right-click to pause, lock now, open the log or exit. |
| 🚀 **One-click setup** | `Setup.cmd` registers your key and enables auto-start at sign-in. |
| 📝 **Logging** | Every lock, unlock and error is written to a log file that rotates automatically. |
| 🪶 **No install needed** | Pure PowerShell. No admin rights, no extra software, no `wmic`. |

---

## 🚀 Quick start (2 minutes)

1. **Download** this repository: **Code → Download ZIP**, then extract it.
2. **Plug in** the USB drive you want to use as your key.
3. **Double-click `Setup.cmd`**, pick your USB drive from the list, and you're done.
4. **Test it:** pull out the USB, and Windows locks. Sign in, plug the USB back in, and you'll see the "Welcome back" notification.

> 💡 If Windows shows *"Windows protected your PC"*, click **More info → Run anyway**. This happens because the file was downloaded from the internet.

---

## 🧭 How it works

```
 ┌──────────────────┐  key seen   ┌───────────┐  key removed  ┌──────────┐
 │  Waiting for key │ ──────────► │   Armed   │ ────────────► │  Locked  │
 └──────────────────┘             └───────────┘   (lock PC)   └──────────┘
          ▲                             ▲                          │
          │ paused & key removed        └──────── key back ────────┘
          └─────────────────────────────            (strict mode: re-lock
                                                     if signed in without key)
```

1. **Register:** `-Register` writes 64 random bytes to `X:\.quicklock\key.bin` (a hidden folder on the USB). The PC stores only the SHA-256 hash of that file and the drive's volume serial number.
2. **Monitor:** every second (configurable), QuickLock checks that a drive holds a key file with the matching hash and serial.
3. **Lock:** when the key disappears, it calls the Windows `LockWorkStation` API directly.

---

## 🛠️ Commands

Run these from the `src` folder in PowerShell:

```powershell
.\QuickLock.ps1 -Register            # choose a USB drive as your key
.\QuickLock.ps1 -Register -Drive E:  # use a specific drive (e.g. a USB SSD)
.\QuickLock.ps1 -Install             # auto-start at every sign-in, and start now
.\QuickLock.ps1 -Status              # show key, running, and auto-start status
.\QuickLock.ps1                      # run now with the tray icon
.\QuickLock.ps1 -NoTray              # run without the tray icon
.\QuickLock.ps1 -Uninstall           # remove auto-start and stop
```

If PowerShell blocks the script, run this once in the same window:
`Set-ExecutionPolicy -Scope Process Bypass`

---

## ⚙️ Settings

Settings live in `%LOCALAPPDATA%\QuickLock\config.json`. Changes apply automatically within about a second; no restart is needed.

| Setting | Default | Description |
|---|---|---|
| `CheckIntervalMs` | `1000` | How often to check for the key, in milliseconds (minimum 250). |
| `GraceSeconds` | `0` | Seconds to wait after removal before locking. |
| `Action` | `"Lock"` | `"Lock"` or `"LockAndScreenOff"`. |
| `StrictMode` | `false` | Lock again if someone signs in without the key. |
| `StrictRelockSeconds` | `15` | How often strict mode re-locks (minimum 5). |
| `ShowTray` | `true` | Show the system-tray icon. |
| `Notifications` | `true` | Show tray pop-up notifications. |
| `LogMaxKB` | `512` | Log size before it rotates to `quicklock.log.old`. |
| `KeyHash`, `VolumeSerial` | — | Set by `-Register`. Don't edit these by hand. |

Example: to turn on strict mode plus screen off, change just these lines and keep all the others, especially `KeyHash`:

```json
  "Action": "LockAndScreenOff",
  "StrictMode": true,
  "StrictRelockSeconds": 10,
```

---

## 🖱️ Tray menu

Right-click the 🛡️ shield icon in the system tray:

- **Status:** waiting for key / protecting / key removed / paused
- **Pause protection:** remove the USB without locking (e.g. to use it on another PC)
- **Lock now:** lock immediately
- **Open log:** view the activity log
- **Exit:** stop QuickLock until the next sign-in

---

## 🔐 Security notes (please read)

QuickLock-USB is a **convenience and "walk-away" protection** tool. It adds to your Windows password; it does not replace it.

- ✅ Locks your session the moment you walk away with the key.
- ✅ A different USB stick, or the same drive letter, will **not** be accepted.
- ⚠️ Anyone who copies the hidden key file **and** clones the volume serial could imitate the key. Keep the USB with you.
- ⚠️ It cannot stop someone from booting another operating system. Use **BitLocker** to protect data at rest.
- ⚠️ A user who is already signed in can stop the program. Strict mode helps against someone who only knows your password.

See [SECURITY.md](SECURITY.md) for the threat model and how to report vulnerabilities.

---

## 🗑️ Uninstall

Double-click **`Uninstall.cmd`**, or run `.\QuickLock.ps1 -Uninstall`.
To remove settings and logs as well, delete `%LOCALAPPDATA%\QuickLock`.
To stop the USB from being a key, delete the hidden `.quicklock` folder on it.

---

## 📁 Project structure

```
QuickLock-USB/
├── Setup.cmd               # one-click: register key + enable auto-start
├── Uninstall.cmd           # one-click removal
├── src/
│   ├── QuickLock.ps1       # the program (monitor, tray, register, install, status)
│   └── QuickLock.vbs       # optional hidden launcher (double-click to start)
├── docs/
│   └── Troubleshooting.md
├── CHANGELOG.md
├── SECURITY.md
└── README.md
```

---

## ❓ Problems?

See **[docs/Troubleshooting.md](docs/Troubleshooting.md)**, or check the log at `%LOCALAPPDATA%\QuickLock\quicklock.log`.

## 👤 Author

**Alluri Partha Saradhi Reddy**, Cybersecurity student
GitHub: [@aparthasaradhireddy897-hash](https://github.com/aparthasaradhireddy897-hash)

Contributions and issues are welcome!
