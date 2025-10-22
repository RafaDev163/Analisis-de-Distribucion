# ADR-0003 • Sugerido de distribución v1 (Reglas + Runbook lógico)

> **Estatus**: Propuesto (v1 piloto)
>
> **Ámbito**: CEDIS 101/102 → Tiendas 103 (grande), 105 (mediana), 106 (chica)
>
> **No cubre**: Código/implementación (este ADR documenta reglas y flujo). Las piezas **especiales** (únicas/alto valor) se asignan **solo por Merchandising**.

---

## 1) Contexto y objetivos

* Los CEDIS **101/102** son **de paso**: todo lo que entra **debe salir** la misma semana (no hay stock de permanencia).
* El lunes llega la mercancía nueva; **jueves 14:00** es el corte operativo para tener todo listo.
* Necesitamos un **sugerido de distribución** que:

  1. Respete la **capacidad semanal real** (tiempo de picking/empaque).
  2. Asigne por **demanda (rotación)** y **cobertura (DOI)**.
  3. Priorice **Firme** frente a **Consigna** (salvo Consigna de alto valor).
  4. Integre reglas operativas (tiempos por clasificación, piezas especiales, equidad, etc.).

## 2) Datos de entrada

* **Stock nuevo** por SKU en 101/102.
* **Ventas históricas (6 meses)** por tienda × SKU.
* **Existencia actual** por tienda × SKU.
* **Clasificación → min/pza** (picking+empaque):

  * 0.5 min: textil, fibras vegetales, impresos, promocionales
  * 1.0 min: joyería, chaquira/huichol, papel/cartón, piedra, nichos, artesanía general, metales, juguetes
  * 2.0 min: madera/lacas, cerería, vidrio
  * 3.0 min: cerámica
  * N/A: arte plumario (tratamiento especial)
* **Capacidad semanal (`T_sem`)**: 30 h/semana, 1 persona en 80% de los casos; **Eficiencia provisional 0.8** → **1,440 min/sem** (ajustable al medir).
* **DOI**: min 30 días, objetivo 60, max 90.
* **Artículos nuevos**: 103=50%, 105=35%, 106=15%.
* **Piezas especiales**: bandera/etiqueta que identifica SKU de alto valor/únicos (asignación manual por Merchandising).

## 3) Reglas de negocio (v1)

1. **Regla base (salida semanal)**: todo lo que entra a 101/102 debe salir en la semana (corte jueves 14:00).
2. **Capacidad operativa**: el plan no puede exceder `T_sem` minutos.
3. **Unidad mínima**: 1 **pieza** (no hay múltiplos de empaque). El packing se hace después en cajas mixtas conforme a reglas de acomodo.
4. **Matriz de packing (operativa)**: Base = textil/fibras; Medio = frágiles/pesados (cerámica, vidrio, piedra, madera, metales, nichos, cerería, artesanía gral.); Tope = ligeros/blandos (joyería, chaquira, impresos, papel/cartón, promocionales, juguetes). **Arte plumario**: trat. especial.
5. **DOI**: asegurar cobertura ≥ 30d; objetivo 60d; tope 90d.
6. **Artículos nuevos**: 50/35/15 (103/105/106) independientemente de histórico.
7. **Consigna vs Firme**: **Firme** tiene prioridad. Consigna solo sube si es **alto valor** (ingreso \$ relevante).
8. **Priorización (pesos iniciales)**:

   * Rotación (ventas 6m) **0.40**
   * DOI (gap vs 60d) **0.30**
   * Prioridad tienda (103>105>106) **0.15**
   * Rapidez (1/min/pza) **0.10**
   * Mínimos visuales **0.00** (desactivado en v1 por decisión de Merchandising)
9. **Desempates**: 103 > menor DOI\_actual > clasificación más rápida. Si ventas y DOI son similares → aplicar **equidad** (reparto proporcional).
10. **Backlog**: si falta tiempo (`T_sem`), registrar piezas no asignadas (pendientes) para decisión operativa.
11. **Piezas especiales**: **excluidas** del cálculo; destino lo define Merchandising. Se reportan en sección separada del informe.

## 4) Flujo lógico (runbook)

1. **¿Pieza especial?**

   * Sí → **Asignación manual por Merchandising** (excluir del algoritmo).
   * No → continuar.
2. **¿SKU nuevo?**

   * Sí → aplicar **50/35/15** y saltar a selección por capacidad (Paso 6).
   * No → continuar.
3. **(Opcional) mínimos visuales**: **desactivado** en v1 (Merchandising se adapta a rotación).
4. **Calcular DOI**: consumo diario (ventas 6m / 180); DOI\_actual; gap hacia 60d.
5. **Generar lotes**: pieza=unidad mínima por tienda (solo si hay demanda/espacio lógico); **Score** = 0.40*Rot + 0.30*DOI + 0.15*Tienda + 0.10*Rapidez (+ bono Firme/Consigna de alto valor); **Densidad** = Score / min\_pza.
6. **Priorizar**: ordenar por Densidad; aplicar desempates y **equidad** cuando corresponda.
7. **Seleccionar hasta `T_sem`**: ir sumando piezas; si no cabe un bloque, fraccionar (permitido) o saltar.
8. **Validar**: no exceder DOI\_max (90d). (Máximos físicos por tienda: pendiente de integración v2 si Merch los provee.)
9. **Salida**: sugerido final (SKU×tienda×piezas), minutos usados, % capacidad, backlog, y **listado separado de piezas especiales**.

## 5) Reportes operativos sugeridos

* **Resumen capacidad**: `min_utilizados / T_sem`, % de uso.
* **Por tienda**: piezas y minutos asignados; cobertura resultante (DOI).
* **Por clasificación**: piezas, minutos, % mix.
* **Firme vs Consigna**: participación por tipo y por \$.
* **Backlog**: detalle por SKU con motivo (falta tiempo / límites).
* **Especiales**: tabla aparte con destino indicado por Merchandising.

## 6) Decisiones futuras (v2+)

* Integrar **mínimos/máximos por tienda** si Merchandising provee matriz.
* Calibrar **Eficiencia** con medición real (back-calc) y actualizar `T_sem`.
* Evaluar **sobrecostos de packing** si se detecta impacto significativo por combinaciones frágiles.
* Ajustar **pesos de priorización** tras piloto (AB/retroalimentación de operación y ventas).

## 7) Artefactos adjuntos

* **Diagrama** de flujo v1 (con piezas especiales): `docs/img/flujo_sugerido_v1_con_piezas_especiales.png` 

---

**Notas**

* Este ADR se convertirá en tarjetas Kanban de Entrega (RUNBOOK de carga semanal, validadores, reportes y CLI del MVP-1). Cuando el piloto se estabilice, actualizar a **“Aceptado”** y versionar.
