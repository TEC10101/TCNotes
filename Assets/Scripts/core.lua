--------------------------------------------------
-- Section 1: Event Frame Registration
--------------------------------------------------
local addonName = ... -- should resolve to folder "TCNotes"

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("PLAYER_LEVEL_UP")

--------------------------------------------------
-- Section 2: Top-level Variables and SavedVariables Schema
--------------------------------------------------
TCNotes = TCNotes or {}
local M = TCNotes
M.charKey = nil
M.initialized = false
M.restoring = false
M.frame = nil

-- SavedVariables root: TCNotesDB
-- Schema:
-- TCNotesDB = {
--   globalNotes = { "note text", ... },
--   charNotes = { ["Char-Realm"] = { "note", ... } },
--   frameState = { x=number, y=number, width=number, height=number, shown=boolean },
-- }

local function InitSavedVariables()
    TCNotesDB = TCNotesDB or {}
    TCNotesDB.globalNotes = TCNotesDB.globalNotes or {}
    TCNotesDB.charNotes = TCNotesDB.charNotes or {}
    -- load DB or initialize defaults
    TCNotesDB.frameState = TCNotesDB.frameState or {
        width = 400,
        height = 500,
        -- expanded height is used when not collapsed
        expandedHeight = 500,
        x = nil,
        y = nil,
        shown = true,
        strata = "HIGH",
        collapsed = false,
        locked = false
    }
end

-- Returns the character key in the format Name-Realm.
-- Used to index character-specific notes.
local function GetCharKey()
    local name = UnitName("player") or "Unknown"
    local realm = GetRealmName() or "Realm"
    return name .. "-" .. realm
end

-- Ensures the character notes table exists for the current character.
-- Called during initialization and note access.
local function EnsureCharTable()
    if not M.charKey then
        M.charKey = GetCharKey()
    end
    if not M.charKey then return end
    TCNotesDB.charNotes[M.charKey] = TCNotesDB.charNotes[M.charKey] or {}
end

-- Trims whitespace from the start and end of a string.
-- Utility for command and note text processing.
local function Trim(s)
    return (s or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

--------------------------------------------------
-- Section 4: DB Management Methods
--------------------------------------------------



function M:GetNotes(section)
    if section == "global" then
        return TCNotesDB.globalNotes
    elseif section == "char" then
        EnsureCharTable()
        return TCNotesDB.charNotes[M.charKey] or {}
    end
    return {}
end

function M:AddNote(section, text)
    if text == "" then return end
    local list = M:GetNotes(section)
    -- store notes as tables to allow metadata (backwards-compatible with strings)
    table.insert(list, 1, { text = text })
end

function M:DeleteNote(section, index)
    local list = M:GetNotes(section)
    if list and index >=1 and index <= #list then
        table.remove(list, index)
    end
end

function M:UpdateNote(section, index, text)
    local list = M:GetNotes(section)
    if not list or index < 1 or index > #list then return end
    -- If caller passed a table, replace the stored entry entirely
    if type(text) == "table" then
        list[index] = text
        return
    end
    -- If caller passed a string, update the .text field if we have a table, otherwise replace
    if text == "" then
        table.remove(list, index)
    else
        if type(list[index]) == "table" then
            list[index].text = text
        else
            list[index] = text
        end
    end
end

local function GetNoteText(note)
    if type(note) == "table" then return note.text or "" end
    return tostring(note or "")
end

-- Simple reminder popup frame (created lazily)
local reminderPopup
local function ShowReminderPopup(msgs)
    if not reminderPopup then
        reminderPopup = CreateFrame("Frame", "TCNotesReminderPopup", UIParent, "BackdropTemplate")
        reminderPopup:SetSize(440, 160)
        reminderPopup:SetPoint("CENTER")
        reminderPopup:SetBackdrop({ bgFile = "Interface/DialogFrame/UI-DialogBox-Background", edgeFile = "Interface/DialogFrame/UI-DialogBox-Border", tile = true, tileSize = 32, edgeSize = 16, insets = { left = 8, right = 8, top = 8, bottom = 8 } })
        reminderPopup.text = reminderPopup:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        reminderPopup.text:SetPoint("TOPLEFT", 12, -12)
        reminderPopup.text:SetPoint("TOPRIGHT", -12, -12)
        reminderPopup.text:SetJustifyH("LEFT")
        reminderPopup.text:SetJustifyV("TOP")
        reminderPopup.text:SetWordWrap(true)
        reminderPopup.text:SetWidth(416)
        reminderPopup.ok = CreateFrame("Button", nil, reminderPopup, "UIPanelButtonTemplate")
        reminderPopup.ok:SetSize(80, 24)
        reminderPopup.ok:SetPoint("BOTTOM", 0, 8)
        reminderPopup.ok:SetText("OK")
        reminderPopup.ok:SetScript("OnClick", function() reminderPopup:Hide() end)
    end
    -- msgs can be a string or table of strings
    local out = ""
    if type(msgs) == "table" then
        for i = 1, #msgs do
            out = out .. (msgs[i] or "")
            if i < #msgs then out = out .. "\n\n" end
        end
    else
        out = tostring(msgs or "Reminder")
    end
    reminderPopup.text:SetText(out)
    reminderPopup:Show()
end

-- Pending level reminders when popup must be deferred (e.g., in combat)
local pendingLevelReminders = nil

local function QueueOrShowLevelReminders(reminders)
    if UnitAffectingCombat and UnitAffectingCombat("player") then
        -- Already cleared the reminders in the lists; refresh UI now so icons update
        if M and M.frame and M.RefreshAll then M:RefreshAll() end
        if M.SaveFrameState then M:SaveFrameState() end
        pendingLevelReminders = reminders
        -- Register to show once we leave combat
        eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    else
        if M and M.frame and M.RefreshAll then M:RefreshAll() end
        ShowReminderPopup(reminders)
        if M.SaveFrameState then M:SaveFrameState() end
    end
end

-- Scans notes for next-login reminders and shows them
local function CheckRemindersOnLogin()
    local reminders = {}

    -- Global notes: next_login/every_login apply to whoever logs in
    local g = M:GetNotes("global")
    for i = 1, #g do
        local n = g[i]
        if type(n) == "table" and n.reminder and (n.reminder.type == "next_login" or n.reminder.type == "every_login") then
            table.insert(reminders, "Global: " .. (n.text or "(note)"))
            -- next_login is a one-shot, clear it; every_login persists
            if n.reminder.type == "next_login" then
                n.reminder = nil
            end
        end
    end

    -- Character notes: only process the notes for the character we're currently logged into.
    -- EnsureCharTable() makes sure M.charKey is set and the table exists.
    EnsureCharTable()
    local c = TCNotesDB.charNotes[M.charKey] or {}
    for i = 1, #c do
        local n = c[i]
        if type(n) == "table" and n.reminder and (n.reminder.type == "next_login" or n.reminder.type == "every_login") then
            table.insert(reminders, "Char: " .. (n.text or "(note)"))
            if n.reminder.type == "next_login" then
                n.reminder = nil
            end
        end
    end

    if #reminders > 0 then
        -- Refresh UI so any cleared reminders update their icons immediately
        if M and M.frame and M.RefreshAll then M:RefreshAll() end
        ShowReminderPopup(reminders)
        if M.SaveFrameState then M:SaveFrameState() end
    end
end

-- Saves the current frame state (size, position, visibility, etc.) to SavedVariables.
-- Called when frame is moved, resized, or toggled.
function M:SaveFrameState()
    if not M.frame then return end
    -- skip transient creation
    if M.restoring then
      --M:Print("Skipping SaveFrameState during restore")
      return
    end
    TCNotesDB.frameState.width = M.frame:GetWidth()
    if not M.frame.collapsed then
        TCNotesDB.frameState.height = M.frame:GetHeight()
        TCNotesDB.frameState.expandedHeight = TCNotesDB.frameState.height
    end
    TCNotesDB.frameState.strata = M.frame:GetFrameStrata()
    TCNotesDB.frameState.collapsed = M.frame.collapsed and true or false
    TCNotesDB.frameState.shown = M.frame:IsShown() or false
    TCNotesDB.frameState.locked = M.frame.locked and true or false
    local left = M.frame:GetLeft()
    local top = M.frame:GetTop()
    if left and top then
        TCNotesDB.frameState.x = left
        TCNotesDB.frameState.y = top
    end
end

--------------------------------------------------
-- Section 5: Frame/UI Methods
--------------------------------------------------
function M:Toggle()
    if not M.frame then return end
    if M.frame:IsShown() then
      M.frame:Hide()
      TCNotesDB.frameState.shown = false
    else
            M.frame:Show()
            TCNotesDB.frameState.shown = true
            -- If the frame implements deferred refresh (pendingRefresh), use it so
            -- layout computations happen after the frame becomes visible. Otherwise
            -- fall back to immediate refresh.
            if M.frame.pendingRefresh ~= nil then
                    M.frame.pendingRefresh = true
            else
                    M:RefreshAll()
            end
    end
    if M.SaveFrameState then M:SaveFrameState() end
end

-- Section 6: Slash Command Registration
SLASH_TCNOTES1 = "/notes"
SlashCmdList["TCNOTES"] = function(msg)
    msg = Trim(msg or "")
    if msg == "debug" then
        InitSavedVariables()
        EnsureCharTable()
        local g = #TCNotesDB.globalNotes
        local c = 0
        if M.charKey and TCNotesDB.charNotes[M.charKey] then
            c = #TCNotesDB.charNotes[M.charKey]
        end
    else
        M:Toggle()
    end
end

local function InitializeAddon()
    if M.initialized then return end
    InitSavedVariables()
    EnsureCharTable() -- charKey ensured lazily inside
    if TCNotes_CreateFrame then
        M.restoring = true
        TCNotes_CreateFrame(TCNotesDB.frameState)
        M.restoring = false
    end
    M.initialized = true
end

-- Section 8: Event Handler (after dependencies)
eventFrame:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" and arg1 == addonName then
        InitializeAddon()
        -- Initialization complete; reminders will be checked on PLAYER_LOGIN
    elseif event == "PLAYER_LOGIN" then
        EnsureCharTable()
        if M.frame and M.frame:IsShown() then M:RefreshAll() end
        CheckRemindersOnLogin()
    elseif event == "PLAYER_LEVEL_UP" then
        local newLevel = tonumber(arg1) or 0
        if newLevel > 0 then
            local reminders = {}
            local function checkLevelForList(list, scope)
                for i = 1, #list do
                    local n = list[i]
                    if type(n) == "table" and n.reminder and n.reminder.type == "level" then
                        local target = tonumber(n.reminder.level) or 0
                        if target > 0 and newLevel >= target then
                            table.insert(reminders, (scope or "Note") .. ": " .. (n.text or "(note)"))
                            -- clear the reminder so it doesn't fire again
                            n.reminder = nil
                        end
                    end
                end
            end
            checkLevelForList(M:GetNotes("global") or {}, "Global")
            checkLevelForList(M:GetNotes("char") or {}, "Char")
            if #reminders > 0 then
                QueueOrShowLevelReminders(reminders)
            end
        end
    elseif event == "PLAYER_REGEN_ENABLED" then
        if pendingLevelReminders and #pendingLevelReminders > 0 then
            ShowReminderPopup(pendingLevelReminders)
            pendingLevelReminders = nil
        end
        -- No longer need to listen for regen enabled until next time
        eventFrame:UnregisterEvent("PLAYER_REGEN_ENABLED")
    end
end)

-- Prints a message to the default chat frame, prefixed with TCNotes.
-- Used for status and debug output.
function M:Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99TCNotes|r: " .. tostring(msg))
end

M:Print("Loaded. Use /notes to toggle.")