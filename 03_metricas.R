# =============================================================================
# ClimaRep - Paso 3: Métricas de red
# =============================================================================
#  Presente:
#   3.1  N2000CRS  → redundancia climática de la red de APs
#   3.2  EUCRS     → redundancia climática de fondo (referencia europea)
#   3.3  RCRI      → log10(N2000CRS_norm / EUCRS_norm): sobre/infra-representación
#
# Cambio climático:
#   3.4  N2000CRS_stable / _lost / _novel → overlay de trayectorias de cambio
#   3.5  N2000CRS_presente, N2000CRS_futuro, ΔN2000CRS
#   3.6  RCRI_futuro, ΔRCRI
#
# Salidas en results/04_metrics/:
#   N2000CRS.tif, EUCRS.tif, RCRI.tif
#   N2000CRS_stable.tif, N2000CRS_lost.tif, N2000CRS_novel.tif
#   N2000CRS_present.tif, N2000CRS_future.tif, delta_N2000CRS.tif
#   RCRI_future.tif, delta_RCRI.tif

source("0_configuracion.R")

library(terra)
library(ClimaRep)

dir.create(DIR_OUT_METRICS, recursive = TRUE, showWarnings = FALSE)

# 3.1 N2000CRS: redundancia de la red----
#
# rep_overlay() suma todos los rásteres binarios de representatividad:
# N2000CRS(c) = nº de APs para las que la celda c es análoga.

message("3.1 Calculando N2000CRS")

ClimaRep::rep_overlay(
  folder_path = file.path(DIR_OUT_APS, "Representativeness"),
  output_dir  = file.path(DIR_OUT_METRICS, "N2000CRS"),
  change = FALSE)

n2000crs_file <- list.files(
  file.path(DIR_OUT_METRICS, "N2000CRS"),
  "\\.tif$", full.names = TRUE)[1]
n2000crs <- terra::rast(n2000crs_file)
names(n2000crs) <- "N2000CRS"
terra::writeRaster(n2000crs, file.path(DIR_OUT_METRICS, "N2000CRS.tif"), overwrite = TRUE)

# 3.2 EUCRS: redundancia de fondo----
#
# EUCRS(c) = nº de celdas de la cuadrícula cuyo espacio climático alcanza c.
# Representa la redundancia climática esperada si toda la región estuviera protegida.

message("3.2 Calculando EUCRS")

ClimaRep::rep_overlay(
  folder_path = file.path(DIR_OUT_GRID, "Representativeness"),
  output_dir  = file.path(DIR_OUT_METRICS, "EUCRS"),
  change = FALSE)

eucrs_file <- list.files(
  file.path(DIR_OUT_METRICS, "EUCRS"),
  "\\.tif$", full.names = TRUE
)[1]
eucrs <- terra::rast(eucrs_file)
names(eucrs) <- "EUCRS"
terra::writeRaster(eucrs, file.path(DIR_OUT_METRICS, "EUCRS.tif"), overwrite = TRUE)

# 3.3 RCRI: índice relativo de representatividad climática ----
#
# RCRI = log10(N2000CRS_norm / EUCRS_norm)
# Normalizar por la suma total antes del cociente hace RCRI independiente del
# número de APs y del número de celdas de la cuadrícula.
#   RCRI > 0: sobre-representación de esa celda en la red
#   RCRI < 0: infra-representación de esa celda en la red

message("3.3  Calculando RCRI")

n2000crs_norm <- n2000crs / terra::global(n2000crs, "max", na.rm = TRUE)[[1]]
eucrs_norm    <- eucrs    / terra::global(eucrs,    "max", na.rm = TRUE)[[1]]

rcri <- log10(n2000crs_norm / eucrs_norm)
rcri <- terra::ifel(rcri < -9999, NA, rcri)
names(rcri) <- "RCRI"
terra::writeRaster(rcri, file.path(DIR_OUT_METRICS, "RCRI.tif"), overwrite = TRUE)

message("   RCRI: [",
        round(terra::global(rcri, "min", na.rm = TRUE)[[1]], 2), ", ",
        round(terra::global(rcri, "max", na.rm = TRUE)[[1]], 2), "]")

# 3.4 Overlays de cambio: Stable / Lost / Novel----
#
# rep_overlay() aplicado a los rásteres de mh_rep_ch() descompone los valores
# codificados (1=Stable, 2=Lost, 3=Novel) y produce conteos separados.
# N2000CRS_stable(c) = nº de APs que mantienen c como análogo en el futuro.
# N2000CRS_lost(c)   = nº de APs que pierden c como análogo.
# N2000CRS_novel(c)  = nº de APs que ganan c como análogo.

message("3.4  Calculando overlays de cambio (Stable / Lost / Novel)")

ClimaRep::rep_overlay(
  folder_path = file.path(DIR_OUT_CHANGE, "Change"),
  output_dir  = file.path(DIR_OUT_METRICS, "change_overlay"),
  change = TRUE
)

# Leer los tres rásteres de cambio producidos por rep_overlay
overlay_dir   <- file.path(DIR_OUT_METRICS, "change_overlay", "individual_bands")
overlay_files <- list.files(overlay_dir, "\\.tif$", full.names = TRUE)

n2000crs_stable <- terra::rast(grep("stable|Stable|_G_", overlay_files, value = TRUE)[1])
n2000crs_lost   <- terra::rast(grep("lost|Lost|_R_",   overlay_files, value = TRUE)[1])
n2000crs_novel  <- terra::rast(grep("novel|Novel|_B_", overlay_files, value = TRUE)[1])

names(n2000crs_stable) <- "N2000CRS_stable"
names(n2000crs_lost)   <- "N2000CRS_lost"
names(n2000crs_novel)  <- "N2000CRS_novel"

# 3.5 Redundancia presente y futura, cambio neto----

message("3.5  Calculando N2000CRS presente/futuro y ΔN2000CRS")

# Presente = celdas que la AP representa ahora (stable + lost)
n2000crs_present <- n2000crs_stable + n2000crs_lost
names(n2000crs_present) <- "N2000CRS_present"

# Futuro = celdas que la AP representará (stable + novel)
n2000crs_future  <- n2000crs_stable + n2000crs_novel
names(n2000crs_future) <- "N2000CRS_future"

# Cambio neto de redundancia por celda
delta_n2000crs <- n2000crs_future - n2000crs_present
names(delta_n2000crs) <- "delta_N2000CRS"

# 3.6 RCRI futuro y ΔRCRI----
#
# El denominador se fija al EUCRS presente para que RCRI_presente y RCRI_futuro
# sean directamente comparables (cambio imputable al CC, no al fondo climático).

message("3.6  Calculando RCRI_futuro y ΔRCRI")

n2000crs_future_norm <- n2000crs_future / terra::global(n2000crs_future, "max", na.rm = TRUE)[[1]]

rcri_future <- log10(n2000crs_future_norm / eucrs_norm)
rcri_future <- terra::ifel(rcri_future < -9999, NA, rcri_future)
names(rcri_future) <- "RCRI_future"

delta_rcri <- rcri_future - rcri
names(delta_rcri) <- "delta_RCRI"

rasters_out <- list(
  N2000CRS_stable  = n2000crs_stable,
  N2000CRS_lost    = n2000crs_lost,
  N2000CRS_novel   = n2000crs_novel,
  N2000CRS_present = n2000crs_present,
  N2000CRS_future  = n2000crs_future,
  delta_N2000CRS   = delta_n2000crs,
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

message("Rásteres guardados en: ", DIR_OUT_METRICS)
message("Paso 3 completado.")
