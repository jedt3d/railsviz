# RailsVis First Release Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A `rails_vis` gem whose `bin/rails rails_vis:dump` task writes a static onboarding dashboard (Start here, Request map, Domain model, Databases) for any Rails 8 app, with every node linked to GitHub at the dump commit and to official Rails and gem documentation.

**Architecture:** The gem boots the host app, eager-loads it, and runs one collector per view, each returning plain hashes. `Dump` merges them into `data.json`, embeds the JSON into a prebuilt single-file viewer, and writes both to `doc/rails_vis/`. The viewer is vanilla JavaScript with Marked and Mermaid inlined; it renders from the embedded JSON only. All collectors run inside a dummy Rails app under `test/` for tests.

**Tech Stack:** Ruby ≥ 3.3 (Prism ships with it), Rails 8.0–8.1, Minitest (bundled with Ruby), SQLite and PostgreSQL, Marked and Mermaid (inlined, no runtime fetch), GitHub Actions. Acceptance targets: Lobsters (SQLite) and Mastodon (PostgreSQL) at pinned commits.

**Spec:** `docs/superpowers/specs/2026-11-03-rails-onboarding-dashboard-design.md`

## Global Constraints

- Gem name `rails_vis`; gemspec `required_ruby_version ">= 3.3"`; dependency `rails ">= 8.0", "< 8.2"` and nothing else at runtime. (Ruby floor raised from the spec's 3.2 so Prism is always present and the regex fallback in spec §10 is not built; owner to confirm.)
- No new dependency in the host app beyond the gem itself. No network access during a dump.
- Output: `doc/rails_vis/data.json` and `doc/rails_vis/index.html`. `index.html` embeds the JSON in `<script id="rails-vis-data" type="application/json">`; the viewer never fetches. (Builder's call: one load path for both GitHub Pages and file://.)
- `data.json` top-level keys exactly: `meta`, `documents`, `routes`, `controllers`, `models`, `databases`, `warnings`. `meta.schema_version` is the integer `1`.
- Every code node is a hash `{ "name", "path", "line", "url" }`; `url` is `nil` when no repository is known. `path` is relative to the repository root (`git rev-parse --show-toplevel`), falling back to the Rails root when there is no repository. The two differ for an engine's dummy app (Spina: Rails root `test/dummy`, code in `app/` at the repository root), and GitHub permalinks need the repository-relative path.
- "App code" means a source path inside the repository root. Classes defined outside it (installed gems) are skipped by the collectors.
- Source URL format: `https://github.com/{owner}/{repo}/blob/{sha}/{path}#L{line}`, commit SHA only, never a branch name.
- Rails API URL: `https://api.rubyonrails.org/v{Rails.version}/classes/{Module/Path}.html#method-i-{name}`; guides: `https://guides.rubyonrails.org/v{major.minor}/{guide}.html`.
- Nothing that could hold a secret is written: no credential values, ENV values, database `url`, `password`, `host`, or `username`.
- A failure on one node records a warning `{ "where", "message" }` and continues. The dump never aborts on one bad class.
- Supported view layers: `app/views` templates and `render inertia: "Name"` resolved to `{pages_dir}/Name.tsx` or `.jsx`.
- Default config when `config/rails_vis.yml` is absent: `docs: ["docs/**/*.md"]`, `exclude: ["docs/superpowers/**"]`, `start_here: []`, `pages_dir: "app/frontend/pages"`, `repo_url: nil`.
- Commits: `git commit -m "..."` with a literal message is fine; never build a message with `$(cat …)` (bat alias rule).

## Review Focus

- A route whose controller class does not exist (typo, deleted controller): the Request map must still list the route, with a warning, not crash. Test in Task 6.
- A model whose table is missing (migration not yet run): skipped with a warning naming the model. Test in Task 7.
- `render inertia: some_variable` (non-literal component): view resolves to `nil` with a warning naming the action. Test in Task 6.
- A document with malformed front matter: shown with inferred fields and a warning; the dump completes. Test in Task 9.
- No git repository, or an origin that is not GitHub: every `url` is `nil`, one warning, dump completes. Test in Task 2.
- Real apps at scale (engine routes, API controllers, replica and multi-database configs with credential fields): the dump completes, links point at the right function line, no credential value is written. Test in Task 14.

---

### Task 1: Gem skeleton, dummy app, test harness

**Files:**
- Create: `rails_vis.gemspec`, `Gemfile`, `lib/rails_vis.rb`, `lib/rails_vis/version.rb`, `lib/rails_vis/railtie.rb`, `lib/tasks/rails_vis.rake`, `Rakefile`, `.gitignore`, `test/test_helper.rb`, `test/dummy/` (generated), `test/rails_vis_test.rb`

**Interfaces:**
- Produces: `RailsVis::VERSION = "0.1.0"`; `RailsVis::Railtie` loading `lib/tasks/rails_vis.rake`; `test/test_helper.rb` that boots `test/dummy` in the `test` environment and exposes `RailsVis.root` (the dummy app root as `Pathname`).

- [ ] **Step 1: Generate the gem layout**

The repository already exists on `main` with `docs/` and `.gitignore` committed (done 2026-11-03 before execution started).
```bash
cd /Users/worajedt/RailsVis
bundle gem rails_vis --test=minitest --no-coc --no-mit --no-changelog --linter=none --ci=none
```
Move the generated files up one level into the repository root (the generator creates a nested `rails_vis/` folder; keep the existing `.gitignore` entries and merge the generator's into it), then delete the nested folder.

- [ ] **Step 2: Fill the gemspec**

`summary`: "Static onboarding dashboard for Rails 8 apps". `required_ruby_version = ">= 3.3"`. `add_dependency "rails", ">= 8.0", "< 8.2"`. `files` = `lib/**/*`, `viewer/index.html`, `README.md`. No other dependencies. `Gemfile` adds `sqlite3`, `pg`, `rake`, `minitest` to the development group. Then `bundle install` (resolves Rails 8.1.4, already installed locally).

- [ ] **Step 3: Generate the dummy app**

```bash
bundle exec rails new test/dummy --skip-git --skip-bundle --skip-javascript --skip-hotwire --skip-test --skip-kamal --skip-docker --skip-ci --skip-solid --skip-rubocop --skip-brakeman --skip-bundler-audit --skip-thruster --skip-dev-gems --database=sqlite3
rm test/dummy/Gemfile test/dummy/Gemfile.lock
```
Edit `test/dummy/config/boot.rb` so `ENV["BUNDLE_GEMFILE"]` points at `../../Gemfile` relative to that file. Add `require "rails_vis"` to `test/dummy/config/application.rb` after `Bundler.require`.

- [ ] **Step 4: Write the failing smoke test**

`test/rails_vis_test.rb`:
```ruby
require "test_helper"
class RailsVisTest < Minitest::Test
  def test_version_and_dummy_boot
    assert_equal "0.1.0", RailsVis::VERSION
    assert Rails.application.initialized?
    assert_equal "dummy", RailsVis.root.basename.to_s
  end
end
```
`test/test_helper.rb`: set `ENV["RAILS_ENV"] = "test"`, require `rails_vis`, `require_relative "dummy/config/environment"`, require `minitest/autorun`, define `RailsVis.root = Rails.root` (add `mattr_accessor :root` in `lib/rails_vis.rb`).

- [ ] **Step 5: Run the test to verify it fails**

Run: `bundle exec ruby -Itest test/rails_vis_test.rb`
Expected: FAIL (dummy not bootable or `RailsVis.root` undefined).

- [ ] **Step 6: Implement `lib/rails_vis.rb`, `version.rb`, `railtie.rb`, empty rake file**

`railtie.rb`: `class RailsVis::Railtie < Rails::Railtie; rake_tasks { load File.expand_path("../tasks/rails_vis.rake", __dir__) }; end`. `lib/tasks/rails_vis.rake` is an empty `namespace :rails_vis do; end` for now.

- [ ] **Step 7: Run the test to verify it passes**

Run: `bundle exec ruby -Itest test/rails_vis_test.rb`
Expected: 1 runs, 0 failures.

- [ ] **Step 8: Rakefile test task and commit**

`Rakefile`: `Rake::TestTask` with `t.libs << "test"`, `t.pattern = "test/**/*_test.rb"`, excluding `test/dummy/**` and `test/acceptance/**`.
```bash
git add -A && git commit -m "chore: gem skeleton with dummy Rails 8 app and minitest harness"
```

---

### Task 2: Config and repository (git SHA, origin, URL builder)

**Files:**
- Create: `lib/rails_vis/config.rb`, `lib/rails_vis/repo.rb`, `test/config_test.rb`, `test/repo_test.rb`

**Interfaces:**
- Produces: `RailsVis::Config.load(root) -> Config` with readers `docs`, `exclude`, `start_here`, `pages_dir`, `repo_url` (defaults from Global Constraints; reads `config/rails_vis.yml` if present).
- Produces: `RailsVis::Repo.detect(root, repo_url: nil) -> Repo` with `root` (Pathname: the git toplevel, or `root` when not a repository), `owner`, `repo`, `sha`, `dirty?`, `relative(path) -> String` (path relative to `root`), `url_for(path, line) -> String | nil` (takes an absolute or repository-relative path), `to_h -> { "owner", "repo", "sha", "dirty", "url_base" }`, `warnings -> Array<String>`.

- [ ] **Step 1: Write failing config tests**

`test/config_test.rb`: `test_defaults_when_file_absent` asserts the five defaults; `test_reads_yaml` writes a temp dir with `config/rails_vis.yml` containing `pages_dir: app/pages` and `start_here: [docs/a.md]`, asserts both and that unspecified keys keep defaults.

- [ ] **Step 2: Write failing repo tests**

`test/repo_test.rb`, each in a `Dir.mktmpdir`:
- `test_github_ssh_origin`: `git init`, commit one file, `git remote add origin git@github.com:acme/app.git`; assert `owner == "acme"`, `repo == "app"`, `sha` is 40 hex chars, `url_for("app/x.rb", 7)` ends with `/blob/#{sha}/app/x.rb#L7`.
- `test_root_is_git_toplevel`: detect from a subdirectory `sub/dummy` of the temp repo; assert `root` is the temp repo and `relative("#{root}/sub/dummy/config/routes.rb") == "sub/dummy/config/routes.rb"`.
- `test_github_https_origin_with_dot_git`: same with `https://github.com/acme/app.git`.
- `test_dirty_tree_warns`: modify a tracked file; assert `dirty?` and a warning mentioning "dirty".
- `test_no_git_repo`: plain dir; assert `url_for` returns `nil`, `sha` is `nil`, one warning.
- `test_non_github_origin`: origin `https://gitlab.com/a/b.git`; assert `url_for` is `nil` and a warning.
- `test_repo_url_override`: no origin but `repo_url: "https://github.com/acme/app"`; assert `url_for` is a GitHub URL.

- [ ] **Step 3: Run to verify they fail**

Run: `bundle exec rake test`
Expected: NameError on `RailsVis::Config` / `RailsVis::Repo`.

- [ ] **Step 4: Implement `Config` and `Repo`**

`Config`: YAML via `YAML.safe_load_file`, merge over defaults. `Repo`: shell out with `git -C root rev-parse HEAD`, `git -C root remote get-url origin`, `git -C root status --porcelain`; parse origin with one regex matching both `git@github.com:o/r(.git)` and `https://github.com/o/r(.git)`; `url_base` = `https://github.com/{owner}/{repo}/blob/{sha}`.

- [ ] **Step 5: Run to verify they pass**

Run: `bundle exec rake test`
Expected: all pass.

- [ ] **Step 6: Commit**

```bash
git add -A && git commit -m "feat: config file and GitHub permalink builder"
```

---

### Task 3: Source nodes and action-body scan (Prism)

**Files:**
- Create: `lib/rails_vis/source.rb`, `lib/rails_vis/body_scan.rb`, `test/source_test.rb`, `test/body_scan_test.rb`, `test/dummy/app/controllers/patients_controller.rb`, `test/dummy/app/frontend/pages/Patients/Show.tsx` (one-line stub)

**Interfaces:**
- Consumes: `Repo#url_for`.
- Produces: `RailsVis::Source.node(name:, path:, line:, repo:) -> Hash` (the four-key node, `path` made relative via `repo.relative`); `RailsVis::Source.app_code?(path, repo:) -> Boolean` (true when the absolute path is inside `repo.root`); `RailsVis::Source.for_method(unbound_method, repo:) -> Hash | nil`; `RailsVis::Source.for_const(klass, repo:) -> Hash | nil` (via `Object.const_source_location`).
- Produces: `RailsVis::BodyScan.new(path, method_name, line) -> BodyScan` with `constants -> Array<String>` (constant and constant-path names read in the method body, e.g. `"Patient"`, `"Admin::Visit"`) and `inertia_component -> String | nil | :dynamic` (`:dynamic` when `render inertia:` has a non-string value).

- [ ] **Step 1: Add the dummy controller**

```ruby
class PatientsController < ApplicationController
  before_action :load_patient, only: %i[show]
  def index  = render(:index, locals: { patients: Patient.all })
  def show   = render(inertia: "Patients/Show", props: { patient: @patient })
  def export = render(inertia: component_name)
  private
  def load_patient = @patient = Patient.find(params[:id])
  def component_name = "Patients/Export"
end
```

- [ ] **Step 2: Write failing tests**

`test/source_test.rb`: `test_for_method_points_at_definition_line` asserts `path == "app/controllers/patients_controller.rb"` and `line` equals the `def show` line; `test_for_const` asserts the controller's node line is 1.
`test/body_scan_test.rb`: `test_constants_in_load_patient` → `["Patient"]`; `test_inertia_literal` on `show` → `"Patients/Show"`; `test_inertia_dynamic` on `export` → `:dynamic`; `test_no_inertia` on `index` → `nil`.

- [ ] **Step 3: Run to verify they fail**

Run: `bundle exec rake test`
Expected: NameError on `RailsVis::Source`.

- [ ] **Step 4: Implement `Source` and `BodyScan`**

`BodyScan`: `Prism.parse_file(path)`, find the `Prism::DefNode` whose `name == method_name` and `location.start_line == line`, then walk its body with a `Prism::Visitor` subclass collecting `ConstantReadNode#name` and `ConstantPathNode#full_name`, and `CallNode` with `name == :render` whose first argument is a `KeywordHashNode` holding an `AssocNode` with key `inertia`; value `StringNode` → its `unescaped`, else `:dynamic`.

- [ ] **Step 5: Run to verify they pass**

Run: `bundle exec rake test`
Expected: all pass.

- [ ] **Step 6: Commit**

```bash
git add -A && git commit -m "feat: source nodes and Prism action-body scan"
```

---

### Task 4: Documentation links

**Files:**
- Create: `lib/rails_vis/doc_links.rb`, `test/doc_links_test.rb`

**Interfaces:**
- Produces: module `RailsVis::DocLinks` with `api(module_path, method, kind: :instance) -> String`, `guide(name, anchor: nil) -> String`, `association(macro) -> String` (API link into `ActiveRecord/Associations/ClassMethods`), `validation(kind) -> String` (API `ActiveModel/Validations/HelperMethods#method-i-validates_{kind}_of`), `model_callback -> String` (guide `active_record_callbacks`), `controller_filter(kind) -> String` (API `AbstractController/Callbacks/ClassMethods#method-i-{kind}_action`), `routing -> String` (guide `routing`), `multiple_databases -> String` (guide `active_record_multiple_databases`), `gem(name) -> Hash` with keys `homepage`, `documentation_uri`, `source_code_uri`, `changelog_uri`, `rubygems`, `rubydoc` (from `Gem.loaded_specs[name]`; `nil` values when absent).

- [ ] **Step 1: Write failing tests**

Assertions use `Rails.version` from the booted dummy:
- `test_api_url`: `api("ActiveRecord::Associations::ClassMethods", :has_many) == "https://api.rubyonrails.org/v#{Rails.version}/classes/ActiveRecord/Associations/ClassMethods.html#method-i-has_many"`.
- `test_guide_url`: `guide("routing") == "https://guides.rubyonrails.org/v#{Rails.version.split('.')[0,2].join('.')}/routing.html"`.
- `test_validation_url` for `:presence` ends with `#method-i-validates_presence_of`.
- `test_gem_links_for_rails`: `gem("rails")[:rubygems] == "https://rubygems.org/gems/rails/versions/#{Rails.version}"` and `[:homepage]` is non-nil.
- `test_gem_links_unknown`: `gem("nope")` → every value `nil` except `rubygems` and `rubydoc`, which are still built from the name without a version.

- [ ] **Step 2: Run to verify they fail**

Run: `bundle exec rake test`
Expected: NameError on `RailsVis::DocLinks`.

- [ ] **Step 3: Implement `DocLinks`**

Pure string building. `rubydoc` = `https://rubydoc.info/gems/{name}/{version}` (version omitted when unknown).

- [ ] **Step 4: Run to verify they pass**

Run: `bundle exec rake test`
Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: Rails API, guide and gem documentation links"
```

---

### Task 5: Routes collector

**Files:**
- Create: `lib/rails_vis/collectors/routes.rb`, `test/collectors/routes_test.rb`
- Modify: `test/dummy/config/routes.rb`

**Interfaces:**
- Consumes: `Source.node`, `DocLinks.routing`.
- Produces: `RailsVis::Collectors::Routes.new(repo:).call -> { "routes" => Array<Hash>, "warnings" => Array<Hash> }`. Each route: `{ "verb", "path", "name", "controller", "action", "engine", "source" (node or nil), "doc_url" }`. Internal Rails routes (`route.internal`) are excluded. A route that mounts a `Rails::Engine` is replaced by that engine's own routes, each with `path` prefixed by the mount path and `engine` = the engine class name; application routes have `engine` `nil`.

- [ ] **Step 1: Dummy routes and a mounted engine**

`test/dummy/config/initializers/blog_engine.rb`:
```ruby
module Blog
  class Engine < ::Rails::Engine
    isolate_namespace Blog
  end
end
Blog::Engine.routes.draw { get "/posts", to: "posts#index" }
```
`test/dummy/config/routes.rb`:
```ruby
Rails.application.routes.draw do
  get "/health", to: "health#show"           # controller does not exist (Review Focus)
  resources :patients, only: %i[index show] do
    get :export, on: :member
  end
  mount Blog::Engine => "/blog"
end
```

- [ ] **Step 2: Write failing tests**

- `test_routes_have_source_line`: the `patients#index` route's `source["path"] == "config/routes.rb"` and `source["line"]` equals the `resources :patients` line.
- `test_internal_routes_excluded`: no route whose path starts with `/rails/`.
- `test_verb_path_controller_action`: `/health` → `verb "GET"`, `controller "health"`, `action "show"`.
- `test_doc_url`: every route's `doc_url` equals `DocLinks.routing`.
- `test_engine_routes_expanded`: a route with `path "/blog/posts"`, `controller "blog/posts"`, `engine "Blog::Engine"`; no route whose `path == "/blog"` without an action.

- [ ] **Step 3: Run to verify they fail**

Run: `bundle exec rake test`
Expected: NameError on the collector.

- [ ] **Step 4: Implement the collector**

Set `ActionDispatch::Routing::Mapper.route_source_locations = true`, call `Rails.application.reload_routes!`, iterate `Rails.application.routes.routes`. `source_location` is a `"path:line"` string on `ActionDispatch::Journey::Route` (verified in actionpack 8.1.4, `journey/route.rb:10`); split on the last colon. `verb` from `route.verb`, `path` from `route.path.spec.to_s` with the `(.:format)` suffix removed, `controller`/`action` from `route.defaults`. Engine expansion: when `route.app.app` (unwrapping `ActionDispatch::Routing::Mapper::Constraints`) is a class inheriting `Rails::Engine`, recurse into `engine.routes.routes` with the mount path as prefix. Engine routes' source lines also come from `source_location`, which the flag records for engine route files once they are reloaded.

- [ ] **Step 5: Run to verify they pass**

Run: `bundle exec rake test`
Expected: all pass.

- [ ] **Step 6: Commit**

```bash
git add -A && git commit -m "feat: routes collector with source lines"
```

---

### Task 6: Controllers collector (actions, filters, models referenced, view)

**Files:**
- Create: `lib/rails_vis/collectors/controllers.rb`, `test/collectors/controllers_test.rb`, `test/dummy/app/views/patients/index.html.erb` (stub)

**Interfaces:**
- Consumes: `Source.for_method`, `Source.for_const`, `BodyScan`, `DocLinks.controller_filter`, `Config#pages_dir`, the route list from Task 5 (to flag missing controllers).
- Produces: `RailsVis::Collectors::Controllers.new(repo:, config:, routes:, model_names:).call -> { "controllers" => Array<Hash>, "warnings" => Array<Hash> }`. Controller: `{ "name", "parent", "source", "filters": [{ "kind", "name", "only", "except", "source", "doc_url" }], "actions": [{ "name", "source", "models": Array<String>, "view": { "kind": "template"|"inertia", "path", "url" } | nil }] }`. `models` is the intersection of `BodyScan#constants` with `model_names`.

- [ ] **Step 1: Write failing tests**

- `test_actions_and_sources`: `PatientsController` has actions `index`, `show`, `export`; `show`'s source line equals its `def` line.
- `test_filters`: one filter `{ kind: "before", name: "load_patient", only: ["show"] }` with a source node and `doc_url` ending `#method-i-before_action`.
- `test_models_referenced`: `show`'s body names no constant, so its `models` is `[]`; `index`'s `models == ["Patient"]` (the controller from Task 3, unchanged).
- `test_view_template`: `index`'s view is `{ kind: "template", path: "app/views/patients/index.html.erb" }`.
- `test_view_inertia`: `show`'s view is `{ kind: "inertia", path: "app/frontend/pages/Patients/Show.tsx" }`.
- `test_view_dynamic_inertia_warns` (Review Focus): `export`'s view is `nil` and a warning names `PatientsController#export`.
- `test_missing_controller_warns` (Review Focus): a warning names `health#show`; the controllers list has no `HealthController`.

- [ ] **Step 2: Run to verify they fail**

Run: `bundle exec rake test`
Expected: NameError on the collector.

- [ ] **Step 3: Implement the collector**

`ActionController::Base.descendants + ActionController::API.descendants`, skip anonymous classes and classes for which `Source.app_code?` is false. Actions from `action_methods`. Filters from `_process_action_callbacks`: `kind`, `filter` (symbols only; procs recorded as `name: "(block)"` with the block's source location), `only`/`except` from the callback's `@if`/`@unless` when they are `ActionController` action-name conditions (best effort; `nil` otherwise). Template lookup: glob `app/views/{controller_path}/{action}.*`. Inertia: `BodyScan#inertia_component` → `{pages_dir}/{component}.tsx` or `.jsx`, whichever exists; neither exists → warning.

- [ ] **Step 4: Run to verify they pass**

Run: `bundle exec rake test`
Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: controllers collector with filters, model references and views"
```

---

### Task 7: Models collector

**Files:**
- Create: `lib/rails_vis/collectors/models.rb`, `test/collectors/models_test.rb`, `test/dummy/app/models/patient.rb`, `test/dummy/app/models/visit.rb`, `test/dummy/app/models/pending.rb`, `test/dummy/db/migrate/*_create_patients.rb`, `*_create_visits.rb`, `test/dummy/db/schema.rb`

**Interfaces:**
- Consumes: `Source.for_const`, `Source.for_method`, `DocLinks.association`, `DocLinks.validation`, `DocLinks.model_callback`.
- Produces: `RailsVis::Collectors::Models.new(repo:).call -> { "models" => Array<Hash>, "warnings" => Array<Hash> }`. Model: `{ "name", "table", "database", "source", "associations": [{ "macro", "name", "class_name", "foreign_key", "through", "dependent", "doc_url" }], "validations": [{ "kind", "attributes", "options", "doc_url" }], "callbacks": [{ "event", "kind", "name", "source", "doc_url" }], "columns": [{ "name", "type", "null", "default" }], "indexes": [{ "name", "columns", "unique" }] }`. The return hash also carries `"model_names" => Array<String>` (names of the listed models) for Task 6; `Dump` does not write that key to `data.json`.

- [ ] **Step 1: Dummy models and migrations**

`Patient`: `has_many :visits, dependent: :destroy`, `validates :name, presence: true`, `before_save :normalize_name`. `Visit`: `belongs_to :patient`. `Pending`: a model with no table (Review Focus). Migrations: patients(name string null false, born_on date) with index on name; visits(patient references, seen_at datetime). Run `bin/rails db:migrate` in `test/dummy` with `RAILS_ENV=test` and commit `db/schema.rb`.

- [ ] **Step 2: Write failing tests**

- `test_models_listed`: names include `Patient`, `Visit`; exclude `Pending` and `ApplicationRecord`.
- `test_pending_warns` (Review Focus): a warning names `Pending` and "table".
- `test_associations`: `Patient` has `{ macro: "has_many", name: "visits", class_name: "Visit", dependent: "destroy" }` with `doc_url` ending `#method-i-has_many`.
- `test_validations`: `Patient` has `{ kind: "presence", attributes: ["name"] }`.
- `test_callbacks`: `Patient` has `{ event: "save", kind: "before", name: "normalize_name" }` with a source node at the private method's line.
- `test_columns_and_indexes`: `patients` columns include `name` with `type "string"`, `null false`; one index on `["name"]`.
- `test_database_role`: `Patient`'s `database == "primary"`.

- [ ] **Step 3: Run to verify they fail**

Run: `bundle exec rake test`
Expected: NameError on the collector.

- [ ] **Step 4: Implement the collector**

`ActiveRecord::Base.descendants.reject(&:abstract_class?)`, skip classes for which `Source.app_code?` is false; `table_exists?` false → warning and skip. Associations via `reflect_on_all_associations` (`macro`, `name`, `class_name`, `options[:dependent]`, `foreign_key`, `options[:through]`). Validations via `validators` (`kind`, `attributes`, `options` minus procs). Callbacks: for each event in `ActiveRecord::Callbacks::CALLBACKS` (activerecord 8.1.4 `callbacks.rb:280`), read `_#{chain}_callbacks` where chain is the part after `before_`/`after_`/`around_`; keep symbol filters defined in the app. Columns via `columns` (`sql_type_metadata.type`), indexes via `connection.indexes(table_name)`. `database` = `connection_db_config.name`.

- [ ] **Step 5: Run to verify they pass**

Run: `bundle exec rake test`
Expected: all pass.

- [ ] **Step 6: Commit**

```bash
git add -A && git commit -m "feat: models collector with associations, validations, callbacks, schema"
```

---

### Task 8: Databases collector

**Files:**
- Create: `lib/rails_vis/collectors/databases.rb`, `test/collectors/databases_test.rb`
- Modify: `test/dummy/config/database.yml`

**Interfaces:**
- Consumes: `DocLinks.multiple_databases`, `DocLinks.gem`, model list from Task 7.
- Produces: `RailsVis::Collectors::Databases.new(models:).call -> { "databases" => Array<Hash> }`. Entry: `{ "env", "name", "adapter", "database", "migrations_paths", "solid_component" ("solid_cache"|"solid_queue"|"solid_cable"|nil), "models": Array<String>, "doc_url", "gem_links" }`. One entry per (env, name) across all environments in `config/database.yml`. Never includes `url`, `host`, `username`, `password`.

- [ ] **Step 1: Dummy database.yml**

Keep the generated file; it already has `production: primary/cache/queue/cable` from the Rails 8 sqlite3 template (railties 8.1.4 `templates/config/databases/sqlite3.yml:35-51`). Add `password: secret-should-not-leak` under `production.primary` for the secrets test in Task 10.

- [ ] **Step 2: Write failing tests**

- `test_all_envs_listed`: entries include `(test, primary)`, `(production, cache)`, `(production, queue)`.
- `test_solid_mapping`: `(production, cache)` → `solid_component == "solid_cache"` when `Gem.loaded_specs["solid_cache"]` exists, else `nil`; `migrations_paths == "db/cache_migrate"`.
- `test_models_attached`: `(test, primary)`'s `models` include `Patient`.
- `test_no_secret_keys`: no entry hash has keys `url`, `host`, `username`, `password`.

- [ ] **Step 3: Run to verify they fail**

Run: `bundle exec rake test`
Expected: NameError on the collector.

- [ ] **Step 4: Implement the collector**

`ActiveRecord::Base.configurations.configs_for` with no filter (signature `configs_for(env_name: nil, name: nil, config_key: nil, include_hidden: false)`, activerecord 8.1.4 `database_configurations.rb:100`); read `env_name`, `name`, `adapter`, `database`, `migrations_paths`. Solid mapping: name `cache`/`queue`/`cable` → `solid_cache`/`solid_queue`/`solid_cable` when that gem is loaded. Models attach by `connection_db_config.name` for the current env only.

- [ ] **Step 5: Run to verify they pass**

Run: `bundle exec rake test`
Expected: all pass.

- [ ] **Step 6: Commit**

```bash
git add -A && git commit -m "feat: databases collector with Solid component mapping"
```

---

### Task 9: Documents collector

**Files:**
- Create: `lib/rails_vis/collectors/documents.rb`, `test/collectors/documents_test.rb`, `test/dummy/docs/overview.md`, `test/dummy/docs/decisions/0001-sqlite.md`, `test/dummy/docs/domain/er.md`, `test/dummy/docs/broken.md`

**Interfaces:**
- Consumes: `Config#docs`, `#exclude`, `#start_here`; `Source.for_const` / `for_method` for `related`.
- Produces: `RailsVis::Collectors::Documents.new(config:, repo:).call -> { "documents" => Array<Hash>, "warnings" => Array<Hash> }`. Document: `{ "path", "title", "kind", "audience", "order", "related": Array<node>, "body", "has_mermaid" }`.

- [ ] **Step 1: Dummy documents**

`overview.md` with front matter `title: Dummy overview`, `kind: overview`, `order: 10`, `related: [app/models/patient.rb, PatientsController#show]`. `decisions/0001-sqlite.md` with no front matter and a `# ADR 0001: SQLite` heading. `domain/er.md` with no front matter and a ` ```mermaid ` block. `broken.md` with front matter whose YAML is invalid (`title: [unclosed`).

- [ ] **Step 2: Write failing tests**

- `test_front_matter_read`: overview → `title "Dummy overview"`, `kind "overview"`, `order 10`, `related.size == 2` with the second `name == "PatientsController#show"`.
- `test_kind_inferred_decision`: `decisions/0001-sqlite.md` → `kind "decision"`, `title "ADR 0001: SQLite"`, `order nil`.
- `test_kind_inferred_diagram`: `domain/er.md` → `kind "diagram"`, `has_mermaid true`.
- `test_broken_front_matter_warns` (Review Focus): `broken.md` is present with `title "broken"` and a warning naming the file; body is the raw text.
- `test_start_here_from_config`: with `start_here: ["docs/decisions/0001-sqlite.md"]` the decision gets `order 1`.
- `test_unresolved_related_warns`: a `related` entry `Nope#x` yields a warning and is dropped.
- `test_exclude`: a file under `docs/superpowers/` is absent.

- [ ] **Step 3: Run to verify they fail**

Run: `bundle exec rake test`
Expected: NameError on the collector.

- [ ] **Step 4: Implement the collector**

Front matter: `/\A---\n(.*?)\n---\n/m`, `YAML.safe_load` in a rescue that records the warning. Inference table from spec §5.3. `related` entries: a path that exists → node with `line 1`; `Class#method` → `Source.for_method(Class.instance_method(method))`; `Class` → `Source.for_const`; else warning. `start_here` config assigns `order` 1..n overriding front matter.

- [ ] **Step 5: Run to verify they pass**

Run: `bundle exec rake test`
Expected: all pass.

- [ ] **Step 6: Commit**

```bash
git add -A && git commit -m "feat: documents collector with front matter and folder inference"
```

---

### Task 10: Dump orchestrator, rake task, secrets guard

**Files:**
- Create: `lib/rails_vis/dump.rb`, `test/dump_test.rb`
- Modify: `lib/tasks/rails_vis.rake`, `viewer/index.html` (placeholder until Task 11: a page that shows `meta.app_name`)

**Interfaces:**
- Consumes: all collectors, `Config`, `Repo`.
- Produces: `RailsVis::Dump.new(root: RailsVis.root).call -> Pathname` (the output dir). Writes `doc/rails_vis/data.json` and `doc/rails_vis/index.html`. `meta`: `{ "schema_version": 1, "app_name", "rails_version", "ruby_version", "generated_at" (ISO 8601 UTC), "repo": Repo#to_h }`. Rake task `rails_vis:dump` runs `Rails.application.eager_load!` then `Dump`.

- [ ] **Step 1: Write failing tests**

- `test_writes_files_and_schema`: after `call`, both files exist; parsed JSON has exactly the seven top-level keys; `meta["schema_version"] == 1`.
- `test_html_embeds_json`: `index.html` contains `<script id="rails-vis-data" type="application/json">` followed by the JSON.
- `test_no_secret_leaks`: the string `secret-should-not-leak` (from Task 8's database.yml) appears in neither file; nor does any value of `ENV` longer than 8 characters that is set to a sentinel `ENV["RAILS_VIS_SENTINEL"] = "sentinel-value-xyz"` before the dump.
- `test_warnings_collected`: `warnings` includes the `Pending` model warning and the `health#show` warning.
- `test_rake_task`: `Rake::Task["rails_vis:dump"].invoke` inside the dummy writes the files (`Rails.application.load_tasks` in the test).

- [ ] **Step 2: Run to verify they fail**

Run: `bundle exec rake test`
Expected: NameError on `RailsVis::Dump`.

- [ ] **Step 3: Implement `Dump` and the rake task**

Run collectors in order Models → Routes → Controllers → Databases → Documents (controllers need `model_names` and `routes`). Each collector call wrapped so an exception becomes a warning `{ where: collector name, message }` and an empty list. Embed: read `viewer/index.html` from the gem, replace the token `<!--RAILS_VIS_DATA-->` with the script tag; JSON escapes `</` as `<\/`.

- [ ] **Step 4: Run to verify they pass**

Run: `bundle exec rake test`
Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: rails_vis:dump writes data.json and embedded viewer"
```

---

### Task 11: Viewer (Start here, Request map, Domain model, Databases, All documents)

**Files:**
- Create: `viewer/src/index.html`, `viewer/src/app.js`, `viewer/src/app.css`, `viewer/vendor/marked.min.js`, `viewer/vendor/mermaid.min.js`, `script/build_viewer.rb`, `test/viewer_test.rb`
- Replace: `viewer/index.html` (built output, committed)

**Interfaces:**
- Consumes: the `data.json` shape from Tasks 5–10, exactly as named there.
- Produces: `viewer/index.html` containing the token `<!--RAILS_VIS_DATA-->` and all scripts inline; `ruby script/build_viewer.rb` regenerates it.

- [ ] **Step 1: Vendor the libraries**

Download pinned versions into `viewer/vendor/` (choose the current stable of each; record the versions and source URLs in `viewer/vendor/VERSIONS`). No CDN references anywhere in the viewer.

- [ ] **Step 2: Write the failing build test**

`test/viewer_test.rb`: `test_built_viewer_is_self_contained` asserts `viewer/index.html` contains `<!--RAILS_VIS_DATA-->`, contains no `src="http`, no `href="http` inside `<link`, and contains the strings `marked` and `mermaid`. `test_build_is_idempotent`: running the build script twice yields identical bytes.

- [ ] **Step 3: Run to verify it fails**

Run: `bundle exec rake test`
Expected: FAIL (placeholder viewer lacks the libraries).

- [ ] **Step 4: Write the viewer**

`app.js` reads the embedded JSON and renders, with `location.hash` routing:
- Left navigation in this order: Start here, Request map, Domain model, Databases, All documents. A search box filters node names across views.
- Start here: documents with `order`, sorted, filtered by audience (`all` plus a toggle for `engineer`/`user`). Document page: Marked-rendered body, Mermaid blocks rendered, "Related code" list of nodes with GitHub links.
- Request map: table grouped by controller; row expands to filters, models referenced, view, source links, doc links. Missing-controller warnings shown inline.
- Domain model: Mermaid `erDiagram` generated from `models` (one entity per model with columns; one relation per `belongs_to`), then one section per model with associations, validations, callbacks, columns, indexes, and a "Documents about this" box (documents whose `related` includes the model's node).
- Databases: one card per entry grouped by env, showing adapter, database, Solid component, attached models, links.
- Footer: app name, Rails version, generated time, commit SHA, and a warning banner when `meta.repo.dirty` or `warnings` is non-empty (expandable list).
- Theme follows `prefers-color-scheme`; layout readable at 375px width.

`script/build_viewer.rb` concatenates `src/index.html` with `app.css` in `<style>`, vendor scripts and `app.js` in `<script>`, writing `viewer/index.html`.

- [ ] **Step 5: Run the test and a visual check**

Run: `bundle exec rake test` → PASS.
Run: `cd test/dummy && RAILS_ENV=test bin/rails rails_vis:dump`, open `test/dummy/doc/rails_vis/index.html` in the browser. Expected: all five navigation entries render; `PatientsController#show` links to GitHub only if the dummy's repo has a GitHub origin (it does not, so links are absent and the banner says so); the ER diagram shows Patient and Visit.

- [ ] **Step 6: Commit**

```bash
git add -A && git commit -m "feat: single-file viewer with Start here, request map, domain model, databases"
```

---

### Task 12: Self-documentation and README

**Files:**
- Create: `docs/overview.md`, `docs/architecture.md`, `docs/decisions/0001-reflect-not-parse.md`, `docs/decisions/0002-static-output.md`, `docs/decisions/0003-commit-permalinks.md`, `docs/decisions/0004-read-existing-docs-tree.md`, `docs/runbooks/local-setup.md`, `config/rails_vis.yml` (for the gem repo itself: `start_here` listing the three), `README.md`

**Interfaces:**
- Consumes: the document convention from Task 9.

- [ ] **Step 1: Write the documents**

Each decision file follows spec §9's row for it: context, chosen, rejected and why. `architecture.md` holds a Mermaid flowchart: host app → eager load → collectors → `data.json` → embed → `index.html` → GitHub Pages / file. `local-setup.md`: clone, `bundle install`, `bundle exec rake test`, run the dummy dump, open the file. `README.md`: what it is, install (`group :development do gem "rails_vis" end`), `bin/rails rails_vis:dump`, config keys from Global Constraints, link to the spec.

- [ ] **Step 2: Verify the documents through the collector**

Add `test/self_docs_test.rb`: run `Collectors::Documents` with `RailsVis.root` temporarily set to the gem root; assert the three `start_here` documents have `order` 1–3, all four decisions have `kind "decision"`, `architecture.md` has `has_mermaid true`, and `warnings` is empty.

Run: `bundle exec rake test`
Expected: PASS.

- [ ] **Step 3: Commit**

```bash
git add -A && git commit -m "docs: self-documentation in the dashboard convention and README"
```

---

### Task 13: PostgreSQL run and CI

**Files:**
- Create: `.github/workflows/test.yml`
- Modify: `test/dummy/config/database.yml`

**Interfaces:**
- Consumes: everything.

- [ ] **Step 1: Make the dummy switchable**

In `test/dummy/config/database.yml`, make the `test` entry an ERB conditional on `ENV["RAILS_VIS_DB"] == "postgres"`: PostgreSQL adapter with `url: <%= ENV["DATABASE_URL"] %>` versus the SQLite default. Keep `production` unchanged.

- [ ] **Step 2: Run the suite on both**

Run: `bundle exec rake test` → PASS (SQLite).
Run: with a local PostgreSQL available, `RAILS_VIS_DB=postgres DATABASE_URL=postgres://localhost/rails_vis_test bundle exec rake test` → PASS. If no local PostgreSQL exists, record that in the commit message and rely on CI.

- [ ] **Step 3: Workflow**

`.github/workflows/test.yml`: matrix `db: [sqlite, postgres]`, Ruby 3.3 and 3.4, a `postgres:16` service for the postgres leg, `bundle exec rake test`. Also assert `test_no_secret_leaks` passes on the postgres leg (DATABASE_URL must not appear in the output).

- [ ] **Step 4: Commit**

```bash
git add -A && git commit -m "ci: test matrix on SQLite and PostgreSQL, Ruby 3.3 and 3.4"
```

---

### Task 14: Acceptance run against real Rails 8 apps

**Files:**
- Create: `script/acceptance.rb`, `test/acceptance/acceptance_test.rb`, `acceptance/targets.yml`
- Modify: `.gitignore` (add `tmp/acceptance/`), `Rakefile` (task `acceptance`, not part of `rake test`), `.github/workflows/test.yml` (manual `workflow_dispatch` job only)

**Interfaces:**
- Consumes: `rails_vis:dump` from Task 10, `Repo` from Task 2.
- Produces: `rake acceptance[target]` where `target` is a key in `acceptance/targets.yml`; writes `tmp/acceptance/<target>/doc/rails_vis/` and a report `tmp/acceptance/<target>.report.json` with `{ "routes", "models", "controllers", "documents", "warnings", "links_checked", "links_ok" }`.

Targets, pinned on 2026-11-03 (all default branches on Rails 8.1). Run them in this order; each must pass before the next is attempted:

```yaml
spina:                      # first: a small CMS; the whole CMS is an engine mounted at "/" in test/dummy
  repo: https://github.com/SpinaCMS/Spina
  sha: 1eb9fa87d4ad559e946df2b1d16c401177233a6a
  app_dir: test/dummy       # Rails root; the repository root is two levels up, so paths and links must be repo-relative
  database: sqlite
  prepare: ["bundle exec rake db:prepare"]
  floors: { routes: 30, models: 10 }
lobsters:
  repo: https://github.com/lobsters/lobsters
  sha: 49c06ba923b252b0f075894c3a8796d2e1d0af11
  app_dir: .
  database: sqlite          # four SQLite databases in development: primary, cache, queue, rack_attack
  prepare: ["cp config/database.yml.sample config/database.yml", "bundle exec rake db:prepare"]
  floors: { routes: 50, models: 20 }
mastodon:
  repo: https://github.com/mastodon/mastodon
  sha: 77a0b36b54162e7395b7d72261af990309ea9fd8
  app_dir: .
  database: postgres        # primary plus replica (replica: true) with username/password/host fields
  prepare: ["bundle exec rake db:prepare"]
  env: { RAILS_ENV: development, DB_HOST: localhost, REDIS_URL: "redis://localhost:6379/9" }
  floors: { routes: 300, models: 100 }
```

- [ ] **Step 1: Write the failing acceptance test**

`test/acceptance/acceptance_test.rb` (excluded from the default pattern; run only by `rake acceptance`). Reads the report for the target named in `ENV["RAILS_VIS_TARGET"]` and asserts:
- `routes >= floors.routes`, `models >= floors.models`, `controllers > 0`.
- `data.json` contains none of the strings from the target's database config secrets: for Mastodon the values of `DB_USER`, `DB_PASS`, `DB_HOST` when set; for both, no key `password`, `username`, `host`, `url` anywhere in `databases`.
- Spina: every route has `engine == "Spina::Engine"`; `models` include `Spina::Page`; every controller and model `path` starts with `app/` (repository-relative, not `test/dummy/app/`); the route source paths start with `config/` (the engine's routes file at the repository root).
- Lobsters: `databases` has entries named `primary`, `cache`, `queue`, `rack_attack` for `development`, with `solid_component` `solid_cache` and `solid_queue` on `cache` and `queue`.
- Mastodon: `databases` has a `development` entry named `replica`.
- `links_checked == 10` and `links_ok == 10` (see Step 3).
- No warning whose `where` is a collector name (a whole collector failing is a defect; per-node warnings are allowed and reported).

- [ ] **Step 2: Run to verify it fails**

Run: `RAILS_VIS_TARGET=lobsters bundle exec ruby -Itest test/acceptance/acceptance_test.rb`
Expected: FAIL (no report file).

- [ ] **Step 3: Implement `script/acceptance.rb`**

For the target: `git clone --filter=blob:none <repo> tmp/acceptance/<target>` then `git checkout <sha>` (skip clone when the directory exists at that SHA); append `gem "rails_vis", path: "<gem root>"` to the repository-root `Gemfile` inside `group :development`; `bundle install`; then, with the working directory set to `app_dir`, run each `prepare` command with the target's `env`, then `bundle exec rake rails_vis:dump` (rake, not `bin/rails`, because an engine repository's `bin/rails` is the engine CLI, while `test/dummy/Rakefile` loads the app and its tasks); read `data.json` from `<app_dir>/doc/rails_vis/` and count. Link check: take the first ten controller action nodes with a non-nil `url`, `GET` each from GitHub and count HTTP 200 as `links_ok`; also fetch the raw file at that SHA and assert the line at `line` contains `def <action>` (this is what proves the permalink points at the right function, spec §7). Write the report. Each shell step prints its command; a non-zero exit aborts with the step name.

- [ ] **Step 4: Run Spina, then Lobsters, and verify**

Run: `bundle exec rake acceptance[spina]`
Expected: report written; the acceptance test passes. Open `tmp/acceptance/spina/test/dummy/doc/rails_vis/index.html` and confirm the Request map lists Spina's engine routes, the Domain model shows `Spina::Page`, and a controller link opens the file under `app/controllers/spina/` on GitHub at the right line.
Run: `bundle exec rake acceptance[lobsters]`
Expected: as above; open `tmp/acceptance/lobsters/doc/rails_vis/index.html` and confirm Request map, Domain model and Databases (four databases) render and that source links open the right line on GitHub.

- [ ] **Step 5: Run Mastodon and verify**

Requires local PostgreSQL and Redis. Run: `bundle exec rake acceptance[mastodon]`
Expected: as Step 4. If boot fails for a reason unrelated to the gem (missing service, missing ENV), record the exact error in the report and in the commit message; do not patch Mastodon.

- [ ] **Step 6: Workflow and commit**

Add a `workflow_dispatch` job `acceptance` to `.github/workflows/test.yml` with a `target` input, PostgreSQL 16 and Redis services, running `bundle exec rake acceptance[${{ inputs.target }}]`. It is not triggered on push.

```bash
git add -A && git commit -m "test: acceptance run against Spina, Lobsters (SQLite) and Mastodon (PostgreSQL) at pinned commits"
```

---

## Execution policy (owner's instruction, 2026-11-03)

- Subagent-driven: one fresh implementer subagent per task, in its own git worktree (`isolation: "worktree"`), branched from `main`; its branch is merged into `main` on this checkout only after review passes.
- Implementer model: Opus 5.5 at medium effort for Tasks 3, 5–11 and 14 (Rails reflection, Prism, the viewer); Sonnet 5.5 at medium effort for Tasks 1, 2, 4, 12 and 13 (scaffolding, string building, docs, CI).
- Verification only on Fable 5.1: the spec-compliance reviewer and the code-quality reviewer for each task, and the whole-branch review at the end. Fable is not used to implement.
- Each implementer brief carries the task text verbatim plus the Global Constraints and the Interfaces blocks of the tasks it consumes; nothing else from this conversation.

## Out of scope for this plan (next plan)

Views 4–7 (Boot, Middleware, Entry points, Gems), `rails_vis:install` and the generated GitHub Pages workflow, `rails_vis:check_links`, and running against PrimaryCareCenter once it has code.
