#!/usr/bin/env bash
# repub-tag.sh — Re-publish a version tag.
#
# If the tag already exists, this script:
#   1. Deletes the tag from local and remote.
#
# It then recreates the tag locally and pushes it to the remote, which triggers
# the CI build workflow for a clean re-publish.
#
# Usage:
#   ./scripts/repub-tag.sh [--sign] [-u <keyid>] <tag>
#
# Options:
#   --sign, -s      GPG-sign the new tag
#   -u <keyid>      Use the specified GPG key (implies --sign)
#
# Environment:
#   REMOTE     Git remote name (default: origin)
#   SIGN_TAG   Set to 1 to sign the tag (alternative to --sign)
#   SIGN_KEY   GPG key ID or fingerprint to use for signing

set -euo pipefail

# ── arguments ────────────────────────────────────────────────────────────────

SIGN_TAG="${SIGN_TAG:-0}"
SIGN_KEY="${SIGN_KEY:-}"
TAG=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --sign|-s)
      SIGN_TAG=1
      shift
      ;;
    -u)
      SIGN_TAG=1
      SIGN_KEY="${2:-}"
      if [[ -z "$SIGN_KEY" ]]; then
        echo "Error: -u requires a key ID argument" >&2
        exit 1
      fi
      shift 2
      ;;
    -*)
      echo "Unknown option: $1" >&2
      echo "Usage: $0 [--sign] [-u <keyid>] <tag>" >&2
      exit 1
      ;;
    *)
      TAG="$1"
      shift
      ;;
  esac
done

if [[ -z "$TAG" ]]; then
  echo "Usage: $0 [--sign] [-u <keyid>] <tag>" >&2
  exit 1
fi

REMOTE="${REMOTE:-origin}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)"

cd "$REPO_ROOT"

# ── pre-flight checks ────────────────────────────────────────────────────────

# Solid release tags (vX.Y.Z with no suffix) must be signed.
if [[ "$TAG" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] && [[ "$SIGN_TAG" != "1" ]]; then
  echo "Error: solid release tag '$TAG' must be signed. Use --sign or -u <keyid>." >&2
  exit 1
fi

if ! git diff --quiet || ! git diff --cached --quiet; then
  echo "Error: there are uncommitted changes. Commit or stash them before re-publishing." >&2
  exit 1
fi

# ── helpers ───────────────────────────────────────────────────────────────────

local_tag_exists()  { git rev-parse "refs/tags/$1" &>/dev/null; }
remote_tag_exists() { git ls-remote --exit-code --tags "$REMOTE" "refs/tags/$1" &>/dev/null; }

# ── 1. Remove local tag if it exists ─────────────────────────────────────────

if local_tag_exists "$TAG"; then
  echo "==> Deleting local tag '$TAG'"
  git tag -d "$TAG"
fi

# ── 2. Create the new local tag (before touching the remote) ─────────────────

if [[ "$SIGN_TAG" == "1" ]]; then
  if [[ -n "$SIGN_KEY" ]]; then
    echo "==> Creating signed local tag '$TAG' (key: $SIGN_KEY)"
    git tag -s -u "$SIGN_KEY" "$TAG"
  else
    echo "==> Creating signed local tag '$TAG' (default GPG key)"
    git tag -s "$TAG"
  fi
else
  echo "==> Creating local tag '$TAG'"
  git tag "$TAG"
fi

# ── 3. Remove remote tag and push (only reached if local tag succeeded) ───────

if remote_tag_exists "$TAG"; then
  echo "==> Deleting remote tag '$TAG'"
  git push "$REMOTE" ":refs/tags/$TAG"
fi

echo "==> Pushing tag '$TAG' to '$REMOTE'"
git push "$REMOTE" "$TAG"

echo "==> Done — CI will now build a fresh release for '$TAG'"
