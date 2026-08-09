# kit-bootstrap

The parts every one of our installers was copying by hand, kept in one place.

Four installers existed before this repo — the Hermes, OpenClaw and Paperclip
DevOps Kits, and the AI-Native Company founding installer. Each carried its own
copy of the same startup code: coloured output, root-or-sudo, the apt install
loop, installing Claude Code, handing over to Claude at the end. They began as
copies of each other and drifted. By the time this repo was written, **212 of
309 lines differed between the Hermes copy and the OpenClaw copy**, and two
real bugs had grown in the gap: the Hermes reset script handed buyers the
*OpenClaw* installer link, and the Hermes installer still pinned version 1.0.4
while the folder beside it shipped 1.0.6.

This repo is the fix. It is MIT licensed and deliberately boring.

## What is in it

**`lib.sh`** — the bash. Output helpers, `sudo_cmd`, `need_tools`,
`ensure_claude_code`, `ensure_gh`, the two interactive sign-ins, the
root-to-normal-user handoff, and `handoff` to Claude Code with its headless
fallback.

**`steps/*.md`** — the questions. The wizard in these installers was never bash:
it is markdown that Claude Code reads after the bash finishes. That is the right
design and it stays. These are the steps that are the same for every product:

| File | Asks |
|---|---|
| `steps/github-repo.md` | which repository holds their folder, or makes one |
| `steps/llm-provider.md` | which LLM, and its key, without hardcoding the list |
| `steps/telegram.md` | the bot token, then finds the chat id itself |

Product-specific steps stay with the product. Only what is genuinely shared
lives here.

## Using it

Two ways, one source. Nothing is copied by hand in either.

**Runtime fetch** — for the free installers. One line at the top:

```bash
eval "$(curl -fsSL https://raw.githubusercontent.com/MichaelZelbel/kit-bootstrap/v1/lib.sh)"
```

A fix pushed to `v1` reaches every reader on their next run. Nothing is
republished, no gist is re-pasted.

One thing to know before you test a fix: **`raw.githubusercontent.com` caches a
branch URL for a few minutes.** Measured 2026-08-06, a push to `v1` took about
40 seconds to appear, and `Cache-Control: no-cache` did not bypass it. If you
need the new file *now*, request it by commit sha instead, which is never served
stale:

```bash
curl -fsSL "https://raw.githubusercontent.com/MichaelZelbel/kit-bootstrap/$(git rev-parse origin/v1)/lib.sh"
```

**Vendored at build time** — for the paid kits, which ship as one self-contained
offline tarball. Their `build.sh` already pins and copies two other repos in
(the OSS watchdog and the Chrome bridge); this is the same move with one more
source:

```bash
git clone --depth 1 --branch v1 https://github.com/MichaelZelbel/kit-bootstrap.git "$TMP/kb"
cp "$TMP/kb/lib.sh" "$STAGE/_shared/lib.sh"
cp -R "$TMP/kb/steps/." "$STAGE/_shared/steps/"
```

The buyer still gets one file that works offline. The source of truth is still
this repo.

## Branches

- **`v1`** — what consumers point at. Fixes only. Never a breaking change.
- **`main`** — development.
- **`v2`** — the next shape, when there is one. Consumers move to it deliberately,
  never by surprise.

A consumer that pins `v1` cannot be broken by work happening on `main`.

## Rules for editing `lib.sh`

It gets `eval`'d into somebody else's shell on a machine they just rented.

1. **Never `exit` at load time.** A `die` inside a function is fine. A `die` at
   the top level kills the caller before it has said anything.
2. **Never `set -e` / `set -u` / `set -o pipefail`.** That is the caller's
   decision, not this file's.
3. **Never print anything on load.** Loading is not an event anybody needs told.
4. **Keep the six short names** (`log`, `warn`, `die`, `ok`, `say`, `sudo_cmd`).
   They are what the four existing installers already call, so a kit can delete
   its local copy and change nothing else.
5. **`bash -n lib.sh` before every push.** A syntax error here breaks every
   installer that fetches it, on every machine, at once. That is the price of
   having one copy, and it is why the `v1` branch is fixes only.

## Two jobs, not two audiences: create and join

Every installer built on this floor answers one question: *build me a thing from
nothing.* That is the CREATE job, and it is the right one for a freshly rented
server. It is not the only job.

The other one is JOIN: *I already have a hub, this is another machine.* Until
2026-08-09 nothing here answered it. So the wiring was written once inside the
author's private repo, and a reader who bought a second laptop got nothing at
all. That is the same drift this repo exists to prevent, one level up: the split
had been made by AUDIENCE (author versus reader) when the real difference is the
JOB. So the join job lives here now and both sides call it.

| File | Runs on | What it does |
|---|---|---|
| `windows/HubSetup.exe` | Windows | **the front door.** An ordinary installer: double-click it |
| `join.sh` | Linux, macOS | joins this machine to a hub that already exists |
| `join.ps1` | Windows | the same as a script, for automation and for the .exe to call |

All of them are safe to run again and none ever deletes a memory.

```bash
# Linux / macOS
curl -fsSL https://raw.githubusercontent.com/MichaelZelbel/kit-bootstrap/v1/join.sh | bash -s -- ~/hub
```

## Windows: HubSetup.exe

Download it from the [latest release](https://github.com/MichaelZelbel/kit-bootstrap/releases/latest)
and double-click. There is nothing to type.

It works out which of the two jobs this PC needs by looking, and never by asking:

- **a hub is already here** → brings it up to date, re-checks the wiring
- **no hub here** → asks where to put one, and whether to fetch a repository you
  already have, then makes it

It also installs what is missing underneath: Git, Node.js and Claude Code.

Why an .exe rather than the one-line command that used to be the answer: the
command was fine for whoever wrote it and a wall for everybody else, and
everybody else is who the book is for. Nobody else's software asks a person to
paste a line of PowerShell.

**It asks for no administrator rights of its own.** That is correctness rather
than manners. Elevating puts the process in a different account, and the
shared-memory link would then be written into the wrong user's profile while
still reporting success. Windows raises its own prompt when it installs Git or
Node.js, which is separate and normal.

### The warning Windows will show, and why

The first time anybody runs it, Windows says **"Windows protected your PC"** and
offers only a *Don't run* button. Click **More info**, then **Run anyway**.

This is Microsoft SmartScreen, and it is not a virus warning. It appears on every
program from a publisher it has not seen enough copies of. The only thing that
removes it is a code-signing certificate, which costs a few hundred euros a year
from a certificate authority. Until there is one, that click is the price, and
telling readers about it up front is better than letting it frighten them.

### Building it

```powershell
cd windows
powershell -ExecutionPolicy Bypass -File build-installer.ps1   # -> dist\HubSetup.exe
```

The compiler is [Inno Setup](https://jrsoftware.org/isinfo.php), free, and the
build script fetches it if the PC has not got it.

Publish it as a release asset, never as a file in the repository:

```powershell
gh release create v1.0.0 dist\HubSetup.exe --repo MichaelZelbel/kit-bootstrap `
  --title "Hub installer v1.0.0" --notes "..."
```

### Testing it

```powershell
cd windows
powershell -ExecutionPolicy Bypass -File test-windows.ps1
```

**Run that under Windows PowerShell 5.1 at least once, not only under 7.** The
.exe runs 5.1, and the first two bugs the suite ever caught were both "works in
7, throws in 5.1": `Set-Content -Encoding utf8NoBOM` does not exist in 5.1, and
5.1 still asks for a version of TLS that GitHub refuses. That is the shape of bug
which reaches every reader and never the author.

To test the installer itself without a wizard appearing:

```powershell
.\dist\HubSetup.exe /VERYSILENT /SUPPRESSMSGBOXES
type "$env:LOCALAPPDATA\Hub\setup-log.txt"
```

### What joining actually does

It points the AI tool's private memory folder at `memory/` inside the hub.

An AI assistant keeps what it learns about you in a folder belonging to the
TOOL, on ONE machine. Nothing else can read it: not your other assistants, not
your other computers. Linking that folder into the hub makes one memory that
every machine and every assistant shares, carried by the same git sync that
already carries the rest of the folder. `kb_link_ai_memory` is the function;
`join.sh` and `join.ps1` are the two front doors to it.

It never deletes anything. Notes already in the old place are copied into the
hub first, and the old folder is kept with a timestamp on it. A link left
pointing at a hub that has moved is repaired rather than reported as fine, which
is the failure that otherwise looks exactly like success.

## Why not just put this inside the Hermes kit

Because that kit's installer exists to fetch a paid tarball with its fingerprint
checked. Anything built on top of it inherits a dependency on a paid download
and a private repository. The shared piece belongs *underneath* all four
products, not inside one of them.
