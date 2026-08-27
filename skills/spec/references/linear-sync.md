# Optional Linear mirror

Load only for `/release:spec NN --linear` when a Linear connector is already available.

Upsert one issue titled `[spec] Phase NN: <name>`. Match an existing issue before creating. Mirror
the SPEC Markdown without expanding or summarizing it, store the returned URL in `linear_issue`, and
keep the local file as source of truth. Connector absence is non-fatal; do not search/install one.
