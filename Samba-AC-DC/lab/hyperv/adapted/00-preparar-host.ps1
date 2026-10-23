# Adaptado a ESTA maquina (DESKTOP-OIAJKVE):
#   - Host Windows 11 en espanol -> grupo 'Administradores de Hyper-V' (SID S-1-5-32-578)
#   - VDI real: D:\VirtualBox_VMs\samba-dc1\samba-dc1.vdi
#   - VHD destino: D:\HyperV\samba-dc1.vhd
#   - Este host NO tiene Wi-Fi; su NIC fisica es 'Ethernet' (Intel I219-LM)
#
# Uso sin administrador (solo convierte el disco):
#   powershell -ExecutionPolicy Bypass -File .\00-preparar-host.ps1 -ConvertOnly
#
# Uso como administrador (rol, servicios, grupo y disco):
#   powershell -ExecutionPolicy Bypass -File .\00-preparar-host.ps1
param(
    [string]$VmName     = 'samba-dc1',
    [string]$SourceVdi  = 'D:\VirtualBox_VMs\samba-dc1\samba-dc1.vdi',
    [string]$StageDir   = 'D:\HyperV',
    [string]$VhdPath    = 'D:\HyperV\samba-dc1.vhd',
    [string]$VBoxManage = 'C:\Program Files\Oracle\VirtualBox\VBoxManage.exe',
    [switch]$ConvertOnly
)

$ErrorActionPreference = 'Stop'
function Say($m) { Write-Host "[$(Get-Date -Format HH:mm:ss)] $m" }

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)
Say "Sesion elevada: $isAdmin"

# ---------------------------------------------------------------------------
# 1. Rol Hyper-V, servicios y permisos (solo con elevacion y sin -ConvertOnly)
# ---------------------------------------------------------------------------
if ($isAdmin -and -not $ConvertOnly) {
    $feat = Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V-All
    if ($feat.State -ne 'Enabled') {
        Say 'Habilitando Microsoft-Hyper-V-All (requiere reinicio)...'
        Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V-All -All -NoRestart | Out-Null
        Say 'AVISO: reinicia el host antes de continuar.'
    } else {
        Say 'Microsoft-Hyper-V-All ya esta Enabled.'
    }

    foreach ($s in 'vmms', 'hns', 'vmcompute') {
        $svc = Get-Service $s -ErrorAction SilentlyContinue
        if ($svc -and $svc.StartType -ne 'Automatic') {
            Say "Servicio $s -> Automatic"
            Set-Service -Name $s -StartupType Automatic
        }
    }

    # El nombre esta localizado en Windows es: 'Administradores de Hyper-V'.
    # Se resuelve por SID para que funcione en cualquier idioma.
    $grpSid = 'S-1-5-32-578'
    $grp = Get-LocalGroup -SID $grpSid -ErrorAction SilentlyContinue
    if (-not $grp) {
        Say "AVISO: no existe el grupo local con SID $grpSid; se omite."
    } else {
        $me = "$env:COMPUTERNAME\$env:USERNAME"
        $already = Get-LocalGroupMember -Group $grp -ErrorAction SilentlyContinue |
                   Where-Object { $_.Name -ieq $me }
        if ($already) {
            Say "$me ya pertenece a '$($grp.Name)'."
        } else {
            Say "Anadiendo $me a '$($grp.Name)' (SID $grpSid)..."
            Add-LocalGroupMember -Group $grp -Member $me
            Say 'AVISO: cierra sesion y vuelve a entrar para que el grupo tenga efecto.'
        }
    }
} elseif (-not $isAdmin) {
    Say 'Sin elevacion: se omiten rol, servicios y grupo. Solo se prepara el disco.'
}

# ---------------------------------------------------------------------------
# 2. Disco: VDI -> VHD (no destructivo: el VDI se conserva)
# ---------------------------------------------------------------------------
if (-not (Test-Path $StageDir)) {
    New-Item -ItemType Directory -Path $StageDir -Force | Out-Null
}

if (Test-Path $VhdPath) {
    $gb = [math]::Round((Get-Item $VhdPath).Length / 1GB, 2)
    Say "El VHD ya existe: $VhdPath ($gb GB). No se vuelve a convertir."
} else {
    if (-not (Test-Path $SourceVdi)) { throw "No existe el VDI origen: $SourceVdi" }
    if (-not (Test-Path $VBoxManage)) { throw "No existe VBoxManage: $VBoxManage" }

    # Seguridad: la VM de VirtualBox debe estar apagada y sin snapshots.
    $info  = & $VBoxManage showvminfo $VmName --machinereadable
    $state = ($info | Select-String '^VMState="(.+)"$').Matches.Groups[1].Value
    if ($state -and $state -ne 'poweroff') {
        throw "La VM VirtualBox '$VmName' esta en estado '$state'. Apagala antes de convertir."
    }

    $snap = & $VBoxManage snapshot $VmName list
    if ($snap -and ($snap -join ' ') -notmatch 'does not have any snapshots|no tiene') {
        throw "La VM '$VmName' tiene snapshots; clonar el VDI base perderia el estado actual."
    }

    Say 'Convirtiendo VDI -> VHD (puede tardar varios minutos, ~7.4 GB)...'
    $sw = [Diagnostics.Stopwatch]::StartNew()
    & $VBoxManage clonemedium disk $SourceVdi $VhdPath --format VHD
    if ($LASTEXITCODE -ne 0) { throw "VBoxManage clonemedium fallo (exit $LASTEXITCODE)." }
    $sw.Stop()

    $gb = [math]::Round((Get-Item $VhdPath).Length / 1GB, 2)
    Say ("VHD creado: {0} ({1} GB) en {2:N1} s" -f $VhdPath, $gb, $sw.Elapsed.TotalSeconds)
}

Say ''
if ($isAdmin) {
    Say 'Siguiente paso: .\01-crear-vm-samba-dc1.ps1'
} else {
    Say 'Siguiente paso (como Administrador): .\01-crear-vm-samba-dc1.ps1'
}
