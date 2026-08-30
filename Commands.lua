-- NoBonusRoll - chat commands

local ADDON_NAME, NS = ...

local HL = "|cffffd100" -- highlight for command names

local function Bool(value, defaultToggle)
    value = value and value:lower()
    if value == "on" or value == "1" or value == "yes" or value == "true" or value == "enable" then
        return true
    elseif value == "off" or value == "0" or value == "no" or value == "false" or value == "disable" then
        return false
    end
    return defaultToggle
end

local function ParseRule(value)
    value = value and value:lower()
    if value == "dismiss" or value == "pass" or value == "no" then
        return NS.RULE_DISMISS
    elseif value == "keep" or value == "roll" or value == "yes" then
        return NS.RULE_KEEP
    elseif value == "clear" or value == "remove" or value == "delete" or value == "none" then
        return "CLEAR"
    end
    return nil
end

local function Help()
    NS:Print("commands (%s/nbr|r or %s/nobonusroll|r):", HL, HL)
    local lines = {
        { "",                          "open the options window" },
        { "on | off",                  "master switch" },
        { "status",                    "what would happen with the current raid and difficulty" },
        { "diff <name or id> [on|off]","put a difficulty on the list, e.g. " .. HL .. "/nbr diff normal on|r" },
        { "here [pass|keep|clear]",    "rule for the raid you are in, current difficulty only" },
        { "raid [pass|keep|clear]",    "rule for the raid you are in, every difficulty" },
        { "rule <instance> <all|difficulty> <pass|keep|clear>", "rule for a raid you are not in" },
        { "list",                      "show every rule" },
        { "raids",                     "show the raids you have visited and their ids" },
        { "invert [on|off]",           "keep only what is listed and pass on everything else" },
        { "delay <seconds>",           "wait before passing (0 - 30)" },
        { "announce [on|off]",         "chat message when a roll is passed" },
        { "pause [minutes]",           "stop passing for a while (no minutes = cancel the pause)" },
        { "next",                      "keep the very next bonus roll" },
        { "reset",                     "restore the default settings" },
    }
    for _, line in ipairs(lines) do
        if line[1] == "" then
            NS:Print("  %s/nbr|r - %s", HL, line[2])
        else
            NS:Print("  %s/nbr %s|r - %s", HL, line[1], line[2])
        end
    end
end

local function Status()
    local ctx = NS:GetContext()
    local dismiss, reason = NS:ShouldDismiss(ctx)

    NS:Print("%s, mode: %s.",
        NS.db.enabled and "|cff60ff60enabled|r" or "|cffff6060disabled|r",
        NS.db.mode == NS.MODE_KEEP_LISTED and "keep only what is listed" or "pass what is listed")

    local paused, minutes = NS:IsPaused()
    if paused then
        NS:Print("Paused for another %d minute(s).", minutes)
    end

    NS:Print("Here (%s): a bonus roll would be %s - %s.",
        NS:DescribeContext(ctx),
        dismiss and "|cffff6060passed automatically|r" or "|cff60ff60left alone|r",
        reason)

    local listed = {}
    for difficultyID in pairs(NS.db.difficulties) do
        listed[#listed + 1] = NS:GetDifficultyName(difficultyID)
    end
    table.sort(listed)
    NS:Print("Difficulties on the list: %s.", #listed > 0 and table.concat(listed, ", ") or "none")
    NS:Print("Bonus rolls passed so far: %d.", NS.db.stats.dismissed or 0)
end

local function ListRules()
    local rules = NS:GetRuleList()
    if #rules == 0 then
        NS:Print("No raid specific rules.")
        return
    end
    NS:Print("Raid specific rules:")
    for _, data in ipairs(rules) do
        NS:Print("  %s (%d) - %s: %s", data.instanceName, data.instanceID,
            NS:DescribeRuleKey(data.difficultyKey),
            data.rule == NS.RULE_DISMISS and "|cffff6060pass|r" or "|cff60ff60keep|r")
    end
end

local function ListSeen()
    local seen = {}
    for instanceID, name in pairs(NS.db.seen) do
        seen[#seen + 1] = { id = instanceID, name = name }
    end
    if #seen == 0 then
        NS:Print("No raids visited yet since the addon was installed.")
        return
    end
    table.sort(seen, function(a, b) return a.name < b.name end)
    NS:Print("Visited instances (use the id with %s/nbr rule|r):", HL)
    for _, entry in ipairs(seen) do
        NS:Print("  %s - %d", entry.name, entry.id)
    end
end

local function SetDifficulty(args)
    local key, state = args:match("^(.-)%s*(%S*)$")
    if state ~= "" and Bool(state, nil) == nil then
        key, state = args, ""
    end
    key = key:gsub("%s+$", "")

    if key == "" then
        NS:Print("Usage: %s/nbr diff <name or id> [on|off]|r", HL)
        return
    end

    local matches = {}
    local asID = tonumber(key)
    if asID then
        matches[1] = asID
    else
        local needle = key:lower()
        for _, difficultyID in ipairs(NS.DIFFICULTY_ORDER) do
            if NS:IsKnownDifficulty(difficultyID)
               and NS:GetDifficultyName(difficultyID):lower():find(needle, 1, true) then
                matches[#matches + 1] = difficultyID
            end
        end
    end

    if #matches == 0 then
        NS:Print("No difficulty matches '%s'. Try %s/nbr status|r or use a numeric id.", key, HL)
        return
    end

    for _, difficultyID in ipairs(matches) do
        local listed = Bool(state, not NS:IsDifficultyListed(difficultyID))
        NS:SetDifficultyListed(difficultyID, listed)
        if NS.db.mode == NS.MODE_KEEP_LISTED then
            NS:Print("%s: bonus rolls will be %s.", NS:GetDifficultyName(difficultyID),
                listed and "|cff60ff60kept|r" or "|cffff6060passed automatically|r")
        else
            NS:Print("%s: bonus rolls will be %s.", NS:GetDifficultyName(difficultyID),
                listed and "|cffff6060passed automatically|r" or "|cff60ff60left alone|r")
        end
    end

    NS:RefreshOptions()
end

local function SetHere(args, allDifficulties)
    local rule = ParseRule(args) or NS.RULE_DISMISS

    if rule == "CLEAR" then
        local ctx = NS:GetContext()
        if not ctx.instanceID then
            NS:Print("You are not in an instance right now.")
            return
        end
        local key = allDifficulties and NS.ALL_DIFFICULTIES or ctx.difficultyID
        NS:SetInstanceRule(ctx.instanceID, key, nil)
        NS:Print("Removed the rule for %s (%s).", ctx.instanceName, NS:DescribeRuleKey(key))
        NS:RefreshOptions()
        return
    end

    NS:AddRuleForCurrentInstance(allDifficulties, rule)
end

local function SetRule(args)
    local instanceID, key, rule = args:match("^(%S+)%s+(%S+)%s+(%S+)$")
    if not instanceID then
        NS:Print("Usage: %s/nbr rule <instanceID> <all|difficultyID> <pass|keep|clear>|r", HL)
        NS:Print("Use %s/nbr raids|r to look up instance ids.", HL)
        return
    end

    instanceID = tonumber(instanceID)
    if not instanceID then
        NS:Print("The instance id has to be a number, see %s/nbr raids|r.", HL)
        return
    end

    local difficultyKey = (key:lower() == "all") and NS.ALL_DIFFICULTIES or tonumber(key)
    if not difficultyKey then
        NS:Print("The difficulty has to be 'all' or a numeric difficulty id.")
        return
    end

    local parsed = ParseRule(rule)
    if not parsed then
        NS:Print("The rule has to be pass, keep or clear.")
        return
    end

    NS:SetInstanceRule(instanceID, difficultyKey, parsed ~= "CLEAR" and parsed or nil)
    NS:Print("%s: %s -> %s", NS:DescribeInstance(instanceID), NS:DescribeRuleKey(difficultyKey),
        parsed == "CLEAR" and "no rule"
        or (parsed == NS.RULE_DISMISS and "|cffff6060pass|r" or "|cff60ff60keep|r"))
    NS:RefreshOptions()
end

local function Handler(input)
    input = (input or ""):gsub("^%s+", ""):gsub("%s+$", "")
    local command, args = input:match("^(%S*)%s*(.-)$")
    command = command:lower()

    if command == "" then
        NS:OpenOptions()

    elseif command == "help" or command == "?" then
        Help()

    elseif command == "on" or command == "off" or command == "toggle" then
        if command == "toggle" then
            NS.db.enabled = not NS.db.enabled
        else
            NS.db.enabled = (command == "on")
        end
        NS:Print("Automatic passing is now %s.",
            NS.db.enabled and "|cff60ff60on|r" or "|cffff6060off|r")
        NS:RefreshOptions()

    elseif command == "status" then
        Status()

    elseif command == "diff" or command == "difficulty" then
        SetDifficulty(args)

    elseif command == "here" then
        SetHere(args, false)

    elseif command == "raid" then
        SetHere(args, true)

    elseif command == "rule" then
        SetRule(args)

    elseif command == "list" then
        ListRules()

    elseif command == "raids" or command == "instances" then
        ListSeen()

    elseif command == "invert" then
        local inverted = Bool(args, NS.db.mode ~= NS.MODE_KEEP_LISTED)
        NS.db.mode = inverted and NS.MODE_KEEP_LISTED or NS.MODE_DISMISS_LISTED
        NS:Print("Mode: %s.", inverted and "keep only what is listed, pass on everything else"
            or "pass on what is listed, keep everything else")
        NS:RefreshOptions()

    elseif command == "delay" then
        local seconds = tonumber(args)
        if not seconds then
            NS:Print("Current delay: %s second(s).", tostring(NS.db.delay or 0))
        else
            NS.db.delay = math.max(0, math.min(30, seconds))
            NS:Print("Delay set to %s second(s).", tostring(NS.db.delay))
            NS:RefreshOptions()
        end

    elseif command == "announce" then
        NS.db.announce = Bool(args, not NS.db.announce)
        NS:Print("Chat messages are %s.", NS.db.announce and "on" or "off")
        NS:RefreshOptions()

    elseif command == "pause" then
        local minutes = NS:Pause(args)
        if minutes then
            NS:Print("Paused for %d minute(s). Bonus rolls are left alone until then.", minutes)
        else
            NS:Print("Pause cancelled.")
        end

    elseif command == "next" then
        NS.skipNextPrompt = true
        NS:Print("The next bonus roll prompt will be left alone.")

    elseif command == "reset" then
        NS:ResetDB()
        NS:Print("Settings restored to their defaults.")

    else
        NS:Print("Unknown command '%s'.", command)
        Help()
    end
end

function NS:SetupCommands()
    SLASH_NOBONUSROLL1 = "/nbr"
    SLASH_NOBONUSROLL2 = "/nobonusroll"
    SlashCmdList["NOBONUSROLL"] = Handler

    self.CommandHandler = Handler
end
