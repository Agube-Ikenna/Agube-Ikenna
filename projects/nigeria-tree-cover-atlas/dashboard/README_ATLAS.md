# Atlas dashboard

The authored atlas entry point is `src/content/dashboard/DashboardContent.jsx`. Data are supplied by `src/data.json`; `R/Build_Dashboard_Data.R` refreshes the reviewed measurements and provenance from committed analytical exports. The stable app identity is preserved.

The repository includes a ready-to-open portable build at `../dashboard-preview/Nigeria_Tree_Cover_Atlas.html`. Download it before opening; GitHub does not render HTML in its file viewer.

On this Codex desktop, build with the installed Data plugin:

```sh
node /path/to/data-analytics/scripts/data-app.mjs build --project-dir /path/to/atlas/dashboard --separate-data
node /path/to/data-analytics/scripts/data-app.mjs export-offline --project-dir /path/to/atlas/dashboard --output /path/to/atlas/dashboard/.data-app-offline/exports/Nigeria_Tree_Cover_Atlas.html
```

Outside Codex, the source project supplies a conventional Vite build (`npm install`, then `npm run build`) using the pinned package lock. Keep the integrity verifier and shared runtime unchanged. Runtime and authoring dependencies are distinct from the R analytical workflow. To preview a split `dist` build, serve its directory over HTTP so its snapshot sidecar loads.

Static figures and data exports are frozen research outputs. Changing a dashboard view does not rerun Earth Engine, modify the analytical exports or validate the classifications.
