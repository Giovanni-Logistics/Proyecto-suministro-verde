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
-- MODELO RELACIONAL — Empresa ↔ Transportista
-- ════════════════════════════════════════════════════════════════════════════
-- Propósito: desacoplar el filtro user_id individual y habilitar que
-- productor y transportista compartan datos dentro de la misma empresa.
--
-- Flujo de datos con empresa_id:
--   Transportista registra viaje → viajes_operativos.empresa_id = su empresa
--   Productor ve viajes de todos sus transportistas vía viajes_select_empresa
--   Transportista ve declaraciones REP del productor vía certs_select_empresa_member
-- ════════════════════════════════════════════════════════════════════════════

-- ── 14. Tabla empresas ────────────────────────────────────────────────────
--    Una empresa por productor (MVP). El productor es la entidad legal REP.
CREATE TABLE IF NOT EXISTS public.empresas (
  id                uuid        NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  nombre            text        NOT NULL,
  rut               text,
  user_id_productor uuid        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  activo            boolean     NOT NULL DEFAULT true,
  created_at        timestamptz NOT NULL DEFAULT now(),
  UNIQUE (user_id_productor)
);

-- ── 15. Tabla transportistas_empresa ──────────────────────────────────────
--    Vínculo N:M entre transportistas (user_id) y empresa.
--    El productor crea filas aquí para invitar a sus transportistas.
CREATE TABLE IF NOT EXISTS public.transportistas_empresa (
  id         uuid        NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  empresa_id uuid        NOT NULL REFERENCES public.empresas(id)  ON DELETE CASCADE,
  user_id    uuid        NOT NULL REFERENCES auth.users(id)       ON DELETE CASCADE,
  activo     boolean     NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (empresa_id, user_id)
);

CREATE INDEX IF NOT EXISTS idx_te_empresa ON public.transportistas_empresa (empresa_id, activo);
CREATE INDEX IF NOT EXISTS idx_te_user    ON public.transportistas_empresa (user_id,    activo);

-- ── 16. empresa_id en tablas operativas ───────────────────────────────────
--    Nullable para compatibilidad: datos existentes (sin empresa) siguen
--    siendo visibles vía las políticas "own" originales.
ALTER TABLE public.certificados_rep  ADD COLUMN IF NOT EXISTS empresa_id uuid REFERENCES public.empresas(id);
ALTER TABLE public.viajes_operativos ADD COLUMN IF NOT EXISTS empresa_id uuid REFERENCES public.empresas(id);
ALTER TABLE public.flota_vehiculos   ADD COLUMN IF NOT EXISTS empresa_id uuid REFERENCES public.empresas(id);

CREATE INDEX IF NOT EXISTS idx_viajes_empresa ON public.viajes_operativos (empresa_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_certs_empresa  ON public.certificados_rep  (empresa_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_flota_empresa  ON public.flota_vehiculos   (empresa_id, activo);

-- ── 17. RLS — empresas ────────────────────────────────────────────────────
ALTER TABLE public.empresas ENABLE ROW LEVEL SECURITY;

-- Productor gestiona su propia empresa
CREATE POLICY "empresa_select_own"
  ON public.empresas FOR SELECT
  USING (user_id_productor = auth.uid());

CREATE POLICY "empresa_insert_own"
  ON public.empresas FOR INSERT
  WITH CHECK (user_id_productor = auth.uid());

CREATE POLICY "empresa_update_own"
  ON public.empresas FOR UPDATE
  USING (user_id_productor = auth.uid());

-- Transportista vinculado puede leer datos de la empresa (nombre, etc.)
CREATE POLICY "empresa_select_transportista"
  ON public.empresas FOR SELECT
  USING (
    id IN (
      SELECT empresa_id FROM public.transportistas_empresa
      WHERE user_id = auth.uid() AND activo = true
    )
  );

-- ── 18. RLS — transportistas_empresa ──────────────────────────────────────
ALTER TABLE public.transportistas_empresa ENABLE ROW LEVEL SECURITY;

-- Productor gestiona los vínculos de su empresa
CREATE POLICY "te_select_productor"
  ON public.transportistas_empresa FOR SELECT
  USING (
    empresa_id IN (
      SELECT id FROM public.empresas WHERE user_id_productor = auth.uid()
    )
  );

CREATE POLICY "te_insert_productor"
  ON public.transportistas_empresa FOR INSERT
  WITH CHECK (
    empresa_id IN (
      SELECT id FROM public.empresas WHERE user_id_productor = auth.uid()
    )
  );

CREATE POLICY "te_delete_productor"
  ON public.transportistas_empresa FOR DELETE
  USING (
    empresa_id IN (
      SELECT id FROM public.empresas WHERE user_id_productor = auth.uid()
    )
  );

-- Transportista ve su propio vínculo
CREATE POLICY "te_select_self"
  ON public.transportistas_empresa FOR SELECT
  USING (user_id = auth.uid());

-- ── 19. RLS adicionales — viajes_operativos a nivel empresa ──────────────
--    NOTA: las políticas "viajes_select_own" e "viajes_insert_own" originales
--    NO se modifican. PostgreSQL usa OR entre múltiples políticas SELECT.

-- Productor ve todos los viajes de su empresa (empresa_id asignado)
CREATE POLICY "viajes_select_empresa"
  ON public.viajes_operativos FOR SELECT
  USING (
    empresa_id IS NOT NULL
    AND empresa_id IN (
      SELECT id FROM public.empresas WHERE user_id_productor = auth.uid()
    )
  );

-- Transportistas de la misma empresa se ven entre sí
CREATE POLICY "viajes_select_empresa_member"
  ON public.viajes_operativos FOR SELECT
  USING (
    empresa_id IS NOT NULL
    AND empresa_id IN (
      SELECT empresa_id FROM public.transportistas_empresa
      WHERE user_id = auth.uid() AND activo = true
    )
  );

-- Transportista puede insertar viajes vinculados a su empresa
CREATE POLICY "viajes_insert_empresa"
  ON public.viajes_operativos FOR INSERT
  WITH CHECK (
    empresa_id IS NULL
    OR empresa_id IN (
      SELECT empresa_id FROM public.transportistas_empresa
      WHERE user_id = auth.uid() AND activo = true
    )
  );

-- ── 20. RLS adicionales — certificados_rep a nivel empresa ────────────────

-- Productor ve todos los certificados de su empresa
CREATE POLICY "certs_select_empresa"
  ON public.certificados_rep FOR SELECT
  USING (
    empresa_id IS NOT NULL
    AND empresa_id IN (
      SELECT id FROM public.empresas WHERE user_id_productor = auth.uid()
    )
  );

-- Transportistas vinculados pueden leer las declaraciones REP de su empresa
CREATE POLICY "certs_select_empresa_member"
  ON public.certificados_rep FOR SELECT
  USING (
    empresa_id IS NOT NULL
    AND empresa_id IN (
      SELECT empresa_id FROM public.transportistas_empresa
      WHERE user_id = auth.uid() AND activo = true
    )
  );

-- ── 21. RLS adicionales — flota_vehiculos a nivel empresa ─────────────────

-- Productor ve la flota de todos sus transportistas
CREATE POLICY "flota_select_empresa"
  ON public.flota_vehiculos FOR SELECT
  USING (
    empresa_id IS NOT NULL
    AND empresa_id IN (
      SELECT id FROM public.empresas WHERE user_id_productor = auth.uid()
    )
  );

-- Transportistas de la misma empresa ven la flota entre sí
CREATE POLICY "flota_select_empresa_member"
  ON public.flota_vehiculos FOR SELECT
  USING (
    empresa_id IS NOT NULL
    AND empresa_id IN (
      SELECT empresa_id FROM public.transportistas_empresa
      WHERE user_id = auth.uid() AND activo = true
    )
  );
