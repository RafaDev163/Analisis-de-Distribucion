-- V2__dim_almacen.sql
CREATE TABLE IF NOT EXISTS dim_almacen (
  almacen_sk      BIGSERIAL PRIMARY KEY,
  almacen_codigo  TEXT UNIQUE NOT NULL,
  tipo            TEXT NOT NULL,       -- PRINCIPAL | SUBPRINCIPAL | TIENDA | CERRADO | DESCONOCIDO
  nombre          TEXT,
  activo          BOOLEAN DEFAULT TRUE
);

INSERT INTO dim_almacen (almacen_codigo, tipo, nombre, activo) VALUES
 ('0','DESCONOCIDO','DESCONOCIDO',FALSE),
 ('101','SUBPRINCIPAL','Almacén 101',TRUE),
 ('102','SUBPRINCIPAL','Almacén 102',TRUE),
 ('103','TIENDA','Tienda 103',TRUE),
 ('104','CERRADO','Tienda 104 (cerrada)',FALSE),
 ('105','TIENDA','Tienda 105',TRUE),
 ('106','TIENDA','Tienda 106',TRUE)
ON CONFLICT (almacen_codigo) DO NOTHING;

-- Diagnóstico: detectar códigos de almacén en staging que no estén en la dimensión
-- (Úsalo manualmente tras cargar: si hay resultados, agregamos esos códigos a la dimensión)
-- SELECT DISTINCT s.pr_almacen
-- FROM stg_existencias s
-- LEFT JOIN dim_almacen a ON a.almacen_codigo = s.pr_almacen
-- WHERE a.almacen_codigo IS NULL;
