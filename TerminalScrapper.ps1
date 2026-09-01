#Requires -Version 5.1

Add-Type -AssemblyName System.Windows.Forms

Add-Type @"
using System;
using System.Runtime.InteropServices;

public class Win32 {
    [DllImport("user32.dll")]
    public static extern bool SetForegroundWindow(IntPtr hWnd);

    [DllImport("user32.dll")]
    public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);

    [DllImport("user32.dll")]
    public static extern bool IsIconic(IntPtr hWnd);

    [DllImport("user32.dll")]
    public static extern void keybd_event(
        byte bVk, byte bScan, uint dwFlags, UIntPtr dwExtraInfo);

    public const int  SW_RESTORE       = 9;
    public const byte VK_CONTROL       = 0x11;
    public const byte VK_A             = 0x41;
    public const byte VK_C             = 0x43;
    public const byte VK_F8            = 0x77;
    public const uint KEYEVENTF_KEYUP  = 0x0002;
}
"@

$script:SpeedMultiplier = 1.0

function Wait-Ms {
    param([int]$BaseMs)
    $actual = [Math]::Max(10, [int]($BaseMs * $script:SpeedMultiplier))
    Start-Sleep -Milliseconds $actual
}

function Focus-Window {
    param([IntPtr]$Handle)
    if ([Win32]::IsIconic($Handle)) {
        [Win32]::ShowWindow($Handle, [Win32]::SW_RESTORE) | Out-Null
    }
    [Win32]::SetForegroundWindow($Handle) | Out-Null
    Wait-Ms 150
}

function Send-KeyDown {
    param([byte]$vk)
    [Win32]::keybd_event($vk, 0, 0, [UIntPtr]::Zero)
}

function Send-KeyUp {
    param([byte]$vk)
    [Win32]::keybd_event($vk, 0, [Win32]::KEYEVENTF_KEYUP, [UIntPtr]::Zero)
}

function Send-CtrlC {
    Send-KeyDown -vk ([Win32]::VK_CONTROL)
    Wait-Ms 30
    Send-KeyDown -vk ([Win32]::VK_C)
    Wait-Ms 30
    Send-KeyUp   -vk ([Win32]::VK_C)
    Send-KeyUp   -vk ([Win32]::VK_CONTROL)
    Wait-Ms 150
}

function Send-CtrlA {
    Send-KeyDown -vk ([Win32]::VK_CONTROL)
    Wait-Ms 30
    Send-KeyDown -vk ([Win32]::VK_A)
    Wait-Ms 30
    Send-KeyUp   -vk ([Win32]::VK_A)
    Send-KeyUp   -vk ([Win32]::VK_CONTROL)
    Wait-Ms 100
}

function Send-F8 {
    Send-KeyDown -vk ([Win32]::VK_F8)
    Wait-Ms 30
    Send-KeyUp   -vk ([Win32]::VK_F8)
    Wait-Ms 100
}

function Get-ClipboardText {
    try {
        return [System.Windows.Forms.Clipboard]::GetText()
    }
    catch {
        return ""
    }
}

function Clear-ClipboardContent {
    try { [System.Windows.Forms.Clipboard]::Clear() }
    catch { }
}

function Trim-Lines {
    param(
        [string]$Text,
        [int]$Top    = 3,
        [int]$Bottom = 3
    )
    $lines = $Text -split "`r?`n"
    if ($lines.Count -le ($Top + $Bottom)) { return "" }
    $trimmed = $lines[$Top..($lines.Count - $Bottom - 1)]
    return ($trimmed -join "`n")
}

function Select-TargetWindow {
    $procs = Get-Process |
        Where-Object { $_.MainWindowHandle -ne [IntPtr]::Zero -and $_.MainWindowTitle } |
        Sort-Object MainWindowTitle

    if ($procs.Count -eq 0) {
        Write-Host "`n  [ERROR] No visible windows found." -ForegroundColor Red
        exit 1
    }

    Write-Host "`n$('=' * 60)"
    Write-Host "  AVAILABLE WINDOWS"
    Write-Host "$('=' * 60)"

    for ($i = 0; $i -lt $procs.Count; $i++) {
        $title = $procs[$i].MainWindowTitle
        if ($title.Length -gt 52) {
            $title = $title.Substring(0, 49) + "..."
        }
        $num = ($i + 1).ToString().PadLeft(3)
        Write-Host "  $num | $title"
    }

    Write-Host "$('=' * 60)"

    while ($true) {
        $userChoice = Read-Host "`n  Select window number"
        $choiceNum = 0
        if ([int]::TryParse($userChoice, [ref]$choiceNum)) {
            if ($choiceNum -ge 1 -and $choiceNum -le $procs.Count) {
                return $procs[$choiceNum - 1]
            }
        }
        Write-Host "  -> Enter a number between 1-$($procs.Count)" -ForegroundColor Yellow
    }
}

# ═══════════════════════════════════════════════════════════
#  MAIN
# ═══════════════════════════════════════════════════════════

Write-Host ""
Write-Host "  +================================================+" -ForegroundColor Cyan
Write-Host "  |       TERMINAL SCREEN SCRAPER (PowerShell)      |" -ForegroundColor Cyan
Write-Host "  |       Ctrl+C -> trim -> save -> F8 -> repeat    |" -ForegroundColor Cyan
Write-Host "  +================================================+" -ForegroundColor Cyan
Write-Host ""

$proc = Select-TargetWindow
$hwnd = $proc.MainWindowHandle

Write-Host "`n  Selected: << $($proc.MainWindowTitle) >>" -ForegroundColor Green

$outputFile = Read-Host "  Output file name [output.txt]"
if ([string]::IsNullOrWhiteSpace($outputFile)) {
    $outputFile = "output.txt"
}

$useCtrlAInput = Read-Host "  Send Ctrl+A before Ctrl+C? (y/n) [n]"
$useCtrlA = $useCtrlAInput -in @("t", "y", "tak", "yes")

$topTrimInput = Read-Host "  Lines to remove from top    [3]"
if ([string]::IsNullOrWhiteSpace($topTrimInput)) {
    $topTrim = 3
} else {
    $topTrim = [int]$topTrimInput
}

$bottomTrimInput = Read-Host "  Lines to remove from bottom [3]"
if ([string]::IsNullOrWhiteSpace($bottomTrimInput)) {
    $bottomTrim = 3
} else {
    $bottomTrim = [int]$bottomTrimInput
}

Write-Host ""
Write-Host "  SPEED — delay multiplier:" -ForegroundColor Cyan
Write-Host "    1.0 = normal (default)"
Write-Host "    0.5 = 2x faster"
Write-Host "    0.2 = 5x faster (aggressive)"
Write-Host "    2.0 = 2x slower (slow terminal / VPN)"
Write-Host ""

$speedInput = Read-Host "  Speed multiplier [1.0]"
if ([string]::IsNullOrWhiteSpace($speedInput)) {
    $script:SpeedMultiplier = 1.0
} else {
    $script:SpeedMultiplier = [Math]::Max(0.05, [double]$speedInput)
}

$baseTimeMs = 150 + 30 + 30 + 150 + 50 + 150 + 30 + 100 + 150 + 100 + 200
$actualTimeMs = [int]($baseTimeMs * $script:SpeedMultiplier)

Write-Host "`n$('-' * 50)"
Write-Host "  Output file    : $outputFile"
if ($useCtrlA) {
    Write-Host "  Ctrl+A         : YES"
} else {
    Write-Host "  Ctrl+A         : NO"
}
Write-Host "  Trim top/bottom: $topTrim / $bottomTrim"
Write-Host "  Speed multiplier: $($script:SpeedMultiplier)x"
Write-Host "  ~time/page     : ${actualTimeMs}ms (~$([Math]::Round($actualTimeMs/1000, 2))s)"
Write-Host "$('-' * 50)"

Read-Host "`n  Press ENTER to start"

"" | Set-Content -Path $outputFile -Encoding UTF8 -NoNewline

$page            = 0
$totalLines      = 0
$previousContent = $null
$stopwatch       = [System.Diagnostics.Stopwatch]::StartNew()

Write-Host "`n  [START] Scraping started...`n" -ForegroundColor Green

try {
    while ($true) {
        $page++
        $pageTimer = [System.Diagnostics.Stopwatch]::StartNew()

        Focus-Window -Handle $hwnd

        if ($useCtrlA) { Send-CtrlA }

        Clear-ClipboardContent
        Wait-Ms 50

        Send-CtrlC
        Wait-Ms 200

        $rawText = Get-ClipboardText

        if ([string]::IsNullOrWhiteSpace($rawText)) {
            Write-Host "  [PAGE $page] Clipboard empty — STOP" -ForegroundColor Yellow
            break
        }

        $trimmed = Trim-Lines -Text $rawText -Top $topTrim -Bottom $bottomTrim

        if ([string]::IsNullOrWhiteSpace($trimmed)) {
            Write-Host "  [PAGE $page] Content empty after trimming — STOP" -ForegroundColor Yellow
            break
        }

        if ($trimmed -eq $previousContent) {
            Write-Host "  [PAGE $page] Duplicate content detected — STOP" -ForegroundColor Yellow
            break
        }
        $previousContent = $trimmed

        Add-Content -Path $outputFile -Value $trimmed -Encoding UTF8

        $lineCount   = ($trimmed -split "`n").Count
        $totalLines += $lineCount
        $pageMs      = $pageTimer.ElapsedMilliseconds

        Write-Host "  [PAGE $page] $lineCount lines | total: $totalLines | ${pageMs}ms"

        Focus-Window -Handle $hwnd
        Send-F8
        Wait-Ms 200
    }
}
catch {
    Write-Host "`n  [!] Error: $($_.Exception.Message)" -ForegroundColor Red
}

$stopwatch.Stop()
$elapsed = $stopwatch.Elapsed

$absPath = $outputFile
if (Test-Path $outputFile) {
    $absPath  = (Resolve-Path $outputFile).Path
    $fileSize = (Get-Item $outputFile).Length
} else {
    $fileSize = 0
}

$pagesCompleted = [Math]::Max(0, $page - 1)
if ($pagesCompleted -gt 0) {
    $avgPerPage = [Math]::Round($elapsed.TotalSeconds / $pagesCompleted, 2)
} else {
    $avgPerPage = 0
}

Write-Host "`n$('=' * 50)"
Write-Host "  DONE!" -ForegroundColor Green
Write-Host "  Pages scraped    : $pagesCompleted"
Write-Host "  Total lines      : $totalLines"
Write-Host "  File size        : $fileSize B"
Write-Host "  Total time       : $($elapsed.ToString('mm\:ss\.ff'))"
Write-Host "  Avg time/page    : ${avgPerPage}s"
Write-Host "  Saved to         : $absPath"
Write-Host "$('=' * 50)`n"