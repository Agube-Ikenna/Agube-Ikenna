# Run after both analytical scripts and the audit; preserves dashboard identity.
library(jsonlite); library(readr); library(sf)
file <- 'dashboard/src/data.json'
snapshot <- read_json(file,simplifyVector=FALSE)
read_rows <- function(path) {
 if (!file.exists(path)) stop('Required output missing: ',path)
 read_csv(path,show_col_types=FALSE) |> as.data.frame()
}
query <- function(path,label,provider,url,description,definition) {
 list(rows=read_rows(path),source=list(label=label,provider=provider,files=list(path),
  links=list(list(label=label,url=url)),description=description,
  evidenceFlow=list(list(title='Reproduce',detail=paste('Run the R scripts described in README.md. Input/output:',path))),
  metricDefinitions=list(list(label=label,definition=definition))))
}
hansen_url <- 'https://developers.google.com/earth-engine/datasets/catalog/UMD_hansen_global_forest_change_2025_v1_13'
dw_url <- 'https://developers.google.com/earth-engine/datasets/catalog/GOOGLE_DYNAMICWORLD_V1'
snapshot$queries$dw_zones <- query('data/dynamic_world/zone_rankings_and_coverage.csv',
 'Dynamic World endpoint metrics','Google Earth Engine',dw_url,
 'July–October 2015 versus 2025, 10 m grid, mean tree probability >=0.5, >=2 predictions per endpoint. No extrapolation.',
 'Change (%) = 100*(loss_km2+gain_km2)/common_km2; paired coverage (%) =100*common_km2/region_km2. Null change where no paired area.')
snapshot$queries$dw_hotspots <- query('data/dynamic_world/candidate_cluster_summary.csv',
 'Candidate high-loss cell groups','Google Earth Engine / R',dw_url,
 '10 km grid; groups use integer gx/gy queen adjacency. Singletons are in the table but only groups >=2 cells are outlined in the figure.',
 'Eligible cells: >=50% paired coverage and >=1 km² baseline tree area. High loss: top decile of positive loss / baseline-tree area. Not a significance test.')
snapshot$queries$hansen_annual <- query('data/hansen/annual_nigeria_loss.csv',
 'Nigeria annual mapped gross loss','Hansen/UMD/Google/USGS/NASA',hansen_url,
 'GFC 2025 v1.13, 2015–2025 inclusive; year-2000 canopy >=30%; mapped land only.',
 'Sum of geodesic pixel area assigned to each annual loss code across the six zones; km² = hectares/100. Gross loss, not net change or permanent deforestation.')
snapshot$queries$hansen_zones <- query('data/hansen/zone_totals_and_size_adjustment.csv',
 'Six-zone mapped gross loss','Hansen/UMD/Google/USGS/NASA',hansen_url,
 'GFC 2025 v1.13; sum of eleven annual loss observations, 2015–2025. Cell-centre boundary inclusion.',
 'Loss / zone area (%) =100*total_loss_ha/region_area_ha. Geographic size adjustment does not control for baseline tree cover.')
snapshot$queries$hansen_states <- query('data/hansen/state_totals_and_size_adjustment.csv',
 'State and FCT mapped gross loss','Hansen / FAO GAUL 2015',hansen_url,
 '36 states and FCT; fixed GAUL 2015 boundary vintage; 2015–2025 gross loss under the 30% canopy filter.',
 'Loss / state area (%) =100*total_loss_ha/region_area_ha. State-level concentrations, not statistically significant fine-scale hotspots.')
snapshot$queries$sensitivity <- query('validation/classification_sensitivity_sample.csv',
 'Sample-based classification sensitivity','Google Earth Engine / R',dw_url,
 '200 random points per zone, seed 20152025, 10 m sampling, July–October 2015/2025.',
 'Nine combinations: mean tree probability 0.4/0.5/0.6 and >=1/2/3 predictions. 100*(loss_points+gain_points)/paired_points; null where paired_points=0. Not full-area estimates or independent accuracy validation.')
snapshot$generatedAt <- format(Sys.time(),'%Y-%m-%dT%H:%M:%SZ',tz='UTC')
snapshot$status <- 'observed'
snapshot$buildStatus <- 'complete'
write_json(snapshot,file,auto_unbox=TRUE,pretty=TRUE,digits=NA,na='null')
file.copy('figures/dynamic_world/01_satellite_comparison.png','dashboard/src/content/assets/01_satellite_comparison.png',overwrite=TRUE)
file.copy('figures/dynamic_world/03_candidate_hotspots.png','dashboard/src/content/assets/03_candidate_hotspots.png',overwrite=TRUE)
file.copy('figures/hansen/03_state_loss_concentrations.png','dashboard/src/content/assets/03_state_loss_concentrations.png',overwrite=TRUE)
