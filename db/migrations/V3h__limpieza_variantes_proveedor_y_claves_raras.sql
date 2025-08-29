BEGIN;

----------------------------------------------------------------------
-- A) CONSOLIDAR PROVEEDORES “DUPLICADOS POR CEROS” EN EL PUENTE
--    Mantener UN solo proveedor canónico por (articulo_clave, raíz)
--    donde raíz = proveedor_codigo sin ceros finales (rtrim('0')).
----------------------------------------------------------------------

-- A.0) Backup ligero del puente (por si quieres revertir después)
CREATE TEMP TABLE ap_backup AS
SELECT * FROM articulo_proveedor;

-- A.1) Vista auxiliar: raíz del código de proveedor (sin ceros finales)
CREATE OR REPLACE VIEW vw_prov_raiz AS
SELECT
  p.proveedor_sk,
  p.proveedor_codigo,
  NULLIF(regexp_replace(p.proveedor_codigo, '0+$', ''), '') AS prov_raiz
FROM dim_proveedor p;

-- A.2) Elegir el proveedor CANÓNICO por (clave, raíz) usando frecuencia en staging
WITH d AS (
  SELECT s.pr_clave, s.proveedor, COUNT(*) AS cnt
  FROM stg_existencias s
  WHERE s.pr_clave IS NOT NULL AND s.proveedor IS NOT NULL
  GROUP BY s.pr_clave, s.proveedor
),
r AS (
  SELECT
    d.pr_clave,
    d.proveedor,
    NULLIF(regexp_replace(d.proveedor, '0+$', ''), '') AS prov_raiz,
    d.cnt
  FROM d
  WHERE d.proveedor IS NOT NULL
),
canon AS (
  SELECT pr_clave, prov_raiz, proveedor AS proveedor_canon
  FROM (
    SELECT pr_clave, prov_raiz, proveedor, cnt,
           ROW_NUMBER() OVER (PARTITION BY pr_clave, prov_raiz
                              ORDER BY cnt DESC, length(proveedor) ASC) AS rn
    FROM r
    WHERE prov_raiz IS NOT NULL
  ) x
  WHERE rn = 1
),
ap_detalle AS (
  SELECT ap.articulo_sk, ap.proveedor_sk, a.articulo_clave,
         vr.prov_raiz, p.proveedor_codigo
  FROM articulo_proveedor ap
  JOIN dim_articulo a   USING (articulo_sk)
  JOIN dim_proveedor p  USING (proveedor_sk)
  JOIN vw_prov_raiz vr  ON vr.proveedor_sk = p.proveedor_sk
  WHERE vr.prov_raiz IS NOT NULL
),
ap_no_canon AS (
  -- filas del puente a eliminar: no coinciden con el proveedor canónico elegido
  SELECT apd.*
  FROM ap_detalle apd
  JOIN canon c
    ON c.pr_clave = apd.articulo_clave
   AND c.prov_raiz = apd.prov_raiz
  WHERE apd.proveedor_codigo <> c.proveedor_canon
)
DELETE FROM articulo_proveedor ap
USING ap_no_canon m
WHERE ap.articulo_sk = m.articulo_sk
  AND ap.proveedor_sk = m.proveedor_sk;

-- A.3) (Opcional) proveed. huérfanos en dim_proveedor (sin uso en puente)
--      Solo reporta; si quieres borrar, hazlo manualmente con cuidado.
-- SELECT p.proveedor_codigo
-- FROM dim_proveedor p
-- LEFT JOIN articulo_proveedor ap ON ap.proveedor_sk = p.proveedor_sk
-- WHERE ap.proveedor_sk IS NULL;


----------------------------------------------------------------------
-- B) REFRESCAR “PROVEEDOR PRINCIPAL” EN dim_articulo TRAS LA LIMPIEZA
--    (A=UNICO y C=VALIDADO; DOMINANTE opcional)
----------------------------------------------------------------------

-- B.1) Limpiar el principal para recalcularlo limpio
UPDATE dim_articulo
SET proveedor_codigo = NULL,
    proveedor_cod_origen = NULL,
    proveedor_confiable = NULL;

-- B.2) A (ÚNICO proveedor en staging por clave)
WITH d AS (
  SELECT DISTINCT s.pr_clave, s.proveedor
  FROM stg_existencias s
  WHERE s.pr_clave IS NOT NULL
),
c AS (
  SELECT pr_clave, COUNT(*) AS n_prov_dist
  FROM d
  GROUP BY pr_clave
),
only_one AS (
  SELECT d.pr_clave, d.proveedor
  FROM d
  JOIN c USING (pr_clave)
  WHERE c.n_prov_dist = 1 AND d.proveedor IS NOT NULL
)
UPDATE dim_articulo a
SET proveedor_codigo     = o.proveedor,
    proveedor_cod_origen = 'UNICO',
    proveedor_confiable  = TRUE
FROM only_one o
WHERE a.articulo_clave = o.pr_clave;

-- B.3) C (VALIDADO con la clave, permitiendo ceros entre fam y proveedor)
WITH base AS (
  SELECT DISTINCT s.pr_clave, s.proveedor
  FROM stg_existencias s
  WHERE s.pr_clave IS NOT NULL AND s.proveedor IS NOT NULL
),
resto AS (
  SELECT b.*, regexp_match(b.pr_clave, '(?i)^(AFF|AF|F{1,2}|C+)?0?([0-9]+)$') AS rx
  FROM base b
),
val AS (
  SELECT r.pr_clave, r.proveedor,
         CASE WHEN r.rx IS NULL THEN NULL ELSE r.rx[2] END AS rest
  FROM resto r
),
ok AS (
  SELECT v.pr_clave, v.proveedor,
         ( ltrim(substring(v.rest from 2), '0') LIKE (v.proveedor || '%')
           OR ltrim(substring(v.rest from 3), '0') LIKE (v.proveedor || '%') ) AS coincide
  FROM val v
  WHERE v.rest IS NOT NULL AND length(v.rest) >= 1
)
UPDATE dim_articulo a
SET proveedor_codigo     = o.proveedor,
    proveedor_cod_origen = 'VALIDADO',
    proveedor_confiable  = TRUE
FROM ok o
WHERE a.articulo_clave = o.pr_clave
  AND o.coincide = TRUE
  AND a.proveedor_codigo IS NULL;

-- B.4) (Opcional) B DOMINANTE por frecuencia para los que aún estén NULL
-- WITH freq AS (
--   SELECT s.pr_clave, s.proveedor, COUNT(*) AS cnt
--   FROM stg_existencias s
--   WHERE s.pr_clave IS NOT NULL AND s.proveedor IS NOT NULL
--   GROUP BY s.pr_clave, s.proveedor
-- ),
-- dom AS (
--   SELECT pr_clave, proveedor
--   FROM (
--     SELECT pr_clave, proveedor,
--            ROW_NUMBER() OVER (PARTITION BY pr_clave ORDER BY cnt DESC) AS rn
--     FROM freq
--   ) x
--   WHERE rn = 1
-- )
-- UPDATE dim_articulo a
-- SET proveedor_codigo     = d.proveedor,
--     proveedor_cod_origen = 'DOMINANTE',
--     proveedor_confiable  = FALSE
-- FROM dom d
-- WHERE a.articulo_clave = d.pr_clave
--   AND a.proveedor_codigo IS NULL;


----------------------------------------------------------------------
-- C) CLAVES “RARAS” (p. ej. científicas tipo 9.90E12)
--    2 rutas:
--      C.1) Si ya conoces el valor correcto -> actualiza staging y
--           luego re-correr cargas dependientes (recomendada).
--      C.2) Si aún no conoces el valor correcto -> CUARENTENA:
--           exclúyelas del puente y marca para revisión.
----------------------------------------------------------------------

-- C.0) Detecta candidatas raras (ajusta el patrón si hace falta)
CREATE TEMP TABLE claves_raras AS
SELECT DISTINCT a.articulo_clave
FROM dim_articulo a
WHERE a.articulo_clave ~* 'E\+?\d+$'   -- estilo científico
   OR a.articulo_clave ~ '[^\w\-]';    -- símbolos raros

-- Si NO hay filas, no hace nada:
-- SELECT * FROM claves_raras;

-- C.1) (Opción preferida) Si sabes los valores correctos, mapea aquí:
-- -- ejemplo:
-- -- UPDATE stg_existencias SET pr_clave = 'C0140740001'
-- -- WHERE pr_clave = '9.90E12';
-- -- Luego tendrás que re-ejecutar la carga de dim_articulo y el puente.

-- C.2) CUARENTENA: sacar del puente cualquier fila de esas claves
DELETE FROM articulo_proveedor ap
USING dim_articulo a, claves_raras k
WHERE ap.articulo_sk = a.articulo_sk
  AND a.articulo_clave = k.articulo_clave;

-- (Opcional) Marcar en dim_articulo para revisión
UPDATE dim_articulo a
SET proveedor_codigo     = NULL,
    proveedor_cod_origen = 'REVISION',
    proveedor_confiable  = FALSE
FROM claves_raras k
WHERE a.articulo_clave = k.articulo_clave;

COMMIT;
