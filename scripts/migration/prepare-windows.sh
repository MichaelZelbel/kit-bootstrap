#!/usr/bin/env bash
# Temporary public CI fixture routing. Signed URLs grant only these private asset downloads;
# no credential, old source, old installer or mirror is uploaded as a public run artifact.
set -euo pipefail
[ "${CI:-}" = true ] || { echo 'Run only on a throwaway CI machine.' >&2; exit 2; }
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
for name in RELEASE_COMMIT PRODUCT_COMMIT BOOTSTRAP_COMMIT; do
  [[ "${!name:-}" =~ ^[0-9a-f]{40}$ ]] || { echo "$name must name a full commit" >&2; exit 2; }
done
for name in SETUP_SHA256 MANIFEST_SHA256; do
  [[ "${!name:-}" =~ ^[0-9a-f]{64}$ ]] || { echo "$name must be a SHA256" >&2; exit 2; }
done
FIXTURES="$(cygpath -u "${RUNNER_TEMP:?}")/godspeed-migration-fixtures"
mkdir -p "$FIXTURES" "$ROOT/candidate" "$ROOT/evidence"
# curl prints no URL and no body. The secrets are short-lived URLs for individual immutable
# release assets, not account credentials. A failed/expired URL stops the run.
curl -fsSL "${PREVIOUS_SETUP_URL:?}" -o "$FIXTURES/GodspeedSetup.exe"
curl -fsSL "${PREVIOUS_MANIFEST_URL:?}" -o "$FIXTURES/windows-manifest.json"
curl -fsSL "${PREVIOUS_MIRROR_URL:?}" -o "$FIXTURES/product-previous.git.tar.gz"
(cd "$FIXTURES" && grep -v '  install-godspeed.sh$' "$ROOT/scripts/migration/fixture-sha256.txt" | sha256sum -c -)
tar -xzf "$FIXTURES/product-previous.git.tar.gz" -C "$FIXTURES"
OLD=69967129e488417d8d5acb42340363239427092a
MIRROR="$FIXTURES/product-previous.git"
[ "$(git -C "$MIRROR" rev-parse HEAD)" = "$OLD" ]
[ "$(git -C "$MIRROR" rev-list --count HEAD)" = 1 ]
git -C "$MIRROR" fsck --full
git -C "$MIRROR" update-ref refs/keep/previous "$OLD"
KIT=https://github.com/MichaelZelbel/godspeed-mission-control
git -C "$MIRROR" fetch --depth 50 "$KIT.git" "$RELEASE_COMMIT"
git -C "$MIRROR" update-ref refs/heads/main "$RELEASE_COMMIT"
git -C "$MIRROR" cat-file -e "$PRODUCT_COMMIT^{commit}"
git -C "$MIRROR" config uploadpack.allowAnySHA1InWant true
git -C "$MIRROR" config uploadpack.allowFilter true
native="$(cygpath -m "$MIRROR")"
url="file:///$native"
git config --global --add "url.$url.insteadOf" "$KIT.git"
git config --global --add "url.$url.insteadOf" "$KIT"
[ "$(git ls-remote "$KIT.git" HEAD | cut -f1)" = "$RELEASE_COMMIT" ]
echo "MIGRATION_FIXTURES=$(cygpath -m "$FIXTURES")" >> "$GITHUB_ENV"
echo "MIGRATION_MIRROR=$native" >> "$GITHUB_ENV"
base="https://raw.githubusercontent.com/MichaelZelbel/godspeed-mission-control/$RELEASE_COMMIT/installers"
curl -fsSL "$base/GodspeedSetup.exe" -o "$ROOT/candidate/GodspeedSetup.exe"
curl -fsSL "$base/windows-manifest.json" -o "$ROOT/candidate/windows-manifest.json"
printf '%s  %s\n%s  %s\n' "$SETUP_SHA256" "$ROOT/candidate/GodspeedSetup.exe" \
  "$MANIFEST_SHA256" "$ROOT/candidate/windows-manifest.json" | sha256sum -c -
node "$ROOT/scripts/migration/verify-candidate.mjs" "$ROOT/candidate/windows-manifest.json" "$PRODUCT_COMMIT" "$BOOTSTRAP_COMMIT"
{
  echo "Candidate release commit: $RELEASE_COMMIT"
  echo "Candidate runtime commit: $PRODUCT_COMMIT"
  echo "Candidate bootstrap commit: $BOOTSTRAP_COMMIT"
  echo "Previous original binary SHA256: 8b74f4fa038d799af05704b4270b127c05cd49dee5bdcbd3f54055f997a077a3"
  echo "Previous exact source commit: $OLD (one shallow commit; no ancestry)"
  echo 'Fixture routing: a local Git mirror serves both old and new starter commits.'
  echo 'Old fixtures are downloaded by temporary asset URLs; their bytes and URLs are never uploaded.'
  echo 'The previous installer and the candidate committed installer are unchanged.'
} | tee "$ROOT/evidence/provenance.txt"
