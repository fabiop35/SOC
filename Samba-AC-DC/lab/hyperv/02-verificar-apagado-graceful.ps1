# Requiere PowerShell ELEVADO. Verifica que la VM se apaga de forma CONTROLADA
# (mismo mecanismo que usara Windows al apagar el host fisico).
#
# Uso:  powershell -ExecutionPolicy Bypass -File lab\hyperv\02-verificar-apagado-graceful.ps1
param(
    [string]$VmName = 'samba-dc1',
    [int]$TimeoutParadaSeg = 240,
    [int]$TimeoutArranqueSeg = 300
)

$ErrorActionPreference = 'Stop'
function Say($m) { Write-Output "[$(Get-Date -Format HH:mm:ss)] $m" }

Import-Module Hyper-V

$vm = Get-VM -Name $VmName
Say "VM '$VmName' | Estado: $($vm.State) | AutomaticStopAction: $($vm.AutomaticStopAction)"

if ($vm.AutomaticStopAction -ne 'ShutDown') {
    Write-Warning "AutomaticStopAction = $($vm.AutomaticStopAction) (se espera 'ShutDown')"
}

# --- 1. Arrancar y esperar a que el guest responda -------------------------
if ($vm.State -ne 'Running') {
    Say 'Arrancando la VM...'
    Start-VM -Name $VmName | Out-Null
}
$sw = [Diagnostics.Stopwatch]::StartNew()
$heartbeatOk = $false
while ($sw.Elapsed.TotalSeconds -lt $TimeoutArranqueSeg) {
    Start-Sleep -Seconds 10
    $hb = Get-VMIntegrationService -VMName $VmName -Name 'Heartbeat' -ErrorAction SilentlyContinue
    $state = (Get-VM -Name $VmName).State
    if ($hb -and $hb.PrimaryStatusDescription -match 'OK|Heartbeat') {
        Say "El guest responde al latido de Hyper-V (integracion activa) en $([int]$sw.Elapsed.TotalSeconds)s."
        $heartbeatOk = $true
        break
    }
    Say "Esperando al guest... (estado VM: $state, $([int]$sw.Elapsed.TotalSeconds)s)"
    if ($state -ne 'Running') { throw "La VM cambio a estado '$state' durante el arranque." }
}
if (-not $heartbeatOk) {
    Write-Warning 'El guest no reporto latido: puede que las integraciones no esten instaladas en el guest.'
    Write-Warning 'En ese caso la parada controlada se hace por pulsador de alimentacion ACPI (probado en VirtualBox: OK).'
}

# --- 2. Parada controlada y medicion ---------------------------------------
Say 'Ejecutando Stop-VM (parada GRACIOSA: integracion Shutdown / ACPI, no -TurnOff)...'
$t0 = Get-Date
Stop-VM -Name $VmName
$t1 = Get-Date
$segundos = [math]::Round(($t1 - $t0).TotalSeconds, 1)

$final = (Get-VM -Name $VmName).State
Say "Estado final: $final  (tardó $segundos s)"

# --- 3. Aserciones ----------------------------------------------------------
$ok = $true
if ($final -ne 'Off') {
    Write-Error "FAIL: el estado final es '$final' (se esperaba 'Off'; 'Saved' implicaria suspension, no parada controlada)"
    $ok = $false
} else {
    Say "OK: la VM quedo en 'Off' (apagado real, no suspendida)."
}
if ($segundos -gt $TimeoutParadaSeg) {
    Write-Error "FAIL: la parada tardo $segundos s (tope configurado: $TimeoutParadaSeg s) -> el guest no respondio a la peticion de apagado."
    $ok = $false
} else {
    Say "OK: el guest apago dentro del tiempo esperado ($segundos s)."
}

# --- 4. Evidencias en el log de Hyper-V ------------------------------------
Say ''
Say 'Eventos recientes de Hyper-V sobre esta VM:'
foreach ($log in 'Microsoft-Windows-Hyper-V-VMMS-Admin', 'Microsoft-Windows-Hyper-V-Worker-Admin', 'Microsoft-Windows-Hyper-V-VMMS-Operational') {
    try {
        Get-WinEvent -LogName $log -MaxEvents 40 -ErrorAction Stop |
            Where-Object { $_.Message -like "*$VmName*" } |
            Select-Object TimeCreated, Id, ProviderName, @{n='Msg';e={($_.Message -replace '\s+', ' ').Substring(0, [math]::Min(150, ($_.Message -replace '\s+', ' ').Length))}} |
            Format-Table -AutoSize | Out-String | Write-Output
    } catch { }
}

Write-Output ''
if ($ok) {
    Write-Output 'RESULTADO: PARADA GRACIOSA CONFIRMADA'
    Write-Output 'Con AutomaticStopAction=ShutDown, un apagado fisico del host:'
    Write-Output '   1) envia al guest la peticion de apagado (integracion Shutdown / ACPI)'
    Write-Output '   2) el guest (systemd) detiene samba, cierra sam.ldb y desmonta en orden'
    Write-Output "   3) Hyper-V marca la VM como 'Off' (no 'Saved', no 'aborted')."
} else {
    Write-Output 'RESULTADO: HAY QUE REVISAR LA PARADA'
}
