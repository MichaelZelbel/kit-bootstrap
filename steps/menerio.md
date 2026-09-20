# Step: Connect Menerio, once, for every assistant

Menerio is the author's online notebook. It is optional. Everything in the book
works on plain files without it.

The installer asks about it once. This sheet is for the day somebody said no and
has changed their mind, or has added a new assistant and wants it connected too.
You do not walk through the whole installer again. There is one command for it.

## The one rule that matters most

**They give you exactly one thing: a Menerio API key, pasted into the terminal.**

**Never ask them to paste the key into the chat, and never read it back to them.**
The installer asks for it itself, stores it locked inside the hub folder, and
never prints it. If you catch yourself drafting "send me your key", strike it.

Never tell them to connect Hermes, Claude Code and Codex one by one. That was the
old way. One key, stored once, and `hub-menerio-connect` gives every assistant on
the computer the same connection.

## 1. Say what it is, and ask

> Menerio is optional. It is the author's online notebook. Connect it once, and
> every assistant that opens this hub can save notes there and find them again.
> Your whole hub also becomes searchable by meaning, not only by exact word. A
> free account is enough to try it: https://menerio.com/auth?tab=signup
>
> 1. **Yes, connect it now**
> 2. Not now. Your hub is complete without it, and you can come back any time.

Option 2 ends the step. Do not ask again in the same session.

## 2. Tell them where the key is

> In Menerio, open Settings, then API Keys, then Generate new API key. Leave every
> box ticked. That is the default. Copy the key. You will paste it in the next
> step, into the terminal, not here.

**Stop the turn here.** Their next message tells you they have the key.

## 3. Run the one step

macOS and Linux:

```bash
curl -fsSL https://raw.githubusercontent.com/MichaelZelbel/kit-bootstrap/v2/setup-hub.sh | bash -s -- --only menerio
```

Windows, in PowerShell. The wizard has no page for this, so it is two lines:

```powershell
iwr https://raw.githubusercontent.com/MichaelZelbel/kit-bootstrap/v2/windows/setup-hub.ps1 -OutFile "$env:TEMP\setup-hub.ps1"
powershell -ExecutionPolicy Bypass -File "$env:TEMP\setup-hub.ps1" -Only menerio
```

`join.sh --only menerio` and `join.ps1 -Only menerio` do the same from a copy of
this repository.

It needs a hub that is already on this computer. It does not pull the hub, does
not check Git, Node or Hermes again, and does not touch the rest of the wiring.
What it does:

1. fetches the kit's small programs, so `hub-menerio-connect` is here
2. fetches `age`, the program that locks the key, if this computer has none
3. asks "Connect Menerio now?" and asks for the key
4. stores the key locked inside the hub folder, and asks for a passphrase so the
   next computer only ever types that passphrase
5. makes the key available to programs on this computer
6. runs `hub-menerio-connect`, and shows one line for each assistant
7. installs the hourly catch-up and the on-save update

On a hub that is already connected it asks nothing and only repeats step 6. That
is how an assistant installed last week gets the connection today.

## 4. Read the report back to them, in plain words

`hub-menerio-connect` prints one line for each assistant it knows: Claude Code,
Hermes, Codex. Tell them which ones are connected and which are not on this
computer. Do not claim one that the report did not name.

> Done. Open a new terminal, or start your assistant again, and Menerio is there.

To look without changing anything:

```bash
hub-menerio-connect --check
```

To connect an assistant they installed later, run it again with nothing after it. It
leaves alone what is already connected:

```bash
hub-menerio-connect
```

They never need `--refresh`. The hourly job runs it. It is silent, and it only gives
Hermes the new key after the key in the hub has been replaced.

## If it says Menerio refused the key

> The notebook  failed: Menerio refused the key (401)

The key is stored and every assistant is set up, and Menerio does not accept the key.
The installer then ends with "your key is stored, and the check above found a problem".
Most often the key was copied with a piece missing, or it was revoked. Make a new key in
Menerio the same way, and store it by running the single step again. Do not ask them to
show you the key to check it.

## If it says the kit is too old

> this copy of the kit cannot connect Hermes and Codex for you yet

The key is stored and Claude Code is connected. Nothing is lost. Run the same
command again after the kit has been updated, and it connects the rest.
