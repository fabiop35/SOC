# Guia completa — replicar `samba-dc1` en Hyper-V

Esta guia documenta **todo lo que se hizo** para mover el DC Samba de VirtualBox a
Hyper-V y dejarlo funcionando como servicio del host (arranque automatico y parada
controlada). Sirve para repetir la configuracion en otra maquina o en otra VM.

> Resumen: VM **Generacion 1**, disco **VHD en IDE 0:0**, adaptador **Legacy (E1000)**,
> conmutador **Internal**, IP estatica del DC `192.168.0.121/24`, host `192.168.0.160/24`,
> `AutomaticStartAction=Start`, `AutomaticStopAction=ShutDown`, RAM estatica 4 GB.

---

## 1. Arquitectura final

| Elemento | Valor |
| :--- | :--- |
| Host | Windows 11, Hyper-V habilitado |
| Conmutador | `Lab-External` — tipo **Internal** |
| Host en el lab | `vEthernet (Lab-External)` = `192.168.0.160/24` (sin gateway) |
| Internet del host | `Wi-Fi` (`192.168.40.x`), independiente del lab |
| VM | `samba-dc1`, Generacion 1 |
| RAM / vCPU | 4096 MB estaticos / 2 vCPU |
| Disco | `D:\HyperV\samba-dc1.vhd` (VHD dinamico, ~7.2 GB; 40 GB virtuales) |
| Controlador del disco | **IDE 0:0** |
| Red de la VM | Adaptador **Legacy (E1000)**, switch `Lab-External` |
| MAC | `08-00-27-7E-8D-F2` (`0800277E8DF2`) |
| Arranque | `IDE, CD, LegacyNetworkAdapter, Floppy` |
| Guest | Ubuntu 26.04.1 LTS, `samba-dc1.soc.smb.local` |
| IP del DC | `192.168.0.121/24` en `enp0s3` |
| Servicio AD | `samba-ad-dc.service` (active/enabled) |
| Parada | `Stop-VM` controlada via integracion `Shutdown` |

El host conserva Internet por Wi-Fi y se comunica con el DC por la red interna
`192.168.0.0/24`. No hay gateway en esa red interna.

---

## 2. Requisitos

- Windows 11 Pro/Enterprise/Education con el rol **Microsoft-Hyper-V-All**.
- PowerShell **elevado** (o pertenencia a `Hyper-V Administrators`).
- Disco de la VM en formato **VHD** o **VHDX** con Ubuntu y Samba AD DC ya instalados.
- Opcional: VirtualBox + `VBoxManage` para reparar el disco del guest antes de pasarlo a Hyper-V (fue necesario en este caso).
- Acceso a la consola del guest o SSH para ajustar netplan/initramfs/Samba.

---

## 3. Variables a cambiar para otra VM

Antes de repetir, define nombres distintos para no chocar con el DC actual:

```powershell
$VmName      = 'samba-dc2'
$StageDir    = 'D:\HyperV'
$SwitchName  = 'Lab-External'
$HostIP      = '192.168.0.160'
$DcIP        = '192.168.0.122'
$MacAddress  = '08-00-27-XX-XX-XX'
$DiskPath    = Join-Path $StageDir "$VmName.vhd"
```

En el guest tambien cambian: hostname, IP, `/etc/hosts`, DNS y, si es otro DC, el procedimiento de union al dominio (ver seccion 11).

---

## 4. Preparar el host (solo la primera vez)

El script `00-preparar-host.ps1` hace esto. Equivalente manual en PowerShell elevado:

```powershell
Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V-All -All -NoRestart
foreach ($s in 'vmms','hns','vmcompute') { Set-Service $s -StartupType Automatic }
bcdedit /set hypervisorlaunchtype auto
Add-LocalGroupMember -Group 'Hyper-V Administrators' -Member $env:USERNAME
Restart-Computer
```

Despues del reinicio, comprueba:

```powershell
Get-Service vmms
Get-VM
```

### Disco: VDI -> VHD (si vienes de VirtualBox)

```powershell
& 'C:\Program Files\Oracle\VirtualBox\VBoxManage.exe' clonemedium disk `
  'D:\VMs\samba-dc1\samba-dc1.vdi' 'D:\HyperV\samba-dc1.vhd' --format VHD
```

El VDI original **no se toca**. En este laboratorio el VHD es el disco activo.

> **VHDX:** `Convert-VHD` genera un VHDX valido, pero en este caso el guest no
> arrancaba con el (dracut no encontraba el UUID raiz). No se volvio a probar tras
> regenerar el initramfs. Si decides usar VHDX, prueba el arranque; si falla,
> usa el VHD o regenera el initramfs (seccion 8).

---

## 5. Decision de red

### Opcion recomendada: Internal (la usada aqui)

No requiere router del laboratorio y **no toca el Wi-Fi del host**:

```powershell
New-VMSwitch -Name Lab-External -SwitchType Internal
New-NetIPAddress -InterfaceAlias 'vEthernet (Lab-External)' `
  -IPAddress 192.168.0.160 -PrefixLength 24
```

El host usara esa IP para hablar con el DC; el Internet sigue saliendo por Wi-Fi.

### Opcion External (solo si hay router del laboratorio)

```powershell
New-VMSwitch -Name Lab-External -NetAdapterName 'Ethernet' -AllowManagementOS $true
```

**No usar `-NetAdapterName 'Wi-Fi'`**: Hyper-V deshabilita TCP/IP en `Wi-Fi` y el host pierde la conexion inalambrica. Ese fue el incidente que se corrigio en este laboratorio.

Para cambiar el tipo desde la GUI: **Hyper-V Manager -> Virtual Switch Manager -> Lab-External -> Internal/External**.

---

## 6. Crear/reconfigurar la VM

### Opcion A: script (recomendado)

```powershell
powershell -ExecutionPolicy Bypass -File D:\tmp\SOC\lab\hyperv\01-crear-vm-samba-dc1.ps1
```

Por defecto usa:

- `-SwitchType Internal`
- disco **VHD** (`D:\HyperV\<VmName>.vhd`)
- **IDE 0:0**
- adaptador Legacy con la MAC indicada
- RAM estatica 4 GB, 2 vCPU
- `AutomaticStartAction=Start`, `AutomaticStopAction=ShutDown`
- checkpoints deshabilitados
- orden de arranque con IDE primero

Es idempotente: si la VM ya existe, solo corrige lo que falte. Si hay que mover el disco, la VM debe estar **apagada**.

### Opcion B: manual

```powershell
$VmName = 'samba-dc1'
$Disk   = 'D:\HyperV\samba-dc1.vhd'

New-VM -Name $VmName -Generation 1 -MemoryStartupBytes 4GB -Path 'D:\HyperV' -NoVHD
Set-VMMemory -VMName $VmName -DynamicMemoryEnabled $false -StartupBytes 4GB
Set-VM -Name $VmName -ProcessorCount 2 `
  -AutomaticStartAction Start -AutomaticStopAction ShutDown `
  -AutomaticCheckpointsEnabled $false

Add-VMHardDiskDrive -VMName $VmName -ControllerType IDE -ControllerNumber 0 `
  -ControllerLocation 0 -Path $Disk

Add-VMNetworkAdapter -VMName $VmName -Name 'Network Adapter' -IsLegacy `
  -SwitchName 'Lab-External' -StaticMacAddress '08-00-27-7E-8D-F2'

Set-VMBios -VMName $VmName -StartupOrder @('IDE','CD','LegacyNetworkAdapter','Floppy')
```

Notas:

- **No adjuntar el disco a SCSI**: en esta VM Gen 1 el guest no arrancaba desde SCSI.
- Si la VM ya tenia el disco en SCSI: apagala, quita el disco y vuelve a agregarlo en
  **IDE 0:0**.
- La MAC se pasa con guiones al cmdlet; `Get-VMNetworkAdapter` la muestra sin guiones.
- `Get-VM` puede mostrar `MemoryStartupBytes` vacio con memoria dinamica;
  usa `Get-VMMemory` para ver el valor real (`Startup`).

---

## 7. Preparar el guest (red y arranque)

Estos pasos se hacen **dentro del guest**, por consola o SSH.

### 7.1 IP estatica con netplan

Comprueba el nombre de la interfaz:

```bash
ip -br link
```

En esta VM es `enp0s3` (por el adaptador E1000). Crea el override:

```bash
sudo tee /etc/netplan/99-static.yaml >/dev/null <<'EOF'
network:
  version: 2
  ethernets:
    enp0s3:
      dhcp4: false
      addresses: [192.168.0.121/24]
EOF
sudo chmod 600 /etc/netplan/99-static.yaml
sudo netplan apply
ip -4 -br a
```

Si el netplan original usa `match`/`set-name`, este archivo se fusiona y conserva
esos valores; solo desactiva DHCP y agrega la IP.

### 7.2 Initramfs generico (si el arranque se queda en dracut)

Sintoma: `dracut-initqueue` espera `/dev/disk/by-uuid/<UUID>` y dice `does not exist`.

```bash
# Ubuntu con dracut (fue el caso de esta VM)
sudo dracut -f -N --regenerate-all
lsinitramfs /boot/initrd.img-$(uname -r) | grep -E 'ahci|ata_piix|libata|sd_mod|e1000'

# Ubuntu con initramfs-tools
sudo update-initramfs -u -k all
```

Verifica tambien que el UUID de `/etc/fstab` y el de GRUB coincidan:

```bash
findmnt -no UUID /
grep -m1 vmlinuz /boot/grub/grub.cfg
```

### 7.3 Hostname y Samba

En esta VM ya estaba configurado:

```bash
hostnamectl
systemctl is-enabled samba-ad-dc
systemctl is-active samba-ad-dc
```

Si es una VM nueva, cambia hostname/IP **antes** de arrancar Samba y ajusta `/etc/hosts` y DNS. Para otro DC, no clones la identidad (ver seccion 11).

---

## 8. Pasar el disco a Hyper-V y arrancar

Si reparaste el disco en VirtualBox:

1. Apaga el guest (`poweroff`).
2. En VirtualBox, desconecta el disco de la VM temporal y desregistrala. **No borres el VHD.**
3. En Hyper-V, adjunta el VHD en **IDE 0:0** (script o GUI).
4. Arranca:

```powershell
Start-VM -Name samba-dc1
Get-VM samba-dc1 | Select-Object Name,State,Heartbeat
```

Comprueba desde el host:

```powershell
ping 192.168.0.121
Test-NetConnection 192.168.0.121 -Port 22
ssh sysadmin@192.168.0.121 "hostname; ip -4 -br a; systemctl is-active samba-ad-dc"
```

Credenciales de laboratorio: `sysadmin` / `sysadmin**` (sudo usa la misma).

Si no hay SSH, usa la consola: **Hyper-V Manager -> Connect** o
`vmconnect.exe localhost samba-dc1`.

---

## 9. Integraciones y parada graciosa

Comprueba las integraciones:

```powershell
Get-VMIntegrationService -VMName samba-dc1 |
  Select-Object Name,Enabled,PrimaryStatusDescription
```

Debe verse `Shutdown = OK` (ademas de `Heartbeat`, `Time Synchronization`, `VSS`).
Si `Shutdown` no responde, instala las integraciones Linux dentro del guest:

```bash
sudo apt update
sudo apt install linux-tools-$(uname -r) linux-cloud-tools-$(uname -r)   # o hyperv-daemons
sudo systemctl enable hv_vss_daemon
```

Prueba real de parada:

```powershell
powershell -ExecutionPolicy Bypass -File D:\tmp\SOC\lab\hyperv\02-verificar-apagado-graceful.ps1
```

Resultado esperado: `Stop-VM` termina en pocos segundos, la VM queda **Off** (no
`Saved`) y el evento de Hyper-V indica `shut down using the Shutdown Integration`.
El script **deja la VM apagada**; vuelve a encenderla con:

```powershell
Start-VM -Name samba-dc1
```

Semantica de arranque:

- `AutomaticStartAction = Start`: arranca siempre al iniciar el host.
- `StartIfPreviouslyRunning`: arranca solo si estaba encendida al apagar el host.
- `AutomaticStopAction = ShutDown`: pide apagado ordenado al guest.

---

## 10. Cambiar la configuracion con GUI

Herramienta: **Hyper-V Manager** (`Win+R` -> `virtmgmt.msc`).

1. Selecciona `samba-dc1` -> clic derecho -> **Settings**.
2. Categorias:
   - **Memory**: 4096 MB, Dynamic Memory **off**.
   - **Processor**: 2 vCPU.
   - **IDE 0:0**: `D:\HyperV\samba-dc1.vhd`.
   - **Network Adapter**: Legacy, switch `Lab-External`, MAC `0800277E8DF2`.
   - **BIOS**: boot order `IDE, CD, Legacy Network Adapter, Floppy`.
   - **Management**: Automatic Start / Automatic Stop / checkpoints.
3. Algunos cambios exigen la VM **apagada**: clic derecho -> **Shut Down**
   (no usar *Turn Off*), editar y luego **Start**.

Conmutador: **Virtual Switch Manager** (panel derecho) -> `Lab-External` -> tipo
`Internal`/`External`.

IP del host en el switch interno: **Settings -> Network & Internet -> Advanced network
settings -> vEthernet (Lab-External) -> Edit IP assignment** (o `ncpa.cpl`).

Dentro del guest no hay escritorio grafico (Ubuntu Server): usa **Connect** para la
consola de texto o SSH para editar netplan/Samba.

---

## 11. Clonar para otra maquina o VM

### 11.1 Otra VM con la misma funcion (mismo DC)

**No copies el disco de un DC y lo arranques con el mismo hostname/IP.** Un DC Samba
tiene identidad propia (SID, base `sam.ldb`, DNS, replicacion). Un clon crudo produce
conflictos.

Para un **nuevo DC** del mismo dominio:

1. Crea una VM nueva con disco nuevo y una IP libre (ej. `192.168.0.122`).
2. Instala Ubuntu + Samba AD DC (o parte de una imagen limpia, no del DC actual).
3. Configura hostname, IP, DNS y `/etc/hosts`.
4. Une el equipo al dominio:

```bash
sudo samba-tool domain join soc.smb.local DC -U Administrator
```

5. Ajusta DNS/replicacion y verifica con `samba-tool drs showrepl`.

### 11.2 Otro servidor/clon sin rol de DC

Si solo quieres otra maquina con el mismo software:

1. Clona el disco y cambia: nombre de VM, ruta del disco y **MAC**.
2. Dentro del guest: hostname, IP, `/etc/machine-id`, claves SSH del host y
   `/etc/hosts`.
3. Si el software usa identidad de Samba/AD, elimina o reconfigura esa identidad.
4. Ajusta el netplan a la nueva IP.

### 11.3 Cambios de infraestructura

- Nuevo host: repite secciones 4, 5 y 6.
- Nuevo switch: crea `Lab-External` (Internal) y asigna al host una IP libre del
  mismo `/24`.
- Nueva MAC: `Set-VMNetworkAdapter -VMName <vm> -StaticMacAddress <mac>`.
- Nuevo disco: adjunta en **IDE 0:0**; no en SCSI.

---

## 12. Checklist de verificacion

| Comprobacion | Comando | Esperado |
| :--- | :--- | :--- |
| VM encendida | `Get-VM samba-dc1` | `Running` |
| Latido | `Get-VM samba-dc1` | `Heartbeat = Ok...` |
| IP del DC | `ssh ... "ip -4 -br a"` | `192.168.0.121/24` |
| Servicio AD | `ssh ... "systemctl is-active samba-ad-dc"` | `active` |
| Ping desde host | `ping 192.168.0.121` | responde |
| SSH | `Test-NetConnection 192.168.0.121 -Port 22` | `True` |
| Integracion Shutdown | `Get-VMIntegrationService` | `OK` |
| Parada graciosa | `02-verificar-apagado-graceful.ps1` | `Off` en pocos segundos |
| Internet del host | `Test-NetConnection 8.8.8.8 -Port 53` | `True` |
| Wi-Fi del host | `Get-NetAdapter Wi-Fi` | `Up` |

---

## 13. Problemas conocidos y solucion

| Sintoma | Causa | Solucion |
| :--- | :--- | :--- |
| "Boot failure" / no arranca | disco en SCSI | mover a **IDE 0:0** y orden IDE primero |
| dracut no encuentra el UUID raiz | initramfs hostonly / drivers faltantes | `dracut -f -N --regenerate-all` |
| VHDX no arranca | conversion / initramfs | usar VHD o regenerar initramfs y reprobar |
| El host pierde Wi-Fi | switch externo sobre `Wi-Fi` | recrear `Lab-External` como **Internal** |
| El guest no tiene IP | netplan con DHCP o interfaz distinta | crear `99-static.yaml` con `enp0s3` correcto |
| No aparece en `services.msc` | es una VM, no un servicio Windows | el servicio es `vmms`; la VM arranca por Hyper-V |
| RAM aparece 0 / dinamica | `Get-VM` con memoria dinamica | `Set-VMMemory -DynamicMemoryEnabled $false -StartupBytes 4GB` |
| `Stop-VM` pide confirmacion | integracion `Shutdown` no disponible | instalar integraciones Linux; `AutomaticStopAction=ShutDown` |
| SSH rechazado | IP distinta o sshd caido | revisar `ip a`, `systemctl status ssh` |
| Clon de DC con conflictos | identidad duplicada | no clonar DC; usar `samba-tool domain join` |
| `02` deja la VM apagada | comportamiento esperado | `Start-VM -Name samba-dc1` |

---

## 14. Archivos y comandos de referencia

| Archivo | Uso |
| :--- | :--- |
| `lab/hyperv/00-preparar-host.ps1` | habilita Hyper-V, servicios, permisos y VDI->VHD |
| `lab/hyperv/01-crear-vm-samba-dc1.ps1` | crea/reconfigura switch, VM, disco IDE 0:0, NIC, RAM y arranque |
| `lab/hyperv/02-verificar-apagado-graceful.ps1` | prueba real de parada controlada |
| `lab/hyperv/REANUDAR.md` | estado y pasos para retomar el laboratorio |
| `lab/hyperv/GUIA-REPLICAR-SAMBA-DC-HYPERV.md` | esta guia |

Comandos utiles:

```powershell
Get-VM samba-dc1
Get-VMHardDiskDrive -VMName samba-dc1
Get-VMNetworkAdapter -VMName samba-dc1
Get-VMBios -VMName samba-dc1
Get-VMMemory -VMName samba-dc1
Get-VMIntegrationService -VMName samba-dc1
Get-VMSwitch
```

Datos del laboratorio:

- DC: `samba-dc1.soc.smb.local` / `192.168.0.121/24`
- Host en el lab: `192.168.0.160/24`
- Credenciales: `sysadmin` / `sysadmin**`; `Administrator` / `Sysadmin**`;
  `soc-admin` / `Sysadmin**`; `invitado01` / `Invitado012026`
- Disco activo: `D:\HyperV\samba-dc1.vhd`
- VHDX de respaldo sin usar: `D:\HyperV\samba-dc1.vhdx`
- VDI original intacto: `D:\VMs\samba-dc1\samba-dc1.vdi`

> Nota de seguridad: esta guia contiene credenciales de laboratorio. No la publiques
> en un repositorio publico sin sanitizarlas.
