# Requiere PowerShell ELEVADO (Administrador). Ejecutar ANTES de reiniciar el host.
# 1) Habilita el rol Hyper-V y deja los servicios en Automatic
# 2) Convierte el disco VDI de VirtualBox a VHD (intermedio para VHDX)
# Uso:  powershell -ExecutionPolicy Bypass -File lab\hyperv\00-preparar-host.ps1
param(
    [string]$VmName        = 'samba-dc1',
    [string]$SourceVdi     = 'D:\VMs\samba-dc1\samba-dc1.vdi',
    [string]$StageDir      = 'D:\HyperV',
    [string]$VBoxManage    = 'C:\Program Files\Oracle\VirtualBox\VBoxManage.exe'
)

$ErrorActionPreference = 'Stop'
function Say($m) { Write-Host "[$(Get-Date -Format HH:mm:ss)] $m" }

# --- 1. Rol Hyper-V -------------------------------------------------------
$feat = Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V-All
if ($feat.State -ne 'Enabled') {
    Say 'Habilitando Microsoft-Hyper-V-All (requiere reinicio)...'
    Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V-All -All -NoRestart | Out-Null
} else {
    Say 'Microsoft-Hyper-V-All ya estaba Enabled.'
}
foreach ($s in 'vmms', 'hns', 'vmcompute') {
    $svc = Get-Service $s -ErrorAction SilentlyContinue
    if ($svc -and $svc.StartType -ne 'Automatic') {
        Say "Setting $s -> Automatic"
        Set-Service -Name $s -StartupType Automatic
    }
}
Say "hypervisorlaunchtype = $((bcdedit /enum '{current}' | Select-String 'hypervisorlaunchtype') -replace '.*\s(\w+)$','$1')"

# --- 1b. Permisos de Hyper-V sin UAC ---------------------------------------
# Sin pertenencia a 'Hyper-V Administrators', los cmdlets de Hyper-V fallan con
# "You do not have the required permission..." aunque la sesion no este elevada.
$grp = 'Hyper-V Administrators'
if (-not (Get-LocalGroupMember -Group $grp -ErrorAction SilentlyContinue |
          Where-Object { $_.Name -like "*\$($env:USERNAME)" })) {
    Say "Anadiendo $env:USERNAME al grupo local '$grp' (para no pedir UAC en cada paso)."
    Add-LocalGroupMember -Group $grp -Member $env:USERNAME
} else {
    Say "$env:USERNAME ya pertenece a '$grp'."
}

# --- 2. Disco: VDI -> VHD -------------------------------------------------
if (-not (Test-Path $StageDir)) { New-Item -ItemType Directory -Path $StageDir | Out-Null }
$vhd = Join-Path $StageDir "$VmName.vhd"
if (Test-Path $vhd) {
    Say "VHD ya existe: $vhd"
} else {
    if (-not (Test-Path $SourceVdi)) { throw "No existe el disco origen: $SourceVdi" }
    Say "Convirtiendo VDI -> VHD ($SourceVdi -> $vhd). Puede tardar varios minutos..."
    & $VBoxManage clonemedium disk $SourceVdi $vhd --format VHD
    if ($LASTEXITCODE -ne 0) { throw 'VBoxManage clonemedium falló' }
}
Say ("VHD: {0} ({1:N2} GB)" -f $vhd, ((Get-Item $vhd).Length / 1GB))

Write-Host ''
Write-Host '== SIGUIENTE PASO: REINICIA EL HOST (para que cargue el hypervisor) y luego ejecuta ==' -ForegroundColor Yellow
Write-Host '   powershell -ExecutionPolicy Bypass -File lab\hyperv\01-crear-vm-samba-dc1.ps1' -ForegroundColor Yellow
