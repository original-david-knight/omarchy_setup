#!/bin/sh

extensions_file="$(dirname "$0")/vscode/extensions.txt"

if ! command -v code >/dev/null 2>&1; then
  echo "VS Code not found; skipping extension install."
  exit 0
fi

if [ ! -f "$extensions_file" ]; then
  echo "Missing $extensions_file; skipping extension install."
  exit 0
fi

while IFS= read -r extension; do
  case "$extension" in
    ""|\#*) continue ;;
  esac
  code --install-extension "$extension" --force
done < "$extensions_file"
