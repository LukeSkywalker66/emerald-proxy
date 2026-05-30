#!/bin/bash

# 1. Cargamos las variables del .env de la App
source /opt/emerald-erp/.env

# 2. Configuración de rutas locales y nombres
BACKUP_DIR="/tmp/emerald_backups"
FECHA=$(date +%Y-%m-%d_%H%M%S)
BACKUP_NAME="emerald_prod_${FECHA}.dump"
LOCAL_PATH="${BACKUP_DIR}/${BACKUP_NAME}"

# Aseguramos que la carpeta temporal local exista
mkdir -p $BACKUP_DIR

echo "[$(date)] 🚀 Iniciando backup de Emerald ERP..."

# 3. Ejecutamos el pg_dump (Producción)
/usr/bin/docker exec emerald_db pg_dump -U $POSTGRES_USER $POSTGRES_DB -F c > $LOCAL_PATH

# Verificar si el archivo se creó correctamente y no está vacío
if [ -s "$LOCAL_PATH" ]; then
    echo "[$(date)] ✅ Dump creado con éxito: ${BACKUP_NAME} ($(ls -lh $LOCAL_PATH | awk '{print $5}'))"
    
    # 4. Subir a Google Drive usando Rclone
    # El formato es: remote_name:folder_id
    echo "[$(date)] ☁️ Subiendo a Google Drive..."
    /usr/bin/rclone copy $LOCAL_PATH "${DRIVE_REMOTE_NAME}:${DRIVE_FOLDER_ID}"
    
    if [ $? -eq 0 ]; then
        echo "[$(date)] 🎉 Subida a la nube completada con éxito."
    else
        echo "[$(date)] ❌ ERROR: Falló la subida a Google Drive."
    fi
else
    echo "[$(date)] ❌ ERROR: El archivo de dump está vacío o no se creó."
    exit 1
fi

# === REPLICACIÓN EN RED LOCAL (LAN) ===
# El script verifica si la función está activada en el .env
if [ "$LAN_BACKUP_ENABLED" = "true" ]; then
    echo "[$(date)] 🖧 Replicación local activada. Enviando a la LAN..."
    
    # Ejecutamos el envío seguro por SSH/SCP usando las variables
    /usr/bin/scp -i /home/lucas-dev/.ssh/id_ed25519 $LOCAL_PATH ${LAN_SERVER_USER}@${LAN_SERVER_IP}:${LAN_DEST_FOLDER}
    
    if [ $? -eq 0 ]; then
        echo "[$(date)] 💾 Copia en red local (LAN) completada con éxito."
    else
        echo "[$(date)] ⚠️ ADVERTENCIA: Falló la réplica en la LAN. Revisar conexión o llaves SSH."
    fi
else
    echo "[$(date)] 🖧 Réplica local (LAN) desactivada en el .env. Saltando."
fi

# 5. Limpieza y Retención Local (Mantiene el script limpio)
/usr/bin/find $BACKUP_DIR -type f -name "emerald_prod_*.dump" -mtime +$BACKUP_RETENTION_DAYS -delete

# 6. Limpieza y Retención en la Nube
echo "[$(date)] 🧹 Aplicando política de retención en la nube (${BACKUP_RETENTION_DAYS} días)..."
/usr/bin/rclone delete "${DRIVE_REMOTE_NAME}:${DRIVE_FOLDER_ID}" --min-age "${BACKUP_RETENTION_DAYS}d"

echo "[$(date)] 🏁 Proceso de backup finalizado con éxito."

