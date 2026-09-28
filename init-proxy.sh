#!/bin/bash
# ==============================================================================
# Emerald ERP - Proxy Bootstrap Sequence (Zero-Touch / Agnostic)
# ==============================================================================
set -e

echo "🟢 [Emerald Tech Lead] Iniciando Bootstrap de Infraestructura SSL..."

# 1. Extracción segura de variables de entorno
ENV_FILE=".env"
if [ ! -f "$ENV_FILE" ]; then
  echo "❌ Error CRÍTICO: Archivo .env no encontrado en el proxy. Abortando."
  exit 1
fi

extract_env_var() {
  local var_name=$1
  grep "^${var_name}=" "$ENV_FILE" | head -n 1 | cut -d '=' -f 2- | sed -e "s/^['\"]//" -e "s/['\"]$//" -e 's/[[:space:]]*#.*$//'
}

DOMAIN=$(extract_env_var "DOMAIN")
EMAIL=$(extract_env_var "EMAIL")
DATA_PATH="./certbot/conf"

if [ -z "$DOMAIN" ] || [ -z "$EMAIL" ]; then
  echo "❌ Error CRÍTICO: DOMAIN o EMAIL faltantes en .env."
  exit 1
fi

echo "⚙️  Entorno detectado: $DOMAIN"

# 2. Verificar si ya existe un certificado real
if [ -d "$DATA_PATH/live/$DOMAIN" ]; then
    echo "✅ Certificados ya existentes. Levantando proxy global..."
    docker compose up -d
    exit 0
fi

# 3. Generar Certificado Dummy (Para que Nginx arranque sin pánico)
echo "⚠️ Generando certificado dummy temporal para engañar a Nginx..."
mkdir -p "$DATA_PATH/live/$DOMAIN"
openssl req -x509 -nodes -newkey rsa:2048 -days 1 \
  -keyout "$DATA_PATH/live/$DOMAIN/privkey.pem" \
  -out "$DATA_PATH/live/$DOMAIN/fullchain.pem" \
  -subj "/CN=$DOMAIN" > /dev/null 2>&1

# 4. Levantar Nginx con el Dummy
echo "🏗️ Levantando Nginx en modo inicialización..."
docker compose up -d proxy
echo "⏳ Esperando 5 segundos para estabilización del socket..."
sleep 5

# 5. Forzar la emisión del certificado real
echo "🔒 Solicitando certificado criptográfico a Let's Encrypt..."
docker compose run --rm --entrypoint "\
  certbot certonly --webroot -w /var/www/certbot \
  -d $DOMAIN \
  --email $EMAIL \
  --rsa-key-size 4096 \
  --agree-tos \
  --force-renewal \
  --non-interactive" certbot

# 6. Recargar Nginx
echo "♻️ Recargando Nginx con validación estricta..."
docker exec emerald_global_proxy nginx -s reload

echo "✅ [Emerald Tech Lead] Proxy desplegado y blindado. Idempotencia lograda."
