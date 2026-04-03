# Split design_auto_update Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extract the view `auto_update` toggle into a dedicated `bin/design_auto_update` script, fix all reviewed bugs, and consolidate on `bin/` as the canonical location.

**Architecture:** Two self-contained bash scripts — `bin/maintenance_mode` (node maintenance) and `bin/design_auto_update` (view auto_update toggling). Each has its own dependency checks, env var handling, and `do_curl()` function. No shared library.

**Tech Stack:** Bash, whiptail, curl, jq, CouchDB HTTP API

**Spec:** `docs/superpowers/specs/2026-04-02-split-design-auto-update-design.md`

---

## Chunk 1: Core implementation

### Task 1: Clean up bin/maintenance_mode

**Files:**
- Modify: `bin/maintenance_mode`

- [ ] **Step 1: Replace `CURL` variable with `do_curl()` function**

In `bin/maintenance_mode`, replace line 42:

```bash
CURL='/usr/bin/curl -s -H "Content-type: application/json"'
```

with:

```bash
do_curl() { curl -s -H "Content-type: application/json" "$@"; }
```

Then replace all `$CURL` occurrences with `do_curl` throughout the file. After Step 4 removes the view-toggle code, exactly two call sites remain:
- `get_maintenance_mode`: line 66 (`$CURL "$COUCH_URL/_node/..."`)
- `set_maintenance_mode`: line 82 (`$CURL "$COUCH_URL/_node/..."`)

Do Step 4 (delete view-toggle code) first, then replace these two remaining `$CURL` sites.

- [ ] **Step 2: Add `COUCHDB_MAINT_LOG` env var**

After the `COUCH_URL` check block (around line 39), add:

```bash
COUCHDB_MAINT_LOG="${COUCHDB_MAINT_LOG:-./maintenance_mode.log}"
```

In `set_maintenance_mode`, replace the hardcoded log path:

```bash
# Before:
echo "..." | tee -a /opt/couchdb/data/maintenance_mode.log
# After:
echo "..." | tee -a "$COUCHDB_MAINT_LOG"
```

- [ ] **Step 3: Fix `set_maintenance_mode` quoting**

Replace the broken quoting in `set_maintenance_mode`:

```bash
# Before (bin/ version, broken):
do_curl "$COUCH_URL/_node/$COUCHDB_NODE_USER@$NODE$COUCHDB_NODE_SUFFIX/_config/couchdb/maintenance_mode" -X PUT -d \"\"$VALUE\"\" > /dev/null
# After (correct):
do_curl "$COUCH_URL/_node/$COUCHDB_NODE_USER@$NODE$COUCHDB_NODE_SUFFIX/_config/couchdb/maintenance_mode" -X PUT -d "\"$VALUE\"" > /dev/null
```

- [ ] **Step 4: Remove all view-toggle code**

Delete these sections from `bin/maintenance_mode`:
- The `ALL_DBS`, `DESIGN_DOCS`, `load_databases()` function definition, AND the standalone `load_databases` call (lines 44-62)
- The `run_toggle_view_menu()` function (lines 86-124)
- The `toggle_view_auto_update()` function (lines 126-149)
- The `toggle_view` static menu entry in the main loop (line 163: `echo "toggle_view \"Toggle view auto_update\" \\" >> .menu`)
- The `toggle_view)` case branch (lines 170-172)

Keep the `jq` dependency check — it's still used by `get_maintenance_mode`.

- [ ] **Step 5: Commit**

```bash
git add bin/maintenance_mode
git commit -m "Clean up bin/maintenance_mode: remove view-toggle code, fix curl and logging"
```

---

### Task 2: Write the test script

**Files:**
- Create: `bin/test_toggle_view.sh`

- [ ] **Step 1: Write `bin/test_toggle_view.sh`**

Overwrite with:

```bash
#!/usr/bin/env bash
set -euo pipefail

COUCH_URL="${COUCH_URL:-http://admin:admin@localhost:5984}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

DB="testdb_$$"
DESIGN_DOC="_design/example"
VIEW_NAME="myview"

do_curl() { curl -s -H "Content-type: application/json" "$@"; }

cleanup() {
    do_curl -X DELETE "$COUCH_URL/$DB" > /dev/null 2>&1 || true
}
trap cleanup EXIT

# Setup: create DB and design doc with auto_update: true
do_curl -X PUT "$COUCH_URL/$DB" > /dev/null
do_curl -X PUT "$COUCH_URL/$DB/$DESIGN_DOC" \
    -d "{\"_id\": \"$DESIGN_DOC\", \"language\": \"javascript\", \"views\": {\"$VIEW_NAME\": {\"map\": \"function(doc){emit(doc._id,null);}\", \"options\": {\"auto_update\": true}}}}" > /dev/null

# Act: toggle via CLI mode
COUCH_URL="$COUCH_URL" "$SCRIPT_DIR/design_auto_update" toggle "$DB" "$DESIGN_DOC" "$VIEW_NAME"

# Assert: auto_update should now be false
ACTUAL=$(do_curl "$COUCH_URL/$DB/$DESIGN_DOC" | jq -r ".views.\"$VIEW_NAME\".options.auto_update")
if [ "$ACTUAL" != "false" ]; then
    echo "FAIL: expected auto_update=false, got auto_update=$ACTUAL"
    exit 1
fi

echo "PASS: auto_update toggled to false"

# Act: toggle again
COUCH_URL="$COUCH_URL" "$SCRIPT_DIR/design_auto_update" toggle "$DB" "$DESIGN_DOC" "$VIEW_NAME"

# Assert: auto_update should now be true
ACTUAL=$(do_curl "$COUCH_URL/$DB/$DESIGN_DOC" | jq -r ".views.\"$VIEW_NAME\".options.auto_update")
if [ "$ACTUAL" != "true" ]; then
    echo "FAIL: expected auto_update=true, got auto_update=$ACTUAL"
    exit 1
fi

echo "PASS: auto_update toggled back to true"
echo "ALL TESTS PASSED"
```

- [ ] **Step 2: Make it executable**

```bash
chmod +x bin/test_toggle_view.sh
```

- [ ] **Step 3: Commit**

```bash
git add bin/test_toggle_view.sh
git commit -m "Rewrite test script for design_auto_update CLI mode"
```

---

### Task 3: Create bin/design_auto_update

**Files:**
- Create: `bin/design_auto_update`

- [ ] **Step 1: Write `bin/design_auto_update`**

```bash
#!/bin/bash
set -e

echo "Checking dependencies..."
if ! which whiptail > /dev/null; then
    echo "ERROR: whiptail not found. Please install whiptail or fix your PATH."
    exit 1
fi

if ! which curl > /dev/null; then
    echo "ERROR: curl not found. Please install curl or fix your PATH."
    exit 1
fi

if ! which jq > /dev/null; then
    echo "ERROR: jq not found. Please install jq or fix your PATH."
    exit 1
fi
echo "All good."

if [ -z "$COUCH_URL" ]; then
    echo "Please set \$COUCH_URL to the admin URL (containing user and password)"
    exit 1
fi

COUCHDB_MAINT_LOG="${COUCHDB_MAINT_LOG:-./maintenance_mode.log}"

do_curl() { curl -s -H "Content-type: application/json" "$@"; }

# Fetch all databases and cache design docs
ALL_DBS=()
declare -A DESIGN_DOCS

function load_databases() {
    echo "Loading databases..."
    while IFS= read -r db; do
        ALL_DBS+=("$db")
        DESIGN_DOCS["$db"]=$(do_curl "$COUCH_URL/$db/_design_docs?include_docs=true" 2>/dev/null)
    done < <(do_curl "$COUCH_URL/_all_dbs" | jq -r '.[]')
    echo "Loaded ${#ALL_DBS[@]} databases."
}

function toggle_view_auto_update() {
    local DB="$1"
    local DESIGN_DOC="$2"
    local VIEW_NAME="$3"

    # Fetch full design doc
    do_curl "$COUCH_URL/$DB/$DESIGN_DOC" > .design_doc

    # Check current auto_update state (defaults to true if not set)
    local CURRENT
    CURRENT=$(jq -r ".views.\"$VIEW_NAME\".options.auto_update // true" .design_doc)
    local NEW
    if [ "$CURRENT" = "true" ]; then
        NEW=false
    else
        NEW=true
    fi

    # Update the design doc
    local UPDATED
    UPDATED=$(jq ".views.\"$VIEW_NAME\".options.auto_update = $NEW" .design_doc)

    # PUT and check for errors
    local RESPONSE
    RESPONSE=$(echo "$UPDATED" | do_curl "$COUCH_URL/$DB/$DESIGN_DOC" -X PUT -d @/dev/stdin)
    if echo "$RESPONSE" | jq -e '.error' > /dev/null 2>&1; then
        echo "ERROR: $(echo "$RESPONSE" | jq -r '.error + ": " + .reason')"
        return 1
    fi

    echo "$(date --iso-8601=minutes) $DB/$DESIGN_DOC/$VIEW_NAME auto_update $CURRENT -> $NEW" | tee -a "$COUCHDB_MAINT_LOG"
}

function run_toggle_view_menu() {
    # Select database
    local DB_MENU=""
    for db in "${ALL_DBS[@]}"; do
        DB_MENU+="$db \"$db\" "
    done
    echo "whiptail --menu \"Select Database\" 20 80 ${#ALL_DBS[@]} ${DB_MENU} 2> .target_db" > .db_menu
    chmod +x .db_menu && ./.db_menu
    local SELECTED_DB
    SELECTED_DB=$(cat .target_db)
    [ -z "$SELECTED_DB" ] && return 1

    # Extract design docs for selected DB
    local DESIGN_JSON="${DESIGN_DOCS["$SELECTED_DB"]}"
    local DESIGN_IDS
    DESIGN_IDS=($(echo "$DESIGN_JSON" | jq -r '.rows[].id'))

    local DESIGN_MENU=""
    for d in "${DESIGN_IDS[@]}"; do
        DESIGN_MENU+="$d \"$d\" "
    done
    echo "whiptail --menu \"Select Design Doc\" 20 80 ${#DESIGN_IDS[@]} ${DESIGN_MENU} 2> .target_design" > .design_menu
    chmod +x .design_menu && ./.design_menu
    local SELECTED_DESIGN
    SELECTED_DESIGN=$(cat .target_design)
    [ -z "$SELECTED_DESIGN" ] && return

    # Fetch design doc to list its views
    do_curl "$COUCH_URL/$SELECTED_DB/$SELECTED_DESIGN" > .tmp_design_doc
    local VIEW_NAMES
    VIEW_NAMES=($(jq -r '.views | keys[]' .tmp_design_doc))

    local VIEW_MENU=""
    for v in "${VIEW_NAMES[@]}"; do
        VIEW_MENU+="$v \"$v\" "
    done
    echo "whiptail --menu \"Select View\" 20 80 ${#VIEW_NAMES[@]} ${VIEW_MENU} 2> .target_view" > .view_menu
    chmod +x .view_menu && ./.view_menu
    local SELECTED_VIEW
    SELECTED_VIEW=$(cat .target_view)
    [ -z "$SELECTED_VIEW" ] && return

    toggle_view_auto_update "$SELECTED_DB" "$SELECTED_DESIGN" "$SELECTED_VIEW"
}

# Entry point: CLI mode or interactive mode
if [ "${1:-}" = "toggle" ] && [ $# -eq 4 ]; then
    toggle_view_auto_update "$2" "$3" "$4"
else
    load_databases
    while true; do
        run_toggle_view_menu || break
        sleep 1
    done
fi
```

- [ ] **Step 2: Make it executable**

```bash
chmod +x bin/design_auto_update
```

- [ ] **Step 3: Run the test in Docker**

```bash
docker compose up -d
# Wait for CouchDB to be ready
sleep 3
docker compose exec couchdb /usr/local/bin/test_toggle_view.sh
```

Expected output:
```
PASS: auto_update toggled to false
PASS: auto_update toggled back to true
ALL TESTS PASSED
```

- [ ] **Step 4: Commit**

```bash
git add bin/design_auto_update
git commit -m "Add bin/design_auto_update for toggling view auto_update"
```

---

## Chunk 2: Cleanup and config

### Task 4: Delete root copies and update config

**Files:**
- Delete: `./maintenance_mode`
- Delete: `./test_toggle_view.sh`
- Create: `.gitignore`
- Modify: `docker-compose.yml`
- Modify: `CLAUDE.md`

- [ ] **Step 1: Delete root copies**

```bash
git rm maintenance_mode
rm -f test_toggle_view.sh
```

Note: `maintenance_mode` is tracked by git so use `git rm`. `test_toggle_view.sh` is untracked so use plain `rm`.

- [ ] **Step 2: Create `.gitignore`**

```gitignore
.env
.maintenance_mode
.menu
.target_*
.db_menu
.design_menu
.view_menu
.tmp_design_doc
.design_doc
maintenance_mode.log
```

- [ ] **Step 3: Remove deprecated `version` from `docker-compose.yml`**

Delete line 1 (`version: "3.9"`) and the following blank line from `docker-compose.yml`.

- [ ] **Step 4: Update `CLAUDE.md`**

Replace the Architecture and Key Functions sections to reflect two scripts:

```markdown
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
```

Also update the Temp Files section to include the new temp files:

```markdown
## Temp Files

- `.maintenance_mode`: Stores raw API response
- `.menu`: Generated whiptail menu script
- `.target_node`/`.target_value`: Capture user selections from whiptail
- `.target_db`/`.target_design`/`.target_view`: Capture selections in design_auto_update
- `.db_menu`/`.design_menu`/`.view_menu`: Generated whiptail menu scripts for design_auto_update
- `.design_doc`/`.tmp_design_doc`: Design doc JSON for reading/updating
```

- [ ] **Step 5: Commit**

```bash
git add .gitignore docker-compose.yml CLAUDE.md
git commit -m "Delete root script copies, add .gitignore, update config and docs"
```

---

### Task 5: Final verification

- [ ] **Step 1: Verify `bin/maintenance_mode` runs in Docker**

```bash
docker compose exec couchdb /usr/local/bin/maintenance_mode
```

Verify the whiptail menu appears with node entries only (no toggle_view entry). Cancel out.

- [ ] **Step 2: Run the test suite again**

```bash
docker compose exec couchdb /usr/local/bin/test_toggle_view.sh
```

Expected: `ALL TESTS PASSED`

- [ ] **Step 3: Verify `bin/design_auto_update` interactive mode**

```bash
docker compose exec couchdb /usr/local/bin/design_auto_update
```

Verify the DB selection menu appears. Cancel out.
