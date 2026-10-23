# REANUDAR — `samba-dc1` en Hyper-V (servicio con parada controlada)

> Punto de partida para retomar el trabajo en una sesion nueva.
> Todo lo necesario esta en `lab/hyperv/`.
>
> Guia completa para replicar en otra maquina/VM:
> [GUIA-REPLICAR-SAMBA-DC-HYPERV.md](GUIA-REPLICAR-SAMBA-DC-HYPERV.md)

## Estado actual (verificado)

- VM `samba-dc1` **Running**; `samba-ad-dc.service` **active**.
- IP del DC: `192.168.0.121/24` en `enp0s3` (estatica, via netplan).
- Host en la red del lab: `192.168.0.160/24` en `vEthernet (Lab-External)`.
- Conmutador `Lab-External` = **Internal** (red aislada host<->DC). El **Wi-Fi del host
  quedo libre** y con Internet (comprobado con `Test-NetConnection 8.8.8.8 -Port 53`).
- Integraciones de Hyper-V Linux: `Heartbeat`, `Shutdown`, `Time Sync`, `VSS` = **OK**.
- Parada controlada verificada con `02`: `Stop-VM` tardo **3.7 s**, estado final `Off`,
  evento `18506/18504` ("shut down using the Shutdown Integration").
- Disco activo: `D:\HyperV\samba-dc1.vhd` en **IDE 0:0**. El VHDX convertido
  (`D:\HyperV\samba-dc1.vhdx`) **no arrancaba** (dracut no encontraba el UUID raiz)
  y quedo como respaldo sin usar.

## TL;DR

```powershell
# 1) Crea/reconfigura conmutador interno, VM Gen 1 y disco en IDE 0:0
powershell -ExecutionPolicy Bypass -File D:\tmp\SOC\lab\hyperv\01-crear-vm-samba-dc1.ps1

# 2) Verifica la parada controlada (arranca, espera el latido, Stop-VM, mide)
powershell -ExecutionPolicy Bypass -File D:\tmp\SOC\lab\hyperv\02-verificar-apagado-graceful.ps1

# 3) Volver a dejar el DC encendido (02 lo deja Off)
Start-VM -Name samba-dc1
```

`01` usa por defecto `-SwitchType Internal` y el VHD. Para enlazar a un adaptador
fisico (solo si el router del lab esta disponible):

```powershell
...\01-crear-vm-samba-dc1.ps1 -SwitchType External -SwitchAdapter Ethernet
```

**No usar `-SwitchAdapter 'Wi-Fi'`**: Hyper-V deshabilita TCP/IP en `Wi-Fi` y el host
pierde la conexion inalambrica (fue la causa del incidente inicial).

## Que se hizo antes del reinicio del host

- Rol `Microsoft-Hyper-V-All` = **Enabled**; `bcdedit` con `hypervisorlaunchtype=Auto`.
- Servicios `vmms`, `hns`, `vmcompute` = **Automatic** (venian en `Disabled`).
- Disco copiado: `D:\VMs\samba-dc1\samba-dc1.vdi` -> `D:\HyperV\samba-dc1.vhd` (7.5 GB).
  El **VDI original no se toco**.
- Parada controlada ya probada en VirtualBox (pulsador ACPI -> `poweroff`, no `aborted`).

## Que se hizo despues del reinicio

1. Se detecto que el switch externo sobre `Wi-Fi` habia dejado al host sin Internet.
2. `Lab-External` se recreo como **Internal**; el host recibio `192.168.0.160/24`.
3. La VM no arrancaba con el disco en SCSI 0:0 ("Boot failure"). Se movio a **IDE 0:0**
   y se fijo el orden de arranque `IDE, CD, LegacyNetworkAdapter, Floppy`.
4. Con IDE, el kernel arrancaba pero dracut se quedaba esperando el UUID raiz.
   Se arranco el VHD en una VM temporal de VirtualBox y se reparo el guest:
   - `dracut -f -N --regenerate-all` (initramfs **generico**, sin `hostonly`;
     el initramfs original no incluia todos los drivers necesarios).
   - Se creo `/etc/netplan/99-static.yaml` con la IP estatica:
     ```yaml
     network:
       version: 2
       ethernets:
         enp0s3:
           dhcp4: false
           addresses: [192.168.0.121/24]
     ```
   - `chmod 600 /etc/netplan/99-static.yaml && netplan apply`
5. El VHD reparado se adjunto a Hyper-V en **IDE 0:0** y arranco correctamente.
   (El VHDX convertido no arrancaba; por eso se usa el VHD.)
6. Se verifico el DC por SSH: hostname `samba-dc1`, IP `192.168.0.121/24`,
   `samba-ad-dc` activo.
7. Se ejecuto `02-verificar-apagado-graceful.ps1`: parada graciosa confirmada.

## Decisiones tomadas

**A. Red del laboratorio: Internal (aislada).** No hay router del lab disponible.
El host y el DC se comunican por `vEthernet (Lab-External)` (`192.168.0.160` <-> `.121`).
El Wi-Fi del host queda para Internet (`192.168.40.x`).

**B. Integraciones Hyper-V en el guest: ya instaladas.** `Shutdown` responde OK, por lo
que `Stop-VM` usa la integracion (no solo ACPI). No hace falta reinstalarlas.

## Puntos tecnicos

- **Generacion 1**, BIOS. Disco en **IDE 0:0** (el SCSI de Hyper-V no arrancaba el guest).
- **Adaptador Legacy (E1000)** con MAC original `0800277E8DF2`, para conservar
  `enp0s3` y no romper el netplan del DC.
- **VHD, no VHDX**: el VHDX generado por `Convert-VHD` fallaba en dracut. Hyper-V Gen 1
  soporta VHD; `01` usa el VHD por defecto.
- **RAM 4096 MB estatica**, 2 vCPU (`DynamicMemoryEnabled=False`), `AutomaticStartAction=Start`,
  `AutomaticStopAction=ShutDown`, checkpoints deshabilitados.
- El disco sigue apareciendo como `/dev/sda` en el guest (igual que en VirtualBox).

## Datos de referencia del laboratorio

- DC: `samba-dc1.soc.smb.local` / `192.168.0.121/24`, Samba AD DC, Ubuntu 26.04.1 LTS.
- Credenciales: `sysadmin` / `sysadmin**`, `Administrator` / `Sysadmin**`,
  `soc-admin` / `Sysadmin**`, `invitado01` / `Invitado012026`.
- Servicio AD dentro del guest: `samba-ad-dc.service` (arranque automatico).
- Host en la red del lab: `192.168.0.160/24` (sin gateway; red aislada).

## Comprobaciones dentro del guest

```bash
hostname; ip -4 -br a
systemctl is-active samba-ad-dc
journalctl -b -1 | tail -30          # ultimo apagado limpio
sudo samba-tool dbcheck
sudo samba-tool domain level show
```

## Si algo falla

| Sintoma | Causa probable | Accion |
| :--- | :--- | :--- |
| `vmms` no corre | falta reiniciar el host | reiniciar y reintentar |
| El host pierde Wi-Fi | switch externo sobre `Wi-Fi` | recrear `Lab-External` como `Internal` |
| La VM no arranca el SO | disco en SCSI | mover el disco a `IDE 0:0` (lo hace `01`) |
| dracut no encuentra el UUID raiz | initramfs hostonly / VHDX convertido | usar el VHD y regenerar con `dracut -f -N --regenerate-all` |
| El guest no tiene IP | netplan sin IP estatica | crear/aplicar `/etc/netplan/99-static.yaml` |
| `Stop-VM` tarda > 240 s | guest sin integracion Shutdown / samba colgado | comprobar `Get-VMIntegrationService` y `systemctl status samba-ad-dc` |
| `02` deja la VM `Off` | es el comportamiento esperado | `Start-VM -Name samba-dc1` |
