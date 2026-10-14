# A year is independent and is cached separately; callers own combined manifests.
prepare_landcover_year <- function(year,sites,config,design_hash) {
  p <- terra::vect(sites,geom=c("lon","lat"),crs="EPSG:4326")
  message("Pre-event Annual NLCD ",year," for tornadoes in ",year+1)
  item_url <- paste0("https://api.water.usgs.gov/gdp/pygeoapi/stac/stac-collection/nlcd/",
                     "nlcd-LndCov/Annual_NLCD_LndCov_",year,"_CU_C1V1?f=json")
  # Frozen official discovery response is bundled, avoiding dependence on a live
  # catalog during every raster transfer. Native annual filenames encode the year.
  metadata_path <- "data/metadata/nlcd_c1v1_1999_stac.json"
  item <- jsonlite::read_json(metadata_path)
  asset <- item$assets[["tif-s3-osn"]]
  if(is.null(asset$href) || !grepl("_1999_CU_C1V1.tif$",asset$href)) stop("Unexpected pinned NLCD template")
  endpoint <- asset[["xarray:storage_options"]]$client_kwargs$endpoint_url
  href <- sub("_1999_",paste0("_",year,"_"),asset$href,fixed=TRUE)
  url <- paste0(sub("/$","",endpoint),"/",sub("^s3://","",href))
  raster_path <- file.path("data/raw/genesis",paste0("landcover_",year,".tif"))
  needs_crop <- !file.exists(raster_path)
  if(!needs_crop) {
    existing <- terra::rast(raster_path)
    required <- as.vector(terra::ext(terra::project(p,terra::crs(existing)))+max(config$radii_m))
    available <- as.vector(terra::ext(existing))
    needs_crop <- any(required[c(1,3)]<available[c(1,3)]) || any(required[c(2,4)]>available[c(2,4)])
  }
  if(needs_crop) {
    remote <- terra::rast(paste0("/vsicurl/",url))
    q <- terra::project(p,terra::crs(remote))
    bbox <- terra::ext(q)+max(config$radii_m)+90
    tmp <- paste0(raster_path,".part.tif")
    terra::crop(remote,bbox,filename=tmp,overwrite=TRUE,
                wopt=list(datatype="INT1U",gdal=c("COMPRESS=DEFLATE","TILED=YES")))
    if(!file.rename(tmp,raster_path)) stop("Cannot save land-cover crop")
  }
  r <- terra::rast(raster_path)
  if(any(abs(terra::res(r)-30)>1e-6) || terra::nlyr(r)!=1) stop("Expected native 30 m class raster")
  q <- sites[sites$landcover_year==year, ]
  pieces <- list()
  for(radius in config$radii_m) {
    cached <- file.path("data/raw/genesis",paste0("fractions_",year,"_",radius,"_",design_hash,".rds"))
    if(!file.exists(cached)) {
      message("  ",radius," m neighborhoods: ",nrow(q)," sites")
      f <- class_fractions(r,q,radius)
      saveRDS(f,cached)
    }
    pieces[[as.character(radius)]] <- readRDS(cached)
  }
  metadata <- data.frame(landcover_year=year,design_sha256=design_hash,item_url=item_url,
    raster_url=url,crop_md5=unname(tools::md5sum(raster_path)),
    metadata_md5=unname(tools::md5sum(metadata_path)),
    retrieved_utc=format(file.info(raster_path)$mtime,tz="UTC",usetz=TRUE),
    resolution_m=30,sites=nrow(q))
  list(fractions=dplyr::bind_rows(pieces),manifest=metadata)
}
