# Run from the repository root. Only preparation requires internet access.
source("R/genesis.R")
options(timeout=600)
Sys.setenv(GDAL_DISABLE_READDIR_ON_OPEN="EMPTY_DIR", CPL_VSIL_CURL_ALLOWED_EXTENSIONS=".tif",
           GDAL_HTTP_MULTIRANGE="YES", VSI_CACHE="TRUE", VSI_CACHE_SIZE="50000000")
dir.create("data/raw/genesis",recursive=TRUE,showWarnings=FALSE)
dir.create("data/processed/genesis",recursive=TRUE,showWarnings=FALSE)
config <- list(projected_crs=genesis_crs,bbox=c(-102,-95,36,42),years=2000:2024,n_controls=10L,
               inner_km=2,outer_km=10,seed=20261014L,radii_m=c(500,1000,2000),
               landcover_collection="Annual NLCD C1V1",landcover_lag_years=1L)
fetch <- function(url,path) {
  if(!file.exists(path)) {
    tmp <- paste0(path,".part")
    download.file(url,tmp,mode="wb",quiet=TRUE)
    if(!file.rename(tmp,path)) stop("Cannot save ",path)
  }
  path
}
raw <- fetch("https://www.spc.noaa.gov/wcm/data/1950-2024_actual_tornadoes.csv",
             "data/raw/spc_actual_1950_2024.csv")
if(!file.exists("data/raw/elevation/15-H.tif")) {
  fetch("https://www.viewfinderpanoramas.org/DEM/TIF15/15-H.zip","data/raw/15-H.zip")
  unzip("data/raw/15-H.zip",exdir="data/raw/elevation")
}
if(!file.exists("data/raw/usadens/usads00g/w001001.adf")) {
  listing <- unzip("usadens.zip",list=TRUE)$Name
  unzip("usadens.zip",files=listing[grepl("^usadens/",listing)],exdir="data/raw")
}
tracks <- prepare_whole_tracks(raw,config$bbox,config$years)
readr::write_csv(tracks,"data/processed/genesis/tracks.csv.gz")
sites <- make_genesis_sites(tracks,config$bbox,config$n_controls,
                            config$inner_km,config$outer_km,config$seed)
# Hash the design so stale neighborhood caches cannot be reused after sampling changes.
design_hash <- digest::digest(list(config,sites),algo="sha256")
readr::write_csv(sites,"data/processed/genesis/sites.csv.gz")
jsonlite::write_json(c(config,list(design_sha256=design_hash)),
                     "data/processed/genesis/design.json",auto_unbox=TRUE,pretty=TRUE)
static_path <- paste0("data/raw/genesis/static-",design_hash,".rds")
if(!file.exists(static_path)) {
  message("Extracting static elevation and population covariates for ",nrow(sites)," sites")
  static <- static_site_covariates(sites,"data/raw/elevation/15-H.tif",
                                   "data/raw/usadens/usads00g/w001001.adf")
  saveRDS(static,static_path)
}
readr::write_csv(readRDS(static_path),"data/processed/genesis/static_covariates.csv.gz")
all_fractions <- list(); manifest <- list()
# One compact regional native-resolution raster per year, shared across all sites/radii.
# The rectangle includes all actual ends (even outside the domain) and buffer halos.
p <- terra::vect(sites,geom=c("lon","lat"),crs="EPSG:4326")
source("R/genesis_landcover.R")
for(year in sort(unique(sites$landcover_year))) {
  prepared <- prepare_landcover_year(year,sites,config,design_hash)
  all_fractions[[as.character(year)]] <- prepared$fractions
  manifest[[as.character(year)]] <- prepared$manifest
  readr::write_csv(dplyr::bind_rows(manifest),"data/processed/genesis/landcover_manifest.csv")
}

readr::write_csv(dplyr::bind_rows(all_fractions),"data/processed/genesis/landcover_fractions.csv.gz")
inputs <- c(raw,"data/raw/elevation/15-H.tif","usadens.zip","data/metadata/aersurface_roughness.csv","data/metadata/nlcd_c1v1_1999_stac.json")
readr::write_csv(data.frame(path=inputs,md5=unname(tools::md5sum(inputs))),
                  "data/processed/genesis/input_manifest.csv")
message("Prepared ",nrow(tracks)," starts and ",sum(tracks$distinct_end)," distinct endpoint pairs.")
