# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

A terminal UI tool written in bash that manages CouchDB cluster node maintenance mode using `whiptail` for the interactive menu interface and `curl` for HTTP API calls.

## Architecture

- **Two self-contained scripts** in `bin/`:
  - `bin/maintenance_mode`: Manages CouchDB cluster node maintenance mode
  - `bin/design_auto_update`: Toggles `auto_update` on design document views
- **Dependencies**: Requires `whiptail` (for TUI menus), `curl` (for HTTP requests), and `jq` (for JSON processing)
- **Configuration via environment variables**:
  - `COUCH_URL`: Admin URL with credentials (required)
  - `COUCHDB_NODE_USER`: Username prefix for Erlang nodes (default: `couchdb`)
  - `COUCHDB_NODE_SUFFIX`: Domain suffix for nodes (default: `.localdomain`)
  - `COUCHDB_NODES`: Space-separated list of node hostnames (default: `host-1 host-2 host-3`)
  - `COUCHDB_MAINT_LOG`: Log file path (default: `./maintenance_mode.log`)

## Key Functions

### maintenance_mode
- `get_maintenance_mode NODE`: Fetches current maintenance_mode config via `/_node/<node>/_config/couchdb/maintenance_mode`
- `set_maintenance_mode NODE VALUE`: Sets maintenance_mode and logs the change

### design_auto_update
- `load_databases`: Fetches all databases and caches their design docs
- `toggle_view_auto_update DB DESIGN_DOC VIEW`: Toggles the `auto_update` flag on a view
- `run_toggle_view_menu`: Interactive three-step drill-down (DB > design doc > view)
- CLI mode: `design_auto_update toggle <db> <design_doc> <view>`

## Maintenance Mode Values

- `true`: Node does not respond to clustered requests; `/_up` returns 404
- `nolb`: Only `/_up` returns 404 (node removed from load balancer)
- `false`: Normal operation; `/_up` returns 200

## API Endpoints

- GET/PUT `$COUCH_URL/_node/<node>/_config/couchdb/maintenance_mode`

## Development

- **Docker-only runtime**: Scripts run inside Debian-based CouchDB container; GNU coreutils assumed (`date --iso-8601`)
- **Docker volume issue**: `./bin:/usr/local/bin:ro` mount clobbers CouchDB's `docker-entrypoint.sh` — container won't start. Needs fix (mount individual files or use different path)
- **Syntax check**: `bash -n bin/<script>` to validate without running
- **Test**: `bin/test_toggle_view.sh` requires running CouchDB; uses CLI mode (`design_auto_update toggle <db> <ddoc> <view>`)

## Code Patterns

- **HTTP calls**: Use `do_curl()` function, not a `$CURL` string variable (embedded quotes don't survive word splitting)
- **Logging**: Both scripts log to `$COUCHDB_MAINT_LOG` (default `./maintenance_mode.log`)

## Temp Files

- `.maintenance_mode`: Stores raw API response
- `.menu`: Generated whiptail menu script
- `.target_node`/`.target_value`: Capture user selections from whiptail
- `.target_db`/`.target_design`/`.target_view`: Capture selections in design_auto_update
- `.db_menu`/`.design_menu`/`.view_menu`: Generated whiptail menu scripts for design_auto_update
- `.design_doc`/`.tmp_design_doc`: Design doc JSON for reading/updating
