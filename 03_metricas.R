# =============================================================================
# ClimaRep - Paso 3: Métricas de red
# =============================================================================
# Todas las métricas se derivan de los rásteres Stable / Lost / Novel
# producidos por mh_rep_ch() (Paso 2) — tanto para las APs (N2000CRS) como
# para la cuadrícula (EUCRS). De este modo presente y futuro comparten la
# MISMA matriz de covarianza interna y todas las comparaciones (N2000CRS vs
# EUCRS, presente vs futuro, ΔN2000CRS, ΔRCRI…) son coherentes.
#
# Convenciones de derivación:
#   * stable = #APs/celdas que mantienen análogo en el futuro
#   * lost   = #APs/celdas que pierden  análogo en el futuro
#   * novel  = #APs/celdas que ganan    análogo en el futuro
#   * present = stable + lost   (análogos en el presente)
#   * future  = stable + novel  (análogos en el futuro)
#
# Métricas (carpeta DIR_OUT_METRICS):
#   N2000CRS_stable.tif, N2000CRS_lost.tif, N2000CRS_novel.tif
#   N2000CRS_present.tif, N2000CRS_future.tif, delta_N2000CRS.tif
#   EUCRS_stable.tif, EUCRS_lost.tif, EUCRS_novel.tif
#   EUCRS_present.tif, EUCRS_future.tif, delta_EUCRS.tif
#   RCRI_present.tif, RCRI_future.tif, delta_RCRI.tif

source("0_configuracion.R")

library(terra)
library(ClimaRep)
tictoc::tic()

dir.create(DIR_OUT_METRICS, recursive = TRUE, showWarnings = FALSE)

# Función auxiliar: lee los tres rásteres (stable/lost/novel) de una carpeta de overlay producida por ClimaRep::rep_overlay() con change = TRUE.
# Esta función escribe las bandas en /individual_bands/ con etiquetas que codifican:Lost (Red, _R_), Stable/Retained (Green, _G_), Novel (Blue, _B_).
read_overlay_bands <- function(overlay_dir) {
  ib <- file.path(overlay_dir, "individual_bands")
  fs <- list.files(ib, "\\.tif$", full.names = TRUE)
  list(
    stable = terra::rast(grep("stable|Stable|Retained|retained|_G_", fs, value = TRUE)[1]),
    lost   = terra::rast(grep("lost|Lost|_R_",                       fs, value = TRUE)[1]),
    novel  = terra::rast(grep("novel|Novel|_B_",                     fs, value = TRUE)[1])
  )
}

# Función auxiliar: dada una namda stable/lost/novel y un prefijo de nombre, 
# devuelve la lista completa de rásteres derivados (stable, lost, novel, present, future, delta).
build_metric_set <- function(bands, prefix) {
  stable <- bands$stable
  lost   <- bands$lost
  novel  <- bands$novel
  names(stable) <- paste0(prefix, "_stable")
  names(lost)   <- paste0(prefix, "_lost")
  names(novel)  <- paste0(prefix, "_novel")
  
  present <- stable + lost
  future  <- stable + novel
  delta   <- future - present
  names(present) <- paste0(prefix, "_present")
  names(future)  <- paste0(prefix, "_future")
  names(delta)   <- paste0("delta_", prefix)
  
  list(
    stable  = stable,
    lost    = lost,
    novel   = novel,
    present = present,
    future  = future,
    delta   = delta
  )
}


# 3.1 Overlay de los rásteres Change de las APs -> N2000CRS_* ----
message("3.1  Overlay de las APs (N2000CRS_stable / _lost / _novel)")

ClimaRep::rep_overlay(
  folder_path = file.path(DIR_OUT_APS_CHANGE, "Change"),
  output_dir  = file.path(DIR_OUT_METRICS, "N2000CRS_overlay"),
  change      = TRUE
)

n2000 <- build_metric_set(
  read_overlay_bands(file.path(DIR_OUT_METRICS, "N2000CRS_overlay")),
  prefix = "N2000CRS"
)


# 3.2 Overlay de los rásteres Change de la cuadrícula -> EUCRS_* ----
message("3.2  Overlay de la cuadrícula EUCRS (EUCRS_stable / _lost / _novel)")

ClimaRep::rep_overlay(
  folder_path = file.path(DIR_OUT_GRID_CHANGE, "Change"),
  output_dir  = file.path(DIR_OUT_METRICS, "EUCRS_overlay"),
  change      = TRUE
)

eucrs <- build_metric_set(
  read_overlay_bands(file.path(DIR_OUT_METRICS, "EUCRS_overlay")),
  prefix = "EUCRS"
)


# 3.3 RCRI presente, RCRI futuro y ΔRCRI ----
#
# RCRI = log10(N2000CRS_norm / EUCRS_norm)
#   * RCRI > 0: sobre-representación en la red
#   * RCRI < 0: infra-representación
#
# Al usar EUCRS_present y EUCRS_future calculados con el MISMO marco de
# referencia (mismo mh_rep_ch) que N2000CRS_present y N2000CRS_future,
# la comparación es internamente consistente:
#   RCRI_present = log10(N2000CRS_present_norm / EUCRS_present_norm)
#   RCRI_future  = log10(N2000CRS_future_norm  / EUCRS_present_norm)
#   delta_RCRI   = RCRI_future - RCRI_present


message("3.3  RCRI presente, RCRI futuro y ΔRCRI")

safe_norm <- function(r) r / terra::global(r, "sum", na.rm = TRUE)$sum

n2000_present_norm <- safe_norm(n2000$present)
n2000_future_norm  <- safe_norm(n2000$future)
eucrs_present_norm <- safe_norm(eucrs$present)
eucrs_future_norm  <- safe_norm(eucrs$future)

rcri_present <- log10(n2000_present_norm / eucrs_present_norm)
rcri_future <- log10(n2000_future_norm / eucrs_present_norm)

rcri_present <- terra::ifel(is.infinite(rcri_present), NA, rcri_present)
rcri_future  <- terra::ifel(is.infinite(rcri_future),  NA, rcri_future)

delta_rcri <- rcri_future - rcri_present

names(rcri_present) <- "RCRI_present"
names(rcri_future)  <- "RCRI_future"
names(delta_rcri)   <- "delta_RCRI"

message("   RCRI_present: [",
        round(terra::global(rcri_present, "min", na.rm = TRUE)[[1]], 2), ", ",
        round(terra::global(rcri_present, "max", na.rm = TRUE)[[1]], 2), "]")
message("   RCRI_future : [",
        round(terra::global(rcri_future, "min", na.rm = TRUE)[[1]], 2), ", ",
        round(terra::global(rcri_future, "max", na.rm = TRUE)[[1]], 2), "]")


# 3.4 Guardado de todos los rásteres ----

message("3.4  Guardando rásteres en ", DIR_OUT_METRICS)

rasters_out <- list(
  N2000CRS_stable  = n2000$stable,
  N2000CRS_lost    = n2000$lost,
  N2000CRS_novel   = n2000$novel,
  N2000CRS_present = n2000$present,
  N2000CRS_future  = n2000$future,
  delta_N2000CRS   = n2000$delta,
  EUCRS_stable     = eucrs$stable,
  EUCRS_lost       = eucrs$lost,
  EUCRS_novel      = eucrs$novel,
  EUCRS_present    = eucrs$present,
  EUCRS_future     = eucrs$future,
  delta_EUCRS      = eucrs$delta,
  RCRI_present     = rcri_present,
  RCRI_future      = rcri_future,
  delta_RCRI       = delta_rcri
)

for (nm in names(rasters_out)) {
  terra::writeRaster(
    rasters_out[[nm]],
    file.path(DIR_OUT_METRICS, paste0(nm, ".tif")),
    overwrite = TRUE
  )
}

message("Paso 3 completado.")
tictoc::toc()