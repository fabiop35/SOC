#!/bin/bash
PASS='sysadmin**'
s() { echo "$PASS" | sudo -S -p '' "$@"; }
K=$(uname -r)

echo "== forzando hv_utils al arranque =="
echo hv_utils | s tee /etc/modules-load.d/hyperv.conf

echo "== reconstruyendo initramfs SOLO para $K (generico) =="
s dracut -f -N "/boot/initrd.img-$K" "$K"
echo "dracut rc=$?"

echo "== verificacion =="
s lsinitrd "/boot/initrd.img-$K" 2>/dev/null | grep -E 'hv_vmbus|hv_utils|hv_storvsc|ahci|e1000' | sort -u
ls -lh "/boot/initrd.img-$K"

echo "== netplan (debe seguir con .121 y MAC) =="
s cat /etc/netplan/00-installer-config.yaml

echo "== fstab root =="
findmnt -no UUID /

echo "== listo para apagar =="
