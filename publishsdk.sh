#!/usr/bin/env bash
set -euo pipefail

# publish_sdk.sh
# Helper script to prepare and publish the SDK to pub.dev.
# Usage: ./scripts/publish_sdk.sh [--non-interactive]

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# Operate from the SDK directory where this script lives.
SDK_DIR="$SCRIPT_DIR"
ROOT_DIR=$(cd "$SDK_DIR/.." && pwd)
cd "$SDK_DIR"

NONINTERACTIVE=0
if [ "${1-}" = "--non-interactive" ]; then
  NONINTERACTIVE=1
fi

echo "SDK publish script running from: $ROOT_DIR"

echo "1) Formatting code..."
if command -v dart >/dev/null 2>&1; then
  echo "Running: dart format ."
  dart format . || echo "dart format failed (continuing)"
elif command -v flutter >/dev/null 2>&1; then
  echo "Running: flutter format . (fallback)"
  if ! flutter format . >/dev/null 2>&1; then
    echo "Warning: 'flutter format' command not available on this Flutter installation. Skipping format step."
  fi
else
  echo "No 'dart' or 'flutter' executable found; skipping format step."
fi

echo "2) Static analysis..."
ANALYSIS_OUTPUT=$(flutter analyze 2>&1 || true)
echo "$ANALYSIS_OUTPUT"
echo "Note: Analyzer findings will not block the publish script (infos/warnings allowed)."


echo "3) Generating API docs (dart doc)..."
if command -v dart >/dev/null 2>&1; then
  echo "Running: dart doc ."
  if ! dart doc . 2>&1 | tee /dev/stderr; then
    echo "Warning: 'dart doc' failed to generate docs. The package validator may report missing documentation."
    # Continue but notify the user.
  else
    echo "dart doc completed."
  fi
else
  echo "'dart' not found; skipping 'dart doc' step."
fi


# Read package name and version from pubspec.yaml
PKG_NAME=$(awk -F":" '/^name:/{gsub(/ /, "", $2); print $2; exit}' "$SDK_DIR/pubspec.yaml" || true)
PKG_VERSION=$(awk -F":" '/^version:/{gsub(/ /, "", $2); print $2; exit}' "$SDK_DIR/pubspec.yaml" || true)

if [ -z "$PKG_NAME" ] || [ -z "$PKG_VERSION" ]; then
  echo "Unable to read package name or version from pubspec.yaml"; exit 1
fi

echo "Package: $PKG_NAME"
echo "Version: $PKG_VERSION"

echo "4) Dry-run publish (validates package)..."
DRYRUN_OUTPUT=$(flutter pub publish --dry-run 2>&1) || true
DRYRUN_EXIT=$?
echo "$DRYRUN_OUTPUT"
if [ $DRYRUN_EXIT -ne 0 ]; then
  # If the only validation issue is that files are modified in git, treat as warning and continue.
  if echo "$DRYRUN_OUTPUT" | grep -qi "checked-in files are modified in git\|Modified files:"; then
    echo "Warning: Dry-run reported modified files in git — treating as non-fatal."
    if [ "$NONINTERACTIVE" -eq 1 ]; then
      echo "Non-interactive mode: continuing despite dry-run modified-files warning."
    else
      read -p "Dry-run reported modified files in git. Proceed to publish anyway? (y/N): " yn
      case "$yn" in
        [Yy]*) echo "Proceeding despite modified-files warning." ;;
        *) echo "Publish cancelled."; exit 0 ;;
      esac
    fi
  else
    echo "Warning: Dry-run returned non-zero — validation reported warnings/errors."
    if [ "$NONINTERACTIVE" -eq 1 ]; then
      echo "Non-interactive mode: continuing despite dry-run failure."
    else
      read -p "Dry-run reported issues. Proceed to publish anyway? (y/N): " yn
      case "$yn" in
        [Yy]*)
          echo "Proceeding despite dry-run issues." ;;
        *)
          echo "Publish cancelled due to dry-run issues."; exit 0 ;;
      esac
    fi
  fi
else
  echo "Dry-run succeeded."
fi

echo "5) Publishing to pub.dev..."
flutter pub publish || { echo "Publish failed"; exit 1; }

echo "6) Tagging and pushing git tag v$PKG_VERSION..."
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  git add -A
  git commit -m "chore(release): $PKG_NAME@$PKG_VERSION" || true
  git tag -a "v$PKG_VERSION" -m "Release $PKG_NAME@$PKG_VERSION" || true
  git push origin --tags || true
else
  echo "Not a git repo, skipping tag/push."
fi

echo "Publish complete. Verify https://pub.dev/packages/$PKG_NAME"

exit 0
