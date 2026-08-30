-- Minimal stand-in for the parts of the WoW API that NoBonusRoll touches, so
-- the addon can be loaded and exercised with a plain Lua 5.1 interpreter.

local stubs = {}

local frames = {}
local timers = {}

stubs.output = {}
stubs.declined = {}
stubs.timers = timers
stubs.frames = frames
stubs.closedByAddon = 0
stubs.clientClosesWindow = true

-- Current fake location, changed by the tests.
stubs.instance = {
    name = "Siege of Orgrimmar",
    instanceType = "raid",
    difficultyID = 14,
    instanceID = 1136,
}

-- Roughly what a current retail client reports. Delve difficulties are left
-- out on purpose: the addon has to cope with ids GetDifficultyInfo knows
-- nothing about.
local difficultyNames = {
    [1] = "Normal", [2] = "Heroic", [8] = "Mythic Keystone",
    [3] = "10 Player", [4] = "25 Player",
    [5] = "10 Player (Heroic)", [6] = "25 Player (Heroic)",
    [7] = "Looking For Raid", [9] = "40 Player",
    [14] = "Normal", [15] = "Heroic", [16] = "Mythic",
    [17] = "Looking For Raid", [23] = "Mythic", [24] = "Timewalking",
    [33] = "Timewalking",
    [148] = "20 Player", [151] = "Looking For Raid (Timewalking)",
    [220] = "Story", [233] = "Mythic", [250] = "World",
}

--------------------------------------------------------------------------------
-- Widgets
--------------------------------------------------------------------------------

local methods = {}
local widgetMT = {}

function widgetMT.__index(widget, key)
    local nils = rawget(widget, "removed")
    if nils and nils[key] then
        return nil -- explicitly removed by a test
    end
    local method = methods[key]
    if method then
        return method
    end
    -- Anything else that looks like an API method is a no-op.
    if type(key) == "string" and key:match("^%u") then
        return function() end
    end
    return nil
end

local function newWidget(frameType, name, parent)
    return setmetatable({
        frameType = frameType,
        frameName = name,
        parent    = parent,
        scripts   = {},
        events    = {},
        shown     = true,
        width     = 0,
        height    = 0,
        text      = "",
        checked   = false,
        enabled   = true,
        scroll    = 0,
    }, widgetMT)
end

function methods:SetSize(w, h) self.width, self.height = w, h end
function methods:SetWidth(w) self.width = w end
function methods:SetHeight(h) self.height = h end
function methods:GetWidth() return self.width end
function methods:GetHeight() return self.height end
function methods:GetParent() return self.parent end
function methods:GetName() return self.frameName end
function methods:GetID() return 1 end
function methods:Show() self.shown = true end
function methods:Hide() self.shown = false end
function methods:SetShown(shown) self.shown = shown and true or false end
function methods:IsShown() return self.shown end
function methods:IsVisible() return self.shown end
function methods:SetText(text) self.text = text end
function methods:GetText() return self.text end
function methods:SetChecked(checked) self.checked = checked and true or false end
function methods:GetChecked() return self.checked end
function methods:SetEnabled(enabled) self.enabled = enabled and true or false end
function methods:IsEnabled() return self.enabled end
function methods:SetVerticalScroll(value) self.scroll = value end
function methods:GetVerticalScroll() return self.scroll end
function methods:SetScript(name, func) self.scripts[name] = func end
function methods:GetScript(name) return self.scripts[name] end
function methods:HasScript(name) return true end
function methods:RegisterEvent(event) self.events[event] = true end
function methods:UnregisterEvent(event) self.events[event] = nil end
function methods:IsEventRegistered(event) return self.events[event] end
function methods:CreateFontString() return newWidget("FontString", nil, self) end
function methods:CreateTexture() return newWidget("Texture", nil, self) end
function methods:SetScrollChild(child) self.scrollChild = child end

function methods:Click()
    if self.scripts.OnClick then
        self.scripts.OnClick(self, "LeftButton")
    end
    self.clicked = (self.clicked or 0) + 1
end

--------------------------------------------------------------------------------
-- Globals
--------------------------------------------------------------------------------

function stubs.install()
    _G.UIParent = newWidget("Frame", "UIParent")

    _G.CreateFrame = function(frameType, name, parent, template)
        local frame = newWidget(frameType, name, parent)
        frame.template = template
        frames[#frames + 1] = frame
        if name then
            _G[name] = frame
        end
        return frame
    end

    _G.DEFAULT_CHAT_FRAME = {
        AddMessage = function(_, msg)
            stubs.output[#stubs.output + 1] = msg
        end,
    }

    _G.GameTooltip = newWidget("GameTooltip", "GameTooltip")

    _G.GetInstanceInfo = function()
        local i = stubs.instance
        -- name, instanceType, difficultyID, difficultyName, maxPlayers,
        -- dynamicDifficulty, isDynamic, instanceID, instanceGroupSize, lfgID
        return i.name, i.instanceType, i.difficultyID, difficultyNames[i.difficultyID],
               25, 0, false, i.instanceID, 25, nil
    end

    _G.IsInInstance = function()
        local i = stubs.instance
        return i.instanceType ~= "none", i.instanceType
    end

    _G.GetDifficultyInfo = function(id)
        return difficultyNames[id]
    end

    stubs.time = 0
    _G.GetTime = function() return stubs.time end

    _G.C_Timer = {
        After = function(delay, func)
            timers[#timers + 1] = { delay = delay, func = func }
        end,
    }

    _G.C_AddOns = {
        GetAddOnMetadata = function(_, field)
            if field == "Version" then return "1.0.0" end
        end,
    }

    -- Retail 12.x: the old SpellConfirmationPromptType enum is gone.
    _G.Enum = {
        ConfirmationPromptUIType = {
            StaticText = 0, BonusRoll = 1, SimpleWarning = 2,
            StaticTextAlert = 3, SimpleWarningAlert = 4,
        },
    }

    _G.DeclineSpellConfirmationPrompt = function(spellID)
        stubs.declined[#stubs.declined + 1] = spellID
    end
    _G.AcceptSpellConfirmationPrompt = function() end
    _G.StaticPopupSpecial_Hide = function(frame) frame:Hide() end

    -- BonusRollFrame as GroupLootFrame.xml builds it: the Pass button lives in
    -- the PromptFrame child and only declines, the window itself is taken down
    -- by the client when the server answers.
    _G.BonusRollFrame = newWidget("Frame", "BonusRollFrame")
    _G.BonusRollFrame:Hide()
    _G.BonusRollFrame.PromptFrame = newWidget("Frame", nil, _G.BonusRollFrame)
    _G.BonusRollFrame.PromptFrame.PassButton = newWidget("Button", nil, _G.BonusRollFrame.PromptFrame)
    _G.BonusRollFrame.PromptFrame.PassButton:SetScript("OnClick", function()
        _G.DeclineSpellConfirmationPrompt(_G.BonusRollFrame.spellID)
        if stubs.clientClosesWindow then
            _G.BonusRollFrame:Hide()
        end
    end)

    -- Current clients have no PassButton directly on the frame any more.
    stubs.removeField(_G.BonusRollFrame, "PassButton")

    _G.BonusRollFrame_CloseBonusRoll = function()
        _G.BonusRollFrame:Hide()
        stubs.closedByAddon = (stubs.closedByAddon or 0) + 1
    end

    _G.SlashCmdList = {}
    _G.InterfaceOptions_AddCategory = function() end
    _G.InterfaceOptionsFrame_OpenToCategory = function() end
    _G.wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
end

--------------------------------------------------------------------------------
-- Test helpers
--------------------------------------------------------------------------------

function stubs.fireEvent(event, ...)
    for _, frame in ipairs(frames) do
        if frame.events[event] and frame.scripts.OnEvent then
            frame.scripts.OnEvent(frame, event, ...)
        end
    end
end

function stubs.runTimers()
    local pending = timers
    stubs.timers = {}
    timers = stubs.timers
    for _, timer in ipairs(pending) do
        timer.func()
    end
end

function stubs.reset()
    stubs.output = {}
    stubs.declined = {}
    stubs.timers = {}
    stubs.closedByAddon = 0
    -- Default: the client tears the window down itself, the way it does when
    -- the server acknowledges a pass.
    stubs.clientClosesWindow = true
    timers = stubs.timers
    _G.BonusRollFrame:Hide()
    _G.BonusRollFrame.spellID = nil
end

-- Pretend a field the addon reaches for does not exist on this client.
function stubs.removeField(widget, key)
    widget[key] = nil
    local removed = rawget(widget, "removed") or {}
    removed[key] = true
    rawset(widget, "removed", removed)
end

function stubs.restoreField(widget, key, value)
    local removed = rawget(widget, "removed")
    if removed then removed[key] = nil end
    widget[key] = value
end

-- Pretend Blizzard showed the bonus roll frame for this prompt.
function stubs.showBonusRollFrame(spellID)
    _G.BonusRollFrame.spellID = spellID
    _G.BonusRollFrame:Show()
end

return stubs
