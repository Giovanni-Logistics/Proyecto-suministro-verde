# Damu SGC — Plataforma de Trazabilidad Ley REP

Plataforma web para la gestión de logística inversa y cumplimiento de la **Ley REP (Ley 20.920)** en Chile. Conecta a empresas productoras con socios transportistas para asegurar la trazabilidad, valorización de residuos y reportes normativos.

## Estructura del proyecto

```
/
├── index.html       # Landing page, portal de login y calculadora Eco-Ticket
└── simulador.html   # Dashboard de KPIs y simulador de rentabilidad Ley REP
```

## Flujo de usuario

1. El usuario entra por **`index.html`** (landing page).
2. Inicia sesión con su RUT y contraseña corporativa.
3. Desde el panel de perfil accede al **Simulador de Rentabilidad Pro** → `simulador.html`.
4. Desde `simulador.html` puede volver al portal con el botón **← Volver al Portal**.

## Páginas

| Archivo | Descripción |
|---|---|
| `index.html` | Landing page comercial, mapa operativo (Google My Maps), portal de autenticación y calculadora Eco-Ticket con las 6 categorías de la Ley REP. |
| `simulador.html` | Hub de logística inversa: simulador de rentabilidad, KPIs de valorización de residuos, CO₂e mitigado y análisis de costos operativos. |

## Tecnologías

- HTML5 + CSS3
- [Tailwind CSS](https://tailwindcss.com/) (CDN en `index.html`, subconjunto estático en `simulador.html`)
- JavaScript vanilla (sin dependencias externas)
- Google My Maps (iframe embebido)

## Uso local

Basta con abrir `index.html` en cualquier navegador moderno. No requiere servidor ni instalación.

```bash
# Con Python (opcional)
python -m http.server 8080
# Luego abre: http://localhost:8080
```

## Credenciales de demo

| Campo | Valor |
|---|---|
| RUT Empresa | `76.234.567-K` |
| Contraseña | `123456` |

## Categorías Ley REP cubiertas

1. Envases y embalajes — $18.500/t
2. Neumáticos fuera de uso — $45.000/t
3. Aparatos eléctricos y electrónicos (RAEE) — $80.000/t
4. Pilas y baterías — $85.000/t
5. Aceites lubricantes usados — $25.000/t
6. Textiles — $15.000/t
