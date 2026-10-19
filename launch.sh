#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/launch_lib.sh
source "$SCRIPT_DIR/lib/launch_lib.sh"

: "${CONFIG_DIR:=$SCRIPT_DIR/configvolumes}"
: "${OUTPUT_DIR:=$SCRIPT_DIR/outputlogs}"

main "$@"
