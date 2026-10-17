# Troubleshooting 🔧

First, run the status check. It answers most questions:

```powershell
cd path\to\QuickLock-USB\src
powershell -ExecutionPolicy Bypass -File .\QuickLock.ps1 -Status
```

Then look at the log: `%LOCALAPPDATA%\QuickLock\quicklock.log` (or tray icon → **Open log**).

---

### "Running scripts is disabled on this system"
Use `Setup.cmd`, or start PowerShell with `-ExecutionPolicy Bypass` as shown above.
To allow it permanently for your user only: `Set-ExecutionPolicy -Scope CurrentUser RemoteSigned`.

### "Windows protected your PC" / the file is blocked
The file came from the internet. Click **More info → Run anyway**, or unblock all files once:
```powershell
Get-ChildItem -Recurse path\to\QuickLock-USB | Unblock-File
```

### "No removable USB drive found" during setup
- Make sure the USB is plugged in and opens in File Explorer.
- Some USB SSDs and hard drives show up as a normal (Fixed) disk. Register them by letter:
  `.\QuickLock.ps1 -Register -Drive E:`

### The PC doesn't lock when I remove the USB
1. `-Status` should show **USB key: plugged in** and **Running now: yes**.
2. If the key shows **registered, not plugged in** while it *is* plugged in:
   - The hidden `.quicklock` folder was deleted, or the drive was formatted. Run `-Register` again.
3. If **Running now: no**, run `-Install` again, or double-click `src\QuickLock.vbs`.
4. Check the tray menu. If the status says **paused**, choose **Resume protection**.
5. QuickLock only starts protecting after it has seen the key. If you started the PC without the key, plug it in once.

### The PC locks immediately after I sign in
This is **Strict mode** doing its job: the key isn't plugged in. Plug in the key, or set `"StrictMode": false` in `%LOCALAPPDATA%\QuickLock\config.json`.

### It locks when I briefly re-plug the USB
Set a grace period in `config.json`, for example `"GraceSeconds": 3`.

### Auto-start doesn't work / "Access is denied" during -Install
- Open **Task Scheduler** (`taskschd.msc`) and look for the **QuickLock-USB** task.
- Some company-managed PCs block creating scheduled tasks. Run PowerShell **as administrator** and repeat `-Install`, or ask your IT team.
- Alternative: press `Win + R`, type `shell:startup`, and put a shortcut to `src\QuickLock.vbs` in that folder.

### A black console window flashes at sign-in
On Windows 10 the task starts through `QuickLock.vbs` to stay hidden. Make sure `QuickLock.vbs` is in the same folder as `QuickLock.ps1` when you run `-Install`.

### I lost my USB key
Sign in with your Windows password as normal (QuickLock never blocks your password).
If **Strict mode** keeps locking you, sign in and immediately right-click the tray icon → **Exit**, then edit `config.json` to set `"StrictMode": false`.
Then register a new USB with `-Register`. The old key stops working automatically.

### I want to use the USB on another PC without locking this one
Tray icon → **Pause protection**, then remove the USB. Choose **Resume protection** when you're back.
