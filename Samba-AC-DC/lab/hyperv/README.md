# Hyper-V como servicio: `samba-dc1`

Migracion de la VM `samba-dc1` (VirtualBox) a **Hyper-V** para que el DC de Samba
levante solo con el host y se apague de forma **controlada** al apagar la maquina.

> **Si estas retomando el trabajo despues de reiniciar el host, empieza por
> [`REANUDAR.md`](REANUDAR.md)** — tiene el estado, los comandos y las decisiones pendientes.

## Estado actual

| Paso | Estado |
| :--- | :--- |
| Rol `Microsoft-Hyper-V-All` habilitado | Hecho (`hypervisorlaunchtype=Auto`) |
| Servicios `vmms` / `hns` / `vmcompute` en `Automatic` | Hecho (estaban en `Disabled`) |
| Disco `samba-dc1.vdi` (40 GB, 7 GB usados) copiado a `D:\HyperV\samba-dc1.vhd` | Hecho (VHDX pendiente, requiere `vmms` activo) |
| VDI original intacto | Si (se uso `clonemedium`) |
| Reinicio del host para cargar el hypervisor | **PENDIENTE** |
| Creacion de la VM en Hyper-V | Pendiente (script `01-...`) |
| Verificacion de parada graciosa | Pendiente (script `02-...`) |

## Procedimiento

```powershell
# 0) (ya ejecutado) preparacion del host
powershell -ExecutionPolicy Bypass -File lab\hyperv\00-preparar-host.ps1

# 1) REINICIAR el host fisico  <-- necesario para que cargue el hypervisor
#    (shut down / restart desde Windows; las VMs de VirtualBox se apagan solas)

# 2) Crear la VM en Hyper-V (elevado)
powershell -ExecutionPolicy Bypass -File lab\hyperv\01-crear-vm-samba-dc1.ps1

# 3) Verificar la parada controlada (elevado)
powershell -ExecutionPolicy Bypass -File lab\hyperv\02-verificar-apagado-graceful.ps1
```

## Configuracion resultante

| Parametro | Valor | Origen |
| :--- | :--- | :--- |
| Generacion | 1 (BIOS) | la VM original usa `firmware=BIOS` |
| RAM | 4096 MB estaticos | sin reprofile (igual que VirtualBox) |
| vCPU | 2 | igual que VirtualBox |
| Disco | VHDX en controlador SCSI 0:0 | el SCSI de Hyper-V aparece como `/dev/sda`, igual que el AHCI de VirtualBox |
| Red | Conmutador externo sobre `Ethernet` | equivalente al modo *bridged* actual |
| MAC | `0800277E8DF2` (original) | se conserva la identidad del guest |
| Adaptador | *Legacy* (E1000) | mantiene el mismo PCI ID que el `82540EM` de VirtualBox, para no cambiar el nombre de interfaz del guest |
| Arranque automatico | `Start` | |
| **Parada automatica** | **`ShutDown`** | **parada controlada del guest al apagar el host** |

## Parada controlada: como funciona

Con `AutomaticStopAction = ShutDown`, al apagar el host fisico Windows:

1. Hyper-V envia al guest una peticion de apagado (integracion **Shutdown**).
2. Si el guest no tiene instaladas las integraciones, Hyper-V enciende el
   **pulsador de alimentacion ACPI** virtual, que Ubuntu/systemd atiende
   (`HandlePowerKey`) y que dispara un `poweroff` ordenado.
3. El guest detiene `samba-ad-dc.service`, cierra `sam.ldb` y desmonta los
   sistemas de archivos; Hyper-V marca la VM como `Off`.

Esto **ya esta verificado en esta misma VM** antes de migrar: con la VM de
VirtualBox se le envio el pulsador ACPI y el guest paso a `poweroff` (no
`aborted`), es decir, apago de forma ordenada.

Opcional (recomendado): instalar las integraciones de Hyper-V para Linux en el
guest para que la parada use la integracion `Shutdown` y ademas obtener
sincronizacion de reloj y VSS:

```bash
curl -sSL https://raw.githubusercontent.com/microsoft/hyperv-linux-tools/main/install.sh | bash
systemctl enable hv_vss_daemon
```

## Pendiente de resolver en la red del laboratorio

El host tiene tres adaptadores y **el laboratorio no esta conectado fisicamente**:

| Adaptador | IP | Estado | Rol |
| :--- | :--- | :--- | :--- |
| `Ethernet` | 192.168.0.160/24 | **Desconectado** (sin cable) | red del laboratorio (`192.168.0.0/24`, gateway `192.168.0.1`) |
| `Wi-Fi` | 192.168.40.12/24 | Conectado | internet del host |
| `Ethernet 2` (Host-Only VBox) | 192.168.56.1/24 | Conectado | red aislada de VirtualBox |

La VM de VirtualBox esta en modo *bridged* sobre el **Wi-Fi**, mientras que el DC
tiene la IP estatica `192.168.0.121/24` (subred del laboratorio) → hoy el guest
queda sin conectividad y sin IP alcanzable. Para que el DC tenga red hay que
**conectar el cable de red del host al switch/router del laboratorio** (o
autorizar el cambio del NIC del guest a DHCP sobre el Wi-Fi).
