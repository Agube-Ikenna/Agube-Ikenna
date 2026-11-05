import React, { useState } from 'react';
import { EvidenceChart, DataComponent, DataTable, Section, useDataApp, useDashboardTabs, Filters, useSectionFilters, SortableRegion, SortableItem } from '../../data-app-public.jsx';
import satellite from '../assets/01_satellite_comparison.png';
import hotspots from '../assets/03_candidate_hotspots.png';
import geography from '../assets/zones.json';
import stateMap from '../assets/03_state_loss_concentrations.png';
import './atlas.css';
const tabs=[{id:'dashboard',label:'Satellite comparison'},{id:'hansen',label:'Annual gross loss'},{id:'coverage',label:'Coverage & sensitivity'}];
const number=(x,d=1)=>x==null?'No paired data':Number(x).toLocaleString('en-GB',{maximumFractionDigits:d});
function Map({rows,field,label}) {
 const [selected,setSelected]=useState(null);
 const geoms=geography.features;
 const all=geoms.flatMap(f=>f.geometry.type==='MultiPolygon'?f.geometry.coordinates.flat(2):f.geometry.coordinates.flat());
 const xs=all.map(c=>c[0]),ys=all.map(c=>c[1]);const minX=Math.min(...xs),maxY=Math.max(...ys),w=Math.max(...xs)-minX,h=maxY-Math.min(...ys);
 const byZone=Object.fromEntries(rows.map(r=>[r.zone??r.region,r]));
 const max=Math.max(...rows.map(r=>r[field]??0),1);
 const path=f=>{const polygons=f.geometry.type==='MultiPolygon'?f.geometry.coordinates:[f.geometry.coordinates];return polygons.map(poly=>poly.map(ring=>ring.map((c,i)=>`${i?'L':'M'}${(c[0]-minX)/w*600},${(maxY-c[1])/w*600}`).join(' ')+'Z').join(' ')).join(' ');};
 return <div className="atlas-map" data-reviewed-rows="true"><svg viewBox={`-8 -8 616 ${h/w*600+16}`} role="group" aria-label={label}>
 {geoms.map(f=>{const r=byZone[f.properties.zone],v=r?.[field];return <path key={f.properties.zone} d={path(f)} fill={v==null?'#c2c5c6':`hsl(${180-v/max*160} 55% ${76-v/max*34}%)`} stroke="var(--text)" strokeWidth="0.9" strokeDasharray="3 2" tabIndex="0" role="button" aria-label={`${f.properties.zone}: ${number(v)} percent`} onPointerEnter={()=>setSelected({name:f.properties.zone,...r})} onPointerLeave={()=>setSelected(null)} onFocus={()=>setSelected({name:f.properties.zone,...r})} onBlur={()=>setSelected(null)} />;})}
 </svg><div className="atlas-tooltip" role="status">{selected?<><strong>{selected.name}</strong><span>{label}: {number(selected[field],2)}%</span>{selected.common_coverage_pct!=null&&<span>Paired coverage: {number(selected.common_coverage_pct,2)}% of zone</span>}<span>2015–2025</span></>:<span>Point to or focus a zone to inspect its values.</span>}</div><div className="atlas-legend"><span>Lower</span><i/><span>Higher</span><span className="atlas-no-data">Grey: no paired data</span></div></div>;
}
export function DashboardContent(){
 const {reviewedRows}=useDataApp();const {activeTabId}=useDashboardTabs(tabs);
 const z=reviewedRows('dw_zones');
 const annual=reviewedRows('hansen_annual');const totals=reviewedRows('hansen_zones');
 const audit=reviewedRows('sensitivity');
 const auditScope=useSectionFilters([{id:'sample_zone',label:'Zone',field:'zone',defaultValue:'North Central',queryIds:['sensitivity']}],{},{id:'sample-sensitivity'});
 const scopedAudit=auditScope.componentProps('sensitivity',['zone','tree_probability','minimum_observations']);
 const auditChartRows=scopedAudit.displayRows.map(r=>({...r,'Sample change (%)':r.apparent_change_pct,'Predictions':r.zone+' · >= '+r.minimum_observations}));
 const zoneRows=z.map(r=>({...r,'Apparent change (%)':r.gross_change_pct_common,'Paired coverage (%)':r.common_coverage_pct}));
 const hansenRows=totals.map(r=>({...r,'Loss (km²)':r.total_loss_km2,'Loss / zone area (%)':r.loss_pct_of_region_area}));
 const spec=(type,x,y)=>({type,x,y,fields:[y],showXAxisLabel:false,valueDecimals:2,stackable:false});
 if(activeTabId==='hansen')return <article className="atlas">
 <p className="atlas-note" data-editable-id="hansen-definition">Annual mapped gross tree-cover loss, 2015–2025 inclusive (11 years); canopy cover in 2000 ≥30%. This series does not estimate gain or net change.</p>
 {annual.length?<><Section id="annual-section" title="Annual gross loss">
 <EvidenceChart id="annual-loss" queryId="hansen_annual" title="Nigeria annual mapped loss (km²)" rows={annual.map(r=>({...r,year:String(r.year),'Mapped loss (km²)':r.loss_km2}))} sourceRows={annual} spec={{...spec('line','year','Mapped loss (km²)'),yLabel:'Mapped loss (km²)'}} height={340} variant="card"/>
 </Section><Section id="ranking-section" title="Six-zone comparison" columns={2}>
 <EvidenceChart id="absolute-loss" queryId="hansen_zones" title="Total mapped loss (km²)" rows={[...hansenRows].sort((a,b)=>b.total_loss_km2-a.total_loss_km2)} sourceRows={totals} spec={spec('horizontalBar','region','Loss (km²)')} height={320} variant="card"/>
 <EvidenceChart id="normalized-loss" queryId="hansen_zones" title="Mapped loss / geographic zone area (%)" rows={[...hansenRows].sort((a,b)=>b.loss_pct_of_region_area-a.loss_pct_of_region_area)} sourceRows={totals} spec={spec('horizontalBar','region','Loss / zone area (%)')} height={320} variant="card"/>
 </Section><Section id="state-section" title="State and FCT concentrations">
 <DataComponent id="state-loss-map" queryId="hansen_states" title="Mapped loss / state geographic area (%)" kind="custom" displayRows={reviewedRows('hansen_states')} variant="card"><img className="atlas-hotspots" src={stateMap} alt="Nigeria state and FCT mapped gross-loss concentrations with percent labels and legend"/></DataComponent>
 <DataComponent id="state-details" queryId="hansen_states" title="State loss measurements" kind="table" displayRows={reviewedRows('hansen_states')} variant="card"><DataTable columns={[{field:'region',label:'State / FCT'},{field:'total_loss_km2',label:'Mapped loss (km²)'},{field:'loss_pct_of_state_area',label:'Loss / state area (%)',renderCell:v=>v>0&&v<.01?'<0.01':number(v,2)}]} rows={reviewedRows('hansen_states')} searchable/></DataComponent>
 </Section></>:<p>Local annual area extraction is running. No interim measurements are displayed.</p>}
 <p className="atlas-note">Size adjustment controls geographic area only. It does not control for baseline tree cover. Mapped loss includes stand-replacement disturbances and is not automatically permanent deforestation.</p>
 </article>;
 if(activeTabId==='coverage')return <article className="atlas"><Section id="coverage-section" title="Observations supporting the endpoint comparison">
 <EvidenceChart id="paired-coverage" queryId="dw_zones" title="Paired coverage by zone (%)" rows={zoneRows} sourceRows={z} spec={{...spec('horizontalBar','zone','Paired coverage (%)'),yDomain:[0,100]}} height={320} variant="card"/>
 <DataComponent id="coverage-values" title="Zone observation coverage" queryId="dw_zones" kind="table" displayRows={z} variant="card"><DataTable rows={z} columns={[{field:'zone',label:'Zone'},{field:'common_coverage_pct',label:'Paired coverage (%)'},{field:'common_km2',label:'Paired area (km²)'},{field:'gross_change_pct_common',label:'Apparent change (%)'}]}/></DataComponent>
 </Section><Section id="sensitivity-section" title="Classification sensitivity" filters={<Filters {...auditScope.filterProps}/>}>
 {auditChartRows.length>0 && auditChartRows.every(r=>r.apparent_change_pct==null) && <p className="atlas-note">No paired sample observations for this selection; change is undefined.</p>}
 <EvidenceChart id="sensitivity-lines" queryId="sensitivity" title="Sample change by mean tree-probability threshold" {...scopedAudit} rows={auditChartRows} spec={{type:'line',x:'tree_probability',y:'Sample change (%)',series:'Predictions',stackable:false,xLabel:'Mean tree probability',valueDecimals:2}} height={300} variant="card"/>
 <p className="atlas-note" data-editable-id="sample-method">200 fixed random points per zone at 10 m. Mean tree probability thresholds 0.4, 0.5 and 0.6; minimum predictions 1, 2 and 3. This sample diagnoses threshold sensitivity; it is not an accuracy validation or a national area estimate.</p>
 {audit.length?<DataComponent id="sensitivity-table" title="Nine sample-based scenarios" queryId="sensitivity" kind="table" {...scopedAudit} variant="card"><DataTable rows={scopedAudit.displayRows} columns={[{field:'zone',label:'Zone'},{field:'tree_probability',label:'Tree threshold'},{field:'minimum_observations',label:'Min predictions'},{field:'paired_points',label:'Paired points'},{field:'apparent_change_pct',label:'Sample change (%)'}]} searchable/></DataComponent>:<p>Sample retrieval is in progress.</p>}
 </Section></article>;
 return <article className="atlas"><p className="atlas-note" data-editable-id="endpoint-definition">July–October 2015 versus 2025. Apparent change = loss + gain within paired observations. Missing areas are not extrapolated.</p>
 <SortableRegion id="atlas-satellite-layout" variant="stack" label="Satellite figures"><SortableItem id="satellite-rgb" label="Satellite comparison"><DataComponent id="satellite-rgb" queryId="dw_zones" title="2015 and 2025 satellite comparison" kind="custom" displayRows={z} variant="card"><img className="atlas-satellite" src={satellite} alt="Side-by-side Nigeria satellite imagery for 2015 and 2025, tree overlay and coverage legend"/><p className="atlas-note">Landsat RGB is visual context. Grey indicates insufficient paired tree predictions; white indicates masked satellite pixels. Green is a tree-class overlay, not necessarily intact natural forest.</p></DataComponent></SortableItem></SortableRegion>
 <Section id="endpoint-regions" title="Zone change and observation coverage" columns={2}>
 <DataComponent id="endpoint-zone-map" queryId="dw_zones" title="Apparent endpoint change (%)" kind="custom" displayRows={z} variant="card"><Map rows={z} field="gross_change_pct_common" label="Apparent change"/></DataComponent>
 <EvidenceChart id="endpoint-change" queryId="dw_zones" title="Change within paired area (%)" rows={zoneRows} sourceRows={z} spec={spec('horizontalBar','zone','Apparent change (%)')} height={360} variant="card"/>
 </Section><p className="atlas-note atlas-important">Paired coverage: South West 2.4%, South South 0.28%, South East 0%. Change rates in these footprints cannot represent their entire zones.</p>
 <Section id="hotspot-section" title="Candidate loss hotspots"><DataComponent id="candidate-hotspot-map" queryId="dw_hotspots" title="Exploratory 10 km loss clusters" kind="custom" displayRows={reviewedRows('dw_hotspots')} variant="card"><img className="atlas-hotspots" src={hotspots} alt="Candidate loss hotspot clusters, eligible loss rates and excluded cells with legends"/><p className="atlas-note">Top decile of positive eligible loss rates; ≥50% paired coverage and ≥1 km² baseline tree area. Adjacent high-loss cells are exploratory clusters, not statistically significant hotspots. Land-use overlap does not establish causes.</p></DataComponent></Section></article>;
}
