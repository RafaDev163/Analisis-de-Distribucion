-- V7__stg_ventas.sql
-- Staging mensual por TIENDA (almacén 103 en este caso)
-- CSV origen: /db/seed/ventasproductosclasificacion.csv

-- ==========================================
-- Parámetros (con defaults por si no hay placeholders en Flyway)
-- ==========================================
-- Flyway placeholders esperados:
--   2025-08-01  (ej. 2025-08-01)
--   2025-08-31     (ej. 2025-08-31)
--   103  (ej. 103)

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'stg_ventas_row') THEN
    CREATE TYPE stg_ventas_row AS (
      raw_id_clasificacion text,
      clasificacion        text,
      clave                text,
      proveedor_id_text    text,
      proveedor_nombre     text,
      descripcion          text,
      unidades_ven_text    text,
      unidades_dev_text    text,
      unidades_neto_text   text,
      importe_ven_text     text,
      importe_dev_text     text,
      importe_neto_text    text
    );
  END IF;
END$$;

-- ==========================================
-- Tabla staging normalizada
-- ==========================================
CREATE TABLE IF NOT EXISTS stg_ventas (
  stg_venta_id      bigserial PRIMARY KEY,
  almacen_codigo    integer NOT NULL,
  almacen_nombre    text NULL,
  raw_id_clasificacion integer NULL,
  clasificacion     text NOT NULL,
  clave             text NOT NULL,
  proveedor_id      integer NULL,
  proveedor_nombre  text NULL,
  descripcion       text NULL,
  unidades_ven      numeric(18,2) NOT NULL,
  unidades_dev      numeric(18,2) NOT NULL,
  unidades_neto     numeric(18,2) NOT NULL,
  importe_ven       numeric(18,2) NOT NULL,
  importe_dev       numeric(18,2) NOT NULL,
  importe_neto      numeric(18,2) NOT NULL,
  periodo_inicio    date NOT NULL,
  periodo_fin       date NOT NULL,
  fuente_archivo    text NOT NULL DEFAULT 'ventasproductosclasificacion.csv',
  loaded_at         timestamptz NOT NULL DEFAULT now(),
  row_md5           char(32) NULL
);

CREATE UNIQUE INDEX IF NOT EXISTS uidx_stg_ventas_periodo_clave_almacen
  ON stg_ventas (clave, almacen_codigo, periodo_inicio, periodo_fin);

CREATE INDEX IF NOT EXISTS idx_stg_ventas_clave   ON stg_ventas (clave);
CREATE INDEX IF NOT EXISTS idx_stg_ventas_almacen ON stg_ventas (almacen_codigo);

-- ==========================================
-- Carga a una tabla raw temporal (para no depender de headers exactos)
-- ==========================================
DROP TABLE IF EXISTS stg_ventas_raw;
CREATE TEMP TABLE stg_ventas_raw OF stg_ventas_row;

COPY stg_ventas_raw
FROM '/csv/ventasproductosclasificacion_utf8.csv'
CSV HEADER;

-- ==========================================
-- Normalización y volcado a stg_ventas
--   - Mapea strings numéricos a numeric
--   - Inserta almacén constante (103 por defecto)
--   - Inserta periodo (agosto por defecto)
--   - Calcula row_md5 para idempotencia
-- ==========================================
WITH params AS (
  SELECT
    COALESCE(NULLIF('2025-08-01',''),'2025-08-01')::date AS periodo_inicio,
    COALESCE(NULLIF('2025-08-31',''),'2025-08-31')::date    AS periodo_fin,
    COALESCE(NULLIF('103',''),'103')::int         AS almacen_codigo
),
src AS (
  SELECT
    NULLIF(trim(r.raw_id_clasificacion),'')                               AS raw_id_clasificacion,
    NULLIF(trim(r.clasificacion),'')                                      AS clasificacion,
    NULLIF(trim(r.clave),'')                                              AS clave,
    NULLIF(trim(r.proveedor_id_text),'')                                  AS proveedor_id_text,
    NULLIF(trim(r.proveedor_nombre),'')                                   AS proveedor_nombre,
    NULLIF(trim(r.descripcion),'')                                        AS descripcion,
    REPLACE(COALESCE(r.unidades_ven_text,'0'), ',', '')::numeric(18,2)    AS unidades_ven,
    REPLACE(COALESCE(r.unidades_dev_text,'0'), ',', '')::numeric(18,2)    AS unidades_dev,
    REPLACE(COALESCE(r.unidades_neto_text,'0'), ',', '')::numeric(18,2)   AS unidades_neto,
    REPLACE(COALESCE(r.importe_ven_text,'0'), ',', '')::numeric(18,2)     AS importe_ven,
    REPLACE(COALESCE(r.importe_dev_text,'0'), ',', '')::numeric(18,2)     AS importe_dev,
    REPLACE(COALESCE(r.importe_neto_text,'0'), ',', '')::numeric(18,2)    AS importe_neto
  FROM stg_ventas_raw r
),
norm AS (
  SELECT
    p.almacen_codigo,
    NULL::text AS almacen_nombre,
    (CASE WHEN src.raw_id_clasificacion ~ '^[0-9]+$' THEN src.raw_id_clasificacion::int END) AS raw_id_clasificacion,
    COALESCE(src.clasificacion, 'SIN_CLASIFICACION') AS clasificacion,
    src.clave AS clave,
    (CASE WHEN src.proveedor_id_text ~ '^[0-9]+$' THEN src.proveedor_id_text::int END) AS proveedor_id,
    src.proveedor_nombre,
    src.descripcion,
    src.unidades_ven,
    src.unidades_dev,
    src.unidades_neto,
    src.importe_ven,
    src.importe_dev,
    src.importe_neto,
    p.periodo_inicio,
    p.periodo_fin,
    md5(
      concat_ws('||',
        p.almacen_codigo::text,
        src.clave,
        COALESCE(src.clasificacion,''),
        COALESCE(src.proveedor_id_text,''),
        COALESCE(src.proveedor_nombre,''),
        COALESCE(src.descripcion,''),
        src.unidades_ven::text,
        src.unidades_dev::text,
        src.unidades_neto::text,
        src.importe_ven::text,
        src.importe_dev::text,
        src.importe_neto::text,
        p.periodo_inicio::text,
        p.periodo_fin::text
      )
    ) AS row_md5
  FROM src CROSS JOIN params p
)
INSERT INTO stg_ventas (
  almacen_codigo, almacen_nombre, raw_id_clasificacion, clasificacion, clave,
  proveedor_id, proveedor_nombre, descripcion,
  unidades_ven, unidades_dev, unidades_neto,
  importe_ven, importe_dev, importe_neto,
  periodo_inicio, periodo_fin, row_md5
)
SELECT
  n.almacen_codigo, n.almacen_nombre, n.raw_id_clasificacion, n.clasificacion, n.clave,
  n.proveedor_id, n.proveedor_nombre, n.descripcion,
  n.unidades_ven, n.unidades_dev, n.unidades_neto,
  n.importe_ven, n.importe_dev, n.importe_neto,
  n.periodo_inicio, n.periodo_fin, n.row_md5
FROM norm n
WHERE n.clave IS NOT NULL                       -- ← evita filas sin clave
  AND length(n.clave) > 0                       -- ← evita cadenas vacías
-- (opcional) si quieres asegurar patrón alfanumérico:
--  AND n.clave ~ '^[A-Z0-9]+$'
ON CONFLICT (clave, almacen_codigo, periodo_inicio, periodo_fin) DO NOTHING;
