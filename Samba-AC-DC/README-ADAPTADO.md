# Migracion `samba-dc1` de VirtualBox a Hyper-V (adaptado a DESKTOP-OIAJKVE)

Este directorio contiene la version **adaptada y ya ejecutada** de
`D:\tmp\GUIA-REPLICAR-SAMBA-DC-HYPERV.md`. La guia original se uso como
referencia, pero varios valores no aplicaban a esta maquina; aqui quedan los
valores reales, la causa raiz del primer fallo y los comandos de reparacion.

## Resultado final

- VM Hyper-V `samba-dc1` en estado **Running**.
- Generacion 1, 4096 MB estaticos, 2 vCPU.
- Disco `D:\HyperV\samba-dc1.vhd` en **IDE 0:0**.
- Adaptador **heredado (E1000)** con MAC fija `08-00-27-7E-8D-F2`.
- Conmutador **externo** `Lab-External` sobre la NIC fisica `Ethernet`.
- Guest en `192.168.0.121/24` (interfaz `enp0s3`), SSH en el puerto 22.
- `samba-ad-dc.service` **active** y **enabled**.
- `AutomaticStartAction=Start`, `AutomaticStopAction=ShutDown`, checkpoints
  deshabilitados, todas las integraciones habilitadas.
- Parada ordenada verificada: estado final **Off** en ~3.7 s, evento Hyper-V
  **18504** (`fuerza = false`) y en el guest
  `hv_utils: Shutdown request received - graceful shutdown initiated`.
- `ShutdownTimeout` de Hyper-V ajustado a **300 s** (antes 120 s): margen
  maximo por VM durante el apagado del host antes de un apagado forzado.

## Diferencias respecto a la guia original

| Tema | Guia original | Esta maquina |
|---|---|---|
| Conmutador | Interno `192.168.0.160/24` | Externo `Lab-External` sobre `Ethernet` |
| IP del host | `192.168.0.160` en switch interno | `192.168.0.114/24` en `vEthernet (Lab-External)` (DHCP) |
| IP del DC | `192.168.0.121/24` | Igual: `192.168.0.121/24` |
| Grupo Hyper-V | `Hyper-V Administrators` | `Administradores de Hyper-V` (SID `S-1-5-32-578`) |
| `Add-VMNetworkAdapter -IsLegacy` | uso como switch | en este modulo exige `-IsLegacy $true` |
| Nombres de integraciones | `Shutdown`, `Heartbeat` | localizados: `Cierre`, `Latido` (usar GUID) |

### Por que conmutador externo y no interno

La guia crea un switch interno con el host en `192.168.0.160/24`. En esta
maquina la NIC `Ethernet` ya esta en `192.168.0.0/24` (LAN real, puerta de
enlace `192.168.0.1`). Poner otra interfaz del host en la misma subred genera
rutas ambiguas. El switch externo mantiene al DC accesible desde la LAN fisica
sin cambiar su direccion `192.168.0.121`.

El host pierde la IP un momento al crear el switch; Windows la reasigna a
`vEthernet (Lab-External)`.

## Causa raiz del primer fallo de arranque

Sintomas: la VM quedaba `Running`, sin latido, todas las integraciones en
"Sin contacto", sin SSH, aunque el disco estaba bien y el guest arrancaba en
VirtualBox.

Causa: el initramfs original era **hostonly** y se genero con el disco en
**SATA/AHCI** (VirtualBox). Hyper-V Gen1 en IDE necesita el controlador
`ata_piix`. En este kernel `ata_piix` esta compilado dentro (`builtin`), pero el
initramfs hostonly no incluia los modulos de Hyper-V (`hv_vmbus`,
`hv_storvsc`) ni el resto necesario. El guest moria en el initramfs, antes de
montar la raiz, por eso **no dejaba rastro en el journal en disco**.

Reparacion aplicada (con el VHD arrancado en una VM temporal de VirtualBox,
`/etc/fstab` y netplan ya correctos):

```bash
# initramfs generico para el kernel actual (sin -H / hostonly)
sudo dracut -f -N /boot/initrd.img-$(uname -r) $(uname -r)

# cargar hv_utils (latido, cierre, KVP, hora) al arranque
printf 'hv_utils\n' | sudo tee /etc/modules-load.d/hyperv.conf
```

Resultado: initramfs de ~108 MB con `hv_vmbus`, `hv_storvsc`, `e1000`, etc.
En Hyper-V el guest arranca en ~10 s con latido correcto.

Comprobaciones utiles dentro del guest:

```bash
lsinitrd /boot/initrd.img-$(uname -r) | grep -E 'hv_vmbus|hv_storvsc|e1000'
lsmod | grep '^hv_'          # hv_utils, hv_vmbus, hv_storvsc...
cat /etc/netplan/00-installer-config.yaml
findmnt -no UUID /           # 98c1dcd2-1acb-480b-a678-8eb808933c78
```

## Archivos

### Orquestacion (host, PowerShell)

| Archivo | Funcion |
|---|---|
| `00-preparar-host.ps1` | Rol Hyper-V, servicios, grupo (por SID) y conversion VDI->VHD. `-ConvertOnly` no requiere elevacion. |
| `01-crear-vm-samba-dc1.ps1` | Crea/reconfigura switch externo, VM Gen1, disco IDE 0:0, NIC legacy, RAM, arranque y integraciones. Idempotente. |
| `02-verificar-apagado-graceful.ps1` | Arranca, espera latido+SSH, exige `Cierre` operativo, ejecuta `Stop-VM` sin `-Force` y valida estado `Off` + evento 18504. `-LeaveRunning` rearranca al final. |
| `ejecutar-todo.ps1` | Ejecuta 00 -> 01 -> 02 con un solo UAC y transcript. |
| `EJECUTAR-COMO-ADMIN.cmd` | Lanzador con autoelevacion. |
| `diagnostico.ps1` | Estado de VM, integraciones, red y eventos. `-StopVm` apaga a la fuerza (solo emergencia). |
| `estado-actual.ps1` | Volcado rapido de estado a `logs\estado-actual.txt`. |
| `run-prueba.ps1` | Envoltorio con transcript para `02` (`logs\prueba-apagado-*.log`). |
| `dump-eventos.ps1` | Exporta eventos de apagado a `logs\eventos-previos.txt`. |
| `dump-ic.ps1` | Lista propiedades/GUID de las integraciones. |
| `set-shutdown-timeout.ps1` | Sube `ShutdownTimeout` (120 -> 300 s) y lo verifica. |

### Guest (bash, via SSH)

| Archivo | Funcion |
|---|---|
| `ssh-guest.ps1` | Ejecuta comandos o sube scripts (`@archivo`) por SSH. `-HostName 192.168.0.121 -Port 22` para Hyper-V; `127.0.0.1:2222` era la VM de reparacion. |
| `build-askpass.ps1` / `askpass.exe` | SSH no interactivo con contrasena (solo laboratorio). |
| `guest-finalize.sh` | Reconstruye initramfs generico y crea `hv_utils` en modules-load. |
| `guest-repair.sh` | Reparacion inicial del initramfs. |
| `guest-check-clean.sh` | Verifica apagado limpio en el journal y estado de Samba. |
| `guest-diag.sh`, `guest-check-ata.sh`, `guest-bootlog.sh`, `guest-fix-hvutils.sh` | Diagnostico y utilidades. |

## Uso habitual

Abrir **Administrador de Hyper-V** y usar:

- **Iniciar**: `Start-VM samba-dc1` (o boton Iniciar).
- **Apagar**: boton **Apagar** / `Stop-VM samba-dc1` (sin `-Force`). El guest
  recibe la peticion por `hv_utils` y systemd detiene Samba y desmonta.
- **Nunca** usar **Turn Off / Apagar a la fuerza** ni cerrar la ventana
  guardando el estado para el dia a dia.

Por linea de comandos (PowerShell elevado):

```powershell
Start-VM samba-dc1
Stop-VM  samba-dc1            # ordenado
(Get-VM samba-dc1).State      # debe quedar Off
```

Para repetir la verificacion completa:

```powershell
.\02-verificar-apagado-graceful.ps1 -LeaveRunning
```

## Apagado del host Windows

Con `AutomaticStopAction=ShutDown`, al apagar el host Hyper-V envia la peticion
de apagado al guest por la integracion `Cierre` y espera a que se apague.
`ShutdownTimeout` (en `HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Virtualization`)
define el maximo por VM antes de apagarla a la fuerza; en esta maquina se dejo
en **300 s** (antes 120 s). El valor lo lee el servicio `vmms` al arrancar, asi
que queda efectivo tras el siguiente reinicio del host.

Escenarios:

| Escenario | Resultado |
|---|---|
| Apagado normal del host, guest sano | Ordenado (evento 18504) |
| Guest colgado / congelado | Forzado al agotar los 300 s |
| Corte de luz, BSOD, reset, boton mantenido | Forzado |
| Hibernar el host (S4) | La VM queda *Saved*, no apagada |

Un apagado forzado no suele corromper ext4 (`journal`) ni `ldb`, pero no es
riesgo cero. Tras uno, conviene ejecutar en el guest
`samba-tool dbcheck --cross-ncr`. Evita *Guardar estado* con un DC.

## Verificacion de la parada (evidencia)

Host, `Microsoft-Windows-Hyper-V-Worker/Admin`:

- `18506`: "El apagado ... se inicio mediante el componente de integracion".
- `18504`: "... se cerro mediante el componente de integracion de cierre con
  fuerza = false". **Este es el evento que confirma parada ordenada.**
- `18502`: "se desactivo" — aparece en apagados forzados; **no** debe ser el
  unico evento.

Guest (`journalctl -b -1`):

```
hv_utils: Shutdown request received - graceful shutdown initiated
systemd[1]: Stopped samba-ad-dc.service - Samba AD Daemon.
systemd[1]: Reached target shutdown.target - System Shutdown.
systemd-shutdown[1]: Syncing filesystems and block devices.
```

## Notas y trampas conocidas

- Los cmdlets devuelven nombres localizados. Para `Cierre` y `Latido` se
  resuelve por GUID (`9F8233AC-...` y `84EAAE65-...`), no por nombre.
- `Get-VMIntegrationService -Name Shutdown` falla en un Windows en espanol.
- Latido valido es `Ok*` (`OkApplicationsUnknown` es normal en Linux);
  comparar solo con `Ok` da falsos negativos.
- Sin el servicio `Cierre` operativo, `Stop-VM` puede abrir un dialogo y
  apagar a la fuerza. El script aborta antes de llegar ahi.
- `Stop-VM` devuelve el control antes de que se escriba el evento 18504; hay
  que consultarlo con reintentos (~segundos).
- El usuario `usuario` esta en `Administradores de Hyper-V`, pero necesita
  cerrar y volver a iniciar sesion para operar sin elevar.
- Credenciales de laboratorio: usuario `sysadmin`, contrasena en `askpass.exe`
  y en los scripts `guest-*.sh` (cambiar si el laboratorio deja de ser aislado).
- El VDI original `D:\VirtualBox_VMs\samba-dc1\samba-dc1.vdi` se conserva
  intacto como respaldo; la VM `samba-dc1` de VirtualBox tambien sigue
  registrada (apagada).
- La VM temporal `samba-dc1-repair` se elimino (sin borrar el VHD).

## Logs

En `logs\`:

- `run-*.log`: ejecuciones del orquestador.
- `prueba-apagado-*.log`: pruebas de parada con evidencia.
- `diagnostico-*.log`, `estado-actual.txt`, `eventos-previos.txt`,
  `ic-propiedades.txt`, `vbox-console.png`: diagnosticos.
