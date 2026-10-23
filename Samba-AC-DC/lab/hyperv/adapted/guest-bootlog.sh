#!/bin/bash
PASS='sysadmin**'
s() { echo "$PASS" | sudo -S -p '' "$@"; }

echo "== boots registrados =="
s journalctl --list-boots --no-pager 2>&1 | tail -12

echo
echo "== ultimos boots (cola) =="
for b in -4 -3 -2 -1; do
  echo "----- boot $b -----"
  s journalctl -b "$b" -n 20 --no-pager 2>&1 | tail -20
  echo
done

echo "== syslog: dracut/hyperv/hv_ =="
s grep -i -E 'dracut|hyper-v|hyperv|hv_vmbus|hv_utils' /var/log/syslog 2>/dev/null | tail -40 || echo "(sin coincidencias)"
