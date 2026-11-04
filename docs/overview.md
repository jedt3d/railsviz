# RailsVis overview

RailsVis is a gem that turns a Rails 8 app into a static onboarding dashboard. It boots the app, reflects on routes, controllers, models and databases, reads the app's Markdown documents, and writes two files: `doc/rails_vis/data.json` and a single-file `doc/rails_vis/index.html` viewer.

Run it with `bin/rails rails_vis:dump`. The output needs no running server: it can be published to GitHub Pages or opened from disk.

A newcomer should be able to answer from the dashboard alone: what the app does, which URL creates a record, which model owns it, and how to run the app locally.

Scope of the first release: Rails 8.0 and 8.1, SQLite and PostgreSQL. Views: Start here, Request map, Page flow, Domain model, Databases, Boot, Middleware, Entry points, Gems, Documents.

`data.json` has thirteen top-level keys: `meta`, `documents`, `routes`, `controllers`, `models`, `databases`, `boot`, `middleware`, `entry_points`, `gems`, `pages`, `layouts` and `warnings`; schema_version 3 added pages and layouts (schema 2 added boot, middleware, entry_points and gems; schema 1 had the first seven).

Further reading: [architecture](architecture.md), [local setup](runbooks/local-setup.md), and the decisions in `docs/decisions/`.
