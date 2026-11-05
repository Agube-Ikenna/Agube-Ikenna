# Coverage audit uses committed full-resolution exports. Sensitivity uses a
# reproducible spatial sample, NOT another national area estimate or accuracy test.
# 200 random points per zone; seed 20152025. 10 m sampling, 2015/2025 Jul–Oct.
library(sf); library(dplyr); library(readr); library(jsonlite)
dir.create('validation',showWarnings=FALSE)
z <- read_csv('data/dynamic_world/zone_rankings_and_coverage.csv',show_col_types=FALSE)
z <- z |> transmute(zone,region_km2,valid_before_km2,valid_after_km2,common_km2,
 paired_coverage_pct=100*common_km2/region_km2,
 missing_paired_pct=100*(1-common_km2/region_km2),
 apparent_change_pct=ifelse(common_km2>0,100*(loss_km2+gain_km2)/common_km2,NA_real_))
stopifnot(nrow(z)==6,all(z$paired_coverage_pct>=0 & z$paired_coverage_pct<=100))
write_csv(z,'validation/observation_coverage.csv')
sample_file <- 'validation/dw_probability_sample.geojson'
if (!file.exists(sample_file)) {
 library(reticulate)
 Sys.setenv(RETICULATE_PYTHON='managed'); Sys.unsetenv('EARTHENGINE_PYTHON')
 py_require(c('earthengine-api','certifi','numpy'),action='add')
 cert <- import('certifi')$where()
 Sys.setenv(SSL_CERT_FILE=cert,REQUESTS_CA_BUNDLE=cert,HTTPLIB2_CA_CERTS=cert)
 ee <- import('ee'); ee$Initialize(project=Sys.getenv('EE_PROJECT','ivory-mountain-435913-n2'))
 boundary <- list.files('data/dynamic_world',pattern='^zones_.*geojson$',full.names=TRUE)
 b <- jsonlite::read_json(boundary[1],simplifyVector=FALSE)
 fc <- ee$FeatureCollection(b)
 image <- function(year) {
  ic <- ee$ImageCollection('GOOGLE/DYNAMICWORLD/V1')$filterBounds(fc)$
   filterDate(paste0(year,'-07-01'),paste0(year,'-11-01'))$select('trees')
  ee$Image$cat(list(ic$mean()$unmask(-1,FALSE)$rename(paste0('p',year)),
                   ic$count()$unmask(0,FALSE)$rename(paste0('n',year))))
 }
 stack <- ee$Image$cat(list(image(2015),image(2025)))
 samples <- lapply(b$features,function(f) {
  geom <- ee$Feature(f)$geometry()
  points <- ee$FeatureCollection$randomPoints(geom,200,20152025,10)
  list(zone=f$properties$zone,collection=stack$reduceRegions(points,ee$Reducer$first(),scale=10,crs='EPSG:32632',tileScale=4))
 })
 # Retrieve one zone at a time; preserve the same seed and sampling frame.
 result <- list(type='FeatureCollection',features=list())
 for (s in samples) {
  part <- s$collection$getInfo()
  for (j in seq_along(part$features)) part$features[[j]]$properties$zone <- s$zone
  result$features <- c(result$features,part$features)
 }
 write_json(result,sample_file,auto_unbox=TRUE,digits=NA)
}
p <- st_read(sample_file,quiet=TRUE) |> st_drop_geometry()
stopifnot(nrow(p)==1200,all(table(p$zone)==200),all(p$n2015>=0),all(p$n2025>=0))
scenarios <- expand.grid(tree_probability=c(.4,.5,.6),minimum_observations=c(1L,2L,3L))
results <- lapply(seq_len(nrow(scenarios)),function(i) {
 th <- scenarios$tree_probability[i]; n <- scenarios$minimum_observations[i]
 p |> mutate(paired=n2015>=n & n2025>=n & p2015>=0 & p2025>=0,
  loss=paired & p2015>=th & p2025<th,gain=paired & p2015<th & p2025>=th) |>
 group_by(zone) |> summarise(sample_points=n(),paired_points=sum(paired),
  loss_points=sum(loss),gain_points=sum(gain),.groups='drop') |>
 mutate(tree_probability=th,minimum_observations=n,
  paired_sample_pct=100*paired_points/sample_points,
  apparent_change_pct=ifelse(paired_points>0,100*(loss_points+gain_points)/paired_points,NA_real_))
})
write_csv(bind_rows(results),'validation/classification_sensitivity_sample.csv')
writeLines(c('200 random points per zone; seed 20152025; 10 m nearest-pixel sampling.',
 'Nine settings: mean tree probability 0.4/0.5/0.6 and minimum predictions 1/2/3.',
 'Sample percentages are conditional on paired points. Sparse zones may have no estimable change.',
 'These are sensitivity diagnostics, not full-area estimates, confidence intervals or independent accuracy validation.',
 'Minimum predictions are prediction counts; overlapping source tiles may not represent unique acquisition dates.'),
 'validation/sensitivity_method.txt')
