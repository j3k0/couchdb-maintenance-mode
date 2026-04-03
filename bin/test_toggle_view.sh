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
