---
title: How other platforms show a project, and what RailsVis can take
kind: reference
audience: engineer
related:
  - viewer/src/app.js
  - lib/rails_vis/collectors/controllers.rb
  - lib/rails_vis/body_scan.rb
---

# How other platforms show a project, and what RailsVis can take

Research note, 2026-11-04. The question: tools on other platforms that present a codebase or project visually, what makes their first screen readable at once, and which of that RailsVis can adopt. Three side questions from the owner: whether a node-based diagram that connects and rearranges fits our design, whether a view can be mapped to a page-flow diagram derived from code, and whether templates and view components deserve a view of their own.

Method: a background agent read primary sources only (official docs, READMEs, package manifests, the jsDelivr package API for sizes) and wrote [the source notes](2026-11-04-visualization-landscape-sources.md), one section per tool with a URL per claim. In parallel, a throwaway spike ran against the Spina acceptance checkout to measure what a page-flow collector would actually find. The interactive deck that presents this is `2026-11-04-visualization-proposals.html` in this folder.

## 1. Where RailsVis stands

| View | Form today | Diagram |
|---|---|---|
| Start here | 7 stat tiles, routes per controller, models per database, reading list | none |
| Request map | Ledger: routes grouped by controller; a row opens filters, models, view, source | none |
| Domain model | Chips, Mermaid `erDiagram` (belongs_to only), one section per model | Mermaid |
| Databases, Boot, Middleware, Entry points, Gems, Documents | Tables and bar charts | none |

Source: `viewer/src/app.js` (`renderStart`, `renderRequests`, `renderDomain`). Mermaid is 5.49 MB of the 5.87 MB viewer (`viewer/vendor/mermaid.min.js`); the spec rejected a second graph library because it "would double the payload" (`docs/superpowers/specs/2026-11-03-rails-onboarding-dashboard-design.md`, decisions table).

`data.json` already holds, per route, the helper stem (`name`), controller, action, engine, redirect and source line; per action, the constants its body touches and its resolved view (`lib/rails_vis/collectors/controllers.rb`, `lib/rails_vis/body_scan.rb`). Nothing links one page to another.

## 2. What recurs across the tools

The agent covered about 45 tools (code explorers, dependency graphs, monorepo graphs, schema viewers, API references, navigation editors, docs sites). Twelve patterns recur; the ones that bear on RailsVis, with the tools that evidence them (URLs in the source notes, Part C):

1. **Entry-point first.** Sourcetrail centres the graph on the selected symbol and shows only its in and out edges; Nx `--focus`; Azimutt "find your starting point, then navigate from it"; Android's Navigation Editor and Xcode storyboards are organised around a start destination.
2. **Counts on the overview, each count a link.** pkg.go.dev's "Known importing packages"; Laravel Pulse's queue card; Sourcetrail's expander counts. RailsVis already does this on Start here.
3. **Colour encodes kind or status, never decoration.** Sourcetrail by symbol kind; Madge by dependency state; cargo-depgraph edge colour by dependency kind; Swagger UI's method badge colours. RailsVis already does this with the four review roles (route, model, database, warning) and the verb pills.
4. **Method badge, monospace path, prose summary** is what makes an endpoint list scannable (Swagger UI, Redoc, Scalar). The Request map has the first two; it has no summary column because nothing in the code yields one.
5. **Click a node, land on code.** Sourcetrail, Nx ("click on any dependency line to find which file(s) created the dependency"), dependency-cruiser `--prefix`, NDepend, Mermaid `click`. RailsVis does this on every row; a diagram node that does the same is the missing piece.
6. **Focus mode with a depth control.** Sourcetrail's depth slider, Nx proximity, code2flow upstream and downstream depth, Backstage `maxDepth`, Azimutt find-path.
7. **Collapse by folder or namespace** is the universal scaling trick: dependency-cruiser `archi`, Nx group-by-folder, rails-erd `cluster`, Mermaid `subgraph` with `@{ view: collapsed }`.
8. **Trim orphans and bundle parallel edges with a count** (Sourcetrail, code2flow, SchemaSpy lists orphan tables separately).
9. **Hover highlights in and out edges, click pins** on an otherwise static SVG (dependency-cruiser `dot-webpage`, NDepend). This gives most of the felt interactivity of a graph library without one.
10. **Two synchronised views of one selection** (NDepend matrix and graph, Sourcetrail graph and code, dbdiagram code and diagram).
11. **Static output that still reads well**: SchemaSpy's HTML report, dependency-cruiser's `dot-webpage`, emerge's self-contained app, Turborepo `--graph html`. RailsVis is in this family.
12. **The page-flow convention**: screens as nodes, actions as labelled arrows, the start marked, a nested flow drawn as one node (Android Navigation Editor; Xcode segues by kind; FigJam and Miro user-flow templates). Blueprints and Blender add: execution flow neutral, data flow coloured by type, inputs left, outputs right.

Why the first screens read instantly, in one sentence each:

- **Nx graph**: one project focused, its neighbours at a chosen depth, everything else absent, with a sidebar to widen.
- **Sourcetrail**: three panes (search, graph, code) that all show the same selected symbol.
- **Laravel Pulse**: a fixed grid of cards, each a count with its worst offenders listed under it.
- **Swagger UI**: one row per operation, a coloured badge first, grouped by tag, collapsed by default.
- **Android Navigation Editor**: destinations as screen previews with arrows between them and a start marked.
- **SchemaSpy**: an entity diagram from foreign keys plus a separate list of anomalies and orphans.

## 3. Examples worth opening

Open source unless marked. Each is the best primary example of a pattern above.

| Tool | Why open it | Source |
|---|---|---|
| Nx `nx graph` (MIT) | Focus, proximity depth, group by folder, trace path, node tooltip to details; built on Cytoscape.js and cytoscape-dagre | https://nx.dev/docs/features/explore-graph |
| Android Studio Navigation Editor | The canonical page-flow node editor: destinations, actions as arrows, nested graphs as one node | https://developer.android.com/guide/navigation/design/editor |
| Sourcetrail (GPL-3.0, archived) | Entry-point-first graph with bundled edges, member counts, depth slider | https://github.com/CoatiSoftware/Sourcetrail/blob/master/DOCUMENTATION.md |
| dependency-cruiser `dot-webpage` (MIT) | Hover-highlight and click-to-pin on a static SVG; collapse by folder; links to source | https://github.com/sverweij/dependency-cruiser/blob/main/doc/cli.md |
| SchemaSpy (LGPL-3.0) | Static HTML schema report with implied relations and Rails naming conventions, anomalies listed apart | https://schemaspy.readthedocs.io/en/latest/features.html |
| Azimutt (MIT) | Start from one table and walk in and out relations; find-path between two tables | https://azimutt.app/features |
| Swagger UI (Apache-2.0) | Method badges, tag grouping, collapsed list by default; the badge colours are in its SCSS variables | https://github.com/swagger-api/swagger-ui |
| Laravel Pulse (MIT) | First screen as a grid of count cards with the worst offenders under each | https://laravel.com/docs/12.x/pulse |
| Backstage catalog-graph (Apache-2.0) | Entity relations graph with `maxDepth`, `unidirectional`, `onNodeClick`, drawn with dagre and d3 | https://github.com/backstage/backstage/blob/master/plugins/catalog-graph/README.md |
| emerge (MIT) | Self-contained static web app; force-directed graph on canvas with cluster hulls and a heat metric | https://github.com/glato/emerge |
| Storybook hierarchy | A catalogue tree from `/`-separated titles, single children hoisted; the model for a components inventory | https://storybook.js.org/docs/writing-stories/naming-components-and-hierarchy |
| Starlight and Docusaurus card grids | An entry page as a grid of cards that each open a section; the model for Start here as a map | https://starlight.astro.build/components/cards/ |

Commercial references read for the pattern only: NDepend (dependency matrix synchronised with a graph), CodeScene (hotspot circle packing), GoJS. Not verified from a primary page, so not relied on: CodeSee, Understand, Structure101, Lattix detail (source notes, Part D).

## 4. Can a node-based diagram that rearranges fit our design?

Yes, at a cost that depends on what "rearranges" has to mean. The constraint is a single file, no build, no network at view time, and a payload already dominated by Mermaid.

Facts from the library comparison (sizes are uncompressed bytes from jsDelivr on 2026-11-04; source notes, Part B):

| Option | Adds | Gives | Lacks |
|---|---|---|---|
| Mermaid flowchart, already vendored | 0 KB | Layered layout (ELK is bundled and default since Mermaid 12), `click` bindings for source links, `subgraph` with `@{ view: collapsed }` for grouping | Dragging nodes; any neighbourhood focus |
| Mermaid plus our own SVG post-processing | about 60 lines of script | Hover-highlight in and out edges, click to pin, dim the rest (pattern 9), on the SVG the viewer already wraps for zoom and pan | Dragging |
| Own spring layout, as in the deck demo | about 30 lines of script | Draggable nodes, neighbour highlight, click to source | Layered ranks; it reads as a cloud, not a flow |
| d3-force, d3-drag, d3-zoom, d3-selection (ISC) | about 35 KB | A tested force layout with drag and zoom | Layered layout, compound nodes |
| Cytoscape.js plus cytoscape-dagre (MIT) | about 470 KB, 8% of the current payload | Drag, layered layout, compound (grouped) nodes, the stack Nx graph ships | A second renderer beside Mermaid, two visual languages to keep aligned |
| vis-network, G6, ELK.js alone, Sigma.js | 1.3 to 1.6 MB each | More than we need | Size |
| React Flow, GoJS, JointJS | React required; commercial; MPL core with layouts in the paid tier | | Unsuitable for a build-less OSS gem |

Recommendation: draw the page flow with the Mermaid we already ship (layered, left to right, grouped by controller namespace with collapsible subgraphs, every node a `click` to its template) and add the hover-highlight and click-to-pin post-processing to the existing diagram viewer. That gives patterns 5, 7 and 9 at zero payload and keeps one visual language across the entity diagram and the flow. Hand-rearranging nodes is the one thing this cannot do. If, after using it, rearranging turns out to matter, Cytoscape.js plus cytoscape-dagre is the proven stack for a static page and costs 8% of the payload; d3-force is cheaper but gives a cloud, which is the wrong shape for a flow.

The deck's demo deliberately uses the own-layout option so the idea can be judged by handling it; it is a sketch, not the proposed implementation.

## 5. Can a view be mapped to a page-flow diagram from the code?

Yes, for the links Rails conventions make explicit. Measured on Spina (174 routes, 31 controllers, engine views under the engine root):

| Measure | Count |
|---|---|
| GET routes with an `.html.erb` template (page nodes) | 37 |
| Page to page links (a GET helper in the page or its partials) | 20 |
| Page to write action (`form_with`, `button_to` to POST, PATCH, DELETE) | 14 |
| Redirect landings (`redirect_to` in a write action) | 16 |
| Pages with no inbound link in a template | 22 |

How: compile each template with `ActionView::Template::Handlers::ERB::Erubi`, parse the Ruby with Prism, keep every `CallNode` named `*_path` or `*_url` whose stem is a `routes[].name`; attribute `render "x"` and `render partial:` one level so a partial's links count for the page that renders it; walk `redirect_to` arguments in controller bodies for landing edges. Plain `Erubi::Engine` is not enough: it emits invalid Ruby for `<%= link_to ... do %>` block helpers, Prism reports two errors and finds no calls, which is why the first spike found almost nothing.

Why 22 orphans: Spina's admin navigation lives in `app/views/spina/admin/shared/_navigation.html.erb` (10 helper calls, rendered from the layout) and in Ruby view components under `app/components` (10 files call `*_path`). Neither a layout nor a component is attributed to a page by the spike. A collector would treat the layout's links as a global-navigation hub (drawn once, not as 37 edges) and scan `app/components/**` with the same Prism pass.

Dependencies needed: none. `action_view` and `prism` are already in the bundle (`Gemfile.lock`).

Prerequisite defect: `Collectors::Controllers#view` globs `app/views` under the app root (`lib/rails_vis/collectors/controllers.rb:120`), so an engine like Spina resolves 0 of 391 views. Page flow needs templates resolved through the controller's own view paths (`_view_paths` or `lookup_context`), which is the reflect-not-parse rule (`docs/decisions/0001-reflect-not-parse.md`) applied to views.

What the code yields per page, so the node can say more than its path: verb, template, filters that apply, models referenced, redirect target, and the jobs and mailers the action names (constants ending in `Job` or `Mailer` are already in `BodyScan#constants`; the controllers collector keeps only model names today). A sentence about what the page is for is authored, never derived; the `related:` front matter already lets a document attach itself to a controller file.

Deferred, because the code does not state it: links built from strings or interpolated paths, Turbo or JavaScript navigation, Inertia client-side `<Link href>` (a TSX scan under `pages_dir` could come later).

## 6. Templates and view components

Worth a view, and page flow depends on half of it. What the booted app can enumerate:

| Kind | Found how | Row shows |
|---|---|---|
| Template | The controller's view paths, per action and format | Controller, action, partials rendered, pages linked |
| Partial | `render` calls resolved one level | Who renders it, how many times |
| Layout | `app/views/layouts` plus `layout` declarations on controllers | Controllers that use it; its links, drawn once as the navigation hub |
| View component | Descendants of `ViewComponent::Base` when the gem is loaded (the same reflection the models collector uses) | Source line, who renders it, links it emits |
| Inertia page | Already resolved under `pages_dir` | The action that renders it |

Storybook's model is the useful one: a tree from the folder path, single children hoisted, a count per folder, each leaf a source line.

## 7. Adaptations proposed

| Gap | Pattern that answers it | Proposal | New data | Viewer |
|---|---|---|---|---|
| Start here counts but does not orient | 1, 2, Starlight and Pulse first screens | **A. Start here as a map**: entry points first (root page, sign-in page when found, jobs, recurring, mailers, channels), then the busiest paths, then small thumbnails of the two diagrams | none; all collected already | yes |
| No view shows page-to-page movement | 12, 5, 9 | **B. Page flow**: Mermaid flowchart, left to right, grouped by controller namespace, click to template, hover and pin | a pages-and-links collector (section 5) | yes |
| Templates and components are invisible unless an action resolves one | Storybook hierarchy, 7 | **C. Templates and components inventory** (section 6) | a views collector; the view-path fix | yes |
| The entity diagram is all or nothing | 6, 9 | **D. Neighbourhood focus** on the domain diagram: pick a model, one or two hops, dim the rest | none | yes |

D is viewer-only and small. B is the one the research argues for most strongly and the one that needs the view-path fix first. A changes the first screen and is mostly re-arrangement of existing data.

Expected outcome, in the spec's terms (a newcomer answers from the dashboard alone): "how do I reach that screen", "what happens after I submit", and "where is this partial used" join the questions the dashboard already answers. Every node stays a file and line at a commit; the output stays one static file; a failing node stays a warning.

Why this suits Rails review: named routes are the link language of idiomatic Rails, so one Prism pass over compiled templates resolves most edges without heuristics; the app is booted, so engines, custom inflections and mounted routes resolve as Rails resolves them; and a Rails review reads route, action, redirect and template in that order, which is the page-flow view drawn once for the whole app.

## 8. Open decisions

1. Order: B first (with the view-path fix), then A and C, or A first because it changes the first screen.
2. Graph engine: Mermaid plus post-processing (recommended above), or Cytoscape.js for dragging from the start.
3. Scope of links in the first cut: templates and partials only, or also layouts and view components.
4. Inertia: defer the TSX scan, or include a minimal `<Link href>` pass so Inertia apps are not blank.

## Assumptions and weaknesses

ASSUMPTIONS: the "latest" npm tag on 2026-11-04 is the version the sizes describe, and sizes are uncompressed bytes, not gzip; Spina is representative of engine-heavy apps but not of plain apps, where the orphan count should be far lower; the owner wants the Ink theme kept, so no visual direction was researched.

WEAKNESSES: the orphan figure (22 of 37) comes from a spike that ignores layouts and components, so the real collector's coverage is unmeasured; the recommendation to stay on Mermaid rests on Mermaid 12's `click` and `view: collapsed` working under the viewer's security level, which was read from the docs and not yet exercised in our viewer; several commercial tools could not be read from primary pages and are cited for the pattern only.
