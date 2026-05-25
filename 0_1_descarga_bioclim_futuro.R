# =============================================================================
# Descarga de datos bioclimáticos futuros de CHELSA V2.1
# Estructura URL ejemplo:
# https://os.unil.cloud.switch.ch/chelsa02/chelsa/global/bioclim/bio01/
#   2011-2040/GFDL-ESM4/ssp585/CHELSA_gfdl-esm4_ssp585_bio01_2011-2040_V.2.1.tif
# =============================================================================

# --- Aumentar timeout (los .tif son pesados ~1GB) -----------------------------
options(timeout = 6000)  # 100 minutos

# --- CONFIGURACIÓN ------------------------------------------------------------
base_dir <- "C:/A_TRABAJO/DATA/CHELSA/FUTURE"

# Períodos a descargar (formato URL: "AAAA-AAAA") c("2011-2040", "2041-2070", "2071-2100")
periodos <- c("2041-2070")

# Escenarios SSP a descargar c("ssp126", "ssp370", "ssp585")
ssps <- c("ssp126")

# Modelos GCM (5 disponibles en CHELSA V2.1)
gcms <- c("GFDL-ESM4", "IPSL-CM6A-LR", "MPI-ESM1-2-HR",
          "MRI-ESM2-0", "UKESM1-0-LL")

# Variables bioclimáticas (bio01 a bio19)
bios <- sprintf("bio%02d", 1:19)   # En la URL son bio1, bio2... bio19 (sin cero)

version <- "V.2.1"
url_base <- "https://os.unil.cloud.switch.ch/chelsa02/chelsa/global/bioclim"

# --- LOOPS DE DESCARGA --------------------------------------------------------
total_archivos <- length(periodos) * length(ssps) * length(gcms) * length(bios)
contador <- 0

for (periodo in periodos) {
  # Para nombres de carpeta locales usamos guión bajo: 2011_2040
  periodo_carpeta <- gsub("-", "_", periodo)
  
  for (ssp in ssps) {
    for (gcm in gcms) {
      
      # Carpeta destino: FUTURE/2041_2070/SSP585/GFDL-ESM4/
      dest_dir <- file.path(base_dir,
                            periodo_carpeta,
                            toupper(ssp),     # SSP585 en lugar de ssp585
                            gcm)
      
      if (!dir.exists(dest_dir)) {
        dir.create(dest_dir, recursive = TRUE)
      }
      
      for (bio in bios) {
        contador <- contador + 1
        
        # En el nombre del archivo el modelo va en minúsculas
        gcm_minus <- tolower(gcm)
        
        file_name <- paste0("CHELSA_", gcm_minus, "_", ssp, "_",
                            bio, "_", periodo, "_", version, ".tif")
        
        url <- paste(url_base, bio, periodo, gcm, ssp, file_name, sep = "/")
        dest_file <- file.path(dest_dir, file_name)
        
        # Saltar si ya existe y pesa más de 0 (descarga válida)
        if (file.exists(dest_file) && file.info(dest_file)$size > 0) {
          message(sprintf("[%d/%d] EXISTE, saltando: %s",
                          contador, total_archivos, file_name))
          next
        }
        
        message(sprintf("[%d/%d] Descargando: %s",
                        contador, total_archivos, file_name))
        
        tryCatch({
          download.file(url, dest_file, mode = "wb", quiet = FALSE)
          
          # Verificación: si el archivo descargado pesa muy poco, borrarlo
          if (file.info(dest_file)$size < 1000) {
            file.remove(dest_file)
            message("  -> Archivo sospechosamente pequeño, eliminado.")
          }
        }, error = function(e) {
          message(sprintf("  -> ERROR descargando %s: %s",
                          file_name, conditionMessage(e)))
          if (file.exists(dest_file)) file.remove(dest_file)
        })
      }
    }
  }
}

message("Proceso terminado.")