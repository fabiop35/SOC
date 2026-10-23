# Envoltorio para capturar toda la salida de 02 en un log.
$log = Join-Path 'D:\tmp\lab\hyperv\adapted\logs' ('prueba-apagado-{0:yyyyMMdd-HHmmss}.log' -f (Get-Date))
Start-Transcript -Path $log -Force | Out-Null
try {
    & 'D:\tmp\lab\hyperv\adapted\02-verificar-apagado-graceful.ps1' -LeaveRunning
} catch {
    Write-Host "ERROR: $($_.Exception.Message)"
    Write-Host $_.ScriptStackTrace
} finally {
    Stop-Transcript | Out-Null
}
