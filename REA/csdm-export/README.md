# csdm-export

Read-only exporter from a cs-demo-manager PostgreSQL database to per-match
SQLite `.csdmm` files for a mobile viewer.

## Status

Task 1: scaffold + PostgreSQL test fixture. More to come.

## Development

```sh
npm install
npm test        # requires a reachable PostgreSQL (see below)
npm run typecheck
```

Tests create and drop a database named `csdm_export_test` on the server
pointed to by `CSDM_TEST_DATABASE_URL`
(default `postgres://postgres:postgres@localhost:5432/csdm_export_test`).
Nothing outside that database is touched.
