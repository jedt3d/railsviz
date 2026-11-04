# RailsVis: Page flow view, design

Date: 2026-11-04. Status: draft for the owner's approval. Research behind it:
`docs/research/2026-11-04-visualization-landscape.md` (sections 4 and 5) and the
deck `docs/research/2026-11-04-visualization-proposals.html`.

## 1. Intent

A newcomer opens the dashboard and asks "how do I reach that screen?" and "what
happens after I submit this form?". Today the Request map answers "which
controller answers this URL" and nothing answers movement between pages. The
page flow view draws the app's pages as nodes and the links Rails conventions
make explicit as arrows, every node and every arrow still a file and line at a
commit.

The owner chose this as the first of the four proposals in the research note
(page flow, then Start here as a map, then the templates inventory, then
neighbourhood focus on the domain diagram).

## 2. Objective, goals, non-goals, anti-goals

### Objective

From the dashboard alone, a reader can follow a page to the pages it links to,
back to the pages that link to it, and through a form to the page it lands on.

### Goals

- G1. A `pages` section in `data.json` with, per controller action: its
  template, layout, the partials and view components it renders, and the links
  (route helper calls) found in them; plus the redirect targets of every action.
- G2. A "Page flow" view: a Mermaid flowchart of pages and links, grouped by
  controller namespace, with click-to-select (neighbours lit, the rest dimmed),
  a detail panel for the selected page, and a ledger of pages under it.
- G3. Templates resolve through the controller's own view paths, so engines
  (Spina: 391 actions, 0 views resolved today) get templates, and page flow
  works on them.
- G4. Zero new runtime dependencies in the host app and zero bytes added to the
  viewer's vendored libraries.
- G5. Links in layouts are shown as the app's navigation, not drawn as one edge
  per page.
- G6. Everything that is not derivable from code is left out, with a warning
  where the collector had to give up on a thing it found.

### Non-goals

- No runtime tracing, no analytics: "busiest" and "visited" never appear.
- No dragging of nodes by hand (the research recommends staying on Mermaid; a
  graph library is a later decision if use shows rearranging matters).
- No Inertia client-side links (`<Link href>` in TSX) in this wave; Inertia
  pages appear as nodes with no outbound links and a note saying why.
- No links built from strings, interpolated paths, `url_for` hashes,
  `polymorphic_path`, or a record in place of a path: `link_to @record`,
  `form_with model: @record`, `redirect_to @record`. These are the scaffold
  defaults, so in a plain app most forms draw to a `verb action` stub and most
  create redirects are absent; the detail panel says "target is a record, not
  a named route" for such a form or redirect so the gap is visible. Turbo and
  JavaScript navigation are likewise absent. Decided with the owner, section 9.
- No prose about what a page is for. The `related:` front matter of a document
  already attaches a document to a controller file; the detail panel lists
  those.

### Anti-goals

- Drawing every page of a large app at once. Mastodon-sized apps must still
  open to a readable diagram.
- A second visual language. The page flow and the entity diagram share the
  Mermaid theme, the diagram viewer (zoom, pan, fit, full screen) and the Ink
  tokens.
- Guessing a link's target when the stem is ambiguous.

## 3. Constraints

- Rails 8.0 and 8.1, the gem's supported range. `action_view` and `prism` are
  already in the bundle; `ActionView::Template::Handlers::ERB::Erubi` compiles
  templates the way Rails does (plain `Erubi::Engine` emits invalid Ruby for
  `<%= link_to ... do %>` block helpers; the spike proved this).
- The viewer stays one static file; Mermaid 12.2.0 is vendored and runs at
  `securityLevel: "strict"`, which disables Mermaid's own `click` bindings.
  Node behaviour is attached by our script to the rendered SVG, the way
  `viewerize` already wraps every diagram.
- `data.json` carries only collector output; no config or ENV values.
- Source nodes keep `name`, `path`, `line`, `url` as everywhere else
  (`RailsVis::Source.node`). Gem code is never linked by repository path.
- A failing node becomes a warning, never an abort (`Dump#run`).

## 4. Data collection

### 4.1 Prerequisite: templates through view paths

`Collectors::Controllers#view` today globs `app/views/<controller_path>/<action>.*`
under the app root (`lib/rails_vis/collectors/controllers.rb:120`). Replace it
with resolution through the class's view paths (`klass._view_paths`, wrapped in
an `ActionView::LookupContext`, formats `[:html]` first, then any), so the
template comes from wherever Rails would read it: the app, an engine, a gem
that ships views. The returned node is a source node like any other; a template
outside app code (a gem's view) is kept with `url: nil`, as middleware source
rows already do. The layout the action would render is resolved the same way
and recorded by name. Inertia resolution under `pages_dir` is unchanged.

The existing `view` field on actions keeps its shape (`kind`, `path`, `url`) so
schema consumers of version 2 keep working.

### 4.2 The pages collector

`Collectors::Pages.new(repo:, routes:, controllers:)` runs after the
controllers collector and returns `{ "pages" => [...], "layouts" => [...],
"warnings" => [...] }`.

**What it reads.** For every controller action that has a template (from 4.1),
the template file, the partials it renders (resolved recursively with a visited
set, by `render "name"` / `render partial: "name"` / `render "dir/name"` with a
string literal; relative names resolve against the template's own folder, then
the controller's view prefixes (`_prefixes`, as Rails does)), and the view components it renders
(`render SomeComponent.new(...)` with a literal constant; the component's own
template is the sidecar file next to its class, or its `call` method). For every
action, with or without a template, the action body for `redirect_to`.

**How it reads.** One Prism pass per file, cached per dump. A template is
compiled to Ruby by the handler Rails registered for its extension
(`ActionView::Template.registered_template_handler(ext)`, called the way
`ActionView::Template#compile` calls it), so ERB, Haml and Slim all read the
way Rails reads them; Mastodon, an acceptance target, is Haml. A handler that
raises, or an extension with no handler, yields one warning naming the file
and the collector moves on. Ruby files are parsed as they are. From the tree it keeps every
`CallNode` whose name matches `/\A(\w+)_(path|url)\z/`, with the call's line.
Each call also records its receiver: none, `main_app`, or a mounted engine's
route proxy (`spina.admin_users_path`; the proxy name is the engine's
`engine_name`). The link's `engine` is set from it: the proxy's engine class
name, `null` for `main_app`, and for a bare call the engine whose root contains
the file (`Rails::Engine.subclasses` roots, longest prefix), or `null` for app
files. The viewer joins a link to a route on (`engine`, `stem`), matching
`routes[].engine` and `routes[].name`, so an app route and an engine route that
share a name (`root` is the usual one) never cross. A call with any other
receiver, or a stem that is not a route name in that engine (asset helpers,
`thumbnail_url`, helpers of an unmounted engine), is dropped; nothing is
guessed.

**Form or link.** A helper call is a form when it is an argument (at any depth)
of `form_with`, `form_for`, `form_tag` or `button_to`, or of a `link_to` whose
literal options include `method:` or `data: { turbo_method: }`. Otherwise it is
a link. The viewer uses this to pick the route of that name: a form takes the
non-GET route (matching an explicit literal method when one is given, else the
first non-GET), a link takes the GET route.

**Layouts.** Each layout an action resolves to is read once: its own helper
calls and the partials it renders become the layout's links. The page records
only the layout name. Links found in a layout are never copied onto pages.

**Shape.**

```json
"pages": [
  {
    "controller": "Spina::Admin::UsersController",
    "action": "index",
    "template": { "name": "spina/admin/users/index.html.erb", "path": "app/views/spina/admin/users/index.html.erb", "line": 1, "url": "https://github.com/.../index.html.erb#L1" },
    "layout": "spina/admin/admin",
    "partials": [ { "name": "spina/admin/users/_user.html.erb", "path": "...", "line": 1, "url": "..." } ],
    "components": [ { "name": "Spina::UserInterface::TabLinkComponent", "path": "app/components/spina/user_interface/tab_link_component.rb", "line": 3, "url": "..." } ],
    "links": [
      { "stem": "new_admin_user", "engine": "Spina::Engine", "form": false, "source": { "name": "new_admin_user_path", "path": "app/views/spina/admin/users/index.html.erb", "line": 12, "url": "...#L12" } },
      { "stem": "admin_users", "engine": "Spina::Engine", "form": true, "source": { "name": "admin_users_path", "path": "app/views/spina/admin/users/_form.html.erb", "line": 3, "url": "...#L3" } }
    ],
    "redirects": [
      { "stem": "admin_users", "engine": "Spina::Engine", "source": { "name": "Spina::Admin::UsersController#create", "path": "app/controllers/spina/admin/users_controller.rb", "line": 23, "url": "...#L23" } }
    ]
  }
],
"layouts": [
  {
    "name": "spina/admin/admin",
    "source": { "name": "layouts/spina/admin/admin.html.erb", "path": "...", "line": 1, "url": "..." },
    "controllers": [ "Spina::Admin::UsersController", "..." ],
    "links": [ { "stem": "admin_pages", "engine": "Spina::Engine", "form": false, "source": { "...": "..." } } ]
  }
]
```

An action with no template, no links and no redirects produces no row. A link's
`source` is the file and line of the helper call, whichever file it was found
in (page template, partial, component template or class). `components` are
source nodes from `Source.for_const`, like models and controllers. `stem` is
the route name as `routes[].name` spells it and `engine` the route's engine;
the viewer joins on both. `schema_version`
becomes 3; `meta`, the existing eleven keys and their shapes do not change.

**Warnings** (`where: "pages"`): a partial or component that could not be
resolved to a file (named, once per name); a template or Ruby file Prism could
not parse (named, with the first error message); an Inertia page, as one
warning per dump saying client-side links are not collected. Unresolved helper
stems are not warnings.

### 4.3 Wiring

`Dump#collect` runs `pages` after `controllers`, passing the controllers' rows
(for actions and view nodes) and the routes (for names). `Dump#run` gives it
the empty shape `{ "pages" => [], "layouts" => [] }` on failure, as `boot` and
`entry_points` get `{}` today.

## 5. The view

### 5.1 Placement

A nav entry "Page flow" (icon: a short chain of three nodes, drawn like the
sprite's other 16px strokes) between Request map and Domain model, with the
page count. Route `#/flow`, `#/flow/<group>` opens a controller group,
`#/flow/<group>/<Controller%23action>` opens a group with a page selected
(the same `ident()` rule as model anchors, so `Spina::Admin::UsersController#index`
becomes `Spina__Admin__UsersController_index`).

### 5.2 What a node is

A node is a controller action that a GET route reaches and that resolves an
HTML template or an Inertia page; an action with only a JSON or Turbo Stream
template is not a page. The node is identified by `Controller#action` (so an
unnamed GET route still gets a node) and labelled by the path of its first GET
route; the other paths are in the detail panel. A link resolves to a route by
(`engine`, `stem`), and the route to its action's node. Write routes (POST, PATCH, PUT, DELETE) are not nodes: a form
edge whose target action redirects is drawn page → landing page, labelled with
the action (`create`, `update`, `destroy`); a form edge whose target does not
redirect to a page (renders, or redirects to a non-page) is drawn to a small
action node labelled `verb action`. Inertia pages are nodes with a `page` tag.

### 5.3 Grouping and scale

Pages group by controller namespace: everything before the last `::` of the
controller name (`Spina::Admin`), or `(app)` for top-level controllers. Chips
above the diagram name the groups with their page counts, as the Domain model's
chips name models.

Below 60 pages the diagram draws every group, one Mermaid `subgraph` per group.
At 60 or more it draws one group at a time (the largest first, or the chip
chosen), one subgraph per controller inside it, and the pages outside the group
that the group links to or is linked from as muted nodes; clicking a muted node
switches to its group. The threshold is a constant in the viewer, not config.

Layout links are not edges. Above the diagram a "Navigation" row lists each
layout with its links as chips (path, verb pill), so a page reachable only from
the navigation is not an orphan but is marked `from navigation` in the ledger.

### 5.4 Interaction on the rendered SVG

After Mermaid renders, the script finds each node's `<g>` by the id it gave
Mermaid (the same `ident()` rule as the entity diagram) and attaches: hover
lights the node's in and out edges; click selects it (its edges stay lit, every
other node and edge dims to the existing muted tokens; click again or press
Escape clears); Enter and Space do the same from the keyboard (nodes get
`tabindex="0"` and an `aria-label` of the path). The selection is written to the
hash with `history.replaceState`, never by assigning `location.hash`, because
`hashchange` re-runs `render()` and Mermaid, which would reset zoom and pan on
every click; `render()` also skips the Mermaid re-run when only the selected
page changed. Zoom, pan, fit and full screen are the existing viewer's;
selection survives them.

The detail panel, under the diagram when a page is selected: path(s) and verb,
template and layout as source links, partials and components as source links,
"links to" and "linked from" as lists of page links (each a link that selects
that page), "lands here after" (write actions that redirect to it, with their
source), filters and models from the Request map's data for that action, and
"documents about this" from `related:`. This is the same information the
Request map's expanded row shows, plus the flow.

### 5.5 The ledger

Under the diagram, one table: Page (path, with the verb pill), Template (source
link), Links out (count), Linked from (count, `from navigation` tag when the
only inbound link is a layout's), Lands here after (action names), Warnings.
Sorted by path; the top-bar filter narrows it by path, route name, controller
and template path, as every other view does. A page with no links in or out
and no navigation link is tagged `unreached`.

### 5.6 Empty and error states

No pages (an API-only app): the empty state says what a page is and that the
app has no HTML templates. Mermaid failure: the diagram error block with the
source, as today. More than 60 pages: the group picker is the first thing shown,
with the largest group open.

### 5.7 Cross-links

The Request map's expanded row gains two lines, "links to" and "linked from",
each a link into `#/flow/<group>/<route>`. Nothing else changes elsewhere.

## 6. Documents, tests, acceptance

- `docs/overview.md`: thirteen top-level keys, schema version 3, Page flow in
  the view list. `docs/architecture.md`: the pages collector in the list.
  `README`: the view list. The spec's view table (section 6 of the first
  release design) is left as history; this document is the record.
- Dummy app: `PatientsController` gains `new` and `create` (redirecting to
  `patient_path`), `patients/new.html.erb` with `form_with url: patients_path`,
  `patients/index.html.erb` rendering a `_row` partial that links to
  `patient_path` and `new_patient_path`, the application layout gaining a
  `patients_path` link, and one template with a non-route helper stem
  (`image_path`). Tests cover: links from template and partial, the form flag,
  the redirect, the layout link not copied onto pages, the dropped non-route
  stem, an unparseable template becoming a warning, an engine template resolved
  through view paths (a tiny engine in the dummy app with one controller and
  template, mounted in routes), and the empty shape on collector failure.
- Viewer test: the dummy dump's `index.html` contains the Page flow nav entry
  and the flowchart source for the dummy's pages.
- Acceptance: the Spina run reports pages and links (the spike measured 37
  pages, 20 page links, 16 redirect landings with partials but without layouts
  and components; the collector should exceed that), and `check_links` verifies
  the template URLs.

## 7. Decisions made in this design

| Decision | Chosen | Rejected and why |
|---|---|---|
| Diagram engine | Mermaid flowchart (vendored; ELK layered layout is bundled) with our own SVG post-processing | Cytoscape.js + dagre: drag and compound nodes for about 470 KB and a second visual language; d3-force: a cloud, the wrong shape for a flow. Revisit only if use shows rearranging matters |
| Click bindings | Attached by the viewer's script | Mermaid `click`: disabled under `securityLevel: "strict"`, which stays |
| Node identity | GET route name; template shared by two routes is one node | One node per template loses the path label readers know |
| Write actions | Collapsed into labelled edges when they redirect to a page | Drawing every POST as a node doubles the node count for no new information |
| Layouts | A navigation row, not edges | One edge per page from the layout buries the real flow |
| Unresolved helper stems | Dropped silently | Warnings for `image_path` and the like would drown the real ones |
| Scale | Draw all under 60 pages, one group at a time above | Collapsible subgraphs need Mermaid's `view: collapsed`, unverified in 12.2.0 under strict mode |
| Inertia links | Deferred; nodes without edges plus one warning | A TSX scan is a second parser and its own design |
| Scope of link sources | Templates, partials, layouts, view components | Templates and partials only: Spina's admin would show 22 of 37 pages unreached |
| Template languages | Every registered handler (ERB, Haml, Slim) | ERB only: Mastodon, an acceptance target, is Haml and would get nodes with no edges |
| Join key for links | (engine, route name) with the call's receiver recorded | Route name alone: an app `root` and an engine `root` would cross-link |
| Node identity | `Controller#action` reached by a GET route with an HTML or Inertia template | Route name: unnamed routes lose their node; any template: JSON endpoints become pages |

## 8. Left to the builder

- Template and layout resolution. Verified on the dummy app under Rails 8.1.4
  on 2026-11-04 (`bin/rails runner`, `PatientsController`):
  `lc = ActionView::LookupContext.new(klass._view_paths, { formats: [:html] })`;
  `lc.find_all(action, klass._prefixes, false).first` returns the
  template (`#identifier` is its absolute path) or nil; partials use `true` as
  the third argument; `klass.new.send(:_layout, lc, [:html], [])` returns the
  layout as an `ActionView::Template` (its `identifier` is the file), a String
  name, or nil, and its arity is three (`actionview/lib/action_view/layouts.rb`,
  `_layout(lookup_context, formats, keys)`). Instantiating the controller with
  `new` is what Rails itself does and raised nothing here; wrap it in the
  per-node rescue like every other reflection call.
- How Mermaid 12.2.0 names node groups in the SVG (verify against the vendored
  build, not the docs) and the muted-node style within the Mermaid theme.
- Partial name resolution edge cases (`render "shared/x"`, collections with
  `partial:`, `render locals:` with no name) beyond the string-literal rule;
  anything not a string literal is skipped, not warned.
- The 60-page threshold's exact value and the order of groups in the chips.
- Test fixtures' names and the tiny engine's layout.
- Sizing the detail panel and the ledger at phone width within the existing
  tokens.

## 9. Questions put to the owner

1. **Decided 2026-11-04: leave out.** Scaffold forms and redirects (`form_with model: @record`, `redirect_to
   @record`). The design leaves them out and shows the gap in the detail
   panel. The alternative is a convention rule: inside a template rendered by
   controller C, `form_with model:` posts to C's `create` (from `new`) or
   `update` (from `edit`) route when C has one, and `redirect_to @record` in C
   lands on C's `show` route; such edges are drawn dashed and tagged `by
   convention`. The rule is right for resourceful controllers and wrong when
   the form's model is routed by another controller, which is why it is not
   the default. The owner chose to leave them out in this wave; the tagged
   rule is a follow-up once the honest edges are in use.
