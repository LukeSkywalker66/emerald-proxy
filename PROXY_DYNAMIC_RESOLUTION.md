# Resolución dinámica de upstreams en Nginx (fix del 502 tras deploys)

## Problema

Tras un deploy que recrea contenedores, Docker les asigna **IPs nuevas** en la red
`emerald_gateway`. Nginx, con un `proxy_pass` estático como:

```nginx
proxy_pass http://emerald_nginx:80;
```

resuelve el hostname a IP **una sola vez al cargar la configuración**. Si el
contenedor de destino cambia de IP después, nginx sigue apuntando a la IP vieja y
devuelve **502**, hasta que se reinicia el contenedor de nginx.

## Solución

Apuntar `proxy_pass` a una **variable** y declarar un `resolver` apuntando al DNS
de Docker (`127.0.0.11`). Con esto nginx re-resuelve el hostname cada `valid`
segundos y levanta la IP nueva **sin reiniciar nada**.

## Cambio ya aplicado en este repo

[`nginx/default.conf`](nginx/default.conf:1) (nginx interno de cada stack) ya
resuelve `frontend`, `beholder` y `backend` dinámicamente:

```nginx
resolver 127.0.0.11 valid=10s ipv6=off;
set $frontend_upstream http://frontend:80;
set $beholder_upstream http://beholder:5173;
set $backend_upstream  http://backend:8500;

location / { proxy_pass $frontend_upstream; ... }
```

## Cambio aplicado en el Proxy Global (`/opt/emerald-proxy`)

El 502 reportado se originó en el **proxy global**, que apunta a
`emerald_nginx`, `emerald_nginx_staging` y `emerald_nginx_dev`.

En este repo la configuración de nginx se genera con **templates** (mecanismo
`envsubst` de la imagen oficial `nginx:alpine`), no con un `nginx/default.conf`:

- [`nginx/templates-available/emerald.conf.template`](nginx/templates-available/emerald.conf.template:21) (producción)
- [`nginx/templates-available/emerald-test.conf.template`](nginx/templates-available/emerald-test.conf.template:21) (staging)
- [`nginx/templates-available/emerald-dev.conf.template`](nginx/templates-available/emerald-dev.conf.template:21) (desarrollo)

Cada server HTTPS ahora usa resolución dinámica:

```nginx
resolver 127.0.0.11 valid=10s ipv6=off;
set $emerald_prod    http://emerald_nginx:80;         # producción
set $emerald_staging http://emerald_nginx_staging:80; # staging
set $emerald_dev     http://emerald_nginx_dev:80;     # desarrollo

location / {
    proxy_pass $emerald_prod;   # (o $emerald_staging / $emerald_dev)
    # ... headers ...
}
```

Notas de esta implementación:

- El `resolver` va dentro de cada `server` (contexto válido: `http`/`server`/
  `location`); así cada template es autocontenido y funciona aunque solo se
  active un entorno vía symlink.
- Los upstreams (`emerald_nginx:80`, etc.) se inyectan desde `.env`
  (`UPSTREAM_CONTAINER`, `TEST_UPSTREAM_CONTAINER`, `DEV_UPSTREAM_CONTAINER`)
  y `envsubst` los resuelve al arrancar el contenedor.
- Al usar templates, un `nginx -s reload` **no** basta: hay que recrear el
  contenedor para que `envsubst` regenere los `.conf`. Aplicar con:

```bash
cd /opt/emerald-proxy
docker compose up -d --force-recreate proxy
docker exec emerald_global_proxy nginx -t
```

- Después de esto, el reinicio del proxy tras un deploy deja de ser necesario:
  nginx re-resuelve el hostname cada `valid=10s` contra el DNS de Docker
  (`127.0.0.11`).

## Notas

- La directiva `set` debe ir dentro del `server` (o `location`) correspondiente,
  no en `http`.
- Con variables en `proxy_pass`, nginx pasa la URI original tal cual; si el proxy
  global agrega un path específico en el `proxy_pass` (ej. `/monitor/`), hay que
  revisar que la URI siga coincidiendo con lo que espera el backend.
- Después de esto, el reinicio del proxy tras un deploy deja de ser necesario.
