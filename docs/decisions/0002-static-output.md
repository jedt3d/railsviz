# ADR 0002: Static output delivered by a rake task

## Context

Readers must open the dashboard without a running app server, including from a plain file.

## Chosen

A gem in the `development` group with the `rails_vis:dump` rake task. It writes static JSON plus one HTML file. Mermaid is inlined, so the file works offline.

## Rejected

- A mounted engine: it needs a running server, which fails the open-from-disk requirement.
- Server-rendered pages: they fail the "no running server" anti-goal.
- A second graph library for the entity diagram: it would double the payload.
