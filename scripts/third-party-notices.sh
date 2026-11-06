#!/bin/zsh
# Regenerates THIRD_PARTY_NOTICES.md from the resolved Swift package dependencies.
set -euo pipefail
cd "$(dirname "$0")/.."
swift package resolve >/dev/null
OUT=THIRD_PARTY_NOTICES.md
{
  echo "# Third-party notices"
  echo
  echo "Dad Flow is licensed under the GNU GPL v3 (see LICENSE). The app bundles the"
  echo "following open-source packages, whose licenses are reproduced in full below."
  echo
  for d in .build/checkouts/*(/); do
    name=$(basename "$d")
    for f in "$d"/(LICENSE|LICENCE|COPYING)*(N.); do
      echo "---"
      echo
      echo "## $name"
      echo
      echo '```'
      cat "$f"
      echo '```'
      echo
    done
  done
} > "$OUT"
echo "wrote $OUT"
