/*
NIGERIA TREE COVER CHANGE ATLAS | STORY DASHBOARD
Measured: annual gross tree-cover loss, 2015–2025 (Hansen/UMD v1.13).
2026: NOT included in the loss statistics. The separate visual_comparison.js
shows provisional 2026 imagery. This script is a study pilot: validate boundaries,
processing choices and reported magnitudes before publishing findings.

HOW TO RUN: paste into https://code.earthengine.google.com/, click Run.
Use the charts in the left panel. Look in Tasks for downloadable CSV exports.
The first run may take time because it analyzes Nigeria at 30-m resolution.
*/

// Six Nigerian geopolitical zones. FCT is counted in North Central.
var statesByZone = {
  'North Central': ['Benue','Kogi','Kwara','Nasarawa','Niger','Plateau','Federal Capital Territory'],
  'North East': ['Adamawa','Bauchi','Borno','Gombe','Taraba','Yobe'],
  'North West': ['Jigawa','Kaduna','Kano','Katsina','Kebbi','Sokoto','Zamfara'],
  'South East': ['Abia','Anambra','Ebonyi','Enugu','Imo'],
  'South South': ['Akwa Ibom','Bayelsa','Cross River','Delta','Edo','Rivers'],
  'South West': ['Ekiti','Lagos','Ogun','Ondo','Osun','Oyo']
};
var zoneNames = Object.keys(statesByZone);
var stateToZone = {};
zoneNames.forEach(function(zone) {
  statesByZone[zone].forEach(function(state) { stateToZone[state] = zone; });
});
// Known possible spelling differences in third-party boundary datasets.
var aliases = {
  'Nassarawa':'Nasarawa',
  'Abuja':'Federal Capital Territory',
  'FCT':'Federal Capital Territory',
  'Federal Capital Territory (Abuja)':'Federal Capital Territory'
};
Object.keys(aliases).forEach(function(alias) {
  stateToZone[alias] = stateToZone[aliases[alias]];
});
var lookup = ee.Dictionary(stateToZone);
var states = ee.FeatureCollection('FAO/GAUL/2015/level1')
  .filter(ee.Filter.eq('ADM0_NAME', 'Nigeria'))
  .map(function(f) {
    var state = ee.String(f.get('ADM1_NAME'));
    return f.set('zone', ee.Algorithms.If(lookup.contains(state),
        lookup.get(state), 'UNMATCHED'));
  });
print('BOUNDARY QA: expecting 37 state/FCT features', states.size());
print('BOUNDARY QA: unmatched feature names (MUST be empty before using results)',
  states.filter(ee.Filter.eq('zone', 'UNMATCHED')).aggregate_array('ADM1_NAME'));
var zones = ee.FeatureCollection(zoneNames.map(function(zone) {
  var group = states.filter(ee.Filter.eq('zone', zone));
  return ee.Feature(group.geometry(), {
    'zone':zone,
    'state_count':group.size()
  });
}));
print('BOUNDARY QA: expected state counts 7,6,7,5,6,6',
  zones.aggregate_array('state_count'));

// Data source: Hansen/UMD/Google/USGS/NASA 2000–2025, 30-m Landsat based.
// Baseline treecover2000 >= 30% is a declared analytical threshold.
// This detects gross canopy loss in areas passing that historic threshold.
// It is NOT a map of all 2015 or 2026 trees, and NOT evidence of causes.
var source = ee.Image('UMD/hansen/global_forest_change_2025_v1_13');
var baseline = source.select('treecover2000').gte(30)
  .and(source.select('datamask').eq(1));
var lossyear = source.select('lossyear');
var yearStart = 2015, yearEnd = 2025;
var annual = ee.Image(0).select([]);
for (var year = yearStart; year <= yearEnd; year++) {
  var band = ee.Image.pixelArea().divide(1e6)
    .multiply(baseline.and(lossyear.eq(year - 2000)))
    .unmask(0)
    .rename('loss_' + year);
  annual = annual.addBands(band);
}

// One multi-band reduction produces regional results for every year.
var stats = annual.reduceRegions({
  collection: zones,
  reducer: ee.Reducer.sum(),
  scale: 30,
  crs: 'EPSG:4326',
  tileScale: 8,
  maxPixelsPerRegion: 2000000000
});
var totals = stats.map(function(f) {
  var total = ee.Number(0);
  for (var y = yearStart; y <= yearEnd; y++) {
    total = total.add(ee.Number(f.get('loss_' + y)));
  }
  var areaKm2 = f.geometry().area(100).divide(1e6);
  return ee.Feature(null, {
    'zone': f.get('zone'),
    'gross_loss_km2_2015_2025': total,
    'zone_area_km2': areaKm2,
    'gross_loss_km2_per_1000_km2_zone': total.divide(areaKm2).multiply(1000)
  });
});

// Long-form per-zone-by-year table: 6 zones x 11 years = 66 observations.
var annualRows = ee.FeatureCollection(
  stats.toList(6).map(function(item) {
    var f = ee.Feature(item);
    return ee.FeatureCollection(ee.List.sequence(yearStart, yearEnd)
      .map(function(y) {
        y = ee.Number(y);
        var key = ee.String('loss_').cat(y.format('%d'));
        return ee.Feature(null, {
          'zone':f.get('zone'),
          'year':y,
          'gross_loss_km2':f.get(key)
        });
      }));
  })
).flatten();
print('Regional totals (2015–2025):', totals);
print('Annual zone-by-zone observations:', annualRows.limit(15));

// Story maps: historic baseline canopy and canopy-loss pixels (2015–25).
Map.setCenter(8.5, 9.1, 6);
Map.setOptions('SATELLITE');
Map.addLayer(baseline.selfMask().clip(states.geometry()),
  {palette:['#1b5e20']}, 'Historic canopy >=30% in 2000', false);
var lossPeriod = baseline.and(lossyear.gte(15)).and(lossyear.lte(25));
Map.addLayer(lossPeriod.selfMask().clip(states.geometry()),
  {palette:['#dc3f3f']}, 'Measured gross canopy loss 2015–2025', true);
Map.addLayer(zones.style({
  color:'#ffffff', fillColor:'00000000', width:2
}), {}, 'Six geopolitical zones', true);

// Storytelling dashboard: actual figures are evaluated by Earth Engine,
// not invented in the script. Values only appear once computations finish.
var title = ui.Label('Where did Nigeria lose tree cover?', {
  fontSize:'19px', fontWeight:'bold', color:'#173d2a',
  margin:'0 0 7px 0'
});
var introduction = ui.Label(
  'A satellite-based comparison of six geopolitical zones, 2015–2025. ' +
  'Red pixels indicate mapped gross canopy loss. ' +
  'Use the charts below to compare regions and years.',
  {fontSize:'12px', color:'#374151', whiteSpace:'pre-wrap'}
);
var disclaimer = ui.Label(
  'NOTE: The reliable annual loss series currently ends in 2025. ' +
  'The separate 2026 imagery is provisional, not a complete annual loss estimate. ' +
  'The 30% canopy threshold refers to year 2000.',
  {fontSize:'11px', color:'#8a5312', whiteSpace:'pre-wrap'}
);
var selector = ui.Select({
  items:['All Nigeria'].concat(zoneNames),
  value:'All Nigeria',
  onChange:function(value) {
    if (value === 'All Nigeria') Map.setCenter(8.5, 9.1, 6);
    else Map.centerObject(zones.filter(ee.Filter.eq('zone', value)), 7);
  }
});
var rankingChart = ui.Chart.feature.byFeature({
  features: totals.sort('gross_loss_km2_2015_2025', false),
  xProperty: 'zone',
  yProperties: ['gross_loss_km2_2015_2025']
}).setChartType('BarChart').setOptions({
  title:'2015–2025 gross canopy loss by zone',
  legend:{position:'none'},
  colors:['#bd3e3a'],
  hAxis:{title:'Area mapped as lost (km²)'},
  vAxis:{title:'Geopolitical zone'},
  height:270,
  chartArea:{left:108,right:15,top:35,bottom:55}
});
var annualChart = ui.Chart.feature.groups({
  features:annualRows,
  xProperty:'year',
  yProperty:'gross_loss_km2',
  seriesProperty:'zone'
}).setChartType('LineChart').setOptions({
  title:'Annual mapped loss: which years were worst?',
  hAxis:{title:'Year',format:'####'},
  vAxis:{title:'Area mapped as lost (km²)',minValue:0},
  lineWidth:2, pointSize:3,
  height:265,
  chartArea:{left:65,right:10,top:40,bottom:70},
  legend:{position:'bottom',textStyle:{fontSize:10}}
});
var normalizedChart = ui.Chart.feature.byFeature({
  features:totals.sort('gross_loss_km2_per_1000_km2_zone', false),
  xProperty:'zone',
  yProperties:['gross_loss_km2_per_1000_km2_zone']
}).setChartType('BarChart').setOptions({
  title:'Zone-size adjusted loss (2015–2025)',
  legend:{position:'none'},
  colors:['#357c69'],
  hAxis:{title:'Lost km² per 1,000 km² of zone'},
  vAxis:{title:'Geopolitical zone'},
  height:260,
  chartArea:{left:108,right:15,top:35,bottom:55}
});
var panel = ui.Panel({
  widgets:[
    title, introduction,
    ui.Label('Explore a zone', {fontWeight:'bold',margin:'9px 0 3px 0'}),
    selector,
    ui.Label('1. Which zones lost the most?',{fontWeight:'bold'}),
    rankingChart,
    ui.Label('2. Was loss concentrated in particular years?',{fontWeight:'bold'}),
    annualChart,
    ui.Label('3. Is the ranking different after accounting for zone size?',{fontWeight:'bold'}),
    normalizedChart,
    disclaimer,
    ui.Label('Sources: Hansen/UMD/Google/USGS/NASA; FAO GAUL 2015.',{
      fontSize:'10px',color:'#6b7280'})
  ],
  style:{
    position:'top-left',width:'440px',maxHeight:'95%',
    padding:'12px',backgroundColor:'#ffffff'
  }
});
Map.add(panel);

// Two downloadable CSV tasks. Start them manually in Earth Engine's Tasks tab.
Export.table.toDrive({
  collection:totals,
  description:'nigeria_zone_gross_tree_loss_2015_2025',
  folder:'NigeriaTreeCoverAtlas',
  fileFormat:'CSV',
  selectors:['zone','gross_loss_km2_2015_2025','zone_area_km2',
             'gross_loss_km2_per_1000_km2_zone']
});
Export.table.toDrive({
  collection:annualRows,
  description:'nigeria_annual_tree_loss_by_zone_2015_2025',
  folder:'NigeriaTreeCoverAtlas',
  fileFormat:'CSV',
  selectors:['zone','year','gross_loss_km2']
});
