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
