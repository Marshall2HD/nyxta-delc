# run.sh
#!/usr/bin/env sh
set -eu

REPO="https://raw.githubusercontent.com/Marshall2HD/nyxta-delc/refs/heads/main/"
SCRIPT="templates/scripts/bootstrap.sh"

for arg in "$@"; do
  case "$arg" in
    --simple) SCRIPT="simple.sh" ;;
    --help|-h)
      echo "Usage: curl -fsSL https://nyxta.run | sh -s -- [--simple] [additional-args]"
      exit 0 ;;
  esac
done

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT INT TERM

echo "→ downloading $SCRIPT"
curl -fsSL "$REPO/$SCRIPT"        -o "$TMP/$SCRIPT"
curl -fsSL "$REPO/$SCRIPT.sha256" -o "$TMP/$SCRIPT.sha256"

echo "→ verifying checksum"
cd "$TMP"
sha256sum -c "$SCRIPT.sha256"

echo "→ executing $SCRIPT"
exec sh "$TMP/$SCRIPT" "$@"