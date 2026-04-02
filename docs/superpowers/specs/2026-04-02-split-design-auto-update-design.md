# Split design_auto_update into dedicated script

## Overview

Extract the view `auto_update` toggle feature from `maintenance_mode` into a new self-contained `bin/design_auto_update` script. Fix all bugs identified in review. Consolidate on `bin/` as the canonical script location.

## Decisions

- **No shared library** — each script is fully self-contained (~15 lines of env/curl setup duplicated)
- **Eager loading** — `design_auto_update` fetches all DBs and design docs at startup
- **Configurable log path** — `COUCHDB_MAINT_LOG` env var, defaults to `./maintenance_mode.log`
- **CLI mode for testability** — `bin/design_auto_update toggle <db> <design_doc> <view>` for non-interactive use; exits 0 on success, 1 on failure
- **Curl wrapper as function** — both scripts define `do_curl() { curl -s -H "Content-type: application/json" "$@"; }` replacing all `$CURL` call sites (the old string variable's embedded quotes didn't survive word splitting)
- **Docker-only** — scripts run inside the Docker container (Debian-based), so GNU coreutils (`date --iso-8601`) are available

## Changes

### `bin/maintenance_mode` — cleanup

- Remove all view-toggle code: `load_databases`, `ALL_DBS`, `DESIGN_DOCS`, `run_toggle_view_menu`, `toggle_view_auto_update`, `toggle_view` case branch and menu entry
- Keep `jq` dependency check (still used by `get_maintenance_mode` for error formatting)
- Replace `CURL` string variable with `do_curl()` function across all call sites (`get_maintenance_mode`, `set_maintenance_mode`, menu loop)
- Fix `set_maintenance_mode` quoting: use `do_curl ... -d "\"$VALUE\""` (the root copy's form, which correctly sends a JSON string)
- Replace hardcoded log path with `COUCHDB_MAINT_LOG` env var (default `./maintenance_mode.log`)
- Delete root `./maintenance_mode` (bin/ is canonical)

### `bin/design_auto_update` — new script

Self-contained bash script for toggling `auto_update` on CouchDB design doc views.

**Dependencies:** `whiptail`, `curl`, `jq` — all three checked at startup (Docker image guarantees availability)

**Environment variables:**
- `COUCH_URL` (required) — admin URL with credentials
- `COUCHDB_MAINT_LOG` (optional, default `./maintenance_mode.log`)

**Functions:**
1. `load_databases()` — fetches `_all_dbs`, then `_design_docs?include_docs=true` for each DB. Populates `ALL_DBS` array and `DESIGN_DOCS` associative array.
2. `run_toggle_view_menu()` — three-step whiptail drill-down: DB, design doc, view. `DESIGN_IDS` and `VIEW_NAMES` declared as proper bash arrays so whiptail menu heights are correct.
3. `toggle_view_auto_update(db, design_doc, view)` — fetches design doc, reads current `auto_update` value (defaults to `true`), flips it, PUTs updated doc back. Checks PUT response for errors (e.g., 409 conflict) and reports them. Logs the change.

**Entry point logic:**
- If called with `toggle <db> <design_doc> <view>` arguments: run `toggle_view_auto_update` directly (non-interactive CLI mode)
- Otherwise: call `load_databases`, enter interactive menu loop (`run_toggle_view_menu`, repeat until user cancels)

### `bin/test_toggle_view.sh` — rewritten

- Uses `curl` directly to set up fixtures (create DB, add design doc with `auto_update: true`)
- Calls `bin/design_auto_update toggle testdb _design/example myview` (CLI mode)
- Asserts `auto_update` flipped to `false` via `curl`; exits 1 with diagnostic message on failure
- Cleans up test DB
- No longer attempts to `source` the main script

### Files to delete

- `./maintenance_mode` (root copy — bin/ is canonical)
- `./test_toggle_view.sh` (root copy — bin/ is canonical)

### Docker / config

- `docker-compose.yml` — remove deprecated `version: "3.9"` line
- Add `.gitignore` with `.env` and temp files (`.maintenance_mode`, `.menu`, `.target_*`, `.db_menu`, `.design_menu`, `.view_menu`, `.tmp_design_doc`, `.design_doc`, `maintenance_mode.log`)
- Update `CLAUDE.md` to reflect two-script architecture and `jq` dependency

## Bug fixes included

1. **Menu item count off by one** — resolved: after removing the `toggle_view` menu entry, `$NUM_NODES` correctly reflects the item count again
2. **`DESIGN_IDS`/`VIEW_NAMES` not arrays** — declared as proper arrays in new script
3. **Test can't source script** — rewritten to use CLI mode instead
4. **Test variable typo (`cURL` vs `$CURL`)** — rewritten test uses curl directly
5. **Diverged bin/ copy quoting in `set_maintenance_mode`** — fixed to `do_curl ... -d "\"$VALUE\""`, root copy deleted
6. **Hardcoded log path** — configurable via `COUCHDB_MAINT_LOG` env var
7. **`$CURL` string variable broken** — embedded quotes don't survive word splitting; replaced with `do_curl()` function in both scripts
8. **PUT errors silently swallowed** — `toggle_view_auto_update` now checks response
