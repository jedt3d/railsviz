# RailsVis Usability Wave Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close the four small follow-ups from the first release (GitHub issues 25, 23, 22, 21 on jedt3d/railsviz): redirect routes labelled in the Request map, filter rows linked to their `before_action` declaration line, an optional `rails_vis:check_links` verifier, and `rails_vis:install` generating the GitHub Pages workflow.

**Architecture:** Each task is one independent change on the existing gem: two touch collectors and the viewer (data shape additions only, `schema_version` stays `1`), two add rake tasks backed by a small plain-Ruby class with injectable I/O so tests never hit the network or the real repository. Nothing new is loaded at host-app boot beyond what the first release loads.

**Tech Stack:** Ruby ≥ 3.3 with Prism, Rails 8.0–8.1, Minitest, Net::HTTP (stdlib), GitHub Actions (`actions/upload-pages-artifact@v3`, `actions/deploy-pages@v4`). No new gem dependency.

**Spec:** `docs/superpowers/specs/2026-11-03-rails-onboarding-dashboard-design.md` (sections 5.4, 6 row 1, 7, 8) plus the issue bodies quoted in each task.

## Global Constraints

- Gem runtime dependency stays `rails ">= 8.0", "< 8.2"` only; nothing else is added to the gemspec or the host app. Standard library only for HTTP and file writing.
- No network access during `rails_vis:dump`. Only `rails_vis:check_links` may fetch, and only when the user runs it.
- `data.json` top-level keys stay exactly `meta, documents, routes, controllers, models, databases, warnings`; `meta.schema_version` stays the integer `1`. New fields are additive.
- Every code node stays `{ "name", "path", "line", "url" }`; built with `RailsVis::Source.node` / `for_method` / `for_const`, never by hand.
- "App code" means `RailsVis::Source.app_code?(path, repo:)`; gem code is never linked by repository path.
- Nothing that could hold a secret is written to any generated file: no credential values, ENV values, database `url`, `password`, `host`, `username`. The generated workflow references `${{ secrets.RAILS_MASTER_KEY }}` by name only (the generated workflow's `DATABASE_URL` names the ephemeral CI service's throwaway password, which is not an app secret).
- A failure on one node records a warning `{ "where", "message" }` via `RailsVis::Collectors.warning` / `.error` and continues.
- Viewer: vanilla JS in `viewer/src/app.js`; after any change run `ruby script/build_viewer.rb` and commit `viewer/index.html` (the test suite asserts the build is idempotent).
- Tests: `bundle exec rake test` must stay green on SQLite; the dummy app lives in `test/dummy` and is the only fixture app.
- Commits: `git commit -m "..."` with a literal message is fine; never build a message with `$(cat …)` (bat alias rule).
- Branch base: `main` at or after `8aab55f`. If your worktree's `main` is an unrelated "Initial commit", run `git reset --hard main` of the primary checkout before starting (see the task brief).

## Review Focus

- A `redirect(host: "example.com")` with no path: the route row must carry `"redirect" => { "status" => 301, "to" => nil }` and the viewer shows "(computed)" rather than crashing. Test in Task 1.
- `before_action :a, :b` (two symbols in one call) and a filter declared inside a concern's `included do` block: both rows link to the declaring line in the right file. Tests in Task 2.
- A filter whose method is not defined anywhere in app code (Devise's `authenticate_user!`): the row appears, sourced from the declaration; a Proc filter from a gem (`allow_browser`) still does not. Tests in Task 2.
- `check_links`: a URL with a `#fragment` is fetched without it; a fetch that raises counts as status `0` and a failure, never an exception out of the task. Tests in Task 3.
- `install` run twice, or on a README without a trailing newline, or in a checkout with no GitHub origin: one README line at most, the existing workflow untouched without `FORCE=1`, a printed note instead of a crash. Tests in Task 4.

---

### Task 1: Redirect routes in the Request map (issue 25)

Issue text: "Routes declared with `to: redirect(...)` (28 of 260 on Lobsters) have no controller or action and appear under a '(no controller)' group with a '?' action. The data is correct and the source link works. Improvement: the routes collector should detect `ActionDispatch::Routing::Redirect` endpoints (unwrapping Constraints) and emit a `redirect` field with the target path when available; the viewer shows a 'redirect' tag and the target instead of '?'."

**Files:**
- Modify: `lib/rails_vis/collectors/routes.rb` (`row`, lines 37–48)
- Modify: `viewer/src/app.js` (`renderRequests`, lines 282–333; `routeDetail`, lines 255–280)
- Modify: `test/dummy/config/routes.rb`
- Test: `test/collectors/routes_test.rb`
- Rebuild: `viewer/index.html` via `ruby script/build_viewer.rb`

**Interfaces:**
- Produces: every route row gains `"redirect"`: `nil` for ordinary routes, else `{ "status" => Integer, "to" => String | nil }`. `to` is the literal path for `redirect("/x")` (`PathRedirect`, whose `block` is the String) and `options[:path]` for `redirect(path: "/x", ...)` (`OptionRedirect`, whose `block` is the Hash); `nil` for a block redirect or a host-only option redirect. `controller` and `action` stay `nil` for redirect rows.

- [ ] **Step 1: Add fixture routes to `test/dummy/config/routes.rb`** (after the `/health` line)

```ruby
  get "/old-patients", to: redirect("/patients")                                  # redirect rows (issue 25)
  get "/legacy/:id", to: redirect { |params, _req| "/patients/#{params[:id]}" }
  get "/elsewhere", to: redirect(host: "example.com")
```

- [ ] **Step 2: Write the failing tests in `test/collectors/routes_test.rb`**

```ruby
  def test_redirect_routes_carry_target
    assert_equal({ "status" => 301, "to" => "/patients" }, find("/old-patients")["redirect"])
    assert_nil find("/old-patients")["controller"]
    assert_equal "test/dummy/config/routes.rb", find("/old-patients")["source"]["path"]
    assert_equal({ "status" => 301, "to" => nil }, find("/legacy/:id")["redirect"])
    assert_equal({ "status" => 301, "to" => nil }, find("/elsewhere")["redirect"])
    assert_nil find("/health")["redirect"]
    assert result["warnings"].none? { |w| w["message"].include?("old-patients") }, result["warnings"].inspect
  end
```

- [ ] **Step 3: Run it to verify it fails**

Run: `bundle exec ruby -Itest test/collectors/routes_test.rb -n test_redirect_routes_carry_target`
Expected: FAIL (`"redirect"` key missing, `nil` vs hash).

- [ ] **Step 4: Implement `redirect(route)` in `lib/rails_vis/collectors/routes.rb`**

Private method `redirect(route) -> Hash | nil`: unwrap `route.app` while it is an `ActionDispatch::Routing::Mapper::Constraints` (`.app`), return `nil` unless the endpoint `is_a?(ActionDispatch::Routing::Redirect)`, else `{ "status" => app.status, "to" => target }` where `target` is `app.block` when it is a `String`, `app.block[:path]` when it is a `Hash`, otherwise `nil`. Add `"redirect" => redirect(route)` to the hash returned by `row`.

- [ ] **Step 5: Run the routes and controllers tests**

Run: `bundle exec ruby -Itest test/collectors/routes_test.rb && bundle exec ruby -Itest test/collectors/controllers_test.rb`
Expected: all PASS (no "does not exist" warning is produced for redirect rows because `controller` is nil).

- [ ] **Step 6: Viewer in `viewer/src/app.js`**

In `renderRequests`: group key `r.redirect ? "(redirects)" : (r.controller || "(no controller)")`. In the action cell, when `r.redirect` is set render `h("span", { class: "tag" }, "redirect " + r.redirect.status), " → ", h("code", {}, r.redirect.to || "(computed)")` instead of `r.action || "?"`. In `routeDetail`, when `route.redirect` is set, the "Source" list shows only the `route` line (no action/controller entries) and the "View" cell reads `empty("redirect")`.

- [ ] **Step 7: Rebuild the viewer and run the whole suite**

Run: `ruby script/build_viewer.rb && bundle exec rake test`
Expected: all PASS; `git status` shows `viewer/index.html` modified.

- [ ] **Step 8: Dump the dummy app and eyeball the JSON**

Run: `cd test/dummy && bundle exec rake rails_vis:dump && ruby -rjson -e 'puts JSON.parse(File.read("doc/rails_vis/data.json"))["routes"].select { |r| r["redirect"] }.map { |r| [r["path"], r["redirect"]] }.inspect'`
Expected: three rows, targets `/patients`, `nil`, `nil`. (`test/dummy/doc/` is git-ignored; do not commit it.)

- [ ] **Step 9: Commit**

```bash
git add lib/rails_vis/collectors/routes.rb viewer/src/app.js viewer/index.html test/dummy/config/routes.rb test/collectors/routes_test.rb
git commit -m "feat: label redirect routes in the Request map (#25)"
```

---

### Task 2: Filter rows link to the declaration line (issue 23)

Issue text: "The app-code rule drops filters declared in app code but defined in a gem (Devise `authenticate_user!`). Source each filter row from the `before_action`/`after_action`/`around_action` call site found with Prism in the controller body, falling back to the method definition."

**Files:**
- Modify: `lib/rails_vis/body_scan.rb` (add a class method)
- Modify: `lib/rails_vis/collectors/controllers.rb` (`filter`, lines 44–65)
- Create: `test/dummy/app/controllers/admin_controller.rb`, `test/dummy/app/controllers/admin/reports_controller.rb`, `test/dummy/app/controllers/concerns/audited.rb`
- Test: `test/body_scan_test.rb`, `test/collectors/controllers_test.rb`

**Interfaces:**
- Produces: `RailsVis::BodyScan.callback_line(path, kind, filter_name) -> Integer | nil`: the start line of the first `Prism::CallNode` in the file whose `name` matches `/\A(?:prepend_|append_)?#{kind}_action\z/` and whose positional arguments include a `Prism::SymbolNode` with `unescaped == filter_name`. `kind` is `"before"`, `"after"` or `"around"`. Returns `nil` when not found; raises on an unreadable file (callers guard with `File.file?`).
- Produces: filter rows keep their keys (`kind, name, only, except, source, doc_url`). For a Symbol filter, `source` is now the declaration node `Source.node(name: "#{declaring_class} #{kind}_action :#{name}", path:, line:, repo:)` where `declaring_class` is the ancestor (class or module) whose file holds the call; fallback to the method-definition node as today when no declaration is found in app code. Proc filters are unchanged.

- [ ] **Step 1: Add fixtures to `test/dummy`**

`app/controllers/concerns/audited.rb`:
```ruby
# Fixture for rails_vis: a filter declared inside a concern (issue 23).
module Audited
  extend ActiveSupport::Concern
  included do
    after_action :audit
  end
  private
  def audit = nil
end
```
`app/controllers/admin_controller.rb`:
```ruby
# Fixture for rails_vis: authenticate_user! is defined by a gem in real apps (Devise); here it is absent,
# so only the declaration line is app code. set_locale is app code and shares the declaration.
class AdminController < ApplicationController
  include Audited
  before_action :authenticate_user!, :set_locale
  def index = head(:ok)
  private
  def set_locale = nil
end
```
`app/controllers/admin/reports_controller.rb`:
```ruby
class Admin::ReportsController < AdminController
  def index = head(:ok)
end
```
Add to `config/routes.rb`: `get "/admin", to: "admin#index"` and `get "/admin/reports", to: "admin/reports#index"`.

- [ ] **Step 2: Write the failing BodyScan test in `test/body_scan_test.rb`**

```ruby
  def test_callback_line_finds_declaration
    path = RailsVis.root.join("app/controllers/admin_controller.rb")
    line = File.readlines(path).index { |l| l.include?("before_action :authenticate_user!") } + 1
    assert_equal line, RailsVis::BodyScan.callback_line(path, "before", "authenticate_user!")
    assert_equal line, RailsVis::BodyScan.callback_line(path, "before", "set_locale")
    assert_nil RailsVis::BodyScan.callback_line(path, "after", "set_locale")
    assert_nil RailsVis::BodyScan.callback_line(path, "before", "nope")
  end
```

- [ ] **Step 3: Run it to verify it fails**

Run: `bundle exec ruby -Itest test/body_scan_test.rb -n test_callback_line_finds_declaration`
Expected: FAIL with NoMethodError `callback_line`.

- [ ] **Step 4: Implement `BodyScan.callback_line`** in `lib/rails_vis/body_scan.rb`

Parse with `Prism.parse_file(path.to_s).value`, walk `compact_child_nodes` depth-first, return the first matching call's `location.start_line`. Only positional arguments count (`node.arguments&.arguments` entries that are `Prism::SymbolNode`); the `only:`/`except:` hash is ignored.

- [ ] **Step 5: Run it to verify it passes**

Run: `bundle exec ruby -Itest test/body_scan_test.rb`
Expected: PASS.

- [ ] **Step 6: Write the failing collector tests in `test/collectors/controllers_test.rb`**

Update `test_filters`: the `load_patient` row's `source["line"]` is the line of `before_action :load_patient, only: %i[show]` in `patients_controller.rb` and `source["name"]` is `"PatientsController before_action :load_patient"`. Add:

```ruby
  def admin = result["controllers"].find { |c| c["name"] == "AdminController" }
  def decl_line(file, text) = File.readlines(RailsVis.root.join("app/controllers", file)).index { |l| l.include?(text) } + 1

  def test_filter_links_to_declaration_even_when_method_is_not_app_code
    filter = admin["filters"].find { |f| f["name"] == "authenticate_user!" }
    assert_equal "test/dummy/app/controllers/admin_controller.rb", filter["source"]["path"]
    assert_equal decl_line("admin_controller.rb", "before_action :authenticate_user!"), filter["source"]["line"]
    assert_equal "AdminController before_action :authenticate_user!", filter["source"]["name"]
    assert_equal filter["source"]["line"], admin["filters"].find { |f| f["name"] == "set_locale" }["source"]["line"]
  end

  def test_inherited_and_concern_filters_link_to_their_declaring_file
    reports = result["controllers"].find { |c| c["name"] == "Admin::ReportsController" }
    auth = reports["filters"].find { |f| f["name"] == "authenticate_user!" }
    assert_equal "test/dummy/app/controllers/admin_controller.rb", auth["source"]["path"]
    audit = reports["filters"].find { |f| f["name"] == "audit" }
    assert_equal "after", audit["kind"]
    assert_equal "test/dummy/app/controllers/concerns/audited.rb", audit["source"]["path"]
    assert_equal decl_line("concerns/audited.rb", "after_action :audit"), audit["source"]["line"]
    assert_equal "Audited after_action :audit", audit["source"]["name"]
  end
```
`test_framework_filters_dropped` stays as is (`allow_browser` is a Proc from actionpack).

- [ ] **Step 7: Run them to verify they fail**

Run: `bundle exec ruby -Itest test/collectors/controllers_test.rb`
Expected: the three filter tests FAIL (`authenticate_user!` row absent; `load_patient` line is the `def`).

- [ ] **Step 8: Implement the declaration lookup in `Controllers#filter`**

For `when Symbol`: iterate `klass.ancestors`, skipping those with `name.nil?`; for each, `node = Source.for_const(ancestor, repo: @repo)` and skip unless `node && Source.app_code?(node["path"], repo: @repo)`; resolve the absolute file via `Object.const_source_location(ancestor.name)&.first`, skip unless `File.file?`; `line = BodyScan.callback_line(file, callback.kind.to_s, raw.to_s)`; on the first hit build `Source.node(name: "#{ancestor.name} #{callback.kind}_action :#{raw}", path: file, line: line, repo: @repo)`. No hit: today's method-definition node. Parse each file once per collector run (`@parsed ||= {}` keyed by path is enough; a helper on `BodyScan` taking a cache is also fine).

- [ ] **Step 9: Run the full suite**

Run: `bundle exec rake test`
Expected: all PASS.

- [ ] **Step 10: Commit**

```bash
git add lib/rails_vis/body_scan.rb lib/rails_vis/collectors/controllers.rb test/dummy/app/controllers test/dummy/config/routes.rb test/body_scan_test.rb test/collectors/controllers_test.rb
git commit -m "feat: filter rows link to their before_action declaration line (#23)"
```

---

### Task 3: `rails_vis:check_links` (issue 22)

Issue text: "Fetches a sample of generated Rails API, guide, gem and GitHub links and reports non-200s. Not part of the dump." Spec section 8: "The dump does not fetch any URL. Link correctness is checked by a separate, optional task (`rails_vis:check_links`)."

**Files:**
- Create: `lib/rails_vis/check_links.rb`
- Modify: `lib/rails_vis.rb` (add `require_relative "rails_vis/check_links"` after `dump`)
- Modify: `lib/tasks/rails_vis.rake` (add the task after `dump`)
- Modify: `README.md` (one paragraph at the end of "## Use")
- Test: `test/check_links_test.rb`

**Interfaces:**
- Produces: `RailsVis::CheckLinks.new(data, sample: 10, fetch: CheckLinks::FETCH, io: $stdout)` where `data` is the parsed `data.json` Hash. `#call -> Array<Hash>` of `{ "kind" => String, "url" => String, "status" => Integer }`, one per checked URL, in check order; `#failures -> Array<Hash>` the subset with `status != 200`. `kind` is `"github"` for URLs starting `https://github.com/`, `"api"` for `https://api.rubyonrails.org/`, `"guides"` for `https://guides.rubyonrails.org/`, `"gem"` for any other `http(s)://` URL. URLs are collected by walking Hash values and Array elements recursively, skipping the Hash key `"body"` (document Markdown); distinct, sorted, first `sample` per kind. The fragment (`#...`) is stripped before fetching. `fetch` is a callable `url -> Integer status`; `FETCH` is the default: `Net::HTTP` GET with `User-Agent: rails_vis`, following up to 3 redirects, 10 s open/read timeouts, returning the final status; any exception from `fetch` is rescued by `call` and recorded as status `0`. `io` receives one line per URL: `ok   <kind> <url>` or `FAIL <kind> <url> (<status>)`, then `"<checked> checked, <failed> failed"`.
- Rake: `rails_vis:check_links` (no `:environment`) reads `Rails.root.join("doc/rails_vis/data.json")`, aborts with `run bin/rails rails_vis:dump first` when absent, runs `CheckLinks` with `sample: Integer(ENV.fetch("RAILS_VIS_LINK_SAMPLE", 10))`, and exits `1` when `failures` is non-empty.

- [ ] **Step 1: Write the failing tests in `test/check_links_test.rb`**

```ruby
# frozen_string_literal: true
require "test_helper"
require "stringio"

class CheckLinksTest < Minitest::Test
  DATA = {
    "routes" => [{ "source" => { "url" => "https://github.com/acme/app/blob/abc/config/routes.rb#L3" }, "doc_url" => "https://guides.rubyonrails.org/v8.1/routing.html" }],
    "models" => [{ "associations" => [{ "doc_url" => "https://api.rubyonrails.org/v8.1.3/classes/ActiveRecord/Associations/ClassMethods.html#method-i-has_many" }] },
                 { "associations" => [{ "doc_url" => "https://api.rubyonrails.org/v8.1.3/classes/ActiveRecord/Associations/ClassMethods.html#method-i-belongs_to" }] }],
    "databases" => [{ "links" => { "rubygems" => "https://rubygems.org/gems/solid_queue/versions/1.0.0", "broken" => "https://example.com/broken" } }],
    "documents" => [{ "body" => "see https://example.com/in-markdown-only" }]
  }.freeze

  def run_check(sample: 10, fetch: ->(url) { url.include?("broken") ? 404 : 200 })
    io = StringIO.new
    checker = RailsVis::CheckLinks.new(DATA, sample: sample, fetch: fetch, io: io)
    [checker.call, checker, io.string]
  end

  def test_kinds_and_statuses
    results, checker, out = run_check
    assert_equal %w[api api gem gem github guides], results.map { |r| r["kind"] }.sort
    assert_equal [{ "kind" => "gem", "url" => "https://example.com/broken", "status" => 404 }], checker.failures
    assert_includes out, "FAIL gem https://example.com/broken (404)"
    assert_includes out, "ok   github https://github.com/acme/app/blob/abc/config/routes.rb#L3"
    assert_includes out, "6 checked, 1 failed"
    refute results.any? { |r| r["url"].include?("in-markdown-only") }
  end

  def test_fetch_gets_url_without_fragment_and_sample_limits_per_kind
    seen = []
    results, = run_check(sample: 1, fetch: ->(url) { seen << url; 200 })
    assert_equal 4, results.size
    assert seen.none? { |u| u.include?("#") }, seen.inspect
    assert_includes seen, "https://github.com/acme/app/blob/abc/config/routes.rb"
  end

  def test_fetch_error_counts_as_failure
    results, checker, = run_check(fetch: ->(_) { raise Errno::ECONNREFUSED })
    assert results.all? { |r| r["status"] == 0 }
    assert_equal results.size, checker.failures.size
  end

  def test_rake_task_defined
    require "rake"
    Rails.application.load_tasks unless Rake::Task.task_defined?("rails_vis:check_links")
    assert Rake::Task.task_defined?("rails_vis:check_links")
  end
end
```
(Look at how `test/dump_test.rb:93-110` loads the rake tasks and mirror it.)

- [ ] **Step 2: Run them to verify they fail**

Run: `bundle exec ruby -Itest test/check_links_test.rb`
Expected: FAIL with NameError `RailsVis::CheckLinks`.

- [ ] **Step 3: Implement `lib/rails_vis/check_links.rb`** per the Interfaces block, and the rake task.

- [ ] **Step 4: Run the tests and the full suite**

Run: `bundle exec ruby -Itest test/check_links_test.rb && bundle exec rake test`
Expected: all PASS.

- [ ] **Step 5: Try it once for real on the dummy app**

Run: `cd test/dummy && bundle exec rake rails_vis:dump && RAILS_VIS_LINK_SAMPLE=2 bundle exec rake rails_vis:check_links; echo "exit=$?"`
Expected: a few `ok` lines for `github`, `api`, `guides`; note any FAIL in the commit message body if one is a genuine bad link generated by the gem (do not fix it in this task).

- [ ] **Step 6: README** — append to "## Use":

"`bin/rails rails_vis:check_links` fetches a sample of the generated links (GitHub, Rails API, guides, gems; `RAILS_VIS_LINK_SAMPLE` per kind, default 10) and exits 1 when any does not answer 200. It is the only task that touches the network."

- [ ] **Step 7: Commit**

```bash
git add lib/rails_vis/check_links.rb lib/rails_vis.rb lib/tasks/rails_vis.rake README.md test/check_links_test.rb
git commit -m "feat: rails_vis:check_links samples generated links and reports non-200s (#22)"
```

---

### Task 4: `rails_vis:install` generates the GitHub Pages workflow (issue 21)

Issue text: "Workflow runs db:prepare (Postgres service when the adapter is postgresql), passes RAILS_MASTER_KEY when present, dumps on push to the default branch, publishes doc/rails_vis/, adds a README link. Spec section 5.4."

**Files:**
- Create: `lib/rails_vis/install.rb`
- Modify: `lib/rails_vis.rb` (add `require_relative "rails_vis/install"` after `dump`)
- Modify: `lib/tasks/rails_vis.rake` (add the task after `dump`)
- Modify: `README.md` (new "## Publish" section between "## Use" and "## Configuration")
- Test: `test/install_test.rb`

**Interfaces:**
- Produces: `RailsVis::Install.new(root:, repo:, io: $stdout, force: false)` where `root` is the Rails root (`Pathname`) and `repo` a `RailsVis::Repo` (`owner`, `repo` may be nil). `#call -> Array<String>` of paths written, relative to `root`.
  - Writes `.github/workflows/rails_vis.yml` (content below). When the file exists and `force` is false: not written, `io.puts ".github/workflows/rails_vis.yml exists; FORCE=1 to overwrite"`.
  - Appends to `README.md` (creating it if absent) exactly one line, preceded by a blank line and ensuring the file ends with a newline before appending: `- [Onboarding dashboard](https://{owner}.github.io/{repo}/) generated by the rails_vis workflow on every push to {branch}.` Skipped when the README already contains `github.io/{repo}/` or when `owner` is nil (then `io.puts "README not updated: no GitHub origin"`).
  - `branch` = `git -C root symbolic-ref --short refs/remotes/origin/HEAD` with the `origin/` prefix removed, else `"main"`.
  - `postgres?` = `config/database.yml` exists and matches `/^\s*adapter:\s*["']?postgres/`. `vips?` = `Gemfile.lock` exists and matches `/^\s+ruby-vips \(/`.
  - Ends with `io.puts "Enable GitHub Pages with source 'GitHub Actions' in the repository settings."` whenever the workflow was written.
- Rake: `rails_vis:install` (no `:environment`): `RailsVis::Install.new(root: Rails.root, repo: RailsVis::Repo.detect(Rails.root, repo_url: RailsVis::Config.load(Rails.root).repo_url), force: ENV["FORCE"] == "1").call`.
- Workflow content (exact; `{branch}` substituted; the `services:` block only when `postgres?`; the `DATABASE_URL` line only when `postgres?`; the libvips step only when `vips?`):

```yaml
# Generated by bin/rails rails_vis:install. Dumps the onboarding dashboard and publishes it to GitHub Pages.
name: rails_vis

on:
  push:
    branches: [{branch}]
  workflow_dispatch:

permissions:
  contents: read
  pages: write
  id-token: write

concurrency:
  group: rails_vis-pages
  cancel-in-progress: true

jobs:
  dump:
    runs-on: ubuntu-latest
    services:
      postgres:
        image: postgres:16
        env:
          POSTGRES_PASSWORD: postgres
        ports:
          - 5432:5432
        options: >-
          --health-cmd "pg_isready -U postgres"
          --health-interval 10s
          --health-timeout 5s
          --health-retries 5
    env:
      RAILS_ENV: development
      RAILS_MASTER_KEY: ${{ secrets.RAILS_MASTER_KEY }}
      DATABASE_URL: postgres://postgres:postgres@localhost:5432/rails_vis
    steps:
      - uses: actions/checkout@v4
      - uses: ruby/setup-ruby@v1
        with:
          bundler-cache: true
      - name: Install libvips
        run: sudo apt-get update && sudo apt-get install -y libvips
      - run: bin/rails db:prepare
      - run: bin/rails rails_vis:dump
      - uses: actions/configure-pages@v5
      - uses: actions/upload-pages-artifact@v3
        with:
          path: doc/rails_vis
  deploy:
    needs: dump
    runs-on: ubuntu-latest
    environment:
      name: github-pages
      url: ${{ steps.deployment.outputs.page_url }}
    steps:
      - id: deployment
        uses: actions/deploy-pages@v4
```

- [ ] **Step 1: Write the failing tests in `test/install_test.rb`**

```ruby
# frozen_string_literal: true
require "test_helper"
require "tmpdir"
require "stringio"

class InstallTest < Minitest::Test
  WORKFLOW = ".github/workflows/rails_vis.yml"

  def with_app(adapter: "postgresql", vips: true, readme: "# App\n")
    Dir.mktmpdir do |dir|
      root = Pathname.new(dir)
      root.join("config").mkpath
      root.join("config/database.yml").write("default: &default\n  adapter: #{adapter}\n")
      root.join("Gemfile.lock").write(vips ? "GEM\n  specs:\n    ruby-vips (2.2.0)\n" : "GEM\n  specs:\n")
      root.join("README.md").write(readme) if readme
      yield root
    end
  end

  def repo(url = "https://github.com/acme/app") = RailsVis::Repo.detect(RailsVis.root, repo_url: url)

  def install(root, repo: self.repo, force: false)
    io = StringIO.new
    [RailsVis::Install.new(root: root, repo: repo, io: io, force: force).call, io.string]
  end

  def test_postgres_app_gets_service_vips_and_readme_line
    with_app do |root|
      written, out = install(root)
      assert_equal [WORKFLOW, "README.md"], written
      yml = root.join(WORKFLOW).read
      %w[postgres:16 DATABASE_URL libvips bin/rails\ db:prepare bin/rails\ rails_vis:dump actions/deploy-pages@v4].each { |s| assert_includes yml, s }
      assert_includes yml, "RAILS_MASTER_KEY: ${{ secrets.RAILS_MASTER_KEY }}"
      assert_includes yml, "path: doc/rails_vis"
      assert_match(/branches: \[\w+\]/, yml)
      assert_equal "# App\n\n- [Onboarding dashboard](https://acme.github.io/app/) generated by the rails_vis workflow on every push to main.\n", root.join("README.md").read
      assert_includes out, "GitHub Pages"
    end
  end

  def test_sqlite_app_without_vips_has_no_service_or_apt_step
    with_app(adapter: "sqlite3", vips: false) do |root|
      install(root)
      yml = root.join(WORKFLOW).read
      refute_includes yml, "postgres:16"
      refute_includes yml, "DATABASE_URL"
      refute_includes yml, "libvips"
    end
  end

  def test_second_run_changes_nothing_without_force
    with_app(readme: "# App") do |root|
      install(root)
      root.join(WORKFLOW).write("custom\n")
      written, out = install(root)
      assert_equal [], written
      assert_equal "custom\n", root.join(WORKFLOW).read
      assert_includes out, "FORCE=1"
      assert_equal 1, root.join("README.md").read.scan("github.io/app/").size
      written, = install(root, force: true)
      assert_equal [WORKFLOW], written
    end
  end

  def test_no_github_origin_skips_readme
    with_app do |root|
      written, out = install(root, repo: RailsVis::Repo.detect(root))
      assert_equal [WORKFLOW], written
      assert_equal "# App\n", root.join("README.md").read
      assert_includes out, "no GitHub origin"
    end
  end

  def test_rake_task_defined
    require "rake"
    Rails.application.load_tasks unless Rake::Task.task_defined?("rails_vis:install")
    assert Rake::Task.task_defined?("rails_vis:install")
  end
end
```
Note `test_second_run_changes_nothing_without_force` starts from a README with no trailing newline (Review Focus).

- [ ] **Step 2: Run them to verify they fail**

Run: `bundle exec ruby -Itest test/install_test.rb`
Expected: FAIL with NameError `RailsVis::Install`.

- [ ] **Step 3: Implement `lib/rails_vis/install.rb`** per the Interfaces block, and the rake task.

- [ ] **Step 4: Run the tests and the full suite**

Run: `bundle exec ruby -Itest test/install_test.rb && bundle exec rake test`
Expected: all PASS.

- [ ] **Step 5: Validate the generated YAML parses**

Run: `bundle exec ruby -ryaml -rtmpdir -rstringio -e 'require "./lib/rails_vis"; Dir.mktmpdir { |d| r = Pathname.new(d); r.join("config").mkpath; r.join("config/database.yml").write("x:\n  adapter: postgresql\n"); RailsVis::Install.new(root: r, repo: RailsVis::Repo.detect(r), io: StringIO.new).call; p YAML.safe_load(r.join(".github/workflows/rails_vis.yml").read).dig("jobs", "dump", "services", "postgres", "image") }'`
Expected: `"postgres:16"`.

- [ ] **Step 6: README** — add before "## Configuration":

```markdown
## Publish

```sh
bin/rails rails_vis:install
```

Writes `.github/workflows/rails_vis.yml`, which runs `db:prepare` (with a PostgreSQL service when `config/database.yml` uses the `postgresql` adapter) and `rails_vis:dump` on every push to the default branch, then publishes `doc/rails_vis/` to GitHub Pages, and adds one README line linking to the page. Add `RAILS_MASTER_KEY` to the repository secrets if the app needs credentials to boot; enable Pages with source "GitHub Actions" in the repository settings. `FORCE=1` overwrites an existing workflow.
```

- [ ] **Step 7: Commit**

```bash
git add lib/rails_vis/install.rb lib/rails_vis.rb lib/tasks/rails_vis.rake README.md test/install_test.rb
git commit -m "feat: rails_vis:install generates the GitHub Pages workflow (#21)"
```

---

## Execution policy (owner's instruction, 2026-11-03, unchanged)

- Subagent-driven: one fresh implementer subagent per task in its own git worktree (`isolation: "worktree"`) branched from `main` at `8aab55f` or later; the four tasks are independent and run in parallel; each branch is merged into `main` on the primary checkout only after review passes (Tasks 3 and 4 both append to `lib/tasks/rails_vis.rake` and `README.md`; the orchestrator resolves that merge).
- Implementer model: Opus 5.5 at medium effort for Task 2 (Prism, callback chain); Sonnet 5.5 at medium effort for Tasks 1, 3 and 4.
- Verification only on Fable 5.1: one spec-compliance-plus-code-quality reviewer per task, then one whole-wave review; the orchestrator (Fable) verifies the viewer change in the browser against the dummy and Spina dumps.
- Each implementer brief carries its task text verbatim plus Global Constraints and Review Focus; nothing else from this conversation.
