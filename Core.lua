-- NoBonusRoll - Core
-- Watches the bonus roll confirmation prompt and passes on it automatically
-- whenever the current instance / difficulty matches the rules the player set
-- up. Retail 12.x (Midnight) hands out bonus rolls in raids, dungeons, delves
-- and out in the world, all through the same SPELL_CONFIRMATION_PROMPT event.

local ADDON_NAME, NS = ...

_G.NoBonusRoll = NS

NS.ADDON_NAME = ADDON_NAME
NS.CHAT_PREFIX = "|cff33ff99NoBonusRoll|r: "

--------------------------------------------------------------------------------
-- Compatibility helpers
--------------------------------------------------------------------------------

local GetAddOnMetadata = (C_AddOns and C_AddOns.GetAddOnMetadata) or _G.GetAddOnMetadata
NS.VERSION = (GetAddOnMetadata and GetAddOnMetadata(ADDON_NAME, "Version")) or "dev"

-- The confirmation prompt type used for bonus rolls. The constant kept moving:
-- LE_SPELL_CONFIRMATION_PROMPT_TYPE_BONUS_ROLL -> Enum.SpellConfirmationPromptType
-- -> Enum.ConfirmationPromptUIType (retail 12.x). The value has always been 1,
-- but look the name up wherever this client keeps it.
local function ResolveBonusRollPromptType()
    if Enum then
        local tables = { Enum.ConfirmationPromptUIType, Enum.SpellConfirmationPromptType }
        for _, enum in ipairs(tables) do
            if enum and enum.BonusRoll ~= nil then
                return enum.BonusRoll
            end
        end
    end
    if _G.LE_SPELL_CONFIRMATION_PROMPT_TYPE_BONUS_ROLL ~= nil then
        return _G.LE_SPELL_CONFIRMATION_PROMPT_TYPE_BONUS_ROLL
    end
    return 1
end

NS.BONUS_ROLL_PROMPT_TYPE = ResolveBonusRollPromptType()

local After = (C_Timer and C_Timer.After) or function(_, func) func() end

-- Seconds to wait for the client to take the prompt window down on its own
-- after a pass before closing it ourselves.
local CLOSE_GRACE = 2

--------------------------------------------------------------------------------
-- Constants
--------------------------------------------------------------------------------

NS.RULE_DISMISS = "DISMISS"
NS.RULE_KEEP    = "KEEP"

NS.MODE_DISMISS_LISTED = "DISMISS_LISTED" -- dismiss what matches, keep the rest
NS.MODE_KEEP_LISTED    = "KEEP_LISTED"    -- keep what matches, dismiss the rest

-- Rules that apply to every difficulty of an instance are stored under this key.
NS.ALL_DIFFICULTIES = "ALL"

-- Bonus rolls outside of an instance (world bosses, prey) are filed under
-- difficulty 0.
NS.WORLD_DIFFICULTY = 0

-- Difficulties offered in the options panel, in the order they are shown.
-- Anything the current client does not know about is skipped, so the same list
-- works on retail and on Classic. Difficulties the client knows but this list
-- does not (delves, anything Blizzard adds later) are picked up as they are
-- seen, see NS:RememberDifficulty.
NS.DIFFICULTY_ORDER = {
    0,                          -- outdoors: world bosses, prey
    1, 2, 23, 8, 24,            -- dungeons, mythic keystone, timewalking
    17, 14, 15, 16,             -- the current raid difficulties
    220, 233, 250,              -- story / flexible mythic / world raid
    33,                         -- timewalking raid
    7, 3, 4, 5, 6, 9, 148, 151, -- legacy raid sizes
}

NS.DIFFICULTY_FALLBACK_NAMES = {
    [0]   = "World / no instance",
    [1]   = "Normal Dungeon",
    [2]   = "Heroic Dungeon",
    [3]   = "10 Player",
    [4]   = "25 Player",
    [5]   = "10 Player (Heroic)",
    [6]   = "25 Player (Heroic)",
    [7]   = "Looking For Raid",
    [8]   = "Mythic Keystone",
    [9]   = "40 Player",
    [14]  = "Normal",
    [15]  = "Heroic",
    [16]  = "Mythic",
    [17]  = "Looking For Raid",
    [23]  = "Mythic Dungeon",
    [24]  = "Timewalking Dungeon",
    [33]  = "Timewalking",
    [148] = "20 Player",
    [151] = "Looking For Raid (Timewalking)",
    [220] = "Story",
    [233] = "Mythic (flexible)",
    [250] = "World Raid",
}

--------------------------------------------------------------------------------
-- Output
--------------------------------------------------------------------------------

function NS:Print(msg, ...)
    if select("#", ...) > 0 then
        msg = msg:format(...)
    end
    DEFAULT_CHAT_FRAME:AddMessage(self.CHAT_PREFIX .. msg)
end

function NS:GetDifficultyName(difficultyID)
    difficultyID = tonumber(difficultyID) or 0
    if difficultyID == self.WORLD_DIFFICULTY then
        return self.DIFFICULTY_FALLBACK_NAMES[0]
    end
    local name = GetDifficultyInfo and GetDifficultyInfo(difficultyID)
    if name and name ~= "" then
        return name
    end
    local learned = self.db and self.db.difficultyNames[difficultyID]
    return learned or self.DIFFICULTY_FALLBACK_NAMES[difficultyID] or ("Difficulty " .. difficultyID)
end

-- True when the current client knows this difficulty, used to hide retail-only
-- entries on Classic (and the other way around).
function NS:IsKnownDifficulty(difficultyID)
    if difficultyID == self.WORLD_DIFFICULTY then
        return true
    end
    local name = GetDifficultyInfo and GetDifficultyInfo(difficultyID)
    return name ~= nil and name ~= ""
end

-- Difficulties the player has actually been in, or that a prompt reported, are
-- remembered so that content DIFFICULTY_ORDER does not list (delves and
-- whatever comes next) can still be ticked in the options panel.
function NS:RememberDifficulty(difficultyID, name)
    difficultyID = tonumber(difficultyID)
    if not difficultyID or difficultyID <= 0 or not self.db then
        return
    end
    if not name or name == "" then
        name = GetDifficultyInfo and GetDifficultyInfo(difficultyID)
    end
    if not name or name == "" then
        name = self.DIFFICULTY_FALLBACK_NAMES[difficultyID] or ("Difficulty " .. difficultyID)
    end
    self.db.difficultyNames[difficultyID] = name
end

-- Every difficulty worth showing: the static order first, then anything that
-- was learned or already has a setting, so nothing silently drops off the list.
function NS:GetDifficultyList()
    local list, added = {}, {}

    for _, difficultyID in ipairs(self.DIFFICULTY_ORDER) do
        if not added[difficultyID] and self:IsKnownDifficulty(difficultyID) then
            added[difficultyID] = true
            list[#list + 1] = difficultyID
        end
    end

    local extra = {}
    if self.db then
        for _, source in ipairs({ self.db.difficultyNames, self.db.difficulties }) do
            for difficultyID in pairs(source) do
                difficultyID = tonumber(difficultyID)
                if difficultyID and not added[difficultyID] then
                    added[difficultyID] = true
                    extra[#extra + 1] = difficultyID
                end
            end
        end
    end
    table.sort(extra)

    for _, difficultyID in ipairs(extra) do
        list[#list + 1] = difficultyID
    end

    return list
end

function NS:DescribeInstance(instanceID)
    if not instanceID then
        return "any instance"
    end
    local entry = self.db and self.db.instances[instanceID]
    local name = (entry and entry.name) or (self.db and self.db.seen[instanceID])
    return name or ("Instance " .. instanceID)
end

--------------------------------------------------------------------------------
-- Saved variables
--------------------------------------------------------------------------------

local defaults = {
    enabled         = true,
    mode            = NS.MODE_DISMISS_LISTED,
    announce        = true,
    debug           = false,
    delay           = 0,
    difficulties    = {}, -- [difficultyID] = true
    difficultyNames = {}, -- [difficultyID] = "name" of every difficulty seen
    instances       = {}, -- [instanceID] = { name = "...", rules = { [difficultyID or "ALL"] = "DISMISS"/"KEEP" } }
    seen            = {}, -- [instanceID] = "name" of every instance visited, for /nbr raids
    stats           = { dismissed = 0 },
}

local function applyDefaults(source, target)
    for key, value in pairs(source) do
        if type(value) == "table" then
            if type(target[key]) ~= "table" then
                target[key] = {}
            end
            applyDefaults(value, target[key])
        elseif target[key] == nil then
            target[key] = value
        end
    end
end

function NS:InitializeDB()
    if type(NoBonusRollDB) ~= "table" then
        NoBonusRollDB = {}
    end
    applyDefaults(defaults, NoBonusRollDB)
    self.db = NoBonusRollDB
    return self.db
end

function NS:ResetDB()
    NoBonusRollDB = {}
    applyDefaults(defaults, NoBonusRollDB)
    self.db = NoBonusRollDB
    if self.RefreshOptions then
        self:RefreshOptions()
    end
end

--------------------------------------------------------------------------------
-- Rules
--------------------------------------------------------------------------------

function NS:SetDifficultyListed(difficultyID, listed)
    difficultyID = tonumber(difficultyID)
    if not difficultyID then
        return false
    end
    self.db.difficulties[difficultyID] = listed and true or nil
    return true
end

function NS:IsDifficultyListed(difficultyID)
    return self.db.difficulties[tonumber(difficultyID) or -1] and true or false
end

function NS:SetInstanceRule(instanceID, difficultyKey, rule)
    instanceID = tonumber(instanceID)
    if not instanceID then
        return false
    end
    if difficultyKey ~= self.ALL_DIFFICULTIES then
        difficultyKey = tonumber(difficultyKey)
        if not difficultyKey then
            return false
        end
    end

    local entry = self.db.instances[instanceID]
    if not rule then
        if entry then
            entry.rules[difficultyKey] = nil
            if not next(entry.rules) then
                self.db.instances[instanceID] = nil
            end
        end
        return true
    end

    if not entry then
        entry = { name = self.db.seen[instanceID], rules = {} }
        self.db.instances[instanceID] = entry
    end
    entry.rules[difficultyKey] = rule
    return true
end

-- Returns the rule that applies to an instance/difficulty pair, or nil when the
-- instance has no opinion and the difficulty list decides.
function NS:GetInstanceRule(instanceID, difficultyID)
    if not instanceID then
        return nil
    end
    local entry = self.db.instances[instanceID]
    if not entry then
        return nil
    end
    return entry.rules[difficultyID] or entry.rules[self.ALL_DIFFICULTIES]
end

-- Flat, sorted list of every instance rule, used by the options panel and /nbr list.
function NS:GetRuleList()
    local list = {}
    for instanceID, entry in pairs(self.db.instances) do
        for key, rule in pairs(entry.rules) do
            list[#list + 1] = {
                instanceID    = instanceID,
                instanceName  = entry.name or self:DescribeInstance(instanceID),
                difficultyKey = key,
                rule          = rule,
            }
        end
    end
    table.sort(list, function(a, b)
        if a.instanceName ~= b.instanceName then
            return a.instanceName < b.instanceName
        end
        local ak = (a.difficultyKey == NS.ALL_DIFFICULTIES) and -1 or a.difficultyKey
        local bk = (b.difficultyKey == NS.ALL_DIFFICULTIES) and -1 or b.difficultyKey
        return ak < bk
    end)
    return list
end

function NS:DescribeRuleKey(difficultyKey)
    if difficultyKey == self.ALL_DIFFICULTIES then
        return "all difficulties"
    end
    return self:GetDifficultyName(difficultyKey)
end

--------------------------------------------------------------------------------
-- Current location
--------------------------------------------------------------------------------

-- promptDifficultyID is the difficulty reported by the prompt itself; it is the
-- most reliable source, but older clients do not send it for world bosses.
function NS:GetContext(promptDifficultyID)
    local name, instanceType, difficultyID, _, _, _, _, instanceID = GetInstanceInfo()
    local inInstance = instanceType and instanceType ~= "none"

    local ctx = {
        instanceID   = inInstance and instanceID or nil,
        instanceName = inInstance and name or nil,
        instanceType = instanceType,
    }

    promptDifficultyID = tonumber(promptDifficultyID)
    if promptDifficultyID and promptDifficultyID > 0 then
        ctx.difficultyID = promptDifficultyID
    elseif inInstance and difficultyID and difficultyID > 0 then
        ctx.difficultyID = difficultyID
    else
        ctx.difficultyID = self.WORLD_DIFFICULTY
    end

    return ctx
end

function NS:DescribeContext(ctx)
    return ("%s (%s)"):format(ctx.instanceName or "outdoors", self:GetDifficultyName(ctx.difficultyID))
end

--------------------------------------------------------------------------------
-- Decision
--------------------------------------------------------------------------------

-- Returns dismiss (boolean) and a short human readable reason.
function NS:ShouldDismiss(ctx)
    if not self.db.enabled then
        return false, "the addon is turned off"
    end

    if self.skipNextPrompt then
        return false, "|cffffd100/nbr next|r was used"
    end

    if self.pausedUntil and GetTime() < self.pausedUntil then
        return false, ("paused for another %d min"):format(math.ceil((self.pausedUntil - GetTime()) / 60))
    end

    local rule = self:GetInstanceRule(ctx.instanceID, ctx.difficultyID)
    if rule == self.RULE_DISMISS then
        return true, ("rule for %s"):format(self:DescribeInstance(ctx.instanceID))
    elseif rule == self.RULE_KEEP then
        return false, ("rule for %s"):format(self:DescribeInstance(ctx.instanceID))
    end

    local listed = self:IsDifficultyListed(ctx.difficultyID)
    local difficultyName = self:GetDifficultyName(ctx.difficultyID)

    if self.db.mode == self.MODE_KEEP_LISTED then
        if listed then
            return false, ("%s is on the keep list"):format(difficultyName)
        end
        return true, ("%s is not on the keep list"):format(difficultyName)
    end

    if listed then
        return true, ("%s is on the dismiss list"):format(difficultyName)
    end
    return false, ("%s is not on the dismiss list"):format(difficultyName)
end

--------------------------------------------------------------------------------
-- Dismissing
--------------------------------------------------------------------------------

-- The prompt window belongs to GroupLootContainer, so it has to be taken out
-- of the container instead of merely hidden, or the container keeps a gap for
-- it. Normally the client does this itself once the server acknowledges the
-- pass; this is only the safety net.
function NS:CloseBonusRollWindow(spellID)
    local frame = _G.BonusRollFrame
    if not frame or not frame:IsShown() then
        return
    end
    if spellID and frame.spellID ~= nil and frame.spellID ~= spellID then
        return -- it belongs to a different prompt by now
    end

    if _G.BonusRollFrame_CloseBonusRoll then
        pcall(_G.BonusRollFrame_CloseBonusRoll)
    elseif _G.StaticPopupSpecial_Hide then
        _G.StaticPopupSpecial_Hide(frame)
    else
        frame:Hide()
    end
end

function NS:DismissPrompt(spellID, ctx, reason)
    if self.pendingSpellID ~= spellID then
        return -- the prompt timed out or the player answered it first
    end
    self.pendingSpellID = nil

    local frame = _G.BonusRollFrame
    local ours = frame and frame:IsShown() and (frame.spellID == nil or frame.spellID == spellID)

    -- Clicking Blizzard's own Pass button does exactly what a manual pass does.
    -- The button sits in BonusRollFrame.PromptFrame on current clients and
    -- directly on BonusRollFrame on older ones; both call the API below, which
    -- stays as the safety net because this pokes at frame internals.
    local passButton = ours and ((frame.PromptFrame and frame.PromptFrame.PassButton) or frame.PassButton)
    local passed = false
    if type(passButton) == "table" and passButton.Click then
        passed = pcall(passButton.Click, passButton)
    end

    if not passed and DeclineSpellConfirmationPrompt then
        DeclineSpellConfirmationPrompt(spellID)
    end

    -- The client removes the window when the server confirms the pass. Give it
    -- a moment and only step in if it is somehow still on screen.
    if ours then
        After(CLOSE_GRACE, function()
            self:CloseBonusRollWindow(spellID)
        end)
    end

    self.db.stats.dismissed = (self.db.stats.dismissed or 0) + 1

    if self.db.announce then
        self:Print("Passed on the bonus roll in %s - %s.", self:DescribeContext(ctx), reason)
    end
end

-- Argument list as of retail 12.x; older clients simply stop after difficultyID.
function NS:HandlePrompt(spellID, confirmType, text, duration, currencyID, currencyCost, difficultyID, displayItemID)
    -- /nbr debug: every spell confirmation, not just bonus rolls, so it is
    -- possible to tell "the addon ignored it" from "the client never asked".
    if self.db.debug then
        self:Print("prompt: spell %s, type %s (bonus roll is %s), currency %s x%s, difficulty %s, item %s",
            tostring(spellID), tostring(confirmType), tostring(self.BONUS_ROLL_PROMPT_TYPE),
            tostring(currencyID), tostring(currencyCost), tostring(difficultyID), tostring(displayItemID))
    end

    if confirmType ~= self.BONUS_ROLL_PROMPT_TYPE then
        return
    end

    self:RememberDifficulty(difficultyID)

    local ctx = self:GetContext(difficultyID)
    ctx.spellID       = spellID
    ctx.currencyID    = currencyID
    ctx.currencyCost  = currencyCost
    ctx.displayItemID = displayItemID

    self.lastPrompt = ctx

    local dismiss, reason = self:ShouldDismiss(ctx)

    if self.skipNextPrompt then
        self.skipNextPrompt = nil
    end

    if not dismiss then
        return
    end

    self.pendingSpellID = spellID

    local delay = tonumber(self.db.delay) or 0
    if delay < 0 then delay = 0 end

    -- Even with no delay, wait a frame so that BonusRollFrame has been created
    -- and shown by Blizzard's own handler before we click its Pass button.
    After(delay, function()
        self:DismissPrompt(spellID, ctx, reason)
    end)
end

--------------------------------------------------------------------------------
-- Pausing
--------------------------------------------------------------------------------

function NS:Pause(minutes)
    minutes = tonumber(minutes)
    if not minutes or minutes <= 0 then
        self.pausedUntil = nil
        return nil
    end
    self.pausedUntil = GetTime() + minutes * 60
    return minutes
end

function NS:IsPaused()
    if self.pausedUntil and GetTime() < self.pausedUntil then
        return true, math.ceil((self.pausedUntil - GetTime()) / 60)
    end
    self.pausedUntil = nil
    return false
end

--------------------------------------------------------------------------------
-- Events
--------------------------------------------------------------------------------

function NS:RememberCurrentInstance()
    local name, instanceType, difficultyID, difficultyName, _, _, _, instanceID = GetInstanceInfo()

    -- "scenario" covers delves, which hand out bonus rolls just like raids and
    -- dungeons do.
    if instanceType ~= "raid" and instanceType ~= "party" and instanceType ~= "scenario" then
        return
    end

    self:RememberDifficulty(difficultyID, difficultyName)

    if not instanceID or not name then
        return
    end
    self.db.seen[instanceID] = name
    local entry = self.db.instances[instanceID]
    if entry then
        entry.name = name
    end
end

local eventFrame = CreateFrame("Frame")
NS.eventFrame = eventFrame

eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:SetScript("OnEvent", function(_, event, ...)
    if event == "ADDON_LOADED" then
        local loaded = ...
        if loaded ~= ADDON_NAME then
            return
        end
        NS:InitializeDB()
        if NS.SetupOptions then
            NS:SetupOptions()
        end
        if NS.SetupCommands then
            NS:SetupCommands()
        end

        eventFrame:UnregisterEvent("ADDON_LOADED")
        eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
        eventFrame:RegisterEvent("SPELL_CONFIRMATION_PROMPT")
        eventFrame:RegisterEvent("SPELL_CONFIRMATION_TIMEOUT")

    elseif event == "SPELL_CONFIRMATION_PROMPT" then
        NS:HandlePrompt(...)

    elseif event == "SPELL_CONFIRMATION_TIMEOUT" then
        local spellID = ...
        if NS.pendingSpellID == spellID then
            NS.pendingSpellID = nil
        end

    elseif event == "PLAYER_ENTERING_WORLD" then
        NS:RememberCurrentInstance()
    end
end)
