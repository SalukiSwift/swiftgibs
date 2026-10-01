# Start the local instagib FFA server and show both connect addresses.
# All the logic lives here rather than in the .bat: batch quoting mangles
# nested quotes and pipes inside for /f, which silently broke IP detection.

$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$exe  = Join-Path $here 'sauer_server.exe'

# The LAN address is the one on an adapter that is up AND has a default
# gateway. Filtering by adapter name is not enough: idle Hyper-V and Ethernet
# adapters sit on 169.254.x.x link-local addresses and would win otherwise.
$lan = (Get-NetIPConfiguration |
        Where-Object { $_.IPv4DefaultGateway -and $_.NetAdapter.Status -eq 'Up' } |
        Select-Object -First 1).IPv4Address.IPAddress

# One-time firewall rule. This WiFi is a "Public" network, where Windows drops
# incoming game traffic by default.
#
# Detection goes through netsh, NOT Get-NetFirewallRule: the latter throws
# "Access is denied" for a non-elevated user here, and with -ErrorAction
# SilentlyContinue that looks identical to "no rule exists" - so the script
# nagged for admin on every launch even when the rule was already in place.
function Test-FirewallRule {
    $null = & netsh advfirewall firewall show rule name=SwiftGibsLocalServer 2>&1
    return ($LASTEXITCODE -eq 0)
}

if (-not (Test-FirewallRule)) {
    Write-Host ''
    Write-Host '  Windows Firewall is blocking incoming players.' -ForegroundColor Yellow
    Write-Host '  Please click YES on the admin prompt to allow UDP 28785-28786.' -ForegroundColor Yellow
    $netshArgs = @('advfirewall','firewall','add','rule','name=SwiftGibsLocalServer',
                   'dir=in','action=allow','protocol=UDP','localport=28785-28786','profile=any')
    try {
        Start-Process netsh -ArgumentList $netshArgs -Verb RunAs -Wait
    } catch {
        Write-Host '  Admin prompt was declined.' -ForegroundColor Red
    }
}
$haveRule = Test-FirewallRule

if (Get-Process sauer_server -ErrorAction SilentlyContinue) {
    Write-Host ''
    Write-Host '  A server is already running - using that one.' -ForegroundColor Cyan
} else {
    Start-Process -FilePath $exe -WorkingDirectory $here   # cwd matters: it reads server-init.cfg
    Start-Sleep -Seconds 1
}

Write-Host ''
Write-Host '  Instagib FFA on fdm6, instant respawns.'
Write-Host ''
Write-Host '    You:          /connect localhost'
if ($lan) {
    Write-Host "    Your friend:  /connect $lan"
} else {
    Write-Host '    Your friend:  (no network found - check WiFi is connected)' -ForegroundColor Red
}
Write-Host ''
if (-not $haveRule) {
    Write-Host '  WARNING: no firewall rule, so friends will NOT get through.' -ForegroundColor Red
    Write-Host '  Re-run this and approve the admin prompt.' -ForegroundColor Red
    Write-Host ''
}
Write-Host '  The server runs in its own window. Close that window to stop it.'
Write-Host ''
Read-Host '  Press Enter to close this window (the server keeps running)'
