#!/bin/bash
PASS='sysadmin**'
s() { echo "$PASS" | sudo -S -p '' "$@"; }
K=$(uname -r)

echo "== modinfo ata_piix =="
modinfo ata_piix 2>&1 | head -5

echo "== builtin? =="
grep -i -E 'ata_piix|libata|ata_generic' "/lib/modules/$K/modules.builtin" 2>/dev/null || echo "(no builtin)"

echo "== modulos ata disponibles =="
ls "/lib/modules/$K/kernel/drivers/ata/" 2>/dev/null

echo "== initrd: ata/libata/pata =="
s lsinitrd "/boot/initrd.img-$K" 2>/dev/null | grep -i -E 'ata_piix|ata_generic|libata|pata_|ahci' | sort -u

echo "== initrd: total modulos =="
s lsinitrd "/boot/initrd.img-$K" 2>/dev/null | grep -c '\.ko'

echo "== config dracut =="
s sh -c "grep -R -E 'hostonly|omit_drivers|drivers' /etc/dracut.conf /etc/dracut.conf.d 2>/dev/null" || true

echo "== kernels instalados =="
ls -d /lib/modules/* 2>/dev/null
