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
DROP POLICY IF EXISTS "viajes_select_own"  ON public.viajes_operativos;
DROP POLICY IF EXISTS "viajes_insert_own"  ON public.viajes_operativos;
DROP POLICY IF EXISTS "viajes_delete_own"  ON public.viajes_operativos;

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
DROP POLICY IF EXISTS "certs_select_own"   ON public.certificados_rep;
DROP POLICY IF EXISTS "certs_insert_own"   ON public.certificados_rep;
DROP POLICY IF EXISTS "certs_delete_own"   ON public.certificados_rep;

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

DROP POLICY IF EXISTS "acopio_select_authed" ON public.puntos_acopio;
CREATE POLICY "acopio_select_authed"
  ON public.puntos_acopio FOR SELECT
  TO authenticated
  USING (activo = true);

-- ── 11. RLS — flota_vehiculos ─────────────────────────────────────────────
ALTER TABLE public.flota_vehiculos ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "flota_select_own"  ON public.flota_vehiculos;
DROP POLICY IF EXISTS "flota_insert_own"  ON public.flota_vehiculos;
DROP POLICY IF EXISTS "flota_update_own"  ON public.flota_vehiculos;
DROP POLICY IF EXISTS "flota_delete_own"  ON public.flota_vehiculos;

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

-- ════════════════════════════════════════════════════════════════════════════
-- PERFILES DE ROL — Soporte para usuarios con múltiples roles
-- ════════════════════════════════════════════════════════════════════════════

-- ── 12. Tabla perfiles ────────────────────────────────────────────────────
--    Almacena los roles habilitados por usuario. Un mismo usuario puede tener
--    una fila para 'productor' y otra para 'transportista', habilitando el
--    selector de rol en el login sin depender de user_metadata (que es fijo
--    desde el signup y no cambia al iniciar sesión con un perfil distinto).
--
--    Flujo:
--      • Signup → se inserta la fila inicial con el rol del registro (trigger).
--      • Login  → el client usa selectedRole; esta tabla permite validar en
--                 el futuro que el usuario tiene ese rol habilitado.
--      • Admin  → puede agregar una segunda fila para habilitar el otro rol.
CREATE TABLE IF NOT EXISTS public.perfiles (
  id         uuid        NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id    uuid        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  rol        text        NOT NULL CHECK (rol IN ('productor', 'transportista')),
  activo     boolean     NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (user_id, rol)
);

CREATE INDEX IF NOT EXISTS idx_perfiles_user ON public.perfiles (user_id, activo);

-- RLS: cada usuario solo ve y gestiona sus propias filas
ALTER TABLE public.perfiles ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "perfiles_select_own"  ON public.perfiles;
DROP POLICY IF EXISTS "perfiles_insert_own"  ON public.perfiles;
DROP POLICY IF EXISTS "perfiles_update_own"  ON public.perfiles;

CREATE POLICY "perfiles_select_own"
  ON public.perfiles FOR SELECT
  USING (user_id = auth.uid());

CREATE POLICY "perfiles_insert_own"
  ON public.perfiles FOR INSERT
  WITH CHECK (user_id = auth.uid());

CREATE POLICY "perfiles_update_own"
  ON public.perfiles FOR UPDATE
  USING (user_id = auth.uid());

-- Trigger: al crear un usuario, insertar automáticamente su perfil inicial
--          tomando el rol desde raw_user_meta_data (guardado en signup).
CREATE OR REPLACE FUNCTION public._on_new_user_insert_perfil()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  _rol text;
BEGIN
  _rol := COALESCE(
    NEW.raw_user_meta_data ->> 'role',
    'productor'   -- default si el signup no incluyó rol
  );
  -- solo insertar si el valor es válido
  IF _rol IN ('productor', 'transportista') THEN
    INSERT INTO public.perfiles (user_id, rol)
    VALUES (NEW.id, _rol)
    ON CONFLICT (user_id, rol) DO NOTHING;
  END IF;
  RETURN NEW;
END;
$$;

CREATE OR REPLACE TRIGGER trg_new_user_perfil
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public._on_new_user_insert_perfil();

-- ── 13. Datos de demostración — Puntos de Acopio Región Metropolitana ─────
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

-- ════════════════════════════════════════════════════════════════════════════
-- FASE 1 — Modelo relacional Empresa ↔ Transportista ↔ Red de Acopio
-- ════════════════════════════════════════════════════════════════════════════
-- Flujo de datos:
--   1. Productor se registra → trigger auto-crea su empresa
--   2. Productor comparte su codigo_invitacion con transportistas
--   3. Transportista ingresa el código → se inserta en transportistas_empresa
--   4. Todos los registros operativos usan empresa_id como eje de visibilidad
-- ════════════════════════════════════════════════════════════════════════════

-- ── 14. Tabla empresas ────────────────────────────────────────────────────
--    Una empresa por productor (MVP). codigo_invitacion = código para unirse.
CREATE TABLE IF NOT EXISTS public.empresas (
  id                uuid        NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  nombre            text        NOT NULL,
  rut               text,
  codigo_invitacion text        UNIQUE DEFAULT upper(substring(replace(gen_random_uuid()::text, '-', ''), 1, 8)),
  user_id_productor uuid        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  activo            boolean     NOT NULL DEFAULT true,
  created_at        timestamptz NOT NULL DEFAULT now(),
  UNIQUE (user_id_productor)
);

-- ── 15. Tabla transportistas_empresa ──────────────────────────────────────
--    Vínculo N:M. user_id_transportista es la FK al usuario transportista.
--    El transportista se auto-inserta usando el codigo_invitacion del productor.
CREATE TABLE IF NOT EXISTS public.transportistas_empresa (
  id                    uuid        NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id_transportista uuid        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  empresa_id            uuid        NOT NULL REFERENCES public.empresas(id) ON DELETE CASCADE,
  activo                boolean     NOT NULL DEFAULT true,
  created_at            timestamptz NOT NULL DEFAULT now(),
  UNIQUE (user_id_transportista, empresa_id)
);

-- ── 16. empresa_id en tablas operativas ───────────────────────────────────
--    Nullable → los datos pre-FASE1 siguen visibles con las políticas "own".
ALTER TABLE public.certificados_rep  ADD COLUMN IF NOT EXISTS empresa_id uuid REFERENCES public.empresas(id);
ALTER TABLE public.viajes_operativos ADD COLUMN IF NOT EXISTS empresa_id uuid REFERENCES public.empresas(id);
ALTER TABLE public.flota_vehiculos   ADD COLUMN IF NOT EXISTS empresa_id uuid REFERENCES public.empresas(id);
ALTER TABLE public.puntos_acopio     ADD COLUMN IF NOT EXISTS empresa_id uuid REFERENCES public.empresas(id);

-- ── 17. Índices ───────────────────────────────────────────────────────────
CREATE INDEX IF NOT EXISTS idx_empresas_productor  ON public.empresas             (user_id_productor);
CREATE INDEX IF NOT EXISTS idx_empresas_codigo     ON public.empresas             (codigo_invitacion);
CREATE INDEX IF NOT EXISTS idx_te_transportista    ON public.transportistas_empresa (user_id_transportista, activo);
CREATE INDEX IF NOT EXISTS idx_te_empresa          ON public.transportistas_empresa (empresa_id, activo);
CREATE INDEX IF NOT EXISTS idx_viajes_empresa      ON public.viajes_operativos    (empresa_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_certs_empresa       ON public.certificados_rep     (empresa_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_flota_empresa       ON public.flota_vehiculos      (empresa_id, activo);
CREATE INDEX IF NOT EXISTS idx_acopio_empresa      ON public.puntos_acopio        (empresa_id, activo);

-- ── 18. RLS — empresas ────────────────────────────────────────────────────
ALTER TABLE public.empresas ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "empresa_select_own"            ON public.empresas;
DROP POLICY IF EXISTS "empresa_insert_own"            ON public.empresas;
DROP POLICY IF EXISTS "empresa_update_own"            ON public.empresas;
DROP POLICY IF EXISTS "empresa_select_transportista"  ON public.empresas;
DROP POLICY IF EXISTS "empresa_select_by_codigo"      ON public.empresas;

CREATE POLICY "empresa_select_own"
  ON public.empresas FOR SELECT
  USING (user_id_productor = auth.uid());

CREATE POLICY "empresa_insert_own"
  ON public.empresas FOR INSERT
  WITH CHECK (user_id_productor = auth.uid());

CREATE POLICY "empresa_update_own"
  ON public.empresas FOR UPDATE
  USING (user_id_productor = auth.uid());

-- Transportista vinculado lee los datos de la empresa.
-- NOTA: esta política se reemplaza en el HOTFIX al final del archivo;
-- esta versión original se mantiene aquí solo como referencia inicial.
CREATE POLICY "empresa_select_transportista"
  ON public.empresas FOR SELECT
  USING (
    id IN (
      SELECT empresa_id FROM public.transportistas_empresa
      WHERE user_id_transportista = auth.uid() AND activo = true
    )
  );

-- Eliminada: reemplazada por fn_buscar_empresa_por_codigo RPC
-- CREATE POLICY "empresa_select_by_codigo" ...

-- ── 19. RLS — transportistas_empresa ──────────────────────────────────────
-- IMPORTANTE: las políticas te_select/insert/delete_productor usan la columna
-- user_id_productor (desnormalizada) para evitar un subquery circular a empresas.
-- Ver HOTFIX v2 al final del archivo para la columna, backfill y trigger.
ALTER TABLE public.transportistas_empresa ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "te_select_productor" ON public.transportistas_empresa;
DROP POLICY IF EXISTS "te_insert_productor" ON public.transportistas_empresa;
DROP POLICY IF EXISTS "te_delete_productor" ON public.transportistas_empresa;
DROP POLICY IF EXISTS "te_select_self"      ON public.transportistas_empresa;
DROP POLICY IF EXISTS "te_insert_self"      ON public.transportistas_empresa;

-- Productor: comparación directa de columna (sin subquery a empresas → sin ciclo RLS)
-- La columna user_id_productor se rellena automáticamente por el trigger trg_fill_productor
CREATE POLICY "te_select_productor"
  ON public.transportistas_empresa FOR SELECT
  USING (user_id_productor = auth.uid());

CREATE POLICY "te_insert_productor"
  ON public.transportistas_empresa FOR INSERT
  WITH CHECK (user_id_productor = auth.uid());

CREATE POLICY "te_delete_productor"
  ON public.transportistas_empresa FOR DELETE
  USING (user_id_productor = auth.uid());

-- Transportista ve y crea su propio vínculo (auto-unión por código)
CREATE POLICY "te_select_self"
  ON public.transportistas_empresa FOR SELECT
  USING (user_id_transportista = auth.uid());

CREATE POLICY "te_insert_self"
  ON public.transportistas_empresa FOR INSERT
  WITH CHECK (user_id_transportista = auth.uid());

-- ── 20. RLS aditivas — viajes_operativos ──────────────────────────────────
--    Las políticas "viajes_select_own" / "viajes_insert_own" NO se modifican.
--    PostgreSQL evalúa múltiples SELECT policies con lógica OR.

-- Productor ve todos los viajes de su empresa
CREATE POLICY "viajes_select_empresa"
  ON public.viajes_operativos FOR SELECT
  USING (
    empresa_id IS NOT NULL AND empresa_id IN (
      SELECT id FROM public.empresas WHERE user_id_productor = auth.uid()
    )
  );

-- Transportista vinculado ve viajes de la empresa
CREATE POLICY "viajes_select_empresa_member"
  ON public.viajes_operativos FOR SELECT
  USING (
    empresa_id IS NOT NULL AND empresa_id IN (
      SELECT empresa_id FROM public.transportistas_empresa
      WHERE user_id_transportista = auth.uid() AND activo = true
    )
  );

-- Transportista puede insertar viajes vinculados a su empresa
CREATE POLICY "viajes_insert_empresa"
  ON public.viajes_operativos FOR INSERT
  WITH CHECK (
    empresa_id IS NULL OR empresa_id IN (
      SELECT empresa_id FROM public.transportistas_empresa
      WHERE user_id_transportista = auth.uid() AND activo = true
    )
  );

-- ── 21. RLS aditivas — certificados_rep ───────────────────────────────────
CREATE POLICY "certs_select_empresa"
  ON public.certificados_rep FOR SELECT
  USING (
    empresa_id IS NOT NULL AND empresa_id IN (
      SELECT id FROM public.empresas WHERE user_id_productor = auth.uid()
    )
  );

CREATE POLICY "certs_select_empresa_member"
  ON public.certificados_rep FOR SELECT
  USING (
    empresa_id IS NOT NULL AND empresa_id IN (
      SELECT empresa_id FROM public.transportistas_empresa
      WHERE user_id_transportista = auth.uid() AND activo = true
    )
  );

-- ── 22. RLS aditivas — flota_vehiculos ────────────────────────────────────
CREATE POLICY "flota_select_empresa"
  ON public.flota_vehiculos FOR SELECT
  USING (
    empresa_id IS NOT NULL AND empresa_id IN (
      SELECT id FROM public.empresas WHERE user_id_productor = auth.uid()
    )
  );

CREATE POLICY "flota_select_empresa_member"
  ON public.flota_vehiculos FOR SELECT
  USING (
    empresa_id IS NOT NULL AND empresa_id IN (
      SELECT empresa_id FROM public.transportistas_empresa
      WHERE user_id_transportista = auth.uid() AND activo = true
    )
  );

CREATE POLICY "flota_insert_empresa_member"
  ON public.flota_vehiculos FOR INSERT
  WITH CHECK (
    empresa_id IS NULL OR empresa_id IN (
      SELECT empresa_id FROM public.transportistas_empresa
      WHERE user_id_transportista = auth.uid() AND activo = true
    )
  );

-- ── 23. RLS aditivas — puntos_acopio ──────────────────────────────────────
--    La política "acopio_select_authed" existente cubre los puntos globales.
--    Estas políticas añaden visibilidad por empresa cuando empresa_id está seteado.
CREATE POLICY "acopio_select_empresa"
  ON public.puntos_acopio FOR SELECT
  USING (
    empresa_id IS NOT NULL AND empresa_id IN (
      SELECT id FROM public.empresas WHERE user_id_productor = auth.uid()
    )
  );

CREATE POLICY "acopio_select_empresa_member"
  ON public.puntos_acopio FOR SELECT
  USING (
    empresa_id IS NOT NULL AND empresa_id IN (
      SELECT empresa_id FROM public.transportistas_empresa
      WHERE user_id_transportista = auth.uid() AND activo = true
    )
  );

-- ── 24. Trigger: auto-crear empresa al registrar un productor ─────────────
--    Fires AFTER INSERT ON auth.users (SECURITY DEFINER → acceso a public.empresas).
--    Usa el email como nombre default; el productor puede cambiarlo luego.
CREATE OR REPLACE FUNCTION public._fn_auto_empresa_productor()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public AS $$
BEGIN
  IF (NEW.raw_user_meta_data ->> 'role') = 'productor' THEN
    INSERT INTO public.empresas (nombre, user_id_productor)
    VALUES (
      COALESCE(
        NULLIF(trim(NEW.raw_user_meta_data ->> 'nombre_empresa'), ''),
        split_part(NEW.email, '@', 1)
      ),
      NEW.id
    )
    ON CONFLICT (user_id_productor) DO NOTHING;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_auto_empresa_productor ON auth.users;
CREATE TRIGGER trg_auto_empresa_productor
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public._fn_auto_empresa_productor();

-- ════════════════════════════════════════════════════════════════════════════
-- FASE 2 — Política UPDATE para puntos_acopio (escáner QR descuenta carga)
-- ════════════════════════════════════════════════════════════════════════════

-- Permite al transportista vinculado actualizar la carga del punto de acopio
-- al escanear un bulto. Solo afecta puntos sin empresa_id (red compartida) o
-- puntos de la empresa a la que el transportista está vinculado.
CREATE POLICY "acopio_update_linked_or_shared"
  ON public.puntos_acopio FOR UPDATE
  USING (
    empresa_id IS NULL
    OR empresa_id IN (
      SELECT empresa_id FROM public.transportistas_empresa
      WHERE user_id_transportista = auth.uid() AND activo = true
    )
  );

-- ════════════════════════════════════════════════════════════════════════════
-- FASE 4 — Columna categoria + RPCs de agregación para dashboards
-- ════════════════════════════════════════════════════════════════════════════

-- ── 25. Columna categoria en viajes_operativos ────────────────────────────
ALTER TABLE public.viajes_operativos
  ADD COLUMN IF NOT EXISTS categoria text
  CHECK (categoria IN ('envases','neumaticos','pilas','raee','aceites'));

CREATE INDEX IF NOT EXISTS idx_viajes_categoria ON public.viajes_operativos (empresa_id, categoria);

-- Backfill: inferir categoría desde el nombre del centro destino (registros previos)
UPDATE public.viajes_operativos SET categoria =
  CASE
    WHEN destino ILIKE '%Envases%'     THEN 'envases'
    WHEN destino ILIKE '%Neumáticos%'  THEN 'neumaticos'
    WHEN destino ILIKE '%Pilas%'       THEN 'pilas'
    WHEN destino ILIKE '%RAEE%'        THEN 'raee'
    WHEN destino ILIKE '%Aceites%'     THEN 'aceites'
  END
WHERE categoria IS NULL AND destino LIKE 'Centro REP%';

-- ── 26. RPC: KPI empresa por semana × categoría ───────────────────────────
-- SECURITY: p_empresa_id validado contra empresas/transportistas_empresa del caller
CREATE OR REPLACE FUNCTION public.fn_kpi_empresa_temporal(
  p_empresa_id uuid, p_semanas int DEFAULT 12
)
RETURNS TABLE(semana date, categoria text, total_kg numeric, total_km numeric, n_viajes bigint)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT date_trunc('week', created_at)::date AS semana,
         COALESCE(categoria,'otros')           AS categoria,
         COALESCE(SUM(cargas_qr_kg),0)        AS total_kg,
         COALESCE(SUM(distancia_km),0)        AS total_km,
         COUNT(*)                              AS n_viajes
  FROM public.viajes_operativos
  WHERE empresa_id = p_empresa_id
    AND created_at >= NOW() - (p_semanas||' weeks')::interval
    AND (
      EXISTS (SELECT 1 FROM public.empresas WHERE id = p_empresa_id AND user_id_productor = auth.uid())
      OR EXISTS (SELECT 1 FROM public.transportistas_empresa WHERE empresa_id = p_empresa_id AND user_id_transportista = auth.uid() AND activo = true)
    )
  GROUP BY semana, COALESCE(categoria,'otros')
  ORDER BY semana DESC;
$$;

-- ── 27. RPC: Resumen REP del productor por categoría ─────────────────────
-- SECURITY: p_empresa_id validado contra empresas/transportistas_empresa del caller
CREATE OR REPLACE FUNCTION public.fn_kpi_productor_rep(p_empresa_id uuid)
RETURNS TABLE(categoria text, total_kg numeric, total_km numeric, n_viajes bigint, co2e_kg numeric)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT COALESCE(categoria,'otros')                             AS categoria,
         COALESCE(SUM(cargas_qr_kg),0)                         AS total_kg,
         COALESCE(SUM(distancia_km),0)                         AS total_km,
         COUNT(*) FILTER (WHERE cargas_qr_kg > 0)              AS n_viajes,
         ROUND(COALESCE(SUM(distancia_km),0)/12.0*2.68, 2)    AS co2e_kg
  FROM public.viajes_operativos
  WHERE empresa_id = p_empresa_id
    AND (
      EXISTS (SELECT 1 FROM public.empresas WHERE id = p_empresa_id AND user_id_productor = auth.uid())
      OR EXISTS (SELECT 1 FROM public.transportistas_empresa WHERE empresa_id = p_empresa_id AND user_id_transportista = auth.uid() AND activo = true)
    )
  GROUP BY COALESCE(categoria,'otros');
$$;

-- ── 28. RPC: KPI personal del transportista (totales de vida) ────────────
-- SECURITY: fuerza p_user_id = auth.uid(), previene enumerar datos de otros usuarios
CREATE OR REPLACE FUNCTION public.fn_kpi_transportista(p_user_id uuid)
RETURNS TABLE(total_km numeric, total_kg numeric, total_costo numeric,
              n_viajes bigint, n_escaneos bigint, kg_por_km numeric, co2e_kg numeric)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT COALESCE(SUM(distancia_km),0)  AS total_km,
         COALESCE(SUM(cargas_qr_kg),0)  AS total_kg,
         COALESCE(SUM(costo_diesel),0)  AS total_costo,
         COUNT(*) FILTER (WHERE distancia_km > 0) AS n_viajes,
         COUNT(*) FILTER (WHERE cargas_qr_kg > 0) AS n_escaneos,
         CASE WHEN COALESCE(SUM(distancia_km),0) > 0
           THEN ROUND(COALESCE(SUM(cargas_qr_kg),0)/SUM(distancia_km),1) ELSE 0
         END AS kg_por_km,
         ROUND(COALESCE(SUM(distancia_km),0)/12.0*2.68, 2) AS co2e_kg
  FROM public.viajes_operativos
  WHERE user_id = p_user_id
    AND p_user_id = auth.uid();
$$;

-- ── 29. RPC: Evolución semanal del transportista ──────────────────────────
-- SECURITY: fuerza p_user_id = auth.uid()
CREATE OR REPLACE FUNCTION public.fn_kpi_transportista_temporal(
  p_user_id uuid, p_semanas int DEFAULT 12
)
RETURNS TABLE(semana date, total_kg numeric, total_km numeric, n_viajes bigint)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT date_trunc('week', created_at)::date AS semana,
         COALESCE(SUM(cargas_qr_kg),0)       AS total_kg,
         COALESCE(SUM(distancia_km),0)       AS total_km,
         COUNT(*)                             AS n_viajes
  FROM public.viajes_operativos
  WHERE user_id = p_user_id
    AND p_user_id = auth.uid()
    AND created_at >= NOW() - (p_semanas||' weeks')::interval
  GROUP BY semana ORDER BY semana DESC;
$$;

-- ════════════════════════════════════════════════════════════════════════════
-- FASE: Funciones atómicas para evitar race conditions
-- Reemplazan el patrón "SELECT valor → calcular → UPDATE" en el frontend.
-- Ambas funciones usan SECURITY DEFINER para ejecutar el UPDATE como superusuario
-- pero validan explícitamente la identidad del caller mediante auth.uid().
-- ════════════════════════════════════════════════════════════════════════════

-- ── 30. descontar_carga_acopio ────────────────────────────────────────────
-- Descuenta p_kg de carga_actual_kg del punto de acopio en una sola operación
-- atómica. Equivale a GREATEST(0, carga_actual_kg - p_kg).
-- Requiere que el caller esté vinculado a la empresa del punto (o que el punto
-- sea de la red compartida sin empresa_id), replicando la lógica de
-- "acopio_update_linked_or_shared".
-- Devuelve: nueva_carga_kg (valor tras el descuento).
CREATE OR REPLACE FUNCTION public.descontar_carga_acopio(
  p_punto_id uuid,
  p_kg       numeric
)
RETURNS TABLE(nueva_carga_kg numeric)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  -- Verificar autorización: punto sin empresa (red global) o empresa vinculada al caller
  IF NOT EXISTS (
    SELECT 1 FROM public.puntos_acopio
    WHERE id = p_punto_id
      AND (
        empresa_id IS NULL
        OR empresa_id IN (
          SELECT empresa_id FROM public.transportistas_empresa
          WHERE user_id_transportista = auth.uid() AND activo = true
        )
      )
  ) THEN
    RAISE EXCEPTION 'No autorizado para modificar el punto de acopio %', p_punto_id;
  END IF;

  RETURN QUERY
    UPDATE public.puntos_acopio
       SET carga_actual_kg = GREATEST(0, carga_actual_kg - p_kg)
     WHERE id = p_punto_id
  RETURNING carga_actual_kg AS nueva_carga_kg;
END;
$$;

-- ── 31. sumar_carga_flota ─────────────────────────────────────────────────
-- Suma p_kg a carga_actual_kg del vehículo, capeando en capacidad_kg (LEAST).
-- Opcionalmente actualiza el campo destino (categoría REP del último escaneo).
-- Verifica que el vehículo pertenezca al caller (user_id = auth.uid()).
-- Devuelve: nueva_carga_kg (tras la suma), capacidad_kg (para que el frontend
-- pueda evaluar alerta de sobrecapacidad sin un SELECT adicional).
CREATE OR REPLACE FUNCTION public.sumar_carga_flota(
  p_vehiculo_id uuid,
  p_kg          numeric,
  p_destino     text DEFAULT NULL
)
RETURNS TABLE(nueva_carga_kg numeric, capacidad_kg numeric)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  -- Verificar que el vehículo pertenece al caller
  IF NOT EXISTS (
    SELECT 1 FROM public.flota_vehiculos
    WHERE id = p_vehiculo_id AND user_id = auth.uid()
  ) THEN
    RAISE EXCEPTION 'No autorizado para modificar el vehículo %', p_vehiculo_id;
  END IF;

  RETURN QUERY
    UPDATE public.flota_vehiculos
       SET carga_actual_kg = LEAST(capacidad_kg, carga_actual_kg + p_kg),
           destino         = COALESCE(p_destino, destino)
     WHERE id = p_vehiculo_id
  RETURNING carga_actual_kg AS nueva_carga_kg,
            capacidad_kg;
END;
$$;

-- ════════════════════════════════════════════════════════════════════════════
-- PARCHE CRÍTICO 1 — Columnas faltantes en viajes_operativos
-- Permite el flujo de estados disponible → en_camino → entregado
-- y vincular cada viaje al transportista que lo tomó.
-- ════════════════════════════════════════════════════════════════════════════

ALTER TABLE public.viajes_operativos
  ADD COLUMN IF NOT EXISTS empresa_id        uuid REFERENCES public.empresas(id),
  ADD COLUMN IF NOT EXISTS estado            text NOT NULL DEFAULT 'disponible'
    CONSTRAINT viajes_estado_chk CHECK (estado IN ('disponible','en_camino','entregado')),
  ADD COLUMN IF NOT EXISTS transportista_id  uuid REFERENCES auth.users(id);

ALTER TABLE public.viajes_operativos REPLICA IDENTITY FULL;

CREATE INDEX IF NOT EXISTS idx_viajes_emp_est  ON public.viajes_operativos (empresa_id, estado);
CREATE INDEX IF NOT EXISTS idx_viajes_tra_est  ON public.viajes_operativos (transportista_id, estado);

-- ════════════════════════════════════════════════════════════════════════════
-- PARCHE CRÍTICO 2 — Tabla produccion_rep
-- Registra las declaraciones de producción ligadas al ciclo logístico.
-- ════════════════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS public.produccion_rep (
  id                           uuid          NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id                      uuid          NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  empresa_id                   uuid          REFERENCES public.empresas(id),
  categoria                    text          NOT NULL DEFAULT 'envases'
    CONSTRAINT prod_cat_chk CHECK (categoria IN ('envases','neumaticos','pilas','raee','aceites')),
  toneladas                    numeric(10,2) NOT NULL DEFAULT 0,
  costo_estimado               numeric(14,2) NOT NULL DEFAULT 0,
  meta_valorizacion_porcentaje numeric(5,2)  NOT NULL DEFAULT 0,
  riesgo_multa_estimado        numeric(14,2) NOT NULL DEFAULT 0,
  estado                       text          NOT NULL DEFAULT 'disponible'
    CONSTRAINT prod_est_chk CHECK (estado IN ('disponible','en_camino','entregado')),
  transportista_asignado_id    uuid          REFERENCES auth.users(id),
  created_at                   timestamptz   NOT NULL DEFAULT now()
);

ALTER TABLE public.produccion_rep REPLICA IDENTITY FULL;
ALTER TABLE public.produccion_rep ENABLE ROW LEVEL SECURITY;

CREATE INDEX IF NOT EXISTS idx_prod_emp_est  ON public.produccion_rep (empresa_id, estado);
CREATE INDEX IF NOT EXISTS idx_prod_uid_at   ON public.produccion_rep (user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_prod_tra_est  ON public.produccion_rep (transportista_asignado_id, estado);

-- RLS produccion_rep: productor lee/escribe los suyos
CREATE POLICY "prod_select_own"
  ON public.produccion_rep FOR SELECT USING (user_id = auth.uid());

CREATE POLICY "prod_insert_own"
  ON public.produccion_rep FOR INSERT WITH CHECK (user_id = auth.uid());

CREATE POLICY "prod_update_own"
  ON public.produccion_rep FOR UPDATE USING (user_id = auth.uid());

CREATE POLICY "prod_delete_own"
  ON public.produccion_rep FOR DELETE USING (user_id = auth.uid());

-- RLS produccion_rep: transportista vinculado a la empresa puede leer (para mostrar cargas)
CREATE POLICY "prod_select_trans_vinculado"
  ON public.produccion_rep FOR SELECT
  USING (
    empresa_id IS NOT NULL AND empresa_id IN (
      SELECT te.empresa_id FROM public.transportistas_empresa te
      WHERE te.user_id_transportista = auth.uid() AND te.activo = true
    )
  );

-- ════════════════════════════════════════════════════════════════════════════
-- PARCHE CRÍTICO 3 — Tabla entregas_qr
-- Token único por viaje que el transportista escanea para confirmar entrega.
-- ════════════════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS public.entregas_qr (
  id               uuid        NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  viaje_id         uuid        NOT NULL REFERENCES public.viajes_operativos(id) ON DELETE CASCADE,
  empresa_id       uuid        NOT NULL REFERENCES public.empresas(id),
  transportista_id uuid        NOT NULL REFERENCES auth.users(id),
  token            uuid        NOT NULL DEFAULT gen_random_uuid(),
  estado           text        NOT NULL DEFAULT 'pendiente'
    CONSTRAINT qr_est_chk CHECK (estado IN ('pendiente','completado')),
  fecha_completado timestamptz,
  created_at       timestamptz NOT NULL DEFAULT now(),
  UNIQUE (viaje_id),
  UNIQUE (token)
);

ALTER TABLE public.entregas_qr ENABLE ROW LEVEL SECURITY;

CREATE INDEX IF NOT EXISTS idx_qr_token      ON public.entregas_qr (token);
CREATE INDEX IF NOT EXISTS idx_qr_emp_est    ON public.entregas_qr (empresa_id, estado);
CREATE INDEX IF NOT EXISTS idx_qr_trans_est  ON public.entregas_qr (transportista_id, estado);

-- RLS entregas_qr: transportista inserta su propio registro
CREATE POLICY "qr_insert_trans"
  ON public.entregas_qr FOR INSERT
  WITH CHECK (
    transportista_id = auth.uid()
    AND empresa_id IN (
      SELECT te.empresa_id FROM public.transportistas_empresa te
      WHERE te.user_id_transportista = auth.uid() AND te.activo = true
    )
  );

-- RLS entregas_qr: productor ve los QR de su empresa
CREATE POLICY "qr_select_productor"
  ON public.entregas_qr FOR SELECT
  USING (
    empresa_id IN (
      SELECT e.id FROM public.empresas e WHERE e.user_id_productor = auth.uid()
    )
  );

-- RLS entregas_qr: transportista ve los suyos
CREATE POLICY "qr_select_trans"
  ON public.entregas_qr FOR SELECT
  USING (transportista_id = auth.uid());

-- ════════════════════════════════════════════════════════════════════════════
-- PARCHE CRÍTICO 4 — RPC fn_tomar_ruta (operación atómica anti-race-condition)
-- Un solo UPDATE con AND estado='disponible' garantiza que sólo un
-- transportista pueda tomar cada ruta, sin importar la concurrencia.
-- ════════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.fn_tomar_ruta(
  p_viaje_id   uuid,
  p_cargas_ids uuid[],
  p_empresa_id uuid
)
RETURNS TABLE(ok boolean, mensaje text, qr_token uuid)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  _uid        uuid := auth.uid();
  _rows_viaje int;
  _token      uuid := gen_random_uuid();
BEGIN
  -- Verificar vínculo activo con la empresa
  IF NOT EXISTS (
    SELECT 1 FROM public.transportistas_empresa
    WHERE user_id_transportista = _uid AND empresa_id = p_empresa_id AND activo = true
  ) THEN
    RETURN QUERY SELECT false, 'No autorizado: no estás vinculado a esta empresa.'::text, NULL::uuid;
    RETURN;
  END IF;

  -- Tomar la ruta atómicamente (falla si ya está en_camino o entregada)
  UPDATE public.viajes_operativos
     SET estado = 'en_camino', transportista_id = _uid
   WHERE id = p_viaje_id
     AND estado = 'disponible'
     AND empresa_id = p_empresa_id;
  GET DIAGNOSTICS _rows_viaje = ROW_COUNT;

  IF _rows_viaje = 0 THEN
    RETURN QUERY SELECT false, 'La ruta ya fue tomada por otro transportista.'::text, NULL::uuid;
    RETURN;
  END IF;

  -- Asignar las cargas seleccionadas
  UPDATE public.produccion_rep
     SET estado = 'en_camino', transportista_asignado_id = _uid
   WHERE id = ANY(p_cargas_ids)
     AND estado = 'disponible'
     AND empresa_id = p_empresa_id;

  -- Crear el token QR para confirmación de entrega
  INSERT INTO public.entregas_qr (viaje_id, empresa_id, transportista_id, token, estado)
  VALUES (p_viaje_id, p_empresa_id, _uid, _token, 'pendiente')
  ON CONFLICT (viaje_id) DO UPDATE
    SET token = _token, transportista_id = _uid, estado = 'pendiente', fecha_completado = NULL;

  RETURN QUERY SELECT true, 'Ruta tomada correctamente.'::text, _token;
END;
$$;

-- ════════════════════════════════════════════════════════════════════════════
-- PARCHE CRÍTICO 5 — RPC fn_confirmar_entrega (atómica, reemplaza rollback manual)
-- Combina los 3 UPDATEs del cliente en una sola función con garantía ACID.
-- ════════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.fn_confirmar_entrega(
  p_token      uuid,
  p_empresa_id uuid
)
RETURNS TABLE(ok boolean, mensaje text)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  _uid      uuid := auth.uid();
  _viaje_id uuid;
BEGIN
  -- Marcar QR como completado y obtener viaje_id (atómico — si el token ya fue usado, no retorna filas)
  UPDATE public.entregas_qr
     SET estado = 'completado', fecha_completado = now()
   WHERE token = p_token
     AND estado = 'pendiente'
     AND transportista_id = _uid
  RETURNING viaje_id INTO _viaje_id;

  IF _viaje_id IS NULL THEN
    RETURN QUERY SELECT false, 'QR inválido, ya utilizado, o no pertenece a tu usuario.'::text;
    RETURN;
  END IF;

  -- Marcar viaje como entregado
  UPDATE public.viajes_operativos
     SET estado = 'entregado'
   WHERE id = _viaje_id AND estado = 'en_camino';

  -- Marcar todas las cargas asignadas al transportista en esta empresa como entregadas
  UPDATE public.produccion_rep
     SET estado = 'entregado'
   WHERE transportista_asignado_id = _uid
     AND empresa_id = p_empresa_id
     AND estado = 'en_camino';

  RETURN QUERY SELECT true, 'Entrega confirmada correctamente.'::text;
END;
$$;

-- ════════════════════════════════════════════════════════════════════════════
-- PARCHE ALTO 1 — Triggers de validación de transición de estado
-- Impiden retrocesos de estado o saltos inválidos (ej: disponible → entregado).
-- ════════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public._fn_validar_estado_viaje()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  IF OLD.estado = NEW.estado THEN RETURN NEW; END IF;
  IF OLD.estado = 'disponible' AND NEW.estado = 'en_camino'  THEN RETURN NEW; END IF;
  IF OLD.estado = 'en_camino'  AND NEW.estado = 'entregado'  THEN RETURN NEW; END IF;
  -- Permitir reversión a disponible sólo si el viaje no llegó a entregado (para rollback de fn_tomar_ruta)
  IF OLD.estado = 'en_camino'  AND NEW.estado = 'disponible' THEN RETURN NEW; END IF;
  RAISE EXCEPTION 'Transición de estado inválida en viaje: % → %', OLD.estado, NEW.estado;
END;
$$;

DROP TRIGGER IF EXISTS trg_validar_estado_viaje ON public.viajes_operativos;
CREATE TRIGGER trg_validar_estado_viaje
  BEFORE UPDATE OF estado ON public.viajes_operativos
  FOR EACH ROW EXECUTE FUNCTION public._fn_validar_estado_viaje();

CREATE OR REPLACE FUNCTION public._fn_validar_estado_produccion()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  IF OLD.estado = NEW.estado THEN RETURN NEW; END IF;
  IF OLD.estado = 'disponible' AND NEW.estado = 'en_camino'  THEN RETURN NEW; END IF;
  IF OLD.estado = 'en_camino'  AND NEW.estado = 'entregado'  THEN RETURN NEW; END IF;
  RAISE EXCEPTION 'Transición de estado inválida en produccion_rep: % → %', OLD.estado, NEW.estado;
END;
$$;

DROP TRIGGER IF EXISTS trg_validar_estado_produccion ON public.produccion_rep;
CREATE TRIGGER trg_validar_estado_produccion
  BEFORE UPDATE OF estado ON public.produccion_rep
  FOR EACH ROW EXECUTE FUNCTION public._fn_validar_estado_produccion();

-- ════════════════════════════════════════════════════════════════════════════
-- PARCHE ALTO 2 — Reemplazar RLS abierta por RPC segura para búsqueda de empresa
-- La política empresa_select_by_codigo exponía TODAS las empresas activas a
-- cualquier usuario autenticado. Se elimina y se reemplaza por una función
-- que devuelve sólo id+nombre (sin datos sensibles) para el código exacto.
-- ════════════════════════════════════════════════════════════════════════════

DROP POLICY IF EXISTS "empresa_select_by_codigo" ON public.empresas;

CREATE OR REPLACE FUNCTION public.fn_buscar_empresa_por_codigo(p_codigo text)
RETURNS TABLE(id uuid, nombre text)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT e.id, e.nombre
  FROM public.empresas e
  WHERE upper(trim(e.codigo_invitacion)) = upper(trim(p_codigo))
    AND e.activo = true
  LIMIT 1;
$$;

-- ════════════════════════════════════════════════════════════════════════════
-- PARCHE BAJO — Columna de auditoría en transportistas_empresa
-- El frontend ya guarda codigo_invitacion al momento del vínculo; formalizar la columna.
-- ════════════════════════════════════════════════════════════════════════════

ALTER TABLE public.transportistas_empresa
  ADD COLUMN IF NOT EXISTS codigo_invitacion text;

-- ════════════════════════════════════════════════════════════════════════════
-- HOTFIX v2 — Romper ciclo RLS por desnormalización (solución definitiva)
--
-- CAUSA raíz:
--   te_select_productor  (transportistas_empresa → subquery empresas)
--   empresa_select_transportista (empresas → subquery transportistas_empresa)
--   → ciclo infinito que se dispara desde cualquier tabla que consulte
--     transportistas_empresa dentro de una política RLS.
--
-- SOLUCIÓN: agregar user_id_productor como columna directa en
--   transportistas_empresa. Las políticas del productor pasan a usar
--   user_id_productor = auth.uid() (comparación de columna, sin subquery).
--   Esto rompe el ciclo sin depender de SECURITY DEFINER ni BYPASSRLS.
-- ════════════════════════════════════════════════════════════════════════════

-- 1. Columna desnormalizada
ALTER TABLE public.transportistas_empresa
  ADD COLUMN IF NOT EXISTS user_id_productor uuid REFERENCES auth.users(id);

-- 2. Backfill de filas existentes
UPDATE public.transportistas_empresa te
   SET user_id_productor = e.user_id_productor
  FROM public.empresas e
 WHERE te.empresa_id = e.id
   AND te.user_id_productor IS NULL;

-- 3. Trigger BEFORE INSERT para auto-rellenar en vínculos futuros
CREATE OR REPLACE FUNCTION public._fn_fill_productor_id()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  SELECT user_id_productor INTO NEW.user_id_productor
  FROM public.empresas WHERE id = NEW.empresa_id;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_fill_productor ON public.transportistas_empresa;
CREATE TRIGGER trg_fill_productor
  BEFORE INSERT ON public.transportistas_empresa
  FOR EACH ROW EXECUTE FUNCTION public._fn_fill_productor_id();

-- 4. Reemplazar políticas del productor en transportistas_empresa
--    por comparación directa de columna (sin subquery a empresas)
DROP POLICY IF EXISTS "te_select_productor" ON public.transportistas_empresa;
CREATE POLICY "te_select_productor"
  ON public.transportistas_empresa FOR SELECT
  USING (user_id_productor = auth.uid());

DROP POLICY IF EXISTS "te_insert_productor" ON public.transportistas_empresa;
CREATE POLICY "te_insert_productor"
  ON public.transportistas_empresa FOR INSERT
  WITH CHECK (user_id_productor = auth.uid());

DROP POLICY IF EXISTS "te_delete_productor" ON public.transportistas_empresa;
CREATE POLICY "te_delete_productor"
  ON public.transportistas_empresa FOR DELETE
  USING (user_id_productor = auth.uid());

-- 5. empresa_select_transportista: ahora transportistas_empresa tiene políticas
--    simples (sin subquery a empresas), por lo que el subquery desde empresas
--    hacia transportistas_empresa ya no genera ciclo.
--    La política queda igual que el original.
DROP POLICY IF EXISTS "empresa_select_transportista" ON public.empresas;
CREATE POLICY "empresa_select_transportista"
  ON public.empresas FOR SELECT
  USING (
    id IN (
      SELECT te.empresa_id FROM public.transportistas_empresa te
      WHERE te.user_id_transportista = auth.uid() AND te.activo = true
    )
  );

-- 6. Resto de tablas: subqueries a transportistas_empresa ya son seguros
--    porque sus políticas son comparaciones directas de columna.
DROP POLICY IF EXISTS "viajes_select_empresa_member" ON public.viajes_operativos;
CREATE POLICY "viajes_select_empresa_member"
  ON public.viajes_operativos FOR SELECT
  USING (
    empresa_id IS NOT NULL AND empresa_id IN (
      SELECT te.empresa_id FROM public.transportistas_empresa te
      WHERE te.user_id_transportista = auth.uid() AND te.activo = true
    )
  );

DROP POLICY IF EXISTS "viajes_insert_empresa" ON public.viajes_operativos;
CREATE POLICY "viajes_insert_empresa"
  ON public.viajes_operativos FOR INSERT
  WITH CHECK (
    empresa_id IS NULL OR empresa_id IN (
      SELECT te.empresa_id FROM public.transportistas_empresa te
      WHERE te.user_id_transportista = auth.uid() AND te.activo = true
    )
  );

DROP POLICY IF EXISTS "certs_select_empresa_member" ON public.certificados_rep;
CREATE POLICY "certs_select_empresa_member"
  ON public.certificados_rep FOR SELECT
  USING (
    empresa_id IS NOT NULL AND empresa_id IN (
      SELECT te.empresa_id FROM public.transportistas_empresa te
      WHERE te.user_id_transportista = auth.uid() AND te.activo = true
    )
  );

DROP POLICY IF EXISTS "flota_select_empresa_member" ON public.flota_vehiculos;
CREATE POLICY "flota_select_empresa_member"
  ON public.flota_vehiculos FOR SELECT
  USING (
    empresa_id IS NOT NULL AND empresa_id IN (
      SELECT te.empresa_id FROM public.transportistas_empresa te
      WHERE te.user_id_transportista = auth.uid() AND te.activo = true
    )
  );

DROP POLICY IF EXISTS "flota_insert_empresa_member" ON public.flota_vehiculos;
CREATE POLICY "flota_insert_empresa_member"
  ON public.flota_vehiculos FOR INSERT
  WITH CHECK (
    empresa_id IS NULL OR empresa_id IN (
      SELECT te.empresa_id FROM public.transportistas_empresa te
      WHERE te.user_id_transportista = auth.uid() AND te.activo = true
    )
  );

DROP POLICY IF EXISTS "prod_select_trans_vinculado" ON public.produccion_rep;
CREATE POLICY "prod_select_trans_vinculado"
  ON public.produccion_rep FOR SELECT
  USING (
    empresa_id IS NOT NULL AND empresa_id IN (
      SELECT te.empresa_id FROM public.transportistas_empresa te
      WHERE te.user_id_transportista = auth.uid() AND te.activo = true
    )
  );

DROP POLICY IF EXISTS "qr_insert_trans" ON public.entregas_qr;
CREATE POLICY "qr_insert_trans"
  ON public.entregas_qr FOR INSERT
  WITH CHECK (
    transportista_id = auth.uid()
    AND empresa_id IN (
      SELECT te.empresa_id FROM public.transportistas_empresa te
      WHERE te.user_id_transportista = auth.uid() AND te.activo = true
    )
  );
