# Nigeria Tree-Cover Change Atlas | 2015–2025

**A remote-sensing and R analysis of Nigeria's six geopolitical zones.**

## What changed, and where?

This project combines satellite land-cover classification, spatial grids and annual forest-loss records to explore changes across Nigeria.

### Findings from the generated figures

| Measure | Finding |
|---|---|
| Highest annual mapped loss (Hansen/UMD) | **2017**, approximately **1,700 km²** in the supplied chart |
| Highest apparent endpoint change among reported zones (Dynamic World) | **South West: 23.4%** of common-observed area |
| Second-highest apparent endpoint change | **South South: 21.5%** of common-observed area |
| Other endpoint-change rates | North Central **19.9%**, North West **8.7%**, North East **8.4%** |
| South East endpoint comparison | No paired data in the supplied zone figure |
| Candidate hotspot areas | Spatial clusters visible in parts of northern and central Nigeria; exploratory, not statistically confirmed |

**Interpretation:** The satellite-derived patterns are geographically uneven. Agriculture, development and other land-use pressures are plausible explanations to investigate, **not causes demonstrated by these maps**.

## How it was done

- **R:** `sf`, `dplyr`, `ggplot2`, `rgee`, `reticulate`, `readr`, `tidyr`, `scales`.
- **Google Earth Engine:** Satellite data processing and cloud-based area calculations.
- **Dynamic World (Sentinel-2):** July–October 2015 and 2025 tree-probability composites, threshold **0.50**, at least **2 observations** at each endpoint, using a common valid footprint.
- **Landsat 8 Collection 2:** Cloud-masked RGB imagery for side-by-side visual context.
- **FAO GAUL 2015:** State boundaries aggregated into six geopolitical zones.
- **10 km grid:** Exploratory loss hotspots defined as the top 10% of positive eligible loss rates, with at least 50% common coverage and 1 km² baseline tree-class area.
- **Hansen Global Forest Change v1.13:** Separate annual **gross** tree-cover-loss series for 2015–2025, restricted to areas with at least 30% canopy in 2000.

The Dynamic World endpoint comparison and Hansen annual-loss series are **different measurements** and should not be added together or interpreted as interchangeable.

### Calculation

```text
Apparent endpoint change (%) =
  100 × (apparent loss area + apparent gain area)
      / area with adequate observations at both endpoints
```

The percentage describes change in the *observed footprint*, not the percentage of all Nigerian forest lost. Spatial coverage differs by zone. Hotspot clusters are exploratory; missing or excluded cells do not indicate no change.

## Project files

- [Annual-loss analysis and Earth Engine dashboard](earth-engine/forest_loss_story_2015_2025.js)
- [Satellite comparison script](earth-engine/visual_comparison.js)

The R workflow used for the displayed figures has been shared in the project conversation, but **is not yet committed here**. Likewise, the exported CSV/GeoJSON data and final PNG figures have **not yet been uploaded to this repository**. The results above are transcribed from the figures shared by the project author, not independently recomputed in this repository.

## Data sources

- [Dynamic World](https://developers.google.com/earth-engine/datasets/catalog/GOOGLE_DYNAMICWORLD_V1)
- [Landsat 8 Surface Reflectance](https://developers.google.com/earth-engine/datasets/catalog/LANDSAT_LC08_C02_T1_L2)
- [Hansen Global Forest Change v1.13](https://developers.google.com/earth-engine/datasets/catalog/UMD_hansen_global_forest_change_2025_v1_13)
- [FAO GAUL boundaries](https://developers.google.com/earth-engine/datasets/catalog/FAO_GAUL_2015_level1)

## Next steps

- [x] Build satellite comparison and annual-loss analysis scripts
- [x] Generate initial R maps and interpret the results
- [ ] Commit the complete self-contained R script
- [ ] Upload generated PNG figures and processed CSV/GeoJSON exports
- [ ] Audit observation coverage and validate classification sensitivity
- [ ] Build a visual-first project dashboard

**Status:** Exploratory analysis with initial figures; validation and reproducible result uploads are pending.
