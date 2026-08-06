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

## Why not just put this inside the Hermes kit

Because that kit's installer exists to fetch a paid tarball with its fingerprint
checked. Anything built on top of it inherits a dependency on a paid download
and a private repository. The shared piece belongs *underneath* all four
products, not inside one of them.
