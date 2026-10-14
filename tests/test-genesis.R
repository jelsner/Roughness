library(testthat)
source(if(file.exists("R/genesis.R")) "R/genesis.R" else "../R/genesis.R")
test_that("whole-track endpoints are not imputed and outside ends are retained", {
  s <- data.frame(om=1:4,yr=2000,mo=5,dy=1,date="2000-05-01",sg=1,mag=0,
    slon=c(-100,-100,-100,-104),slat=38,elon=c(0,-100,-94,-103),elat=c(0,38,38,38))
  p<-tempfile(fileext=".csv");readr::write_csv(s,p)
  x<-prepare_whole_tracks(p)
  expect_equal(nrow(x),3L)
  expect_equal(x$landcover_year,rep(1999,3))
  expect_equal(x$valid_end,c(FALSE,TRUE,TRUE))
  expect_equal(x$distinct_end,c(FALSE,FALSE,TRUE))
  expect_equal(x$end_in_domain,c(FALSE,TRUE,FALSE))
  expect_equal(x$elon[1],0)
  s$sg[1]<-2;readr::write_csv(s,p)
  expect_error(prepare_whole_tracks(p),"whole-track")
})
test_that("reference samples respect distance, domain, and reproducibility", {
  s <- data.frame(om=1,yr=2000,mo=5,dy=1,date="2000-05-01",sg=1,mag=0,
    slon=-101.999,slat=38,elon=-101.9,elat=38)
  p<-tempfile(fileext=".csv");readr::write_csv(s,p)
  t<-prepare_whole_tracks(p)
  q<-make_genesis_sites(t,n_controls=50,seed=42)
  expect_identical(q,make_genesis_sites(t,n_controls=50,seed=42))
  expect_equal(sum(q$role=="start"),1L)
  expect_equal(sum(q$role=="end"),1L)
  a<-sf::st_transform(sf::st_as_sf(q[q$role=="start",],coords=c("lon","lat"),crs=4326),genesis_crs)
  b<-sf::st_transform(sf::st_as_sf(q[q$role=="background",],coords=c("lon","lat"),crs=4326),genesis_crs)
  d<-as.numeric(sf::st_distance(a,b))
  expect_true(all(d>=2000 & d<=10000))
  expect_true(all(lengths(sf::st_covered_by(b,sf::st_transform(genesis_domain(),genesis_crs)))==1))
})
test_that("class fractions and geometric roughness agree on a known landscape", {
  r<-terra::rast(xmin=-2000,xmax=2000,ymin=-2000,ymax=2000,resolution=30,crs=genesis_crs)
  xy<-terra::xyFromCell(r,seq_len(terra::ncell(r)))
  terra::values(r)<-ifelse(xy[,1]<0,71L,42L)
  point<-sf::st_transform(sf::st_as_sf(data.frame(x=0,y=0),coords=c("x","y"),crs=genesis_crs),4326)
  pxy<-sf::st_coordinates(point)
  sites<-data.frame(site_id="one",lon=pxy[1,1],lat=pxy[1,2],month=7)
  f<-class_fractions(r,sites,1000)
  expect_equal(f$coverage,1)
  expect_equal(sum(f[paste0("lc_",nlcd_classes)]),1)
  expect_equal(f$lc_71,.5,tolerance=.02)
  table_path<-if(file.exists("data/metadata/aersurface_roughness.csv")) "data/metadata/aersurface_roughness.csv" else "../data/metadata/aersurface_roughness.csv"
  lookup<-readr::read_csv(table_path,show_col_types=FALSE)
  x<-add_roughness(sites,f,lookup)
  expect_equal(x$log2_z0,f$lc_71*log2(.1)+f$lc_42*log2(1.3),tolerance=1e-8)
  expect_equal(season_category(c(1,4,7,10)),c(1L,3L,4L,5L))
})
test_that("incomplete matched sets are removed as whole sets", {
  x<-data.frame(track_id=rep(c("a","b"),each=3),role=rep(c("start","background","background"),2),
    landcover_ok=c(TRUE,TRUE,TRUE,TRUE,FALSE,TRUE),log2_z0=1:6,log2_z0_summer=1:6,
    elevation_100m=1,elevation_sd_10m=1,log2_population=1)
  y<-complete_matched_sets(x,"genesis",n_controls=2)
  expect_equal(unique(y$track_id),"a")
  expect_equal(nrow(y),3L)
})
test_that("conditional model recovers an imposed negative selection effect", {
  set.seed(14)
  n<-300
  x<-data.frame(track_id=rep(seq_len(n),each=5),event_date=as.Date("2000-01-01")+rep(seq_len(n)%/%3,each=5),
                 log2_z0=rnorm(n*5),case=0)
  for(i in seq_len(n)) {
    j<-which(x$track_id==i)
    x$case[sample(j,1,prob=exp(-x$log2_z0[j]))]<-1
  }
  fit<-fit_genesis_clogit(x,adjusted=FALSE)
  expect_lt(coef(fit)[["log2_z0"]],-.5)
  expect_true(!is.null(fit$naive.var))
  expect_lt(clogit_effect(fit)$upper_95,1)
})
