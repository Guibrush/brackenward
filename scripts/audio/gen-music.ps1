#requires -Version 5.1
# Generate one music bed and land it as a seamless OGG loop.
#
#   powershell -NoProfile -File scripts/audio/gen-music.ps1 `
#       -Id mus_forest_calm -Prompt "calm 8-bit chiptune exploration theme" -Seconds 20
#
# Looping is engineered, not requested: the model returns a track with leading
# silence and a quieter tail, so post.ps1 trims and crossfades the seam before
# normalising. Never ship the raw generator output.
#
# `-FromFile` skips the API and re-processes an existing clip.

param(
    [Parameter(Mandatory = $true)][string]$Id,
    [string]$Prompt = '',
    [double]$Seconds = 20,
    [string]$Out = '',
    [string]$FromFile = '',
    [switch]$AllowVocals,
    [string]$License = 'ElevenLabs generated',
    [double]$TargetLufs = -18,
    [int]$CrossfadeMs = 100
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\lib\common.ps1')
. (Join-Path $PSScriptRoot '..\gate\gate.config.ps1')

if ($Seconds -lt 3 -or $Seconds -gt 600) { Write-Error '-Seconds must be between 3 and 600'; exit 1 }
if ($Out -eq '') { $Out = Join-Path $StudioRoot ('assets\audio\music\' + $Id + '.ogg') }
$tmp = Join-Path $env:TEMP ('gen_mus_' + [guid]::NewGuid().ToString('N') + '.mp3')
$source = $null
$songId = ''

if ($FromFile -ne '') {
    if (-not (Test-Path $FromFile)) { Write-Error ('-FromFile not found: ' + $FromFile); exit 1 }
    $source = $FromFile
    Write-Host ('source: ' + $FromFile + ' (no generation)')
} else {
    if ($Prompt -eq '') { Write-Error '-Prompt is required unless -FromFile is used'; exit 1 }
    $key = Get-SecretValue 'ELEVENLABS_API_KEY'
    if (-not $key) { Write-Error 'ELEVENLABS_API_KEY not found in User or Machine scope'; exit 1 }

    Add-Type -AssemblyName System.Net.Http
    $client = New-Object System.Net.Http.HttpClient
    $client.Timeout = [TimeSpan]::FromSeconds(300)
    $client.DefaultRequestHeaders.Add('xi-api-key', $key)
    $body = @{
        prompt             = $Prompt
        music_length_ms    = [int]($Seconds * 1000)
        model_id           = 'music_v2_5'
        force_instrumental = (-not $AllowVocals)
    } | ConvertTo-Json -Compress
    $content = New-Object System.Net.Http.StringContent($body, [System.Text.Encoding]::UTF8, 'application/json')
    try {
        $resp = $client.PostAsync('https://api.elevenlabs.io/v1/music?output_format=mp3_48000_192', $content).GetAwaiter().GetResult()
    } catch {
        Write-Error ('request failed: ' + $_.Exception.Message)
        exit 1
    }
    if ([int]$resp.StatusCode -ne 200) {
        $txt = $resp.Content.ReadAsStringAsync().GetAwaiter().GetResult()
        Write-Error ('API returned ' + [int]$resp.StatusCode + ': ' + $txt.Substring(0, [Math]::Min(300, $txt.Length)))
        exit 1
    }
    $sid = $null
    if ($resp.Headers.TryGetValues('song-id', [ref]$sid)) { $songId = (@($sid)[0]) }
    $bytes = $resp.Content.ReadAsByteArrayAsync().GetAwaiter().GetResult()
    [System.IO.File]::WriteAllBytes($tmp, $bytes)
    if (-not $bytes.Length) { Write-Error 'API returned an empty body'; exit 1 }
    $source = $tmp
    Write-Host ('generated: ' + $bytes.Length + ' bytes, ' + $Seconds + 's requested, song ' + $songId)
}

$postArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $PSScriptRoot 'post.ps1'),
    '-In', $source, '-Out', $Out, '-Kind', 'music', '-Loop',
    '-TargetLufs', [string]$TargetLufs, '-CrossfadeMs', [string]$CrossfadeMs)

$post = Invoke-Native -Exe 'powershell' -Arguments $postArgs
Write-Host $post.Output.TrimEnd()
if ($post.ExitCode -ne 0) { if (Test-Path $tmp) { Remove-Item $tmp -Force }; exit 1 }

$rel = $Out.Replace($StudioRoot.TrimEnd('\') + '\', '').Replace('\', '/')
Add-ManifestEntry -Path (Join-Path $StudioRoot 'audio\manifest.json') -Collection 'entries' -Entry ([pscustomobject]@{
    id          = $Id
    kind        = 'music'
    file        = $rel
    loop        = $true
    target_lufs = $TargetLufs
    license     = $License
    prompt      = $Prompt
    song_id     = $songId
    generator   = $(if ($FromFile -ne '') { 'local file' } else { 'elevenlabs/music' })
    cost        = $(if ($FromFile -ne '') { 'none' } else { $Seconds.ToString() + 's music generation' })
})

if (Test-Path $tmp) { Remove-Item $tmp -Force -ErrorAction SilentlyContinue }
Write-Host ('manifest: audio/manifest.json += ' + $Id)
exit 0
