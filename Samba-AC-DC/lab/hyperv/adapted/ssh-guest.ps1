# Ejecuta un comando en el guest por SSH.
#   VirtualBox (reparacion): -Port 2222 (host 127.0.0.1)
#   Hyper-V (red real):      -HostName 192.168.0.121 -Port 22
# Uso:
#   powershell -ExecutionPolicy Bypass -File .\ssh-guest.ps1 "hostname; uname -r"
#   powershell -ExecutionPolicy Bypass -File .\ssh-guest.ps1 "@.\script.sh" -HostName 192.168.0.121 -Port 22
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$Command,
    [string]$HostName = '127.0.0.1',
    [int]$Port = 2222,
    [string]$User = 'sysadmin'
)

$askpass = Join-Path $PSScriptRoot 'askpass.exe'
if (-not (Test-Path $askpass)) { throw "Falta $askpass. Ejecuta build-askpass.ps1." }

$env:SSH_ASKPASS         = $askpass
$env:SSH_ASKPASS_REQUIRE = 'force'
$env:DISPLAY             = 'localhost:0'

function Invoke-Remote([string]$remoteCommand, [switch]$WithStdin, [string]$stdinText) {
    $args = @(
        '-p', $Port,
        '-o', 'StrictHostKeyChecking=no',
        '-o', 'UserKnownHostsFile=NUL',
        '-o', 'PreferredAuthentications=password',
        '-o', 'NumberOfPasswordPrompts=1',
        '-o', 'ConnectTimeout=15',
        "$User@$HostName",
        $remoteCommand
    )
    if ($WithStdin) {
        $stdinText | & ssh @args
    } else {
        & ssh @args
    }
}

# Si $Command empieza por '@', se interpreta como ruta a un script local que
# se sube a /tmp y se ejecuta con bash.
if ($Command.StartsWith('@')) {
    $file = $Command.Substring(1)
    if (-not (Test-Path $file)) { throw "No existe el script local: $file" }
    # Base64 en una sola linea: PowerShell convierte LF->CRLF al usar stdin nativo.
    $text = (Get-Content -Raw -Path $file) -replace "`r", ''
    $b64  = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($text))
    Invoke-Remote "printf '%s' '$b64' | base64 -d > /tmp/opencode-guest.sh; bash /tmp/opencode-guest.sh"
} else {
    Invoke-Remote $Command
}
exit $LASTEXITCODE
