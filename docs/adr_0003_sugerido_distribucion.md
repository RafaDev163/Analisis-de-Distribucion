# ADR-0003: Lógica para el Sugerido de Distribución

## Contexto

El proyecto de *Análisis de inventario predictivo* requiere definir una metodología clara para sugerir la distribución de productos desde los almacenes centrales (101 y 102) hacia las tiendas (103, 105 y 106). Actualmente la distribución se hace manualmente con criterios no estandarizados. El objetivo es construir un proceso automatizado que:

- Use datos de ventas e inventario.
- Ajuste el reparto según rotación y potencial de cada tienda.
- Considere artículos estacionales y nuevos.
- Sea parametrizable y trazable.

## Definiciones clave

- **SKU**: en nuestro modelo corresponde a `articulo_clave` en `dim_articulo`.
- **WADS (Weighted Average Daily Sales)**: promedio diario ponderado de ventas recientes (ej. 30 días 60%, 60 días 30%, 365 días 10%). Corrige días con stock = 0.
- **Target (Inventario Objetivo)**: unidades necesarias para cubrir `DOI (días-objetivo) × WADS`.
- **NEC (Necesidad)**:
  - Bruta: `max(0, Target − Stock_tienda − En_transito)`.
  - Ajustada: `NEC_final = α × Necesidad_bruta + β × Potencial_normalizado`.
- **Artículos nuevos**: sin historial. Se reparte según regla base 50% (103), 30% (105), 20% (106) y luego se ajusta con primeras ventas.
- **Artículos estacionales**: se evalúan con ventas históricas “in-season” (meses equivalentes de años previos).

## Lógica de cálculo

1. Calcular **WADS** por SKU/tienda usando ventas con fecha por línea.
2. Definir **Target** según DOI por categoría y rotación.
3. Calcular **NEC bruta** y luego **NEC final** ponderando volumen histórico.
4. Para artículos nuevos:
   - Primera distribución = regla 50/30/20.
   - Ajustar pesos conforme entren ventas reales.
5. Restricciones de asignación:
   - Stock disponible en DC (`OnHand_101 + OnHand_102 − Seguridad_DC`).
   - Redondeo a múltiplos de empaque.
   - Capacidad máxima de anaquel (si aplica).
   - No enviar si cobertura en tienda > X días.
6. Asignación final:
   - Si ΣNEC ≤ Stock DC → asignar NEC.
   - Si ΣNEC > Stock DC → asignar proporcional a NEC, con prioridad a mayor WADS y menor cobertura.

## Parametrización requerida

- `param.dias_objetivo(categoria, doi_min, doi_max)`.
- `param.pesos_nuevo_sku(tienda, peso)`.
- `param.seguridad_dc(valor_absoluto | porcentaje)`.
- `param.multiplo_empaque(articulo_id, multiplo)`.
- `param.capacidad_anaquel(articulo_id, tienda_id, max_unidades)`.
- `dim_articulo.estacional` y (opcional) `param.temporadas(articulo_id, mes_ini, mes_fin)`.

## Ejemplos de cálculo

- **SKU normal**: rotación rápida en 105, volumen alto en 103, se ajusta para no sobrecargar a 103.
- **SKU estacional**: ventas históricas feb–abr, se usa solo ese periodo para cálculo de WADS.
- **SKU nuevo**: primera distribución con 50/30/20, luego ajuste adaptativo.

## Decisiones pendientes

- Validar días-objetivo por categoría con negocio.
- Confirmar si en tránsito se descuenta del NEC.
- Definir periodicidad del sugerido (diario, semanal).
- Documentar reglas actuales de distribución para comparar contra modelo.

## Próximos pasos

1. Validar el borrador con stakeholders de negocio (compras, logística).
2. Completar tablas de parámetros en base al catálogo maestro.
3. Prototipo SQL/Excel para casos reales.
4. Migración `V6__dist_plan_sugerido.sql` con tablas de parámetros.
5. Implementar función `dist.plan_sugerido` para generar plan de distribución.

