# Step — Which GitHub repository holds their folder

**Read this before you ask anything.** By the time you are running, the
installer's bash phase has already signed GitHub in on this machine with a
one-time code. So `gh` works, `git push` works, and **there is no token to ask
for and no deploy key to make.** If you find yourself about to ask for a
personal access token, or about to run `ssh-keygen`, stop: that is the old path
and it is not needed here.

Every `gh` command in this file is non-interactive and safe to run from your
Bash tool. Do not run `gh auth login` — it waits for a person and would hang.

## The rule this step follows

**Ask only for what you cannot look up.** You can look up which repositories
they have. You cannot look up which one is *theirs for this*. So: never open
with "what is your repository called?" Open with a list you already fetched.

## 1 — Find out who they are and what they have

```bash
gh api user --jq .login
gh repo list --limit 100 --json name,isPrivate,updatedAt,description \
  --jq 'sort_by(.updatedAt) | reverse | .[] | "\(.name)\t\(if .isPrivate then "private" else "PUBLIC" end)\t\(.description // "")"'
```

Then look for the ones that plausibly already hold a personal-assistant folder.
A repository qualifies if it contains any of `AGENTS.md`, `CLAUDE.md`,
`procedures.md`, or a `context/` directory:

```bash
# For each candidate repo name:
gh api "repos/<owner>/<name>/contents" --jq '.[].name' 2>/dev/null
```

Check the three or four most recently updated private repos, not all hundred.

## 2 — Ask, with the answer already half-written

**If exactly one repository looks like their folder**, do not present a menu.
Confirm it:

> I can see a private repository called `<name>` that has `AGENTS.md` and a
> `context/` folder in it, last updated `<when>`. That looks like your folder.
> Shall I put that one on this server? (yes / or tell me a different name)

**If several look plausible**, list only those, newest first, and ask which.

**If none look like it**, ask the real question, and make "I don't have one"
a first-class answer rather than a failure:

> I could not find a repository on your account that looks like your folder.
> Two possibilities:
>
> 1. It is there under a name I did not recognise — tell me the name.
> 2. You have not backed the folder up to GitHub yet — say "make one" and I
>    will create a private repository for you and put your folder in it.

**Stop the turn after this ask.** Do not run other work in the same turn. Their
next message is the answer, and if you keep working they will not know whether
to reply or wait.

## 3a — They named an existing repository: clone it

```bash
cd "$HOME"
gh repo clone "<owner>/<name>" hub
```

Then check what actually arrived, because an empty or wrong repository is the
failure that shows up three days later as "the assistant does not know anything
about me":

```bash
ls -A "$HOME/hub"
[ -f "$HOME/hub/AGENTS.md" ] && echo "has-brain" || echo "no-brain"
```

If it cloned but there is no `AGENTS.md`, say so plainly rather than carrying
on: *"That repository cloned, but there is no `AGENTS.md` in it, so the
assistant on this machine would not know anything about you. Is this the right
repository?"*

## 3b — They have no repository: make one

Create it private, from whatever their folder should start as. Private is not a
default you may change: this folder is going to hold notes about their life.

```bash
cd "$HOME/hub"
git init -b main
git add -A
git commit -m "My folder"
gh repo create "<name>" --private --source . --push
```

Confirm it landed, because `gh repo create` can report success while the push
behind it failed:

```bash
git -C "$HOME/hub" remote -v
git -C "$HOME/hub" log --oneline -1
gh repo view "<name>" --json name,isPrivate,pushedAt
```

A repository that exists but has no commits in it is not done. Say so and fix
it before moving on.

## 4 — Make git able to push from here without a person

The sign-in already did this, but confirm it rather than assume, because the
first time it matters is at three in the morning when nobody is watching:

```bash
cd "$HOME/hub"
git config user.name  >/dev/null 2>&1 || git config user.name  "$(gh api user --jq .name // .login)"
git config user.email >/dev/null 2>&1 || git config user.email "$(gh api user --jq '.email // "noreply@users.noreply.github.com"')"
git pull --rebase --autostash 2>&1 | tail -2
```

A `git pull` that works without asking for a password is the proof. If it asks
for anything, `gh auth setup-git` was not run — run it and try again.

## What to report back

One line, in plain words: which repository is now on this machine, whether it is
private, and whether a pull worked without a password. Never report this step as
done on a clone alone.
