# Diagnostico de solo lectura: estado de la VM, integraciones y captura de consola.
# Uso (elevado):
#   powershell -ExecutionPolicy Bypass -File .\diagnostico.ps1
#   powershell -ExecutionPolicy Bypass -File .\diagnostico.ps1 -StopVm   # apagado forzado al final
#Requires -RunAsAdministrator
param(
    [string]$VmName = 'samba-dc1',
    [string]$OutDir = 'D:\tmp\lab\hyperv\adapted\logs',
    [int]$Width = 1024,
    [int]$Height = 768,
    [switch]$StopVm
)

$ErrorActionPreference = 'Stop'
function Say($m) { Write-Host "[$(Get-Date -Format HH:mm:ss)] $m" }

if (-not (Test-Path $OutDir)) { New-Item -ItemType Directory -Path $OutDir -Force | Out-Null }
$log = Join-Path $OutDir ("diagnostico-{0:yyyyMMdd-HHmmss}.log" -f (Get-Date))
Start-Transcript -Path $log -Force | Out-Null

Import-Module Hyper-V

$vm = Get-VM -Name $VmName
Say "VM: $($vm.Name) | State=$($vm.State) | Uptime=$($vm.Uptime) | Status=$($vm.Status)"
Say "AutomaticStartAction=$($vm.AutomaticStartAction) AutomaticStopAction=$($vm.AutomaticStopAction)"
Say "Heartbeat=$($vm.Heartbeat) IntegrationServicesState=$($vm.IntegrationServicesState)"

Say ''
Say 'Integraciones:'
Get-VMIntegrationService -VMName $VmName |
    Select-Object Name, Enabled, PrimaryStatusDescription, SecondaryStatusDescription |
    Format-Table -AutoSize | Out-String -Width 200 | Write-Output

Say 'Red:'
Get-VMNetworkAdapter -VMName $VmName |
    Select-Object Name, SwitchName, MacAddress, IsLegacy, Connected, Status |
    Format-Table -AutoSize | Out-String -Width 200 | Write-Output

# ---------------------------------------------------------------------------
# Captura de consola (thumbnail WMI, RGB565)
# ---------------------------------------------------------------------------
try {
    $cs = Get-CimInstance -Namespace root\virtualization\v2 -ClassName Msvm_ComputerSystem |
          Where-Object { $_.ElementName -eq $VmName }
    $svc = Get-CimInstance -Namespace root\virtualization\v2 -ClassName Msvm_VirtualSystemManagementService

    $res = Invoke-CimMethod -InputObject $svc -MethodName GetVirtualSystemThumbnailImage -Arguments @{
        TargetSystem = [CimInstance]$cs
        WidthPixels  = [uint16]$Width
        HeightPixels = [uint16]$Height
    }

    if ($res.ReturnValue -ne 0) { throw "GetVirtualSystemThumbnailImage ReturnValue=$($res.ReturnValue)" }

    $bytes = [byte[]]$res.ImageData
    Say "Thumbnail: $($bytes.Length) bytes para ${Width}x${Height}"

    Add-Type -AssemblyName System.Drawing
    $bmp = $null
    if ($bytes.Length -eq ($Width * $Height * 2)) {
        $bmp = New-Object System.Drawing.Bitmap($Width, $Height, [System.Drawing.Imaging.PixelFormat]::Format16bppRgb565)
    } elseif ($bytes.Length -eq ($Width * $Height * 4)) {
        $bmp = New-Object System.Drawing.Bitmap($Width, $Height, [System.Drawing.Imaging.PixelFormat]::Format32bppRgb)
    } else {
        throw "Tamano de thumbnail inesperado: $($bytes.Length)"
    }

    $rect = New-Object System.Drawing.Rectangle(0, 0, $Width, $Height)
    $data = $bmp.LockBits($rect, [System.Drawing.Imaging.ImageLockMode]::WriteOnly, $bmp.PixelFormat)
    try {
        [System.Runtime.InteropServices.Marshal]::Copy($bytes, 0, $data.Scan0, $bytes.Length)
    } finally {
        $bmp.UnlockBits($data)
    }

    $png = Join-Path $OutDir ("consola-{0:yyyyMMdd-HHmmss}.png" -f (Get-Date))
    $bmp.Save($png, [System.Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose()
    Say "Captura guardada: $png"
} catch {
    Say "No se pudo capturar la consola: $($_.Exception.Message)"
}

# ---------------------------------------------------------------------------
# Eventos de apagado/arranque
# ---------------------------------------------------------------------------
Say ''
Say 'Ultimos eventos de Hyper-V de esta VM:'
Get-WinEvent -LogName 'Microsoft-Windows-Hyper-V-Worker-Admin' -MaxEvents 40 -ErrorAction SilentlyContinue |
    Where-Object { $_.Message -like "*$VmName*" } |
    Select-Object TimeCreated, Id, @{n='Msg';e={($_.Message -replace '\s+',' ')}} |
    Format-Table -AutoSize -Wrap | Out-String -Width 200 | Write-Output

if ($StopVm -and $vm.State -ne 'Off') {
    Say 'Apagando la VM a la fuerza (solo si el guest no responde)...'
    Stop-VM -Name $VmName -TurnOff -Force
    Say "Estado final: $((Get-VM -Name $VmName).State)"
}

Stop-Transcript | Out-Null
