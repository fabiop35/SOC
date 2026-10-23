# Adaptado a ESTA maquina (DESKTOP-OIAJKVE).
# Arranca la VM, espera latido + SSH, la para con Stop-VM (sin -Force) y comprueba
# que queda 'Off' (apagado real, no 'Saved') y que Hyper-V registro el evento
# 18504 (apagado ordenado por el servicio de integracion "Cierre").
#   18502 = apagado forzado (NO valido)
#   18504 = apagado ordenado (VALIDO)
#
# Uso:
#   powershell -ExecutionPolicy Bypass -File .\02-verificar-apagado-graceful.ps1 -LeaveRunning
#Requires -RunAsAdministrator
param(
    [string]$VmName           = 'samba-dc1',
    [int]$TimeoutParadaSeg    = 240,
    [int]$TimeoutArranqueSeg  = 600,
    [int]$TimeoutSshSeg       = 300,
    [string]$DcIp             = '192.168.0.121',
    [switch]$LeaveRunning
)

$ErrorActionPreference = 'Stop'
function Say($m) { Write-Host "[$(Get-Date -Format HH:mm:ss)] $m" }

Import-Module Hyper-V

# ---------------------------------------------------------------------------
# 0. Estado inicial y precondiciones
# ---------------------------------------------------------------------------
$vm = Get-VM -Name $VmName
Say "VM '$VmName' | Estado: $($vm.State) | AutomaticStopAction: $($vm.AutomaticStopAction)"
if ($vm.AutomaticStopAction -ne 'ShutDown') {
    throw "AutomaticStopAction = $($vm.AutomaticStopAction); se espera 'ShutDown'."
}

# Los nombres de las integraciones estan localizados ('Cierre', 'Latido'), pero
# el GUID del componente es estable en cualquier idioma.
$IC_SHUTDOWN  = '9F8233AC-BE49-4C79-8EE3-E7E1985B2077'
$IC_HEARTBEAT = '84EAAE65-2F2E-45F5-9BB5-0E857DC8EB47'

function Get-Ic([string]$guid) {
    Get-VMIntegrationService -VMName $VmName -ErrorAction SilentlyContinue |
        Where-Object { $_.Id -like "*$guid" } | Select-Object -First 1
}

$shutdownIc = Get-Ic $IC_SHUTDOWN
if (-not $shutdownIc) { throw "La VM no expone la integracion 'Cierre' (Shutdown)." }
Say "Integracion Shutdown: Enabled=$($shutdownIc.Enabled) Estado=$($shutdownIc.PrimaryStatusDescription)"
if (-not $shutdownIc.Enabled) {
    throw "La integracion 'Cierre' esta deshabilitada. No se intenta apagar: un Stop-VM acabaria en apagado forzado."
}

# ---------------------------------------------------------------------------
# 1. Arrancar y esperar latido
# ---------------------------------------------------------------------------
if ($vm.State -ne 'Running') {
    Say 'Arrancando la VM...'
    Start-VM -Name $VmName | Out-Null
} else {
    Say 'La VM ya estaba encendida.'
}

$sw = [Diagnostics.Stopwatch]::StartNew()
$heartbeatOk = $false
while ($sw.Elapsed.TotalSeconds -lt $TimeoutArranqueSeg) {
    Start-Sleep -Seconds 5
    $vmNow = Get-VM -Name $VmName
    $hb = Get-Ic $IC_HEARTBEAT
    if ($vmNow.Heartbeat -like 'Ok*' -or ($hb -and $hb.PrimaryStatusDescription -match '^(OK|Correcto|Normal)$')) {
        Say "Latido OK a los $([int]$sw.Elapsed.TotalSeconds)s."
        $heartbeatOk = $true
        break
    }
    Say "Esperando guest... estado=$($vmNow.State), heartbeat=$($vmNow.Heartbeat), $([int]$sw.Elapsed.TotalSeconds)s"
    if ($vmNow.State -ne 'Running') { throw "La VM cambio a estado '$($vmNow.State)' durante el arranque." }
}
if (-not $heartbeatOk) {
    throw "El guest no reporto latido en $TimeoutArranqueSeg s. Revisa el initramfs/consola antes de probar el apagado."
}

# ---------------------------------------------------------------------------
# 2. Esperar SSH (guest realmente operativo)
# ---------------------------------------------------------------------------
$sshOk = $false
$sw2 = [Diagnostics.Stopwatch]::StartNew()
while ($sw2.Elapsed.TotalSeconds -lt $TimeoutSshSeg) {
    if (Test-NetConnection $DcIp -Port 22 -InformationLevel Quiet -WarningAction SilentlyContinue) {
        Say "SSH ${DcIp}:22 disponible a los $([int]$sw2.Elapsed.TotalSeconds)s."
        $sshOk = $true
        break
    }
    Start-Sleep -Seconds 5
}
if (-not $sshOk) {
    throw "El guest tiene latido pero no responde en ${DcIp}:22 en $TimeoutSshSeg s. No se prueba el apagado."
}

# Revalidar la integracion justo antes de parar (puede tardar en ponerse OK).
$shutdownIc = Get-Ic $IC_SHUTDOWN
$icStatus = [string]$shutdownIc.PrimaryStatusDescription
Say "Shutdown IC antes de parar: Enabled=$($shutdownIc.Enabled) Estado=$icStatus"
if (-not $shutdownIc.Enabled -or $icStatus -match 'Sin contacto|No contact|NoContact') {
    throw "El servicio de cierre no esta operativo ($icStatus). Se aborta para no provocar un apagado forzado."
}

# ---------------------------------------------------------------------------
# 3. Parada graciosa y verificacion por eventos
# ---------------------------------------------------------------------------
Say 'Ejecutando Stop-VM (parada GRACIOSA: sin -Force, sin -TurnOff)...'
$t0 = Get-Date
try {
    Stop-VM -Name $VmName -ErrorAction Stop -Confirm:$false
} catch {
    throw "Stop-VM fallo: $($_.Exception.Message). Revisa la integracion 'Cierre' y el guest."
}
$secs = [math]::Round(((Get-Date) - $t0).TotalSeconds, 1)
$final = (Get-VM -Name $VmName).State
Say "Estado final: $final (tardo $secs s)"

$ok = $true
if ($final -ne 'Off') {
    Write-Warning "FAIL: estado final '$final' (se esperaba 'Off'; 'Saved' seria suspension)."
    $ok = $false
}
if ($secs -gt $TimeoutParadaSeg) {
    Write-Warning "FAIL: la parada tardo $secs s (tope $TimeoutParadaSeg s)."
    $ok = $false
}

# Eventos del Worker posteriores al Stop-VM: 18504 = ordenado, 18502 = forzado.
# 18506 indica que el apagado se *inicio* por el componente de integracion, pero
# 18504 es el que confirma que se cerro con fuerza=false. Puede tardar unos
# segundos en escribirse, asi que se consulta con reintentos.
$eventos = @()
$graceful = $false
$hardOff  = $false
$swEv = [Diagnostics.Stopwatch]::StartNew()
while ($swEv.Elapsed.TotalSeconds -lt 60) {
    try {
        $eventos = Get-WinEvent -LogName 'Microsoft-Windows-Hyper-V-Worker-Admin' -MaxEvents 100 -ErrorAction Stop |
            Where-Object { $_.TimeCreated -ge $t0.AddSeconds(-2) -and $_.Message -like "*$VmName*" -and $_.Id -in 18502, 18504, 18506 }
    } catch {
        $eventos = @()
    }
    $graceful = @($eventos | Where-Object { $_.Id -eq 18504 }).Count -gt 0
    $hardOff  = @($eventos | Where-Object { $_.Id -eq 18502 }).Count -gt 0
    if ($graceful -or $hardOff) { break }
    Start-Sleep -Seconds 3
}

Say ''
Say 'Eventos de apagado posteriores al Stop-VM:'
if ($eventos) {
    $eventos | Sort-Object TimeCreated | Select-Object TimeCreated, Id,
        @{n='Msg'; e={ ($_.Message -replace '\s+', ' ') }} |
        Format-Table -AutoSize -Wrap | Out-String -Width 200 | Write-Output
} else {
    Write-Output '  (ninguno encontrado)'
}

if (-not $graceful) {
    Write-Warning 'FAIL: no hay evento 18504; el apagado no fue ordenado por el servicio de integracion.'
    if ($hardOff) { Write-Warning 'Se detecto 18502: la VM se apago a la fuerza.' }
    $ok = $false
}

Write-Output ''
if ($ok) {
    Write-Output 'RESULTADO: PARADA GRACIOSA CONFIRMADA (evento 18504, estado Off)'
    Write-Output '  AutomaticStopAction=ShutDown -> al apagar el host se pedira al guest'
    Write-Output '  que systemd detenga samba-ad-dc, cierre sam.ldb y desmonte en orden.'
} else {
    Write-Output 'RESULTADO: HAY QUE REVISAR LA PARADA'
}

# ---------------------------------------------------------------------------
# 4. Dejar la VM encendida (solo si todo fue bien)
# ---------------------------------------------------------------------------
if ($LeaveRunning -and $ok) {
    Say 'Volviendo a arrancar la VM...'
    Start-VM -Name $VmName | Out-Null
    $sw3 = [Diagnostics.Stopwatch]::StartNew()
    while ($sw3.Elapsed.TotalSeconds -lt $TimeoutArranqueSeg) {
        Start-Sleep -Seconds 5
        $vm3 = Get-VM -Name $VmName
        if ($vm3.Heartbeat -like 'Ok*') {
            Say "VM encendida y con latido ($([int]$sw3.Elapsed.TotalSeconds)s)."
            break
        }
    }
    $sw4 = [Diagnostics.Stopwatch]::StartNew()
    while ($sw4.Elapsed.TotalSeconds -lt $TimeoutSshSeg) {
        if (Test-NetConnection $DcIp -Port 22 -InformationLevel Quiet -WarningAction SilentlyContinue) {
            Say "SSH ${DcIp}:22 disponible ($([int]$sw4.Elapsed.TotalSeconds)s)."
            break
        }
        Start-Sleep -Seconds 5
    }
}

if (-not $ok) { throw 'La verificacion de parada graciosa no paso.' }
