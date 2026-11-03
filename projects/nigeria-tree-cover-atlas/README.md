# Nigeria Tree Cover Change Atlas: 2015–2026

**Status:** pilot project, analysis not yet run. Six geopolitical zones, 36 states + Federal Capital Territory.

Research question: **What changed in satellite-estimated tree cover across Nigeria's six geopolitical zones between matching July–October windows in 2015 and 2026?**

## Research design

- **Regions:** North Central, North East, North West, South East, South South, South West.
- **Visuals:** Landsat 8 cloud-masked satellite imagery in 2015 and 2026; Dynamic World tree-cover maps and preliminary change classification (stable, apparent loss, apparent gain).
- **Datasets:** [Dynamic World](https://developers.google.com/earth-engine/datasets/catalog/GOOGLE_DYNAMICWORLD_V1), [Landsat 8 Collection 2](https://developers.google.com/earth-engine/datasets/catalog/LANDSAT_LC08_C02_T1_L2), [FAO GAUL admin boundaries](https://developers.google.com/earth-engine/datasets/catalog/FAO_GAUL_2015_level1).
- **Historical check:** [Hansen/UMD Global Forest Change 2000–2025](https://developers.google.com/earth-engine/datasets/catalog/UMD_hansen_global_forest_change_2025_v1_13).
- **Season:** July 1 through October 31 of each year, using currently available 2026 imagery.

## Initial visual workflow

The [Earth Engine script](earth-engine/visual_comparison.js) displays real 2015/2026 satellite views and Dynamic World tree-cover change. Paste it into the [Earth Engine Code Editor](https://code.earthengine.google.com/) and press **Run**, then use the Layers control to switch imagery on and off. An authenticated Earth Engine project is required.

The full analysis starter package (available in the original planning conversation) adds six-zone area estimation, observation coverage checks, CSV/GeoJSON exports, methodology notes and a chart generation script.

## Scientific safeguards

1. 2015 Sentinel-2 observations may be sparse and geographically uneven. Missing pixels are **not** forest loss. Only compare pixels observed adequately in both years.
2. The 2026 snapshot is **provisional**, not full-year change.
3. Satellite tree cover is not necessarily intact natural forest; apparent change is not proof of deforestation or restoration.
4. No numerical results or final maps are claimed until the Earth Engine project has run and outputs have been validated.

## Upcoming deliverables

- [x] Scope, sources, scripts and seasonal comparison plan
- [ ] Run the imagery workflow and audit observation coverage
- [ ] Validate zone boundaries and classification
- [ ] Publish verified maps, per-zone CSV tables and reproducible charts
- [ ] Create a live, visual-first Nigeria tree-cover dashboard
