# El Completo — estándar nutricional v1

## Presentación (obligatoria)

1. **Resumen siempre visible:** energía (kcal), proteínas, carbohidratos, grasas totales, grasas saturadas y fibra; todos **por una porción definida**.
2. **Detalle desplegable:** bloque HTML `<details>` con tabla completa; compatible con Quartz y Markdown.
3. **Porción precisa:** descripción doméstica, peso final en gramos (o volumen en mL), rendimiento total medido, número de porciones; declarar exclusión/inclusión de acompañamientos.
4. **Datos:** valores en frontmatter YAML `nutricion.valores_por_porcion`, fuente, método, fecha y estado.
5. **Nulos:** `null` en YAML y `ND` en pantalla son **desconocidos**, nunca cero. No publicar cifras estimadas como verificadas.
6. **Unidades:** kcal, kJ, g, mg, µg. Mantener unidades en el nombre o visualización del campo.
7. **Datos para cálculo:** pesar ingredientes, indicar cocido/crudo, etiqueta/marca de procesados, aceite consumido, partes desechadas, rendimiento y tamaño de las porciones. Calcular por suma de nutrientes de ingredientes dividido por porciones; cuando corresponda, ajustar pérdidas y conversiones con fuente documentada.
8. **Opcionales:** excluir de la estimación base salvo declaración expresa.
9. **Clasificaciones:** `clasificaciones_verificadas` sólo puede contener etiquetas cuya regla documentada y datos las respalden; evitar inferencias clínicas.
10. **Fuentes preferidas:** Canadian Nutrient File (Health Canada), USDA FoodData Central y etiquetas de productos concretos. No sustituir datos faltantes por resultados generados sin fuentes.

## Campos de la tabla detallada

- Energía kcal/kJ; proteínas; carbohidratos; fibra; azúcares totales/añadidos.
- Grasa total, saturada, monoinsaturada, poliinsaturada, trans; omega-3/omega-6.
- Colesterol; sodio; potasio; calcio; hierro; magnesio; zinc.
- Vitaminas B12, C, D y folato; % VD canadiense cuando corresponde y se conoce.

## Clasificaciones futuras

Alto/fuente de proteína, alto/fuente de fibra, bajo en sodio, bajo en grasas saturadas, sin azúcares añadidos, y restricciones alimentarias comprobadas. Para afirmaciones regulatorias, usar los umbrales y condiciones canadienses correspondientes, no un umbral arbitrario de gramos por porción. No usar «saludable para el corazón» ni categorías médicas automáticas.

## Alcance de la adopción

Las recetas existentes sin datos fiables deben quedar sin valores, no recalcularse de forma inventada. Nuevas recetas deben seguir esta plantilla. La ficha piloto es el burrito de porotos negros y champiñones.
