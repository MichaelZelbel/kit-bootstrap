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
`kb_install_hermes` (what the reader-facing prereqs fetch since Batch AK),
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
| `steps/menerio.md` | whether to connect Menerio, then runs the one command that connects every assistant |

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

There are two front doors, one per kind of computer, and **they do the same job**:
look at the machine, then install or update without asking which is needed.

| File | Runs on | What it is |
|---|---|---|
| `windows/HubSetup.exe` | Windows | the front door: an ordinary installer, double-click it |
| `setup-hub.sh` | macOS, Linux | the front door: one command, the native way there |
| `join.ps1` / `join.sh` | both | the join-only half, and the library the two front doors call |

All of them are safe to run again and none ever deletes a memory.

**The front doors differ on purpose, and that is the whole point.** A terminal
command IS the native way to install software on macOS and Linux - Homebrew
installs itself exactly that way - and it is NOT the native way on Windows, where
people expect a file. Making both identical would mean annoying one group to
please the other. What is kept identical is the *promise*: one thing to run, no
decisions, it works out the rest.

Getting that wrong once already cost a day. On 2026-08-09 the Windows side gained
two abilities the bash side did not get: installing prerequisites, and creating a
hub from nothing. `join.sh` only ever joined, and stopped with an error when there
was no hub to join. So a Mac reader on a fresh machine got an error while a
Windows reader got a finished setup. The two halves are twins now, function for
function, and both test suites carry the same cases. **Change one, change the
other.**

## macOS and Linux: setup-hub.sh

```bash
curl -fsSL https://raw.githubusercontent.com/MichaelZelbel/kit-bootstrap/v1/setup-hub.sh | bash
```

Options, all optional, after `bash -s --`:

| Option | What it does |
|---|---|
| `--hub <path>` | where the hub is, or should go (default `~/hub`) |
| `--repo <git url>` | a hub you already keep somewhere, to fetch |
| `--starter-repo <url>` | the product whose starter folder a brand-new hub begins as |
| `--starter-path <name>` | the folder inside that repo (default `starter-hub`) |
| `--skip-prereqs` | install nothing, just wire it up |
| `--only menerio` | run the Menerio step and nothing else (see below) |
| `--only gmail` | run the guided Gmail step and nothing else (see below) |

A product points the last two at itself and ships a one-line wrapper under its own
name, the same way the `.exe` does. `teach-it-once-kit/install-hub.sh` is that
wrapper for the book.

**macOS is handled rather than assumed away.** `need_tools` only knows `apt-get`
and dies on anything else, which on a Mac is a wall, so `kb_install_one` picks apt
or brew by looking at the machine. Homebrew is deliberately **not** installed for
them: it is a large change that asks for their password, so they get the one line
and the reason instead of a surprise.

## Menerio: connect it once, and every assistant has it

Menerio is the author's online notebook, and it is optional. The installer asks
about it once, with "no" as the answer unless the reader says yes.

When the reader says yes, the installer stores the pasted key as `MENERIO_API_KEY`
in the locked store inside the hub (`secrets/hub-secrets.env.age`), makes it
available to programs on the computer, and then runs the kit's
`hub-menerio-connect`. That program reads the key from the store and gives Claude
Code, Hermes and Codex the same connection. Its one line for each assistant is
shown to the reader as it comes. Nobody is told to run `hermes mcp add` by hand any
more.

**The notebook and the copy of the hub are two choices, not one.** Two readers given
the chapter cold both refused to connect, because connecting quietly started copying
their whole hub, client notes and patient notes included, into an online account. So
after the assistants are connected the installer asks a second question, "Copy your
hub's files to Menerio for search?", and Enter means no. The answer is a fact about
one computer, so it is the line `HUB_NOTEBOOK_MIRROR=1` or `=0` in
`~/.hub/device.env`, and the kit's hourly runner obeys it in BOTH directions: after a
no, nothing is sent to Menerio and nothing is fetched from it in the background.

- A full install asks once for each computer. `--only menerio` asks again, with the
  last answer as the default, so a mind can be changed.
- `KB_NOTEBOOK_MIRROR=yes|no` answers without asking. With no keyboard and no answer
  it is no, and nothing is written, so the question is still there for the day
  somebody is at the keyboard.
- A computer that already had the hourly job before 2026-09-21 WAS copying. It is
  written down as 1 without being asked, and one line says so.
- The hub job (on save, and once an hour) is installed either way, because it also
  keeps the folder fresh from its repository and hands a replaced key to Hermes. Its
  lines never describe it as Menerio copying after a no.
- A job from an older copy of the kit never reads the setting. After anything but a
  yes it is not scheduled, and one scheduled earlier is taken out, with a line that
  says so. A no has to be a no.

**The passphrase is a question too.** A first connect used to end in "Choose a
passphrase", which locks this computer's key into the hub folder so a second computer
can open it. A reader with one computer does not need it. Now the installer asks "Set
a passphrase for a second computer now?", Enter means no, and a no is a finished
state: nothing warns about it on later runs. `--only menerio` offers it again.
`KB_NOTEBOOK_PASSPHRASE=skip|ask` answers without asking.

It runs on every road into the step: a key pasted a moment ago, a hub that was
connected already, and a second computer that has just typed its passphrase. So
running the installer again is also how an assistant installed later gets the
connection. A kit too old to have `hub-menerio-connect` still leaves Claude Code
its `.mcp.json`, and one line says what is missing.

`age`, the program that locks the key, is fetched at the moment a key needs
locking and not before. Most readers never connect Menerio, and they get nothing
installed for it.

**The way back in**, for the reader who said no on the day:

```bash
curl -fsSL https://raw.githubusercontent.com/MichaelZelbel/kit-bootstrap/v2/setup-hub.sh | bash -s -- --only menerio
```

```powershell
iwr https://raw.githubusercontent.com/MichaelZelbel/kit-bootstrap/v2/windows/setup-hub.ps1 -OutFile "$env:TEMP\setup-hub.ps1"
powershell -ExecutionPolicy Bypass -File "$env:TEMP\setup-hub.ps1" -Only menerio
```

It needs a hub already on the computer. It fetches the kit's programs and runs the
Menerio step, and it leaves everything else alone: no pull, no prerequisite check,
no re-wiring. `join.sh --only menerio` and `join.ps1 -Only menerio` do the same.
`KB_NOTEBOOK=skip` and `KB_NOTEBOOK_TOKEN` still answer the question without
asking, except that `--only menerio` ignores `skip`, because somebody who typed it
has asked to be asked. The HubSetup.exe wizard has no page for the single step.

`steps/menerio.md` is the sheet an assistant follows to walk somebody through it.

## Gmail: a step of the installer, and no command for the reader

Connecting Gmail is optional, and it works the same way for everyone: each person registers
their own small Google app once, in their own Google account. No shared app, and no connection
company in between. The reader never types a command for it.

- **When it asks.** Never on the day a hub is made. On a later run of the whole installer, which
  is what **Update my hub** in the Windows Start menu is, it asks `Connect Gmail now?` once, with
  no as the answer, and only while Gmail is not connected. `KB_GMAIL=skip` says no without asking.
- **The single step.** `--only gmail` (and `-Only gmail`) fetches the kit's programs, tells every
  assistant about the mail tool, and starts the guide. It does not ask whether.

```bash
curl -fsSL https://raw.githubusercontent.com/MichaelZelbel/kit-bootstrap/v2/setup-hub.sh | bash -s -- --only gmail
```

- **The words are not in this repository.** The guiding (which Google page to open, the one
  sentence about what to click there, the two hidden pastes, Google's Allow window, the mailbox
  question) is one program in the kit, `tools/hub-mail-guide.js`, and both installers start it.
  The Menerio step had its sentences in `lib.sh` and `join.ps1` and they drifted apart. What
  lives here is only what an installer knows: is somebody at the keyboard, is the tool on this
  computer, is `age` here to lock the connection away, and the one question. `test.sh` checks
  that neither installer carries a sentence of the guide.
- The connection is kept in the hub's locked store, so `age` is fetched when this step needs it,
  and a hub that never had a store gets one.

## Windows: HubSetup.exe

**This repository holds the source. It is not where anybody downloads it from.**

The built installer is published on the repository the reader is already sent to
by their book, which for *Teach It Once* is
[teach-it-once-kit](https://github.com/MichaelZelbel/teach-it-once-kit/releases/latest).

That split matters, and it is the same distinction as everywhere else here: where
the code lives is not the same question as where a person downloads from. This
repo's front page is about drift between four installers and rules for editing
`lib.sh`. It is written for whoever maintains the floor. A reader landing here to
run an unsigned `.exe` would find a page about somebody else's refactoring
problem, at the exact moment Windows is asking them to trust the file. The
product's own repository answers that question; this one cannot.

Download and double-click. There is nothing to type.

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

Publish it as a release asset on **the product's** repository, never as a file
committed here:

```powershell
gh release create v1.0.0 dist\HubSetup.exe --repo MichaelZelbel/teach-it-once-kit `
  --title "Windows installer v1.0.0" --notes "..."
```

A second kit that wants its own Windows installer builds from this same floor and
overrides two parameters, changing nothing else:

```powershell
# in that kit's own hub-setup.iss, on the [Run] line
-StarterRepo "https://github.com/MichaelZelbel/<their-kit>.git" -StarterPath "starter-hub"
```

Publish it on *their* repository under *their* name. One .exe per product, each
next to the book or kit that sends people to it, all built from this floor.

### Testing it

```powershell
cd windows
powershell -ExecutionPolicy Bypass -File test-windows.ps1
```

And the bash half, `bash test.sh`. **Run it on real Linux or a Mac, not only in
Git Bash on Windows.** Doing that for the first time on 2026-08-10 found two
things that had passed for months by luck: five cases assumed the machine had no
terminal, and hung forever on one that did; and twelve more were dropped by a
`jq` guard that printed nothing, so a machine without `jq` ran 12 fewer tests and
still said ALL PASS. Every skip announces itself now.

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
