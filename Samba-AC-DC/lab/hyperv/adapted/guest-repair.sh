#!/bin/bash
PASS='sysadmin**'
s() { echo "$PASS" | sudo -S -p '' "$@"; }

echo "== antes: drivers IDE en el initrd =="
s lsinitrd "/boot/initrd.img-$(uname -r)" 2>/dev/null | grep -E 'ata_piix|hv_utils' | sort -u || echo "(no estan)"

echo "== regenerando initramfs generico (sin hostonly) =="
s dracut -f -N --regenerate-all
RC=$?
echo "dracut rc=$RC"
if [ $RC -ne 0 ]; then exit $RC; fi

echo "== despues: drivers en el initrd =="
s lsinitrd "/boot/initrd.img-$(uname -r)" 2>/dev/null | grep -E 'ata_piix|hv_vmbus|hv_utils|hv_storvsc' | sort -u

echo "== modulo hv_utils disponible =="
modinfo hv_utils 2>/dev/null | grep -E '^filename|^description' || echo "hv_utils no disponible"

echo "== tamano initrd =="
ls -lh /boot/initrd.img-$(uname -r)
