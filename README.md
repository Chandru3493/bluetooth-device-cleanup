# Bluetooth Device Cleanup

A PowerShell script to **unpair duplicate or problematic Bluetooth devices** (both Classic and Bluetooth LE) and **recover a hung Bluetooth service** (`bthserv`) on Windows.

> **Script file:** `Reset-Bluetooth.ps1`

---

## 🎯 What It Does

- **Detects & lists** all currently paired Bluetooth devices (Classic + LE) using Windows WinRT APIs
- **Groups duplicates** by name so you can see which devices appear multiple times
- **Unpairs selected devices** — by number, name, partial name, or `all`
- **Auto-recovers** the Bluetooth Support Service (`bthserv`) if it's stopped or stuck
- **Requires admin only when the service needs restarting** (UAC prompt appears automatically)

---

## 📋 Requirements

- **Windows 10 / 11** (WinRT Bluetooth APIs)
- **PowerShell 5.1+** (built into Windows)
- **Administrator rights** only if the Bluetooth service needs a restart

---

## 🚀 Quick Start

```powershell
# Interactive mode (lists devices, prompts for selection)
powershell -ExecutionPolicy Bypass -File .\Reset-Bluetooth.ps1

# Unpair a specific device by name (no prompt)
powershell -ExecutionPolicy Bypass -File .\Reset-Bluetooth.ps1 -Name "WH-1000XM4"

# Unpair everything without prompting (use with caution!)
powershell -ExecutionPolicy Bypass -File .\Reset-Bluetooth.ps1 -Force
```

---

## 📖 Usage

| Switch | Description |
|--------|-------------|
| *(none)* | Interactive menu — lists devices, prompts for number/name/`all` |
| `-Name "Device Name"` | Unpair only the device matching the given name (exact or partial), no prompt |
| `-Force` | Unpair **all** paired devices immediately, no prompt |
| `-FixServiceOnly` | Only restart the Bluetooth service (`bthserv`) if it's not running; skip device enumeration/unpairing |

---

## 🖥️ Example Session

```text
PS> powershell -ExecutionPolicy Bypass -File .\Reset-Bluetooth.ps1
bthserv: Running
Bluetooth device entries: 12   Paired devices: 8

#  Count Name
-  ----- ----
1  3     WH-1000XM4
2  2     Mouse (unnamed)
3  1     Keyboard K380
4  1     Galaxy Buds Pro
5  1     (unnamed)

Enter a number or device name from the list, or 'all' to remove everything (blank = cancel): 1
Unpairing 'WH-1000XM4' (3 entries)...
Unpaired 3 of 3. Device entries: 12 -> 9
```

---

## ⚙️ How It Works

1. **Service Health Check** — Verifies `bthserv` (Bluetooth Support Service) is running. If not, it elevates via UAC, kills the stuck process, and restarts the service.
2. **Device Enumeration** — Uses `Windows.Devices.Bluetooth` WinRT APIs to find **both Classic and LE** paired devices.
3. **Smart Grouping** — Normalizes names (handles Unicode dashes, invisible chars, odd spaces) and groups identical names together.
4. **Flexible Selection** — Accepts menu number, exact name, partial name, or `all`.
5. **Unpair** — Calls `DeviceInformation.Pairing.UnpairAsync()` for each selected device.
6. **Summary** — Reports how many were unpaired and the before/after device count.

---

## 🛡️ Safety Notes

- **`-Force` unpairs everything** — use only when you intend to re-pair all devices.
- The script **never deletes drivers** or touches the registry directly; it uses the official Windows unpairing API.
- If `bthserv` shares its PID with other services, the script **aborts and tells you to reboot** instead of forcing a risky restart.

---

## 📦 Installation

No installation needed. Just download `Reset-Bluetooth.ps1` and run it.

Optional: Add the folder to your `PATH` or create a shortcut for quick access.

---

## 🤝 Contributing

1. Fork the repo
2. Create a feature branch (`git checkout -b feature/awesome-thing`)
3. Commit your changes (`git commit -am 'Add awesome thing'`)
4. Push to the branch (`git push origin feature/awesome-thing`)
5. Open a Pull Request

---

## 📄 License

[MIT License](LICENSE) — free for personal and commercial use.

---

## ⭐ If This Helped You

Give the repo a star! It helps others discover the script.