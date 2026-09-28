#!/bin/bash
# ==============================================================================
# Emerald ERP - Proxy Bootstrap Sequence (Zero-Touch / Multi-Domain / Idempotent)
# ==============================================================================
set -e

# Garantizamos que el script se ejecute desde la raíz del proyecto (donde viven
# docker-compose.yml y .env), sin importar el directorio desde el que se invoque.
cd "$(dirname "$0")"

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
TEST_DOMAIN=$(extract_env_var "TEST_DOMAIN")
DEV_DOMAIN=$(extract_env_var "DEV_DOMAIN")
DATA_PATH="./certbot/conf"
TEMPLATES_DIR="./nginx/templates-enabled"

if [ -z "$DOMAIN" ] || [ -z "$EMAIL" ]; then
  echo "❌ Error CRÍTICO: DOMAIN o EMAIL faltantes en .env."
  exit 1
fi

# 2. Determinar qué dominios están habilitados según los templates activos.
#    Solo bootstrapamos dominios con template habilitado para no gastar cuota
#    de Let's Encrypt en dominios que Nginx no sirve.
template_enabled() {
  [ -e "$TEMPLATES_DIR/$1" ]
}

DOMAINS=()
if template_enabled "emerald.conf.template"; then
  DOMAINS+=("$DOMAIN")
fi
if template_enabled "emerald-test.conf.template"; then
  if [ -z "$TEST_DOMAIN" ]; then
    echo "❌ Error CRÍTICO: emerald-test.conf.template habilitado pero TEST_DOMAIN vacío."
    exit 1
  fi
  DOMAINS+=("$TEST_DOMAIN")
fi
if template_enabled "emerald-dev.conf.template"; then
  if [ -z "$DEV_DOMAIN" ]; then
    echo "❌ Error CRÍTICO: emerald-dev.conf.template habilitado pero DEV_DOMAIN vacío."
    exit 1
  fi
  DOMAINS+=("$DEV_DOMAIN")
fi

if [ ${#DOMAINS[@]} -eq 0 ]; then
  echo "❌ Error CRÍTICO: No hay templates habilitados en $TEMPLATES_DIR."
  exit 1
fi

echo "🔍 Dominios habilitados: ${DOMAINS[*]}"

# 3. Helpers que operan dentro del contenedor (como root) para evitar problemas
#    de permisos en certbot/conf (propiedad root:root 700).
cert_real() {
  local domain=$1
  docker run --rm --entrypoint sh \
    -v "$(pwd)/certbot/conf:/etc/letsencrypt" \
    certbot/certbot -c \
    'test -f "/etc/letsencrypt/renewal/$1.conf" && test -f "/etc/letsencrypt/live/$1/fullchain.pem"' \
    sh "$domain"
}

create_dummy() {
  local domain=$1
  echo "⚠️  Generando certificado dummy temporal para $domain..."
  docker run --rm --entrypoint sh \
    -v "$(pwd)/certbot/conf:/etc/letsencrypt" \
    -w /etc/letsencrypt \
    certbot/certbot -c \
    'mkdir -p "live/$1" && openssl req -x509 -nodes -newkey rsa:2048 -days 1 \
      -keyout "live/$1/privkey.pem" \
      -out "live/$1/fullchain.pem" \
      -subj "/CN=$1" >/dev/null 2>&1' \
    sh "$domain"
}

# 4. Asegurar un certificado (dummy o real) para cada dominio habilitado,
#    para que Nginx siempre pueda arrancar.
PENDING=()
for domain in "${DOMAINS[@]}"; do
  if cert_real "$domain"; then
    echo "✅ Certificado real ya existente para $domain."
  else
    echo "ℹ️  No hay certificado real para $domain."
    create_dummy "$domain"
    PENDING+=("$domain")
  fi
done

# 5. Si todos los certificados ya existían, solo levantamos el proxy.
if [ ${#PENDING[@]} -eq 0 ]; then
  echo "✅ Certificados ya existentes. Levantando proxy global..."
  docker compose up -d
  exit 0
fi

# 6. Levantar Nginx con los dummies.
echo "🏗️  Levantando Nginx en modo inicialización (dummies)..."
docker compose up -d --force-recreate proxy
echo "⏳ Esperando 5 segundos para estabilización del socket..."
sleep 5

# 7. Emitir el certificado real para cada dominio pendiente.
for domain in "${PENDING[@]}"; do
  echo "🔒 Solicitando certificado a Let's Encrypt para $domain..."
  docker run --rm \
    -v "$(pwd)/certbot/conf:/etc/letsencrypt" \
    -v "$(pwd)/certbot/www:/var/www/certbot" \
    certbot/certbot certonly --webroot -w /var/www/certbot \
    -d "$domain" \
    --email "$EMAIL" \
    --rsa-key-size 4096 \
    --agree-tos \
    --force-renewal \
    --non-interactive
done

# 8. Recargar Nginx con los certificados reales.
echo "♻️  Recargando Nginx con validación estricta..."
docker exec emerald_global_proxy nginx -s reload

# 9. Dejamos corriendo también el servicio de renovación periódica de certbot.
docker compose up -d

echo "✅ [Emerald Tech Lead] Proxy desplegado y blindado. Idempotencia lograda."
