-- Loads NoBonusRoll against the stubbed API and checks the decision logic.
-- Run with:  lua5.1 tests/run_tests.lua   (from the addon folder)

package.path = "tests/?.lua;" .. package.path
local stubs = require("wow_stubs")
stubs.install()

local NS = {}
for _, file in ipairs({ "Core.lua", "Options.lua", "Commands.lua" }) do
    local chunk = assert(loadfile(file))
    chunk("NoBonusRoll", NS)
end

stubs.fireEvent("ADDON_LOADED", "NoBonusRoll")

--------------------------------------------------------------------------------

local passed, failed = 0, 0

local function check(condition, description)
    if condition then
        passed = passed + 1
        print("  ok   - " .. description)
    else
        failed = failed + 1
        print("  FAIL - " .. description)
    end
end

local function fresh(instance)
    NS:ResetDB()
    stubs.reset()
    NS.pendingSpellID = nil
    NS.pausedUntil = nil
    NS.skipNextPrompt = nil
    stubs.instance = instance or {
        name = "Siege of Orgrimmar", instanceType = "raid", difficultyID = 14, instanceID = 1136,
    }
end

-- Timers queue further timers (the delayed pass queues the window safety net),
-- so keep going until nothing is left.
local function runTimers()
    for _ = 1, 5 do
        if #stubs.timers == 0 then
            break
        end
        stubs.runTimers()
    end
end

-- Fires a bonus roll prompt the way the client does and returns whether the
-- addon passed on it.
local function prompt(spellID, difficultyID)
    spellID = spellID or 1234
    stubs.declined = {}
    NS:HandlePrompt(spellID, NS.BONUS_ROLL_PROMPT_TYPE, "Roll?", 20, 3272, 1, difficultyID, 0, 0, 0)
    stubs.showBonusRollFrame(spellID)
    runTimers()
    return #stubs.declined > 0
end

local function slash(input)
    stubs.output = {}
    SlashCmdList["NOBONUSROLL"](input)
    return table.concat(stubs.output, "\n")
end

--------------------------------------------------------------------------------
print("defaults")
--------------------------------------------------------------------------------
fresh()
check(NS.db.enabled == true, "the addon starts enabled")
check(NS.db.mode == NS.MODE_DISMISS_LISTED, "default mode is to pass only what is listed")
check(next(NS.db.difficulties) == nil, "no difficulty is listed out of the box")
check(prompt() == false, "a fresh install never passes on a roll by itself")

--------------------------------------------------------------------------------
print("difficulty rules")
--------------------------------------------------------------------------------
fresh()
NS:SetDifficultyListed(14, true)
check(prompt() == true, "Normal is listed, so the Normal roll is passed")
check(BonusRollFrame:IsShown() == false, "the bonus roll frame is closed afterwards")

stubs.instance = { name = "Siege of Orgrimmar", instanceType = "raid", difficultyID = 15, instanceID = 1136 }
check(prompt(2001, 15) == false, "Heroic is not listed, so that roll is left alone")

stubs.instance = { name = "Siege of Orgrimmar", instanceType = "raid", difficultyID = 14, instanceID = 1136 }
check(prompt(2002, nil) == true, "the client difficulty is used when the prompt does not carry one")

fresh()
NS:SetDifficultyListed(17, true)
stubs.instance = { name = "Nerub-ar Palace", instanceType = "raid", difficultyID = 17, instanceID = 2657 }
check(prompt(2003, 17) == true, "LFR can be listed independently")

--------------------------------------------------------------------------------
print("closing the prompt")
--------------------------------------------------------------------------------
fresh()
NS:SetDifficultyListed(14, true)
check(prompt(9000, 14) == true, "the roll is declined through the Pass button in BonusRollFrame.PromptFrame")
check(stubs.closedByAddon == 0, "and the client is left to close its own window")

-- Clients that do not take the window down on their own must not be left with
-- a dead prompt on screen.
fresh()
NS:SetDifficultyListed(14, true)
stubs.clientClosesWindow = false
check(prompt(9001, 14) == true, "a stubborn window is still declined")
check(BonusRollFrame:IsShown() == false, "and closed by the addon afterwards")
check(stubs.closedByAddon == 1, "using Blizzard's own close function, not a plain Hide")

-- Older layouts, and anything else that moves the button, fall back to the API.
fresh()
NS:SetDifficultyListed(14, true)
local promptFrame = BonusRollFrame.PromptFrame
stubs.removeField(BonusRollFrame, "PromptFrame")
check(prompt(9002, 14) == true, "the roll is still declined when the Pass button is not where we expect")
check(BonusRollFrame:IsShown() == false, "and the window is closed for us")
stubs.restoreField(BonusRollFrame, "PromptFrame", promptFrame)

-- A prompt for a different spell must not have its window closed by us.
fresh()
NS:SetDifficultyListed(14, true)
NS:HandlePrompt(9003, NS.BONUS_ROLL_PROMPT_TYPE, "Roll?", 20, 3272, 1, 14)
stubs.declined = {}
stubs.showBonusRollFrame(4242)
runTimers()
check(#stubs.declined == 1 and stubs.declined[1] == 9003, "only the prompt we decided on is declined")
check(BonusRollFrame:IsShown() == true, "a window belonging to another prompt is left open")
BonusRollFrame:Hide()

--------------------------------------------------------------------------------
print("world bosses")
--------------------------------------------------------------------------------
fresh({ name = "Valley of the Four Winds", instanceType = "none", difficultyID = 0, instanceID = 870 })
check(prompt(3001, 0) == false, "world boss rolls are kept unless difficulty 0 is listed")
NS:SetDifficultyListed(0, true)
check(prompt(3002, 0) == true, "listing difficulty 0 covers world bosses")

--------------------------------------------------------------------------------
print("dungeons, delves and unknown difficulties")
--------------------------------------------------------------------------------
fresh()
check(NS.BONUS_ROLL_PROMPT_TYPE == Enum.ConfirmationPromptUIType.BonusRoll,
    "the prompt type comes from the enum this client actually has")

local offered = {}
for _, difficultyID in ipairs(NS:GetDifficultyList()) do
    offered[difficultyID] = true
end
check(offered[0] and offered[8] and offered[16] and offered[233],
    "the difficulty list covers the world, dungeons and current raid difficulties")

fresh({ name = "Ara-Kara, City of Echoes", instanceType = "party", difficultyID = 8, instanceID = 2660 })
stubs.fireEvent("PLAYER_ENTERING_WORLD")
check(NS.db.seen[2660] == "Ara-Kara, City of Echoes", "dungeons are remembered like raids")
NS:SetDifficultyListed(8, true)
check(prompt(10001, 8) == true, "a keystone dungeon roll is passed when its difficulty is listed")

-- Delves report a difficulty that GetDifficultyInfo knows nothing about, so the
-- addon has to learn it before it can be ticked.
fresh({ name = "Earthcrawl Mines", instanceType = "scenario", difficultyID = 208, instanceID = 2664 })
check(NS:IsKnownDifficulty(208) == false, "the client does not know the delve difficulty")
stubs.fireEvent("PLAYER_ENTERING_WORLD")
check(NS.db.seen[2664] == "Earthcrawl Mines", "delves are remembered as well")
check(NS.db.difficultyNames[208] ~= nil, "and so is the difficulty they run at")

local learned = false
for _, difficultyID in ipairs(NS:GetDifficultyList()) do
    learned = learned or difficultyID == 208
end
check(learned, "a learned difficulty joins the list the options panel builds from")

NS:SetDifficultyListed(208, true)
check(prompt(10002, 208) == true, "and can be passed on like any other")

fresh()
check(NS.db.difficultyNames[208] == nil, "a reset forgets the learned difficulties again")
NS:HandlePrompt(10003, NS.BONUS_ROLL_PROMPT_TYPE, "Roll?", 20, 3272, 1, 208, 0, 0, 0)
check(NS.db.difficultyNames[208] ~= nil, "a prompt on its own teaches the addon a difficulty")

--------------------------------------------------------------------------------
print("per raid rules")
--------------------------------------------------------------------------------
fresh()
NS:SetDifficultyListed(14, true)
NS:SetInstanceRule(1136, 14, NS.RULE_KEEP)
check(prompt(4001, 14) == false, "a keep rule for one raid beats the difficulty list")

NS:SetInstanceRule(1136, 14, nil)
check(prompt(4002, 14) == true, "removing the rule falls back to the difficulty list")

fresh()
NS:SetInstanceRule(1136, NS.ALL_DIFFICULTIES, NS.RULE_DISMISS)
check(prompt(4003, 16) == true, "an all-difficulties rule covers every difficulty of that raid")
stubs.instance = { name = "Throne of Thunder", instanceType = "raid", difficultyID = 16, instanceID = 1098 }
check(prompt(4004, 16) == false, "the rule does not leak into other raids")

fresh()
NS:SetInstanceRule(1136, NS.ALL_DIFFICULTIES, NS.RULE_DISMISS)
NS:SetInstanceRule(1136, 16, NS.RULE_KEEP)
check(prompt(4005, 16) == false, "an exact difficulty rule beats the all-difficulties rule")
check(prompt(4006, 15) == true, "other difficulties still follow the all-difficulties rule")

--------------------------------------------------------------------------------
print("inverted mode")
--------------------------------------------------------------------------------
fresh()
NS.db.mode = NS.MODE_KEEP_LISTED
NS:SetDifficultyListed(16, true)
check(prompt(5001, 16) == false, "Mythic is on the keep list, so it is left alone")
check(prompt(5002, 14) == true, "everything not on the keep list is passed")

--------------------------------------------------------------------------------
print("switches")
--------------------------------------------------------------------------------
fresh()
NS:SetDifficultyListed(14, true)
NS.db.enabled = false
check(prompt(6001, 14) == false, "the master switch stops everything")
NS.db.enabled = true

NS:Pause(30)
check(prompt(6002, 14) == false, "pausing stops passing")
stubs.time = stubs.time + 31 * 60
check(prompt(6003, 14) == true, "passing resumes once the pause runs out")

NS.skipNextPrompt = true
check(prompt(6004, 14) == false, "/nbr next keeps exactly one roll")
check(prompt(6005, 14) == true, "and only one")

--------------------------------------------------------------------------------
print("other prompt types and delay")
--------------------------------------------------------------------------------
fresh()
NS:SetDifficultyListed(14, true)
stubs.declined = {}
NS:HandlePrompt(7001, 0, "Some other confirmation", 20, nil, nil, 14)
runTimers()
check(#stubs.declined == 0, "non bonus roll confirmations are ignored")

NS.db.delay = 5
NS:HandlePrompt(7002, NS.BONUS_ROLL_PROMPT_TYPE, "Roll?", 20, 3272, 1, 14)
check(#stubs.timers == 1 and stubs.timers[1].delay == 5, "the queued timer uses the configured delay")
runTimers()
check(#stubs.declined == 1, "the delayed pass still fires")

fresh()
NS:SetDifficultyListed(14, true)
NS:HandlePrompt(7003, NS.BONUS_ROLL_PROMPT_TYPE, "Roll?", 20, 3272, 1, 14)
stubs.fireEvent("SPELL_CONFIRMATION_TIMEOUT", 7003, NS.BONUS_ROLL_PROMPT_TYPE)
runTimers()
check(#stubs.declined == 0, "a prompt that timed out first is not declined afterwards")

--------------------------------------------------------------------------------
print("counters and saved variables")
--------------------------------------------------------------------------------
fresh()
NS:SetDifficultyListed(14, true)
prompt(8001, 14)
prompt(8002, 14)
check(NS.db.stats.dismissed == 2, "passed rolls are counted")

local saved = NoBonusRollDB
NS.db = nil
NoBonusRollDB = saved
NS:InitializeDB()
check(NS.db.difficulties[14] == true, "settings survive a reload")

--------------------------------------------------------------------------------
print("chat commands")
--------------------------------------------------------------------------------
fresh()
local out = slash("diff normal on")
check(NS:IsDifficultyListed(14) == true, "/nbr diff normal on lists the Normal difficulty")
check(out:find("Normal") ~= nil, "and says so")

slash("diff normal off")
check(NS:IsDifficultyListed(14) == false, "/nbr diff normal off removes it again")

slash("diff 17 on")
check(NS:IsDifficultyListed(17) == true, "/nbr diff accepts a numeric id")

slash("here pass")
check(NS:GetInstanceRule(1136, 14) == NS.RULE_DISMISS, "/nbr here pass adds a rule for the current raid")
slash("here keep")
check(NS:GetInstanceRule(1136, 14) == NS.RULE_KEEP, "/nbr here keep flips it")
slash("here clear")
check(NS:GetInstanceRule(1136, 14) == nil, "/nbr here clear removes it")

slash("raid pass")
check(NS:GetInstanceRule(1136, 16) == NS.RULE_DISMISS, "/nbr raid pass covers every difficulty")

slash("rule 1098 all keep")
check(NS:GetInstanceRule(1098, 3) == NS.RULE_KEEP, "/nbr rule works for raids you are not in")

slash("off")
check(NS.db.enabled == false, "/nbr off disables the addon")
slash("on")
check(NS.db.enabled == true, "/nbr on enables it again")

slash("invert on")
check(NS.db.mode == NS.MODE_KEEP_LISTED, "/nbr invert on switches to keep-only mode")
slash("invert off")
check(NS.db.mode == NS.MODE_DISMISS_LISTED, "/nbr invert off switches back")

slash("delay 3")
check(NS.db.delay == 3, "/nbr delay sets the delay")
slash("delay 99")
check(NS.db.delay == 30, "the delay is capped")

slash("announce off")
check(NS.db.announce == false, "/nbr announce off silences the chat message")

slash("debug on")
stubs.output = {}
NS:HandlePrompt(11001, 0, "Some other confirmation", 20, nil, nil, 14)
check(#stubs.output == 1, "/nbr debug on reports prompts the addon does not act on")
slash("debug off")
stubs.output = {}
NS:HandlePrompt(11002, 0, "Some other confirmation", 20, nil, nil, 14)
check(#stubs.output == 0, "/nbr debug off stops it again")

slash("pause 15")
check(select(1, NS:IsPaused()) == true, "/nbr pause pauses")
slash("pause")
check(select(1, NS:IsPaused()) == false, "/nbr pause without a number cancels it")

slash("next")
check(NS.skipNextPrompt == true, "/nbr next arms the one shot skip")

check(#slash("status") > 0, "/nbr status prints something")
check(#slash("list") > 0, "/nbr list prints something")
check(#slash("help") > 0, "/nbr help prints something")
check(#slash("raids") > 0, "/nbr raids prints something")
check(#slash("nonsense") > 0, "an unknown command falls back to the help text")

slash("reset")
check(next(NS.db.difficulties) == nil and NS.db.enabled == true, "/nbr reset restores the defaults")

--------------------------------------------------------------------------------
print("options panel")
--------------------------------------------------------------------------------
fresh()
NS:SetDifficultyListed(14, true)
NS:SetInstanceRule(1136, 14, NS.RULE_DISMISS)
NS:SetInstanceRule(1098, NS.ALL_DIFFICULTIES, NS.RULE_KEEP)
local ok, err = pcall(function() NS:RefreshOptions() end)
check(ok, "the options panel refreshes without errors" .. (ok and "" or (": " .. tostring(err))))
check(#NS:GetRuleList() == 2, "both rules show up in the list")

NS:RememberDifficulty(208)
check(pcall(function() NS:RefreshOptions() end), "a learned difficulty gets a checkbox without errors")

local panel = NoBonusRollOptionsPanel
check(panel ~= nil, "the options panel frame exists")
check(pcall(function() panel.scripts.OnShow(panel) end), "showing the panel refreshes it")

--------------------------------------------------------------------------------
print("")
print(("%d passed, %d failed"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
