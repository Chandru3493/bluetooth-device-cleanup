# Reset-Bluetooth.ps1 - unpair Bluetooth devices (classic + LE) and recover a hung bthserv.
# Usage:  powershell -ExecutionPolicy Bypass -File .\Reset-Bluetooth.ps1 [-Name "Device Name"] [-Force]
#   (no switches)  list paired devices, then prompt: type a number, a name (or part of it), or 'all'
#   -Name "X"      unpair only the device matching X (name or part of name), no prompt
#   -Force         unpair everything, no prompt
param([string]$Name, [switch]$Force, [switch]$FixServiceOnly)

function Test-Admin {
  ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)
}

# Normalize a device name for matching: unify unicode dashes, drop invisible/control
# characters, turn odd spaces into normal ones, trim, lowercase.
function Normalize([string]$s) {
  $s = $s -replace '[\u2010-\u2015\u2212]', '-'
  $s = $s -replace '\p{C}', ''
  $s = $s -replace '\p{Z}+', ' '
  $s.Trim().ToLowerInvariant()
}

# --- 1. Make sure the Bluetooth service is healthy ---------------------------
$svc = Get-CimInstance Win32_Service -Filter "Name='bthserv'"
if ($svc.State -ne 'Running') {
  if (-not (Test-Admin)) {
    Write-Host "bthserv is '$($svc.State)'. Elevating to recover it (UAC prompt)..."
    Start-Process powershell -Verb RunAs -Wait -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" -FixServiceOnly"
  } else {
    $shared = @(Get-CimInstance Win32_Service -Filter "ProcessId=$($svc.ProcessId)")
    if ($svc.ProcessId -gt 0 -and $shared.Count -gt 1) {
      throw "bthserv shares PID $($svc.ProcessId) with other services ($($shared.Name -join ', ')). Restart the PC instead."
    }
    if ($svc.ProcessId -gt 0) { Stop-Process -Id $svc.ProcessId -Force }
    Start-Sleep 3
    Start-Service bthserv
  }
  if ($FixServiceOnly) { return }
  Start-Sleep 5
  $svc = Get-CimInstance Win32_Service -Filter "Name='bthserv'"
  if ($svc.State -ne 'Running') { throw "bthserv is still '$($svc.State)'. Restart the PC, then run again." }
}
if ($FixServiceOnly) { return }
Write-Host "bthserv: Running"

# --- 2. Find paired devices via WinRT (handles classic + Bluetooth LE) -------
Add-Type -AssemblyName System.Runtime.WindowsRuntime
$asTask = [System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object {
  $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and
  $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1' } | Select-Object -First 1
function Await($op, [type]$t) {
  $task = $asTask.MakeGenericMethod($t).Invoke($null, @($op)); $task.Wait(-1) | Out-Null; $task.Result
}
$null = [Windows.Devices.Enumeration.DeviceInformation, Windows.Devices.Enumeration, ContentType = WindowsRuntime]
$null = [Windows.Devices.Bluetooth.BluetoothLEDevice, Windows.Devices.Bluetooth, ContentType = WindowsRuntime]
$null = [Windows.Devices.Bluetooth.BluetoothDevice, Windows.Devices.Bluetooth, ContentType = WindowsRuntime]

$selectors = @(
  [Windows.Devices.Bluetooth.BluetoothLEDevice]::GetDeviceSelectorFromPairingState($true),
  [Windows.Devices.Bluetooth.BluetoothDevice]::GetDeviceSelectorFromPairingState($true)
)
$paired = foreach ($aqs in $selectors) {
  Await ([Windows.Devices.Enumeration.DeviceInformation]::FindAllAsync($aqs)) ([Windows.Devices.Enumeration.DeviceInformationCollection])
}
$before = (Get-PnpDevice -Class Bluetooth).Count
Write-Host "Bluetooth device entries: $before   Paired devices: $(@($paired).Count)"

if (-not @($paired).Count) { Write-Host "Nothing to unpair."; return }

# Wrap each device with a display label (blank names shown as '(unnamed)') and a normalized key
$items = @($paired | ForEach-Object {
  $label = if ($_.Name) { $_.Name } else { '(unnamed)' }
  [pscustomobject]@{ Label = $label; Key = Normalize $label; Device = $_ }
})

# Group entries of the same device name and show a numbered menu
$groups = @($items | Group-Object Key | Sort-Object Count -Descending)
$menu = for ($i = 0; $i -lt $groups.Count; $i++) {
  [pscustomobject]@{ '#' = $i + 1; Count = $groups[$i].Count; Name = $groups[$i].Group[0].Label }
}
$menu | Format-Table -AutoSize

# Resolve user text to matching group(s): number, exact name, then partial name
function Find-Groups([string]$text) {
  $n = 0
  if ([int]::TryParse($text.Trim(), [ref]$n) -and $n -ge 1 -and $n -le $groups.Count) { return $groups[$n - 1] }
  $key = Normalize $text
  $exact = @($groups | Where-Object { $_.Name -eq $key })
  if ($exact.Count) { return $exact }
  return @($groups | Where-Object { $_.Name -like "*$([WildcardPattern]::Escape($key))*" })
}

# --- 3. Choose what to unpair --------------------------------------------------
$targets = @()
if ($Force) {
  $targets = $items
}
elseif ($Name) {
  $pick = @(Find-Groups $Name)
  if ($pick.Count -ne 1) { Write-Warning "'$Name' matched $($pick.Count) devices. Be more specific."; return }
  $targets = @($pick[0].Group)
}
else {
  while ($true) {
    $choice = (Read-Host "Enter a number or device name from the list, or 'all' to remove everything (blank = cancel)").Trim()
    if (-not $choice) { Write-Host "Cancelled."; return }
    if ($choice -in 'all', 'remove all') { $targets = $items; break }

    $pick = @(Find-Groups $choice)
    if ($pick.Count -eq 1) { $targets = @($pick[0].Group); break }
    if ($pick.Count -gt 1) { Write-Warning "'$choice' matches $($pick.Count) devices. Type the number from the list instead."; continue }
    Write-Warning "No device matches '$choice'. Type a number from the list, or part of the name."
  }
}

if ($targets.Count -eq $items.Count) { Write-Host "Unpairing ALL $($targets.Count) entries..." }
else { Write-Host "Unpairing '$($targets[0].Label)' ($($targets.Count) entries)..." }

# --- 4. Unpair -----------------------------------------------------------------
$ok = 0
foreach ($t in $targets) {
  $r = Await ($t.Device.Pairing.UnpairAsync()) ([Windows.Devices.Enumeration.DeviceUnpairingResult])
  if ($r.Status -in 'Unpaired', 'AlreadyUnpaired') { $ok++ } else { Write-Warning "$($t.Label) -> $($r.Status)" }
}
Start-Sleep 5
Write-Host "Unpaired $ok of $($targets.Count). Device entries: $before -> $((Get-PnpDevice -Class Bluetooth).Count)"