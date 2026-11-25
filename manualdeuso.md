# Manual de uso — Emerald Global Proxy

Proxy global basado en `nginx:alpine` que genera su configuración con **templates**
(`envsubst`) y enruta los tres entornos: producción, staging y desarrollo.

## 1. Activar / desactivar entornos (symlinks)

Los templates viven en `nginx/templates-available/` y se activan creando un
symlink dentro de `nginx/templates-enabled/` (el contenedor lo ve como
`/etc/nginx/templates`).

```bash
cd /opt/emerald-proxy/nginx

# Activar
ln -s ../templates-available/emerald.conf.template      ./templates-enabled/emerald.conf.template
ln -s ../templates-available/emerald-test.conf.template ./templates-enabled/emerald-test.conf.template
ln -s ../templates-available/emerald-dev.conf.template  ./templates-enabled/emerald-dev.conf.template

# Desactivar
rm ./templates-enabled/emerald-dev.conf.template
```

## 2. Aplicar cambios en los templates

La imagen oficial de nginx procesa los templates con `envsubst` **al arrancar el
contenedor**. Un `nginx -s reload` **NO** regenera los `.conf`. Para aplicar
cambios:

```bash
cd /opt/emerald-proxy
docker compose up -d --force-recreate proxy
docker exec emerald_global_proxy nginx -t
```

## 3. Páginas de error personalizadas

La carpeta [`error-pages/`](error-pages/) se monta en `/var/www/error-pages` y
contiene:

| Página | Archivo | Cuándo aparece |
|--------|---------|----------------|
| 403 | [`403.html`](error-pages/403.html) | Acceso denegado |
| 404 | [`404.html`](error-pages/404.html) | Página no encontrada |
| 413 | [`413.html`](error-pages/413.html) | Archivo mayor a 20 MB |
| 500 | [`500.html`](error-pages/500.html) | Error interno del backend |
| 502 | [`502.html`](error-pages/502.html) | Backend caído / IP vieja |
| 503 | [`503.html`](error-pages/503.html) | Servicio no disponible |
| 504 | [`504.html`](error-pages/504.html) | Backend agotó el tiempo |
| Mantenimiento | [`maintenance.html`](error-pages/maintenance.html) | Flag de mantenimiento activo |

Las imágenes viven en [`error-pages/assets/`](error-pages/assets/) (en formato
**WebP** para que pesen poco) y los estilos compartidos en
[`error-pages/assets/error.css`](error-pages/assets/error.css).

### Cómo funciona la selección aleatoria de imágenes

Cada página HTML elige al azar una imagen de su lista al cargar. Por ejemplo,
[`502.html`](error-pages/502.html) alterna entre `502.webp` y `502-2.webp`, y
[`500.html`](error-pages/500.html) entre `500.webp` y `500-2.webp`. Para agregar
una imagen nueva:

1. Convertila a WebP y copiala a `error-pages/assets/` (por ejemplo `502-3.webp`).
2. Agregala al array del script en la página correspondiente:

```html
<script>
  var images = [
    '/error-pages/assets/502.webp',
    '/error-pages/assets/502-2.webp',
    '/error-pages/assets/502-3.webp'   <!-- nueva -->
  ];
  ...
</script>
```

No hace falta tocar nginx: los assets son estáticos y se sirven desde
`/error-pages/assets/`.

### Optimizar / comprimir imágenes (WebP)

Las ilustraciones originales (PNG/JPG de 1–3 MB) se comprimieron a WebP con
calidad 85, quedando en ~120–240 KB cada una. Para convertir imágenes nuevas:

```bash
cd /opt/emerald-proxy/error-pages/assets
docker run --rm -v "$PWD:/imgs" --entrypoint /bin/sh dpokidov/imagemagick -c '
  cd /imgs
  magick imagen.png -strip -quality 85 imagen.webp
  # Si viene muy grande, reducir a 1408x768 antes de convertir:
  # magick imagen.jpg -strip -resize 1408x768 -quality 85 imagen.webp
'
```

`quality` va de 0 a 100 (85 es un buen equilibrio; subir a 90 si se ve borroso).
Después actualizá la referencia en el HTML correspondiente.

> Nota: `proxy_intercept_errors on` hace que nginx reemplace las páginas de error
> del backend (incluidos los 404) por las del proxy. Si un backend expone una API
> que necesita devolver 404 en JSON, quitar la línea `error_page 404` del template
> correspondiente.

## 4. Mantenimiento programado (producción)

Solo el template de producción ([`emerald.conf.template`](nginx/templates-available/emerald.conf.template:1))
incluye el chequeo de mantenimiento. El flag es el archivo `maintenance/on`
(montado en `/var/www/maintenance/on`).

### Activar / desactivar

```bash
cd /opt/emerald-proxy

./maintenance.sh on      # activa la pantalla de mantenimiento (503)
./maintenance.sh off     # la desactiva
./maintenance.sh status  # muestra el estado
```

El cambio es **inmediato y sin recargar nginx**: el `if (-f /var/www/maintenance/on)`
se evalúa por request. La página de mantenimiento se recarga sola cada 15 s, por
lo que cuando se quita el flag los usuarios vuelven solos a la app.

### Integración con CI del repo de producción

En el pipeline, al iniciar el deploy (antes de recrear contenedores):

```bash
# Si el CI corre en el host del proxy
touch /opt/emerald-proxy/maintenance/on

# O si el CI tiene acceso a Docker
docker exec emerald_global_proxy touch /var/www/maintenance/on
```

Y al terminar el deploy:

```bash
rm -f /opt/emerald-proxy/maintenance/on
# o
docker exec emerald_global_proxy rm -f /var/www/maintenance/on
```

> El flag está pensado para producción. Si se quisiera usar también en staging o
> dev, replicar el bloque `if (-f /var/www/maintenance/on) { ... }` (con su propia
> variable de mapa) en el template correspondiente.

## 5. Resolución dinámica de upstreams

El proxy usa `resolver 127.0.0.11 valid=10s ipv6=off;` y `proxy_pass` a variable
para re-resolver los contenedores cada 10 s. Detalles en
[`PROXY_DYNAMIC_RESOLUTION.md`](PROXY_DYNAMIC_RESOLUTION.md:1).
