#Requires -Version 5.1
<#
.SYNOPSIS
    Terminal Screen Scraper
.DESCRIPTION
    Kopiuje zawartość ekranu terminala strona po stronie
    (Ctrl+C → trim → zapis → F8 → powtórz)
#>

# ═══════════════════════════════════════════════════════════
#  .NET — dostęp do Win32 API + Clipboard
# ═══════════════════════════════════════════════════════════
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

    public const int SW_RESTORE        = 9;
    public const byte VK_CONTROL       = 0x11;
    public const byte VK_A             = 0x41;
    public const byte VK_C             = 0x43;
    public const byte VK_F8            = 0x77;
    public const uint KEYEVENTF_KEYUP  = 0x0002;
}
"@

# ═══════════════════════════════════════════════════════════
#  Funkcje pomocnicze
# ═══════════════════════════════════════════════════════════

function Focus-Window([IntPtr]$Handle) {
    if ([Win32]::IsIconic($Handle)) {
        [Win32]::ShowWindow($Handle, [Win32]::SW_RESTORE) | Out-Null
    }
    [Win32]::SetForegroundWindow($Handle) | Out-Null
    Start-Sleep -Milliseconds 300
}

function Send-KeyDown([byte]$vk) {
    [Win32]::keybd_event($vk, 0, 0, [UIntPtr]::Zero)
}

function Send-KeyUp([byte]$vk) {
    [Win32]::keybd_event($vk, 0, [Win32]::KEYEVENTF_KEYUP, [UIntPtr]::Zero)
}

function Send-CtrlC {
    Send-KeyDown ([Win32]::VK_CONTROL)
    Start-Sleep -Milliseconds 50
    Send-KeyDown ([Win32]::VK_C)
    Start-Sleep -Milliseconds 50
    Send-KeyUp   ([Win32]::VK_C)
    Send-KeyUp   ([Win32]::VK_CONTROL)
    Start-Sleep -Milliseconds 300
}

function Send-CtrlA {
    Send-KeyDown ([Win32]::VK_CONTROL)
    Start-Sleep -Milliseconds 50
    Send-KeyDown ([Win32]::VK_A)
    Start-Sleep -Milliseconds 50
    Send-KeyUp   ([Win32]::VK_A)
    Send-KeyUp   ([Win32]::VK_CONTROL)
    Start-Sleep -Milliseconds 200
}

function Send-F8 {
    Send-KeyDown ([Win32]::VK_F8)
    Start-Sleep -Milliseconds 50
    Send-KeyUp   ([Win32]::VK_F8)
    Start-Sleep -Milliseconds 200
}

function Get-ClipboardText {
    try {
        $text = [System.Windows.Forms.Clipboard]::GetText()
        return $text
    } catch {
        return ""
    }
}

function Clear-ClipboardContent {
    try {
        [System.Windows.Forms.Clipboard]::Clear()
    } catch {}
}

function Trim-Lines {
    param(
        [string]$Text,
        [int]$Top    = 3,
        [int]$Bottom = 3
    )
    $lines = $Text -split "`r?`n"

    if ($lines.Count -le ($Top + $Bottom)) {
        return ""
    }

    $trimmed = $lines[$Top..($lines.Count - $Bottom - 1)]
    return ($trimmed -join "`n")
}

# ═══════════════════════════════════════════════════════════
#  Menu wyboru okna
# ═══════════════════════════════════════════════════════════
function Select-TargetWindow {
    $procs = Get-Process |
        Where-Object { $_.MainWindowHandle -ne [IntPtr]::Zero -and $_.MainWindowTitle } |
        Sort-Object MainWindowTitle

    if ($procs.Count -eq 0) {
        Write-Host "`n  [BLAD] Nie znaleziono zadnych okien." -ForegroundColor Red
        exit 1
    }

    Write-Host "`n$('=' * 60)"
    Write-Host "  DOSTEPNE OKNA"
    Write-Host "$('=' * 60)"

    for ($i = 0; $i -lt $procs.Count; $i++) {
        $title = $procs[$i].MainWindowTitle
        if ($title.Length -gt 52) { $title = $title.Substring(0, 49) + "..." }
        $num = ($i + 1).ToString().PadLeft(3)
        Write-Host "  $num | $title"
    }

    Write-Host "$('=' * 60)"

    while ($true) {
        $input = Read-Host "`n  Podaj numer okna"
        $choice = 0
        if ([int]::TryParse($input, [ref]$choice)) {
            if ($choice -ge 1 -and $choice -le $procs.Count) {
                return $procs[$choice - 1]
            }
        }
        Write-Host "  -> Wybierz liczbe 1-$($procs.Count)" -ForegroundColor Yellow
    }
}

# ═══════════════════════════════════════════════════════════
#  MAIN
# ═══════════════════════════════════════════════════════════

Write-Host @"

  +================================================+
  |       TERMINAL SCREEN SCRAPER (PowerShell)      |
  |       Ctrl+C -> trim -> save -> F8 -> repeat    |
  +================================================+

"@ -ForegroundColor Cyan

# ---------- konfiguracja ----------

$proc = Select-TargetWindow
$hwnd = $proc.MainWindowHandle

Write-Host "`n  Wybrano: << $($proc.MainWindowTitle) >>" -ForegroundColor Green

$outputFile = Read-Host "  Nazwa pliku wyjsciowego [output.txt]"
if ([string]::IsNullOrWhiteSpace($outputFile)) { $outputFile = "output.txt" }

$useCtrlA = Read-Host "  Wysylac Ctrl+A przed Ctrl+C? (t/n) [n]"
$useCtrlA = $useCtrlA -in @("t", "y", "tak", "yes")

$topTrimInput = Read-Host "  Ile linii usuwac z gory?  [3]"
$topTrim = if ($topTrimInput) { [int]$topTrimInput } else { 3 }

$bottomTrimInput = Read-Host "  Ile linii usuwac z dolu?  [3]"
$bottomTrim = if ($bottomTrimInput) { [int]$bottomTrimInput } else { 3 }

$delayInput = Read-Host "  Opoznienie miedzy stronami w sek. [1.0]"
$delay = if ($delayInput) { [double]$delayInput } else { 1.0 }

Write-Host "`n$('-' * 50)"
Write-Host "  Plik wyjsciowy : $outputFile"
Write-Host "  Ctrl+A         : $(if ($useCtrlA) {'TAK'} else {'NIE'})"
Write-Host "  Trim gora/dol  : $topTrim / $bottomTrim"
Write-Host "  Opoznienie     : ${delay}s"
Write-Host "$('-' * 50)"

Read-Host "`n  Nacisnij ENTER aby rozpoczac"

# ---------- przygotowanie pliku ----------
"" | Set-Content -Path $outputFile -Encoding UTF8 -NoNewline

# ---------- petla ----------
$page           = 0
$totalLines     = 0
$previousContent = $null

Write-Host "`n  [START] Rozpoczynam kopiowanie...`n" -ForegroundColor Green

try {
    while ($true) {
        $page++

        # 1. Aktywuj okno
        Focus-Window -Handle $hwnd
        Start-Sleep -Milliseconds 200

        # 2. Opcjonalnie Ctrl+A
        if ($useCtrlA) {
            Send-CtrlA
        }

        # 3. Wyczysc schowek + Ctrl+C
        Clear-ClipboardContent
        Start-Sleep -Milliseconds 100

        Send-CtrlC
        Start-Sleep -Milliseconds 400

        # 4. Odczytaj schowek
        $rawText = Get-ClipboardText

        if ([string]::IsNullOrWhiteSpace($rawText)) {
            Write-Host "  [STRONA $page] Schowek pusty — STOP" -ForegroundColor Yellow
            break
        }

        # 5. Trim
        $trimmed = Trim-Lines -Text $rawText -Top $topTrim -Bottom $bottomTrim

        # 6. Pusta tresc po trimie?
        if ([string]::IsNullOrWhiteSpace($trimmed)) {
            Write-Host "  [STRONA $page] Po przyciu linii tresc pusta — STOP" -ForegroundColor Yellow
            break
        }

        # 7. Duplikat = koniec scrolla
        if ($trimmed -eq $previousContent) {
            Write-Host "  [STRONA $page] Tresc identyczna z poprzednia strona — STOP" -ForegroundColor Yellow
            break
        }
        $previousContent = $trimmed

        # 8. Dopisz do pliku
        Add-Content -Path $outputFile -Value $trimmed -Encoding UTF8

        $lineCount   = ($trimmed -split "`n").Count
        $totalLines += $lineCount
        Write-Host "  [STRONA $page] Zapisano $lineCount linii  (lacznie: $totalLines)"

        # 9. F8 — przewiniecie
        Focus-Window -Handle $hwnd
        Start-Sleep -Milliseconds 150
        Send-F8

        # 10. Czekaj
        Start-Sleep -Seconds $delay
    }
}
catch {
    Write-Host "`n  [!] Blad: $($_.Exception.Message)" -ForegroundColor Red
}

# ---------- podsumowanie ----------
$absPath  = (Resolve-Path $outputFile -ErrorAction SilentlyContinue).Path
if (-not $absPath) { $absPath = $outputFile }
$fileSize = if (Test-Path $outputFile) { (Get-Item $outputFile).Length } else { 0 }

Write-Host "`n$('=' * 50)"
Write-Host "  GOTOWE!" -ForegroundColor Green
Write-Host "  Stron skopiowanych : $($page - 1)"
Write-Host "  Linii lacznie      : $totalLines"
Write-Host "  Rozmiar pliku      : $fileSize B"
Write-Host "  Zapisano do        : $absPath"
Write-Host "$('=' * 50)`n"