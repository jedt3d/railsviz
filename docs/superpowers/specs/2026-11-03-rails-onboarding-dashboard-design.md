# RailsVis: Rails onboarding dashboard, design

Date: 2026-11-03
Status: approved by owner, 2026-11-03
Owner: Worajedt Sitthidumrong

## 1. Intent

One static dashboard per Rails 8 project that lets a new user or a new
software engineer understand, on day one, what the application does, how a
request moves through it, what the data looks like, where the code for each
of those lives on GitHub, and which official Rails or gem documentation
explains each concept.

The reason it exists: every Rails app has the same folders, so a file tree
teaches nothing. What differs between apps is the wiring (routes, models,
jobs, configuration), and that wiring is exactly what a newcomer must learn.
Reflection at dump time can recover all of it with file and line numbers.

## 2. Objective, goals, non-goals, anti-goals

### The single objective

Shorten the time for a newcomer to become productive in a given Rails 8
project. Every feature is judged against this alone.

### Goals

- G1. Show the request path: route, middleware, controller action, filters,
  models referenced, view (an `app/views` template or an Inertia page
  component), response.
- G2. Show the domain model: models, associations, validations, callbacks,
  and the table and columns under each model.
- G3. Show boot and configuration: application config, environment file,
  initializers in load order, credentials and environment variables read.
- G4. Show the non-route entry points: jobs and queues, mailers, Action Cable
  channels, recurring tasks, rake tasks.
- G5. Show the database layout, including the Rails 8 multi-database default
  (primary, cache, queue, cable) and which Solid component sits on each.
- G6. Link every code node to the exact file and line on GitHub, at the commit
  the dump was taken from, and display the function or method name.
- G7. Link every concept to the official documentation for the running Rails
  version, and every gem to its own documentation.
- G8. Carry a layer of project-authored documents in a defined format, with a
  "Start here" reading order and cross-links from code nodes to the documents
  that explain them.
- G9. Work as a published static site (link in the README, no clone needed)
  and as a single HTML file opened from disk after a local dump.

### Non-goals

- Not a debugger or a live request tracer.
- Not a dependency or vulnerability auditor.
- Not a test coverage tool.
- Not an editor. Reading only.
- Not a general documentation site generator. Only the defined document
  format is rendered.

### Anti-goals (would make it a failure even if it works)

- Requiring any new runtime dependency inside the host application.
- Requiring a running Rails server to view the dashboard.
- A hand-maintained table of links that goes stale.
- Showing everything with equal weight. Priority order (section 6) is part of
  the product.

## 3. Constraints

- Rails 8.0 and 8.1 only. No support or conditionals for older versions.
- Databases: SQLite and PostgreSQL. Other adapters may work but are not
  tested or promised.
- Ruby 3.2 or newer (the Rails 8 minimum). Prism, the parser that ships with
  Ruby 3.3+, may be used when present.
- Source links target GitHub only. Other hosts are out of scope. A project
  may override the repository URL in the config file (section 5.6); without
  git or without a GitHub origin, nodes keep `path` and `line`, get no `url`,
  and the dump records one warning.
- The dump needs a prepared development database (migrated, reachable).
  There is no schema-file fallback. The publish workflow provisions one.
- View layers supported in the first release: `app/views` templates and
  Inertia pages rendered with `render inertia: "Name"`, resolved to
  `app/frontend/pages/Name.{tsx,jsx}` (the vite_rails layout). Other view
  layers show "no template resolved" and a warning.
- The viewer is one self-contained HTML file plus one JSON data file. Any
  JavaScript libraries it needs are inlined at build time. It makes no network
  requests except the outbound documentation and GitHub links the user clicks.
- Data collection runs only in the development environment.

## 4. Users and the day-one journey

Two audiences, one page:

- A new software engineer who will change the code.
- A new non-engineering user (product, operations, clinical staff in the
  PrimaryCareCenter case) who needs to know what the system does and which
  screens exist.

The dashboard opens on the "Start here" reading list. From there the
expected path is: overview document, then the request map grouped by
resource, then the domain model, then local setup. Engineers go deeper into
boot, middleware and jobs. Non-engineers stop at the request map and the
domain model.

## 5. What we create

Five deliverables. The gem is `rails_vis` (name free on RubyGems as of
2026-11-03), developed in its own repository at `/Users/worajedt/RailsVis`
against a throwaway `rails new` fixture app, with PrimaryCareCenter as the
first real host once it has code.

### 5.1 The gem (data collector)

A Ruby gem added to the host application's development group. It provides
one rake task:

    bin/rails rails_vis:dump

The task boots the application in development, eager-loads all code,
reflects, and writes:

    doc/rails_vis/data.json
    doc/rails_vis/index.html   (copy of the viewer)

It also copies the project documents (5.3) into `data.json`. No code from
the gem is loaded in production. The gem's own runtime dependencies are
Rails only.

### 5.2 The viewer (single HTML file)

One HTML file that loads `data.json` from the same directory (or has it
inlined when built for file:// use) and renders the views in section 6. It
contains inlined copies of a Markdown renderer and Mermaid, chosen by the
builder. Mermaid renders both the project documents' diagrams and the
generated entity diagram, so one library serves both needs.

### 5.3 The document convention

The dashboard reads the host project's existing `docs/` tree. It does not
require a separate folder, because PrimaryCareCenter already defines a
documentation layout (`docs/documentation-plan.md`) with Mermaid diagrams in
Markdown under named subfolders and decision records under
`docs/decisions/NNNN-slug.md`, and copying those into a second folder would
be the stale-link anti-goal in another form. (My call, made after the
builder check; see section 15.)

Default input: every `docs/**/*.md`, excluding `docs/superpowers/**`.
Overridable in the config file (section 5.6).

Front matter is optional. When present it is YAML:

    ---
    title: Patient intake flow
    kind: proposal          # overview, proposal, decision, diagram, runbook, reference
    audience: engineer      # all, engineer, user
    order: 30               # position in the Start here list; lower first
    related:
      - app/models/patient.rb
      - PatientsController#create
    ---

When a field is absent the dump infers it:

| Field    | Inferred from                                                                 |
|----------|-------------------------------------------------------------------------------|
| title    | First `#` heading, else the file name                                         |
| kind     | Folder: `decisions/` is decision; `workflows/`, `sequences/`, `ui/`, `domain/`, `security/` is diagram when the file holds a Mermaid block, else reference; `research/` is reference; root files are overview |
| audience | all                                                                           |
| order    | none: the document is not in Start here, only in the All documents index      |
| related  | empty                                                                         |

The body is Markdown. Fenced blocks tagged `mermaid` are rendered as
diagrams. The `related` list accepts repository-relative file paths and
`Class#method` or `Class` names. The dump task resolves each entry to a code
node and records unresolved entries as warnings in `data.json`.

Start here shows documents that have an `order`, sorted. The config file may
instead list `start_here` paths in order, for projects that do not want
front matter in their docs. All documents appear in an index grouped by
folder.

Reserved kinds and their intent:

| kind      | What it is for                                              |
|-----------|-------------------------------------------------------------|
| overview  | What the system does, for whom, in plain language            |
| proposal  | A feature or change being proposed or built                  |
| decision  | A decision already made, with the options rejected and why   |
| diagram   | A standalone picture with a short caption                    |
| runbook   | Step-by-step instructions (local setup, deploy, on-call)     |
| reference | Glossary, data dictionary, research notes, anything looked up rather than read through |

### 5.4 The publish workflow

A GitHub Actions workflow file the gem can generate into the host repo:

    bin/rails rails_vis:install

It runs `rails_vis:dump` on every push to the default branch and publishes
`doc/rails_vis/` to GitHub Pages. The README gains one line linking to the
published page.

Because the dump needs a prepared database, the generated workflow:

- starts a PostgreSQL service container when `config/database.yml` names the
  `postgresql` adapter, else relies on SQLite files;
- runs `bin/rails db:prepare` before the dump;
- passes `RAILS_MASTER_KEY` from the repository secrets when present. When
  absent, the Boot view's credentials keys are omitted with a warning; the
  dump still completes.

### 5.5 The dashboard project's own documents

The dashboard repository uses the convention from the first commit:

- `docs/overview.md` (kind: overview, order 10)
- `docs/architecture.md` (kind: diagram, order 20) showing the dump pipeline
- `docs/decisions/NNNN-*.md` (kind: decision) for each decision in section 9
- `docs/runbooks/local-setup.md` (kind: runbook, order 30)

So the tool documents itself, and these files are the reference examples of
the format.

For PrimaryCareCenter, the Start here list (my call until told otherwise):
`docs/project-brief.md`, `docs/architecture.md`, `docs/GLOSSARY.md`, set
through `start_here` in the config file so the existing files need no front
matter.

### 5.6 The config file (optional)

`config/rails_vis.yml` in the host project. Every key is optional; the file
may be absent.

    repo_url: https://github.com/org/repo   # overrides the origin remote
    docs:                                   # globs, relative to the app root
      - docs/**/*.md
    exclude:
      - docs/superpowers/**
    start_here:                             # ordered; alternative to front matter
      - docs/project-brief.md
      - docs/architecture.md
    pages_dir: app/frontend/pages           # Inertia page root

No other configuration exists. Anything else is reflected from the app.

## 6. Views, in priority order

The order is the order of the left navigation and the order of build effort.
A release that ships only views 1 and 2 plus the Start here list is a valid
first release.

| # | View            | Content                                                                                                   | Links out to                                      |
|---|-----------------|-----------------------------------------------------------------------------------------------------------|---------------------------------------------------|
| 0 | Start here      | Project documents in `order`, filtered by audience                                                        | Document pages                                    |
| 1 | Request map     | Routes grouped by controller; each row expands to filters, action, models referenced, view (template or Inertia page), response format | Routes file line, action line, filter line, page component file, routing guide, controller guide |
| 2 | Domain model    | Entity diagram (Mermaid erDiagram) plus one page per model: associations, validations, callbacks, columns, indexes | Model file line, association API doc, validation guide, callback guide, schema |
| 3 | Databases       | Each configured database: adapter, role, which models connect, which Solid component uses it               | database.yml, multiple databases guide, Solid gem docs |
| 4 | Boot            | application.rb, environments/development.rb, initializers in load order, credentials keys, ENV keys read   | Each file line, configuring guide                 |
| 5 | Middleware      | Ordered stack with the gem that inserted each entry                                                        | Rails on Rack guide, gem docs                     |
| 6 | Entry points    | Jobs (queue, adapter), mailers (actions, templates), channels, recurring tasks, rake tasks                 | File lines, Active Job and Action Mailer guides   |
| 7 | Gems            | Each gem: version, what it injects (middleware, initializers, generators), links                           | Homepage, documentation_uri, source_code_uri, RubyGems page |

Every page shows a "Documents about this" box fed by the `related` field.

## 7. Source linking rules

- Link format: `https://github.com/{owner}/{repo}/blob/{sha}/{path}#L{line}`.
- `{sha}` is the commit at dump time (`git rev-parse HEAD`). `{owner}/{repo}`
  is parsed from the `origin` remote. Both are stored in `data.json`.
- Links use the commit, never the branch name, because line numbers drift
  when the branch moves. Regenerating on every push keeps links current.
- The dump records a warning when the working tree is dirty, and the viewer
  shows a banner, because lines may then not match the commit.
- Each code node stores `path`, `line`, and `name` (`Class#method` or
  `Class.method`). The viewer shows the name; the link carries the line.
  GitHub has no symbol anchor, so name-to-line resolution happens at dump
  time.
- Nodes from gems link to the gem's `source_code_uri` when present, else to
  the RubyGems page. No line numbers for gem code.

## 8. Documentation linking rules

- Rails API: `https://api.rubyonrails.org/v{Rails.version}/classes/{Module}.html#method-i-{name}`
  for instance methods, `#method-c-{name}` for class methods. The mapping from
  node kind to API page is a fixed table inside the gem (for example,
  association macros to `ActiveRecord::Associations::ClassMethods`).
- Rails guides: `https://guides.rubyonrails.org/v{major.minor}/{guide}.html`.
  Fixed table from view or node kind to guide name.
- Gems: from `Gem::Specification` at dump time: `homepage`,
  `metadata["documentation_uri"]`, `metadata["source_code_uri"]`,
  `metadata["changelog_uri"]`, plus `https://rubygems.org/gems/{name}/versions/{version}`
  and `https://rubydoc.info/gems/{name}/{version}`.
- The dump does not fetch any URL. Link correctness is checked by a separate,
  optional task (`rails_vis:check_links`) that is not part of the first
  release.

## 9. Decisions already made

| Decision                                   | Chosen                                               | Rejected and why                                                                 |
|--------------------------------------------|------------------------------------------------------|----------------------------------------------------------------------------------|
| Collection method                          | Boot the app and reflect                             | Static parsing misses Rails metaprogramming                                      |
| Delivery                                   | Gem in development group with a rake task            | Mounted engine needs a running server, fails G9                                   |
| Output                                     | Static JSON plus one HTML file                       | Server-rendered pages fail the "no running server" anti-goal                      |
| Link target                                | Commit SHA permalink                                 | Branch name links drift                                                           |
| Diagram engine                             | Mermaid, inlined                                     | A second graph library for the entity diagram would double the payload            |
| Rails versions                             | 8.0 and 8.1 only                                     | Version conditionals are maintenance with no onboarding value                     |
| Databases                                  | SQLite and PostgreSQL                                | Owner's scope                                                                     |
| Route source lines                         | Enable `ActionDispatch::Routing::Mapper.route_source_locations` before loading routes | Parsing routes.rb cannot follow `draw`, concerns or engine mounts |
| Project document location                  | The host's existing `docs/` tree, optional front matter, inference by folder | A dedicated `docs/dashboard/` folder would force copying existing docs      |
| Database at dump time                      | Required; workflow provisions it                     | A schema-file fallback is a second code path that can disagree with the live DB |
| Configuration                              | One optional `config/rails_vis.yml`, five keys         | Zero config cannot express repo URL overrides or Start here order                 |
| Documentation links                        | Generated from Rails version and gemspec metadata    | Hand-maintained link tables go stale                                              |

## 10. Data collection, by view

This is the plan of record for how each view's data is obtained. The
builder may substitute an equivalent reflection call.

- Eager load: `Rails.application.eager_load!` after boot, so descendants
  lists are complete.
- Routes: `Rails.application.routes.routes`, with the source-location flag
  enabled and routes reloaded; each route gives verb, path, controller,
  action, name, constraints, and source location. Engine routes are kept and
  tagged with the engine name.
- Controllers: `ActionController::Base.descendants` and
  `ActionController::API.descendants`; `action_methods`;
  `_process_action_callbacks` with `kind`, `filter`, and conditions;
  `Method#source_location` for actions and symbol filters; block filters
  store the block's source location.
- Models referenced by an action (approximate): constant references in the
  action method body. With Prism present, parse the file and walk the method
  node; otherwise, read the method's line range and match capitalized
  constants against known model names. Results are labeled "referenced", not
  "used", in the viewer.
- Views: for each action, the template files that match the controller path
  and action name under `app/views`, with their handlers and formats. In
  addition, `render inertia: "..."` calls found in the action body (same
  Prism walk as the models heuristic) resolve to a file under `pages_dir`.
  An action with neither shows "no template resolved" and a warning.
- Models: `ActiveRecord::Base.descendants` excluding abstract classes;
  `reflect_on_all_associations`, `validators`, callback chains per lifecycle
  event, `columns`, `connection.indexes(table_name)`, `table_name`,
  `connection_db_config` for the database role.
- Databases: `ActiveRecord::Base.configurations.configs_for(env_name: "development")`
  giving name, adapter, database. Solid component mapping from the presence of
  `solid_queue`, `solid_cache`, `solid_cable` and their configured connection
  names.
- Boot: `Rails.application.initializers.tsort_each` for name and context;
  `config/initializers/*.rb` listed in load order; ENV keys by scanning
  `config/` for `ENV[` and `ENV.fetch(`; credentials keys by
  `Rails.application.credentials.config.keys` (top level only, values never
  dumped).
- Middleware: the application's middleware stack in order; each entry's
  class and, when resolvable, the gem that defines it (from the class's
  source location matched against gem paths).
- Jobs: `ActiveJob::Base.descendants`, `queue_name`, the configured adapter.
  Recurring tasks from `config/recurring.yml` when present.
- Mailers: `ActionMailer::Base.descendants`, `action_methods`, template files.
- Channels: `ActionCable::Channel::Base.descendants`.
- Rake tasks: `Rails.application.load_tasks` then `Rake::Task.tasks`, keeping
  tasks defined under the application root only.
- Gems: `Bundler.load.specs` for name, version, metadata, and whether the gem
  defines a Railtie (checked by `Rails::Railtie.subclasses` source paths).
- Documents: read `docs/dashboard/*.md`, parse front matter, resolve
  `related` entries, embed body text.

Nothing that could contain a secret is written: credential values, ENV
values, database passwords and URLs are excluded by construction. Database
entries store adapter and name only.

## 11. The data file

`data.json` is one object with top-level keys: `meta`, `documents`, `routes`,
`controllers`, `models`, `databases`, `boot`, `middleware`, `entry_points`,
`gems`, `warnings`. Every code node has at least `name`, `path`, `line`,
`url`. The exact shape is left to the builder with two rules:

- The viewer must be able to render any view from `data.json` alone.
- A `meta.schema_version` integer is present from the first release.

## 12. Left to the builder

- Internal gem layout, test framework, and CI for the gem itself.
- Choice of Markdown renderer and Mermaid version to inline.
- Viewer visual design, within these limits: left navigation in the section 6
  order, a search box over node names, readable at phone width, light and
  dark theme.
- Exact JSON shape (section 11).
- How the viewer is bundled into the gem (prebuilt file committed, or built
  during gem release).
- Error handling when a reflection call fails for one node: record a warning,
  skip the node, continue. The dump must never abort on a single bad class.

## 13. First release and success criteria

First release contains: the gem with `rails_vis:dump`, views 0, 1, 2 and 3,
source links, Rails and gem documentation links, the document convention,
and the dashboard's own documents. Views 4 to 7 and `rails_vis:install`
follow.

Success is measured on a fresh Rails 8 app and on the PrimaryCareCenter app:

- `bin/rails rails_vis:dump` completes without error on both SQLite and
  PostgreSQL configurations.
- Every route in the Request map links to the correct line in the routes
  file and the correct action line, verified by hand on a sample of ten.
- On the PrimaryCareCenter app, every action that renders an Inertia page
  links to the page component file.
- Every model in the Domain model shows the same columns as `db/schema.rb`
  or `structure.sql`.
- A newcomer, given only the dashboard URL, can answer these without asking
  anyone: what the app does, which URL creates a patient, which model owns a
  visit, how to run the app locally.
- `data.json` contains no credential or ENV values (checked by a test that
  seeds a known secret and asserts it is absent).

## 14. Risks

- Models referenced per action is a heuristic. Mitigated by labeling and by
  the `related` field in documents for the cases that matter.
- Route source locations may resolve to the wrong frame when routes are
  drawn through helper methods (a known Rails issue). Mitigated by falling
  back to the routes file without a line and recording a warning.
- GitHub Pages publishing of a private repository requires a paid plan or a
  different host. Out of scope for the gem; the workflow is a template the
  host project may edit.
- Large apps produce large `data.json` files. No pagination in the first
  release; revisit if a real app exceeds a few megabytes.
- GitHub Pages for a private repository needs a paid plan. PrimaryCareCenter
  may end up on a customer VPS with no GitHub at all; there the dashboard is
  produced by a local dump and opened from disk (G9), and source links are
  absent unless `repo_url` is set.

## 15. Decided by the owner on 2026-11-03

1. The gem lives in its own repository (`RailsVis`), not inside the
   PrimaryCareCenter tree. It is developed against a throwaway `rails new`
   fixture app; PrimaryCareCenter becomes the first real host once it has
   code. The self-documentation in 5.5 lives in the RailsVis repository.
2. Project and gem name: RailsVis, gem `rails_vis`.

## 16. Calls made after the builder check

For the owner to confirm or overturn while reading:

- Read the host's existing `docs/` tree instead of a dedicated folder;
  front matter optional, kind inferred by folder (5.3).
- Inertia pages are a first-release view kind, resolved from
  `render inertia:` calls (constraints, 10).
- The dump requires a prepared database; the workflow provisions PostgreSQL
  or SQLite and runs `db:prepare` (5.4).
- One optional config file with five keys (5.6); without git or GitHub, nodes
  lose their links and the dump warns rather than fails.
- PrimaryCareCenter's Start here list: project brief, architecture,
  glossary (5.5).
