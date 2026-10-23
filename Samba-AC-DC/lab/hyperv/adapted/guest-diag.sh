#!/bin/bash
PASS='sysadmin**'
s() { echo "$PASS" | sudo -S -p '' "$@"; }

echo "== kernel / cmdline =="
uname -r
cat /proc/cmdline

echo "== grub root =="
s grep -m1 vmlinuz /boot/grub/grub.cfg

echo "== netplan actual =="
s cat /etc/netplan/00-installer-config.yaml

echo "== netplan backups =="
s ls -l /etc/netplan/backups
s cat /etc/netplan/backups/* 2>/dev/null

echo "== paquetes =="
dpkg -l | grep -E 'dracut|initramfs-tools|hyperv|linux-tools|linux-cloud-tools' || true

echo "== modulos hv cargados =="
lsmod | grep -E 'hv_|hyperv' || echo "(ninguno, normal fuera de Hyper-V)"

echo "== daemons hv =="
systemctl is-enabled hv-kvp-daemon hv-vss-daemon 2>&1 || true

echo "== drivers en el initrd =="
if command -v lsinitrd >/dev/null 2>&1; then
  s lsinitrd "/boot/initrd.img-$(uname -r)" | grep -E 'hv_vmbus|hv_utils|hv_storvsc|ata_piix|libata|ahci|e1000' | sort -u
else
  echo "lsinitrd no disponible"
fi

echo "== config dracut =="
s grep -R -E '^\s*hostonly|^drivers|^add_drivers' /etc/dracut.conf /etc/dracut.conf.d 2>/dev/null || true

echo "== blkid =="
s blkid

echo "== ultimo arranque (journal) =="
s journalctl -b -1 -n 25 --no-pager 2>/dev/null || true
