# Ejecuta la adaptacion completa con UN solo UAC:
#   00 (rol/grupo/disco) -> 01 (switch + VM) -> 02 (prueba de parada graciosa)
#
# Uso (se autoeleva desde EJECUTAR-COMO-ADMIN.cmd, o manualmente como admin):
#   powershell -ExecutionPolicy Bypass -File .\ejecutar-todo.ps1 -LeaveRunning
#Requires -RunAsAdministrator
param(
    [switch]$LeaveRunning
)

$ErrorActionPreference = 'Stop'
$root   = $PSScriptRoot
$logDir = Join-Path $root 'logs'
New-Item -ItemType Directory -Path $logDir -Force | Out-Null
$log = Join-Path $logDir ("run-{0:yyyyMMdd-HHmmss}.log" -f (Get-Date))

function Say($m) { Write-Host "[$(Get-Date -Format HH:mm:ss)] $m" }

Start-Transcript -Path $log -Force | Out-Null
try {
    Say "Log: $log"
    Say '=== 00-preparar-host.ps1 ==='
    & (Join-Path $root '00-preparar-host.ps1')

    Say '=== 01-crear-vm-samba-dc1.ps1 ==='
    & (Join-Path $root '01-crear-vm-samba-dc1.ps1')

    Say '=== 02-verificar-apagado-graceful.ps1 ==='
    & (Join-Path $root '02-verificar-apagado-graceful.ps1') -LeaveRunning:$LeaveRunning

    Say '=== TODO COMPLETADO ==='
} catch {
    Say "ERROR: $($_.Exception.Message)"
    Say "Revisa el log: $log"
    throw
} finally {
    Stop-Transcript | Out-Null
}
