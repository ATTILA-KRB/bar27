#!/bin/bash
# Notarise puis installe dans /Applications ce Mac.
set -euo pipefail
cd "$(dirname "$0")/.."
scripts/notarize.sh
scripts/install.sh --no-build
