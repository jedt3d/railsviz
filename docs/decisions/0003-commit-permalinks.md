# ADR 0003: Source links are commit permalinks

## Context

Every code node links to GitHub with a file and line. Lines move as branches move.

## Chosen

Links use `https://github.com/{owner}/{repo}/blob/{sha}/{path}#L{line}`, where `{sha}` is `git rev-parse HEAD` at dump time. The dump warns when the working tree is dirty. Regenerating on every push keeps links current.

## Rejected

- Branch-name links: line numbers drift as the branch moves.
