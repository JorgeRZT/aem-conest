# AEM Conest

<img src="Resources/AppIcon.svg" width="128" align="right" alt="AEM Conest icon">

App de macOS para revisar logs de CDN de **AEM as a Cloud Service**: limpia el tráfico
(bots, recursos estáticos, rutas internas) y cuenta peticiones de contenido por día,
dominio o rango de fechas. Arrastra uno o varios ficheros (`.csv`, `.log`, `.txt`…) y
obtén los resultados sin usar la terminal. Está pensada para ficheros de varios gigas.

> Los resultados son **recuentos aproximados de peticiones** (no visitantes ni sesiones)
> basados en filtros de texto. No esperes una coincidencia exacta con una métrica oficial
> de uso o facturación.

## Secciones

- **Dashboard**: analiza uno o varios ficheros en una sola pasada y permite filtrar por
  fechas y dominios al instante. Incluye gráfica por día (apilable por dominio), top de
  dominios, mapa de calor día × dominio, tablas ordenables y exportación a CSV.
- **Procesar**: ejecuta el flujo de scripts sobre los ficheros arrastrados y muestra el
  comando exacto y la salida de cada paso.
- **Flujo**: lista ordenada de pasos (script + argumentos). Se pueden reordenar,
  desactivar, borrar y añadir. Variables: `{input}`, `{cleaned}`, `{dir}`, `{name}`,
  `{start}`, `{end}`.
- **Scripts**: editor de los `.sh`. Puedes crear scripts nuevos y añadirlos al flujo.

Los scripts y el flujo se guardan en `~/Library/Application Support/AEM Conest/`.

## Qué hace la limpieza (`clean.sh`)

Se descartan las líneas que coinciden (sin distinguir mayúsculas, en cualquier parte de la
línea) con:

- **Bots, crawlers, monitorización, proxies e IA**: Googlebot, Bingbot, AhrefsBot, SemrushBot,
  Applebot, ClaudeBot, ChatGPT, Perplexity, StatusCake, SiteImprove, etc.
- **Rutas internas de AEM**: `/etc.clientlibs/`, `/api/graphql`, `/content/experience-fragments/`.
- **Recursos**: imágenes, vídeo, `.css`, `.js`, `.mjs`.

Después solo se conservan las líneas con `GET,200` y `html` (sensible a mayúsculas). La lista
completa está en [`default-scripts/clean.sh`](default-scripts/clean.sh); estos filtros no
garantizan la eliminación de todo el tráfico automatizado.

## Formato de entrada esperado

- La fecha ocupa los caracteres 2 a 11 de cada línea, en formato `YYYY-MM-DD`
  (por ejemplo, una línea que empieza por `"2026-09-21`).
- El dominio es el último campo separado por comas.
- Cada línea es una petición, sin cabecera. No es un parser CSV completo (no gestiona
  comillas generales ni registros multilínea).

## Requisitos

- macOS 14 o superior. Usa solo herramientas del sistema (`bash`, `grep`, `awk`, `sort`, `perl`).
- Para compilar: Xcode / Swift 5.9+.

## Compilar

```bash
./build.sh   # genera dist/AEM Conest.app (universal) y dist/AEM-Conest-1.0.dmg
```

La app resultante va firmada ad-hoc. En otro Mac, macOS pedirá confirmación la primera vez:
clic derecho → **Abrir**, o *Ajustes del Sistema → Privacidad y seguridad → Abrir igualmente*.

Para firmar con Developer ID y notarizar, consulta el encabezado de `build.sh`
(`SIGN_IDENTITY` y `NOTARY_PROFILE`).

## Estructura

```
Sources/CDNFiltering/   código SwiftUI (Dashboard, Procesar, Flujo, Scripts)
default-scripts/        scripts originales; tools/gen_defaults.sh los embebe en la app
Resources/AppIcon.svg   icono; tools/make_icon.sh genera el .icns
build.sh                compila, empaqueta, firma y crea el .dmg
```

## Licencia

[MIT](LICENSE)
