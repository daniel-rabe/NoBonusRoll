-- NoBonusRoll - Core
-- Watches the bonus roll confirmation prompt and passes on it automatically
-- whenever the current raid / difficulty matches the rules the player set up.

local ADDON_NAME, NS = ...

_G.NoBonusRoll = NS

NS.ADDON_NAME = ADDON_NAME
NS.CHAT_PREFIX = "|cff33ff99NoBonusRoll|r: "

--------------------------------------------------------------------------------
-- Compatibility helpers
--------------------------------------------------------------------------------

local GetAddOnMetadata = (C_AddOns and C_AddOns.GetAddOnMetadata) or _G.GetAddOnMetadata
NS.VERSION = (GetAddOnMetadata and GetAddOnMetadata(ADDON_NAME, "Version")) or "dev"

-- The confirmation prompt type used for bonus rolls. The name of the constant
-- moved from a LE_ global to the Enum table, so look in both places.
NS.BONUS_ROLL_PROMPT_TYPE =
    (Enum and Enum.SpellConfirmationPromptType and Enum.SpellConfirmationPromptType.BonusRoll)
    or _G.LE_SPELL_CONFIRMATION_PROMPT_TYPE_BONUS_ROLL
    or 1

local After = (C_Timer and C_Timer.After) or function(_, func) func() end

--------------------------------------------------------------------------------
-- Constants
--------------------------------------------------------------------------------

NS.RULE_DISMISS = "DISMISS"
NS.RULE_KEEP    = "KEEP"

NS.MODE_DISMISS_LISTED = "DISMISS_LISTED" -- dismiss what matches, keep the rest
NS.MODE_KEEP_LISTED    = "KEEP_LISTED"    -- keep what matches, dismiss the rest

-- Rules that apply to every difficulty of an instance are stored under this key.
NS.ALL_DIFFICULTIES = "ALL"

-- Bonus rolls outside of an instance (world bosses) are filed under difficulty 0.
NS.WORLD_DIFFICULTY = 0

-- Difficulties offered in the options panel, in the order they are shown.
-- Anything the current client does not know about is skipped, so the same list
-- works on retail and on Classic.
NS.DIFFICULTY_ORDER = { 0, 7, 17, 3, 4, 5, 6, 9, 14, 15, 16, 33, 148, 151 }

NS.DIFFICULTY_FALLBACK_NAMES = {
    [0]   = "World / no instance",
    [3]   = "10 Player",
    [4]   = "25 Player",
    [5]   = "10 Player (Heroic)",
    [6]   = "25 Player (Heroic)",
    [7]   = "Looking For Raid",
    [9]   = "40 Player",
    [14]  = "Normal",
    [15]  = "Heroic",
    [16]  = "Mythic",
    [17]  = "Looking For Raid",
    [33]  = "Timewalking",
    [148] = "20 Player",
    [151] = "Looking For Raid (Timewalking)",
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
    return self.DIFFICULTY_FALLBACK_NAMES[difficultyID] or ("Difficulty " .. difficultyID)
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

function NS:DescribeInstance(instanceID)
    if not instanceID then
        return "any raid"
    end
    local entry = self.db and self.db.instances[instanceID]
    local name = (entry and entry.name) or (self.db and self.db.seen[instanceID])
    return name or ("Instance " .. instanceID)
end

--------------------------------------------------------------------------------
-- Saved variables
--------------------------------------------------------------------------------

local defaults = {
    enabled      = true,
    mode         = NS.MODE_DISMISS_LISTED,
    announce     = true,
    delay        = 0,
    difficulties = {}, -- [difficultyID] = true
    instances    = {}, -- [instanceID] = { name = "...", rules = { [difficultyID or "ALL"] = "DISMISS"/"KEEP" } }
    seen         = {}, -- [instanceID] = "name" of every raid visited, for /nbr raids
    stats        = { dismissed = 0 },
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

function NS:DismissPrompt(spellID, ctx, reason)
    if self.pendingSpellID ~= spellID then
        return -- the prompt timed out or the player answered it first
    end
    self.pendingSpellID = nil

    local frame = _G.BonusRollFrame
    local ours = frame and frame:IsShown() and (frame.spellID == nil or frame.spellID == spellID)
    local handled = false

    -- Clicking Blizzard's own Pass button declines the prompt and tears the
    -- frame down exactly the way a manual pass would. It is wrapped because it
    -- relies on frame internals, and the plain API below is the safety net.
    if ours and frame.PassButton and frame.PassButton.Click then
        local ok = pcall(frame.PassButton.Click, frame.PassButton)
        handled = ok and not frame:IsShown()
    end

    if not handled then
        if DeclineSpellConfirmationPrompt then
            DeclineSpellConfirmationPrompt(spellID)
        end
        if frame and frame:IsShown() and (frame.spellID == nil or frame.spellID == spellID) then
            if StaticPopupSpecial_Hide then
                StaticPopupSpecial_Hide(frame)
            else
                frame:Hide()
            end
        end
    end

    self.db.stats.dismissed = (self.db.stats.dismissed or 0) + 1

    if self.db.announce then
        self:Print("Passed on the bonus roll in %s - %s.", self:DescribeContext(ctx), reason)
    end
end

function NS:HandlePrompt(spellID, confirmType, text, duration, currencyID, currencyCost, difficultyID)
    if confirmType ~= self.BONUS_ROLL_PROMPT_TYPE then
        return
    end

    local ctx = self:GetContext(difficultyID)
    ctx.spellID      = spellID
    ctx.currencyID   = currencyID
    ctx.currencyCost = currencyCost

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
    local name, instanceType, _, _, _, _, _, instanceID = GetInstanceInfo()
    if instanceType ~= "raid" and instanceType ~= "party" then
        return
    end
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
