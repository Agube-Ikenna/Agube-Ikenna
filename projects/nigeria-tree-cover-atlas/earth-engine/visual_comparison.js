/*
Nigeria Tree Cover Change Atlas: six-zone satellite visualization
2015 vs 2026 (July 1–October 31, both years).
RUN IN: https://code.earthengine.google.com/
IMPORTANT: Pilot map, not validated forest-loss evidence.
*/

var zoneStates = {
  'North Central': ['Benue','Kogi','Kwara','Nasarawa','Niger','Plateau','Federal Capital Territory'],
  'North East': ['Adamawa','Bauchi','Borno','Gombe','Taraba','Yobe'],
  'North West': ['Jigawa','Kaduna','Kano','Katsina','Kebbi','Sokoto','Zamfara'],
  'South East': ['Abia','Anambra','Ebonyi','Enugu','Imo'],
  'South South': ['Akwa Ibom','Bayelsa','Cross River','Delta','Edo','Rivers'],
  'South West': ['Ekiti','Lagos','Ogun','Ondo','Osun','Oyo']
};
var aliases = {'Nassarawa':'Nasarawa', 'Abuja':'Federal Capital Territory',
  'FCT':'Federal Capital Territory', 'Federal Capital Territory (Abuja)':'Federal Capital Territory'};
var lookup = {};
Object.keys(zoneStates).forEach(function(zone) {
  zoneStates[zone].forEach(function(state){ lookup[state] = zone; });
});
Object.keys(aliases).forEach(function(alias){ lookup[alias] = lookup[aliases[alias]]; });
var dictionary = ee.Dictionary(lookup);
var states = ee.FeatureCollection('FAO/GAUL/2015/level1')
  .filter(ee.Filter.eq('ADM0_NAME','Nigeria'))
  .map(function(feature){
    var name = ee.String(feature.get('ADM1_NAME'));
    return feature.set('zone', ee.Algorithms.If(dictionary.contains(name),
      dictionary.get(name), 'UNMATCHED'));
  });
print('Boundary check: expected 37 administrative polygons, found:', states.size());
print('STOP if unmatched state names are present:',
  states.filter(ee.Filter.eq('zone','UNMATCHED')).aggregate_array('ADM1_NAME'));
var zoneNames = Object.keys(zoneStates);
var zones = ee.FeatureCollection(zoneNames.map(function(zone){
  var subset = states.filter(ee.Filter.eq('zone',zone));
  return ee.Feature(subset.geometry(), {zone:zone, number_of_states:subset.size()});
}));
print('Zone counts:', zones.aggregate_array('number_of_states'));
var nigeria = states.geometry();
var date15 = ['2015-07-01','2015-11-01'];
var date26 = ['2026-07-01','2026-11-01'];

// Dynamic World: per-pixel class probability from Sentinel-2 scenes.
var dw = ee.ImageCollection('GOOGLE/DYNAMICWORLD/V1').filterBounds(nigeria);
function treeComposite(window) {
  var collection = dw.filterDate(window[0],window[1]).select('trees');
  return {p:collection.mean(),n:collection.count(), scenes:collection.size()};
}
var a = treeComposite(date15);
var b = treeComposite(date26);
print('Dynamic World 2015 scenes (not cloud-free observation count):',a.scenes);
print('Dynamic World 2026 scenes (not cloud-free observation count):',b.scenes);
var common = a.n.gte(2).and(b.n.gte(2));
var t15 = a.p.gte(0.5);
var t26 = b.p.gte(0.5);
var lost = t15.and(t26.not());
var gained = t15.not().and(t26);
var stable = t15.and(t26);
var change = ee.Image(0).where(stable,1).where(lost,2)
  .where(gained,3).updateMask(common).clip(nigeria);

// Comparable Landsat 8 true-colour optical imagery for both dates.
function landsatComposite(window) {
  return ee.ImageCollection('LANDSAT/LC08/C02/T1_L2')
    .filterBounds(nigeria).filterDate(window[0],window[1]).map(function(im){
      var clear = im.select('QA_PIXEL').bitwiseAnd(parseInt('11111',2)).eq(0)
        .and(im.select('QA_RADSAT').eq(0));
      var optical = im.select('SR_B.').multiply(0.0000275).add(-0.2);
      return im.addBands(optical,null,true).updateMask(clear);
    }).median().clip(nigeria);
}
var rgb = {bands:['SR_B4','SR_B3','SR_B2'],min:0.02,max:0.3,gamma:1.15};
Map.setCenter(8.5,9.1,6);
Map.addLayer(landsatComposite(date15), rgb, '2015 satellite true colour', false);
Map.addLayer(landsatComposite(date26), rgb, '2026 satellite true colour', false);
Map.addLayer(t15.updateMask(common).selfMask().clip(nigeria),
  {palette:['#286c42']}, '2015 trees (common-valid footprint)', false);
Map.addLayer(t26.updateMask(common).selfMask().clip(nigeria),
  {palette:['#50b17b']}, '2026 trees (common-valid footprint)', false);
Map.addLayer(change.updateMask(change.gt(0)),
  {min:1,max:3,palette:['#286c42','#d64e4b','#4686b8']},
  'Change: stable / apparent loss / apparent gain', true);
Map.addLayer(zones.style({color:'white',fillColor:'00000000',width:2}),
  {},'Six geopolitical zones',true);
Map.addLayer(common.selfMask().clip(nigeria),
  {palette:['#ffffcc']},'Pixels observed in BOTH years',false);
var selector = ui.Select({
  items:['All zones'].concat(zoneNames), value:'All zones',
  onChange:function(zone) {
    if(zone === 'All zones') Map.setCenter(8.5,9.1,6);
    else Map.centerObject(zones.filter(ee.Filter.eq('zone',zone)),7);
  }
});
var panel = ui.Panel({style:{position:'top-left',width:'310px',padding:'12px'}});
panel.add(ui.Label('Nigeria Tree Cover Atlas 2015–2026',{fontSize:'17px',fontWeight:'bold'}));
panel.add(ui.Label('Choose a zone:'));
panel.add(selector);
panel.add(ui.Label('Green: stable tree | Red: apparent loss | Blue: apparent gain.'));
panel.add(ui.Label('Only common-observed pixels are compared. Sparse 2015 coverage means missing zones cannot support trends. 2026 is provisional.',
  {color:'#a33b2e',fontSize:'11px'}));
Map.add(panel);
