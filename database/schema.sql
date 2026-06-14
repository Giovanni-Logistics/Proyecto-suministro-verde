-- ══════════════════════════════════════════════════════════════════════════════
-- Damu SGC — Esquema de Base de Datos Supabase
-- Instrucciones: Supabase → SQL Editor → New Query → pegar y presionar Run
-- ══════════════════════════════════════════════════════════════════════════════

-- ── 1. Tabla viajes_operativos (Transportistas) ───────────────────────────
--    Almacena: rutas simuladas + escaneos QR de carga
--    distancia_km  → kilómetros calculados por el simulador de ruta
--    costo_diesel  → costo anual de diésel estimado por el simulador
--    cargas_qr_kg  → kilogramos registrados por el escáner QR
CREATE TABLE IF NOT EXISTS public.viajes_operativos (
  id            uuid         NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id       uuid         NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  origen        text,
  destino       text,
  distancia_km  numeric(10,2) NOT NULL DEFAULT 0,
  costo_diesel  numeric(12,2) NOT NULL DEFAULT 0,
  cargas_qr_kg  numeric(10,2) NOT NULL DEFAULT 0,
  created_at    timestamptz  NOT NULL DEFAULT now()
);

-- ── 2. Tabla certificados_rep (Empresas Productoras) ─────────────────────
--    Almacena: declaración REP + evaluación de multa al generar PDF
--    meta_valorizacion_porcentaje → % del slider de la calculadora
--    riesgo_multa_estimado        → 0 si cumple, >0 si hay riesgo Art. 48
CREATE TABLE IF NOT EXISTS public.certificados_rep (
  id                           uuid         NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id                      uuid         NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  categoria                    text         NOT NULL,
  toneladas_declaradas         numeric(10,2) NOT NULL DEFAULT 0,
  meta_valorizacion_porcentaje numeric(5,2)  NOT NULL DEFAULT 0,
  riesgo_multa_estimado        numeric(14,2) NOT NULL DEFAULT 0,
  created_at                   timestamptz  NOT NULL DEFAULT now()
);

-- ── 3. Índices para consultas frecuentes ─────────────────────────────────
CREATE INDEX IF NOT EXISTS idx_viajes_user_id   ON public.viajes_operativos (user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_certs_user_id    ON public.certificados_rep  (user_id, created_at DESC);

-- ── 4. Habilitar Row Level Security ──────────────────────────────────────
ALTER TABLE public.viajes_operativos ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.certificados_rep  ENABLE ROW LEVEL SECURITY;

-- ── 5. Políticas RLS — viajes_operativos ─────────────────────────────────
CREATE POLICY "viajes_select_own"
  ON public.viajes_operativos FOR SELECT
  USING (user_id = auth.uid());

CREATE POLICY "viajes_insert_own"
  ON public.viajes_operativos FOR INSERT
  WITH CHECK (user_id = auth.uid());

CREATE POLICY "viajes_delete_own"
  ON public.viajes_operativos FOR DELETE
  USING (user_id = auth.uid());

-- ── 6. Políticas RLS — certificados_rep ──────────────────────────────────
CREATE POLICY "certs_select_own"
  ON public.certificados_rep FOR SELECT
  USING (user_id = auth.uid());

CREATE POLICY "certs_insert_own"
  ON public.certificados_rep FOR INSERT
  WITH CHECK (user_id = auth.uid());

CREATE POLICY "certs_delete_own"
  ON public.certificados_rep FOR DELETE
  USING (user_id = auth.uid());

-- ════════════════════════════════════════════════════════════════════════════
-- MAPA OPERATIVO — Tablas de la red de recolección REP
-- ════════════════════════════════════════════════════════════════════════════

-- ── 7. Tabla puntos_acopio ────────────────────────────────────────────────
--    Puntos físicos de recolección de la red Damu SGC.
--    Estado visual = carga_actual_kg / capacidad_total_kg × 100:
--      < 50% → LIBRE (verde) · 50–80% → MEDIO (amarillo) · > 80% → CRÍTICO (rojo)
CREATE TABLE IF NOT EXISTS public.puntos_acopio (
  id                 uuid          NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  nombre             text          NOT NULL,
  lat                numeric(10,7) NOT NULL,
  lng                numeric(10,7) NOT NULL,
  categoria          text          NOT NULL, -- envases | neumaticos | pilas | raee | aceites
  capacidad_total_kg numeric(10,2) NOT NULL DEFAULT 1000,
  carga_actual_kg    numeric(10,2) NOT NULL DEFAULT 0,
  activo             boolean       NOT NULL DEFAULT true,
  created_at         timestamptz   NOT NULL DEFAULT now()
);

-- ── 8. Tabla flota_vehiculos ──────────────────────────────────────────────
--    Vehículos registrados por cada transportista en la plataforma.
--    lat/lng = posición actual (nullable hasta el primer viaje).
CREATE TABLE IF NOT EXISTS public.flota_vehiculos (
  id              uuid          NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id         uuid          NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  patente         text          NOT NULL,
  conductor       text,
  tipo            text          NOT NULL DEFAULT 'camion', -- camion | furgon | camion_mayor
  lat             numeric(10,7),
  lng             numeric(10,7),
  carga_actual_kg numeric(10,2) NOT NULL DEFAULT 0,
  capacidad_kg    numeric(10,2) NOT NULL DEFAULT 5000,
  destino         text,
  activo          boolean       NOT NULL DEFAULT true,
  updated_at      timestamptz   NOT NULL DEFAULT now()
);

-- ── 9. Índices Mapa Operativo ─────────────────────────────────────────────
CREATE INDEX IF NOT EXISTS idx_acopio_activo ON public.puntos_acopio   (activo, carga_actual_kg DESC);
CREATE INDEX IF NOT EXISTS idx_flota_user    ON public.flota_vehiculos  (user_id, activo);

-- ── 10. RLS — puntos_acopio ───────────────────────────────────────────────
--    Lectura pública para todos los usuarios autenticados (datos de red compartidos).
--    Escritura solo vía service_role (administración de la plataforma).
ALTER TABLE public.puntos_acopio ENABLE ROW LEVEL SECURITY;

CREATE POLICY "acopio_select_authed"
  ON public.puntos_acopio FOR SELECT
  TO authenticated
  USING (activo = true);

-- ── 11. RLS — flota_vehiculos ─────────────────────────────────────────────
ALTER TABLE public.flota_vehiculos ENABLE ROW LEVEL SECURITY;

CREATE POLICY "flota_select_own"
  ON public.flota_vehiculos FOR SELECT
  USING (user_id = auth.uid());

CREATE POLICY "flota_insert_own"
  ON public.flota_vehiculos FOR INSERT
  WITH CHECK (user_id = auth.uid());

CREATE POLICY "flota_update_own"
  ON public.flota_vehiculos FOR UPDATE
  USING (user_id = auth.uid());

CREATE POLICY "flota_delete_own"
  ON public.flota_vehiculos FOR DELETE
  USING (user_id = auth.uid());

-- ── 12. Datos de demostración — Puntos de Acopio Región Metropolitana ─────
--    Ejecutar en SQL Editor para activar el Mapa Operativo con datos reales.
--    Los porcentajes están calculados en el comentario: carga/capacidad × 100
INSERT INTO public.puntos_acopio
  (nombre, lat, lng, categoria, capacidad_total_kg, carga_actual_kg) VALUES
  ('Maipú Centro — Punto REP',        -33.5108, -70.7581, 'envases',    2000, 1720),  -- 86% CRÍTICO
  ('Pudahuel Norte — Galpón REP',     -33.4071, -70.7450, 'raee',       1500, 1275),  -- 85% CRÍTICO
  ('La Florida Sur — Eco-Punto',      -33.5173, -70.5991, 'neumaticos', 3000, 2580),  -- 86% CRÍTICO
  ('Puente Alto — Eco-Punto Sur',     -33.6084, -70.5757, 'neumaticos', 2200, 1980),  -- 90% CRÍTICO
  ('Ñuñoa Industrial — Centro REP',   -33.4563, -70.5990, 'aceites',    1200,  660),  -- 55% MEDIO
  ('Peñalolén — Punto Reciclaje',    -33.4724, -70.5311, 'pilas',        800,  432),  -- 54% MEDIO
  ('San Bernardo — Acopio REP',       -33.5986, -70.7061, 'envases',    2500, 1000),  -- 40% LIBRE
  ('Quilicura — Centro Valorización', -33.3622, -70.7397, 'raee',       1800,  450);  -- 25% LIBRE
