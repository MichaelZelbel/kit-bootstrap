#!/usr/bin/env bash
# Offline integration of the CI preparation, with real Git mirrors and cached private fixtures.
# It never installs anything or changes the user's global Git settings.
# Usage: bash scripts/migration/test-prepare-windows.sh /private/upgrade-fixtures
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
FIXTURE_SOURCE="$(cd "${1:?private fixture directory}" && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/project/scripts/migration" "$TMP/bin" "$TMP/runtime" "$TMP/new-product"
cp "$HERE/prepare-windows.sh" "$HERE/verify-candidate.mjs" "$HERE/fixture-sha256.txt" "$TMP/project/scripts/migration/"
REAL_GIT="$(command -v git)"
git -C "$TMP/new-product" init -q
printf 'clean new product\n' > "$TMP/new-product/README.md"
git -C "$TMP/new-product" add README.md
git -C "$TMP/new-product" -c user.name=Fixture -c user.email=fixture@example.invalid commit -qm clean
PRODUCT_COMMIT="$(git -C "$TMP/new-product" rev-parse HEAD)"
RELEASE_COMMIT="$PRODUCT_COMMIT"
BOOTSTRAP_COMMIT=2222222222222222222222222222222222222222
printf 'exact candidate installer bytes\n' > "$TMP/candidate.exe"
printf '{"kitCommit":"%s","bootstrapCommit":"%s","version":"2.0.0-beta.1"}\n' "$PRODUCT_COMMIT" "$BOOTSTRAP_COMMIT" > "$TMP/manifest.json"
SETUP_SHA256="$(sha256sum "$TMP/candidate.exe" | cut -d' ' -f1)"
MANIFEST_SHA256="$(sha256sum "$TMP/manifest.json" | cut -d' ' -f1)"
cat > "$TMP/bin/curl" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
case "$2" in
  fixture:setup) source="$FIXTURE_SOURCE/GodspeedSetup.exe" ;;
  fixture:manifest) source="$FIXTURE_SOURCE/windows-manifest.json" ;;
  fixture:mirror) source="$FIXTURE_SOURCE/product-previous.git.tar.gz" ;;
  */installers/GodspeedSetup.exe) source="$TEST_TMP/candidate.exe" ;;
  */installers/windows-manifest.json) source="$TEST_TMP/manifest.json" ;;
  *) echo 'Unexpected fixture request' >&2; exit 22 ;;
esac
[ "$1" = -fsSL ] && [ "$3" = -o ] && [ "$#" = 4 ]
cp "$source" "$4"
SH
cat > "$TMP/bin/git" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
args=("$@")
# Only candidate network fetching is stood in. All hashes, object checks and URL rewriting
# still use real Git. The private old mirror is unpacked unchanged from its checked archive.
if [ "${args[2]:-}" = fetch ] && [ "${args[4]:-}" = 50 ]; then
  for i in "${!args[@]}"; do
    if [ "${args[$i]}" = https://github.com/MichaelZelbel/godspeed-mission-control.git ]; then
      args[$i]="$TEST_TMP/new-product"
    fi
  done
fi
exec "$REAL_GIT" "${args[@]}"
SH
chmod +x "$TMP/bin/curl" "$TMP/bin/git"
export REAL_GIT FIXTURE_SOURCE TEST_TMP="$TMP" PRODUCT_COMMIT RELEASE_COMMIT BOOTSTRAP_COMMIT SETUP_SHA256 MANIFEST_SHA256
export CI=true RUNNER_TEMP="$TMP/runtime" GITHUB_ENV="$TMP/github-env" GITHUB_PATH="$TMP/github-path"
export GIT_CONFIG_GLOBAL="$TMP/gitconfig" PREVIOUS_SETUP_URL=fixture:setup PREVIOUS_MANIFEST_URL=fixture:manifest PREVIOUS_MIRROR_URL=fixture:mirror
export PATH="$TMP/bin:$PATH"
bash "$TMP/project/scripts/migration/prepare-windows.sh"
mirror="$TMP/runtime/godspeed-migration-fixtures/product-previous.git"
[ "$(git -C "$mirror" rev-parse HEAD)" = "$PRODUCT_COMMIT" ]
old=69967129e488417d8d5acb42340363239427092a
git -C "$mirror" cat-file -e "$old^{commit}"
mkdir "$TMP/reader"
git -C "$TMP/reader" init -q
for ref in "$old" "$PRODUCT_COMMIT"; do
  git -C "$TMP/reader" fetch -q --depth 1 https://github.com/MichaelZelbel/godspeed-mission-control.git "$ref"
  [ "$(git -C "$TMP/reader" rev-parse FETCH_HEAD)" = "$ref" ]
done
test "$(find "$TMP/project/evidence" -type f | wc -l | tr -d ' ')" = 1
test -f "$TMP/project/evidence/provenance.txt"
echo 'ok: exact old and unrelated new commits both fetch through the same rewritten product URL'
echo 'ok: candidate artifact bytes and manifest pins verified; evidence contains provenance only'
echo 'all Windows fixture preparation checks passed'
