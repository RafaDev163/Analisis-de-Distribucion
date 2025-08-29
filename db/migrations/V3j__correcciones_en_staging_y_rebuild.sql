-- V3j__correcciones_en_staging_y_rebuild.sql
-- Objetivo: corregir inconsistencias del CSV en staging (stg_existencias)
--           y reconstruir el puente articulo_proveedor para reflejar el catálogo maestro "nuevo".
-- ...
BEGIN;

-- A) Correcciones puntuales
UPDATE stg_existencias
SET proveedor = '347'
WHERE pr_clave   = 'C015347052'
  AND pr_almacen IN ('103','104','105','106')
  AND proveedor IS DISTINCT FROM '347';

-- (agrega más correcciones aquí si detectas otras claves)

-- B) (Opcional) corregir claves raras si ya conoces su valor correcto
-- UPDATE stg_existencias SET pr_clave = 'CLAVE_CORRECTA' WHERE pr_clave = '9.90E12';

-- C) Rebuild del puente (idéntico a V3i)
DELETE FROM articulo_proveedor;
INSERT INTO articulo_proveedor (articulo_sk, proveedor_sk, costo_unitario, fuente)
SELECT
  a.articulo_sk,
  p.proveedor_sk,
  NULLIF(AVG(NULLIF(s.pr_costo, 0)), NULL) AS costo_prom,
  'stg_existencias (proveedor CSV, V3j)'    AS fuente
FROM stg_existencias s
JOIN dim_articulo  a ON a.articulo_clave  = s.pr_clave
JOIN dim_proveedor p ON p.proveedor_codigo IS NOT DISTINCT FROM s.proveedor
WHERE a.pseudo IS FALSE
  AND s.proveedor IS NOT NULL
GROUP BY a.articulo_sk, p.proveedor_sk
ON CONFLICT (articulo_sk, proveedor_sk) DO UPDATE
SET costo_unitario = EXCLUDED.costo_unitario,
    fuente         = EXCLUDED.fuente,
    updated_at     = now();

COMMIT;
