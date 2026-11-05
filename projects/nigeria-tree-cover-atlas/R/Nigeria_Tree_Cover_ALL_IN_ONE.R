# ============================================================
# NIGERIA TREE-COVER CHANGE — ONE SELF-CONTAINED R SCRIPT
# ============================================================
# Open NigeriaTreeCoverClean.Rproj, or set your working directory first.
# This file does not source any other R scripts.
#
# FIRST: MODE <- "maps"    : side-by-side satellite views
# NEXT:  MODE <- "exports" : submit zone/grid calculations to Earth Engine
#        MODE <- "status" : check submitted jobs
# LAST:  MODE <- "results": after downloading exports, create rankings/hotspots
#
# The cloud jobs finish asynchronously; results cannot be plotted until
# their completed CSV/GeoJSON files are downloaded to the printed folder.
# Endpoints are July–October 2015 and 2025. Run from this project directory.
# Install missing R packages once, then restart R:
# install.packages(c("rgee","reticulate","png","jsonlite","sf","readr",
#                    "dplyr","tidyr","ggplot2","scales"),
#                  repos="https://cloud.r-project.org")

MODE <- "results"
stopifnot(MODE %in% c("maps", "exports", "status", "results"))

# ==================== SETTINGS ===============================

# EDIT SETTINGS HERE ONLY. Run scripts from NigeriaTreeCoverClean.Rproj.
cfg <- list(
  project = Sys.getenv('EE_PROJECT', unset='ivory-mountain-435913-n2'),
  start_year = 2015L,
  end_year = 2025L,                 # Requested comparison: 2015–2025.
  tree_threshold = 0.5,
  pressure_threshold = 0.5,
  minimum_observations = 2L,
  analysis_scale_m = 10L,
  analysis_crs = 'EPSG:32632',      # Common grid; pixelArea computes ground area.
  grid_size_m = 10000L,
  hotspot_min_coverage_pct = 50,    # Exploratory choices: assess sensitivity.
  hotspot_min_baseline_km2 = 1,
  hotspot_quantile = 0.90,
  preview_dimensions = 900L,
  download_timeout_seconds = 600,
  reuse_previews = TRUE,
  python = 'managed'
)
stopifnot(cfg$end_year > cfg$start_year,
          cfg$tree_threshold > 0, cfg$tree_threshold < 1,
          cfg$minimum_observations >= 1)
cfg$interval_years <- cfg$end_year - cfg$start_year
cfg$run_id <- sprintf('%d_%d_JulOct_p%s_n%d_s%d_grid%d_pressure%s',cfg$start_year,
                      cfg$end_year, gsub('[.]','p',as.character(cfg$tree_threshold)),
                      cfg$minimum_observations,cfg$analysis_scale_m,cfg$grid_size_m,
                      gsub('[.]','p',as.character(cfg$pressure_threshold)))
workflow_root <- Sys.getenv('NIGERIA_ATLAS_ROOT', unset=getwd())
if (!dir.exists(file.path(workflow_root,'R'))) stop('Set working directory to projects/nigeria-tree-cover-atlas first.')
cfg$output_dir <- file.path(workflow_root, 'figures', 'dynamic_world')
cfg$input_dir <- file.path(workflow_root, 'data', 'dynamic_world')
cfg$drive_folder <- paste0('Nigeria_Tree_Cover_', cfg$run_id)
cfg$zone_export <- paste0('zone_metrics_',cfg$run_id)
cfg$grid_export <- paste0('grid_metrics_',cfg$run_id)
cfg$boundary_export <- paste0('zones_',cfg$run_id)
dir.create(cfg$output_dir, recursive=TRUE, showWarnings=FALSE)
dir.create(cfg$input_dir, recursive=TRUE, showWarnings=FALSE)
options(timeout=max(600,cfg$download_timeout_seconds))


# ==================== CONNECTION =============================
if (MODE %in% c("maps", "exports", "status")) {

  # Use reticulate's managed Python consistently, including existing managed sessions.
  # Do not load rgee before declaring its Python dependencies.
  required <- c('rgee','reticulate','png','jsonlite')
  installed <- vapply(required,function(p) length(find.package(p,quiet=TRUE))>0,logical(1))
  if (any(!installed)) stop('Install R packages first: ',paste(required[!installed],collapse=', '))
  Sys.setenv(RETICULATE_PYTHON='managed')
  Sys.unsetenv('EARTHENGINE_PYTHON')
  library(reticulate)
  reticulate::py_require(c('earthengine-api','numpy','certifi'),action='add')
  # Reticulate resolves/install these packages in its managed environment.
  certifi <- reticulate::import('certifi')
  cert <- certifi$where()
  if (length(cert)!=1 || !file.exists(cert)) stop('A valid certifi bundle was not found.')
  Sys.setenv(SSL_CERT_FILE=cert,REQUESTS_CA_BUNDLE=cert,HTTPLIB2_CA_CERTS=cert)
  if (!reticulate::py_module_available('ee')) stop('earthengine-api is unavailable; inspect the dependency-installation error.')
  library(rgee)
  ee <- reticulate::import('ee')
  # Direct initialization avoids the legacy asset-home prompt.
  ee$Initialize(project=cfg$project)
  stopifnot(ee$Number(1)$getInfo()==1)
  jsonlite::write_json(cfg,file.path(cfg$output_dir,'settings.json'),
                       pretty=TRUE,auto_unbox=TRUE)

}

# ==================== SATELLITE DATA ==========================
if (MODE %in% c("maps", "exports")) {

  # Build server-side expressions; this is not a downloaded result table.
  zone_states <- list(
    'North Central'=c('Benue','Kogi','Kwara','Nasarawa','Niger','Plateau','Federal Capital Territory'),
    'North East'=c('Adamawa','Bauchi','Borno','Gombe','Taraba','Yobe'),
    'North West'=c('Jigawa','Kaduna','Kano','Katsina','Kebbi','Sokoto','Zamfara'),
    'South East'=c('Abia','Anambra','Ebonyi','Enugu','Imo'),
    'South South'=c('Akwa Ibom','Bayelsa','Cross River','Delta','Edo','Rivers'),
    'South West'=c('Ekiti','Lagos','Ogun','Ondo','Osun','Oyo'))
  aliases <- list(Nassarawa='Nasarawa',Abuja='Federal Capital Territory',
                  FCT='Federal Capital Territory','Federal Capital Territory (Abuja)'='Federal Capital Territory')
  lookup <- list()
  for (z in names(zone_states)) for (s in zone_states[[z]]) lookup[[s]] <- z
  for (a in names(aliases)) lookup[[a]] <- lookup[[aliases[[a]]]]
  zone_dictionary <- ee$Dictionary(lookup)
  states <- ee$FeatureCollection('FAO/GAUL/2015/level1')$
    filter(ee$Filter$eq('ADM0_NAME','Nigeria'))$
    map(ee_utils_pyfunc(function(f) {
      f <- ee$Feature(f)
      nm <- ee$String(f$get('ADM1_NAME'))
      f$set('zone',ee$Algorithms$If(zone_dictionary$contains(nm),
                                    zone_dictionary$get(nm),'UNMATCHED'))
    }))
  if (states$size()$getInfo()!=37) stop('Expected 36 states plus FCT.')
  unmatched <- states$filter(ee$Filter$eq('zone','UNMATCHED'))$
    aggregate_array('ADM1_NAME')$getInfo()
  if (length(unmatched)) stop('Unmatched boundary names: ',paste(unmatched,collapse=', '))
  zones_ee <- ee$FeatureCollection(lapply(names(zone_states),function(z) {
    subset <- states$filter(ee$Filter$eq('zone',z))
    ee$Feature(subset$geometry(),list(zone=z,number_of_states=subset$size()))
  }))
  counts <- unlist(zones_ee$aggregate_array('number_of_states')$getInfo())
  stopifnot(identical(as.integer(counts),c(7L,6L,7L,5L,6L,6L)))
  nigeria <- states$geometry()
  season <- function(y) c(sprintf('%d-07-01',y),sprintf('%d-11-01',y))
  dates_before <- season(cfg$start_year)
  dates_after <- season(cfg$end_year)
  class_bands <- c('water','trees','grass','flooded_vegetation','crops',
                   'shrub_and_scrub','built','bare','snow_and_ice')
  dw <- ee$ImageCollection('GOOGLE/DYNAMICWORLD/V1')$filterBounds(nigeria)
  composite_dw <- function(dates) {
    collection <- dw$filterDate(dates[1],dates[2])$select(class_bands)
    scenes <- collection$size()$getInfo()
    if (scenes==0) stop('No Dynamic World data for ',dates[1])
    mean <- collection$mean()
    list(probability=mean$select('trees'),all_probabilities=mean,
         observations=collection$select('trees')$count(),scenes=scenes,
         dominant=mean$toArray()$arrayArgmax()$arrayGet(list(0)))
  }
  before <- composite_dw(dates_before)
  after <- composite_dw(dates_after)
  valid_before <- before$observations$unmask(0,FALSE)$gte(cfg$minimum_observations)$clip(nigeria)
  valid_after <- after$observations$unmask(0,FALSE)$gte(cfg$minimum_observations)$clip(nigeria)
  common <- valid_before$And(valid_after)
  tree_before <- before$probability$gte(cfg$tree_threshold)$unmask(0,FALSE)
  tree_after <- after$probability$gte(cfg$tree_threshold)$unmask(0,FALSE)
  persistent <- tree_before$And(tree_after)$And(common)
  loss <- tree_before$And(tree_after$Not())$And(common)
  gain <- tree_before$Not()$And(tree_after)$And(common)
  non_tree <- tree_before$Not()$And(tree_after$Not())$And(common)
  # Endpoint co-occurrence indicators. They do NOT prove causes of tree loss.
  crop_expansion <- before$dominant$neq(4)$And(after$dominant$eq(4))$
    And(after$all_probabilities$select('crops')$gte(cfg$pressure_threshold))$
    unmask(0,FALSE)$And(common)
  built_expansion <- before$dominant$neq(6)$And(after$dominant$eq(6))$
    And(after$all_probabilities$select('built')$gte(cfg$pressure_threshold))$
    unmask(0,FALSE)$And(common)
  loss_to_crop <- loss$And(crop_expansion)
  loss_to_built <- loss$And(built_expansion)
  loss_other <- loss$And(loss_to_crop$Or(loss_to_built)$Not())
  change <- ee$Image$constant(0)$where(persistent,1)$where(loss,2)$where(gain,3)$
    updateMask(common)$unmask(4,FALSE)$clip(nigeria)
  # km², using actual ground area on a specified common analysis grid.
  pixel_km2 <- ee$Image$pixelArea()$divide(1e6)
  area_band <- function(mask,name) mask$unmask(0,FALSE)$clip(nigeria)$multiply(pixel_km2)$rename(name)
  area_bands <- list(
    pixel_km2$clip(nigeria)$rename('region_km2'),
    area_band(valid_before,'valid_before_km2'),area_band(valid_after,'valid_after_km2'),
    area_band(common,'common_km2'),area_band(common$And(tree_before),'tree_before_km2'),
    area_band(common$And(tree_after),'tree_after_km2'),area_band(persistent,'persistent_km2'),
    area_band(non_tree,'non_tree_km2'),area_band(loss,'loss_km2'),area_band(gain,'gain_km2'),
    area_band(crop_expansion,'crop_expansion_km2'),area_band(built_expansion,'built_expansion_km2'),
    area_band(loss_to_crop,'loss_to_crop_km2'),area_band(loss_to_built,'loss_to_built_km2'),
    area_band(loss_other,'loss_other_km2'))
  metric_names <- c('region_km2','valid_before_km2','valid_after_km2','common_km2',
                    'tree_before_km2','tree_after_km2','persistent_km2','non_tree_km2','loss_km2','gain_km2',
                    'crop_expansion_km2','built_expansion_km2','loss_to_crop_km2','loss_to_built_km2','loss_other_km2')
  metrics <- ee$ImageCollection$fromImages(area_bands)$toBands()$rename(metric_names)
  add_metadata <- function(f) {
    ee$Feature(f)$set(list(start_year=cfg$start_year,end_year=cfg$end_year,
                           season='JulOct',tree_threshold=cfg$tree_threshold,pressure_threshold=cfg$pressure_threshold,minimum_observations=cfg$minimum_observations,
                           analysis_scale_m=cfg$analysis_scale_m,analysis_crs=cfg$analysis_crs,run_id=cfg$run_id))
  }
  reduce_metrics <- function(regions) metrics$reduceRegions(collection=regions,
                                                            reducer=ee$Reducer$sum(),scale=cfg$analysis_scale_m,crs=cfg$analysis_crs,tileScale=4)$
    map(ee_utils_pyfunc(add_metadata))
  scene_record <- data.frame(year=c(cfg$start_year,cfg$end_year),
                             source_scenes=c(before$scenes,after$scenes),retrieved=as.character(Sys.Date()))
  write.csv(scene_record,file.path(cfg$output_dir,'scene_counts.csv'),row.names=FALSE)
  message('Boundary checks passed. Scene counts are not per-pixel coverage statistics.')

}

# ==================== SIDE-BY-SIDE MAPS ========================
if (MODE == "maps") {

  if (!requireNamespace('png',quietly=TRUE)) stop('Install png first.')
  landsat_composite <- function(dates) {
    collection <- ee$ImageCollection('LANDSAT/LC08/C02/T1_L2')$
      filterBounds(nigeria)$filterDate(dates[1],dates[2])
    if (collection$size()$getInfo()==0) stop('No Landsat scenes for ',dates[1])
    collection$map(ee_utils_pyfunc(function(im) {
      im <- ee$Image(im)
      clear <- im$select('QA_PIXEL')$bitwiseAnd(31)$eq(0)$And(im$select('QA_RADSAT')$eq(0))
      im$select(c('SR_B4','SR_B3','SR_B2'))$multiply(0.0000275)$add(-0.2)$updateMask(clear)
    }))$median()$clip(nigeria)
  }
  outline <- ee$Image$constant(0)$toByte()$paint(zones_ee,1,1)$selfMask()$
    visualize(palette=list('ffffff'))
  make_satellite <- function(dates,trees) {
    rgb <- landsat_composite(dates)$visualize(bands=list('SR_B4','SR_B3','SR_B2'),
                                              min=0.02,max=0.30,gamma=1.15)
    overlay <- trees$updateMask(common)$selfMask()$
      visualize(palette=list('55ee78'),opacity=0.65)
    missing <- common$Not()$selfMask()$clip(nigeria)$
      visualize(palette=list('999999'),opacity=0.5)
    rgb$blend(missing)$blend(overlay)$blend(outline)
  }
  map_before <- make_satellite(dates_before,tree_before)
  map_after <- make_satellite(dates_after,tree_after)
  change_rgb <- change$visualize(min=0,max=4,
                                 palette=list('f2eee5','237443','d73027','2878b5','999999'))$blend(outline)
  thumbnail_region <- nigeria$bounds()$getInfo()
  download_preview <- function(image,filename) {
    destination <- file.path(cfg$output_dir,filename)
    if (cfg$reuse_previews && file.exists(destination)) {
      ok <- tryCatch({png::readPNG(destination); TRUE},error=function(e) FALSE)
      if (ok) return(destination)
    }
    last_error <- NULL
    for (attempt in 1:3) {
      # A fresh URL on every attempt; downloading does not change analysis scale.
      url <- image$getThumbURL(list(region=thumbnail_region,
                                    dimensions=cfg$preview_dimensions,format='png',crs='EPSG:4326'))
      part <- paste0(destination,'.part')
      ok <- tryCatch({
        utils::download.file(url,part,mode='wb',method='libcurl',quiet=TRUE)
        png::readPNG(part)
        file.copy(part,destination,overwrite=TRUE)
        unlink(part)
        TRUE
      },error=function(e) {last_error <<- conditionMessage(e); FALSE})
      if (ok) return(destination)
      message('Preview attempt ',attempt,' failed; requesting a fresh image URL.')
    }
    stop('Preview download failed: ',last_error,
         '\nRetry RUN_MAPS.R; completed PNGs are reused. Heavy tables use batch exports.')
  }
  before_file <- download_preview(map_before,'satellite_before_separate_v2.png')
  after_file <- download_preview(map_after,'satellite_after_separate_v2.png')
  # Change classes remain available as change_rgb, but are not a third panel.
  draw_image <- function(path,label) {
    im <- png::readPNG(path)
    plot.new()
    plot.window(xlim=c(0,ncol(im)),ylim=c(0,nrow(im)),asp=1,xaxs='i',yaxs='i')
    rasterImage(im,0,0,ncol(im),nrow(im))
    title(main=label,cex.main=0.95)
  }
  draw_comparison <- function() {
    old <- par(no.readonly=TRUE)
    on.exit({layout(1); par(old)},add=TRUE)
    layout(matrix(c(1,2,3,3),nrow=2,byrow=TRUE),heights=c(10,1.4))
    par(mar=c(0,0,3,0))
    draw_image(before_file,paste(cfg$start_year,'satellite + tree overlay'))
    draw_image(after_file,paste(cfg$end_year,'satellite + tree overlay'))
    par(mar=c(0,0,0,0)); plot.new()
    legend('center',legend=c('Bright green: tree-class overlay in common footprint',
                             'Grey overlay: insufficient paired tree observations','White gaps: masked satellite pixels'),
           fill=c('#55ee78','#999999','white'),border='grey40',ncol=1,bty='n',cex=0.9)
    mtext(sprintf('July–October %d vs %d | White outlines: geopolitical zones | Overviews, not area estimates',
                  cfg$start_year,cfg$end_year),side=1,line=-1.1,cex=0.75)
  }
  save_comparison <- function() {
    png(file.path(cfg$output_dir,'01_satellite_comparison.png'),width=2600,height=1400,res=180)
    on.exit(dev.off(),add=TRUE)
    draw_comparison()
  }
  save_comparison()
  if (interactive()) draw_comparison()
  message('Image 1 saved in ',cfg$output_dir)

}

# ==================== CLOUD EXPORTS ===========================
if (MODE == "exports") {

  # Country-wide 10 m metrics use batch tasks, not synchronous getInfo().
  zone_metrics <- reduce_metrics(zones_ee)$map(ee_utils_pyfunc(function(f) {
    ee$Feature(f)$setGeometry(NULL)
  }))
  grid <- nigeria$coveringGrid(ee$Projection(cfg$analysis_crs),cfg$grid_size_m)$
    map(ee_utils_pyfunc(function(f) {
      f <- ee$Feature(f)
      xy <- f$geometry()$centroid(1)$transform(cfg$analysis_crs,1)$coordinates()
      gx <- ee$Number(xy$get(0))$divide(cfg$grid_size_m)$floor()
      gy <- ee$Number(xy$get(1))$divide(cfg$grid_size_m)$floor()
      id <- gx$format('%d')$cat('_')$cat(gy$format('%d'))
      f$set(list(grid_id=id,gx=gx,gy=gy))
    }))
  grid_metrics <- reduce_metrics(grid)
  requests <- list(
    list(name=cfg$zone_export,collection=zone_metrics,format='CSV'),
    list(name=cfg$grid_export,collection=grid_metrics,format='GeoJSON'),
    list(name=cfg$boundary_export,collection=zones_ee,format='GeoJSON'))
  record_file <- file.path(cfg$output_dir,'export_tasks.json')
  records <- if (file.exists(record_file)) jsonlite::read_json(record_file) else list()
  for (r in requests) {
    if (r$name %in% names(records)) {
      message('Already recorded; not resubmitting: ',r$name)
      next
    }
    task <- ee$batch$Export$table$toDrive(collection=r$collection,description=r$name,
                                          folder=cfg$drive_folder,fileNamePrefix=r$name,fileFormat=r$format)
    task$start()
    records[[r$name]] <- list(id=task$id,submitted=as.character(Sys.time()),format=r$format)
    jsonlite::write_json(records,record_file,pretty=TRUE,auto_unbox=TRUE)
    message('Submitted: ',r$name,' | task ',task$id)
  }
  message('Drive destination folder: ',cfg$drive_folder)
  message('Run CHECK_EXPORTS.R for status. After completion, download the CSV and two GeoJSONs into: ',cfg$input_dir)

}

# ==================== EXPORT STATUS ===========================
if (MODE == "status") {

  f <- file.path(cfg$output_dir, "export_tasks.json")
  if (!file.exists(f)) stop("No task record. Run this script with MODE = 'exports' first.")
  tasks <- jsonlite::read_json(f)
  for (name in names(tasks)) {
    cat("\n", name, "\n")
    print(ee$data$getTaskStatus(list(tasks[[name]]$id)))
  }

}

# ==================== CLEANING AND RESULT FIGURES =============
if (MODE == "results") {

  # Offline R cleaning and plots: only run after batch exports are downloaded.
  needed <- c('sf','readr','dplyr','tidyr','ggplot2','scales')
  missing <- needed[!vapply(needed,requireNamespace,logical(1),quietly=TRUE)]
  if (length(missing)) stop('Install packages first: ',paste(missing,collapse=', '))
  library(sf); library(dplyr); library(ggplot2)
  zone_file <- file.path(cfg$input_dir,paste0(cfg$zone_export,'.csv'))
  grid_file <- file.path(cfg$input_dir,paste0(cfg$grid_export,'.geojson'))
  boundary_file <- file.path(cfg$input_dir,paste0(cfg$boundary_export,'.geojson'))
  files <- c(zone_file,grid_file,boundary_file)
  if (any(!file.exists(files))) stop('Download completed exports into ',cfg$input_dir,
                                     '\nMissing: ',paste(basename(files[!file.exists(files)]),collapse=', '))
  metric_names <- c('region_km2','valid_before_km2','valid_after_km2','common_km2',
                    'tree_before_km2','tree_after_km2','persistent_km2','non_tree_km2','loss_km2','gain_km2',
                    'crop_expansion_km2','built_expansion_km2','loss_to_crop_km2','loss_to_built_km2','loss_other_km2')
  expected_zones <- c('North Central','North East','North West','South East','South South','South West')
  z <- readr::read_csv(zone_file,show_col_types=FALSE)
  boundaries <- sf::st_read(boundary_file,quiet=TRUE) |>
    sf::st_make_valid() |> sf::st_collection_extract('POLYGON')
  g <- sf::st_read(grid_file,quiet=TRUE)
  # Earth Engine may export native UTM geometry without a GeoJSON CRS tag.
  # Assign the SOURCE CRS before validation, then transform to the zone CRS.
  grid_bbox <- sf::st_bbox(g)
  metres_in_geojson <- any(abs(grid_bbox[c('xmin','xmax')])>180) ||
                       any(abs(grid_bbox[c('ymin','ymax')])>90)
  if (metres_in_geojson) {
    exported_crs <- unique(as.character(g$analysis_crs))
    if (length(exported_crs)!=1 || is.na(exported_crs) ||
        exported_crs!=cfg$analysis_crs) {
      stop('Cannot determine the source CRS of grid coordinates.')
    }
    g <- sf::st_set_crs(g,NA)
    g <- sf::st_set_crs(g,exported_crs)
  }
  g <- sf::st_make_valid(g)
  g <- sf::st_transform(g,sf::st_crs(boundaries))
  g <- g[!is.na(g$region_km2) & g$region_km2>0,]
  stopifnot(nrow(z)==6,!anyDuplicated(z$zone),setequal(z$zone,expected_zones),
            nrow(boundaries)==6,!anyDuplicated(boundaries$zone),setequal(boundaries$zone,expected_zones),
            nrow(g)>0,!anyDuplicated(g$grid_id),all(sf::st_is_valid(boundaries)),all(sf::st_is_valid(g)))
  validate_metrics <- function(x) {
    required <- c(metric_names,'start_year','end_year','tree_threshold','pressure_threshold','minimum_observations',
                  'analysis_scale_m','analysis_crs','run_id')
    if (!all(required %in% names(x))) stop('Missing exported fields.')
    if (!all(vapply(x[metric_names],is.numeric,logical(1)))) stop('Non-numeric area fields.')
    if (any(vapply(x[metric_names],function(v) any(!is.finite(v) | v<0),logical(1))))
      stop('Missing, non-finite or negative area values; inspect exports.')
    stopifnot(all(x$start_year==cfg$start_year),all(x$end_year==cfg$end_year),
              all(abs(x$tree_threshold-cfg$tree_threshold)<1e-9),
              all(abs(x$pressure_threshold-cfg$pressure_threshold)<1e-9),
              all(x$minimum_observations==cfg$minimum_observations),
              all(x$analysis_scale_m==cfg$analysis_scale_m),all(x$analysis_crs==cfg$analysis_crs),
              all(x$run_id==cfg$run_id))
    tol <- pmax(1e-5,x$region_km2*1e-6)
    stopifnot(all(x$common_km2<=x$valid_before_km2+tol),
              all(x$common_km2<=x$valid_after_km2+tol),
              all(x$valid_before_km2<=x$region_km2+tol),all(x$valid_after_km2<=x$region_km2+tol),
              all(abs(x$persistent_km2+x$loss_km2-x$tree_before_km2)<=tol),
              all(abs(x$persistent_km2+x$gain_km2-x$tree_after_km2)<=tol),
              all(abs(x$persistent_km2+x$non_tree_km2+x$loss_km2+x$gain_km2-x$common_km2)<=tol),
              all(abs(x$loss_to_crop_km2+x$loss_to_built_km2+x$loss_other_km2-x$loss_km2)<=tol))
    invisible(TRUE)
  }
  validate_metrics(z); validate_metrics(sf::st_drop_geometry(g))
  pct <- function(n,d) {
    out <- rep(NA_real_,length(d)); ok <- is.finite(d) & d>0
    out[ok] <- 100*n[ok]/d[ok]; out
  }
  add_rates <- function(x) x |>
    mutate(common_coverage_pct=pct(common_km2,region_km2),
           loss_pct_common=pct(loss_km2,common_km2),gain_pct_common=pct(gain_km2,common_km2),
           loss_pct_baseline_tree=pct(loss_km2,tree_before_km2),
           gain_pct_baseline_non_tree=pct(gain_km2,common_km2-tree_before_km2),
           net_change_km2=gain_km2-loss_km2,gross_change_km2=gain_km2+loss_km2,
           gross_change_pct_common=pct(gross_change_km2,common_km2),
           mean_annual_net_change_km2=net_change_km2/cfg$interval_years,
           loss_to_crop_pct=pct(loss_to_crop_km2,loss_km2),
           loss_to_built_pct=pct(loss_to_built_km2,loss_km2))
  z <- add_rates(z) |> arrange(desc(gross_change_km2))
  g <- add_rates(g)
  sf::st_write(g,file.path(cfg$input_dir,'grid_metrics_wgs84.geojson'),delete_dsn=TRUE,quiet=TRUE)
  readr::write_csv(z,file.path(cfg$output_dir,'zone_rankings_and_coverage.csv'))
  readr::write_csv(sf::st_drop_geometry(g),file.path(cfg$output_dir,'grid_metrics_clean.csv'))
  # Report both absolute and relative rankings: 'changed most' depends on denominator.
  readr::write_csv(z |> arrange(desc(gross_change_pct_common)),
                   file.path(cfg$output_dir,'zone_rankings_relative_change.csv'))
  period <- sprintf('%d–%d (July–October endpoints)',cfg$start_year,cfg$end_year)
  palette <- c('Apparent loss'='#d73027','Apparent gain'='#2878b5')
  make_ranked_chart <- function(relative=FALSE) {
    order <- if (relative) z$zone[order(z$gross_change_pct_common)] else rev(z$zone)
    rows <- dplyr::bind_rows(
      z |> transmute(zone,transition='Apparent loss',value=ifelse(common_km2>0,if(relative) loss_pct_common else loss_km2,NA_real_)),
      z |> transmute(zone,transition='Apparent gain',value=ifelse(common_km2>0,if(relative) gain_pct_common else gain_km2,NA_real_)))
    rows$zone <- factor(rows$zone,levels=order)
    ggplot(rows,aes(zone,value,fill=transition))+geom_col(position='dodge')+coord_flip()+
      scale_fill_manual(values=palette)+scale_y_continuous(labels=scales::label_number(big.mark=','))+
      labs(title=if(relative) 'Zone ranking: relative apparent change' else 'Zone ranking: apparent change area',
           subtitle=paste(period,'| Ranked by loss + gain'),x=NULL,
           y=if(relative) '% of common-observed area' else 'Mapped area (km²)',fill=NULL,
           caption='Same observed footprint in both years. Missing areas are not extrapolated; coverage differs between zones.')+
      theme_minimal(base_size=12)+theme(legend.position='bottom')
  }
  p_area <- make_ranked_chart(FALSE); p_relative <- make_ranked_chart(TRUE)
  ggsave(file.path(cfg$output_dir,'02_zone_ranking_km2.png'),p_area,width=10,height=6,dpi=300,bg='white')
  ggsave(file.path(cfg$output_dir,'02_zone_ranking_percent.png'),p_relative,width=10,height=6,dpi=300,bg='white')
  p_coverage <- ggplot(z,aes(reorder(zone,common_coverage_pct),common_coverage_pct))+
    geom_col(fill='#666666')+coord_flip()+scale_y_continuous(limits=c(0,100))+
    labs(title='Coverage supporting each zone comparison',x=NULL,y='% of zone observed in BOTH periods')+
    theme_minimal(base_size=12)
  ggsave(file.path(cfg$output_dir,'02_zone_coverage.png'),p_coverage,width=10,height=6,dpi=300,bg='white')
  # IMAGE 2: zone map with dotted boundaries, dots and percentage labels.
  zone_map <- boundaries |> left_join(z,by='zone')
  label_points <- sf::st_point_on_surface(sf::st_geometry(sf::st_transform(zone_map,32632)))
  label_points <- sf::st_sf(zone=zone_map$zone,
                            change_pct=zone_map$gross_change_pct_common,geometry=label_points) |> sf::st_transform(4326)
  label_points$label <- paste0(label_points$zone, '\n',
                               ifelse(is.finite(label_points$change_pct),sprintf('%.1f%%',label_points$change_pct),'No paired data'))
  p_zone <- ggplot(zone_map)+
    geom_sf(aes(fill=gross_change_pct_common),colour='grey20',linetype='dotted',linewidth=0.65)+
    scale_fill_viridis_c(option='cividis',na.value='grey85',name='Apparent change\n(% observed area)')+
    geom_sf(data=label_points,shape=21,size=2.2,fill='white',colour='black')+
    geom_sf_label(data=label_points,aes(label=label),nudge_y=0.22,size=3,
                  label.padding=grid::unit(0.13,'lines'),fill='white',alpha=0.9)+
    labs(title='Which geopolitical zone changed most?',subtitle=period,
         caption='Percentage = (apparent loss + apparent gain) / common-observed area × 100.\nDotted lines: zone boundaries; dots locate labels. Grey: no paired data. Coverage differs between zones.')+
    theme_void(base_size=12)+theme(legend.position='right',plot.caption=element_text(hjust=0))
  ggsave(file.path(cfg$output_dir,'02_zone_change_percentage_map.png'),p_zone,width=11,height=9,dpi=300,bg='white')

  # EXPLORATORY HOTSPOTS: high-loss cells joined by spatial adjacency.
  # No p-values: these are not statistically significant hotspot claims.
  g$eligible <- g$common_coverage_pct>=cfg$hotspot_min_coverage_pct &
    g$tree_before_km2>=cfg$hotspot_min_baseline_km2 & is.finite(g$loss_pct_baseline_tree)
  positive <- g$loss_pct_baseline_tree[g$eligible & g$loss_km2>0]
  threshold <- if(length(positive)) as.numeric(quantile(positive,cfg$hotspot_quantile,na.rm=TRUE)) else Inf
  g$high_loss <- g$eligible & g$loss_km2>0 & g$loss_pct_baseline_tree>=threshold
  g$cluster_id <- NA_integer_; g$cluster_cells <- NA_integer_
  idx <- which(g$high_loss)
  if (length(idx)) {
    # Queen adjacency (edges or corners) between equal-grid cells.
    # Use exact integer grid indices: round-trip reprojection can break st_touches.
    delta <- expand.grid(dx=-1:1,dy=-1:1)
    delta <- delta[delta$dx!=0 | delta$dy!=0,]
    keys <- paste(g$gx[idx],g$gy[idx],sep=':')
    adj <- lapply(idx,function(i) {
      hits <- match(paste(g$gx[i]+delta$dx,g$gy[i]+delta$dy,sep=':'),keys)
      hits[!is.na(hits)]
    })
    component <- integer(length(idx)); component_id <- 0L
    for (seed in seq_along(idx)) {
      if (component[seed]!=0) next
      component_id <- component_id+1L
      queue <- seed; component[seed] <- component_id
      while(length(queue)) {
        current <- queue[1]; queue <- queue[-1]
        unseen <- adj[[current]][component[adj[[current]]]==0]
        if (length(unseen)) {
          component[unseen] <- component_id
          queue <- c(queue,unseen)
        }
      }
    }
    sizes <- tabulate(component)
    g$cluster_id[idx] <- component
    g$cluster_cells[idx] <- sizes[component]
  }
  # Clip only for cartographic display; metrics were already masked to Nigeria.
  clipped <- suppressWarnings(sf::st_intersection(g,sf::st_union(boundaries)))
  cluster_display <- clipped[which(clipped$high_loss & clipped$cluster_cells>=2),]
  excluded_display <- clipped[which(!clipped$eligible),]
  p_hotspots <- ggplot()+
    geom_sf(data=clipped,aes(fill=ifelse(eligible,loss_pct_baseline_tree,NA_real_)),colour=NA)+
    scale_fill_viridis_c(option='magma',direction=-1,na.value='grey85',
                         name='Apparent loss\n(% baseline tree area)')+
    geom_sf(data=excluded_display,aes(colour='Excluded cells'),fill='grey85',linewidth=0.1)+
    geom_sf(data=cluster_display,aes(colour='Candidate hotspot cluster'),fill=NA,linewidth=0.6)+
    scale_colour_manual(name='Map features',
                        values=c('Candidate hotspot cluster'='#00a6a6','Excluded cells'='grey65'),
                        breaks=c('Candidate hotspot cluster','Excluded cells'),
                        limits=c('Candidate hotspot cluster','Excluded cells'),drop=FALSE)+
    geom_sf(data=boundaries,fill=NA,colour='grey20',linetype='dotted',linewidth=0.35)+
    guides(colour=guide_legend(override.aes=list(fill=c(NA,'grey85'),linewidth=c(0.8,0.3))))+
    labs(title='Where are the candidate tree-cover loss hotspots?',subtitle=period,
         caption=sprintf('%.0f km grid; top %.0f%% of positive eligible loss rates. Cyan: groups of at least 2 adjacent high-loss cells.\nEligibility: >= %.0f%% common coverage and >= %.1f km² baseline tree area. Dotted lines: zone boundaries.\nExploratory clusters, not a statistical significance test; excluded cells are not evidence of no change.',
                         cfg$grid_size_m/1000,100*(1-cfg$hotspot_quantile),cfg$hotspot_min_coverage_pct,
                         cfg$hotspot_min_baseline_km2))+theme_void(base_size=11)+
    theme(legend.position='right',plot.caption=element_text(hjust=0))
  ggsave(file.path(cfg$output_dir,'03_candidate_hotspots.png'),p_hotspots,width=11,height=10,dpi=300,bg='white')

  hot <- g[g$high_loss,]
  if (nrow(hot)) {
    sf::st_write(hot,file.path(cfg$output_dir,'candidate_hotspots.geojson'),delete_dsn=TRUE,quiet=TRUE)
    clusters <- sf::st_drop_geometry(hot) |> group_by(cluster_id) |>
      summarise(cells=n(),common_km2=sum(common_km2),tree_before_km2=sum(tree_before_km2),
                loss_km2=sum(loss_km2),loss_to_crop_km2=sum(loss_to_crop_km2),
                loss_to_built_km2=sum(loss_to_built_km2),loss_other_km2=sum(loss_other_km2),.groups='drop') |>
      mutate(loss_pct_baseline_tree=pct(loss_km2,tree_before_km2),
             crop_overlap_pct=pct(loss_to_crop_km2,loss_km2),built_overlap_pct=pct(loss_to_built_km2,loss_km2)) |>
      arrange(desc(loss_km2))
    readr::write_csv(clusters,file.path(cfg$output_dir,'candidate_cluster_summary.csv'))
  }
  pressure_rows <- bind_rows(
    z |> transmute(zone,endpoint='Crop-class expansion overlap',km2=loss_to_crop_km2),
    z |> transmute(zone,endpoint='Built-class expansion overlap',km2=loss_to_built_km2),
    z |> transmute(zone,endpoint='Other / uncertain endpoint',km2=loss_other_km2)) |>
    left_join(z |> select(zone,loss_km2),by='zone') |>
    mutate(share_of_loss_pct=pct(km2,loss_km2))
  readr::write_csv(pressure_rows,file.path(cfg$output_dir,'land_use_overlap.csv'))
  p_pressure <- ggplot(pressure_rows,aes(zone,share_of_loss_pct,fill=endpoint))+
    geom_col()+coord_flip()+scale_fill_manual(values=c('Crop-class expansion overlap'='#d8a52b',
                                                       'Built-class expansion overlap'='#6c5b8e','Other / uncertain endpoint'='#bdbdbd'))+
    labs(title='Land-cover transitions co-occurring with apparent tree loss',subtitle=period,
         x=NULL,y='% of apparent loss area',fill=NULL,
         caption='Endpoint co-occurrence from the same model, not independent evidence or proof of cause. Undefined where no loss was mapped.')+
    theme_minimal(base_size=11)+theme(legend.position='bottom')
  ggsave(file.path(cfg$output_dir,'03_land_use_overlap.png'),p_pressure,width=11,height=7,dpi=300,bg='white')
  writeLines(c(sprintf('Hotspot loss-per-baseline threshold: %s percent',threshold),
               'No inference of causal drivers or statistical hotspot significance.',
               'Persistent means tree at both endpoints; intermediate loss/regrowth is not measured.'),
             file.path(cfg$output_dir,'interpretation_notes.txt'))
  writeLines(capture.output(sessionInfo()),file.path(cfg$output_dir,'R_session_info.txt'))
  if (interactive()) {print(p_zone); print(p_hotspots)}
  for (f in list.files(cfg$output_dir,pattern='[.](csv|geojson)$',full.names=TRUE))
    file.copy(f,file.path(cfg$input_dir,basename(f)),overwrite=TRUE)
  message('Saved tables and figures in ',cfg$output_dir)

}
