param(
    [ValidateRange(1, 365)]
    [int] $Days = 60,

    [string] $TaskName = "WhenBuffInGameDataRefresh",

    [string] $DailyAt = "07:00",

    [switch] $NoLogonTrigger
)

$ErrorActionPreference = "Stop"

$addonRoot = Split-Path -Parent $PSScriptRoot
$updateScript = Join-Path $PSScriptRoot "update-data.ps1"
$dataPath = Join-Path $addonRoot "Data.lua"

if (-not (Test-Path -LiteralPath $updateScript)) {
    throw "Could not find updater script: $updateScript"
}

if ($DailyAt -notmatch "^\d{2}:\d{2}$") {
    throw "-DailyAt must use 24-hour HH:mm format, for example 07:00"
}

$runAt = [datetime]::ParseExact($DailyAt, "HH:mm", [System.Globalization.CultureInfo]::InvariantCulture)
$powerShellPath = Join-Path $PSHOME "powershell.exe"
if (-not (Test-Path -LiteralPath $powerShellPath)) {
    $powerShellPath = "powershell.exe"
}

$taskArguments = @(
    "-NoProfile",
    "-ExecutionPolicy", "Bypass",
    "-File", "`"$updateScript`"",
    "-Days", $Days,
    "-OutputPath", "`"$dataPath`""
) -join " "

$action = New-ScheduledTaskAction -Execute $powerShellPath -Argument $taskArguments
$triggers = @(
    New-ScheduledTaskTrigger -Daily -At $runAt
)

if (-not $NoLogonTrigger) {
    $triggers += New-ScheduledTaskTrigger -AtLogOn
}

$settings = New-ScheduledTaskSettingsSet `
    -StartWhenAvailable `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -MultipleInstances IgnoreNew

$description = "Refreshes WhenBuff In-Game Data.lua from https://api.whenbuff.com with a $Days day lookahead."

Register-ScheduledTask `
    -TaskName $TaskName `
    -Action $action `
    -Trigger $triggers `
    -Settings $settings `
    -Description $description `
    -Force | Out-Null

Write-Host "Registered scheduled task: $TaskName"
Write-Host "Daily refresh: $DailyAt"
if (-not $NoLogonTrigger) {
    Write-Host "Logon refresh: enabled"
}

Write-Host "Running updater once now..."
& $updateScript -Days $Days -OutputPath $dataPath

Write-Host ""
Write-Host "Done. If WoW is open, run /reload after the task updates Data.lua."