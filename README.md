# NoBonusRoll

A World of Warcraft addon that automatically passes on the bonus roll prompt in
the raids and difficulties you pick, so you stop burning coins/seals on content
you only care about clearing.

Nothing is dismissed until you say so: a fresh install leaves every bonus roll
alone.

## Quick start

1. Copy the `NoBonusRoll` folder into `World of Warcraft/<flavor>/Interface/AddOns/`.
2. Log in and type `/nbr` to open the options, or use chat commands.

"Pass on every Normal raid automatically":

```
/nbr diff normal on
```

"…but always let me roll in Siege of Orgrimmar" (while standing in that raid):

```
/nbr here keep
```

The other way around — only ever roll in Mythic, pass on everything else:

```
/nbr invert on
/nbr diff mythic on
```

## How a prompt is decided

When the client shows a bonus roll prompt, the addon works out the raid and the
difficulty and checks, in this order:

1. **A rule for this raid and this exact difficulty** (`/nbr here`).
2. **A rule for this raid, all difficulties** (`/nbr raid`).
3. **The difficulty list** (`/nbr diff`, or the checkboxes in the options).
   * Normal mode: listed difficulties are passed, everything else is left alone.
   * Inverted mode (`/nbr invert on`): listed difficulties are kept, everything
     else is passed.

The master switch, a pause, and `/nbr next` all short-circuit the whole thing
and leave the prompt alone.

Bonus rolls from world bosses have no instance difficulty, so they are filed
under the pseudo difficulty **World / no instance** (id `0`) and can be listed
like any other.

## Options panel

`/nbr` opens a panel (also under Interface → AddOns → NoBonusRoll) with:

* the master switch and the chat message toggle,
* a delay in seconds before passing — `0` passes instantly, a few seconds gives
  you time to hit Roll yourself if you change your mind,
* the invert switch,
* a checkbox per difficulty the current client knows about,
* the list of per-raid rules, where each row can be flipped between **Pass** and
  **Keep** or removed.

## Chat commands

`/nbr` or `/nobonusroll`

| Command | What it does |
| --- | --- |
| `/nbr` | open the options window |
| `/nbr on` / `off` / `toggle` | master switch |
| `/nbr status` | what would happen right here, right now |
| `/nbr diff <name or id> [on\|off]` | list a difficulty, e.g. `/nbr diff normal on`, `/nbr diff 17 on` |
| `/nbr here [pass\|keep\|clear]` | rule for the raid you are in, current difficulty (defaults to `pass`) |
| `/nbr raid [pass\|keep\|clear]` | rule for the raid you are in, every difficulty |
| `/nbr rule <instanceID> <all\|difficultyID> <pass\|keep\|clear>` | rule for a raid you are not standing in |
| `/nbr list` | every per-raid rule |
| `/nbr raids` | raids you have visited, with their instance ids |
| `/nbr invert [on\|off]` | keep only what is listed, pass on everything else |
| `/nbr delay <seconds>` | wait before passing (0–30) |
| `/nbr announce [on\|off]` | chat message when a roll is passed |
| `/nbr pause [minutes]` | stop passing for a while; no number cancels the pause |
| `/nbr next` | keep the very next prompt, one time only |
| `/nbr reset` | back to defaults |

Difficulty names come from the client, so `/nbr diff normal on` matches whatever
that client calls "Normal". A name that matches several entries lists all of
them; numeric ids are always accepted.

## Which game versions have bonus rolls

Bonus rolls exist in Mists of Pandaria through Shadowlands; retail removed the
system in Dragonflight (10.0), so on a current retail client there is simply no
prompt for the addon to answer. It ships with two TOC files anyway:

* `NoBonusRoll_Mists.toc` — Mists of Pandaria Classic, where this is actually useful.
* `NoBonusRoll.toc` — the fallback the client uses for anything else, including retail.

If a client marks the addon out of date, bump the `## Interface:` line in the
matching TOC to that client's interface number (`/dump select(4, GetBuildInfo())`
in game prints it).

Everything the addon touches is version-tolerant: the prompt type constant, the
metadata lookup, the settings registration and the way the prompt window is
closed all have fallbacks for older and newer clients.

## Files

| File | Contents |
| --- | --- |
| `Core.lua` | saved variables, rule storage, the decision, event handling |
| `Options.lua` | the options panel |
| `Commands.lua` | `/nbr` |
| `tests/` | a stubbed WoW API and a test suite for the logic above |

## Tests

The decision logic, the chat commands and an options refresh run outside the
game against a stubbed API:

```
lua5.1 tests/run_tests.lua
```

WoW runs Lua 5.1, so use the same interpreter.

## License

MIT — see [LICENSE](LICENSE).
