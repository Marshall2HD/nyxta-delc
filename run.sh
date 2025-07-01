# run.sh
#!/usr/bin/env sh
set -eu

REPO="https://raw.githubusercontent.com/Marshall2HD/nyxta-delc/refs/heads/main"
SCRIPT_PATH="templates/scripts/bootstrap.sh"

for arg in "$@"; do
  case "$arg" in
    --simple) SCRIPT_PATH="templates/scripts/simple.sh" ;;
    --help|-h)
      echo "Usage: curl -fsSL https://nyxta.run | sh -s -- [--simple] [additional-args]"
      exit 0 ;;
  esac
done

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT INT TERM

SCRIPT_NAME=$(basename "$SCRIPT_PATH")

echo "→ downloading $SCRIPT_NAME"
curl -fsSL "$REPO/$SCRIPT_PATH"        -o "$TMP/$SCRIPT_NAME"

echo "→ executing $SCRIPT_NAME"
cd "$TMP"
exec sh "$TMP/$SCRIPT_NAME" "$@"