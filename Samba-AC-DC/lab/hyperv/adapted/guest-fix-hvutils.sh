#!/bin/bash
PASS='sysadmin**'

# Cachea credenciales sudo para que los comandos siguientes no consuman stdin.
echo "$PASS" | sudo -S -p '' -v

sudo tee /etc/modules-load.d/hyperv.conf >/dev/null <<'EOF'
hv_utils
EOF

echo "== contenido =="
cat /etc/modules-load.d/hyperv.conf
echo "== od =="
od -c /etc/modules-load.d/hyperv.conf
