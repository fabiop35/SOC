# Sube el tiempo maximo que Hyper-V espera el apagado ordenado de cada VM
# durante el apagado del host: 120 s -> 300 s.
# Ruta documentada: HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Virtualization
# Requiere PowerShell elevado.
#Requires -RunAsAdministrator
$ErrorActionPreference = 'Stop'
$out = 'D:\tmp\lab\hyperv\adapted\logs\shutdown-timeout.txt'
$key = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Virtualization'
$name = 'ShutdownTimeout'

Remove-Item $out -ErrorAction SilentlyContinue
"[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Ajustando $name..." | Out-File $out -Encoding utf8

$before = (Get-ItemProperty -Path $key -Name $name -ErrorAction SilentlyContinue).$name
"Antes: $before" | Out-File $out -Append -Encoding utf8

New-ItemProperty -Path $key -Name $name -PropertyType DWord -Value 300 -Force | Out-Null

$after = (Get-ItemProperty -Path $key -Name $name).$name
"Despues: $after" | Out-File $out -Append -Encoding utf8

if ($after -ne 300) { throw "No se pudo aplicar: valor actual $after" }

# Solo informativo: el valor lo lee el servicio vmms al arrancar.
$svc = Get-Service vmms
"Servicio vmms: $($svc.Status) (StartType $($svc.StartType))" | Out-File $out -Append -Encoding utf8
"Nota: el nuevo valor se aplica cuando vmms vuelva a arrancar (siguiente reinicio del host)." |
    Out-File $out -Append -Encoding utf8

"OK" | Out-File $out -Append -Encoding utf8
