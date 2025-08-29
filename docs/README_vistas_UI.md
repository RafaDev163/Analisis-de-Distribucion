# README_vistas_UI.md

Estas son las vistas finales pensadas para la UI. Trabajan con **articulo_clave** y exponen agregados útiles.

## Vistas principales
- `v_inv_principal_mod` — Inventario en centros de distribución (101/102) por clave, modalidad y almacén.
- `v_inv_principal_total` — Totales por clave en 101/102.
- `v_inv_tiendas_mod` — Inventario en tiendas (103/105/106) por clave, modalidad y tienda.
- `v_inv_tiendas_total` — Totales por clave en tiendas.
- `v_inv_disponible_mod` — Alias de principal (disponible para distribuir).
- `v_inv_disponible_total` — Totales disponibles por clave.
- `v_inv_articulo` — Detalle por artículo/almacén (>0 existencias).
- `v_inv_articulo_completo` — Incluye artículos sin existencia (0).
- Derivadas: `v_inv_principal_familia_*`, `v_inv_tiendas_familia_*`, `v_inv_principal_proveedor_mod`.

## Consultas útiles

**Consignación disponible (lista completa):**
```sql
SELECT a.articulo_clave, a.descripcion, SUM(v.existencia) AS existencia_total
FROM v_inv_disponible_mod v
JOIN dim_articulo a ON a.articulo_clave = v.articulo_clave
WHERE v.modalidad = 'CONSIGNACION' AND v.existencia > 0
GROUP BY a.articulo_clave, a.descripcion
ORDER BY existencia_total DESC;
```

**Ficha de artículo:**
```sql
SELECT * FROM v_inv_articulo WHERE articulo_clave = 'C015347052';
```

**Resumen por familia (101/102):**
```sql
SELECT * FROM v_inv_principal_familia_total ORDER BY existencia_total DESC LIMIT 20;
```

## Índices recomendados
```sql
CREATE INDEX IF NOT EXISTS ix_fi_fecha     ON fact_inventario(fecha_corte);
CREATE INDEX IF NOT EXISTS ix_fi_articulo  ON fact_inventario(articulo_sk);
CREATE INDEX IF NOT EXISTS ix_fi_almacen   ON fact_inventario(almacen_sk);
CREATE INDEX IF NOT EXISTS ix_da_clave     ON dim_articulo(articulo_clave);
```

## Notas
- Todas las vistas usan la **última `fecha_corte`** (`v_fecha_corte_max`).
- `dim_articulo.modalidad` clasifica **NA|AFF|AF|F|FF → FIRME** y **C → CONSIGNACION**.
