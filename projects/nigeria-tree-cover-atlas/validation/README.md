# Validation scope

**Share with caveats.** This is an exploratory mapped-change analysis, not an accuracy-adjusted national inventory.

Checks run on 5 November 2026:

- Six unique zones, 37 states/FCT, eleven annual Hansen observations per region.
- Dynamic World transition identities, nonnegative areas, metadata and percentage denominators checked in R.
- All 9,419 original grid geometries repaired using their recorded EPSG:32632 source CRS and transformed to EPSG:4326; 9,412 positive-Nigeria-area cells enter analysis. Zero-area boundary cells are excluded, not treated as observations.
- Zone/grid sums reconcile within 0.002% for all tested measures; differences arise at rasterized polygon boundaries. See `zone_grid_reconciliation.csv`.
- Sample-based classification sensitivity: 1,200 deterministic random points (200/zone), nine settings (probability 0.4/0.5/0.6 × prediction count 1/2/3), 10 m sampling. The saved sample allows the R audit to run without Earth Engine. Predictions are not guaranteed to be unique acquisition dates.
- Main-setting paired sample sizes: North Central 51, North East 142, North West 89, South East 0, South South 2, South West 5. These southern samples do not support stable estimates. Zero changes at two sampled South South points do not demonstrate no loss in the zone.
- Corrected queen-adjacency grouping uses integer grid coordinates. Reprojection no longer determines whether cells touch.
- Hansen state and zone totals differ by 0.0367% (4.04 km²), retained without forced rescaling. Both annual and regional totals reconcile internally; boundary/cell inclusion differs slightly.
- Figures inspected for legends, units, masking and explicit missingness. PNG maps exported with a white background for readable titles and legends.

## Limits that remain

Full-area sensitivity reruns at 10 m and independent reference-label accuracy validation are **not completed**. The Earth Engine project reports its noncommercial compute quota is exceeded and restricted mode is active. The small sample still returned successfully; local R calculations use already downloaded Hansen rasters. The probability/observation scenarios do not measure classification accuracy or provide confidence intervals.

Dynamic World coverage is strongly spatially selective. South East has no paired footprint. South West and South South observed-footprint change rates cannot be used as whole-zone rates, and there is no national extrapolation. Missing observations and stable non-tree classification are different conditions.

Hansen gross loss and Dynamic World endpoint loss/gain have different definitions, baselines, resolutions and temporal windows. Hansen is annual loss during calendar years 2015 through 2025 inclusive; the endpoint comparison is the difference between two seasonal classifications. Do not add them together or infer causality from their disagreement. Hansen cannot establish gain or net change in this period.

`R/Validate_Exports.R` and the two audit CSVs expose arithmetic and coverage checks. Source agreement is not independent proof of accuracy. See `DATA_SOURCES.md` for source-specific limitations and terms.
