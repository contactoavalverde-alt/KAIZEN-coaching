# Fotos del Coach (carrusel "El Coach")

Carrusel coverflow 3D en `index.html` (`.swiper-coach`). Actualmente **10 fotos**:

- `coach-1.jpg` … `coach-5.jpg` — fotos originales de Kaizen (selfies)
- `coach-6.jpg` … `coach-10.jpg` — fotos nuevas (gym / boxing)

Formato: JPG. Ideal vertical (~1200x1600px). Cada `<img>` tiene
`onerror="this.style.display='none'"` para tolerar una foto faltante.

## Cambiar / agregar fotos
1. Copiar la imagen aquí con el nombre `coach-N.jpg`.
2. Si agregás más allá de 10, añadir el `<div class="swiper-slide">` correspondiente en
   `index.html` (sección `#coach`).
3. Commit + push:
   ```bash
   git add assets/ && git commit -m "update coach photos" && git push origin main
   ```

> Las demás imágenes del sitio (transformaciones, blog, testimonios) NO van aquí: se suben
> desde el backoffice a Supabase Storage.
