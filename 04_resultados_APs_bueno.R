# =============================================================================
# ClimaRep - Paso 4: Estadísticas de resumen por AP  [VERSIÓN CORREGIDA]
# =============================================================================
# CAMBIOS RESPECTO A LA VERSIÓN ORIGINAL
#
# 1. cells_stable / cells_lost / cells_novel ya NO se obtienen sumando los
#    rásteres agregados de red (N2000CRS_*) dentro del polígono de la AP.
#    Ahora se cuentan sobre el ráster de cambio individual de cada AP
#    (salida de mh_rep_ch) en TODO el dominio, con terra::freq().
#
# 2. Resilience_rep vuelve a ser una fracción (stable / present) y devuelve
#    NA cuando present == 0, en lugar del epsilon 1e-6.
#
# 3. Los conteos se unen por site_code, no por posición de fila.
#
# SUPUESTOS A VERIFICAR ANTES DE EJECUTAR (ver bloque 4.0)
#   a) Los rásteres individuales están en DIR_CHANGE_RASTERS con el patrón
#      <site_code>_rep_change.tif  (ojo a mayúsculas/minúsculas del nombre).
#   b) Codificación de categorías 1 = Stable, 2 = Lost, 3 = Novel.
# =============================================================================

source("0_configuracion.R")

library(terra)
library(sf)
library(dplyr)
library(purrr)

# Ruta y patrón de los rásteres de cambio individuales. AJUSTAR.
DIR_CHANGE_RASTERS <- DIR_OUT_APS_CHANGE
change_raster_path <- function(code) {
  file.path(DIR_CHANGE_RASTERS, paste0(tolower(code), "_rep_change.tif"))
}

# Cargar rásteres de métricas----

load_raster <- function(name) terra::rast(file.path(DIR_OUT_METRICS, paste0(name, ".tif")))

r_n2000crs_pres <- load_raster("N2000CRS_present")
r_rcri_present  <- load_raster("RCRI_present")
r_rcri_future   <- load_raster("RCRI_future")
r_delta_rcri    <- load_raster("delta_RCRI")

# Cargar APs

aps <- read_sf(file.path(DIR_OUT_APS_CHANGE, "protected_areas_filtered.shp")) |>
  st_transform(crs(r_n2000crs_pres)) |>
  mutate(
    Area_km2 = as.numeric(st_area(geometry)) / 1e6,
    AP_id    = seq_len(n())
  )

aps_vect <- terra::vect(aps)

extract_quantiles <- function(r, vect, prefix) {
  col <- names(r)[1]
  terra::extract(r, vect, ID = TRUE) |>
    rename(value = all_of(col)) |>
    group_by(ID) |>
    summarise(
      !!paste0(prefix, "_P10") := quantile(value, 0.10, na.rm = TRUE),
      !!paste0(prefix, "_P50") := quantile(value, 0.50, na.rm = TRUE),
      !!paste0(prefix, "_P90") := quantile(value, 0.90, na.rm = TRUE),
      .groups = "drop"
    )
}

# Métricas de distribución interna (RCRI, N2000CRS)----
# Estas SÍ son extracciones sobre el polígono. La pregunta es "cómo de
# representado está el clima que hay dentro de esta AP", así que el recorte
# geográfico es el correcto.

message("4.1 Extrayendo estadísticas de RCRI y N2000CRS por AP")

stats_rcri_pres   <- extract_quantiles(r_rcri_present, aps_vect, "RCRI_present")
stats_rcri_future <- extract_quantiles(r_rcri_future,  aps_vect, "RCRI_future")
stats_delta_rcri  <- extract_quantiles(r_delta_rcri,   aps_vect, "delta_RCRI")

sing <- terra::extract(r_n2000crs_pres, aps_vect, ID = TRUE) |>
  rename(N2000CRS_present = 2) |>
  group_by(ID) |>
  summarise(Singularity_P10 = quantile(N2000CRS_present, 0.10, na.rm = TRUE), .groups = "drop")

# 4.0 Índice de rásteres de cambio----
# Un .tif por AP en la subcarpeta Change, con el código como sufijo del nombre.

archivos_ch <- list.files(DIR_OUT_APS_CHANGE, pattern = "\\.tif$",
                          recursive = TRUE, full.names = TRUE)

m <- regexpr("[Ee][Ss][0-9]{7}", basename(archivos_ch))
codigos_ch  <- toupper(regmatches(basename(archivos_ch), m))
archivos_ch <- archivos_ch[m != -1]          # descarta ficheros sin código

if (length(archivos_ch) == 0) stop("No se han encontrado rásteres de cambio en ", DIR_OUT_APS_CHANGE)
if (anyDuplicated(codigos_ch)) stop("Códigos duplicados en Change/: ",
                                    paste(unique(codigos_ch[duplicated(codigos_ch)]), collapse = ", "))

idx_ch <- setNames(archivos_ch, codigos_ch)

change_raster_path <- function(code) {
  p <- idx_ch[toupper(code)]
  if (is.na(p)) NA_character_ else unname(p)
}

# Cobertura. Debe salir 0 antes de seguir.
faltan <- aps[[COL_AP_ID]][is.na(vapply(aps[[COL_AP_ID]], change_raster_path, character(1)))]
message("APs sin ráster de cambio: ", length(faltan), " de ", nrow(aps))
if (length(faltan) > 0) print(head(faltan, 20))

# 4.1 Verificación de supuestos----
# Ejecutar una vez y contrastar contra ArcGIS antes de lanzar el bucle.

verificar_codigos <- function(code) {
  p <- change_raster_path(code)
  if (is.na(p)) stop("Sin ráster para ", code)
  r <- terra::rast(p)
  message("Ráster: ", p)
  message("Categórico: ", terra::is.factor(r)[1])
  lv <- terra::cats(r)[[1]]
  if (!is.null(lv)) print(lv)
  print(terra::freq(r))
  invisible(r)
}
# verificar_codigos("ES4240016")   # esperado 5986 / 187639 / 7773

# 4.2 Conteo de trayectorias----
message("4.2 Contando trayectorias sobre el ráster individual de cada AP")

# Ajustar aquí si la verificación revela otra codificación o etiquetas distintas.
CLAVES_CAMBIO <- list(
  cells_stable = c("1", "Stable"),
  cells_lost   = c("2", "Lost"),
  cells_novel  = c("3", "Novel")
)

count_change <- function(code) {
  vacio <- data.frame(site_code = code, cells_stable = NA_real_,
                      cells_lost = NA_real_, cells_novel = NA_real_)
  p <- change_raster_path(code)
  if (is.na(p) || !file.exists(p)) {
    warning("Falta el ráster de cambio de ", code)
    return(vacio)
  }
  
  f <- try(terra::freq(terra::rast(p)), silent = TRUE)
  if (inherits(f, "try-error") || nrow(f) == 0) {
    warning("freq() ha fallado o el ráster está vacío para ", code)
    return(vacio)
  }
  
  # Normaliza a texto para comparar códigos numéricos y etiquetas por igual
  val <- trimws(as.character(f$value))
  cnt <- as.numeric(f$count)
  ok  <- !is.na(val)
  
  pick <- function(claves) {
    hit <- ok & val %in% claves
    if (!any(hit)) 0 else sum(cnt[hit])
  }
  
  # Avisa si aparecen valores fuera de los tres esperados y del fondo
  esperados <- c(unlist(CLAVES_CAMBIO, use.names = FALSE), "0", "NaN")
  raros <- setdiff(val[ok], esperados)
  if (length(raros) > 0) warning(code, ": valores no contemplados -> ",
                                 paste(raros, collapse = ", "))
  
  data.frame(
    site_code    = code,
    cells_stable = pick(CLAVES_CAMBIO$cells_stable),
    cells_lost   = pick(CLAVES_CAMBIO$cells_lost),
    cells_novel  = pick(CLAVES_CAMBIO$cells_novel)
  )
}

codigos_aps <- aps[[COL_AP_ID]]
pb <- txtProgressBar(min = 0, max = length(codigos_aps), style = 3)
lst <- vector("list", length(codigos_aps))
for (i in seq_along(codigos_aps)) {
  lst[[i]] <- count_change(codigos_aps[i])
  setTxtProgressBar(pb, i)
}
close(pb)

df_change <- dplyr::bind_rows(lst) |>
  mutate(
    cells_present  = cells_stable + cells_lost,
    cells_future   = cells_stable + cells_novel,
    Resilience_rep = if_else(cells_present > 0, cells_stable / cells_present, NA_real_)
  )

# 4.3 Controles de sanidad----
n_celdas_dominio <- terra::ncell(r_n2000crs_pres)

message("APs con conteo NA: ", sum(is.na(df_change$cells_present)))
message("APs con cells_present == 0: ", sum(df_change$cells_present == 0, na.rm = TRUE))
message("Máximo cells_present: ", max(df_change$cells_present, na.rm = TRUE),
        " sobre ", n_celdas_dominio, " celdas del dominio")

stopifnot(nrow(df_change) == nrow(aps))
stopifnot(all(df_change$cells_present <= n_celdas_dominio, na.rm = TRUE))
stopifnot(all(df_change$cells_future  <= n_celdas_dominio, na.rm = TRUE))
# Tabla final----
message("4.4 Ensamblando tabla final")

tabla_final <- aps |>
  st_drop_geometry() |>
  select(all_of(c(COL_AP_ID, COL_AP_NAME)), Area_km2, AP_id) |>
  rename(ID = AP_id) |>
  left_join(stats_rcri_pres,   by = "ID") |>
  left_join(stats_rcri_future, by = "ID") |>
  left_join(stats_delta_rcri,  by = "ID") |>
  left_join(sing,              by = "ID") |>
  left_join(df_change,         by = setNames("site_code", COL_AP_ID)) |>
  select(-ID)

write.csv(tabla_final, file.path(DIR_OUT_METRICS, "tabla_metrics.csv"), row.names = FALSE)
message("Tabla guardada: ", file.path(DIR_OUT_METRICS, "tabla_metrics.csv"))

# Shapefile final----
aps_shp <- aps |>
  select(-AP_id) |>
  bind_cols(
    tabla_final |> select(-all_of(c(COL_AP_ID, COL_AP_NAME, "Area_km2")))
  )

st_write(
  aps_shp,
  file.path(DIR_OUT_METRICS, "N2000_metrics.shp"),
  delete_layer = TRUE
)
message("Shapefile guardado: ", file.path(DIR_OUT_METRICS, "N2000_metrics.shp"))
message("Paso 4 completado.")

