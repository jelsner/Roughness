# Reported whole-track endpoints, matched sampling, and local land-cover covariates.
# WGS84 Albers matches the native NLCD projection without remote datum-grid downloads.
genesis_crs <- "+proj=aea +lat_1=29.5 +lat_2=45.5 +lat_0=23 +lon_0=-96 +datum=WGS84 +units=m +no_defs"
genesis_domain <- function(bbox = c(-102, -95, 36, 42)) {
  # Densify constant-latitude edges before projection; four projected corners
  # alone replace latitude boundaries with straight chords.
  lon <- seq(bbox[1],bbox[2],length.out=201)
  lat <- seq(bbox[3],bbox[4],length.out=201)
  ring <- rbind(cbind(lon,bbox[3]),cbind(bbox[2],lat[-1]),
                cbind(rev(lon)[-1],bbox[4]),cbind(bbox[1],rev(lat)[-1]))
  sf::st_sfc(sf::st_polygon(list(ring)),crs=4326)
}

valid_endpoint <- function(lon, lat) {
  is.finite(lon) & is.finite(lat) & lon >= -180 & lon <= 180 &
    lat >= -90 & lat <= 90 & lon != 0 & lat != 0
}

select_rating_tracks <- function(tracks, group=c("all","weak","strong")) {
  group <- match.arg(group)
  keep <- switch(group,all=rep(TRUE,nrow(tracks)),
                 weak=tracks$mag %in% 0:1,strong=tracks$mag %in% 2:5)
  tracks[keep, ,drop=FALSE]
}
prepare_whole_tracks <- function(path, bbox=c(-102,-95,36,42), years=2000:2024) {
  s <- readr::read_csv(path, show_col_types=FALSE, progress=FALSE)
  needed <- c("om","yr","mo","dy","date","slat","slon","elat","elon","sg","mag")
  if (!all(needed %in% names(s))) stop("Expected SPC actual-tornado CSV columns")
  if (any(s$sg != 1, na.rm=TRUE) || anyNA(s$sg)) stop("Use the SPC actual_tornadoes whole-track file")
  s$source_row <- seq_len(nrow(s))
  s <- s[s$yr %in% years, ]
  duplicate <- duplicated(s[setdiff(names(s), "source_row")])
  n_duplicate <- sum(duplicate)
  s <- s[!duplicate, ]
  valid_start <- valid_endpoint(s$slon,s$slat)
  in_domain <- valid_start & s$slon >= bbox[1] & s$slon <= bbox[2] &
    s$slat >= bbox[3] & s$slat <= bbox[4]
  s <- s[in_domain, ]
  s$track_id <- paste0("spc-",s$yr,"-row-",s$source_row)
  s$event_date <- as.Date(s$date)
  s$landcover_year <- s$yr - 1L
  s$valid_end <- valid_endpoint(s$elon,s$elat)
  s$distinct_end <- s$valid_end & (s$slon != s$elon | s$slat != s$elat)
  s$end_in_domain <- s$valid_end & s$elon >= bbox[1] & s$elon <= bbox[2] &
    s$elat >= bbox[3] & s$elat <= bbox[4]
  s$displacement_km <- NA_real_
  if (any(s$valid_end)) {
    a <- sf::st_as_sf(s[s$valid_end,], coords=c("slon","slat"), crs=4326)
    b <- sf::st_as_sf(s[s$valid_end,], coords=c("elon","elat"), crs=4326)
    s$displacement_km[s$valid_end] <- as.numeric(sf::st_distance(
      sf::st_transform(a,genesis_crs), sf::st_transform(b,genesis_crs), by_element=TRUE))/1000
  }
  if (anyNA(s$event_date) || anyDuplicated(s$track_id)) stop("Invalid dates or track IDs")
  attr(s,"national_exact_duplicates_removed") <- n_duplicate
  s
}

make_genesis_sites <- function(tracks, bbox=c(-102,-95,36,42), n_controls=10L,
                               inner_km=5, outer_km=30, seed=20261014) {
  stopifnot(n_controls >= 1, inner_km >= 0, outer_km > inner_km)
  set.seed(seed)
  starts <- sf::st_transform(sf::st_as_sf(tracks, coords=c("slon","slat"),
                                         crs=4326, remove=FALSE),genesis_crs)
  xy <- sf::st_coordinates(starts)
  out <- vector("list",nrow(tracks))
  for (i in seq_len(nrow(tracks))) {
    candidates <- matrix(numeric(),ncol=2)
    attempts <- 0L
    while(nrow(candidates) < n_controls) {
      attempts <- attempts+1L
      if(attempts > 100) stop("Unable to sample controls inside the domain")
      # sqrt gives uniform area within the annulus, rather than uniform radius.
      distance <- sqrt(runif(n_controls*3, inner_km^2, outer_km^2))*1000
      angle <- runif(length(distance),0,2*pi)
      q <- cbind(xy[i,1]+distance*cos(angle), xy[i,2]+distance*sin(angle))
      qsf <- sf::st_as_sf(data.frame(x=q[,1],y=q[,2]),coords=c("x","y"),crs=genesis_crs)
      geographic <- sf::st_coordinates(sf::st_transform(qsf,4326))
      inside <- geographic[,1]>=bbox[1] & geographic[,1]<=bbox[2] &
        geographic[,2]>=bbox[3] & geographic[,2]<=bbox[4]
      candidates <- rbind(candidates,q[inside,,drop=FALSE])
    }
    qsf <- sf::st_transform(sf::st_as_sf(data.frame(
      x=candidates[seq_len(n_controls),1], y=candidates[seq_len(n_controls),2]),
      coords=c("x","y"),crs=genesis_crs),4326)
    q <- sf::st_coordinates(qsf)
    roles <- c("start", if(tracks$distinct_end[i]) "end", rep("background",n_controls))
    lon <- c(tracks$slon[i], if(tracks$distinct_end[i]) tracks$elon[i], q[,1])
    lat <- c(tracks$slat[i], if(tracks$distinct_end[i]) tracks$elat[i], q[,2])
    out[[i]] <- data.frame(track_id=tracks$track_id[i], event_date=tracks$event_date[i],
      year=tracks$yr[i], month=as.integer(tracks$mo[i]), landcover_year=tracks$landcover_year[i],
      role=roles, lon=lon, lat=lat, site_id=paste0(tracks$track_id[i],"-",seq_along(roles)))
  }
  dplyr::bind_rows(out)
}

nlcd_classes <- c(11L,12L,21L,22L,23L,24L,31L,41L,42L,43L,52L,71L,81L,82L,90L,95L)
class_fractions <- function(raster, sites, radius_m) {
  points <- terra::vect(sites,geom=c("lon","lat"),crs="EPSG:4326")
  points <- terra::project(points, terra::crs(raster))
  polygons <- terra::buffer(points, width=radius_m, quadsegs=30)
  z <- terra::extract(raster,polygons,ID=TRUE)
  v <- as.integer(z[[2]])
  code <- match(v,nlcd_classes)
  good <- !is.na(code)
  n <- nrow(sites); k <- length(nlcd_classes)
  counts <- matrix(tabulate((z$ID[good]-1L)*k + code[good],nbins=n*k),nrow=n,byrow=TRUE)
  total <- tabulate(z$ID, nbins=n)
  valid <- rowSums(counts)
  f <- counts / pmax(valid,1)
  colnames(f) <- paste0("lc_",nlcd_classes)
  data.frame(site_id=sites$site_id, radius_m=radius_m, coverage=valid/pmax(total,1),
             pixel_count=valid, f, check.names=FALSE)
}

season_category <- function(month) {
  # Fixed calendar proxy; snow cover and actual crop phenology are not observed.
  ifelse(month %in% c(11,12,1,2),1L, ifelse(month %in% 3:5,3L,
    ifelse(month %in% 6:8,4L,5L)))
}
add_roughness <- function(sites, fractions, lookup, min_coverage=0.99) {
  x <- merge(sites,fractions,by="site_id",sort=FALSE)
  x <- x[match(fractions$site_id,x$site_id), ]
  season <- season_category(x$month)
  f <- as.matrix(x[paste0("lc_",nlcd_classes)])
  stopifnot(all(nlcd_classes %in% lookup$class))
  lookup <- lookup[match(nlcd_classes,lookup$class), ]
  seasonal <- as.matrix(lookup[paste0("season_",1:5)])
  x$log2_z0 <- vapply(seq_len(nrow(x)),function(i) sum(f[i,]*log2(seasonal[,season[i]])),numeric(1))
  x$log2_z0_summer <- as.numeric(f %*% log2(lookup$season_4))
  x$z0_m <- 2^x$log2_z0
  x$developed_fraction <- rowSums(f[,nlcd_classes %in% 21:24,drop=FALSE])
  x$forest_fraction <- rowSums(f[,nlcd_classes %in% 41:43,drop=FALSE])
  x$water_fraction <- f[,nlcd_classes==11]
  x$landcover_ok <- is.finite(x$coverage) & x$coverage >= min_coverage
  x
}

static_site_covariates <- function(sites, dem_path, population_path, radius_m=1000) {
  p <- terra::vect(sites,geom=c("lon","lat"),crs="EPSG:4326")
  dem <- terra::rast(dem_path)
  b <- terra::buffer(terra::project(p,genesis_crs),radius_m)
  dem <- terra::crop(dem, terra::ext(terra::project(b,terra::crs(dem))))
  # DEM neighborhood SD, not aerodynamic roughness, is the terrain adjustment.
  b <- terra::project(b,terra::crs(dem))
  v <- terra::extract(dem,b,fun=mean,na.rm=TRUE)[,2]
  sd <- terra::extract(dem,b,fun=stats::sd,na.rm=TRUE)[,2]
  population <- terra::rast(population_path)
  pop <- terra::extract(population,terra::project(p,terra::crs(population)),method="bilinear")[,2]
  data.frame(site_id=sites$site_id,elevation_100m=v/100,
             elevation_sd_10m=sd/10,log2_population=log2(pmax(pop,0)+1))
}

complete_matched_sets <- function(x, design=c("genesis","endpoints"), n_controls=10L,
                                  tracks=NULL, min_displacement_km=0, ends_inside=FALSE) {
  design <- match.arg(design)
  x <- x[x$role %in% if(design=="genesis") c("start","background") else c("start","end"), ]
  x$case <- as.integer(x$role=="start")
  required <- c("log2_z0","log2_z0_summer","elevation_100m","elevation_sd_10m","log2_population")
  good <- x$landcover_ok & apply(is.finite(as.matrix(x[required])),1,all)
  expected <- if(design=="genesis") n_controls+1L else 2L
  sets <- split(seq_len(nrow(x)),x$track_id)
  keep <- vapply(sets,function(i) length(i)==expected && all(good[i]) && sum(x$case[i])==1L,logical(1))
  if(design=="endpoints" && !is.null(tracks)) {
    eligible <- tracks$distinct_end & tracks$displacement_km >= min_displacement_km
    if(ends_inside) eligible <- eligible & tracks$end_in_domain
    keep <- keep & names(keep) %in% tracks$track_id[eligible]
  }
  x[x$track_id %in% names(keep)[keep], ]
}

fit_genesis_clogit <- function(x, roughness="log2_z0", adjusted=TRUE, developed_adjustment=FALSE) {
  # One case per stratum: Efron and exact conditional likelihood agree. Efron permits
  # sandwich covariance clustered by date, allowing dependence within an outbreak day.
  if(length(unique(x$track_id)) < 20) stop("Too few complete matched sets")
  x$date_cluster <- as.character(x$event_date)
  rhs <- roughness
  if(adjusted) rhs <- paste(rhs,"+ elevation_100m + elevation_sd_10m + log2_population")
  if(developed_adjustment) rhs <- paste(rhs,"+ developed_fraction")
  coxph <- survival::coxph
  Surv <- survival::Surv
  strata <- survival::strata
  cluster <- survival::cluster
  formula <- stats::as.formula(paste("case ~",rhs,"+ strata(track_id) + cluster(date_cluster)"))
  survival::clogit(formula,data=x,method="efron",model=TRUE)
}

clogit_effect <- function(model, term="log2_z0") {
  b <- stats::coef(model)[[term]]
  se <- sqrt(stats::vcov(model)[term,term])
  data.frame(log_odds=b,robust_se=se,odds_ratio=exp(b),lower_95=exp(b-1.96*se),
             upper_95=exp(b+1.96*se))
}

rating_comparison <- function(x, tracks) {
  # Rating is a track-level attribute: assign it to the case AND all alternatives.
  x$mag <- tracks$mag[match(x$track_id,tracks$track_id)]
  x <- x[x$mag %in% 0:5, ,drop=FALSE]
  x$stronger <- as.integer(x$mag>=2)
  groups <- tapply(x$track_id,x$stronger,function(z) length(unique(z)))
  if(length(groups)!=2L || any(groups<20)) stop("Too few sets in a rating group")
  terms <- c("log2_z0","elevation_100m","elevation_sd_10m","log2_population")
  # Interact every slope so each rating group has its own nuisance adjustments.
  # No group intercept: it is constant within track and absorbed by the strata.
  for(term in terms) x[[paste0("stronger_",term)]] <- x$stronger*x[[term]]
  fit <- fit_genesis_clogit(x,roughness=paste(c(terms,paste0("stronger_",terms)),collapse=" + "),
                            adjusted=FALSE)
  b <- stats::coef(fit); v <- stats::vcov(fit)
  contrast <- function(weights,label) {
    w <- setNames(rep(0,length(b)),names(b)); w[names(weights)] <- weights
    estimate <- sum(w*b); se <- sqrt(as.numeric(t(w)%*%v%*%w))
    data.frame(contrast=label,log_odds=estimate,robust_se=se,
      odds_ratio=exp(estimate),lower_95=exp(estimate-1.96*se),
      upper_95=exp(estimate+1.96*se),p_two_sided=2*stats::pnorm(-abs(estimate/se)))
  }
  effects <- rbind(contrast(c(log2_z0=1),"F/EF0–1 slope"),
    contrast(c(log2_z0=1,stronger_log2_z0=1),"F/EF2+ slope"),
    contrast(c(stronger_log2_z0=1),"F/EF2+ / F/EF0–1 odds-ratio ratio"))
  list(model=fit,effects=effects,sets=data.frame(group=c("F/EF0–1","F/EF2+"),
    matched_sets=as.integer(groups)))
}

paired_difference <- function(x, bootstrap=999L, seed=20261014) {
  a <- x[x$role=="start",c("track_id","event_date","log2_z0")]
  b <- x[x$role=="end",c("track_id","log2_z0")]
  pairs <- merge(a,b,by="track_id",suffixes=c("_start","_end"))
  pairs$difference <- pairs$log2_z0_start - pairs$log2_z0_end
  groups <- split(pairs$difference,as.character(pairs$event_date))
  set.seed(seed)
  estimates <- replicate(bootstrap,{
    j <- sample.int(length(groups),replace=TRUE)
    mean(unlist(groups[j],use.names=FALSE))
  })
  list(pairs=pairs,summary=data.frame(pairs=nrow(pairs),days=length(groups),
    mean_log2_difference=mean(pairs$difference),
    lower_95=unname(stats::quantile(estimates,.025)),
    upper_95=unname(stats::quantile(estimates,.975))))
}
