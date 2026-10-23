# Requiere PowerShell ELEVADO (o pertenencia al grupo local 'Hyper-V Administrators').
# Crea el conmutador, crea/reconfigura la VM Gen 1 y deja el disco en IDE 0:0
# (configuracion probada: el disco VHD arranca; el VHDX convertido no arrancaba).
#
# Uso:  powershell -ExecutionPolicy Bypass -File lab\hyperv\01-crear-vm-samba-dc1.ps1
#
# NOTA (host con modulo Hyper-V 2.0.0.0, el unico disponible en Windows 11 cliente):
#   - No existe 'Set-VMNetworkAdapter -VirtualNetworkAdapterType' ni '-MacAddress'.
#     El adaptador E1000 se crea con 'Add-VMNetworkAdapter -IsLegacy' y la MAC
#     se fija con '-StaticMacAddress'.
#   - 'Set-VM' no tiene '-StartupDelay' (es '-AutomaticStartDelay').
#   - '-CheckpointType Standard' NO es valido en Generacion 1 (solo 'Production').
param(
    [string]$VmName          = 'samba-dc1',
    [string]$StageDir        = 'D:\HyperV',
    [string]$SwitchName      = 'Lab-External',
    # 'Internal' = red aislada host<->DC (recomendado si no hay router del lab).
    # 'External' = enlaza el conmutador a un adaptador fisico del host.
    [ValidateSet('Internal', 'External')]
    [string]$SwitchType      = 'Internal',
    # Solo se usa con -SwitchType External. 'Ethernet' = red del laboratorio.
    # NO usar 'Wi-Fi' salvo que se acepte que el host pierda/degrada su Wi-Fi.
    [string]$SwitchAdapter   = 'Ethernet',
    # IP del host en el conmutador interno (solo -SwitchType Internal).
    [string]$HostIP          = '192.168.0.160',
    [int]$HostPrefixLength   = 24,
    [int]$MemoryMB           = 4096,
    [int]$ProcessorCount     = 2,
    [string]$MacAddress      = '08-00-27-7E-8D-F2'
)

$ErrorActionPreference = 'Continue'
function Say($m) { Write-Output "[$(Get-Date -Format HH:mm:ss)] $m" }
function Try-Op($label, $block) {
    try { & $block; Say "OK: $label" }
    catch { Say "ERROR $label : $($_.Exception.Message)" }
}

Import-Module Hyper-V
if ((Get-Service vmms).Status -ne 'Running') { throw 'El servicio vmms no esta corriendo: reinicia el host.' }

$vhd  = Join-Path $StageDir "$VmName.vhd"
$vhdx = Join-Path $StageDir "$VmName.vhdx"

# --- 1. Elegir disco -------------------------------------------------------
# Preferimos el VHD: es el que arranca en Hyper-V. El VHDX convertido fallaba
# al montar la raiz (dracut no encontraba el UUID) y queda solo como respaldo.
if (Test-Path $vhd) {
    $diskPath = $vhd
} elseif (Test-Path $vhdx) {
    $diskPath = $vhdx
    Say "AVISO: no existe $vhd; se usara el VHDX $vhdx (puede no arrancar)."
} else {
    throw "No existe el disco: ni $vhd ni $vhdx"
}
Get-VHD -Path $diskPath | Select-Object Path, VhdFormat, VhdType,
    @{n='SizeGB';e={[math]::Round($_.Size/1GB,2)}},
    @{n='FileGB';e={[math]::Round($_.FileSize/1GB,2)}} |
    Format-List | Out-String | Write-Output

# --- 2. Conmutador ---------------------------------------------------------
$sw = Get-VMSwitch -Name $SwitchName -ErrorAction SilentlyContinue
if ($sw) {
    Say "Conmutador '$SwitchName' ya existe (tipo: $($sw.SwitchType))."
    if ($sw.SwitchType -ne $SwitchType) {
        Say "AVISO: el conmutador existente es '$($sw.SwitchType)' y se pidio '$SwitchType'."
        Say "       No se recrea automaticamente para no cortar la red de la VM."
    }
} elseif ($SwitchType -eq 'Internal') {
    Say "Creando conmutador interno '$SwitchName'..."
    New-VMSwitch -Name $SwitchName -SwitchType Internal | Out-Null
} else {
    Say "Creando conmutador externo '$SwitchName' sobre '$SwitchAdapter'..."
    try {
        New-VMSwitch -Name $SwitchName -NetAdapterName $SwitchAdapter -AllowManagementOS $true | Out-Null
    } catch {
        Write-Output "No se pudo crear el conmutador sobre '$SwitchAdapter': $($_.Exception.Message)"
        Write-Output 'Opciones:'
        Write-Output "  1) Conectar el cable de red del host al switch del laboratorio y reintentar."
        Write-Output "  2) Red aislada:  -SwitchType Internal  (recomendado si no hay router del lab)"
        throw
    }
}
Get-VMSwitch | Select-Object Name, SwitchType, NetAdapterInterfaceDescription |
    Format-Table -AutoSize | Out-String | Write-Output

# IP del host en el conmutador interno (el DC usa 192.168.0.121/24).
if ($SwitchType -eq 'Internal') {
    $ifAlias = "vEthernet ($SwitchName)"
    if (-not (Get-NetIPAddress -InterfaceAlias $ifAlias -AddressFamily IPv4 -ErrorAction SilentlyContinue)) {
        Try-Op "IP del host $HostIP/$HostPrefixLength en $ifAlias" {
            New-NetIPAddress -InterfaceAlias $ifAlias -IPAddress $HostIP `
                -PrefixLength $HostPrefixLength -ErrorAction Stop | Out-Null
        }
    } else {
        Say "El host ya tiene IPv4 en $ifAlias."
    }
}

# --- 3. Crear la VM --------------------------------------------------------
if (Get-VM -Name $VmName -ErrorAction SilentlyContinue) {
    Say "La VM '$VmName' ya existe; se reconfigura."
    $vm = Get-VM -Name $VmName
} else {
    Say "Creando VM '$VmName' (Generacion 1, $($MemoryMB)MB, $ProcessorCount vCPU)..."
    $vm = New-VM -Name $VmName -Generation 1 -MemoryStartupBytes ($MemoryMB * 1MB) `
                  -Path $StageDir -NoVHD -Force
}

# Disco en IDE 0:0. El VHDX convertido fallaba en dracut; el VHD si arranca.
$drives = @(Get-VMHardDiskDrive -VM $vm)
$target = $drives | Where-Object {
    $_.ControllerType -eq 'IDE' -and $_.ControllerNumber -eq 0 -and
    $_.ControllerLocation -eq 0 -and $_.Path -eq $diskPath
}
if ($target) {
    Say "Disco ya adjuntado en IDE 0:0: $diskPath"
} else {
    if ($vm.State -ne 'Off') {
        throw "La VM esta en estado '$($vm.State)'. Apagala para mover el disco a IDE 0:0."
    }
    if ($drives.Count -gt 0) { $drives | Remove-VMHardDiskDrive }
    Add-VMHardDiskDrive -VM $vm -ControllerType IDE -ControllerNumber 0 `
        -ControllerLocation 0 -Path $diskPath | Out-Null
    Say "Disco adjuntado en IDE 0:0: $diskPath"
}

# Red: adaptador heredado (E1000) para conservar el perfil de guest y la MAC original.
# En este modulo no se puede 'cambiar el tipo' de un adaptador existente: hay que
# borrarlo y volverlo a crear con -IsLegacy.
$macNorm = ($MacAddress -replace '[-:]', '')
$nic = Get-VMNetworkAdapter -VM $vm | Select-Object -First 1
if ($nic -and $nic.IsLegacy) {
    if (($nic.MacAddress -replace '[-:]', '') -ne $macNorm -or $nic.SwitchName -ne $SwitchName) {
        Try-Op 'MAC/switch del adaptador Legacy' {
            Set-VMNetworkAdapter -VMName $VmName -Name $nic.Name `
                -StaticMacAddress $MacAddress -SwitchName $SwitchName -ErrorAction Stop
        }
    } else {
        Say "Adaptador Legacy ya correcto (MAC $($nic.MacAddress), switch $($nic.SwitchName))."
    }
} else {
    if ($nic) {
        Try-Op 'borrar adaptador sintetico' { Remove-VMNetworkAdapter -VMName $VmName -Name $nic.Name -ErrorAction Stop }
    }
    Try-Op 'crear adaptador Legacy (E1000) con MAC original' {
        Add-VMNetworkAdapter -VMName $VmName -Name 'Network Adapter' -IsLegacy `
            -SwitchName $SwitchName -StaticMacAddress $MacAddress -ErrorAction Stop
    }
}

# --- 4. Comportamiento como servicio --------------------------------------
Say 'Configurando arranque/parada automatica...'
Try-Op 'Start / ShutDown / sin checkpoints / vCPU' {
    Set-VM -Name $VmName -AutomaticStartAction Start `
              -AutomaticStopAction ShutDown `
              -AutomaticStartDelay 0 `
              -AutomaticCheckpointsEnabled $false `
              -ProcessorCount $ProcessorCount -ErrorAction Stop
}
# RAM estatica (el DC es un servicio: no conviene que Hyper-V le quite memoria).
$mem = Get-VMMemory -VMName $VmName
if ($mem.DynamicMemoryEnabled -or $mem.Startup -ne ($MemoryMB * 1MB)) {
    if ((Get-VM -Name $VmName).State -eq 'Off') {
        Try-Op 'RAM estatica (sin memoria dinamica)' {
            Set-VMMemory -VMName $VmName -DynamicMemoryEnabled $false `
                -StartupBytes ($MemoryMB * 1MB) -ErrorAction Stop
        }
    } else {
        Say 'AVISO: la VM esta encendida; apagala para aplicar RAM estatica.'
    }
} else {
    Say "RAM ya correcta (estatica, $($MemoryMB) MB)."
}

# Orden de arranque Gen 1: el disco esta en IDE 0:0.
$bootOrder = @('IDE', 'CD', 'LegacyNetworkAdapter', 'Floppy')
$bios = Get-VMBios -VMName $VmName
if (($bios.StartupOrder -join ',') -ne ($bootOrder -join ',')) {
    if ((Get-VM -Name $VmName).State -eq 'Off') {
        Try-Op 'orden de arranque BIOS (IDE primero)' {
            Set-VMBios -VMName $VmName -StartupOrder $bootOrder -ErrorAction Stop
        }
    } else {
        Say 'AVISO: la VM esta encendida; no se cambia el orden de arranque.'
    }
} else {
    Say 'Orden de arranque BIOS ya correcto (IDE primero).'
}

# Integraciones: "Shutdown" es la que permite la parada controlada del guest
$vm = Get-VM -Name $VmName
Get-VMIntegrationService -VM $vm | Where-Object { -not $_.Enabled } | ForEach-Object {
    try { Enable-VMIntegrationService -VM $vm -Name $_.Name }
    catch { Say "  integracion $($_.Name) no habilitable: $($_.Exception.Message)" }
}
Get-VMIntegrationService -VM $vm | Select-Object Name, Enabled, PrimaryStatusDescription |
    Format-Table -AutoSize | Out-String | Write-Output

Write-Output ''
Get-VM -Name $VmName | Select-Object Name, State, Generation, `
    @{n='AutomaticStartAction';e={$_.AutomaticStartAction}}, `
    @{n='AutomaticStopAction';e={$_.AutomaticStopAction}}, `
    @{n='AutomaticCheckpoints';e={$_.AutomaticCheckpointsEnabled}}, `
    @{n='RAMMB';e={[math]::Round((Get-VMMemory -VMName $VmName).Startup/1MB)}}, `
    @{n='vCPU';e={$_.ProcessorCount}} | Format-List | Out-String | Write-Output
Get-VMNetworkAdapter -VM $vm | Select-Object Name, SwitchName, MacAddress, IsLegacy, Connected |
    Format-List | Out-String | Write-Output
Get-VMBios -VM $vm | Select-Object StartupOrder | Format-List | Out-String | Write-Output

Write-Output '== VERIFICACION DE PARADA GRACIOSA =='
Write-Output '   powershell -ExecutionPolicy Bypass -File lab\hyperv\02-verificar-apagado-graceful.ps1'
Write-Output ''
Write-Output 'Netplan del guest (IP estatica del DC): /etc/netplan/99-static.yaml'
Write-Output '  network:'
Write-Output '    version: 2'
Write-Output '    ethernets:'
Write-Output '      enp0s3:'
Write-Output '        dhcp4: false'
Write-Output '        addresses: [192.168.0.121/24]'
