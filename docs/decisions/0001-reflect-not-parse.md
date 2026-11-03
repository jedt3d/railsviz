# ADR 0001: Reflect on the booted app, do not parse source

## Context

The dashboard must show routes, controllers, models and associations as Rails actually sees them.

## Chosen

Boot the app, eager load it, and reflect (`Rails.application.routes`, `ActiveRecord::Base.descendants`, `reflect_on_all_associations`). Route source lines come from enabling `ActionDispatch::Routing::Mapper.route_source_locations` before routes load.

## Rejected

- Static parsing: it misses Rails metaprogramming, and parsing `routes.rb` cannot follow `draw`, concerns or engine mounts.
- A schema-file fallback for the database: a second code path that can disagree with the live database. The dump requires a prepared database.
