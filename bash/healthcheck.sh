#!/usr/bin/env bash
#
# healthcheck.sh — Revisión rápida del estado de un servidor Linux.
#
# Uso:
#   ./healthcheck.sh                 # usa los umbrales por defecto
#   UMBRAL_DISCO=90 ./healthcheck.sh # cambia un umbral
#
# Comprueba:
#   - Uso de disco de cada sistema de ficheros
#   - Uso de memoria RAM
#   - Carga de CPU respecto al número de núcleos
#   - Que los servicios indicados estén activos (systemd)
#
# Sale con código 0 si todo está bien y 1 si hay alguna alerta,
# para poder integrarlo en cron, Nagios/Zabbix o un pipeline.
#
# Autor: Toni Susany

set -uo pipefail

UMBRAL_DISCO="${UMBRAL_DISCO:-85}"      # % de uso de disco a partir del cual se alerta
UMBRAL_RAM="${UMBRAL_RAM:-90}"          # % de RAM usada a partir del cual se alerta
SERVICIOS="${SERVICIOS:-ssh cron}"      # servicios que deben estar activos

ALERTAS=0

ok()     { printf '  \e[32m[OK]\e[0m     %s\n' "$1"; }
alerta() { printf '  \e[31m[ALERTA]\e[0m %s\n' "$1"; ALERTAS=$((ALERTAS + 1)); }

echo "== Healthcheck de $(hostname) · $(date '+%Y-%m-%d %H:%M') =="

# --- Disco -------------------------------------------------------------------
echo "Disco (umbral ${UMBRAL_DISCO}%):"
while read -r uso punto; do
    porcentaje=${uso%\%}
    if (( porcentaje >= UMBRAL_DISCO )); then
        alerta "$punto al ${porcentaje}%"
    else
        ok "$punto al ${porcentaje}%"
    fi
done < <(df -P -x tmpfs -x devtmpfs -x overlay -x squashfs | awk 'NR>1 {print $5, $6}')

# --- Memoria -----------------------------------------------------------------
echo "Memoria (umbral ${UMBRAL_RAM}%):"
RAM=$(free | awk '/^Mem:/ {printf "%d", ($2 - $7) * 100 / $2}')
if (( RAM >= UMBRAL_RAM )); then
    alerta "RAM usada al ${RAM}%"
else
    ok "RAM usada al ${RAM}%"
fi

# --- CPU ---------------------------------------------------------------------
echo "CPU:"
NUCLEOS=$(nproc)
CARGA=$(awk '{print $1}' /proc/loadavg)
# Alerta si la carga media de 1 minuto supera el número de núcleos
if awk -v c="$CARGA" -v n="$NUCLEOS" 'BEGIN {exit !(c > n)}'; then
    alerta "Carga ${CARGA} con ${NUCLEOS} núcleos"
else
    ok "Carga ${CARGA} con ${NUCLEOS} núcleos"
fi

# --- Servicios ---------------------------------------------------------------
echo "Servicios:"
if command -v systemctl > /dev/null 2>&1 && [[ -d /run/systemd/system ]]; then
    for s in $SERVICIOS; do
        if systemctl is-active --quiet "$s"; then
            ok "$s activo"
        else
            alerta "$s NO está activo"
        fi
    done
else
    echo "  (systemd no disponible: se omite la comprobación de servicios)"
fi

echo
if (( ALERTAS > 0 )); then
    echo "Resultado: $ALERTAS alerta(s)."
    exit 1
fi
echo "Resultado: todo correcto."
exit 0
