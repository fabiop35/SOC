# Adaptado a ESTA maquina (DESKTOP-OIAJKVE).
#   - Conmutador recomendado: EXTERNO sobre 'Ethernet' (host cableado, 192.168.0.114/24).
#     El DC conserva 192.168.0.121/24 y es accesible desde la LAN fisica.
#   - NO se replica el switch interno 192.168.0.160/24 de la guia: esta maquina ya
#     tiene 'Ethernet' en 192.168.0.0/24 y dos interfaces del host en la misma red
#     provocan rutas ambiguas.
#   - Si se pide -SwitchType Internal, se exige otra subred (HostIP 192.168.50.x).
#
# Uso:
#   powershell -ExecutionPolicy Bypass -File .\01-crear-vm-samba-dc1.ps1
#
# Requiere PowerShell ELEVADO.
#Requires -RunAsAdministrator
param(
    [string]$VmName        = 'samba-dc1',
    [string]$StageDir      = 'D:\HyperV',
    [string]$DiskPath      = 'D:\HyperV\samba-dc1.vhd',
    [string]$SwitchName    = 'Lab-External',
    [ValidateSet('External', 'Internal')]
    [string]$SwitchType    = 'External',
    [string]$SwitchAdapter = 'Ethernet',
    [string]$HostIP        = '192.168.50.1',
    [int]$HostPrefixLength = 24,
    [int]$MemoryMB         = 4096,
    [int]$ProcessorCount   = 2,
    [string]$MacAddress    = '08-00-27-7E-8D-F2'
)

$ErrorActionPreference = 'Stop'
function Say($m) { Write-Host "[$(Get-Date -Format HH:mm:ss)] $m" }

Import-Module Hyper-V

if ((Get-Service vmms).Status -ne 'Running') {
    throw 'El servicio vmms no esta corriendo. Reinicia el host y reintenta.'
}
if (-not (Test-Path $DiskPath)) {
    throw "No existe el disco $DiskPath. Ejecuta primero 00-preparar-host.ps1."
}

# ---------------------------------------------------------------------------
# 1. Conmutador
# ---------------------------------------------------------------------------
$switch = Get-VMSwitch -Name $SwitchName -ErrorAction SilentlyContinue
if ($switch) {
    Say "El conmutador '$SwitchName' ya existe (tipo: $($switch.SwitchType))."
    if ($switch.SwitchType -ne $SwitchType) {
        throw "El conmutador existente es '$($switch.SwitchType)' y se pidio '$SwitchType'. No se recrea para no cortar la red; ajustalo en el Administrador de Hyper-V."
    }
} elseif ($SwitchType -eq 'External') {
    $adapter = Get-NetAdapter -Name $SwitchAdapter -ErrorAction SilentlyContinue
    if (-not $adapter) { throw "No existe el adaptador fisico '$SwitchAdapter'." }
    if ($adapter.Status -ne 'Up') { Say "AVISO: '$SwitchAdapter' no esta Up (estado: $($adapter.Status))." }
    Say "Creando conmutador externo '$SwitchName' sobre '$SwitchAdapter' (la red del host se corta unos segundos)..."
    New-VMSwitch -Name $SwitchName -NetAdapterName $SwitchAdapter -AllowManagementOS $true | Out-Null
} else {
    if ($HostIP -like '192.168.0.*') {
        throw "No uses 192.168.0.0/24 en un switch interno: 'Ethernet' ya usa esa red. Usa por ejemplo 192.168.50.1."
    }
    Say "Creando conmutador interno '$SwitchName'..."
    New-VMSwitch -Name $SwitchName -SwitchType Internal | Out-Null
    if (-not (Get-NetIPAddress -InterfaceAlias "vEthernet ($SwitchName)" -AddressFamily IPv4 -ErrorAction SilentlyContinue)) {
        New-NetIPAddress -InterfaceAlias "vEthernet ($SwitchName)" -IPAddress $HostIP `
            -PrefixLength $HostPrefixLength -ErrorAction Stop | Out-Null
        Say "IP del host en vEthernet ($SwitchName): $HostIP/$HostPrefixLength"
    }
}

Get-VMSwitch | Select-Object Name, SwitchType, NetAdapterInterfaceDescription |
    Format-Table -AutoSize | Out-String | Write-Output

# ---------------------------------------------------------------------------
# 2. VM Generacion 1
# ---------------------------------------------------------------------------
if (-not (Test-Path $StageDir)) { New-Item -ItemType Directory -Path $StageDir -Force | Out-Null }

$vm = Get-VM -Name $VmName -ErrorAction SilentlyContinue
if ($vm) {
    Say "La VM '$VmName' ya existe (estado: $($vm.State)); se reconfigura."
} else {
    Say "Creando VM '$VmName' (Generacion 1, $MemoryMB MB, $ProcessorCount vCPU)..."
    $vm = New-VM -Name $VmName -Generation 1 -MemoryStartupBytes ($MemoryMB * 1MB) `
                 -Path $StageDir -NoVHD
}

# Disco en IDE 0:0 (probado: el VHD arranca; SCSI fallaba en la guia).
$drives = @(Get-VMHardDiskDrive -VMName $VmName)
$target = $drives | Where-Object {
    $_.ControllerType -eq 'IDE' -and $_.ControllerNumber -eq 0 -and
    $_.ControllerLocation -eq 0 -and $_.Path -eq $DiskPath
}
if ($target) {
    Say "Disco ya adjuntado en IDE 0:0: $DiskPath"
} else {
    if ($vm.State -ne 'Off') {
        throw "La VM esta en estado '$($vm.State)'. Apagala para mover el disco a IDE 0:0."
    }
    if ($drives.Count -gt 0) { $drives | Remove-VMHardDiskDrive }
    Add-VMHardDiskDrive -VMName $VmName -ControllerType IDE -ControllerNumber 0 `
        -ControllerLocation 0 -Path $DiskPath | Out-Null
    Say "Disco adjuntado en IDE 0:0: $DiskPath"
}

# Adaptador heredado (E1000). Es lo que mantiene 'enp0s3' y el netplan del guest.
$macNorm = ($MacAddress -replace '[-:]', '').ToUpper()
$nic = Get-VMNetworkAdapter -VMName $VmName | Select-Object -First 1
if ($nic -and $nic.IsLegacy) {
    $nicMac = ($nic.MacAddress -replace '[-:]', '').ToUpper()
    if ($nicMac -ne $macNorm -or $nic.SwitchName -ne $SwitchName) {
        Set-VMNetworkAdapter -VMName $VmName -Name $nic.Name `
            -StaticMacAddress $MacAddress -SwitchName $SwitchName | Out-Null
        Say "Adaptador Legacy actualizado (MAC $MacAddress, switch $SwitchName)."
    } else {
        Say "Adaptador Legacy ya correcto (MAC $($nic.MacAddress), switch $($nic.SwitchName))."
    }
} else {
    if ($nic) {
        Remove-VMNetworkAdapter -VMName $VmName -Name $nic.Name
        Say "Adaptador sintetico eliminado (rompia 'enp0s3')."
    }
    # En este modulo -IsLegacy es bool, no switch: hay que pasar $true.
    Add-VMNetworkAdapter -VMName $VmName -Name 'Network Adapter' -IsLegacy $true `
        -SwitchName $SwitchName -StaticMacAddress $MacAddress | Out-Null
    Say "Adaptador Legacy (E1000) creado con MAC $MacAddress en '$SwitchName'."
}

# ---------------------------------------------------------------------------
# 3. Comportamiento como servicio
# ---------------------------------------------------------------------------
Say 'Configurando arranque/parada automatica...'
Set-VM -Name $VmName -AutomaticStartAction Start `
          -AutomaticStopAction ShutDown `
          -AutomaticStartDelay 0 `
          -AutomaticCheckpointsEnabled $false `
          -ProcessorCount $ProcessorCount

$mem = Get-VMMemory -VMName $VmName
if ($mem.DynamicMemoryEnabled -or $mem.Startup -ne ($MemoryMB * 1MB)) {
    if ($vm.State -eq 'Off') {
        Set-VMMemory -VMName $VmName -DynamicMemoryEnabled $false -StartupBytes ($MemoryMB * 1MB)
        Say "RAM estatica: $MemoryMB MB."
    } else {
        Say "AVISO: la VM esta encendida; apagala para aplicar RAM estatica."
    }
} else {
    Say "RAM ya correcta (estatica, $MemoryMB MB)."
}

$bootOrder = @('IDE', 'CD', 'LegacyNetworkAdapter', 'Floppy')
$bios = Get-VMBios -VMName $VmName
if (($bios.StartupOrder -join ',') -ne ($bootOrder -join ',')) {
    if ($vm.State -eq 'Off') {
        Set-VMBios -VMName $VmName -StartupOrder $bootOrder
        Say ("Orden de arranque: " + ($bootOrder -join ', '))
    } else {
        Say 'AVISO: la VM esta encendida; no se cambia el orden de arranque.'
    }
} else {
    Say 'Orden de arranque ya correcto (IDE primero).'
}

# La integracion 'Shutdown' es la que permite parar el guest de forma ordenada.
Get-VMIntegrationService -VMName $VmName | Where-Object { -not $_.Enabled } | ForEach-Object {
    try {
        Enable-VMIntegrationService -VMName $VmName -Name $_.Name
        Say "Integracion habilitada: $($_.Name)"
    } catch {
        Say "AVISO: no se pudo habilitar $($_.Name): $($_.Exception.Message)"
    }
}

# ---------------------------------------------------------------------------
# 4. Resumen
# ---------------------------------------------------------------------------
Write-Output ''
Get-VM -Name $VmName | Select-Object Name, State, Generation,
    AutomaticStartAction, AutomaticStopAction, AutomaticCheckpointsEnabled,
    ProcessorCount | Format-List | Out-String | Write-Output
Get-VMNetworkAdapter -VMName $VmName |
    Select-Object Name, SwitchName, MacAddress, IsLegacy, Connected |
    Format-List | Out-String | Write-Output
Get-VMIntegrationService -VMName $VmName |
    Select-Object Name, Enabled, PrimaryStatusDescription |
    Format-Table -AutoSize | Out-String | Write-Output

Say 'Siguiente paso: .\02-verificar-apagado-graceful.ps1 -LeaveRunning'
