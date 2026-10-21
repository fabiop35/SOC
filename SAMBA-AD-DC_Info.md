# **Samba** *Active Directory & Domain Controller*

## 1. Entorno

| Recurso | Descripción |
| :--- | :--- | 
| Host | `samba-dc1.soc.smb.local` |
| IP del DC | `192.168.0.121/24` (estática) |
|Usuario Administrador Linux | Usuario (máquina virtual Linux) `sysadmin` *password:* `sysadmin**` 
| NetBIOS | `SAMBA-DC1` |
| Dominio (Realm) | `SOC.SMB.LOCAL` |
| Grupo de trabajo | `SOC` |
| Rol | Controlador de Dominio de Active Directory |
| Samba | 4.23.6 (Ubuntu) |
| Puerta de enlace | `192.168.0.1` |
| DNS (en el DC) | `127.0.0.1` |
| Zona horaria | `America/Bogota` (UTC-05, reloj de hardware en UTC) |
| Cuenta de administrador | `Administrator` (RID 500) |
| **SID del dominio** | `S-1-5-21-3873822391-889540105-2879782541` |
| **Sistema operativo** | Ubuntu 26.04.1 LTS (Resolute Raccoon), núcleo 7.0.0-38-generic |
| **Rol** | Controlador de dominio de Active Directory (nivel funcional del bosque/dominio 2008 R2) |

### 1.1 Zona horaria
```bash
timedatectl set-timezone America/Bogota
```
### 1.2 Puertos
DNS `53`, Kerberos `88`, RPC `135`, NetBIOS `139`, LDAP `389`, SMB `445`, kpasswd `464`, LDAPS `636`, GC `3268`/`3269`.

### 1.3 Firewall

| Protocolo | Puertos | Propósito |
| :--- | :--- | :--- |
| TCP | 22 | SSH |
| TCP | 53 | DNS |
| UDP | 53 | DNS |
| TCP | 88 | Kerberos |
| UDP | 88 | Kerberos |
| TCP+UDP | 135 | Mapeador de endpoints RPC |
| TCP+UDP | 137, 138 | Servicio de nombres NetBIOS / datagramas |
| TCP | 139 | Sesión NetBIOS |
| TCP | 389 | LDAP |
| UDP | 389 | LDAP (CLDAP) |
| TCP | 445 | SMB/CIFS |
| TCP+UDP | 464 | Cambio de password de Kerberos |
| TCP | 636 | LDAPS |
| TCP | 3268, 3269 | Catálogo global (GC / GC-SSL) |	


## 2. Arquitectura / Flujo de solicitudes
					Clientes Windows / Linux
                                |
                                |  TCP 445 (SMB), 53 (DNS), 88 (Kerberos),
                                |  389 (LDAP), 137/138/139, 464, 636, 3268, 3269
                                v
                     +------------------------------+
                     |  samba-dc1 (192.168.0.121/24)|
                     |  samba-ad-dc.service         |
                     |  /usr/sbin/samba daemon      |
                     |  (smbd/nmbd/winbind masked)  |
                     +------------------------------+
                                |          |
                  posee 127.0.0.1:53       | reenvía consultas ajenas al dominio
                  (DNS interno) |          v
                     +-------v--+  +------------------------------+
                     | sam.ldb  |  | reenvíadores (forwarders):   |
                     | (Base de |  | 192.168.0.1, 1.1.1.1,        |
                     | datos AD:|  | 8.8.8.8                      |
                     | usuarios,|  +------------------------------+
                     | grupos,  |
                     | esquema, |
                     | zonas DNS|
                     +----------+

## 3. ADMINISTRACIÓN

### 3.1 Usuarios/Credenciales
**Usuario Administrador de Dominio:** `soc-admin` **Password:** `Sysadmin**`
**Usuario Administrador de Dominio:** `Administrator` **Password:** `Sysadmin**`

**Usuario Dominio Permisos Básicos:** `invitado01` **Password:** `Invitado012026`

**Usuario Administrador Maquina Local**(*Por fuera del control del Dominio*): `Administrador` **Password:** `Admin2026*`

### 3.2 Cambiar Password

```bash
sudo samba-tool user setpassword invitado01 --newpassword='Invitado012026'
```

### 3.3 Carpetas Compartidas en RED

| Recurso compartido | Ruta | Notas |
| :--- | :--- | :--- |
| `public` | `/srv/samba/public` | Lectura/escritura para `SOC\Domain Users` ruta `\\samba-dc1\public`|
| `home` | `/srv/samba/homes/%U` | Carpeta personal por usuario; `\\samba-dc1\home` apunta a `/srv/samba/homes/<nombre_de_usuario>` |

Para compartir más recursos editar el archivo `/etc/samba/smb.conf`

### 3.4 Acceder a un recurso compartido:
```bash
sudo apt install -y smbclient cifs-utils
smbclient //samba-dc1/public -U invitado01

#montar con credenciales
sudo mount -t cifs //samba-dc1/public /mnt/public -o username=invitado01,domain=SOC
```

### 3.4 Comando Básicos  (Crear usuario, cambiar password etc.)
Ingresar mediante `SSH` al servidor controlador de dominio Linux (usuario sysadmin)
```bash
# Listar usuarios / grupos
samba-tool user list
samba-tool group list

# Crear un usuario
sudo samba-tool user create invitado01 'Invitado012026' --given-name=invitado01 --surname=01
sudo samba-tool user setexpiry invitado01 --noexpiry

# Restablecer una contraseña
samba-tool user setpassword invitado01 --newpassword='New#Pass456'

# Agregar un usuario a un grupo
samba-tool group addmembers "SOC\Domain Users" invitado01

# Agreagar un usuario al grupo de Administrador
sudo samba-tool group addmembers "Domain Admins" soc-admin

# Consultar el estado de una cuenta
sudo samba-tool user show invitado01

#Bloquear un usuario 
sudo samba-tool user disable invitado01

#Desbloquear un Usuario
sudo samba-tool user enable invitado01

# Registros DNS
sudo samba-tool dns query 127.0.0.1 soc.smb.local @ ALL -U Administrator

# Probar SMB desde el controlador de dominio
sudo smbclient //localhost/public -U 'Administrator%PASSWORD'

# Recargar/reiniciar el controlador de dominio
sudo systemctl reload samba-ad-dc     # aplica cambios en smb.conf
sudo systemctl restart samba-ad-dc    # breve interrupción del servicio

#Eliminar un cliente
echo 'sysadmin**' | sudo -S samba-tool computer delete SEC-SOC-03\$

#Verificar un cliente registrado desde el controlador de dominio
sudo samba-tool computer list
host -t A <nombre-host-cliente> 127.0.0.1          # registro DNS del registro del cliente
```

**Script de conmutación:** `/usr/local/sbin/net-ip.sh`
```bash
net-ip.sh status                  # mostrar direccionamiento actual
net-ip.sh static [IP PREFIX GW]   # aplicar config estática
net-ip.sh dhcp                    # volver a DHCP
net-ip.sh help
```

### 3.5 Registro/Unión de clientes al dominio

#### 3.5.1 Cliente Windows (Windows 10/11/Server)
* 1. Configurar el DNS del cliente apuntando al controlador de dominio: Panel de control → Red → IPv4 → Servidor DNS **192.168.0.121** (*Sólo ese DNS*).
 > Verificar en el simbolo del sistema(CMD): `nslookup samba-dc1.soc.smb.local` devuelve `192.168.0.121`.
* 2. Verificar de que el reloj del cliente esté sincronizado con el controlador de dominio dentro de un margen de ~5 minutos.
* En Configuración → Sistema → Acerca de → Cambiar nombre de este PC (avanzado) → **Cambiar**.
* Seleccionar **Dominio** e ingresar `soc.smb.local`.
* Cuando lo solicite, iniciar sesión como **SOC\soc-admin** (o un *administrador del dominio*) con la contraseña de *administrador*.
* Reinicie cuando lo indique.
* Después de reiniciar, iniciar sesión con un usuario del dominio, por ejemplo `invitado01` **SOC\invitado01**.
* El primer inicio de sesión toma bastante tiempo.

La unión se puede hacer mediante consola
```bash
Add-Computer -DomainName soc.smb.local -Credential SOC\soc-admin -Restart
samba-tool computer show <NOMBRE_DE_EQUIPO>
samba-tool user list | grep -i '\$'    # las cuentas de equipo terminan en $
```

#### 3.5.2 Cliente Linux
```bash
# Instalar paquetes
sudo apt update && sudo apt install -y realmd sssd sssd-tools libnss-sss libpam-sss adcli krb5-user samba-common-bin

# Establecer el nombre de host del cliente (debe ser resoluble / FQDN)
sudo hostnamectl set-hostname client01.soc.smb.local
# Asegurar la resolución en el cliente: echo "10.172.206.44 samba-dc1.soc.smb.local" >> /etc/hosts

# Descubrir el realm
sudo realm discover soc.smb.local

# Unir al dominio
sudo realm join --user=Administrator soc.smb.local

# (solicitará la contraseña del Administrator)

# Habilitar servicios
sudo systemctl enable --now sssd

# Probar
sudo kinit Administrator
getent passwd administrator         # debería devolver una entrada de usuario de dominio
sudo realm list                     # muestra el estado de unión
```

### 4. Rutas útiles
| Ruta | Propósito |
| :--- | :--- |
| `/etc/samba/smb.conf` | Configuración global del DC y recursos compartidos (sysvol, netlogon, public, home) |
| `/etc/netplan/00-installer-config.yaml` | Configuración de red estática |
| `/etc/netplan/backups/` | Respaldos de netplan con marca de tiempo |
| `/usr/local/sbin/net-ip.sh` | Script para cambiar entre estática y DHCP |
| `/var/lib/samba/sysvol/soc.smb.local/Policies/` | Archivos de Directivas de Grupo |
| `/var/lib/samba/private/sam.ldb` | Base de datos de directorios (GPO versionNumber) |
| `/var/lib/samba/private/ldapi` | Socket LDAP local (operaciones de root) |
| `/var/lib/samba/private/secrets.keytab` | Keytab de la máquina DC (admin con -k yes) |
| `/var/log/samba/log.samba`, `log.smbd`, `log.winbindd` | Registros (logs) |

### 5. Copias de seguridad y recuperación
* Copias de seguridad de *configuración* preinstalación: `/root/samba-install-backup/`
* Base de datos de AD: `/var/lib/samba/` *(principalmente private/sam.ldb, sysvol y etc/smb.conf)*.

### 6. Politicas de Dominio
#### 6.1 Directiva de Grupo (GPO): bloqueo de pantalla tras 5 minutos
se creó GPO: Default Domain Policy {31B2F340-016D-11D2-945F-00C04FB984F9} (vinculada en la raíz del dominio, por lo que aplica a todos los equipos

Archivo `/var/lib/samba/sysvol/soc.smb.local/Policies/{31B2F340-016D-11D2-945F-00C04FB984F9}/MACHINE/microsoft/windows nt/SecEdit/GptTmpl.inf`
         `/var/lib/samba/sysvol/soc.smb.local/Policies/\{31B2F340-016D-11D2-945F-00C04FB984F9\}/MACHINE/microsoft/windows\ nt/SecEdit/GptTmpl.inf`

### 7. Servicios
* **LDAP (Lightweight Directory Access Protocol) & LDAPS:**  Base de datos central de Active Directory
* **KDC (Key Distribution Center) — Kerberos:** Seguridad y autenticación.
* **DNS (Domain Name System) Interno**
*  **SYSVOL y NETLOGON** (Replicación y Archivos de **Políticas**)


