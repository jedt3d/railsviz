# RailsVis

RailsVis generates a static onboarding dashboard for a Rails 8 app (8.0 and 8.1; SQLite or PostgreSQL). It boots the app, reflects on routes, controllers, models and databases, reads the project's Markdown documents, and writes `doc/rails_vis/data.json` plus a single-file `doc/rails_vis/index.html`. No running server is needed to view it.

## Install

```ruby
# Gemfile
group :development do
  gem "rails_vis"
end
```

## Use

```sh
bin/rails rails_vis:dump
```

The database must be prepared first (`bin/rails db:prepare`). Open `doc/rails_vis/index.html`, or publish `doc/rails_vis/` to GitHub Pages. Commit `doc/rails_vis/` or add it to `.gitignore`; either way it does not mark the working tree dirty, but any other uncommitted change does, and then source links point at the last commit.

## Configuration

Optional file `config/rails_vis.yml`. Every key is optional; these are the defaults:

| Key          | Default                    | Meaning                                              |
|--------------|----------------------------|------------------------------------------------------|
| `docs`       | `["docs/**/*.md"]`         | Globs, relative to the app root, of documents to read |
| `exclude`    | `["docs/superpowers/**"]`  | Globs removed from `docs`                            |
| `start_here` | `[]`                       | Ordered document paths; assigns `order` 1..n         |
| `pages_dir`  | `app/frontend/pages`       | Inertia page root                                    |
| `repo_url`   | none                       | Overrides the `origin` remote for source links       |

## Documents

Documents are the host's existing Markdown files matched by `docs`. Front matter is optional YAML with `title`, `kind`, `audience`, `order` and `related`. Without front matter, `kind` is inferred from the first folder below the docs root:

- `decisions/`: decision
- `workflows/`, `sequences/`, `ui/`, `domain/`, `security/`: diagram if the file has a Mermaid fence, else reference
- `research/`: reference
- files directly in the docs root: overview
- any other folder: reference

`related` lists file paths, `Class`, or `Class#method` entries; entries that do not resolve are dropped with a warning. `start_here` takes precedence over front matter `order`.

## More

- Design: [docs/superpowers/specs/2026-11-03-rails-onboarding-dashboard-design.md](docs/superpowers/specs/2026-11-03-rails-onboarding-dashboard-design.md)
- Plan: [docs/superpowers/plans/2026-11-03-rails-vis-first-release.md](docs/superpowers/plans/2026-11-03-rails-vis-first-release.md)
- Local development: [docs/runbooks/local-setup.md](docs/runbooks/local-setup.md)

## License

MIT. See [LICENSE](LICENSE).
