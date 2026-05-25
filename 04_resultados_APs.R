# =============================================================================
# ClimaRep - Paso 4: Estadísticas de resumen por AP
# =============================================================================
# Extrae las métricas de red sobre los polígonos de cada AP y produce:
#
# Por AP (Paper 2 – presente):
#   RCRI_present_P10, RCRI_present_P50, RCRI_present_P90  → distribución de sobre/infra-representación
#   Singularity_P10                                       → P10 de N2000CRS_present interno: APs con climas únicos
#
# Por AP (Paper 3 – cambio):
#   cells_stable, cells_lost, cells_novel  → extensión de cada trayectoria
#   Resilience_rep                          → fracción estable / total presente
#   delta_RCRI_P50                          → cambio neto de representatividad
#
# Salidas:
#   results/04_metrics/tabla_metrics.csv
#   results/04_metrics/N2000_metrics.shp

source("0_configuracion.R")

library(terra)
library(sf)
library(dplyr)

# Cargar rásteres de métricas----

load_raster <- function(name) terra::rast(file.path(DIR_OUT_METRICS, paste0(name, ".tif")))

# Todos los rásteres son ahora derivados de mh_rep_ch() (ver scripts 02 y 03).
# El antiguo "N2000CRS" (output directo de mh_rep) se sustituye por
# "N2000CRS_present", que es Stable + Lost — análogos en el presente.
r_n2000crs_pres  <- load_raster("N2000CRS_present")
r_rcri_present   <- load_raster("RCRI_present")
r_rcri_future    <- load_raster("RCRI_future")
r_delta_rcri     <- load_raster("delta_RCRI")
r_stable         <- load_raster("N2000CRS_stable")
r_lost           <- load_raster("N2000CRS_lost")
r_novel          <- load_raster("N2000CRS_novel")
r_present        <- load_raster("N2000CRS_present")
r_future         <- load_raster("N2000CRS_future")
r_delta_n2000crs <- load_raster("delta_N2000CRS")

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

extract_sum <- function(r, vect, col_name) {
  vals <- terra::extract(r, vect, fun = sum, na.rm = TRUE, ID = FALSE)
  v    <- as.numeric(vals[[1]])
  df <- data.frame(ID = seq_along(v), value = v)
  names(df)[2] <- col_name
  return(df)
}

# Métricas de distribución interna (RCRI, N2000CRS)----

message("4.1 Extrayendo estadísticas de RCRI y N2000CRS por AP")

stats_rcri_pres   <- extract_quantiles(r_rcri_present, aps_vect, "RCRI_present")
stats_rcri_future <- extract_quantiles(r_rcri_future,  aps_vect, "RCRI_future")
stats_delta_rcri  <- extract_quantiles(r_delta_rcri,   aps_vect, "delta_RCRI")

# Singularidad: P10 de N2000CRS_present interno a la AP.
# Una AP es singular (climáticamente única en la red) cuando tiene P10 bajo.
sing <- terra::extract(r_n2000crs_pres, aps_vect, ID = TRUE) |>
  rename(N2000CRS_present = 2) |>
  group_by(ID) |>
  summarise(Singularity_P10 = quantile(N2000CRS_present, 0.10, na.rm = TRUE), .groups = "drop")

# Métricas de cambio climático----
message("4.3 Calculando métricas de cambio por AP")

df_stable  <- extract_sum(r_stable,  aps_vect, "cells_stable")
df_lost    <- extract_sum(r_lost,    aps_vect, "cells_lost")
df_novel   <- extract_sum(r_novel,   aps_vect, "cells_novel")
df_present <- extract_sum(r_present, aps_vect, "cells_present")
df_future  <- extract_sum(r_future,  aps_vect, "cells_future")

# Resiliencia representacional: fracción del espacio climático presente que persiste.
# Responde a: ¿el clima que esta AP representa ahora seguirá existiendo?
resilience <- (df_stable$cells_stable + 1e-6) / (df_present$cells_present + 1e-6)

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
  mutate(
    cells_stable   = df_stable$cells_stable,
    cells_lost     = df_lost$cells_lost,
    cells_novel    = df_novel$cells_novel,
    cells_present  = df_present$cells_present,
    cells_future   = df_future$cells_future,
    Resilience_rep = resilience
  ) |>
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