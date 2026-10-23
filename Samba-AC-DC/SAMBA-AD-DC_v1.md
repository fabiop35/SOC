# Samba AD Domain Controller — Server Documentation

| | |
|---|---|
| **Hostname** | `samba-dc1` |
| **FQDN** | `samba-dc1.soc.smb.local` |
| **IP address** | `10.172.206.44/24` (static) |
| **Gateway** | `10.172.206.42` |
| **OS** | Ubuntu 26.04.1 LTS (Resolute Raccoon), kernel 7.0.0-38-generic |
| **Samba version** | 4.23.6 (`2:4.23.6+dfsg-1ubuntu2.2`) |
| **Domain (realm)** | `soc.smb.local` (Kerberos realm `SOC.SMB.LOCAL`) |
| **NetBIOS domain / workgroup** | `SOC` |
| **Domain SID** | `S-1-5-21-3873822391-889540105-2879782541` |
| **Role** | Active Directory Domain Controller (forest/domain function level 2008 R2) |
| **Administrator account** | `Administrator` / `SOC\Administrator` |

---

´sysadmin/sysadmin**´

## 1. Architecture / Request Flow

```
                            Windows / Linux clients
                                     |
                                     |  TCP 445 (SMB), 53 (DNS), 88 (Kerberos),
                                     |  389 (LDAP), 137/138/139, 464, 636, 3268, 3269
                                     v
                        +----------------------------+
                        |   samba-dc1 (10.172.206.44/24)
                        |   samba-ad-dc.service       |
                        |   /usr/sbin/samba daemon    |
                        |   (smbd/nmbd/winbind masked)|
                        +----------------------------+
                                |          |
              owns 127.0.0.1:53 |          | forwards non-domain queries
              (internal DNS)    |          v
                        +-------v--+   +------------------------------+
                        | sam.ldb  |   | forwarders: 10.172.206.42,   |
                        | (AD DB:  |   |             1.1.1.1, 8.8.8.8 |
                        | users,   |   +------------------------------+
                        | groups,  |
                        | schema,  |
                        | DNS zones|
                        +----------+
```

**How authentication works:**

1. Client looks up the domain via DNS SRV records:
   - `_ldap._tcp.soc.smb.local`, `_kerberos._tcp.soc.smb.local` → `samba-dc1.soc.smb.local` → `10.172.206.44`.
2. Client obtains a Kerberos ticket from the DC (port 88) using its domain credentials.
3. SMB file access (port 445) is secured with those Kerberos / NTLM tokens against the AD database (`sam.ldb`, accessed through LDB/LDAP).
4. The DC's internal DNS answers domain queries and forwards everything else to the configured forwarders.

**Key processes/services:**

- `samba-ad-dc.service` — the single Samba daemon (`/usr/sbin/samba --foreground --no-process-group`) that runs KDC, LDAP(*), NetBIOS, DNS, and SMB.
- `smbd`, `nmbd`, `winbind` — **masked** (a DC must not run the standalone S3 daemons).
- `systemd-resolved` — **disabled** (Samba owns port 53).

---

## 2. Networking

`/etc/netplan/00-installer-config.yaml`:

```yaml
network:
  version: 2
  ethernets:
    enp0s3:
      match:
        macaddress: 08:00:27:7e:8d:f2
      set-name: enp0s3
      dhcp4: false
      dhcp6: false
      addresses:
        - 10.172.206.44/24
      routes:
        - to: default
          via: 10.172.206.42
      nameservers:
        addresses:
          - 127.0.0.1
        search:
          - soc.smb.local
```

Apply changes with `netplan apply`.

`/etc/resolv.conf` (static, replaced the systemd-resolved stub):

```
nameserver 127.0.0.1
search soc.smb.local
```

`/etc/hosts`:

```
127.0.0.1	localhost
10.172.206.44	samba-dc1.soc.smb.local	samba-dc1

::1	ip6-localhost	ip6-loopback
ff02::1	ip6-allnodes
ff02::2	ip6-allrouters
```

> The IP must not be served by the DHCP pool, or reserve it on the DHCP server.

---

## 3. DNS

- Owned by Samba's internal DNS backend on port 53 (`0.0.0.0` / `127.0.0.1`).
- Forwarders (configured in `/etc/samba/smb.conf`): `10.172.206.42`, `1.1.1.1`, `8.8.8.8`.
- Standard AD zones created: `soc.smb.local`, `DomainDnsZones`, `ForestDnsZones`.
- Verify:
  - `host -t SRV _ldap._tcp.soc.smb.local 127.0.0.1`
  - `host samba-dc1.soc.smb.local 127.0.0.1`
  - `nslookup archive.ubuntu.com 127.0.0.1` (forwarding test)

---

## 4. Credentials

- **Admin user:** `Administrator` (UPN `Administrator@soc.smb.local`, sAMAccountName `Administrator`)
- **Admin password:** set to the value provided during setup. NOTE: it does not meet AD complexity rules (was set with complexity temporarily off); **change it** with:
  ```bash
  sudo samba-tool user setpassword administrator --newpassword='Sysadmin**'
  ```
- The DNS `machinekrbtgt` accounts, `krbtgt` and `dns-*` accounts are auto-created by provisioning.

---

## 5. Samba Shares

Config in `/etc/samba/smb.conf` (relevant sections below describe the shares; see the full file for `[global]`, `[sysvol]`, `[netlogon]`).

| Share | Path | Notes |
|---|---|---|
| `sysvol` | `/var/lib/samba/sysvol` | AD system volume (auto-created) |
| `netlogon` | `/var/lib/samba/sysvol/soc.smb.local/scripts` | Login scripts / GPO storage (auto-created) |
| `public` | `/srv/samba/public` | Read/write for `SOC\Domain Users` |
| `home` | `/srv/samba/homes/%U` | Per-user home share; `//samba-dc1/home` maps to `/srv/samba/homes/<username>` |

- Users authenticate with their AD account and are in the `Domain Users` group.
- `force user = sysadmin` / `force group = sysadmin` makes the DC write files as the local `sysadmin` account (POSIX mapping workaround for a lab; no winbind/nss).
- Directory perms: `2777` (world + setgid) so mapped domain users can write.

Full share stanzas:

```ini
[public]
	path = /srv/samba/public
	read only = no
	browseable = yes
	valid users = "@SOC\Domain Users"
	force user = sysadmin
	force group = sysadmin
	create mask = 0660
	directory mask = 2770

[home]
	path = /srv/samba/homes/%U
	read only = no
	browseable = yes
	valid users = "@SOC\Domain Users"
	force user = sysadmin
	force group = sysadmin
	create mask = 0660
	directory mask = 2770
```

> The classic `[homes]` auto-share does **not** work on a DC without winbind/NSS, hence the explicit `home` share using `%U`.

---

## 6. Firewall (ufw — active, deny incoming)

| Protocol | Ports | Purpose |
|---|---|---|
| TCP | 22 | SSH |
| TCP | 53 | DNS |
| UDP | 53 | DNS |
| TCP | 88 | Kerberos |
| UDP | 88 | Kerberos |
| TCP+UDP | 135 | RPC endpoint mapper |
| TCP+UDP | 137, 138 | NetBIOS name service / datagrams |
| TCP | 139 | NetBIOS session |
| TCP | 389 | LDAP |
| UDP | 389 | LDAP (CLDAP) |
| TCP | 445 | SMB/CIFS |
| TCP+UDP | 464 | Kerberos password change |
| TCP | 636 | LDAPS |
| TCP | 3268, 3269 | Global Catalog (GC / GC-SSL) |

Note: no explicit high-port rule was added; for SMB dynamic RPC ports, add if clients fail on some operations.

---

## 7. Day-to-Day Administration (run on the DC)

```bash
# List users / groups
samba-tool user list
samba-tool group list

# Create a user (must meet complexity: upper+lower+digit+symbol, ≥8 chars)
sudo samba-tool user create invitado01 'Invitado012026' --given-name=invitado01 --surname=01
sudo samba-tool user setexpiry invitado01 --noexpiry

# Reset a password
samba-tool user setpassword alice --newpassword='New#Pass456'

# Add user to a group
samba-tool group addmembers "SOC\Domain Users" alice

# Replication / domain state
samba-tool domain level show
samba-tool drs showrepl

# DNS records
samba-tool dns query 127.0.0.1 soc.smb.local @ ALL -U Administrator

# Test SMB from the DC
smbclient //localhost/public -U 'Administrator%PASSWORD'

# Reload/restart the DC
systemctl reload samba-ad-dc     # picks up smb.conf changes
systemctl restart samba-ad-dc    # brief downtime
```

---

## 8. Joining Clients to the Domain

### 8.1 Windows client (Windows 10/11/Server)

1. Set the client's DNS to the DC: **Control Panel → Network → IPv4 → DNS server `192.168.0.121`** (remove any other DNS; do not use DHCP DNS).
   - Verify: `nslookup samba-dc1.soc.smb.local` returns `192.168.0.121`.
2. Ensure client clock is within ~5 minutes of the DC (Kerberos requirement).
3. **Settings → System → About → Rename this PC (advanced) → Change**.
4. Select **Domain** and enter `soc.smb.local`.
5. When prompted, log in as `SOC\Administrator` (or a domain admin) with the admin password.
6. A computer account is auto-created; restart when prompted.
7. After reboot, log in with `SOC\<username>`.

Join can also be automated:
```powershell
Add-Computer -DomainName soc.smb.local -Credential SOC\Administrator -Restart
```

Verify on the DC:
```bash
samba-tool computer show <COMPUTERNAME>
samba-tool user list | grep -i '\$'   # computer accounts end with $
```

### 8.2 Linux client (with `realmd` on Ubuntu/Debian)

> Prefer DNS `10.172.206.44` for the client.

```bash
# Install packages
sudo apt update && sudo apt install -y realmd sssd sssd-tools libnss-sss libpam-sss \
    adcli krb5-user samba-common-bin
# Set client hostname (must be resolvable/FQDN)
sudo hostnamectl set-hostname client01.soc.smb.local
# Ensure the client resolves: echo "10.172.206.44 samba-dc1.soc.smb.local" >> /etc/hosts

# Discover the realm
sudo realm discover soc.smb.local
# Join
sudo realm join --user=Administrator soc.smb.local
# (prompts for the Administrator password)

# Enable services
sudo systemctl enable --now sssd

# Test
sudo kinit Administrator
getent passwd administrator          # should return a domain user entry
sudo realm list                      # show joined state
```

Access a share:
```bash
sudo apt install -y smbclient cifs-utils
smbclient //samba-dc1/public -U alice
# or mount with credentials
sudo mount -t cifs //samba-dc1/public /mnt/public -o username=alice,domain=SOC
```

### 8.3 Verify a joined client from the DC

```bash
samba-tool computer list
host -t A <client-hostname> 127.0.0.1          # DNS record from client registration
```

---

## 9. Troubleshooting

| Symptom | Likely cause / fix |
|---|---|
| `KRB5KDC_ERR` / "clock skew" | Client time out of sync → check `timedatectl` on both |
| DNS queries fail on port 53 | `systemd-resolved` re-enabled? `systemctl is-active systemd-resolved` |
| `NT_STATUS_BAD_NETWORK_NAME` on `home` | User dir missing: `mkdir -p /srv/samba/homes/<username>` |
| Can't join: "DNS name does not exist" | Client DNS must point to `10.172.206.44`, not upstream |
| Write denied on share | Check POSIX perms on the share dir: `ls -la /srv/samba/<share>` |
| Want to inspect AD objects | `ldbsearch -H /var/lib/samba/private/sam.ldb -s base ""` |

---

## 10. Backups & Rollback

- **Pre-install config backups:** `/root/samba-install-backup/` (original netplan YAML + resolv.conf).
- **AD database:** `/var/lib/samba/` (most importantly `private/sam.ldb`, `sysvol`, and `etc/smb.conf`).

Backup the AD:
```bash
samba-tool domain backup offline --targetdir=/root/samba-backups
```
Restore to a new machine per Samba docs; the VM's snapshot (VirtualBox) is the fastest full rollback.

---

## 11. Security Notes

- `sysadmin**` was used as the Administrator password (below AD complexity); **change it** (see section 4) before adding users.
- Password complexity is enforced for all future password changes (`samba-tool domain passwordsettings show`).
- Shares use `force user`/world-write for lab simplicity — tighten POSIX permissions / per-user directories before production use.
- Consider restricting ufw sources to your LAN/VPN instead of `Anywhere`.
- Always keep `samba-ad-dc` the only Samba service; never re-enable `smbd`/`nmbd` on the DC.




***********************
###  Plan to change the IP (Samba stays working)
 Current setup (verified)                                                                                                                   
                                                                                                                                            
 - Ubuntu 26.04, host samba-dc1.soc.smb.local, role: Samba AD Domain Controller (samba-ad-dc.service active; smbd/nmbd masked � normal for
   an AD DC).                                                                                                                               
 - Interface enp0s3: static 10.172.206.44/24, gateway 10.172.206.42.                                                                        
 - Network managed by netplan (/etc/netplan/00-installer-config.yaml, mode 600, root-only).                                                 
 - DNS: Samba internal DNS at 127.0.0.1; /etc/resolv.conf ? 127.0.0.1, search soc.smb.local.                                                
 - /etc/hosts maps 10.172.206.44 ? samba-dc1.soc.smb.local samba-dc1.
 - smb.conf has no interfaces/bind interfaces only, so Samba binds to all interfaces automatically � no bind change needed on IP change.    
                                                                                                                                            
 The real risk with an AD DC is its internal DNS records (its own A record + SRV records) and /etc/hosts going stale, so clients can't find
 the DC.

 Plan to change the IP (Samba stays working)

 1. Decide new IP + gateway/subnet. If the subnet changes, gateway and any DNS forwarder must change too.
 2. Edit netplan /etc/netplan/00-installer-config.yaml: change addresses (and gateway4/routes, nameservers only if applicable).
    - Apply: sudo netplan generate then sudo netplan apply (use --debug to preview).
 3. Update /etc/hosts: change the 10.172.206.44  samba-dc1.soc.smb.local samba-dc1 line to the new IP. (Do this before/in step with apply so
    self-resolution stays consistent.)
 4. Update Samba's internal DNS A record (same hostname ? just replaces old IP):
    sudo samba_dnsupdate --all --use-file --verbose (or sudo samba-tool dns update 127.0.0.1 soc.smb.local samba-dc1 A <oldip> <newip>). SRV
    records use the hostname, so they should not need editing.
 5. If the gateway changed, update dns forwarder = 10.172.206.42 ... in /etc/samba/smb.conf to the new external resolver(s), else internet
    name resolution breaks (Samba itself still works).
 6. Restart Samba: sudo systemctl restart samba-ad-dc.
 7. Update everything that points at the old IP: clients' DNS server setting / DHCP scope option, DNS delegations/forwarders on other
    servers, any static /etc/hosts on clients, firewall rules. Kerberos/SPNs use the hostname, so they're unaffected.
 8. Verify:
    - host samba-dc1.soc.smb.local 127.0.0.1
    - host -t SRV _ldap._tcp.soc.smb.local 127.0.0.1
    - sudo samba-tool domain info 127.0.0.1
    - smbclient -L localhost -U administrator (share list)                                                                                  
    - sudo samba-tool dbcheck --cross-nc
                                                                                                                                            
 Notes/tradeoffs:                                                                                                                           

 - If you keep the same subnet, it's just steps 2�4 + 6. If you move subnets, step 5 (forwarder) and step 7 (clients/DHCP/firewall) become  
   mandatory.                                                                                                                               

- Avoid editing DNS via the Samba AD database files directly; always use samba-tool/samba_dnsupdate.
 Do you want the plan tailored to a specific new IP (same subnet) or a subnet change, and should I check for a firewall (ufw/nftables) before finalizing?


### Fix Internet

### Windows Commands
gpupdate /force
reg query "HKLM\\Software\\Microsoft\\Windows\\CurrentVersion\\Policies\\System" /v InactivityTimeoutSecs
reg add "HKLM\\Software\\Microsoft\\Windows\\CurrentVersion\\Policies\\System" /v InactivityTimeoutSecs /t REG\_DWORD /d 300 /f

nslookup soc.smb.local
nslookup samba-dc1.soc.smb.local

gpresult /r
Get-Service sshd
netstat -ano | findstr :22

ipconfig /flushdns  
nltest /sc_query:SOC
gpupdate /force
nltest /sc_reset:SOC
gpupdate /force
                                                                                             
Then reboot and verify:
reg query "HKLM\Software\Microsoft\Windows\CurrentVersion\Policies\System" /v InactivityTimeoutSecs
reg query "HKCU\Software\Policies\Microsoft\Windows\Control Panel\Desktop" /v ScreenSaveTimeOut

##### The fix (on the DC, root) 
firewall-cmd --permanent --zone=<zone> --add-service=samba-dc   # or: 
firewall-cmd --permanent --zone=<zone> --add-port=49152-65535/tcp 
firewall-cmd --permanent --zone=<zone> --add-port=1024-5000/tcp 
firewall-cmd --reload 



















