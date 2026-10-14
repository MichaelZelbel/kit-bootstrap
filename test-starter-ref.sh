#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
source ./lib.sh
# The fixture checks bytes independently of the developer's checkout settings.
export GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=core.autocrlf GIT_CONFIG_VALUE_0=false
fixture=$(mktemp -d)
trap 'rm -rf "$fixture"' EXIT
repo="$fixture/source"
mkdir -p "$repo/starter-godspeed/skills/next-action"
git -C "$repo" init --quiet
printf 'release recipe\n' > "$repo/starter-godspeed/skills/next-action/SKILL.md"
kb_sha256_lf "$repo/starter-godspeed/skills/next-action/SKILL.md" > "$repo/starter-godspeed/skills/next-action/.shipped-sha256"
printf 'release starter\n' > "$repo/starter-godspeed/AGENTS.md"
git -C "$repo" add .
git -C "$repo" -c user.name=Fixture -c user.email=fixture@example.invalid commit --quiet -m release
release=$(git -C "$repo" rev-parse HEAD)
printf 'later recipe\n' > "$repo/starter-godspeed/skills/next-action/SKILL.md"
kb_sha256_lf "$repo/starter-godspeed/skills/next-action/SKILL.md" >> "$repo/starter-godspeed/skills/next-action/.shipped-sha256"
printf 'later starter\n' > "$repo/starter-godspeed/AGENTS.md"
git -C "$repo" add .
git -C "$repo" -c user.name=Fixture -c user.email=fixture@example.invalid commit --quiet -m later
unset GODSPEED_STARTER_REF
kb_copy_starter_godspeed "$fixture/default" "file://$repo"
grep -qx 'later recipe' "$fixture/default/skills/next-action/SKILL.md"
export GODSPEED_STARTER_REF="$release"
kb_copy_starter_godspeed "$fixture/pinned" "file://$repo"
grep -qx 'release recipe' "$fixture/pinned/skills/next-action/SKILL.md"
printf 'my edited recipe\n' > "$fixture/pinned/skills/next-action/SKILL.md"
printf 'my own instructions\n' > "$fixture/pinned/AGENTS.md"
kb_copy_starter_godspeed "$fixture/pinned" "file://$repo"
grep -qx 'my edited recipe' "$fixture/pinned/skills/next-action/SKILL.md"
grep -qx 'my own instructions' "$fixture/pinned/AGENTS.md"
for bad in main --help ffffffffffffffffffffffffffffffffffffffff; do
  export GODSPEED_STARTER_REF="$bad"
  if kb_copy_starter_godspeed "$fixture/rejected" "file://$repo"; then
    echo 'An invalid or unavailable starter pin was accepted.' >&2; exit 1
  fi
  test ! -e "$fixture/rejected"
done
echo 'Default and pinned starters, edited files, and rejected pins verified.'
