# settings

## `server-profile.json`

The permission profile for an assistant living on a server, in an account of its
own.

**This is Chapter 25's lesson written as a file.** On a laptop the leash is a
question: it asks, you answer. On a server at three in the morning there is
nobody to answer, so a question is the same as a refusal and the job dies
waiting. The leash has to be the walls instead: an account that can reach almost
nothing, with permission to act inside it granted in advance.

It applies to the install itself, not only to the jobs afterwards. Without this
file the reader is asked to approve every single file read, one at a time, while
their own server is being set up.

So `allow` is broad and `deny` is the short list of things that are never a good
idea even inside your own home directory. That deny list is adapted from the
Hermes DevOps Kit's conservative profile, which is where it was built and
proven. The audit hooks belong to that product and are not here.

## Why there are no comments inside the JSON

Because it costs you the whole file.

`~/.claude/settings.json` belongs to Claude Code, and Claude Code rewrites it.
An earlier version of this profile carried an explanatory `_comment` array and a
`kit-bootstrap-profile` marker so a second install could recognise its own work.
Both are outside the published schema. The moment Claude Code started, it
replaced the entire file with a two-line version of its own settings, and the
permissions went with it. From the outside this looked exactly like the profile
never being installed.

Verified on Ubuntu 24.04, 2026-08-06: the identical profile with those two keys
removed survives a Claude Code run byte for byte.

**So: only `$schema` and `permissions` go in this file.** Anything you want to
say about it says it here. "Is this file ours?" is answered by comparing it with
this source, not by marking it.
