# =============================================================================
# ClimaRep - Paso 1: Preparación de datos
# =============================================================================
# 1.1  Filtra variables bioclimáticas colineales (VIF)
# 1.2  Construye el ensamble multi-modelo para el clima futuro (media + SD (incertidumbre espacial))
# 1.3  Filtra polígonos de APs por área y calidad de forma (IPQ)
#
# Salidas:
#   results/01_climate/present_climate_VIF.tif
#   results/01_climate/future_climate_ensemble_MEAN.tif
#   results/01_climate/future_climate_ensemble_SD.tif
#   results/01_climate/protected_areas_filtered.shp

source("0_configuracion.R")

library(terra)
library(sf)
library(dplyr)
library(ClimaRep)

# 1.1 Clima presente----

message("1.1  Cargando variables climáticas presentes")

present_raw <- terra::rast(list.files(DIR_PRESENT_CLIMATE, "\\.tif$", full.names = TRUE))

exclude_pat  <- paste0("(", paste(EXCLUDE_BIOCLIM, collapse = "|"), ")")
present_raw  <- terra::subset(
  present_raw,
  grep(exclude_pat, names(present_raw), invert = TRUE, value = TRUE)
)

study_area  <- read_sf(PATH_STUDY_AREA) |> st_transform(crs(present_raw))
study_area_src   <- vect(PATH_STUDY_AREA)
present_raw <- terra::mask(terra::crop(present_raw, study_area), study_area)

message("Ejecutando vif_filter (umbral = ", VIF_THRESHOLD, ")")
vif_result    <- ClimaRep::vif_filter(present_raw, th = VIF_THRESHOLD)
present_clim  <- vif_result$filtered_raster
present_clim  <- project(present_clim, CHELSA_TARGET_CRS, method = "bilinear")
print(vif_result$summary)
names(present_clim) <- gsub(".*_(bio[0-9]+)_.*", "\\1", names(present_clim))
names(present_clim) <-  gsub("bio0", "bio", names(present_clim))
selected_vars <- names(present_clim)

message("Variables retenidas: ", paste(selected_vars, collapse = ", "))
print(vif_result$summary)

dir.create(DIR_OUT_CLIMATE, recursive = TRUE, showWarnings = FALSE)
terra::writeRaster(
  present_clim,
  file.path(DIR_OUT_CLIMATE, "present_climate_VIF.tif"),
  overwrite = TRUE
)

# 1.2 Clima futuro: ensamble multi-modelo----

message("1.2  Construyendo ensamble de clima futuro")

dir_stats <- file.path(DIR_OUT_CLIMATE, "ensemble_by_variable")
dir.create(dir_stats, recursive = TRUE, showWarnings = FALSE)

model_rasters <- list()
for (model in FUTURE_MODELS) {
  model_dir <- file.path(DIR_FUTURE_CLIMATE, model)
  if (!dir.exists(model_dir)) {
    warning("Carpeta de modelo no encontrada, omitiendo: ", model_dir)
    next
  }
  r <- terra::rast(list.files(model_dir, "\\.tif$", full.names = TRUE))
  names(r) <- gsub(".*_(bio[0-9]+)_.*", "\\1", names(r))
  names(r) <- gsub("bio0", "bio", names(r))
  r <- terra::subset(r, selected_vars)
  r <- terra::mask(terra::crop(r, study_area), study_area)
  model_rasters[[model]] <- r
  message("Modelo cargado: ", model)
}

for (var in selected_vars) {
  layers <- lapply(model_rasters, \(r) r[[var]])
  stk    <- terra::sds(layers)
  mean_r <- terra::app(stk, mean); names(mean_r) <- var
  sd_r   <- terra::app(stk, sd);   names(sd_r)   <- var
  terra::writeRaster(mean_r, file.path(dir_stats, paste0(var, "_MEAN.tif")), overwrite = TRUE)
  terra::writeRaster(sd_r,   file.path(dir_stats, paste0(var, "_SD.tif")),   overwrite = TRUE)
}

mean_files  <- list.files(dir_stats, "_MEAN\\.tif$", full.names = TRUE)
future_clim <- terra::rast(mean_files)
names(future_clim) <- gsub("_MEAN\\.tif$", "", basename(mean_files))
names(future_clim) <- selected_vars
terra::writeRaster(
  future_clim,
  file.path(DIR_OUT_CLIMATE, "future_climate_ensemble_MEAN.tif"),
  overwrite = TRUE
)

sd_files       <- list.files(dir_stats, "_SD\\.tif$", full.names = TRUE)
future_clim_sd <- terra::rast(sd_files)
names(future_clim_sd) <- gsub("_SD\\.tif$", "", basename(sd_files))
names(future_clim) <- selected_vars
terra::writeRaster(
  future_clim_sd,
  file.path(DIR_OUT_CLIMATE, "future_climate_ensemble_SD.tif"),
  overwrite = TRUE
)

message("Ensamble futuro guardado.")
message("Paso 1 completado.")
