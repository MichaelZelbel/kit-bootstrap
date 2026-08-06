#!/usr/bin/env bash
# =============================================================================
# publish-kit.sh — put a built kit in front of buyers, in one command.
#
#   bash publish-kit.sh <tarball> <gist-id> <install.sh> [token-dir]
#
# e.g.
#   bash publish-kit.sh dist/hermes-ops-kit-v1.0.7.tar.gz \
#        fec343846a03592daaa083bf061f5e36 dist/install.sh 1cab1053c45c1aaaa0bafdcb
#
# WHY THIS EXISTS
#
# Publishing a kit used to be four things done by hand: build the tarball,
# upload it, edit install.sh, and paste install.sh into a public gist. Every one
# of those is a copy, and copies drift. By 2026-08-06 all three kits had drifted
# somewhere:
#
#   - the Hermes reset script sent buyers to the OPENCLAW installer
#   - the Hermes install.sh in git was pinned to v1.0.4 while the gist and the
#     download were on v1.0.6, so the next release would have pasted the old
#     fingerprint back over a working gist and broken every buyer
#   - the OpenClaw install.sh in git named v1.10.16 with a fingerprint for a
#     tarball that existed nowhere; the live product was v1.10.15
#
# None of those were visible from inside the repo, because the repo was never
# the thing buyers touched. So this script does all four steps from one source
# of truth, and then CHECKS THE BUYER'S PATH: it downloads from the published
# URL and compares the fingerprint to what the published gist demands. If those
# two disagree, buyers are broken, and it says so and exits non-zero.
#
# It is safe to run twice.
# =============================================================================

set -euo pipefail

# --check walks the buyer's path and changes NOTHING. Use it to answer "are my
# customers fine right now?" without cutting a release. Publishing repairs drift
# as a side effect, which is right for a release and useless as an alarm: on
# 2026-08-06 all three kits had drifted and nothing had noticed for weeks,
# because the only way to look was to publish.
#
#   bash publish-kit.sh --check <gist-id>
#
CHECK_ONLY=0
if [ "${1:-}" = "--check" ]; then
  CHECK_ONLY=1
  GIST_ID="${2:?usage: publish-kit.sh --check <gist-id>}"
fi

if [ "$CHECK_ONLY" -eq 0 ]; then
  TARBALL="${1:?usage: publish-kit.sh <tarball> <gist-id> <install.sh> [token-dir]}"
  GIST_ID="${2:?missing gist id}"
  INSTALL_SH="${3:?missing path to install.sh}"
  TOKEN_DIR="${4:-}"
fi

HOST="${KIT_HOST:-root@srv1328602.hstgr.cloud}"
KEY="${KIT_SSH_KEY:-$HOME/hub/.secrets/claude-desktop_ed25519}"
ROOT="${KIT_ARTIFACT_ROOT:-/srv/hub-artifacts/kits}"
BASE="${KIT_BASE_URL:-https://srv1328602.hstgr.cloud/hub/kits}"

log()  { printf "\033[1;34m[publish]\033[0m %s\n" "$*"; }
die()  { printf "\033[1;31m[stop]\033[0m %s\n" "$*" >&2; exit 1; }

command -v gh >/dev/null || die "The GitHub CLI is needed to read the gist."

# --- check mode: read the live state, touch nothing -------------------------
if [ "$CHECK_ONLY" -eq 1 ]; then
  GIST_FILE="$(gh api "gists/$GIST_ID" --jq '.files | keys[0]')"
  LIVE="$(gh api "gists/$GIST_ID" --jq ".files[\"$GIST_FILE\"].content")"
  LIVE_URL="$(printf '%s' "$LIVE" | sed -n 's/^KIT_URL="\([^"]*\)".*/\1/p')"
  LIVE_SHA="$(printf '%s' "$LIVE" | sed -n 's/^EXPECTED_SHA="\([a-f0-9]*\)".*/\1/p')"
  LIVE_VER="$(printf '%s' "$LIVE" | sed -n 's/^KIT_VERSION="\([^"]*\)".*/\1/p')"
  echo "  gist     : $GIST_ID ($GIST_FILE), version $LIVE_VER"
  echo "  demands  : ${LIVE_SHA:0:16}..."
  echo "  downloads: $LIVE_URL"
  [ -n "$LIVE_URL" ] || die "The published installer names no download URL."
  TMP="$(mktemp)"
  curl -fsSL -o "$TMP" "$LIVE_URL" 2>/dev/null || { rm -f "$TMP"; die "BUYERS BROKEN: that URL does not download."; }
  if ! file "$TMP" | grep -q 'gzip compressed'; then
    rm -f "$TMP"; die "BUYERS BROKEN: that URL serves something that is not a tarball (an interstitial page?)."
  fi
  GOT="$(sha256sum "$TMP" | awk '{print $1}')"; rm -f "$TMP"
  [ "$GOT" = "$LIVE_SHA" ] || die "BUYERS BROKEN: the download is $GOT but the installer demands $LIVE_SHA.
   Every install aborts with a security warning until these agree."
  log "Buyers are fine: the published installer and the published download agree."
  exit 0
fi

[ -f "$TARBALL" ]    || die "No tarball at $TARBALL"
[ -f "$INSTALL_SH" ] || die "No install.sh at $INSTALL_SH"

SSH_OPTS=(-o BatchMode=yes -o StrictHostKeyChecking=no -i "$KEY")
FILE="$(basename "$TARBALL")"
SHA="$(sha256sum "$TARBALL" | awk '{print $1}')"

# The path segment is what keeps the download unlisted, the same way the
# existing `hub publish` mechanism does. Reuse the kit's own segment across
# releases so old links keep working; a new one is only for a new kit.
if [ -z "$TOKEN_DIR" ]; then
  TOKEN_DIR="$(openssl rand -hex 12)"
  log "New unlisted path segment for this kit: $TOKEN_DIR"
fi
URL="$BASE/$TOKEN_DIR/$FILE"

log "Uploading $FILE ($(wc -c < "$TARBALL") bytes)"
ssh "${SSH_OPTS[@]}" "$HOST" "mkdir -p '$ROOT/$TOKEN_DIR'"
scp -q "${SSH_OPTS[@]}" "$TARBALL" "$HOST:$ROOT/$TOKEN_DIR/"
ssh "${SSH_OPTS[@]}" "$HOST" "chmod -R a+rX '$ROOT/$TOKEN_DIR'"

log "Pointing $INSTALL_SH at it"
sed -i "s|^KIT_URL=.*|KIT_URL=\"$URL\"|"        "$INSTALL_SH"
sed -i "s|^EXPECTED_SHA=.*|EXPECTED_SHA=\"$SHA\"|" "$INSTALL_SH"
bash -n "$INSTALL_SH" || die "install.sh no longer parses after the edit."
printf '%s *%s\n' "$SHA" "$FILE" > "$(dirname "$TARBALL")/${FILE%.tar.gz}.sha256"

log "Publishing install.sh to gist $GIST_ID"
GIST_FILE="$(gh api "gists/$GIST_ID" --jq '.files | keys[0]')"
gh gist edit "$GIST_ID" -f "$GIST_FILE" "$INSTALL_SH" >/dev/null

# ---------------------------------------------------------------------------
# The only check that means anything: walk the buyer's path.
# Everything above can succeed while the buyer is still broken.
# ---------------------------------------------------------------------------
log "Checking what a buyer actually gets"
LIVE="$(gh api "gists/$GIST_ID" --jq ".files[\"$GIST_FILE\"].content")"
LIVE_URL="$(printf '%s' "$LIVE" | sed -n 's/^KIT_URL="\([^"]*\)".*/\1/p')"
LIVE_SHA="$(printf '%s' "$LIVE" | sed -n 's/^EXPECTED_SHA="\([a-f0-9]*\)".*/\1/p')"

[ "$LIVE_URL" = "$URL" ] || die "The gist points at $LIVE_URL, not the file just uploaded."
[ "$LIVE_SHA" = "$SHA" ] || die "The gist expects $LIVE_SHA, but the file is $SHA."

TMP="$(mktemp)"
curl -fsSL -o "$TMP" "$LIVE_URL" || { rm -f "$TMP"; die "The published URL does not download: $LIVE_URL"; }
file "$TMP" | grep -q 'gzip compressed' || { rm -f "$TMP"; die "The published URL served something that is not a tarball."; }
GOT="$(sha256sum "$TMP" | awk '{print $1}')"
rm -f "$TMP"
[ "$GOT" = "$LIVE_SHA" ] || die "A buyer would download $GOT but the installer demands $LIVE_SHA."

log "Published and verified end to end."
echo
echo "  version fingerprint : $SHA"
echo "  download            : $URL"
echo "  buyers run          : curl -fsSL \"https://gist.githubusercontent.com/MichaelZelbel/$GIST_ID/raw/$GIST_FILE\" | bash"
echo "  path segment (reuse it for the next release of this kit): $TOKEN_DIR"
