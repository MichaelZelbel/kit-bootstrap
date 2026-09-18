#!/usr/bin/env bash
# Full desktop setup in a disposable hosted account; no gateway credentials or messages.
set -euo pipefail
[[ ${GITHUB_ACTIONS:-} == true ]] || { echo 'Requires a disposable hosted runner.' >&2; exit 1; }
route=${1:?fresh or upgrade}
[[ $route == fresh || $route == upgrade ]]
[[ ! -e "$HOME/hub" ]]
mkdir -p journey-evidence
git config --global user.name 'Example Reader'
git config --global user.email 'reader@example.org'
if [[ $(uname) == Darwin ]]; then
  client_dir="$HOME/Library/Application Support/Hermes"
else
  client_dir="$HOME/.config/Hermes"
fi
mkdir -p "$client_dir"
printf '%s' '{"version":2,"connections":[{"kind":"ssh","host":"example.org","token":"fictional-reader-token"}]}' > "$client_dir/connections.json"
cp "$client_dir/connections.json" journey-evidence/connection-before.json
if [[ $route == upgrade ]]; then
  curl -fsSL 'https://raw.githubusercontent.com/MichaelZelbel/kit-bootstrap/v2.7/setup-hub.sh' -o journey-evidence/baseline.sh
  KB_BRANCH=v2.7 bash journey-evidence/baseline.sh --hub "$HOME/hub" --skip-prereqs --sources= </dev/null >journey-evidence/baseline.log 2>&1
  [[ -f "$HOME/hub/AGENTS.md" ]]
  printf '%s' 'Keep this personal note exactly.' > "$HOME/hub/reader-note.txt"
fi
revision=$(git rev-parse HEAD)
curl -fsSL "https://raw.githubusercontent.com/MichaelZelbel/kit-bootstrap/$revision/setup-hub.sh" -o journey-evidence/candidate.sh
cmp setup-hub.sh journey-evidence/candidate.sh
KB_BRANCH="$revision" bash journey-evidence/candidate.sh --hub "$HOME/hub" --skip-prereqs --sources= </dev/null >journey-evidence/candidate.log 2>&1
[[ -f "$HOME/hub/AGENTS.md" ]]
cmp journey-evidence/connection-before.json "$client_dir/connections.json"
if [[ $route == upgrade ]]; then
  [[ $(cat "$HOME/hub/reader-note.txt") == 'Keep this personal note exactly.' ]]
fi
node -e 'const s=require(process.argv[1]);if(s.state!=="remote_update_pending"||!s.notice.includes("not checked"))process.exit(1)' "$HOME/.hub/chat/setup-status.json"
cp "$HOME/.hub/chat/setup-status.json" journey-evidence/setup-status.json
if KB_BRANCH="$revision" KB_TOOLS_REF=invalid-fixture-ref bash journey-evidence/candidate.sh --hub "$HOME/hub" --skip-prereqs --sources= </dev/null >journey-evidence/failed-update.log 2>&1; then
  echo 'Invalid update incorrectly reported success.' >&2; exit 1
fi
echo "PASS: downloaded $route setup; remote status explicit; personal data preserved; failure surfaced."
