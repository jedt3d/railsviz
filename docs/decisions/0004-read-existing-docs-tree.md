# ADR 0004: Read the host's existing docs tree

## Context

Projects already keep Markdown under `docs/`. The dashboard needs those documents for Start here and for "Documents about this" boxes.

## Chosen

Read `docs/**/*.md` from the app root (configurable via `docs` and `exclude`). Front matter is optional; `kind` is inferred from the first folder below the docs root. Start here order comes from `start_here` in `config/rails_vis.yml` or from front matter `order`.

## Rejected

- A dedicated `docs/dashboard/` folder: it would force teams to copy documents they already have.
