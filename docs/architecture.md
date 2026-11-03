---
title: Architecture
kind: diagram
---

# Architecture

`rails_vis:dump` runs inside the host app, so reflection sees the real, booted application.

```mermaid
flowchart LR
  host[Host Rails app] --> eager[Eager load]
  eager --> collectors[Collectors]
  collectors --> data[data.json]
  data --> embed[Embed into viewer]
  embed --> html[index.html]
  html --> out[GitHub Pages or local file]
```

- Collectors live in `lib/rails_vis/collectors/` (routes, controllers, models, databases, documents, `boot`, `middleware`, `entry_points` and `gems`) and each returns its slice of `data.json`; a failing node becomes a warning, not an abort.
- `viewer/index.html` is the prebuilt viewer; the dump embeds `data.json` into a copy of it.
- Nothing is fetched at dump time and no secret values are written.
