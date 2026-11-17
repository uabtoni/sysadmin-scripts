#!/usr/bin/env bash
#
# backup.sh — Copia de seguridad comprimida de un directorio, con rotación y log.
#
# Uso:
#   ./backup.sh <directorio_origen> <directorio_destino> [dias_a_conservar]
#
# Ejemplo:
#   ./backup.sh /etc /srv/backups 7
#
# Qué hace:
#   1. Comprueba que el origen existe y que hay espacio en el destino.
#   2. Crea un .tar.gz con fecha y hora en el nombre (p. ej. etc_2026-11-17_0300.tar.gz).
#   3. Verifica que el fichero generado no está corrupto.
#   4. Borra las copias más antiguas que el número de días indicado (rotación).
#   5. Registra todo en un log y sale con código de error si algo falla
#      (así cron o una herramienta de monitorización pueden detectarlo).
#
# Programarlo con cron (cada día a las 3:00):
#   0 3 * * * /opt/scripts/backup.sh /etc /srv/backups 7
#
# Autor: Toni Susany

set -euo pipefail   # Sale ante cualquier error, variable no definida o fallo en una tubería

# --- Parámetros --------------------------------------------------------------
ORIGEN="${1:-}"
DESTINO="${2:-}"
DIAS="${3:-7}"
LOG="${BACKUP_LOG:-/var/log/backup.log}"

# --- Funciones ---------------------------------------------------------------
log() {
    # Escribe en pantalla y en el log con marca de tiempo
    echo "$(date '+%Y-%m-%d %H:%M:%S') [$1] $2" | tee -a "$LOG"
}

uso() {
    echo "Uso: $0 <directorio_origen> <directorio_destino> [dias_a_conservar]"
    exit 1
}

# --- Validaciones ------------------------------------------------------------
[[ -z "$ORIGEN" || -z "$DESTINO" ]] && uso

if [[ ! -d "$ORIGEN" ]]; then
    log "ERROR" "El directorio de origen '$ORIGEN' no existe."
    exit 2
fi

if ! [[ "$DIAS" =~ ^[0-9]+$ ]]; then
    log "ERROR" "Los días a conservar deben ser un número entero (recibido: '$DIAS')."
    exit 1
fi

mkdir -p "$DESTINO"

# Espacio libre en destino (KB) frente al tamaño del origen (KB)
LIBRE=$(df -Pk "$DESTINO" | awk 'NR==2 {print $4}')
NECESARIO=$(du -sk "$ORIGEN" | awk '{print $1}')
if (( NECESARIO > LIBRE )); then
    log "ERROR" "Espacio insuficiente en $DESTINO: necesarios ${NECESARIO} KB, libres ${LIBRE} KB."
    exit 3
fi

# --- Copia -------------------------------------------------------------------
NOMBRE="$(basename "$ORIGEN")_$(date '+%Y-%m-%d_%H%M').tar.gz"
FICHERO="$DESTINO/$NOMBRE"

log "INFO" "Iniciando copia de '$ORIGEN' en '$FICHERO'."
tar -czf "$FICHERO" -C "$(dirname "$ORIGEN")" "$(basename "$ORIGEN")"

# --- Verificación ------------------------------------------------------------
if tar -tzf "$FICHERO" > /dev/null; then
    TAMANO=$(du -h "$FICHERO" | cut -f1)
    log "OK" "Copia verificada: $NOMBRE ($TAMANO)."
else
    log "ERROR" "La copia $NOMBRE está corrupta."
    exit 4
fi

# --- Rotación ----------------------------------------------------------------
BORRADOS=$(find "$DESTINO" -maxdepth 1 -name "$(basename "$ORIGEN")_*.tar.gz" -mtime +"$DIAS" -print -delete | wc -l)
log "INFO" "Rotación: $BORRADOS copia(s) con más de $DIAS días eliminada(s)."

exit 0
