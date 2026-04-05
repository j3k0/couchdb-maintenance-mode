#!/usr/bin/env bash
set -euo pipefail

COUCH_URL="${COUCH_URL:-http://admin:admin@localhost:5984}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

DB="testdb_$$"
DESIGN_DOC="_design/example"

do_curl() { curl -s -H "Content-type: application/json" "$@"; }

cleanup() {
    do_curl -X DELETE "$COUCH_URL/$DB" > /dev/null 2>&1 || true
}
trap cleanup EXIT

# Setup: create DB and design doc with auto_update: true (at doc level)
do_curl -X PUT "$COUCH_URL/$DB" > /dev/null
do_curl -X PUT "$COUCH_URL/$DB/$DESIGN_DOC" \
    -d "{\"_id\": \"$DESIGN_DOC\", \"language\": \"javascript\", \"views\": {\"myview\": {\"map\": \"function(doc){emit(doc._id,null);\"}}, \"options\": {\"auto_update\": true}}" > /dev/null

# Test 1: set to false via CLI
COUCH_URL="$COUCH_URL" "$SCRIPT_DIR/design_auto_update" set "$DB" "$DESIGN_DOC" false

ACTUAL=$(do_curl "$COUCH_URL/$DB/$DESIGN_DOC" | jq -r '.options.auto_update')
if [ "$ACTUAL" != "false" ]; then
    echo "FAIL: expected auto_update=false, got auto_update=$ACTUAL"
    exit 1
fi
echo "PASS: auto_update set to false"

# Test 2: set to true via CLI
COUCH_URL="$COUCH_URL" "$SCRIPT_DIR/design_auto_update" set "$DB" "$DESIGN_DOC" true

ACTUAL=$(do_curl "$COUCH_URL/$DB/$DESIGN_DOC" | jq -r '.options.auto_update')
if [ "$ACTUAL" != "true" ]; then
    echo "FAIL: expected auto_update=true, got auto_update=$ACTUAL"
    exit 1
fi
echo "PASS: auto_update set to true"

# Test 3: toggle via CLI
COUCH_URL="$COUCH_URL" "$SCRIPT_DIR/design_auto_update" toggle "$DB" "$DESIGN_DOC"

ACTUAL=$(do_curl "$COUCH_URL/$DB/$DESIGN_DOC" | jq -r '.options.auto_update')
if [ "$ACTUAL" != "false" ]; then
    echo "FAIL: expected auto_update=false after toggle, got auto_update=$ACTUAL"
    exit 1
fi
echo "PASS: toggle flipped true -> false"

echo "ALL TESTS PASSED"
