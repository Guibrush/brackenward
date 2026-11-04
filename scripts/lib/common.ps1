# Shared helpers for gate scripts. Dot-source it:
#   . (Join-Path $PSScriptRoot '..\lib\common.ps1')
#
# Exit codes used by every gate script:
#   0  pass
#   1  fail      — a criterion is not satisfied
#   3  blocked   — the criterion cannot be evaluated yet (missing engine, no scene)
#
# Blocked is deliberately distinct from fail: "Godot is not installed" must never
# look like "the code is broken".

$script:GateResults = New-Object System.Collections.ArrayList

function Add-Result {
    param(
        [Parameter(Mandatory = $true)][string]$Id,
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][ValidateSet('pass', 'fail', 'blocked')][string]$Status,
        [string]$Detail = ''
    )
    [void]$script:GateResults.Add([pscustomobject]@{ Id = $Id; Name = $Name; Status = $Status; Detail = $Detail })

    if ($Status -eq 'pass') { $label = 'PASS ' }
    elseif ($Status -eq 'fail') { $label = 'FAIL ' }
    else { $label = 'BLOCK' }

    $line = '  [' + $label + '] ' + $Id.PadRight(7) + ' ' + $Name
    if ($Detail -ne '') { $line = $line + ' - ' + $Detail }
    Write-Host $line
}

function Complete-Gate {
    param([string]$Title = 'gate')
    $pass = @($script:GateResults | Where-Object { $_.Status -eq 'pass' }).Count
    $fail = @($script:GateResults | Where-Object { $_.Status -eq 'fail' }).Count
    $block = @($script:GateResults | Where-Object { $_.Status -eq 'blocked' }).Count

    Write-Host ''
    Write-Host ('{0}: {1} pass, {2} fail, {3} blocked' -f $Title, $pass, $fail, $block)

    if ($fail -gt 0) { exit 1 }
    if ($block -gt 0) { exit 3 }
    exit 0
}

function Remove-Ansi {
    param([string]$Text)
    if ($null -eq $Text) { return '' }
    return ($Text -replace '\x1b\[[0-9;]*[A-Za-z]', '')
}

function Read-Text {
    param([string]$Path)
    if (-not (Test-Path $Path)) { return $null }
    return (Get-Content $Path -Raw)
}

# Returns the body of a "## Heading" section, up to the next "## " or EOF.
function Get-Section {
    param([string]$Text, [string]$Heading)
    if ([string]::IsNullOrEmpty($Text)) { return '' }
    $pattern = '(?ms)^##[ \t]+' + [regex]::Escape($Heading) + '[ \t]*\r?\n(.*?)(?=^##[ \t]|\z)'
    $m = [regex]::Match($Text, $pattern)
    if ($m.Success) { return $m.Groups[1].Value }
    return ''
}

function Get-TodoLines {
    param([string]$Text)
    if ([string]::IsNullOrEmpty($Text)) { return @() }
    return @([regex]::Matches($Text, '(?m)^.*\bTODO\b.*$') | ForEach-Object { $_.Value.Trim() })
}

# Runs a native executable and returns exit code plus ANSI-stripped output.
#
# Uses System.Diagnostics.Process rather than '&' with redirection. In Windows
# PowerShell 5.1, redirected native stderr becomes ErrorRecords, and a caller
# running with $ErrorActionPreference = 'Stop' turns those into a terminating
# error - so any tool that logs to stderr would crash the script calling it.
# Reading the process pipes directly avoids PowerShell's stream model entirely.
function Invoke-Native {
    param(
        [Parameter(Mandatory = $true)][string]$Exe,
        [string[]]$Arguments = @()
    )

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $Exe
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.StandardOutputEncoding = [System.Text.Encoding]::UTF8
    $psi.StandardErrorEncoding = [System.Text.Encoding]::UTF8

    $quoted = @()
    foreach ($a in $Arguments) {
        if ($a -match '[\s"]') { $quoted += ('"' + ($a -replace '"', '\"') + '"') }
        else { $quoted += $a }
    }
    $psi.Arguments = ($quoted -join ' ')

    $p = New-Object System.Diagnostics.Process
    $p.StartInfo = $psi
    try {
        [void]$p.Start()
    } catch {
        return [pscustomobject]@{
            ExitCode = 127
            Output   = ('executable not found or not runnable: ' + $Exe)
        }
    }
    $outTask = $p.StandardOutput.ReadToEndAsync()
    $errTask = $p.StandardError.ReadToEndAsync()
    $p.WaitForExit()
    $text = $outTask.Result + $errTask.Result

    return [pscustomobject]@{
        ExitCode = $p.ExitCode
        Output   = (Remove-Ansi $text)
    }
}

# Reads a secret from the Windows registry rather than the process environment.
# A stale parent environment is the reason this exists; see L-001.
function Get-SecretValue {
    param([Parameter(Mandatory = $true)][string]$Name)
    foreach ($scope in @('User', 'Machine')) {
        $v = [Environment]::GetEnvironmentVariable($Name, $scope)
        if ($v) { return $v.Trim() }
    }
    $v = [Environment]::GetEnvironmentVariable($Name)
    if ($v) { return $v.Trim() }
    return $null
}

# Appends an entry to a manifest collection, preserving the rest of the file.
# Not concurrency-safe: one writer at a time is a studio rule, see OWNERSHIP.md.
function Add-ManifestEntry {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Collection,
        [Parameter(Mandatory = $true)][object]$Entry
    )
    $obj = $null
    if (Test-Path $Path) {
        $obj = Get-Content $Path -Raw | ConvertFrom-Json
    } else {
        $obj = [pscustomobject]@{ version = 1 }
    }
    $list = @()
    if ($obj.PSObject.Properties.Name -contains $Collection) { $list = @($obj.$Collection) }
    $list += $Entry
    $obj | Add-Member -NotePropertyName $Collection -NotePropertyValue $list -Force
    $obj | ConvertTo-Json -Depth 8 | Set-Content $Path -Encoding utf8
}

# Converts an absolute path inside the project into a res:// path.
function ConvertTo-ResPath {
    param([string]$Root, [string]$Path)
    $r = $Root.TrimEnd('\')
    $p = $Path.Replace('/', '\')
    if ($p.StartsWith($r, [System.StringComparison]::OrdinalIgnoreCase)) {
        return 'res:/' + $p.Substring($r.Length).Replace('\', '/')
    }
    return $null
}

# Reads width and height from a PNG header without decoding pixels.
function Get-PngSize {
    param([string]$Path)
    try {
        $bytes = [System.IO.File]::ReadAllBytes($Path)
        if ($bytes.Length -lt 24) { return $null }
        if ($bytes[0] -ne 0x89 -or $bytes[1] -ne 0x50 -or $bytes[2] -ne 0x4E -or $bytes[3] -ne 0x47) { return $null }
        $w = ($bytes[16] -shl 24) + ($bytes[17] -shl 16) + ($bytes[18] -shl 8) + $bytes[19]
        $h = ($bytes[20] -shl 24) + ($bytes[21] -shl 16) + ($bytes[22] -shl 8) + $bytes[23]
        return [pscustomobject]@{ Width = $w; Height = $h }
    } catch { return $null }
}
