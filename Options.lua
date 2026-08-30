-- NoBonusRoll - options panel
-- Deliberately built from plain widgets (no dropdowns, no Blizzard options
-- templates) so the same file works on retail and on Classic clients.

local ADDON_NAME, NS = ...

local PANEL_TITLE = "NoBonusRoll"

local COLOR_DISMISS = "|cffff6060"
local COLOR_KEEP    = "|cff60ff60"

local panel, widgets

--------------------------------------------------------------------------------
-- Small widget builders
--------------------------------------------------------------------------------

local function CreateHeader(parent, text, x, y)
    local fs = parent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    fs:SetPoint("TOPLEFT", x, y)
    fs:SetText(text)
    return fs
end

local function CreateHelp(parent, text, x, y, width)
    local fs = parent:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    fs:SetPoint("TOPLEFT", x, y)
    fs:SetJustifyH("LEFT")
    if width then
        fs:SetWidth(width)
    end
    fs:SetText(text)
    return fs
end

local function CreateCheckbox(parent, label, tooltip, x, y, onClick)
    local check = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    check:SetSize(24, 24)
    check:SetPoint("TOPLEFT", x, y)

    local fs = check:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    fs:SetPoint("LEFT", check, "RIGHT", 2, 1)
    fs:SetText(label)
    check.label = fs

    check:SetScript("OnClick", function(self)
        onClick(self:GetChecked() and true or false)
    end)

    if tooltip then
        check:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(label, 1, 1, 1)
            GameTooltip:AddLine(tooltip, nil, nil, nil, true)
            GameTooltip:Show()
        end)
        check:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end

    return check
end

local function CreateButton(parent, label, width, x, y, onClick)
    local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetSize(width, 22)
    button:SetPoint("TOPLEFT", x, y)
    button:SetText(label)
    button:SetScript("OnClick", onClick)
    return button
end

--------------------------------------------------------------------------------
-- Panel
--------------------------------------------------------------------------------

local function BuildPanel()
    panel = CreateFrame("Frame", "NoBonusRollOptionsPanel", UIParent)
    panel:Hide()
    panel.name = PANEL_TITLE

    widgets = { difficulties = {}, rows = {} }

    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText(PANEL_TITLE)

    CreateHelp(panel, "Version " .. NS.VERSION ..
        "  -  passes on bonus rolls for the raids and difficulties you choose.", 18, -38, 560)

    local y = -64

    widgets.enabled = CreateCheckbox(panel, "Enable automatic bonus roll passing",
        "Master switch. When unchecked, every bonus roll prompt is left alone.",
        16, y, function(checked)
            NS.db.enabled = checked
        end)
    y = y - 26

    widgets.announce = CreateCheckbox(panel, "Print a message when a roll is passed",
        "Writes a line to the chat frame so you can see what was dismissed and why.",
        16, y, function(checked)
            NS.db.announce = checked
        end)
    y = y - 26

    widgets.invert = CreateCheckbox(panel, "Invert: keep only what is selected, pass on everything else",
        "Off (default): rolls matching your selection are passed on.\n" ..
        "On: rolls matching your selection are kept, everything else is passed on.",
        16, y, function(checked)
            NS.db.mode = checked and NS.MODE_KEEP_LISTED or NS.MODE_DISMISS_LISTED
            NS:RefreshOptions()
        end)
    y = y - 30

    local delayLabel = CreateHelp(panel, "Wait before passing (seconds):", 20, y + 4, 200)
    delayLabel:SetFontObject("GameFontHighlight")
    widgets.delay = CreateFrame("EditBox", nil, panel, "InputBoxTemplate")
    widgets.delay:SetSize(40, 20)
    widgets.delay:SetPoint("TOPLEFT", 210, y + 6)
    widgets.delay:SetAutoFocus(false)
    widgets.delay:SetNumeric(false)
    widgets.delay:SetMaxLetters(4)
    widgets.delay:SetScript("OnEnterPressed", function(self)
        local value = tonumber(self:GetText()) or 0
        if value < 0 then value = 0 end
        if value > 30 then value = 30 end
        NS.db.delay = value
        self:SetText(tostring(value))
        self:ClearFocus()
    end)
    widgets.delay:SetScript("OnEscapePressed", function(self)
        self:SetText(tostring(NS.db.delay or 0))
        self:ClearFocus()
    end)
    CreateHelp(panel, "0 passes instantly. A short delay lets you cancel by clicking Roll yourself.",
        258, y + 2, 320)
    y = y - 32

    -- Difficulties -------------------------------------------------------------
    widgets.difficultyHeader = CreateHeader(panel, "Difficulties", 16, y)
    y = y - 18
    widgets.difficultyHelp = CreateHelp(panel, "", 18, y, 560)
    y = y - 20

    local column, rowY = 0, y
    for _, difficultyID in ipairs(NS.DIFFICULTY_ORDER) do
        if NS:IsKnownDifficulty(difficultyID) then
            local x = 16 + column * 285
            local check = CreateCheckbox(panel, NS:GetDifficultyName(difficultyID), nil, x, rowY,
                function(checked)
                    NS:SetDifficultyListed(difficultyID, checked)
                end)
            check.difficultyID = difficultyID
            widgets.difficulties[#widgets.difficulties + 1] = check

            column = column + 1
            if column == 2 then
                column = 0
                rowY = rowY - 22
            end
        end
    end
    if column ~= 0 then
        rowY = rowY - 22
    end
    y = rowY - 14

    -- Per raid rules -----------------------------------------------------------
    CreateHeader(panel, "Rules for single raids", 16, y)
    y = y - 18
    CreateHelp(panel, "These win over the difficulty selection above, so you can make one raid an exception.",
        18, y, 560)
    y = y - 20

    widgets.addThis = CreateButton(panel, "Add current raid (this difficulty)", 200, 16, y, function()
        NS:AddRuleForCurrentInstance(false)
    end)
    widgets.addAll = CreateButton(panel, "Add current raid (all difficulties)", 200, 222, y, function()
        NS:AddRuleForCurrentInstance(true)
    end)
    widgets.clearRules = CreateButton(panel, "Clear all", 90, 428, y, function()
        wipe(NS.db.instances)
        NS:RefreshOptions()
    end)
    y = y - 26

    -- Scrolling rule list. Built by hand instead of UIPanelScrollFrameTemplate
    -- so it does not depend on templates that differ between clients.
    local listHeight = 132
    local list = CreateFrame("ScrollFrame", nil, panel)
    list:SetPoint("TOPLEFT", 16, y)
    list:SetSize(520, listHeight)

    local background = list:CreateTexture(nil, "BACKGROUND")
    background:SetPoint("TOPLEFT", -4, 4)
    background:SetPoint("BOTTOMRIGHT", 4, -4)
    background:SetColorTexture(0, 0, 0, 0.35)

    local content = CreateFrame("Frame", nil, list)
    content:SetSize(520, listHeight)
    list:SetScrollChild(content)

    list:EnableMouseWheel(true)
    list:SetScript("OnMouseWheel", function(self, delta)
        local maxScroll = math.max(0, content:GetHeight() - self:GetHeight())
        local scroll = math.min(maxScroll, math.max(0, self:GetVerticalScroll() - delta * 22))
        self:SetVerticalScroll(scroll)
    end)

    widgets.list = list
    widgets.listContent = content

    widgets.empty = content:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    widgets.empty:SetPoint("TOPLEFT", 6, -6)
    widgets.empty:SetText("No raid specific rules. Enter a raid and use the buttons above, or type /nbr here dismiss.")

    y = y - listHeight - 12
    CreateHelp(panel, "Chat commands: /nbr help  -  /nbr status  -  /nbr here dismiss  -  /nbr pause 30",
        18, y, 560)

    panel.OnRefresh = function() NS:RefreshOptions() end
    panel.OnCommit  = function() end
    panel.OnDefault = function() NS:ResetDB() end
    panel:SetScript("OnShow", function() NS:RefreshOptions() end)

    return panel
end

--------------------------------------------------------------------------------
-- Rule rows
--------------------------------------------------------------------------------

local function AcquireRow(index)
    local row = widgets.rows[index]
    if row then
        return row
    end

    row = CreateFrame("Frame", nil, widgets.listContent)
    row:SetSize(510, 22)

    row.label = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    row.label:SetPoint("LEFT", 6, 0)
    row.label:SetJustifyH("LEFT")
    row.label:SetWidth(360)

    row.remove = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    row.remove:SetSize(24, 20)
    row.remove:SetPoint("RIGHT", -4, 0)
    row.remove:SetText("X")
    row.remove:SetScript("OnClick", function(self)
        local data = self:GetParent().data
        NS:SetInstanceRule(data.instanceID, data.difficultyKey, nil)
        NS:RefreshOptions()
    end)

    row.toggle = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    row.toggle:SetSize(90, 20)
    row.toggle:SetPoint("RIGHT", row.remove, "LEFT", -4, 0)
    row.toggle:SetScript("OnClick", function(self)
        local data = self:GetParent().data
        local newRule = (data.rule == NS.RULE_DISMISS) and NS.RULE_KEEP or NS.RULE_DISMISS
        NS:SetInstanceRule(data.instanceID, data.difficultyKey, newRule)
        NS:RefreshOptions()
    end)

    widgets.rows[index] = row
    return row
end

--------------------------------------------------------------------------------
-- Refresh
--------------------------------------------------------------------------------

function NS:RefreshOptions()
    if not panel then
        return
    end

    local db = self.db
    local inverted = db.mode == self.MODE_KEEP_LISTED

    widgets.enabled:SetChecked(db.enabled)
    widgets.announce:SetChecked(db.announce)
    widgets.invert:SetChecked(inverted)
    widgets.delay:SetText(tostring(db.delay or 0))

    widgets.difficultyHelp:SetText(inverted
        and "Bonus rolls in the checked difficulties are kept. Everything else is passed on automatically."
        or  "Bonus rolls in the checked difficulties are passed on automatically.")

    for _, check in ipairs(widgets.difficulties) do
        check:SetChecked(self:IsDifficultyListed(check.difficultyID))
    end

    local inInstance = self:GetContext().instanceID ~= nil
    widgets.addThis:SetEnabled(inInstance)
    widgets.addAll:SetEnabled(inInstance)

    local rules = self:GetRuleList()
    for index, data in ipairs(rules) do
        local row = AcquireRow(index)
        row.data = data
        row:SetPoint("TOPLEFT", 0, -(index - 1) * 22)
        row.label:SetText(("%s  |cffaaaaaa%s|r"):format(data.instanceName, self:DescribeRuleKey(data.difficultyKey)))
        if data.rule == self.RULE_DISMISS then
            row.toggle:SetText(COLOR_DISMISS .. "Pass|r")
        else
            row.toggle:SetText(COLOR_KEEP .. "Keep|r")
        end
        row:Show()
    end
    for index = #rules + 1, #widgets.rows do
        widgets.rows[index]:Hide()
    end

    widgets.empty:SetShown(#rules == 0)
    widgets.listContent:SetHeight(math.max(widgets.list:GetHeight(), #rules * 22 + 4))
end

--------------------------------------------------------------------------------
-- Helpers used by both the panel and the chat commands
--------------------------------------------------------------------------------

function NS:AddRuleForCurrentInstance(allDifficulties, rule)
    local ctx = self:GetContext()
    if not ctx.instanceID then
        self:Print("You are not in an instance right now.")
        return false
    end

    self.db.seen[ctx.instanceID] = ctx.instanceName
    local key = allDifficulties and self.ALL_DIFFICULTIES or ctx.difficultyID
    self:SetInstanceRule(ctx.instanceID, key, rule or self.RULE_DISMISS)

    local entry = self.db.instances[ctx.instanceID]
    if entry then
        entry.name = ctx.instanceName
    end

    self:Print("%s: bonus rolls in %s (%s) will now be %s.",
        rule == self.RULE_KEEP and "Keep rule added" or "Pass rule added",
        ctx.instanceName,
        self:DescribeRuleKey(key),
        rule == self.RULE_KEEP and "kept" or "passed automatically")

    self:RefreshOptions()
    return true
end

--------------------------------------------------------------------------------
-- Registration
--------------------------------------------------------------------------------

function NS:SetupOptions()
    BuildPanel()

    if Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory then
        local category = Settings.RegisterCanvasLayoutCategory(panel, PANEL_TITLE)
        category.ID = PANEL_TITLE
        Settings.RegisterAddOnCategory(category)
        self.settingsCategory = category
    elseif InterfaceOptions_AddCategory then
        InterfaceOptions_AddCategory(panel)
    end

    self:RefreshOptions()
end

function NS:OpenOptions()
    if self.settingsCategory and Settings and Settings.OpenToCategory then
        Settings.OpenToCategory(self.settingsCategory:GetID())
    elseif InterfaceOptionsFrame_OpenToCategory then
        -- Long standing Blizzard bug: the first call only opens the parent list.
        InterfaceOptionsFrame_OpenToCategory(panel)
        InterfaceOptionsFrame_OpenToCategory(panel)
    else
        self:Print("Could not open the options window; use /nbr help instead.")
    end
end
