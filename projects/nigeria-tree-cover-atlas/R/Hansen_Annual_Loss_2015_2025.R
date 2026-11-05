# ======================================================================
# ALTERNATIVE WORKFLOW B: HANSEN LOSS ANALYSIS, 2015–2025
# Local Hansen GFC v1.13; annual losses in 2015–2025 INCLUSIVE (11 years).
# Independent of the queued Dynamic World exports. Run this script in R.
# See validation for execution and QA records.
# ======================================================================

# 1. SETTINGS -----------------------------------------------------------
data_dir <- Sys.getenv('HANSEN_DATA_ROOT', unset=file.path(getwd(),'data/hansen_source'))
start_year <- 2015L
end_year <- 2025L
canopy_threshold_2000 <- 30
make_state_map <- TRUE       # Main Figure 3: state/FCT loss concentrations.
state_map_year <- NA_integer_  # Entire 2015–2025 period, not 2025 alone.
reuse_cached_tables <- TRUE
project_id <- Sys.getenv('EE_PROJECT', unset='ivory-mountain-435913-n2')
out_dir <- file.path(getwd(),'figures/hansen')
dir.create(out_dir,recursive=TRUE,showWarnings=FALSE)
cache_dir <- file.path(out_dir,'cache')
dir.create(cache_dir,showWarnings=FALSE)
options(timeout=600)

# Your terra installation may be in this study-specific library.
local_lib <- file.path(path.expand('~'),'.local/share/nigeria-tree-cover/R-library')
if (dir.exists(local_lib)) .libPaths(c(local_lib,.libPaths()))
packages <- c('terra','sf','dplyr','tidyr','readr','ggplot2','scales')
missing <- packages[!vapply(packages,function(p) length(find.package(p,quiet=TRUE))>0,logical(1))]
if (length(missing)) stop('Install these R packages, then run again: ',paste(missing,collapse=', '),
 '\nExample: install.packages(c("',paste(missing,collapse='","'),'"), repos="https://cloud.r-project.org")')
library(terra); library(sf); library(dplyr); library(ggplot2)
terraOptions(memfrac=0.25, progress=0)
stopifnot(start_year>=2001,end_year<=2025,start_year<=end_year)
years <- seq.int(start_year,end_year)
tag <- sprintf('Hansen_v1_13_%d_%d_canopy%d',start_year,end_year,canopy_threshold_2000)

# 2. LOAD LOCAL DATA ----------------------------------------------------
# On a fresh checkout, download 12 official source tiles (~1.4 GB total).
# Set HANSEN_DATA_ROOT to reuse an existing source folder instead.
dir.create(file.path(data_dir,'data/derived'),recursive=TRUE,showWarnings=FALSE)
dir.create(file.path(data_dir,'data/raw/hansen'),recursive=TRUE,showWarnings=FALSE)
for (band in c('lossyear','treecover2000','datamask')) {
 vrt_file <- file.path(data_dir,'data/derived',paste0(band,'.vrt'))
 if (!file.exists(vrt_file)) {
  tiles <- c('10N_000E','10N_010E','20N_000E','20N_010E')
  tile_files <- file.path(data_dir,'data/raw/hansen',paste0('Hansen_GFC-2025-v1.13_',band,'_',tiles,'.tif'))
  for (i in seq_along(tile_files)) if (!file.exists(tile_files[i])) {
   url <- paste0('https://storage.googleapis.com/earthenginepartners-hansen/GFC-2025-v1.13/',basename(tile_files[i]))
   message('Downloading ',basename(tile_files[i]))
   part <- paste0(tile_files[i],'.part'); download.file(url,part,mode='wb',method='libcurl')
   stopifnot(file.rename(part,tile_files[i]))
  }
  terra::vrt(tile_files,filename=vrt_file,overwrite=TRUE)
 }
}
zone_rds <- file.path(data_dir,'data/derived/zones.rds')
if (!file.exists(zone_rds)) {
 zone_file <- list.files('data/dynamic_world',pattern='^zones_.*geojson$',full.names=TRUE)[1]
 saveRDS(sf::st_read(zone_file,quiet=TRUE),zone_rds)
}
files <- file.path(data_dir,'data/derived',c('zones.rds','lossyear.vrt','treecover2000.vrt','datamask.vrt'))
if (any(!file.exists(files))) stop('Check data_dir. Missing: ',paste(files[!file.exists(files)],collapse='\n'))
zones <- readRDS(files[1]) |> st_make_valid() |> st_collection_extract('POLYGON')
expected <- c('North Central','North East','North West','South East','South South','South West')
stopifnot(nrow(zones)==6,!anyDuplicated(zones$zone),setequal(zones$zone,expected))
zones$region <- zones$zone
loss_year <- rast(files[2]); canopy <- rast(files[3]); land_mask <- rast(files[4])
stopifnot(compareGeom(loss_year,canopy,stopOnError=FALSE),
          compareGeom(loss_year,land_mask,stopOnError=FALSE))

# 3. LOCAL AREA EXTRACTION, WITH REUSABLE TABLE CACHES --------------------
# Uses cell-centre polygon inclusion. Geographic cell areas are computed in
# hectares; a fixed 900 m² per pixel is NOT assumed. Boundary approximation
# and classification uncertainty remain. Large rasters use terra disk/chunks.
extract_annual <- function(regions, cache_file) {
 signature <- list(tag=tag,data_dir=normalizePath(data_dir),
   polygon_md5=NA_character_,region_names=as.character(regions$region))
 # Exact geometry bytes included in the cache signature.
 geom_file <- tempfile(fileext='.rds'); saveRDS(st_geometry(regions),geom_file)
 signature$polygon_md5 <- unname(tools::md5sum(geom_file)); unlink(geom_file)
 meta_file <- paste0(cache_file,'.rds')
 if (reuse_cached_tables && file.exists(cache_file) && file.exists(meta_file) &&
     identical(readRDS(meta_file),signature)) {
  message('Reusing ',basename(cache_file))
  return(readr::read_csv(cache_file,show_col_types=FALSE))
 }
 polygon_area <- as.numeric(st_area(st_transform(regions,6933)))/1e4
 results <- vector('list',nrow(regions))
 for (i in seq_len(nrow(regions))) {
  message(sprintf('Local calculation %d/%d: %s',i,nrow(regions),regions$region[i]))
  region <- vect(regions[i,])
  ly <- crop(loss_year,region)
  tc <- crop(canopy,ly)
  dm <- crop(land_mask,ly)
  # Map land excludes persistent water and no-data categories.
  area <- cellSize(ly,unit='ha')
  valid_land <- mask(ifel(dm==1,area,NA),region)
  mapped_land_ha <- as.numeric(global(valid_land,'sum',na.rm=TRUE)[1,1])
  if (!is.finite(mapped_land_ha) || mapped_land_ha<=0)
   stop('No mapped land data for ',regions$region[i],'; refusing to substitute zero loss.')
  eligible <- ifel(dm==1 & tc>=canopy_threshold_2000,ly,NA)
  eligible <- mask(eligible,region)
  eligible_area <- mask(area,eligible)
  eligible_ha <- as.numeric(global(eligible_area,'sum',na.rm=TRUE)[1,1])
  if (!is.finite(eligible_ha)) eligible_ha <- 0
  if (eligible_ha>0) {
   totals <- zonal(eligible_area,eligible,fun='sum',na.rm=TRUE)
   names(totals) <- c('loss_code','loss_ha')
  } else {
   # Valid mapped land, but none meets the year-2000 canopy filter.
   totals <- data.frame(loss_code=integer(),loss_ha=numeric())
  }
  stopifnot(all(totals$loss_code %in% 0:25),all(totals$loss_ha>=0))
  results[[i]] <- tibble(region=as.character(regions$region[i]),year=years,
    loss_code=years-2000L) |>
   left_join(totals,by='loss_code') |>
   mutate(loss_ha=coalesce(loss_ha,0),region_area_ha=polygon_area[i],
          mapped_land_ha=mapped_land_ha,eligible_2000_canopy_ha=eligible_ha) |>
   select(-loss_code)
  rm(ly,tc,dm,area,valid_land,eligible,eligible_area,totals); gc(verbose=FALSE)
 }
 result <- bind_rows(results) |> mutate(loss_km2=loss_ha/100,
  loss_pct_of_region_area=100*loss_ha/region_area_ha,
  canopy_threshold_2000_pct=canopy_threshold_2000)
 stopifnot(nrow(result)==nrow(regions)*length(years),
  !anyDuplicated(result[c('region','year')]),all(is.finite(result$loss_ha)),all(result$loss_ha>=0))
 readr::write_csv(result,cache_file); saveRDS(signature,meta_file)
 result
}
annual_zone <- extract_annual(zones,file.path(cache_dir,paste0('zone_annual_',tag,'.csv')))
zone_total <- annual_zone |> group_by(region) |>
 summarise(total_loss_ha=sum(loss_ha),total_loss_km2=sum(loss_km2),
  region_area_ha=first(region_area_ha),mapped_land_ha=first(mapped_land_ha),
  mean_annual_loss_ha=mean(loss_ha),.groups='drop') |>
 mutate(loss_pct_of_region_area=100*total_loss_ha/region_area_ha) |>
 arrange(desc(total_loss_km2))
annual_nigeria <- annual_zone |> group_by(year) |>
 summarise(loss_ha=sum(loss_ha),loss_km2=sum(loss_km2),.groups='drop') |> arrange(year)
# A descriptive 3-year moving mean; no invented confidence intervals.
annual_nigeria$moving_mean_km2 <- as.numeric(stats::filter(annual_nigeria$loss_km2,
                                                       rep(1/3,3),sides=2))
peak_years <- annual_nigeria$year[annual_nigeria$loss_km2==max(annual_nigeria$loss_km2)]
readr::write_csv(zone_total,file.path(out_dir,'zone_totals_and_size_adjustment.csv'))
readr::write_csv(annual_nigeria,file.path(out_dir,'annual_nigeria_loss.csv'))
readr::write_csv(annual_zone,file.path(out_dir,'annual_zone_loss.csv'))

dir.create('data/hansen',recursive=TRUE,showWarnings=FALSE)
for (f in list.files(out_dir,pattern='[.]csv$',full.names=TRUE)) file.copy(f,file.path('data/hansen',basename(f)),overwrite=TRUE)

# 4. SHARED FIGURE STYLE ------------------------------------------------
period <- sprintf('%d–%d inclusive',start_year,end_year)
source_note <- sprintf('Hansen/UMD/Google/USGS/NASA, GFC v1.13; >=%d%% canopy in 2000. Mapped estimates, not accuracy-adjusted areas.',canopy_threshold_2000)
theme_study <- theme_minimal(base_size=13)+theme(
 plot.title=element_text(face='bold',size=18),plot.subtitle=element_text(colour='grey35'),
 panel.grid.minor=element_blank(),plot.caption=element_text(hjust=0,size=9),
 legend.position='bottom')
loss_colours <- c('#087f5b','#a8d75d','#ffe169','#f48d35','#c52727')

# FIGURE 1: ABSOLUTE AND AREA-NORMALIZED REGIONAL RANKINGS ---------------
zone_order <- rev(zone_total$region)
rank_rows <- bind_rows(
 zone_total |> transmute(region,metric='Total mapped loss (km²)',value=total_loss_km2),
 zone_total |> transmute(region,metric='Mapped loss / zone area (%)',value=loss_pct_of_region_area)
)
rank_rows$region <- factor(rank_rows$region,levels=zone_order)
rank_rows$metric <- factor(rank_rows$metric,
 levels=c('Total mapped loss (km²)','Mapped loss / zone area (%)'))
p1 <- ggplot(rank_rows,aes(value,region,fill=metric))+
 geom_col(width=.7)+
 geom_text(aes(label=ifelse(metric=='Total mapped loss (km²)',
  scales::number(value,accuracy=.1,big.mark=','),ifelse(value>0 & value<.01,'<0.01%',sprintf('%.2f%%',value)))),
  hjust=-.1,size=3.7)+
 facet_wrap(~metric,nrow=1,scales='free_x')+
 scale_fill_manual(values=c('Total mapped loss (km²)'='#b73535',
 'Mapped loss / zone area (%)'='#247ba0'),guide='none')+
 scale_x_continuous(labels=scales::label_number(big.mark=','),
                    expand=expansion(mult=c(0,.3)))+
 labs(title='Which geopolitical zone experienced the greatest mapped loss?',
 subtitle=period,x=NULL,y=NULL,
 caption=paste(source_note,'\nArea normalization controls geographic size only; it does not control baseline tree cover.'))+
 theme_study+theme(panel.spacing.x=grid::unit(2,'lines'))

# GRAPH 2: ANNUAL TREND -------------------------------------------------
p2 <- ggplot(annual_nigeria,aes(year,loss_km2))+
 geom_line(aes(colour='Recorded annual loss'),linewidth=.9)+
 geom_point(aes(colour='Recorded annual loss'),size=2.8)+
 geom_line(aes(y=moving_mean_km2,colour='3-year moving mean'),linewidth=1,
           linetype='dashed',na.rm=TRUE)+
 scale_colour_manual(values=c('Recorded annual loss'='#247ba0','3-year moving mean'='#d4941d'),name=NULL)+
 scale_x_continuous(breaks=years)+scale_y_continuous(labels=scales::label_comma(),
 limits=c(0,NA),expand=expansion(mult=c(0,.1)))+
 labs(title='Which years recorded the most tree-cover loss in Nigeria?',
 subtitle=paste(period,'| Peak year(s):',paste(peak_years,collapse=', ')),
 x='Year',y='Mapped loss (km² per calendar year)',
 caption=paste(source_note,'\nDashed line: descriptive moving mean; no uncertainty interval is estimated.'))+theme_study

# SUPPLEMENT: GEOGRAPHIC-SIZE-ADJUSTED ZONE MAP ------------------------------
zone_map <- zones |> left_join(zone_total,by='region')
points <- st_point_on_surface(st_geometry(st_transform(zone_map,6933)))
label_points <- st_sf(region=zone_map$region,
 label=paste0(zone_map$region,'\n',ifelse(zone_map$loss_pct_of_region_area<.01 & zone_map$loss_pct_of_region_area>0,'<0.01%',sprintf('%.2f%%',zone_map$loss_pct_of_region_area))),
 geometry=points) |> st_transform(st_crs(zone_map))
p3 <- ggplot(zone_map)+geom_sf(aes(fill=loss_pct_of_region_area),colour='grey20',linewidth=.5)+
 scale_fill_gradientn(colours=loss_colours,name='Mapped loss\n(% of zone area)')+
 geom_sf_label(data=label_points,aes(label=label),size=3.5,
               label.padding=grid::unit(.12,'lines'),fill='white',alpha=.9)+
 labs(title='Tree-cover loss adjusted for geopolitical-zone size',subtitle=period,
 caption=paste(source_note,'\nPercentage = mapped loss / full geographic zone area × 100. This does not control for baseline tree cover.'))+
 theme_void(base_size=13)+theme(plot.title=element_text(face='bold',size=18),
 legend.position='bottom',plot.caption=element_text(hjust=0,size=9))

ggsave(file.path(out_dir,'01_regional_ranking.png'),p1,width=11,height=7,dpi=300,bg='white')
ggsave(file.path(out_dir,'02_annual_trend.png'),p2,width=12,height=7,dpi=300,bg='white')
ggsave(file.path(out_dir,'supplement_size_adjusted_zone_map.png'),p3,width=11,height=9,dpi=300,bg='white')
if (interactive()) {print(p1); print(p2)}
message('Figures 1 and 2 saved in: ',normalizePath(out_dir))

# 5. FIGURE 3: STATE/FCT LOSS CONCENTRATIONS ----------------------------
# Only boundaries are downloaded from Earth Engine; all loss calculations
# below remain LOCAL in R. This does not submit another batch export.
if (make_state_map) {
 tryCatch({
  state_file <- 'data/hansen/Nigeria_states_GAUL2015.geojson'
  if (!file.exists(state_file)) {
   if (!requireNamespace('reticulate',quietly=TRUE)) stop('Install reticulate to obtain state boundaries for Figure 3.')
   Sys.setenv(RETICULATE_PYTHON='managed')
   Sys.unsetenv('EARTHENGINE_PYTHON')
   reticulate::py_require(c('earthengine-api','certifi','numpy'),action='add')
   cert <- reticulate::import('certifi')$where()
   Sys.setenv(SSL_CERT_FILE=cert,REQUESTS_CA_BUNDLE=cert,HTTPLIB2_CA_CERTS=cert)
   ee <- reticulate::import('ee'); ee$Initialize(project=project_id)
   fc <- ee$FeatureCollection('FAO/GAUL/2015/level1')$
    filter(ee$Filter$eq('ADM0_NAME','Nigeria'))
   url <- fc$getDownloadURL(filetype='geojson',filename='Nigeria_states_GAUL2015')
   part <- paste0(state_file,'.part')
   utils::download.file(url,part,mode='wb',method='libcurl',quiet=TRUE)
   check <- sf::st_read(part,quiet=TRUE)
   stopifnot(nrow(check)==37)
   file.copy(part,state_file,overwrite=TRUE); unlink(part)
  }
  states <- st_read(state_file,quiet=TRUE) |> st_make_valid() |> st_collection_extract('POLYGON')
  states$region <- as.character(states$ADM1_NAME)
  stopifnot(nrow(states)==37,!anyDuplicated(states$region))
  annual_state <- extract_annual(states,file.path(cache_dir,paste0('state_annual_',tag,'.csv')))
  readr::write_csv(annual_state,file.path(out_dir,'annual_state_loss.csv'))
  state_total <- annual_state |> group_by(region) |>
   summarise(total_loss_ha=sum(loss_ha),total_loss_km2=sum(loss_km2),
    region_area_ha=first(region_area_ha),.groups='drop') |>
   mutate(loss_pct_of_state_area=100*total_loss_ha/region_area_ha)
  # Record reconciliation; boundary-cell allocation can introduce small differences.
  state_sum <- sum(state_total$total_loss_ha); zone_sum <- sum(zone_total$total_loss_ha)
  reconciliation <- data.frame(zone_sum_ha=zone_sum,state_sum_ha=state_sum,
    difference_ha=state_sum-zone_sum,
    relative_difference_pct=if(zone_sum>0) 100*(state_sum-zone_sum)/zone_sum else NA_real_)
  readr::write_csv(reconciliation,file.path(out_dir,'state_zone_reconciliation.csv'))
  readr::write_csv(state_total,file.path(out_dir,'state_totals_and_size_adjustment.csv'))
  if (is.na(state_map_year)) {
   state_values <- state_total
   state_period <- period
   state_suffix <- '2015_2025'
  } else {
   stopifnot(state_map_year %in% years)
   state_values <- annual_state |> filter(year==state_map_year) |>
    transmute(region,total_loss_ha=loss_ha,total_loss_km2=loss_km2)
   state_period <- as.character(state_map_year)
   state_suffix <- as.character(state_map_year)
  }
  if (!'region_area_ha' %in% names(state_values)) {
   state_values <- state_values |> left_join(state_total |> select(region,region_area_ha),by='region')
  }
  state_values$loss_pct_of_state_area <- 100*state_values$total_loss_ha/state_values$region_area_ha
  state_map <- states |> left_join(state_values,by='region')
  st_write(st_transform(state_map,4326),'data/hansen/state_loss_concentrations.geojson',delete_dsn=TRUE,quiet=TRUE)
  for (f in list.files(out_dir,pattern='[.]csv$',full.names=TRUE)) file.copy(f,file.path('data/hansen',basename(f)),overwrite=TRUE)
  # Map geographic-size-adjusted concentrations, with actual percentages.
  # This is a state-level choropleth, not a fine-scale hotspot-significance test.
  label_geom <- st_point_on_surface(st_geometry(st_transform(state_map,6933)))
  labels <- st_sf(label=paste0(state_map$region,'\n',
    ifelse(state_map$loss_pct_of_state_area>0 & state_map$loss_pct_of_state_area<.01,'<0.01%',sprintf('%.2f%%',state_map$loss_pct_of_state_area))),
    geometry=label_geom) |> st_transform(st_crs(state_map))
  p4 <- ggplot(state_map)+
   geom_sf(aes(fill=loss_pct_of_state_area),colour='grey20',linewidth=.25)+
   scale_fill_gradientn(colours=loss_colours,name='Mapped loss\n(% of state area)',
                        labels=scales::label_number(accuracy=.01),
                        guide=guide_colourbar(title.position='top',title.hjust=.5,barwidth=grid::unit(8,'cm')))+
   geom_sf_label(data=labels,aes(label=label),size=2.1,
                 label.padding=grid::unit(.06,'lines'),fill='white',alpha=.88)+
   labs(title='Where was mapped tree-cover loss concentrated?',
    subtitle=paste('States and FCT |',state_period),
    caption=paste(source_note,
     '\nState labels = mapped loss / state geographic area × 100. Absolute km² are supplied in the accompanying CSV.',
     '\nState-level concentrations are exploratory; they are not proof of deforestation causes or significant fine-scale clusters.'))+
   theme_void(base_size=12)+theme(plot.title=element_text(face='bold',size=18),
    legend.position='bottom',plot.caption=element_text(hjust=0,size=9))
  ggsave(file.path(out_dir,'03_state_loss_concentrations.png'),p4,width=14,height=13,dpi=350,bg='white')
  message('Figure 3 saved in: ',normalizePath(out_dir))
  if (interactive()) print(p4)
 },error=function(e) {
  message('Figures 1 and 2 are saved. Figure 3 stopped: ',conditionMessage(e),
          '\nCorrect the boundary/data issue and rerun; cached area tables are reused.')
 })
}
writeLines(capture.output(sessionInfo()),file.path(out_dir,'R_session_info.txt'))
writeLines(c(
 'Source: Hansen/UMD/Google/USGS/NASA, GFC 2025 v1.13.',
 '2015–2025 inclusive includes ELEVEN annual loss observations.',
 'The Dynamic World satellite comparison is supplementary; it is not used to quantify this loss series.',
 'This workflow addresses mapped gross loss only; it does not estimate 2015–2025 gain or net tree-cover change.',
 'Year-2000 canopy >=30% is not 2015 tree-cover extent; later-established trees may be omitted.',
 'Mapped loss includes stand-replacement disturbances; it is not automatically permanent deforestation.',
 'Area-normalization controls geographic size only, not baseline tree cover, ecosystem differences or mapping error.',
 'Annual comparability is affected by sensor, observation availability and algorithm changes.',
 'No confidence intervals, causal attribution or inferential tests were fabricated.',
 'Hansen source/use notes: https://storage.googleapis.com/earthenginepartners-hansen/GFC-2025-v1.13/download.html',
 'FAO GAUL 2015 is a fixed, deprecated boundary vintage with separate non-commercial-use conditions.'
),file.path(out_dir,'source_and_limitations.txt'))
