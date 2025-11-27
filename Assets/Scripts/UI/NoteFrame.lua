--------------------------------------------------
-- Section 1: Module setup and constants
--------------------------------------------------
local M = TCNotes
if not M then return end

local LINE_HEIGHT = 16
local MIN_WIDTH = 240
local MIN_HEIGHT = 300
-- Base target height when frame is collapsed; will be raised if backdrop insets demand more.
local COLLAPSED_BASE_HEIGHT = 40
-- Extra vertical padding added to measured row heights to avoid overlap when
-- wrapping occurs. Increase if your font or theme needs more breathing room.
local ROW_PADDING = 8

local sections = {
    { key = "global", title = "Global Notes" },
    { key = "char", title = "Character Notes" },
}

--------------------------------------------------
-- Link insertion support (SHIFT-click item links)
--------------------------------------------------
-- Returns the TCNotes editbox that currently has focus, if any.
-- Checks per-section add boxes first, then inline row edit boxes.
function M:GetFocusedNotesEditBox()
    if not M or not M.frame then return nil end
    -- Section add boxes
    for _, def in ipairs(sections) do
        local c = def.container
        local eb = c and c.addBox
        if eb and eb.HasFocus and eb:HasFocus() then
            return eb
        end
    end
    -- Inline row edit boxes
    for _, def in ipairs(sections) do
        local c = def.container
        local rows = c and c.rows
        if rows then
            for i = 1, #rows do
                local row = rows[i]
                local eb = row and row.editBox
                if eb and eb.HasFocus and eb:HasFocus() then
                    return eb
                end
            end
        end
    end
    return nil
end

-- One-time wrapper around ChatEdit_InsertLink so SHIFT-clicked links
-- go into the focused TCNotes editbox when applicable.
do
    local _origChatEdit_InsertLink
    function M:SetupLinkHook()
        if M._linkHooked then return end
        -- Only proceed if the global inserter exists
        if type(ChatEdit_InsertLink) ~= "function" then
            return
        end
        _origChatEdit_InsertLink = ChatEdit_InsertLink
        ChatEdit_InsertLink = function(link)
            -- Prefer inserting into TCNotes if one of our editboxes has focus
            local eb = M.GetFocusedNotesEditBox and M:GetFocusedNotesEditBox()
            if eb and eb.Insert then
                eb:Insert(link)
                return true
            end
            -- Otherwise, fall back to original behavior (chat, other addons)
            if _origChatEdit_InsertLink then
                return _origChatEdit_InsertLink(link)
            end
            return false
        end
        M._linkHooked = true
    end
end

-- Removes leading/trailing whitespace from a string for clean inputs.
local function Trim(s)
    return (s or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

-- Extracts the first hyperlink payload between |H and |h (e.g. item:1234:...)
local function ExtractFirstHyperlink(s)
    if type(s) ~= "string" or s == "" then return nil end
    -- capture minimal substring between |H and |h (works for item, spell, quest, etc.)
    local link = s:match("|H(.-)|h")
    return link
end

-- Reminder dialog (lazy-created)
local ReminderDlg
local function EnsureReminderDialog()
    if ReminderDlg then return ReminderDlg end
    local dlg = CreateFrame("Frame", "TCNotes_ReminderDlg", UIParent, "BackdropTemplate")
    dlg:SetSize(300, 140)
    dlg:SetPoint("CENTER")
    dlg:SetBackdrop({ bgFile = "Interface/DialogFrame/UI-DialogBox-Background", edgeFile = "Interface/DialogFrame/UI-DialogBox-Border", tile = true, tileSize = 32, edgeSize = 16, insets = { left = 8, right = 8, top = 8, bottom = 8 } })
    dlg.title = dlg:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    dlg.title:SetPoint("TOP", 0, -10)
    dlg.title:SetText("Remind me at")

    dlg.dropLabel = dlg:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    dlg.dropLabel:SetPoint("TOPLEFT", 12, -36)
    dlg.dropLabel:SetText("Type:")

    dlg.nextBtn = CreateFrame("Button", nil, dlg, "UIPanelButtonTemplate")
    dlg.nextBtn:SetSize(90, 22)
    -- center the three type buttons as a group
    -- compute an approximate left offset so the three 90px buttons + gaps (8px) are centered
    dlg.nextBtn:SetPoint("TOP", dlg, "TOP", -92, -48)
    dlg.nextBtn:SetText("Next Login")
    dlg.everyBtn = CreateFrame("Button", nil, dlg, "UIPanelButtonTemplate")
    dlg.everyBtn:SetSize(90, 22)
    dlg.everyBtn:SetPoint("LEFT", dlg.nextBtn, "RIGHT", 4, 0)
    dlg.everyBtn:SetText("Every Login")
    dlg.levelBtn = CreateFrame("Button", nil, dlg, "UIPanelButtonTemplate")
    dlg.levelBtn:SetSize(90, 22)
    dlg.levelBtn:SetPoint("LEFT", dlg.everyBtn, "RIGHT", 4, 0)
    dlg.levelBtn:SetText("Level")

    dlg.levelBox = CreateFrame("EditBox", nil, dlg, "InputBoxTemplate")
    -- center levelBox under dialog
    dlg.levelBox:SetPoint("TOP", dlg, "TOP", 0, -75)
    dlg.levelBox:SetSize(50, 20)
    dlg.levelBox:SetAutoFocus(false)
    dlg.levelBox:Hide()

    local function SetSelection(sel)
        dlg.sel = sel
        if sel == "level" then
            dlg.levelBox:Show()
            -- focus and highlight so the user can start typing immediately
            dlg.levelBox:SetFocus()
            if dlg.levelBox.HighlightText then dlg.levelBox:HighlightText() end
        else
            dlg.levelBox:Hide()
            if dlg.levelBox.ClearFocus then dlg.levelBox:ClearFocus() end
        end
    end

    dlg.nextBtn:SetScript("OnClick", function() SetSelection("next_login") end)
    dlg.everyBtn:SetScript("OnClick", function() SetSelection("every_login") end)
    dlg.levelBtn:SetScript("OnClick", function() SetSelection("level") end)

    dlg.save = CreateFrame("Button", nil, dlg, "UIPanelButtonTemplate")
    dlg.save:SetSize(80, 24)
    dlg.save:SetPoint("BOTTOMLEFT", 20, 12)
    dlg.save:SetText("Save")
    dlg.remove = CreateFrame("Button", nil, dlg, "UIPanelButtonTemplate")
    -- make Remove uniform width with Save/Cancel
    dlg.remove:SetSize(80, 24)
    dlg.remove:SetPoint("BOTTOM", 0, 12)
    dlg.remove:SetText("Remove")
    dlg.cancel = CreateFrame("Button", nil, dlg, "UIPanelButtonTemplate")
    dlg.cancel:SetSize(80, 24)
    dlg.cancel:SetPoint("BOTTOMRIGHT", -20, 12)
    dlg.cancel:SetText("Cancel")

    dlg:SetScript("OnShow", function(self)
        if not self.sel then SetSelection("next_login") end
    end)

    dlg.Open = function(self, row)
        self.contextRow = row
        -- inspect existing reminder
        local notes = M:GetNotes(row.sectionKey) or {}
        local entry = notes[row.dataIndex]
        local sel = "next_login"
        local lvl = ""
        if type(entry) == "table" and entry.reminder then
            sel = entry.reminder.type or sel
            if sel == "level" then lvl = tostring(entry.reminder.level or "") end
        end
        -- disable level option for global notes
        if row.sectionKey == "global" then
            dlg.levelBtn:Disable()
        else
            dlg.levelBtn:Enable()
        end
        -- If the saved selection is level but level is not allowed, fall back
        if sel == "level" and row.sectionKey == "global" then sel = "next_login" end
        -- set text first so focusing/highlighting keeps the correct contents selected
        self.levelBox:SetText(lvl)
        SetSelection(sel)
        self:Show()
    end

    -- centralize save logic so it can be called from multiple places (Save button and Enter in levelBox)
    local function SaveReminder()
        local row = dlg.contextRow
        if not row or not row.sectionKey or not row.dataIndex then dlg:Hide(); return end
        local notes = M:GetNotes(row.sectionKey) or {}
        local entry = notes[row.dataIndex]
        local noteText = entry
        if type(entry) == "table" then noteText = entry.text end
        local reminder = nil
        if dlg.sel == "next_login" then
            reminder = { type = "next_login" }
        elseif dlg.sel == "every_login" then
            reminder = { type = "every_login" }
        elseif dlg.sel == "level" and row.sectionKey ~= "global" then
            reminder = { type = "level", level = tonumber(dlg.levelBox:GetText()) or nil }
        end
        local newEntry = { text = noteText }
        if reminder then newEntry.reminder = reminder end
        M:UpdateNote(row.sectionKey, row.dataIndex, newEntry)
        -- update the row's reminder button immediately so tooltip/label refreshes
        do
            local updated = (M:GetNotes(row.sectionKey) or {})[row.dataIndex]
            if row.reminderBtn then
                local tip = "Set reminder"
                if type(updated) == "table" and updated.reminder then
                    if updated.reminder.type == "level" then
                        tip = "At Level " .. tostring(updated.reminder.level or "")
                        row.reminderBtn:SetText("!")
                    elseif updated.reminder.type == "next_login" then
                        tip = "Next Login"
                        row.reminderBtn:SetText("!")
                    elseif updated.reminder.type == "every_login" then
                        tip = "Every Login"
                        row.reminderBtn:SetText("!")
                    end
                else
                    row.reminderBtn:SetText("R")
                end
                row.reminderBtn:SetScript("OnEnter", function(self)
                    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
                    GameTooltip:SetText(tip)
                end)
                row.reminderBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
            end
        end
        if row.sectionDef and RefreshSection then
            RefreshSection(row.sectionDef)
        end
        -- request a full relayout (LayoutSections) if available on the frame
        if M.frame and M.frame.LayoutSections then M.frame:LayoutSections() end
        dlg:Hide()
    end

    dlg.save:SetScript("OnClick", function() SaveReminder() end)
    -- Allow pressing Enter in the level edit box to save the reminder as well
    dlg.levelBox:SetScript("OnEnterPressed", function() SaveReminder() end)

    dlg.remove:SetScript("OnClick", function()
        local row = dlg.contextRow
        if not row or not row.sectionKey or not row.dataIndex then dlg:Hide(); return end
        local notes = M:GetNotes(row.sectionKey) or {}
        local entry = notes[row.dataIndex]
        if type(entry) == "table" then
            entry.reminder = nil
            M:UpdateNote(row.sectionKey, row.dataIndex, entry)
        end
        if row.sectionDef and RefreshSection then
            RefreshSection(row.sectionDef)
        end
        -- update the row's button immediately (keep CreateRow's dynamic tooltip)
        if row.reminderBtn then
            row.reminderBtn:SetText("R")
        end
        if M.frame and M.frame.LayoutSections then M.frame:LayoutSections() end
        dlg:Hide()
    end)

    dlg.cancel:SetScript("OnClick", function() dlg:Hide() end)

    dlg:Hide()
    ReminderDlg = dlg
    return ReminderDlg
end

local RefreshSection

local function SafeStringHeight(fs)
    local h = fs:GetStringHeight()
    if not h or h == 0 then
        -- Force a layout pass
        local txt = fs:GetText()
        fs:SetText(txt)
        h = fs:GetStringHeight() or 0
    end
    if h <= 0 then h = LINE_HEIGHT end
    return h
end

local function CreateRow(parent)
  -- Creates a note row with delete and inline edit controls.
    local f = CreateFrame("Frame", nil, parent)
    -- row height will be dynamic based on text; start with a minimal height
    f:SetHeight(LINE_HEIGHT)
    f:EnableMouse(true) -- allow row to receive clicks for inline edit
    f.delete = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    f.delete:SetSize(18,18)
    f.delete:SetPoint("LEFT", 2, 0)
    f.delete:SetScript("OnEnter", function() f.delete:SetAlpha(1) end)
    f.delete:SetScript("OnLeave", function() f.delete:SetAlpha(0.6) end)
    f.delete:SetAlpha(0.6)
    -- Hidden measurer FontString (used to compute wrapped height)
    f.text = f:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    f.text:SetPoint("LEFT", f.delete, "RIGHT", 4, 0)
    -- leave some space on the right for the reminder button
    f.text:SetPoint("RIGHT", -28, 0)
    f.text:SetJustifyH("LEFT")
    f.text:SetJustifyV("TOP")
    f.text:SetWordWrap(true)
    f.text:Hide()
    -- Visible message frame with hyperlink support
    f.msg = CreateFrame("ScrollingMessageFrame", nil, f)
    f.msg:SetPoint("LEFT", f.delete, "RIGHT", 4, 0)
    f.msg:SetPoint("RIGHT", -28, 0)
    f.msg:SetFading(false)
    f.msg:SetMaxLines(100)
    f.msg:SetJustifyH("LEFT")
    f.msg:SetIndentedWordWrap(false)
    f.msg:EnableMouse(true)
    if f.msg.SetHyperlinksEnabled then f.msg:SetHyperlinksEnabled(true) end
    if f.msg.SetFontObject then f.msg:SetFontObject(GameFontHighlightSmall) end
    -- Edit box for inline editing
    f.editBox = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
    f.editBox:SetAutoFocus(false)
    f.editBox:SetMultiLine(true)
    f.editBox:SetPoint("TOPLEFT", f.text, "TOPLEFT", -2, 2)
    f.editBox:SetPoint("RIGHT", -2, 0)
    f.editBox:Hide()
    -- Add background fill (InputBoxTemplate sometimes only shows edge textures)
    if not f.editBox.bg then
        local bg = f.editBox:CreateTexture(nil, "BACKGROUND")
        bg:SetColorTexture(0,0,0,0.45)
        bg:SetPoint("TOPLEFT", 4, -2)
        bg:SetPoint("BOTTOMRIGHT", -4, 2)
        f.editBox.bg = bg
    end
    f.editing = false
    f.editBox:SetScript("OnEscapePressed", function(b)
        b:ClearFocus(); f.editing = false; b:Hide(); if f.msg then f.msg:Show() end
    end)
    local function finishEdit()
        local txt = Trim(f.editBox:GetText())
        if f.editing and f.sectionKey and f.dataIndex then
            M:UpdateNote(f.sectionKey, f.dataIndex, txt)
            f.editing = false
            f.editBox:Hide()
            if f.msg then f.msg:Show() end
            if RefreshSection and f.sectionDef then
                RefreshSection(f.sectionDef)
            end
        end
    end
    f.editBox:SetScript("OnEnterPressed", function() finishEdit() end)
    f.editBox:SetScript("OnEditFocusLost", function() finishEdit() end)
    f:SetScript("OnMouseDown", function(_, btn)
        if btn == "LeftButton" and not f.editing and ((f.msg and f.msg:IsShown()) or (f.text and f.text:IsShown())) and f.dataIndex then
            f.editing = true
            f.editBox:SetText(f.text:GetText())
            if f.msg then f.msg:Hide() end
            f.editBox:Show()
            f.editBox:SetFocus()
        end
    end)

    -- Reminder button wrapped (decorated with border like lockWrap)
    f.reminderWrap = CreateFrame("Frame", nil, f, "BackdropTemplate")
    f.reminderWrap:SetSize(18, 18)
    f.reminderWrap:SetPoint("RIGHT", -4, 0)
    f.reminderWrap:SetBackdrop({ edgeFile = "Interface/Tooltips/UI-Tooltip-Border", tile = false, edgeSize = 10, insets = { left = 4, right = 4, top = 4, bottom = 4 } })
    -- make the wrapper transparent so only the inner button is visible (match lockWrap visual)
    f.reminderWrap:SetBackdropColor(0, 0, 0, 0)
    f.reminderWrap:SetBackdropBorderColor(0, 0, 0, 0)
    f.reminderWrap:SetFrameLevel(f:GetFrameLevel() + 18)

    f.reminderBtn = CreateFrame("Button", nil, f.reminderWrap, "UIPanelButtonTemplate")
    f.reminderBtn:SetSize(14, 15)
    f.reminderBtn:SetPoint("CENTER", f.reminderWrap, "CENTER", 0, 0)
    f.reminderBtn:SetText("R")
    f.reminderBtn:SetFrameLevel(f.reminderWrap:GetFrameLevel() - 1)

    f.reminderBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        -- grandparent is the row frame which holds the note
        local gp = self:GetParent() and self:GetParent():GetParent()
        local tip = "Set reminder"
        if gp and gp.note and type(gp.note) == "table" and gp.note.reminder then
            local r = gp.note.reminder
            if r.type == "level" then
                tip = "At Level " .. tostring(r.level or "")
            elseif r.type == "next_login" then
                tip = "Next Login"
            elseif r.type == "every_login" then
                tip = "Every Login"
            end
        end
        GameTooltip:SetText(tip)
    end)
    f.reminderBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Hyperlink tooltips for visible text: only show when hovering actual links
    -- Track whether the mouse is currently over a hyperlink so clicks on
    -- non-link areas can fall through to the row's edit handler.
    f._hoveringLink = false
    f.msg:SetScript("OnHyperlinkEnter", function(self, link, text, button)
        local parent = self:GetParent()
        if parent and parent.editing then return end
        f._hoveringLink = true
        GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
        if GameTooltip.SetHyperlink then GameTooltip:SetHyperlink(link) end
        GameTooltip:Show()
    end)
    f.msg:SetScript("OnHyperlinkLeave", function(self)
        f._hoveringLink = false
        GameTooltip:Hide()
    end)

    -- Clicking the visible message should enter edit mode when not clicking
    -- an actual hyperlink. We use the hovering flag set by hyperlink events
    -- to determine whether to start editing or allow the hyperlink click.
    f.msg:SetScript("OnMouseDown", function(self, btn)
        if btn ~= "LeftButton" then return end
        if f._hoveringLink then
            -- clicking a link; let the message frame handle hyperlink clicks
            return
        end
        if not f.editing and f.dataIndex then
            f.editing = true
            f.editBox:SetText(f.text and f.text:GetText() or "")
            self:Hide()
            f.editBox:Show()
            f.editBox:SetFocus()
        end
    end)

    return f
end


local frame
-- Persists the current frame size/position/visibility to SavedVariables.
local function SaveState() M:SaveFrameState() end

local function CreateResizeHandle(parent)
    -- Creates the resize grab handle shown in the frame corner.
    local h = CreateFrame("Button", nil, parent)
    h:SetSize(16,16)
    h:SetPoint("BOTTOMRIGHT", -2, 2)
    h:SetNormalTexture("Interface/CHATFRAME/UI-ChatIM-SizeGrabber-Up")
    h:SetHighlightTexture("Interface/CHATFRAME/UI-ChatIM-SizeGrabber-Highlight")
    h:SetPushedTexture("Interface/CHATFRAME/UI-ChatIM-SizeGrabber-Down")
    h:SetScript("OnMouseDown", function(_, btn)
        if btn == "LeftButton" then
            parent:StartSizing("BOTTOMRIGHT")
        end
    end)
    h:SetScript("OnMouseUp", function(_, btn)
        if btn == "LeftButton" then
            parent:StopMovingOrSizing()
            SaveState()
        end
    end)
    return h
end

local function ConfigureFrame(f, state)
  -- Hooks dragging/resizing scripts onto the frame.
    f:SetMinResize(MIN_WIDTH, MIN_HEIGHT)
    f:SetMovable(not state.locked)
    f:SetResizable(true)
    f:EnableMouse(true)
        -- Movement is handled via the title header only (see header scripts below)
        f:SetScript("OnDragStart", nil)
        f:SetScript("OnDragStop", nil)
    f:SetScript("OnSizeChanged", function() SaveState(); for _, s in ipairs(sections) do s.refreshNeeded = true end end)
    f:SetScript("OnShow", SaveState)
    f:SetScript("OnHide", SaveState)
end

-- Refreshes the rows within a section container to match current notes.
RefreshSection = function(def)
    local section = def.container
    if section.collapsed then return end
    local notes = M:GetNotes(def.key)

    -- width available for text (leave padding for delete button and margins)
    local textWidth = math.max(40, section.scrollFrame:GetWidth() - 40)
    section.scrollChild:SetWidth(section.scrollFrame:GetWidth())

    local totalH = 0
    for i = 1, #notes do
        local row = section.rows[i]
        if not row then
            row = CreateRow(section.scrollChild)
            section.rows[i] = row
            row:SetPoint("TOPLEFT", section.scrollChild, "TOPLEFT", 0, -totalH)
            row:SetPoint("RIGHT", -2, 0)
        else
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", section.scrollChild, "TOPLEFT", 0, -totalH)
            row:SetPoint("RIGHT", -2, 0)
        end

        local note = notes[i]
        local txt = (type(note) == "table" and note.text) or note
        -- measure the wrapped height using the hidden FontString
        row.text:SetWidth(textWidth)
        row.text:SetText("")
        row.text:SetText(txt)
        -- update visible message frame content
        if row.msg then
            row.msg:Clear()
            row.msg:AddMessage(txt)
            row.msg:SetWidth(textWidth)
        end

        row.delete:SetScript("OnClick", function()
            M:DeleteNote(def.key, i)
            RefreshSection(def)
        end)
        row.dataIndex = i
        row.sectionKey = def.key
        row.sectionDef = def
        row.note = note
        if row.reminderBtn then
            row.reminderBtn:SetScript("OnClick", function()
                EnsureReminderDialog()
                ReminderDlg:Open(row)
            end)
            -- Update label only; tooltip is handled dynamically in CreateRow's OnEnter
            if type(note) == "table" and note.reminder then
                row.reminderBtn:SetText("!")
            else
                row.reminderBtn:SetText("R")
            end
        end

        if not row.editing then
            row.editBox:Hide()
            if row.msg then row.msg:Show() end
        else
            -- when editing, set editBox size to match text area
            row.editBox:SetWidth(textWidth)
            row.editBox:SetHeight(math.max(20, row.text:GetStringHeight() + ROW_PADDING))
            if row.msg then row.msg:Hide() end
        end

        -- Add a small vertical padding so ScrollingMessageFrame rendering and
        -- FontString measurement align (prevents overlap for multi-line rows).
        local h = math.max(LINE_HEIGHT, SafeStringHeight(row.text) + ROW_PADDING)
        if row.msg then row.msg:SetHeight(h) end
        row:SetHeight(h)
        totalH = totalH + h
        row:Show()
    end

    -- hide any extra rows
    for i = #notes + 1, #section.rows do
        section.rows[i]:Hide()
    end

    section.scrollChild:SetHeight(totalH)

    -- respect section offset (scroll position) if used by the scroll handler
    if section.scrollFrame and section.offset then
        local ofs = math.max(0, section.offset or 0)
        section.scrollFrame:SetVerticalScroll(ofs * LINE_HEIGHT)
    end
end

-- Builds the UI container for a specific note section (global or character).
local function CreateSection(parent, def)
    local container = CreateFrame("Frame", nil, parent)
    container.title = container:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    container.title:SetPoint("TOPLEFT", 4, -4)
    container.title:SetText(def.title)

    container.addBox = CreateFrame("EditBox", nil, container, "InputBoxTemplate")
    container.addBox:SetAutoFocus(false)
    container.addBox:SetHeight(20)
    container.addBox:SetPoint("TOPLEFT", container.title, "BOTTOMLEFT", 6, -4)
    container.addBox:SetPoint("RIGHT", -20, 0)
    -- Background fill for add box
    if not container.addBox.bg then
        local bg = container.addBox:CreateTexture(nil, "BACKGROUND")
        bg:SetColorTexture(0,0,0,0.45)
        bg:SetPoint("TOPLEFT", 4, -2)
        bg:SetPoint("BOTTOMRIGHT", -4, 2)
        container.addBox.bg = bg
    end
    container.addBox:SetScript("OnEscapePressed", function(b) b:ClearFocus() end)
    local function tryAdd()
        local txt = Trim(container.addBox:GetText())
        if txt ~= "" then
            M:AddNote(def.key, txt)
            container.addBox:SetText("")
            container.offset = 0
            if container.scrollFrame then
                container.scrollFrame:SetVerticalScroll(0)
            end
            RefreshSection(def)
        end
    end
    container.addBox:SetScript("OnEnterPressed", tryAdd)

    -- Not exactly a "Add" button, but functions to let us add notes via keyboard.
    -- container.addBtn = CreateFrame("Button", nil, container, "UIPanelButtonTemplate")

    container.scrollFrame = CreateFrame("ScrollFrame", nil, container, "UIPanelScrollFrameTemplate")
    container.scrollFrame:SetPoint("TOPLEFT", container.addBox, "BOTTOMLEFT", 0, -6)
    container.scrollFrame:SetPoint("BOTTOMRIGHT", -26, 4)

    container.scrollChild = CreateFrame("Frame", nil, container.scrollFrame)
    container.scrollChild:SetPoint("TOPLEFT")
    container.scrollChild:SetSize(10,10)
    container.scrollFrame:SetScrollChild(container.scrollChild)

    container.offset = 0
    container.rows = {}

    container.scrollFrame:EnableMouseWheel(true)
    return container
end

-- Refreshes the rows within a section container to match current notes.
RefreshSection = function(def)
    local section = def.container
    if section.collapsed then return end
    local notes = M:GetNotes(def.key)

    -- width available for text (leave padding for delete button and margins)
    local textWidth = math.max(40, section.scrollFrame:GetWidth() - 40)
    section.scrollChild:SetWidth(section.scrollFrame:GetWidth())

    local totalH = 0
    for i = 1, #notes do
        local row = section.rows[i]
        if not row then
            row = CreateRow(section.scrollChild)
            section.rows[i] = row
            row:SetPoint("TOPLEFT", section.scrollChild, "TOPLEFT", 0, -totalH)
            row:SetPoint("RIGHT", -2, 0)
        else
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", section.scrollChild, "TOPLEFT", 0, -totalH)
            row:SetPoint("RIGHT", -2, 0)
        end

        local note = notes[i]
        local txt = (type(note) == "table" and note.text) or note
        -- measure with hidden FontString
        row.text:SetWidth(textWidth)
        row.text:SetText("")
        row.text:SetText(txt)
        -- set visible message text with hyperlinks
        if row.msg then
            row.msg:Clear()
            row.msg:AddMessage(txt)
            row.msg:SetWidth(textWidth)
        end
        row.delete:SetScript("OnClick", function()
            M:DeleteNote(def.key, i)
            RefreshSection(def)
        end)
        row.dataIndex = i
        row.sectionKey = def.key
        row.sectionDef = def

        row.note = note
        if row.reminderBtn then
            row.reminderBtn:SetScript("OnClick", function()
                EnsureReminderDialog()
                ReminderDlg:Open(row)
            end)
            if type(note) == "table" and note.reminder then
                row.reminderBtn:SetText("!")
            else
                row.reminderBtn:SetText("R")
            end
        end

        if not row.editing then
            row.editBox:Hide()
            if row.msg then row.msg:Show() end
        else
            -- when editing, set editBox size to match text area
            row.editBox:SetWidth(textWidth)
            row.editBox:SetHeight(math.max(20, row.text:GetStringHeight() + ROW_PADDING))
            if row.msg then row.msg:Hide() end
        end

        local h = math.max(LINE_HEIGHT, SafeStringHeight(row.text) + ROW_PADDING)
        if row.msg then row.msg:SetHeight(h) end
        row:SetHeight(h)
        totalH = totalH + h
        row:Show()
    end

    -- hide any extra rows
    for i = #notes + 1, #section.rows do
        section.rows[i]:Hide()
    end

    section.scrollChild:SetHeight(totalH)
end

-- Hooks button and scroll handlers that belong to a section container.
local function HookSection(def)
    local section = def.container
    section.scrollFrame:SetScript("OnMouseWheel", function(self, delta)
        -- Compute the current and maximum scroll values, step by one line per wheel tick.
        local cur = self:GetVerticalScroll()
        local childH = section.scrollChild and section.scrollChild:GetHeight() or 0
        local frameH = self:GetHeight()
        local maxScroll = math.max(0, childH - frameH)
        local step = LINE_HEIGHT
        local new = cur - (delta * step)
        if new < 0 then new = 0 end
        if new > maxScroll then new = maxScroll end
        self:SetVerticalScroll(new)
        -- Keep offset in sync (integer number of lines)
        section.offset = math.floor(new / LINE_HEIGHT)
    end)
end


function TCNotes_CreateFrame()
  -- Creates, configures, and restores the TCNotes frame on ADDON_LOADED.

    if frame then return end
    frame = CreateFrame("Frame", "TCNotesFrame", UIParent, "BackdropTemplate")

    local savedState = TCNotesDB.frameState
    frame.locked = TCNotesDB.frameState.locked
    M.frame = frame
    local defaultW, defaultH = 400, 500
    local w = (savedState and savedState.width) or defaultW
    local h = (savedState and savedState.height) or defaultH
    frame:SetSize(w, h)
    frame:ClearAllPoints()
    if savedState and savedState.x and savedState.y then
        frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", savedState.x, savedState.y)
    else
        frame:SetPoint("CENTER")
    end
    frame:SetBackdrop({
        bgFile = "Interface/DialogFrame/UI-DialogBox-Background",
        edgeFile = "Interface/DialogFrame/UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 },
    })
    frame:SetBackdropColor(0,0,0,0.9)

    -- Apply saved frame strata immediately if available (core also reapplies on restore)
    -- TC TODO - testing low frame strata.  So far this works good, lets me put the notes behind my bagnon inventory
    frame:SetFrameStrata("LOW")
    -- if savedState and savedState.strata then
    --     frame:SetFrameStrata(savedState.strata)
    -- elseif TCNotesDB and TCNotesDB.frameState and TCNotesDB.frameState.strata then
    --     frame:SetFrameStrata(TCNotesDB.frameState.strata)
    -- else
    --     frame:SetFrameStrata("HIGH")
    -- end

    ConfigureFrame(frame, savedState)
    -- When the frame becomes visible after being hidden at load, defer a refresh
    -- until the next frame to ensure widths/heights are finalized by the client.
    frame:SetScript("OnShow", function()
        SaveState()
        frame.pendingRefresh = true
    end)
    frame.resizeHandle = CreateResizeHandle(frame)

    -- Slim tooltip-style header (matches lockWrap style) replacing bulky dialog header
    local headerHeight = 18
    frame.header = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    -- Fixed-width centered header (does not grow/shrink when frame resizes)
    frame.header:SetPoint("TOP", frame, "TOP", 0, 3)
    local headerWidth = 100
    -- Add 2px to ensure backdrop reaches slightly past bezel and hides tiny gaps
    frame.header:SetWidth(headerWidth + 2)
    frame.header:SetHeight(headerHeight)
    -- Prefer LibSharedMedia "Blizzard Rock" background if available, fall back to tooltip style
    local rock, border
    local ok, SML = pcall(LibStub, "LibSharedMedia-3.0")
    if ok and SML then
        -- Try explicit Blizzard Rock name first
        -- rock = SML:Fetch("background", "Blizzard Parchment")
        rock = SML:Fetch("background", "Blizzard Marble")
        -- rock = SML:Fetch("background", "Blizzard Rock")
        -- If not registered, scan for any background name containing 'Rock'
        if not rock then
            local list = SML:List("background")
            if list then
                for _, name in ipairs(list) do
                    if name:lower():find("rock") then
                        rock = SML:Fetch("background", name)
                        break
                    end
                end
            end
        end
        border = SML:Fetch("border", "Blizzard Tooltip")
        -- -- Debug print once (will appear in chat) so user can see chosen texture name/path
        -- if rock then
        --     print("TCNotes: header background set to Rock texture:", rock)
        -- else
        --     print("TCNotes: Rock texture not found in LSM; using tooltip background.")
        -- end
    end
    -- Fallback chain: dialog background provides a more stone-like look than plain tooltip if rock missing
    rock = rock or "Interface/DialogFrame/UI-DialogBox-Background"
    border = border or "Interface/Tooltips/UI-Tooltip-Border"
    frame.header:SetBackdrop({
        bgFile = rock,
        edgeFile = border,
        tile = true,
        tileSize = 128,
        edgeSize = 10,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    -- Use full alpha so the chosen background texture is visible; darken if using a fallback later
    frame.header:SetBackdropColor(1,1,1,1)
    frame.header:SetBackdropBorderColor(0.72, 0.72, 0.72, 1)
    -- Ensure full fill for very small height (backdrop bg can occasionally clip).
    -- If we have a rock texture, reuse it instead of a solid black overlay so it isn't hidden.
    -- Remove solid fill when tiling; the backdrop will handle repetition.
    if frame.header.fill then
        frame.header.fill:Hide()
    end

    -- Create a dedicated tiled background texture that extends slightly beyond
    -- the header edges to hide small seams from the bezel/backdrop border.
    if not frame.header.bgTex then
        local bg = frame.header:CreateTexture(nil, "BACKGROUND", nil, -1)
        bg:SetPoint("TOPLEFT", frame.header, "TOPLEFT", 2, -2)
        bg:SetPoint("BOTTOMRIGHT", frame.header, "BOTTOMRIGHT", -2, 2)
        bg:SetTexture(rock)
        if bg.SetHorizTile then bg:SetHorizTile(true) end
        if bg.SetVertTile then bg:SetVertTile(false) end
        bg:SetVertexColor(1,1,1,1)
        frame.header.bgTex = bg
    else
        frame.header.bgTex:SetTexture(rock)
        frame.header.bgTex:SetPoint("TOPLEFT", frame.header, "TOPLEFT", 2, -2)
        frame.header.bgTex:SetPoint("BOTTOMRIGHT", frame.header, "BOTTOMRIGHT", -2, 2)
        if frame.header.bgTex.SetHorizTile then frame.header.bgTex:SetHorizTile(true) end
    end

    -- Floating title in its own frame so it renders above the backdrop/header textures
    frame.titleFrame = CreateFrame("Frame", nil, frame)
    frame.titleFrame:SetPoint("TOP", frame, "TOP", 0, 8)
    frame.titleFrame:SetSize(1, 1)
    frame.titleFrame:SetFrameLevel(frame:GetFrameLevel() + 50)
    frame.title = frame.titleFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    frame.title:SetPoint("TOP", frame.titleFrame, "TOP", 0, -9)
    frame.title:SetText("Notes")

    -- Make the top area draggable
    -- Using direct mouse handlers for instant movement.
    local tr = frame:CreateTitleRegion()
    tr:SetAllPoints(frame.header)
    frame.header:EnableMouse(true)
    frame.header:SetScript("OnMouseDown", function(_, btn)
        if btn == "LeftButton" and not frame.locked then
            frame:StartMoving()
        end
    end)
    frame.header:SetScript("OnMouseUp", function(_, btn)
        if btn == "LeftButton" then
            frame:StopMovingOrSizing()
            SaveState()
        end
    end)

    -- Lock icon wrapper (decorated with dialog border), contains the actual button
    local lockWrap = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    lockWrap:SetSize(18, 18)
    lockWrap:SetPoint("LEFT", frame, "TOPLEFT", 12, -6)
    lockWrap:SetFrameLevel(frame:GetFrameLevel() + 18)
    lockWrap:SetBackdrop({
        --bgFile = "Interface/Tooltips/UI-Tooltip-Background",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        tile = false, edgeSize = 10,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    lockWrap:SetBackdropBorderColor(0.72, 0.72, 0.72, 1)

    local lockBtn = CreateFrame("Button", nil, lockWrap, "UIPanelButtonTemplate")
    frame.lockBtn = lockBtn
    lockBtn:SetSize(14, 18)
    lockBtn:SetPoint("CENTER", lockWrap, "CENTER", 0, 0)
    lockBtn:SetFrameLevel(lockWrap:GetFrameLevel() - 1)

    local function UpdateLockIcon()
        -- Use the live frame.locked state (not savedState) so toggles update immediately.
        if frame.locked then
            lockBtn:SetText("L")
            -- if frame.resizeHandle then frame.resizeHandle:Hide() end
            if closeBtn and closeBtn.Disable then closeBtn:Disable() end
        else
            lockBtn:SetText("U")
            -- if frame.resizeHandle then frame.resizeHandle:Show() end
            if closeBtn and closeBtn.Enable then closeBtn:Enable() end
        end
    end

    lockBtn:SetScript("OnClick", function()
        frame.locked = not frame.locked
        if TCNotesDB and TCNotesDB.frameState then
            TCNotesDB.frameState.locked = frame.locked and true or false
        end
        frame:SetMovable(not frame.locked)
        frame:SetResizable(not frame.locked)
        if (frame.locked or frame.collapsed) then
          if frame.resizeHandle then frame.resizeHandle:Hide() end
        else
          if frame.resizeHandle then frame.resizeHandle:Show() end
        end
        UpdateLockIcon()
        if M.SaveFrameState then M:SaveFrameState() end
    end)
    lockBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(frame.locked and "Locked (can't move or close)" or "Unlocked (click to lock)")
    end)
    lockBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    UpdateLockIcon()

    -- Close button wrapper (decorated with dialog border)
    local closeWrap = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    closeWrap:SetSize(18, 18)
    closeWrap:SetPoint("RIGHT", frame, "TOPRIGHT", -10, -6)
    closeWrap:SetFrameLevel(frame:GetFrameLevel() + 18)
    closeWrap:SetBackdrop({
        bgFile = "Interface/Tooltips/UI-Tooltip-Background",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        tile = false, edgeSize = 10,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    -- opaque background and lighter border
    closeWrap:SetBackdropColor(0,0,0,1)
    closeWrap:SetBackdropBorderColor(0.72, 0.72, 0.72, 1)
    local closeBtn = CreateFrame("Button", nil, closeWrap, "UIPanelCloseButton")
    frame.closeBtn = closeBtn
    closeBtn:SetSize(24,24)
    closeBtn:SetPoint("CENTER", closeWrap, "CENTER", 0, 0)
    closeBtn:SetFrameLevel(closeWrap:GetFrameLevel() + 2)
    closeBtn:SetScript("OnClick", function()
        -- Prevent closing when frame is locked
        if frame.locked then return end
        frame:Hide()
        if TCNotesDB and TCNotesDB.frameState then
            TCNotesDB.frameState.shown = false
        end
        if M.SaveFrameState then M:SaveFrameState() end
    end)
    -- keep default close button textures (no extra embossed overlay)

    frame.separator = frame:CreateTexture(nil, "ARTWORK")
    frame.separator:SetColorTexture(0.4,0.4,0.4,0.8)

    for _, def in ipairs(sections) do
        def.container = CreateSection(frame, def)
    end

    local function LayoutSections()
        local headerOffset = (frame.header and frame.header:GetHeight() or 24) + 0
        -- Reserve a small top inset for the visual header; the floating title/buttons do not affect layout
        local headerLayoutReserve = 14
        local total = frame:GetHeight() - headerLayoutReserve
        local gDef, cDef = sections[1], sections[2]
        local g, c = gDef.container, cDef.container
        if frame.collapsed then
            g:Hide(); c:Hide(); frame.separator:Hide()
        else
            g:Show(); c:Show(); frame.separator:Show()
            local separatorSpace = 10
            local half = (total - separatorSpace) / 2
            g:SetPoint("TOPLEFT", 8, -headerLayoutReserve)
            g:SetPoint("TOPRIGHT", -8, -headerLayoutReserve)
            g:SetHeight(half)
            frame.separator:ClearAllPoints()
            frame.separator:SetPoint("TOPLEFT", g, "BOTTOMLEFT", 0, -5)
            frame.separator:SetPoint("TOPRIGHT", g, "BOTTOMRIGHT", 0, -5)
            frame.separator:SetHeight(1)
            c:SetPoint("TOPLEFT", frame.separator, "BOTTOMLEFT", 0, -5)
            c:SetPoint("TOPRIGHT", frame.separator, "BOTTOMRIGHT", 0, -5)
            c:SetPoint("BOTTOMLEFT", 8, 8)
            c:SetPoint("BOTTOMRIGHT", -8, 8)
            c:SetHeight(half)
        end
        for _, def in ipairs(sections) do
            if not frame.collapsed and def.container and def.container.refreshNeeded then
                RefreshSection(def)
                def.container.refreshNeeded = false
            end
        end
    end

    -- expose LayoutSections so other code (eg. reminder dialog) can request a relayout
    frame.LayoutSections = LayoutSections

    -- Recalculate wrapped row widths/heights on resize
    frame:SetScript("OnSizeChanged", function()
        for _, def in ipairs(sections) do
            def.container.refreshNeeded = true
        end
        LayoutSections()
        SaveState()
    end)

    for _, def in ipairs(sections) do
        HookSection(def)
        def.container.refreshNeeded = true
    end

    -- Enable SHIFT-click item link insertion into focused TCNotes editboxes
    if M and M.SetupLinkHook then M:SetupLinkHook() end

    -- Single expand/collapse toggle button (left of close button)
    -- create a wrapper for the expand/collapse button so it matches the close button border
    local expandWrap = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    expandWrap:SetSize(18, 18)
    expandWrap:SetPoint("LEFT", lockWrap, "RIGHT", 0, 0)
    expandWrap:SetFrameLevel(frame:GetFrameLevel() + 18)
    expandWrap:SetBackdrop({
        bgFile = "Interface/Tooltips/UI-Tooltip-Background",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        tile = false, edgeSize = 10,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    expandWrap:SetBackdropColor(0,0,0,1)
    expandWrap:SetBackdropBorderColor(0.72, 0.72, 0.72, 1)

    local expandCollapseBtn = CreateFrame("Button", nil, expandWrap)
    frame.expandCollapseBtn = expandCollapseBtn
    expandCollapseBtn:SetSize(20,20)
    expandCollapseBtn:SetPoint("CENTER", expandWrap, "CENTER", 0, 0)
    expandCollapseBtn:SetFrameLevel(expandWrap:GetFrameLevel() + 2)
    -- Use quest tracker style expand/minimize button textures (with built-in highlight)
    -- Prefer quest tracker style collapse/expand arrow buttons if present; fallback to panel minimize/expand.
    -- Some clients / texture packs include these quest log collapse textures.
    -- Use only panel expand/minimize textures (quest log arrow textures not present on this client).
    -- Use plus/minus icon set for clearer collapse vs expand (quest/panel set looked like close X)
    local PLUS_UP      = "Interface/Buttons/UI-PlusButton-Up"
    local PLUS_DOWN    = "Interface/Buttons/UI-PlusButton-Down"
    local PLUS_HL      = "Interface/Buttons/UI-PlusButton-Hilight"
    local MINUS_UP     = "Interface/Buttons/UI-MinusButton-Up"
    local MINUS_DOWN   = "Interface/Buttons/UI-MinusButton-Down"
    local MINUS_HL     = "Interface/Buttons/UI-MinusButton-Hilight"

    local function SafeSet(btn, normal, pushed, highlight)
        btn:SetNormalTexture(normal)
        btn:SetPushedTexture(pushed)
        btn:SetHighlightTexture(highlight)
        local hl = btn:GetHighlightTexture(); if hl then hl:SetBlendMode("ADD") end
    end

    local function ApplyExpandTextures(isCollapsed)
        if isCollapsed then
            -- Frame is collapsed: show plus to indicate expand action
            SafeSet(expandCollapseBtn, PLUS_UP, PLUS_DOWN, PLUS_HL)
        else
            -- Frame expanded: show minus to indicate collapse action
            SafeSet(expandCollapseBtn, MINUS_UP, MINUS_DOWN, MINUS_HL)
        end
    end
    local function UpdateToggleIcon()
        ApplyExpandTextures(frame.collapsed)
    end
    local function ApplyCollapsedHeight()
        -- Preserve current top-left so collapsing never moves it
        local left, top = frame:GetLeft(), frame:GetTop()
        if frame.collapsed then
            if not frame.preCollapseHeight then frame.preCollapseHeight = frame:GetHeight() end
            -- collapsed height: keep it a thin strip so only the top border + label are visible
            -- Ensure collapsed height is never smaller than summed backdrop inset space.
            local bd = frame:GetBackdrop()
            local topInset = (bd and bd.insets and bd.insets.top) or 12
            local bottomInset = (bd and bd.insets and bd.insets.bottom) or 11
            local neededForInsets = topInset + bottomInset + 2 -- +2 for a thin interior strip
            local collapsedH = math.max(COLLAPSED_BASE_HEIGHT, neededForInsets)
            frame:SetMinResize(MIN_WIDTH, collapsedH)
            frame:SetHeight(collapsedH)
            if frame.resizeHandle then frame.resizeHandle:Hide() end
        else
            local restoreH = (TCNotesDB and TCNotesDB.frameState and TCNotesDB.frameState.expandedHeight)
                              or frame.preCollapseHeight or frame:GetHeight()
            frame:SetMinResize(MIN_WIDTH, MIN_HEIGHT)
            frame:SetHeight(restoreH)
            if frame.resizeHandle then
                if frame.locked or frame.collapsed then
                    frame.resizeHandle:Hide()
                else
                    frame.resizeHandle:Show()
                end
            end
        end
        if left and top then
            frame:ClearAllPoints()
            frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
        end
    end
    expandCollapseBtn:SetScript("OnClick", function()
        frame.collapsed = not frame.collapsed
        ApplyCollapsedHeight()

        for _, def in ipairs(sections) do
            if def.container then def.container.refreshNeeded = true end
        end

        LayoutSections()
        UpdateToggleIcon()

        frame.pendingRefresh = not frame.collapsed  -- refresh after next frame so widths are final

        if TCNotesDB and TCNotesDB.frameState then
            TCNotesDB.frameState.collapsed = frame.collapsed
        end
        if M.SaveFrameState then M:SaveFrameState() end
    end)

    -------------- Restore state of prior frame --------------
    frame.collapsed = savedState and savedState.collapsed and true or false
    frame.locked = savedState and savedState.locked and true or false
    ApplyCollapsedHeight()
    UpdateToggleIcon()
    if frame.lockChk then frame.lockChk:SetChecked(not frame.locked) end

    -- Respect saved visibility (hide if previously hidden)
    if savedState and savedState.shown == false then
        frame:Hide()
    elseif savedState and savedState.shown == true then
        frame:Show()
    end

    LayoutSections()

    frame.pendingRefresh = false
    frame:SetScript("OnUpdate", function(self)
        if self.pendingRefresh then
            self.pendingRefresh = false
            for _, def in ipairs(sections) do
                if not frame.collapsed and def.container then
                    RefreshSection(def)
                end
            end
        end
    end)
end

-- Forces every section to reload their rows from SavedVariables.
function M:RefreshAll()
    for _, def in ipairs(sections) do
        if def.container then RefreshSection(def) end
    end
end
