# Step — Which LLM Hermes should use, and its key

Lifted from the Hermes DevOps Kit's own installer playbook, which is where this
text was proven. Two changes only: the wording is consumer-neutral, and the
report lines say "tell them" instead of naming that kit's report format.

Hermes is provider-agnostic. **Do NOT assume Anthropic.** At the time of writing
it supports Anthropic, OpenAI, Google (Gemini), Hugging Face, Mistral, Groq,
Together, OpenRouter and others, plus any OpenAI-compatible endpoint (Kimi via
Moonshot, a local Ollama, a corporate gateway) through a custom base URL. Many
people explicitly do not want Anthropic.

## The confusion to head off before it happens

Someone will say *"but Claude Code is already running here and I never entered a
key."* That is correct, and it is a different thing. Say so in one sentence:

- **Claude Code's sign-in** is what authenticates this setup conversation. It
  was done in the installer's first phase, against their Claude subscription.
- **Hermes's provider key** is for the messages Hermes itself will answer, later,
  from their phone. That is what this step is asking for.

The two are independent. Make the distinction explicit the moment it comes up.

## 1 — Look up which providers THIS build supports

Never hardcode the list. It changes.

```bash
hermes setup --help 2>&1 | grep -E '^\s+--[a-z-]+-api-key' | head -20
```

Typical output:

```text
  --anthropic-api-key <key>      Anthropic API key
  --openai-api-key <key>         OpenAI API key
  --google-api-key <key>         Google (Gemini) API key
  --mistral-api-key <key>        Mistral API key
  --groq-api-key <key>           Groq API key
  --openrouter-api-key <key>     OpenRouter API key (gateway to many models)
```

Capture that list. Do not use anything remembered from a previous build.

## 2 — Ask which one, building the menu from what you just read

Multiple choice is right here: it is a discrete list.

**The list comes from `--help`, not from what you happen to know.** The supported
providers, the exact flag names and the sign-in shapes all change, and most
providers have several sub-plans and endpoints. **Do not editorialise** about
which is "best", "most common" or "the usual pick". You will be wrong, and they
know their own setup better than you do.

Build the question mechanically:

1. Take the `--*-api-key` flags from step 1.
2. Strip `--` and `-api-key` to get the name (`--anthropic-api-key` → `anthropic`).
3. Show each one named exactly what Hermes named it. No commentary about plans,
   key formats or what a provider is good at.
4. Add two more options at the end:
   - **Other** — for OpenAI-compatible endpoints (Kimi/Moonshot direct, a local
     Ollama, regional variants, corporate gateways). You will ask for a base URL too.
   - **Skip for now** — everything else still gets set up; they run this later.

Rendered shape:

> Which AI should do the thinking when you message your assistant?
> *(This is separate from the Claude sign-in that is running this setup.)*
>
> 1. anthropic
> 2. openai
> 3. google
> 4. mistral
> 5. groq
> 6. openrouter
> 7. *(...whichever others `--help` listed...)*
> 8. **Other** — an OpenAI-compatible address. I will ask for the address too.
> 9. **Skip for now** — you can do this later with `hermes model`.

If they already mentioned a preference earlier, do not override it. Surface the
matching option instead: "Kimi via OpenRouter" → `openrouter`; "Kimi direct" →
`moonshot` if `--help` lists it, otherwise **Other** with Moonshot's base URL;
"local Ollama" → **Other** with `http://127.0.0.1:11434/v1`.

If you genuinely cannot tell which option fits, ask one short question. Do not
wrap it in opinions about providers.

## 3 — Ask for the key as plain text, never as a menu

Once they have picked, ask in prose. **Do not use a multiple-choice widget for
this** — it gives options like "Type something" / "I'll paste next turn", which
is confusing when what you need is a pasted string.

> Paste your `<provider>` key in your next message (it looks like
> `<example-shape>`). I will keep it out of any log and use it to set Hermes up.

**Stop the turn after this ask. Do not run other tool calls in the same turn**
("I'll run the checks while you decide"). Their next message *is* the input. If
you keep working, people think you have moved on, they freeze, and the install
stalls there.

If they picked **Other**, ask in prose for two things: the address (for example
`https://api.moonshot.cn/v1`) and the key.

If they picked **Skip**, go to section 5.

## 4 — Store the key without exposing it

The key is a real secret. **Never put it in a command's arguments**
(`hermes setup --anthropic-api-key="$KEY"`): arguments are visible in
`/proc/<pid>/cmdline` to every other process on the machine for as long as the
command runs, and they land in shell history.

```bash
# $PROVIDER is the literal token from step 1.
# Confirm the exact config key name with `hermes config --help`.
hermes config set "${PROVIDER}_api_key" "$KEY"
```

**A zero exit code is NOT proof the key landed somewhere that gets read.** The
`${PROVIDER}_api_key` form is a guess derived from a label. The real name may be
`api_keys.<provider>`, `<provider>-api-key`, `<PROVIDER>_API_KEY` or something
else. If the guess is wrong, the key is saved under a name nothing reads, and
they end up with a Hermes that says "configured" and fails on the first real
message. Check before believing it:

```bash
if hermes config 2>/dev/null | grep -qi "${PROVIDER}" \
   || grep -qi "${PROVIDER}" "$HOME/.hermes/.env" 2>/dev/null; then
  echo "key-verified"
else
  echo "key-unverified"
fi
```

Only treat this step as done on `key-verified`. On `key-unverified`, do not say
it is set up — fall through to section 6.

Then `unset KEY`.

**For Other / OpenAI-compatible**, find the base-URL flag rather than inventing one:

```bash
hermes setup --help 2>&1 | grep -E '\-\-[a-z-]+-(base-url|endpoint)'
```

If `--help` has no flag for their provider and no OpenAI-compatible base-URL
path, say so honestly: *"This build of Hermes has no setting for `<provider>`.
Either it is older than that provider's support, or it was removed. You can
(a) use a different provider you have a key for, (b) skip this and do it later,
or (c) run `hermes model` yourself in another terminal."* **Never invent a flag
name.**

## 5 — If they skipped

Tell them the exact command, not a description of it:

> To choose an AI later, in any terminal on this machine:
> `hermes model`
> It walks you through picking one and entering the key.

Carry on with everything else. Nothing else depends on this.

## 6 — If the wizard insists on a real terminal

Some builds need a live terminal for part of this, and your Bash tool runs a
command to completion before you see anything, so a prompt that waits for a
person waits forever. Do not loop trying. Say:

> `hermes model` on this build needs a real terminal. Open a second connection
> to this machine, run `hermes model` to add your key and pick a model, then
> `hermes gateway setup`. Follow its questions and tell me "done" when you are
> back.

Then wait, and verify when they return.

## 7 — Verify

```bash
hermes status 2>/dev/null
ls -la "$HOME/.hermes/config.yaml" 2>/dev/null
ls -la "$HOME/.hermes/.env" 2>/dev/null
```

Hermes splits its settings: ordinary ones in `~/.hermes/config.yaml`, the key
and other secrets in `~/.hermes/.env` (which should be readable only by them).
Both present means this step is done. Tell them which provider they chose.
