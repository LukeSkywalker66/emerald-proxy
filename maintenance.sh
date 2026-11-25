#!/bin/bash
# ==============================================================================
# Emerald ERP - Control de mantenimiento programado
#
# Uso:
#   ./maintenance.sh on       # Activa la pantalla de mantenimiento (503)
#   ./maintenance.sh off      # Desactiva la pantalla de mantenimiento
#   ./maintenance.sh status   # Muestra el estado actual
#
# El flag vive en /var/www/maintenance/on (bind mount de ./maintenance).
# Nginx lo chequea por request, por lo que el cambio es inmediato y no
# requiere recargar ni recrear el contenedor.
# ==============================================================================
set -u

CONTAINER="${EMERALD_PROXY_CONTAINER:-emerald_global_proxy}"
FLAG_FILE="/var/www/maintenance/on"
HOST_FLAG="/opt/emerald-proxy/maintenance/on"

flag_active() {
  docker exec "$CONTAINER" sh -c "[ -f $FLAG_FILE ]" >/dev/null 2>&1 \
    || [ -f "$HOST_FLAG" ]
}

cmd="${1:-status}"

case "$cmd" in
  on)
    if docker exec "$CONTAINER" sh -c "mkdir -p $(dirname "$FLAG_FILE") && touch $FLAG_FILE" >/dev/null 2>&1; then
      echo "🟠 Mantenimiento ACTIVADO. La pantalla aparece de inmediato (sin recargar nginx)."
    elif touch "$HOST_FLAG" 2>/dev/null; then
      echo "🟠 Mantenimiento ACTIVADO (vía archivo local)."
    else
      echo "❌ No se pudo activar el mantenimiento. Verificá el acceso a Docker o a $HOST_FLAG" >&2
      exit 1
    fi
    ;;
  off)
    if docker exec "$CONTAINER" rm -f "$FLAG_FILE" >/dev/null 2>&1; then
      echo "🟢 Mantenimiento DESACTIVADO. El tráfico vuelve a los backends."
    elif rm -f "$HOST_FLAG" 2>/dev/null; then
      echo "🟢 Mantenimiento DESACTIVADO (vía archivo local)."
    else
      echo "❌ No se pudo desactivar el mantenimiento." >&2
      exit 1
    fi
    ;;
  status)
    if flag_active; then
      echo "🟠 Estado: mantenimiento ACTIVO."
    else
      echo "🟢 Estado: operación normal (sin mantenimiento)."
    fi
    ;;
  *)
    echo "Uso: $0 {on|off|status}" >&2
    exit 1
    ;;
esac
