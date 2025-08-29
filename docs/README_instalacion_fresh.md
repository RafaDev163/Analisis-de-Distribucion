# Instalación Fresh del Catálogo Maestro

Este documento describe los pasos mínimos para levantar la base de datos **desde cero** con el catálogo maestro final.

## 1. Preparar staging

1. Crear la tabla `stg_existencias` en la base de datos (estructura mínima):

```sql
CREATE TABLE stg_existencias (
  pr_clave    TEXT,
  descripcion TEXT,
  proveedor   TEXT,
  ps_nombre   TEXT,
  pr_almacen  TEXT,
  pr_costo    NUMERIC,
  fecha_corte DATE
);
```

2. Cargar el CSV de existencias en `stg_existencias`.
   - Asegúrate de que `pr_clave` y `proveedor` estén como **TEXT** (para evitar notación científica).
   - Incluye los almacenes 101, 102, 103, 105, 106.

Ejemplo de carga rápida (psql):
```bash
\copy stg_existencias FROM 'existencias.csv' WITH CSV HEADER
```

## 2. Ejecutar V3_final

Corre el script consolidado que crea y carga el modelo dimensional:

```bash
psql -U <usuario> -d Inventario_TMAP -f V3_final__modelo_dimensional_y_carga.sql
```

Esto crea y llena:
- `dim_proveedor`
- `dim_articulo`
- `articulo_proveedor`

Incluye lógica:
- Modalidad FIRME = NA | AFF | AF | F | FF
- Modalidad CONSIGNACION = C
- Proveedor principal asignado por reglas UNICO / VALIDADO

## 3. Ejecutar V5_final

Corre el script que crea las vistas para la UI (DROP CASCADE + CREATE):

```bash
psql -U <usuario> -d Inventario_TMAP -f V5_final_vistas.sql
```

Esto crea:
- `v_inv_principal_mod`, `v_inv_principal_total`
- `v_inv_tiendas_mod`, `v_inv_tiendas_total`
- `v_inv_disponible_mod`, `v_inv_disponible_total`
- `v_inv_articulo`, `v_inv_articulo_completo`
- Derivadas por familia y proveedor

## 4. Smoke tests

Valida que todo quedó correcto:

```sql
-- a) Sin multi-proveedor por clave
SELECT a.articulo_clave, COUNT(*) AS n_prov
FROM articulo_proveedor ap JOIN dim_articulo a USING (articulo_sk)
GROUP BY a.articulo_clave HAVING COUNT(*) > 1;

-- b) Consignación disponible (ejemplo)
SELECT a.articulo_clave, a.descripcion, SUM(v.existencia) AS existencia_total
FROM v_inv_disponible_mod v
JOIN dim_articulo a ON a.articulo_clave = v.articulo_clave
WHERE v.modalidad='CONSIGNACION' AND v.existencia>0
GROUP BY a.articulo_clave, a.descripcion
ORDER BY existencia_total DESC LIMIT 20;
```

Si estos checks salen limpios, la instalación fresh está lista.

## 5. Recomendaciones

- Crear índices en tablas base:
```sql
CREATE INDEX IF NOT EXISTS ix_fi_fecha     ON fact_inventario(fecha_corte);
CREATE INDEX IF NOT EXISTS ix_fi_articulo  ON fact_inventario(articulo_sk);
CREATE INDEX IF NOT EXISTS ix_fi_almacen   ON fact_inventario(almacen_sk);
CREATE INDEX IF NOT EXISTS ix_da_clave     ON dim_articulo(articulo_clave);
```

- Documentar la fecha del CSV de carga inicial y el tag de versión (`V3_final_YYYYMMDD`, `V5_final_YYYYMMDD`).

---

✅ Con estos pasos tendrás una instalación fresh del catálogo maestro, listo para consultas y para conectar la futura UI.
