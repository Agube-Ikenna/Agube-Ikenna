# Independent checks on the saved measurements; this does not measure map accuracy.
library(readr); library(sf); library(dplyr); library(jsonlite)
z <- read_csv('data/dynamic_world/zone_rankings_and_coverage.csv',show_col_types=FALSE)
g <- read_csv('data/dynamic_world/grid_metrics_clean.csv',show_col_types=FALSE)
stopifnot(nrow(z)==6,!anyDuplicated(z$zone),!anyDuplicated(g$grid_id))
fields <- c('region_km2','common_km2','persistent_km2','non_tree_km2','loss_km2','gain_km2')
reconcile <- data.frame(measure=fields,zone_sum=sapply(z[fields],sum),grid_sum=sapply(g[fields],sum))
reconcile$relative_difference_pct <- 100*(reconcile$grid_sum-reconcile$zone_sum)/reconcile$zone_sum
stopifnot(all(abs(reconcile$relative_difference_pct)<0.1))
write_csv(reconcile,'validation/zone_grid_reconciliation.csv')
closure <- with(z,persistent_km2+non_tree_km2+loss_km2+gain_km2-common_km2)
stopifnot(all(abs(closure)<1e-5),all(abs(z$gross_change_pct_common[z$common_km2>0]-
 100*(z$loss_km2+z$gain_km2)[z$common_km2>0]/z$common_km2[z$common_km2>0])<1e-8),
 all(is.na(z$gross_change_pct_common[z$common_km2==0])))
geo <- st_read('data/dynamic_world/grid_metrics_wgs84.geojson',quiet=TRUE)
geo <- geo[!is.na(geo$region_km2) & geo$region_km2>0,]
stopifnot(nrow(geo)==nrow(g),all(st_is_valid(geo)),!anyDuplicated(geo$grid_id),
 all(abs(st_bbox(geo)[c('xmin','xmax')])<=180),all(abs(st_bbox(geo)[c('ymin','ymax')])<=90))
write_json(list(status='passed',zone_rows=nrow(z),grid_rows=nrow(g),
 max_transition_closure_error_km2=max(abs(closure)),
 classification_accuracy='Not assessed: no independent reference labels',
 interpretation='Footprint-limited endpoint estimates; no national extrapolation'),
 'validation/export_checks.json',auto_unbox=TRUE,pretty=TRUE,digits=NA)
# Hansen: reconcile independently across output grains and guard percentage units.
annual <- read_csv('data/hansen/annual_nigeria_loss.csv',show_col_types=FALSE)
zannual <- read_csv('data/hansen/annual_zone_loss.csv',show_col_types=FALSE)
sannual <- read_csv('data/hansen/annual_state_loss.csv',show_col_types=FALSE)
zt <- read_csv('data/hansen/zone_totals_and_size_adjustment.csv',show_col_types=FALSE)
st <- read_csv('data/hansen/state_totals_and_size_adjustment.csv',show_col_types=FALSE)
stopifnot(nrow(annual)==11,setequal(annual$year,2015:2025),nrow(zannual)==66,
 nrow(sannual)==407,nrow(st)==37,!anyDuplicated(zannual[c('region','year')]),
 !anyDuplicated(sannual[c('region','year')]),all(zt$total_loss_km2>=0),
 all(abs(zt$loss_pct_of_region_area-100*zt$total_loss_ha/zt$region_area_ha)<1e-8),
 all(abs(st$loss_pct_of_state_area-100*st$total_loss_ha/st$region_area_ha)<1e-8))
by_year <- zannual |> group_by(year) |> summarise(zone_km2=sum(loss_km2),.groups='drop') |>
 left_join(annual,by='year')
stopifnot(all(abs(by_year$zone_km2-by_year$loss_km2)<1e-8),
 abs(sum(zt$total_loss_km2)-sum(annual$loss_km2))<1e-8)
reconciliation <- read_csv('data/hansen/state_zone_reconciliation.csv',show_col_types=FALSE)
stopifnot(abs(reconciliation$relative_difference_pct)<0.1)
write_json(list(status='passed',zone_year_rows=nrow(zannual),state_year_rows=nrow(sannual),
 peak_year=annual$year[which.max(annual$loss_km2)],
 total_mapped_loss_km2=sum(annual$loss_km2),
 state_zone_difference_pct=reconciliation$relative_difference_pct,
 independent_accuracy_validation='Not completed'),
 'validation/hansen_checks.json',pretty=TRUE,auto_unbox=TRUE,digits=NA)
