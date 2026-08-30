# NoBonusRoll

A World of Warcraft addon that automatically passes on the bonus roll prompt in
the instances and difficulties you pick, so you stop burning voidcores/coins on
content you only care about clearing.

Nothing is dismissed until you say so: a fresh install leaves every bonus roll
alone.

## Quick start

1. Copy the `NoBonusRoll` folder into `World of Warcraft/<flavor>/Interface/AddOns/`.
2. Log in and type `/nbr` to open the options, or use chat commands.

"Pass on every Normal raid automatically" (14 is the Normal raid difficulty;
`/nbr diff normal on` would cover Normal dungeons too):

```
/nbr diff 14 on
```

"…but always let me roll in this raid" (while standing in it):

```
/nbr here keep
```

The other way around — only ever roll in Mythic, pass on everything else:

```
/nbr invert on
/nbr diff mythic on
```

## How a prompt is decided

When the client shows a bonus roll prompt, the addon works out where you are and
at which difficulty, then checks, in this order:

1. **A rule for this instance and this exact difficulty** (`/nbr here`).
2. **A rule for this instance, all difficulties** (`/nbr raid`).
3. **The difficulty list** (`/nbr diff`, or the checkboxes in the options).
   * Normal mode: listed difficulties are passed, everything else is left alone.
   * Inverted mode (`/nbr invert on`): listed difficulties are kept, everything
     else is passed.

The master switch, a pause, and `/nbr next` all short-circuit the whole thing
and leave the prompt alone.

Rolls that happen outside an instance (world bosses, prey) have no instance
difficulty, so they are filed under the pseudo difficulty **World / no
instance** (id `0`) and can be listed like any other.

Raids, dungeons and delves are all covered. The difficulty list starts with
everything the client knows about, and any difficulty the addon runs into that
is not on that list — delve tiers, or whatever Blizzard adds next — is added to
the options panel the first time you enter it or get a prompt there.

## Options panel

`/nbr` opens a panel (also under Interface → AddOns → NoBonusRoll) with:

* the master switch and the chat message toggle,
* a delay in seconds before passing — `0` passes instantly, a few seconds gives
  you time to hit Roll yourself if you change your mind,
* the invert switch,
* a checkbox per difficulty the current client knows about, plus any the addon
  has seen,
* the list of per-instance rules, where each row can be flipped between **Pass**
  and **Keep** or removed.

## Chat commands

`/nbr` or `/nobonusroll`

| Command | What it does |
| --- | --- |
| `/nbr` | open the options window |
| `/nbr on` / `off` / `toggle` | master switch |
| `/nbr status` | what would happen right here, right now |
| `/nbr diff <name or id> [on\|off]` | list a difficulty, e.g. `/nbr diff normal on`, `/nbr diff 17 on` |
| `/nbr here [pass\|keep\|clear]` | rule for the instance you are in, current difficulty (defaults to `pass`) |
| `/nbr raid [pass\|keep\|clear]` | rule for the instance you are in, every difficulty |
| `/nbr rule <instanceID> <all\|difficultyID> <pass\|keep\|clear>` | rule for an instance you are not standing in |
| `/nbr list` | every per-instance rule |
| `/nbr raids` | instances you have visited, with their ids |
| `/nbr invert [on\|off]` | keep only what is listed, pass on everything else |
| `/nbr delay <seconds>` | wait before passing (0–30) |
| `/nbr announce [on\|off]` | chat message when a roll is passed |
| `/nbr debug [on\|off]` | print every confirmation prompt the client sends, with its type, currency and difficulty |
| `/nbr pause [minutes]` | stop passing for a while; no number cancels the pause |
| `/nbr next` | keep the very next prompt, one time only |
| `/nbr reset` | back to defaults |

Difficulty names come from the client, so `/nbr diff normal on` matches whatever
that client calls "Normal". Several difficulties share a name — "Normal" and
"Mythic" exist for dungeons as well as for raids — and a name that matches
several of them lists every match, printing each one with its id. Use the id
(`/nbr diff 14 on`) when you mean exactly one.

## Which game versions have bonus rolls

* **Retail (Midnight).** Bonus rolls are back. Patch 12.0.5 brought them in with
  the Voidforge and its Nebulous Voidcores, and Season 2 (12.1) uses Ascendant
  Venomstones; they drop from raids, dungeons, delves and prey. Under the hood
  the client still uses the old plumbing: the prompt arrives as
  `SPELL_CONFIRMATION_PROMPT` with `Enum.ConfirmationPromptUIType.BonusRoll` and
  is shown by `BonusRollFrame`, which is exactly what this addon answers.
* **Mists of Pandaria through Shadowlands** — the original system, same event.
* **Dragonflight through The War Within** — no bonus rolls, so there is nothing
  to answer.

Two TOC files ship with the addon:

* `NoBonusRoll.toc` — retail, currently flagged for 11.2.7, 12.0.0 and 12.1.0.
* `NoBonusRoll_Mists.toc` — Mists of Pandaria Classic.

If a client marks the addon out of date, bump the `## Interface:` line in the
matching TOC to that client's interface number (`/dump select(4, GetBuildInfo())`
in game prints it).

Everything the addon touches is version-tolerant: the prompt type constant (it
moved from `LE_SPELL_CONFIRMATION_PROMPT_TYPE_BONUS_ROLL` to
`Enum.SpellConfirmationPromptType` to `Enum.ConfirmationPromptUIType`), the
metadata lookup, the settings registration, the position of Blizzard's own Pass
button and the way the prompt window is closed all have fallbacks for older and
newer clients.

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
