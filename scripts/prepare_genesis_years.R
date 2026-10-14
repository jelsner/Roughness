# Optional independent cache worker: Rscript scripts/prepare_genesis_years.R 2010 2011
source("R/genesis.R")
source("R/genesis_landcover.R")
options(timeout=600)
Sys.setenv(GDAL_DISABLE_READDIR_ON_OPEN="EMPTY_DIR",CPL_VSIL_CURL_ALLOWED_EXTENSIONS=".tif",
           GDAL_HTTP_MULTIRANGE="YES",VSI_CACHE="TRUE",VSI_CACHE_SIZE="50000000")
config <- jsonlite::read_json("data/processed/genesis/design.json",simplifyVector=TRUE)
sites <- readr::read_csv("data/processed/genesis/sites.csv.gz",show_col_types=FALSE)
for(year in as.integer(commandArgs(trailingOnly=TRUE))) {
  stopifnot(year %in% sites$landcover_year)
  invisible(prepare_landcover_year(year,sites,config,config$design_sha256))
}
