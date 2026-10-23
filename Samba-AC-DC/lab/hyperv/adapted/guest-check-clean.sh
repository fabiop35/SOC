#!/bin/bash
PASS='sysadmin**'
s() { echo "$PASS" | sudo -S -p '' "$@"; }

echo "== boot actual =="
uptime -p
systemctl is-active samba-ad-dc
systemctl is-enabled samba-ad-dc
ip -4 -br a show enp0s3

echo
echo "== ultimo apagado (boot anterior) =="
echo "$PASS" | sudo -S -p '' -v
sudo journalctl -b -1 --no-pager -n 400 2>/dev/null \
  | grep -E 'Reached target (System )?Shutdown|Shutdown|systemd-shutdown|Stopped.*(Samba|samba)|Unmounted' \
  | tail -25 || echo "(sin coincidencias)"

echo
echo "== ultima linea del boot anterior =="
sudo journalctl -b -1 --no-pager -n 6 2>/dev/null

echo
echo "== reinicios no planificados / errores =="
sudo journalctl --list-boots --no-pager 2>/dev/null | tail -4
