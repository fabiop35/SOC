# SOC

Laboratorio de Security Operations Center: Active Directory con Samba 4.23.6 como
controlador de dominio, VMs de deteccion/respuesta (Wazuh, TheHive, Shuffle, Kali)
y documentacion de la arquitectura.

## Documentacion

| Documento | Contenido |
| :--- | :--- |
| [`SAMBA-AD-DC_Info.md`](SAMBA-AD-DC_Info.md) | Entorno, puertos, usuarios, GPO, copias de seguridad y troubleshooting del DC |
| [`lab/hyperv/README.md`](lab/hyperv/README.md) | Migracion de `samba-dc1` a Hyper-V para correrla como servicio |
| [`lab/hyperv/REANUDAR.md`](lab/hyperv/REANUDAR.md) | **Punto de partida** si se retoma el trabajo tras un reinicio |

## Arquitectura

| Imagen | Contenido |
| :--- | :--- |
| [`images/arquitectura.jpg`](images/arquitectura.jpg) | Flujo de solicitudes del DC Samba (base generada por `SAMBA-AD-DC_Info.md`) |
| [`images/arquitectura_fases.jpg`](images/arquitectura_fases.jpg) | Stack SOC de 4 niveles: Telemetria → Deteccion → Automatizacion → Casos/CTI (EN) |
| [`images/arquitectura_fases_es.jpg`](images/arquitectura_fases_es.jpg) | El mismo diagrama en espanol |

Los diagramas son reproducibles con `images/generar_arquitectura_fases.py` y
`images/generar_arquitectura_fases_es.py` (requieren `matplotlib`).
