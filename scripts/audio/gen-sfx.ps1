#requires -Version 5.1
# Generate one sound effect and land it in the project, ready for the gate.
#
#   powershell -NoProfile -File scripts/audio/gen-sfx.ps1 `
#       -Id sfx_coin_pickup_01 -Prompt "retro arcade coin pickup" -Seconds 1
#
# Costs one ElevenLabs generation. `-FromFile` skips the API entirely and only
# re-processes an existing clip, which is how you verify the pipeline or fix a
# bad normalisation without paying twice.

param(
    [Parameter(Mandatory = $true)][string]$Id,
    [string]$Prompt = '',
    [double]$Seconds = 1.0,
    [switch]$Loop,
    [string]$Out = '',
    [string]$FromFile = '',
    [string]$License = 'ElevenLabs generated',
    [double]$TargetLufs = -16
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\lib\common.ps1')
. (Join-Path $PSScriptRoot '..\gate\gate.config.ps1')

if ($Out -eq '') { $Out = Join-Path $StudioRoot ('assets\audio\sfx\' + $Id + '.wav') }
$tmp = Join-Path $env:TEMP ('gen_sfx_' + [guid]::NewGuid().ToString('N') + '.mp3')
$source = $null

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
    $client.Timeout = [TimeSpan]::FromSeconds(120)
    $client.DefaultRequestHeaders.Add('xi-api-key', $key)
    $body = @{
        text              = $Prompt
        duration_seconds  = $Seconds
        prompt_influence  = 0.5
        model_id          = 'eleven_text_to_sound_v3'
        loop              = [bool]$Loop
    } | ConvertTo-Json -Compress
    $content = New-Object System.Net.Http.StringContent($body, [System.Text.Encoding]::UTF8, 'application/json')
    try {
        $resp = $client.PostAsync('https://api.elevenlabs.io/v1/sound-generation?output_format=mp3_44100_128', $content).GetAwaiter().GetResult()
    } catch {
        Write-Error ('request failed: ' + $_.Exception.Message)
        exit 1
    }
    if ([int]$resp.StatusCode -ne 200) {
        $txt = $resp.Content.ReadAsStringAsync().GetAwaiter().GetResult()
        Write-Error ('API returned ' + [int]$resp.StatusCode + ': ' + $txt.Substring(0, [Math]::Min(300, $txt.Length)))
        exit 1
    }
    $bytes = $resp.Content.ReadAsByteArrayAsync().GetAwaiter().GetResult()
    [System.IO.File]::WriteAllBytes($tmp, $bytes)
    if (-not $bytes.Length) { Write-Error 'API returned an empty body'; exit 1 }
    $source = $tmp
    Write-Host ('generated: ' + $bytes.Length + ' bytes, ' + $Seconds + 's requested')
}

$postArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $PSScriptRoot 'post.ps1'),
    '-In', $source, '-Out', $Out, '-Kind', 'sfx', '-TargetLufs', [string]$TargetLufs,
    '-MaxSeconds', [string][math]::Ceiling($Seconds + 0.5))
if ($Loop) { $postArgs += '-Loop' }

$post = Invoke-Native -Exe 'powershell' -Arguments $postArgs
Write-Host $post.Output.TrimEnd()
if ($post.ExitCode -ne 0) { if (Test-Path $tmp) { Remove-Item $tmp -Force }; exit 1 }

$rel = $Out.Replace($StudioRoot.TrimEnd('\') + '\', '').Replace('\', '/')
Add-ManifestEntry -Path (Join-Path $StudioRoot 'audio\manifest.json') -Collection 'entries' -Entry ([pscustomobject]@{
    id          = $Id
    kind        = 'sfx'
    file        = $rel
    loop        = [bool]$Loop
    target_lufs = $TargetLufs
    max_seconds = [math]::Ceiling($Seconds + 0.5)
    license     = $License
    prompt      = $Prompt
    generator   = $(if ($FromFile -ne '') { 'local file' } else { 'elevenlabs/text_to_sound_effects' })
    cost        = $(if ($FromFile -ne '') { 'none' } else { '1 sound effect generation' })
})

if (Test-Path $tmp) { Remove-Item $tmp -Force -ErrorAction SilentlyContinue }
Write-Host ('manifest: audio/manifest.json += ' + $Id)
exit 0
