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

**Connecting the notebook and copying the hub are two separate choices.** Never
present them as one. Somebody whose hub holds client notes or patient notes can say
yes to the notebook and no to the copy, and that is a complete setup. After a no to
the copy, nothing is sent to Menerio or fetched from it in the background, in either
direction. Do not talk them into a yes.

## 1. Say what it is, and ask

> Menerio is optional. It is the author's online notebook. Connect it once, and
> every assistant that opens this hub can save notes there and find them again.
> Connecting sends none of your hub's files anywhere. Copying them for search is a
> second question, asked after this one, and its answer is no unless you say yes.
> A free account is enough to try it: https://menerio.com/auth?tab=signup
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
4. stores the key locked inside the hub folder
5. asks "Set a passphrase for a second computer now?" Enter means no. A yes asks for
   a passphrase, and that passphrase is all they type on the next computer. A no is
   a finished setup for one computer, and nothing warns about it later
6. makes the key available to programs on this computer
7. runs `hub-menerio-connect`, and shows one line for each assistant
8. asks "Copy your hub's files to Menerio for search?" Enter means no. See below
9. installs the small hub job, on save and once an hour. It keeps the folder fresh
   from its repository and hands a replaced key to Hermes. It copies to and from
   Menerio only after a yes in step 8

On a hub that is already connected it does not ask for the key again. It repeats
step 7, which is how an assistant installed last week gets the connection today. It
offers the passphrase again if there is none. And it asks step 8 again with their
last answer as the default, so this is also how somebody changes their mind.

## The second choice: a copy of the hub, for search

The installer says this, and you should not soften it or shorten it:

> One more choice. Menerio can keep a copy of your hub's text files, so your assistant
> can search them by meaning and not only by exact word. The copy holds everything in
> your hub except dev/ and your locked keys. In return, the people and facts Menerio
> holds for you are copied into your hub's world/ folder as a safety copy. Say yes only
> if you are happy for your hub's files to be in your Menerio account. Your notebook
> works either way.

The answer is kept for this one computer, as the line `HUB_NOTEBOOK_MIRROR=1` or
`HUB_NOTEBOOK_MIRROR=0` in `~/.hub/device.env`. A full install asks once and never
again. Only this single step asks again.

- **After a no:** nothing is copied in either direction, and nothing is sent to
  Menerio or fetched from it in the background. Their assistant still saves and finds
  notes there when they ask it to. `hub-search --local` still searches the hub's own
  files by word.
- **After a yes:** the hub's files go up when the hub saves a version and once an
  hour, and the people and facts Menerio holds for them come down into `world/` once
  an hour.
- **A computer that was already copying before this question existed** is written
  down as yes without being asked, and one line says so. To turn it off, run this
  step and say no.
- **An older copy of the kit** has a job that copies whatever anybody answered. After
  a no the installer does not schedule that job and takes out one it scheduled before,
  and says so. Updating the kit brings the job back, and the new one reads the answer.

To answer without a keyboard: `KB_NOTEBOOK_MIRROR=yes` or `KB_NOTEBOOK_MIRROR=no`,
and `KB_NOTEBOOK_PASSPHRASE=skip` or `KB_NOTEBOOK_PASSPHRASE=ask`. With no keyboard
and no answer, both are no.

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
