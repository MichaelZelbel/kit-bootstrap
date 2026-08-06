# Step — Connect Telegram, so it can reach their phone

Lifted from the Hermes DevOps Kit's own watchdog playbook, which is where this
text was proven. Changed only where it named that kit's own file paths.

The caller sets `KB_TELEGRAM_ENV` to where the credentials should be written
(for example `$HOME/.hub-env`). If it is unset, ask the caller, do not guess.

## The one rule that matters most

**They give you exactly one thing: the bot token.** The chat id is discovered
automatically by asking Telegram after they message the bot once.

**Never ask anyone for a chat id.** They do not have one yet — it does not exist
until they message the bot. They do not know where to find it. And you do not
need them to. If you catch yourself drafting "paste your token and chat id",
that is a bug in the sentence. Strike it.

## 1 — Ask the one real question

Multiple choice is right here: it is yes / walk-me-through / no. Put the main
action first and the escape hatch last.

> Shall I connect this to Telegram now, so your assistant can message your
> phone? I only need a bot token from you. The rest I work out myself once
> you have sent your new bot a message.
>
> 1. **Yes — I have a bot token, let me paste it**
> 2. **Walk me through making one** (about three minutes)
> 3. Skip for now — you can connect it later

Option 1 goes straight to section 3. Option 2 does section 2 first. Option 3
skips to the end.

## 2 — Walk them through making the bot

> On your phone or on desktop Telegram, search for `@BotFather` and open that
> chat. Send `/newbot`. It asks two things: a name (anything, for example
> "My Assistant") and a username that has to end in `bot` (for example
> `yourname_assistant_bot`). When you have answered both, BotFather sends back
> a message with a long line in it that looks like
> `7234567890:AAH-aB1cD-eFgHIJklMNo_PqRsTuVwXyZ12`. Paste that line here.

**Stop the turn here. Do not run other tool calls.** Their next message is the
token. If you keep working in parallel, they cannot tell whether to answer or
whether you have already moved on.

## 3 — Find the chat id yourself

This is the part that makes the difference. People do not know how to find a
chat id and should never have to.

> Now open the chat with your new bot in Telegram (search for the username you
> just made) and send it any message. "hi" is fine. Tell me when you have sent
> it.

**Stop the turn after this ask too.** You have to actually wait: asking Telegram
too early returns an empty answer, and then the search below thinks they messaged
the wrong account.

When they confirm, ask Telegram what it saw:

```bash
TOKEN="<the token they pasted>"
CHAT_ID=""
DISTINCT_COUNT=0

# Up to three tries: Telegram can take a few seconds to register the message.
for attempt in 1 2 3; do
  RESPONSE=$(curl -fsSL "https://api.telegram.org/bot${TOKEN}/getUpdates" 2>/dev/null)
  # Only real messages (skip edits and channel posts, where .message is null),
  # and only private chats. Take the FIRST one - that is their first message to
  # a brand-new bot. Taking the last would pick someone else's chat if anyone
  # else has messaged it.
  CHAT_ID=$(echo "$RESPONSE" | jq -r '
    [ .result[]? | select(.message.chat.type == "private")
                 | .message.chat.id ]
    | (.[0] // empty)' 2>/dev/null)
  DISTINCT_COUNT=$(echo "$RESPONSE" | jq -r '
    [ .result[]? | select(.message.chat.type == "private")
                 | .message.chat.id ] | unique | length' 2>/dev/null)
  if [ -n "$CHAT_ID" ] && [ "$CHAT_ID" != "null" ]; then break; fi
  sleep 5
done

[ -n "$CHAT_ID" ] && [ "$CHAT_ID" != "null" ] || echo "no-chat-id-yet"
```

**If `DISTINCT_COUNT` is more than 1**, more than one account has messaged this
bot, and picking the first is a guess. Do not quietly wire it up. Show them the
ids you found and ask which is theirs, or ask them to send a fresh message from
the account they want and run the search again.

If nothing comes back after three tries:

> I cannot see your message yet. Two things to check:
>
> 1. Did you send it from the same Telegram account you want the messages on?
> 2. Did you actually open the bot's chat and press send? BotFather's reply can
>    make it look like you have already spoken to the bot when you have not.
>
> Send another message and tell me again, and I will look once more.

If a second round still finds nothing, do not stall the whole install:

> Telegram is still showing nothing after two tries. This happens with brand-new
> bots sometimes. I will finish everything else without it. To connect it later,
> send your bot a message and then run:
>
> ```bash
> curl -s "https://api.telegram.org/bot<YOUR_TOKEN>/getUpdates" \
>   | jq -r '[ .result[]? | select(.message.chat.type=="private") | .message.chat.id ] | .[0]'
> ```
>
> Then put the token and that number into your settings file.

When it works:

> Got it. Saving this and sending you a test message now.

## 4 — Save the credentials

```bash
umask 077
cat >> "$KB_TELEGRAM_ENV" <<EOF
TELEGRAM_BOT_TOKEN=$TOKEN
TELEGRAM_CHAT_ID=$CHAT_ID
EOF
chmod 600 "$KB_TELEGRAM_ENV"
```

The heredoc is deliberately unquoted, so the real values get written rather than
the literal words `$TOKEN` and `$CHAT_ID`.

**Do not echo the token back into the chat.** The `chmod 600` and the file
location are the whole of the protection here.

## 5 — Prove it, do not assume it

Send one real message and check what Telegram answered. Anything other than
`ok` means it never arrived, whatever the exit code said:

```bash
curl -s --max-time 20 -X POST \
  "https://api.telegram.org/bot${TOKEN}/sendMessage" \
  -d chat_id="${CHAT_ID}" \
  --data-urlencode "text=Setup test. If you can read this, your assistant can reach you."
```

Then ask them to look at their phone and confirm it arrived. **A test message
that you sent but nobody confirmed seeing is not a working connection.**
