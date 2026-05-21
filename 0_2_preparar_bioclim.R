# =============================================================================
# ClimaRep - Paso 01: Cálculo de variables bioclimáticas desde CHELSA mensual
# =============================================================================
# Calcula climatologías mensuales (pr, tmin, tmax) sobre el periodo
# [YEAR_START, YEAR_END] a partir de CHELSA V2.1 mensual y deriva las 19
# variables bioclimáticas estándar (BIO1-BIO19) siguiendo la lógica de
# dismo::biovars (https://github.com/cran/dismo/blob/master/R/biovars.R).
#
# Entradas (definidas en 0_configuracion.R):
#   DIR_CHELSA_MONTHLY  - carpeta raíz con subcarpetas PR/, TMAX/, TMIN/
#   YEAR_START, YEAR_END
#   PATH_STUDY_AREA     - shapefile del área de estudio
#   DIR_PRESENT_CLIMATE - directorio raíz para la salida (se crea una subcarpeta
#                         con la etiqueta del periodo, p.ej. "1981-2010/")
#   CHELSA_TARGET_CRS   - CRS de salida (p.ej. "EPSG:3035")
#   NUM_CORES           - cores para terra::app

source("0_configuracion.R")

library(terra)
library(sf)

# 0. Comprobaciones previas----

stopifnot(
  exists("DIR_CHELSA_MONTHLY"), dir.exists(DIR_CHELSA_MONTHLY),
  exists("YEAR_START"), exists("YEAR_END"), YEAR_END >= YEAR_START,
  exists("CHELSA_TARGET_CRS"),
  file.exists(PATH_STUDY_AREA)
)

period_tag <- paste0(YEAR_START, "-", YEAR_END)
out_dir    <- file.path(DIR_PRESENT_CLIMATE, period_tag)
dir_month  <- file.path(out_dir, "monthly")
dir.create(dir_month, recursive = TRUE, showWarnings = FALSE)

message("Periodo:        ", period_tag)
message("CHELSA en:      ", DIR_CHELSA_MONTHLY)
message("Salida en:      ", out_dir)

# 1. Área de estudio en WGS84 (CRS nativo de CHELSA)----

study_area_src   <- vect(PATH_STUDY_AREA)
study_area_wgs84 <- project(study_area_src, "EPSG:4326")

# Pequeño margen sobre el extent para evitar pérdidas en bordes al reproyectar.
# 0.~11 km, suficiente para datos a 30 arcsec.
crop_ext <- ext(study_area_wgs84) + 0.1

# 2. Función para climatología mensual ----
# Para cada mes m (1..12) promedia los píxeles a lo largo de los años en
# [YEAR_START, YEAR_END]. Acepta tres parametrizaciones:
#   subfolder : "PR" | "TMAX" | "TMIN"
#   out_prefix: prefijo de los .tif mensuales de salida
#   is_temp   : TRUE para convertir K -> °C (resta 273.15)
#
# Convención de nombres CHELSA V2.1:
#   CHELSA_<var>_<MM>_<YYYY>_V.2.1.tif    (var ∈ {pr, tasmax, tasmin})
# Se extrae mes y año con la regex .*_(MM)_(YYYY)_.*

monthly_climatology <- function(subfolder, out_prefix, is_temp) {
  path  <- file.path(DIR_CHELSA_MONTHLY, subfolder)
  if (!dir.exists(path)) stop("No existe la carpeta: ", path)
  files <- list.files(path, pattern = "\\.tif$", full.names = TRUE)
  if (length(files) == 0) stop("No hay .tif en ", path)
  
  months <- as.integer(sub(".*_([0-9]{1,2})_([0-9]{4})_.*", "\\1", basename(files)))
  years  <- as.integer(sub(".*_([0-9]{1,2})_([0-9]{4})_.*", "\\2", basename(files)))
  keep   <- which(!is.na(years) & years >= YEAR_START & years <= YEAR_END)
  if (length(keep) == 0) stop("Sin archivos en ", subfolder, " para ", period_tag)
  files  <- files[keep]; months <- months[keep]
  
  message("[", subfolder, "] ", length(files), " ficheros en ", period_tag)
  out_layers <- vector("list", 12)
  
  for (m in 1:12) {
    m_files <- files[months == m]
    if (length(m_files) == 0) {
      warning("Sin archivos para mes ", m, " en ", subfolder); next
    }
    
    stk <- list()
    for (f in m_files) {
      r_crop <- try(crop(rast(f), crop_ext, snap = "out"), silent = TRUE)
      if (inherits(r_crop, "try-error")) {
        warning("Error leyendo ", basename(f), " - omitido")
      } else {
        stk[[length(stk) + 1]] <- r_crop
      }
    }
    
    m_avg <- mean(rast(stk), na.rm = TRUE)
    if (is_temp) m_avg <- m_avg - 273.15
    
    out_file <- file.path(dir_month, sprintf("%s_%02d.tif", out_prefix, m))
    writeRaster(m_avg, out_file, overwrite = TRUE)
    out_layers[[m]] <- m_avg
    message(sprintf("  mes %02d ok (%d ficheros)", m, length(m_files)))
    tmpFiles(remove = TRUE)
  }
  
  out <- rast(out_layers)
  names(out) <- sprintf("%s_%02d", out_prefix, 1:12)
  out
}

# 3. Climatologías mensuales ----

message("\n=== Calculando climatologías mensuales ===")
pr_clim   <- monthly_climatology("PR",   "pr",   is_temp = FALSE)
tmin_clim <- monthly_climatology("TMIN", "tmin", is_temp = TRUE)
tmax_clim <- monthly_climatology("TMAX", "tmax", is_temp = TRUE)

# 4. Función biovars (terra::app) ----
# Equivalente funcional a dismo::biovars adaptado para terra.
# Recibe 36 capas (12 pr + 12 tmin + 12 tmax) y devuelve 19 (BIO1..BIO19).
# BIO15 usa la variante (sd(p+1)/(mean(p)+1))*100 para evitar /0 en zonas áridas.
biovars_terra <- function(prec, tmin, tmax, cores = 1, ...) {
  s <- c(prec, tmin, tmax)
  
  calc_bio <- function(x) {
    if (all(is.na(x))) return(rep(NA_real_, 19))
    p  <- x[1:12]; tn <- x[13:24]; tx <- x[25:36]
    ta <- (tn + tx) / 2
    
    window_3m <- function(v) {
      v_ext <- c(v, v[1:2])
      v_ext[1:12] + v_ext[2:13] + v_ext[3:14]
    }
    p_q <- window_3m(p)        # suma trimestral de precipitación
    t_q <- window_3m(ta) / 3   # media trimestral de temperatura
    
    res <- rep(NA_real_, 19)
    res[1]  <- mean(ta)                          # BIO1
    res[2]  <- mean(tx - tn)                     # BIO2
    res[5]  <- max(tx)                           # BIO5
    res[6]  <- min(tn)                           # BIO6
    res[7]  <- res[5] - res[6]                   # BIO7
    res[3]  <- (res[2] / res[7]) * 100           # BIO3
    res[4]  <- sd(ta) * 100                      # BIO4
    res[10] <- max(t_q)                          # BIO10
    res[11] <- min(t_q)                          # BIO11
    res[8]  <- t_q[which.max(p_q)]               # BIO8
    res[9]  <- t_q[which.min(p_q)]               # BIO9
    # Precipitación
    res[12] <- sum(p)                            # BIO12
    res[13] <- max(p)                            # BIO13
    res[14] <- min(p)                            # BIO14
    res[15] <- (sd(p + 1) / (mean(p) + 1)) * 100 # BIO15
    res[16] <- max(p_q)                          # BIO16
    res[17] <- min(p_q)                          # BIO17
    res[18] <- p_q[which.max(t_q)]               # BIO18
    res[19] <- p_q[which.min(t_q)]               # BIO19
    res
  }
  
  app(s, calc_bio, cores = cores, ...)
}

# 5. Cálculo de las 19 BIO ----
message("Calculando BIO1-BIO19 (cores = ", NUM_CORES, ")")
bioclim_wgs84 <- biovars_terra(
  prec  = pr_clim, tmin = tmin_clim, tmax = tmax_clim,
  cores = NUM_CORES,
  wopt  = list(datatype = "FLT4S")
)
names(bioclim_wgs84) <- paste0("bio", 1:19)

# 6. Reproyección al CRS objetivo, recorte y guardado ----

message("Reproyectando a ", CHELSA_TARGET_CRS, " …")
study_area_tgt <- project(study_area_src, CHELSA_TARGET_CRS)
bioclim_tgt    <- project(bioclim_wgs84, CHELSA_TARGET_CRS, method = "bilinear")
bioclim_tgt    <- mask(crop(bioclim_tgt, study_area_tgt), study_area_tgt)

message("Guardando 19 rásteres bioclim")
for (i in 1:19) {
  # Nombre compatible con la regex del Paso 02:  sub("_[0-9]{4}-.*", "", names)
  out_name <- sprintf("bio%d_%s.tif", i, period_tag)
  writeRaster(
    bioclim_tgt[[i]],
    filename = file.path(out_dir, out_name),
    overwrite = TRUE,
    wopt = list(datatype = "FLT4S")
  )
  message("  ", out_name)
}

message("Hecho. Bioclim para el periodo ", period_tag, " en:")
message("  ", out_dir)
message("Para usarlas en el Paso 02, ajusta en 0_configuracion.R:")
message("DIR_PRESENT_CLIMATE <- \"", normalizePath(out_dir, winslash = "/", mustWork = FALSE), "\"")

