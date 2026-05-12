-- Options.lua — visual config panel for Totem Tommys Bars.
-- Sections:
--   1. Bar appearance
--   2. Custom Stacks (build / save / use / delete; max 10)
--   3. Weapon Imbues (independent of stacks)
--   4. Utility

local addonName, NS = ...

local MAX_STACKS = 20
local MAX_UTIL_STACKS = 20
local PANEL_W, PANEL_H = 1040, 720  -- horizontal 2x; vertical unchanged

local Panel
local KeybindPanel
local DB

-- Forward-declared so the Custom Stacks editor's link dropdown can call it
local refreshLinkDropdown
local refreshTotemLinkDropdown

------------------------------------------------------------------------
-- Keybindings dialog
------------------------------------------------------------------------
local PURE_MODIFIERS = {
    LSHIFT = true, RSHIFT = true,
    LCTRL  = true, RCTRL  = true,
    LALT   = true, RALT   = true,
    UNKNOWN = true,
}

local function modifierPrefix()
    local p = ""
    if IsShiftKeyDown()   then p = p .. "SHIFT-"   end
    if IsControlKeyDown() then p = p .. "CTRL-"    end
    if IsAltKeyDown()     then p = p .. "ALT-"     end
    return p
end

local function prettyKey(key)
    if not key or key == "" then return "|cffaaaaaa(not bound)|r" end
    return key:gsub("SHIFT%-", "Shift+"):gsub("CTRL%-", "Ctrl+"):gsub("ALT%-", "Alt+")
end

local function buildKeybindPanel()
    KeybindPanel = CreateFrame("Frame", "TotemTommysBarsKeybinds", UIParent, "BackdropTemplate")
    KeybindPanel:SetSize(520, 100 + #NS.BINDING_ACTIONS * 26 + 30)
    KeybindPanel:SetPoint("CENTER")
    KeybindPanel:SetFrameStrata("DIALOG")
    KeybindPanel:SetMovable(true)
    KeybindPanel:EnableMouse(true)
    KeybindPanel:RegisterForDrag("LeftButton")
    KeybindPanel:SetScript("OnDragStart", KeybindPanel.StartMoving)
    KeybindPanel:SetScript("OnDragStop", KeybindPanel.StopMovingOrSizing)
    KeybindPanel:SetClampedToScreen(true)
    KeybindPanel:Hide()

    if KeybindPanel.SetBackdrop then
        KeybindPanel:SetBackdrop({
            bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Gold-Border",
            tile = true, tileSize = 16, edgeSize = 32,
            insets = { left = 11, right = 12, top = 12, bottom = 11 },
        })
        KeybindPanel:SetBackdropColor(0.05, 0.05, 0.07, 0.95)
        KeybindPanel:SetBackdropBorderColor(1, 1, 1, 1)
    end

    -- Header band
    local headerBand = KeybindPanel:CreateTexture(nil, "ARTWORK")
    headerBand:SetPoint("TOPLEFT", 14, -14)
    headerBand:SetPoint("TOPRIGHT", -14, -14)
    headerBand:SetHeight(40)
    headerBand:SetColorTexture(0.12, 0.10, 0.06, 0.85)

    local title = KeybindPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    title:SetPoint("TOP", 0, -18)
    title:SetText("|cffffd200Keybindings|r")

    local headerDivider = KeybindPanel:CreateTexture(nil, "OVERLAY")
    headerDivider:SetTexture("Interface\\Common\\UI-TooltipDivider-Transparent")
    headerDivider:SetPoint("TOPLEFT", 18, -56)
    headerDivider:SetPoint("TOPRIGHT", -18, -56)
    headerDivider:SetHeight(8)

    local close = CreateFrame("Button", nil, KeybindPanel, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -4, -4)

    local hint = KeybindPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    hint:SetPoint("TOP", headerDivider, "BOTTOM", 0, -6)
    hint:SetWidth(480); hint:SetJustifyH("CENTER")
    hint:SetText("|cffaaccffSet|r → press a single key (Esc cancels). Hold Shift while pressing the bound key to cycle/secondary.")

    -- Row factory
    local rows = {}
    local capturing  -- the row currently capturing input

    local function refreshRow(row)
        local key = DB.bindings and DB.bindings[row.actionId]
        row.keyText:SetText(prettyKey(key))
    end

    for i, action in ipairs(NS.BINDING_ACTIONS) do
        local row = CreateFrame("Frame", nil, KeybindPanel)
        row:SetSize(490, 24)
        row:SetPoint("TOPLEFT", KeybindPanel, "TOPLEFT", 20, -100 - (i - 1) * 26)

        row.actionId = action.id

        local lbl = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        lbl:SetPoint("LEFT", 0, 0)
        lbl:SetWidth(240); lbl:SetJustifyH("LEFT")
        lbl:SetText(action.label)

        row.keyText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        row.keyText:SetPoint("LEFT", lbl, "RIGHT", 8, 0)
        row.keyText:SetWidth(140); row.keyText:SetJustifyH("LEFT")

        local setBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        setBtn:SetSize(50, 22)
        setBtn:SetText("Set")
        setBtn:SetPoint("RIGHT", -56, 0)

        local clrBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        clrBtn:SetSize(50, 22)
        clrBtn:SetText("Clear")
        clrBtn:SetPoint("RIGHT", 0, 0)

        local function exitCapture()
            row:EnableKeyboard(false)
            row:SetScript("OnKeyDown", nil)
            setBtn:SetText("Set")
            capturing = nil
        end

        setBtn:SetScript("OnClick", function()
            -- Cancel any other row's capture first
            for _, r in ipairs(rows) do
                if r ~= row and r.exitCapture then r:exitCapture() end
            end
            row:EnableKeyboard(true)
            row:SetPropagateKeyboardInput(false)
            setBtn:SetText("…press key")
            capturing = row
            row:SetScript("OnKeyDown", function(_, key)
                if PURE_MODIFIERS[key] then return end
                if key == "ESCAPE" then exitCapture(); return end
                -- Plain keys only — modifiers are reserved for shift-click
                -- behavior on the bar buttons themselves (cycle, secondary).
                if NS.API.setBinding(action.id, key) then
                    refreshRow(row)
                    for _, r in ipairs(rows) do refreshRow(r) end
                end
                exitCapture()
            end)
        end)

        clrBtn:SetScript("OnClick", function()
            NS.API.clearBinding(action.id)
            refreshRow(row)
        end)

        row.exitCapture = exitCapture
        row.refresh = function() refreshRow(row) end
        rows[#rows + 1] = row
    end

    KeybindPanel.rows = rows

    KeybindPanel:SetScript("OnShow", function()
        for _, r in ipairs(rows) do r.refresh() end
    end)
end

local function openKeybindPanel()
    if not DB then return end
    if not KeybindPanel then buildKeybindPanel() end
    if KeybindPanel:IsShown() then KeybindPanel:Hide() else KeybindPanel:Show() end
end

------------------------------------------------------------------------
-- Icon picker popup (used by the Stack icon button)
------------------------------------------------------------------------
local IconPicker
local iconPickerCallback  -- function(fileID) invoked when user picks an icon

local function buildIconPicker()
    IconPicker = CreateFrame("Frame", "TotemTommysBarsIconPicker", UIParent, "BackdropTemplate")
    IconPicker:SetSize(420, 460)
    IconPicker:SetPoint("CENTER")
    IconPicker:SetFrameStrata("FULLSCREEN_DIALOG")
    IconPicker:SetMovable(true)
    IconPicker:EnableMouse(true)
    IconPicker:RegisterForDrag("LeftButton")
    IconPicker:SetScript("OnDragStart", IconPicker.StartMoving)
    IconPicker:SetScript("OnDragStop", IconPicker.StopMovingOrSizing)
    IconPicker:SetClampedToScreen(true)
    IconPicker:Hide()

    if IconPicker.SetBackdrop then
        IconPicker:SetBackdrop({
            bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Gold-Border",
            tile = true, tileSize = 16, edgeSize = 32,
            insets = { left = 11, right = 12, top = 12, bottom = 11 },
        })
        IconPicker:SetBackdropColor(0.05, 0.05, 0.07, 0.97)
    end

    local title = IconPicker:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -16)
    title:SetText("|cffffd200Pick a Stack Icon|r")

    local close = CreateFrame("Button", nil, IconPicker, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -4, -4)

    -- Scroll area
    local scrollFrame = CreateFrame("ScrollFrame", nil, IconPicker, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 18, -50)
    scrollFrame:SetPoint("BOTTOMRIGHT", -34, 16)

    local grid = CreateFrame("Frame", nil, scrollFrame)
    grid:SetSize(360, 4000)  -- height adjusted after population
    scrollFrame:SetScrollChild(grid)

    local ICON_SIZE = 38
    local ICON_PAD  = 6
    local COLS      = 8
    local btns = {}

    -- Build the icon list with a parallel `labels` table so the filter
    -- can match against meaningful text (spell name, texture name).
    -- Each entry in `list[i]` is either a fileID (number) or a texture
    -- path string; `labels[i]` is the lower-cased searchable label.
    local function getIconList()
        local list, labels, seen = {}, {}, {}
        local function add(v, label)
            if v and not seen[v] then
                seen[v] = true
                list[#list + 1] = v
                labels[#labels + 1] = (label or tostring(v)):lower()
            end
        end

        -- 1) Spell icons from our own data tables (live GetSpellInfo).
        local function addSpell(name)
            local _, _, icon = GetSpellInfo(name)
            if icon then add(icon, name) end
        end
        for _, list2 in pairs(NS.TOTEMS) do
            for _, n in ipairs(list2) do addSpell(n) end
        end
        for _, n in ipairs(NS.IMBUES)          do addSpell(n) end
        for _, n in ipairs(NS.UTILITY_OPTIONS) do addSpell(n) end
        addSpell(NS.LIGHTNING_SHIELD)

        -- 2) Player's full spellbook — scan every tab so we get class
        -- spells whose names we can attach as labels.
        if GetSpellBookItemInfo and GetSpellBookItemName and GetSpellBookItemTexture then
            for i = 1, 1024 do
                local name = GetSpellBookItemName(i, "spell")
                if not name then break end
                local tex = GetSpellBookItemTexture(i, "spell")
                if tex then add(tex, name) end
            end
        end

        -- 3) Blizzard's macro icon catalog — names ARE searchable here.
        if GetMacroIcons then
            local names = {}
            pcall(GetMacroIcons, names)
            for _, v in ipairs(names) do
                if type(v) == "number" then
                    add(v)
                elseif type(v) == "string" then
                    -- Strip any prefix; the name itself is the search target
                    local pretty = v:gsub("^Interface\\Icons\\", "")
                                    :gsub("^.*[\\/]", "")
                    add("Interface\\Icons\\" .. v, pretty)
                end
            end
        end
        if GetMacroItemIcons then
            local items = {}
            pcall(GetMacroItemIcons, items)
            for _, v in ipairs(items) do add(v) end
        end
        if GetNumMacroIcons and GetMacroIconInfo then
            local n = GetNumMacroIcons()
            for i = 1, n do
                local id = GetMacroIconInfo(i)
                if id then add(id) end
            end
        end

        return list, labels
    end

    local fullList, fullLabels
    local filtered = {}

    -- Virtualization: we create a fixed pool of buttons (enough to cover
    -- the visible scroll window + a small buffer).  As the user scrolls,
    -- we re-point each pool button at the next icon in the filtered list
    -- — no thousands of frames, no scroll lag.
    local STEP = ICON_SIZE + ICON_PAD
    local POOL_ROWS = 14  -- ~visible rows + buffer
    local POOL_SIZE = COLS * POOL_ROWS

    -- Pre-create the pool once
    for i = 1, POOL_SIZE do
        local b = CreateFrame("Button", nil, grid, "ActionButtonTemplate")
        b:SetSize(ICON_SIZE, ICON_SIZE)
        if b.icon then
            b.icon:ClearAllPoints()
            b.icon:SetPoint("TOPLEFT",     b, "TOPLEFT",      2, -2)
            b.icon:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -2,  2)
        end
        b:Hide()
        btns[i] = b
    end

    local function updateVisible()
        local scrollY  = scrollFrame:GetVerticalScroll() or 0
        local startRow = math.floor(scrollY / STEP)
        local startIdx = startRow * COLS + 1

        for i = 1, POOL_SIZE do
            local b = btns[i]
            local dataIdx = startIdx + (i - 1)
            local fileID  = filtered[dataIdx]
            if fileID then
                b:Show()
                if b.icon then
                    b.icon:SetTexture(fileID)
                    b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                end
                local col = (dataIdx - 1) % COLS
                local row = math.floor((dataIdx - 1) / COLS)
                b:ClearAllPoints()
                b:SetPoint("TOPLEFT", grid, "TOPLEFT",
                    col * STEP, -(row * STEP))
                b:SetScript("OnClick", function()
                    if iconPickerCallback then iconPickerCallback(fileID) end
                    IconPicker:Hide()
                end)
            else
                b:Hide()
                b:SetScript("OnClick", nil)
            end
        end
    end

    local function populate()
        if not fullList then fullList, fullLabels = getIconList() end
        wipe(filtered)
        for _, id in ipairs(fullList) do filtered[#filtered + 1] = id end
        local rows = math.ceil(#filtered / COLS)
        grid:SetHeight(math.max(rows * STEP, 200))
        scrollFrame:SetVerticalScroll(0)
        updateVisible()
    end

    scrollFrame:SetScript("OnVerticalScroll", function(self, value)
        if self.ScrollBar and self.ScrollBar.SetValue then
            self.ScrollBar:SetValue(value)
        end
        updateVisible()
    end)

    IconPicker:SetScript("OnShow", populate)
end

local function openIconPicker(onPick)
    if not IconPicker then buildIconPicker() end
    iconPickerCallback = onPick
    IconPicker:Show()
end


local function ensureDB()
    DB = NS.API and NS.API.getDB and NS.API.getDB() or nil
    return DB ~= nil
end

------------------------------------------------------------------------
-- Widget factories
------------------------------------------------------------------------
local function makeLabel(parent, text, x, y, color)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    fs:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    fs:SetText(text)
    if color then fs:SetTextColor(unpack(color)) end
    return fs
end

-- Section header with a gold caption + horizontal divider line beneath.
-- Returns the FontString (for anchoring sub-widgets to its BOTTOMLEFT).
local function makeSection(parent, text, x, y)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    fs:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    fs:SetText("|cffffd200" .. text .. "|r")

    local line = parent:CreateTexture(nil, "ARTWORK")
    line:SetTexture("Interface\\Common\\UI-TooltipDivider-Transparent")
    line:SetHeight(8)
    line:SetPoint("LEFT", fs, "RIGHT", 8, 0)
    line:SetPoint("RIGHT", parent, "RIGHT", -10, 0)

    return fs
end

local function makeCheckbox(parent, label, getter, setter)
    local cb = CreateFrame("CheckButton", nil, parent, "InterfaceOptionsCheckButtonTemplate")
    cb.Text:SetText(label)
    cb:SetScript("OnShow", function(self) self:SetChecked(getter()) end)
    cb:SetScript("OnClick", function(self) setter(self:GetChecked()) end)
    return cb
end

local function makeSlider(parent, label, minV, maxV, step, getter, setter)
    local s = CreateFrame("Slider", nil, parent, "OptionsSliderTemplate")
    s:SetWidth(180)
    s:SetMinMaxValues(minV, maxV)
    s:SetValueStep(step)
    s:SetObeyStepOnDrag(true)
    s.Low:SetText(tostring(minV))
    s.High:SetText(tostring(maxV))
    s.Text:SetText(label)
    s:SetScript("OnShow", function(self) self:SetValue(getter()) end)
    s:SetScript("OnValueChanged", function(self, v)
        v = math.floor(v / step + 0.5) * step
        setter(v)
        if self.valueLabel then self.valueLabel:SetText(string.format("%.2f", v)) end
    end)
    s.valueLabel = s:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    s.valueLabel:SetPoint("TOP", s, "BOTTOM", 0, -2)
    return s
end

-- A dropdown whose choices regenerate each open via a function.
-- If `useIcons` is true, items are prefixed with the spell's icon.
local function iconLabelLocal(name)
    local _, _, icon = GetSpellInfo(name)
    if icon then
        return "|T" .. icon .. ":20:20:0:0:64:64:4:60:4:60|t  " .. name
    end
    return name
end

local function makeDynamicDropdown(parent, label, width, choicesFn, getter, setter, useIcons)
    local container = CreateFrame("Frame", nil, parent)
    local hasLabel = label and label ~= ""
    container:SetSize(width + 30, hasLabel and 50 or 30)

    local dd = CreateFrame("Frame", nil, container, "UIDropDownMenuTemplate")
    if hasLabel then
        local fs = container:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        fs:SetPoint("TOPLEFT", container, "TOPLEFT", 18, 0)
        fs:SetText(label)
        dd:SetPoint("TOPLEFT", fs, "BOTTOMLEFT", -16, -2)
    else
        dd:SetPoint("LEFT", container, "LEFT", -16, 0)
    end
    UIDropDownMenu_SetWidth(dd, width)

    local function refresh()
        local v = getter()
        UIDropDownMenu_SetText(dd, v and (useIcons and iconLabelLocal(v) or v) or "—")
    end

    UIDropDownMenu_Initialize(dd, function(self, level)
        for _, choice in ipairs(choicesFn()) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = useIcons and iconLabelLocal(choice) or choice
            info.checked = (getter() == choice)
            info.func = function()
                setter(choice)
                refresh()
                CloseDropDownMenus()
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end)

    container.refresh = refresh
    container.dropdown = dd
    container:SetScript("OnShow", refresh)
    return container
end

local function makeButton(parent, label, w, h)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(w or 80, h or 22)
    b:SetText(label)
    return b
end

------------------------------------------------------------------------
-- Stack list (scrollable rows)
------------------------------------------------------------------------
local stackRows = {}

local function refreshStackList(parent, countLabel, onEdit)
    local names = {}
    for n in pairs(DB.sets or {}) do names[#names + 1] = n end
    table.sort(names)

    countLabel:SetText(string.format("Saved stacks (%d / %d)", #names, MAX_STACKS))

    for _, row in ipairs(stackRows) do row:Hide() end

    for i, name in ipairs(names) do
        local row = stackRows[i]
        if not row then
            row = CreateFrame("Frame", nil, parent)
            row:SetSize(810, 20)
            row.name = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            row.name:SetPoint("LEFT", row, "LEFT", 0, 0)
            row.name:SetWidth(154); row.name:SetHeight(20)
            row.name:SetJustifyH("LEFT"); row.name:SetJustifyV("MIDDLE")
            row.name:SetWordWrap(false); row.name:SetMaxLines(1)
            row.detail = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.detail:SetPoint("LEFT", row.name, "RIGHT", 4, 0)
            row.detail:SetWidth(405); row.detail:SetHeight(20)
            row.detail:SetJustifyH("LEFT"); row.detail:SetJustifyV("MIDDLE")
            row.detail:SetWordWrap(false); row.detail:SetMaxLines(1)
            row.paired = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.paired:SetPoint("LEFT", row.detail, "RIGHT", 4, 0)
            row.paired:SetWidth(154); row.paired:SetHeight(20)
            row.paired:SetJustifyH("LEFT"); row.paired:SetJustifyV("MIDDLE")
            row.paired:SetWordWrap(false); row.paired:SetMaxLines(1)
            row.editBtn = makeButton(row, "Edit", 42, 20)
            row.editBtn:SetPoint("RIGHT", row, "RIGHT", -47, 0)
            row.delBtn = makeButton(row, "Del", 42, 20)
            row.delBtn:SetPoint("RIGHT", row, "RIGHT", 0, 0)
            stackRows[i] = row
        end

        row:Show()
        row:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -((i - 1) * 22))

        local prefix = (DB.activeSet == name) and "|cff00ff88* |r" or "  "
        row.name:SetText(prefix .. name)

        local set = DB.sets[name] or {}
        local short = {}
        for _, t in ipairs(set) do
            local s = t:gsub(" Totem", "")
            short[#short + 1] = (NS.TOTEM_SHORT and NS.TOTEM_SHORT[s]) or s
        end
        row.detail:SetText(table.concat(short, ", "))
        -- Sequences don't pair with anything (linkedUtil lives on
        -- Totem Stacks, not on Sequences) — leave the column dashed.
        row.paired:SetText("|cff888888—|r")

        row.editBtn:SetScript("OnClick", function()
            if onEdit then onEdit(name) end
        end)

        row.delBtn:SetScript("OnClick", function()
            DB.sets[name] = nil
            if DB.stackIcons then DB.stackIcons[name] = nil end
            if DB.setReset then DB.setReset[name] = nil end
            if DB.linkedUtil then DB.linkedUtil[name] = nil end
            if DB.activeSet == name then
                local first = next(DB.sets)
                DB.activeSet = first
                if not NS.API.inCombat() and first then NS.API.refresh() end
            end
            refreshStackList(parent, countLabel, onEdit)
        end)
    end
end

------------------------------------------------------------------------
-- Build the panel
------------------------------------------------------------------------
local function buildPanel()
    Panel = CreateFrame("Frame", "TotemTommysBarsOptions", UIParent, "BackdropTemplate")
    Panel:SetSize(PANEL_W, PANEL_H)
    Panel:SetPoint("CENTER")
    Panel:SetFrameStrata("DIALOG")
    Panel:SetMovable(true)
    Panel:EnableMouse(true)
    Panel:RegisterForDrag("LeftButton")
    Panel:SetScript("OnDragStart", Panel.StartMoving)
    Panel:SetScript("OnDragStop", Panel.StopMovingOrSizing)
    Panel:SetClampedToScreen(true)
    Panel:Hide()

    if Panel.SetBackdrop then
        Panel:SetBackdrop({
            bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Gold-Border",
            tile = true, tileSize = 16, edgeSize = 32,
            insets = { left = 11, right = 12, top = 12, bottom = 11 },
        })
        Panel:SetBackdropColor(0.05, 0.05, 0.07, 0.95)
        Panel:SetBackdropBorderColor(1, 1, 1, 1)
    end

    -- Header band (subtle dark stripe behind the title)
    local headerBand = Panel:CreateTexture(nil, "ARTWORK")
    headerBand:SetPoint("TOPLEFT", 14, -14)
    headerBand:SetPoint("TOPRIGHT", -14, -14)
    headerBand:SetHeight(46)
    headerBand:SetColorTexture(0.12, 0.10, 0.06, 0.85)

    local title = Panel:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    title:SetPoint("TOP", 0, -18)
    title:SetText("|cffffd200Totem Tommys Bars|r")

    -- Decorative gold divider line under the header band
    local headerDivider = Panel:CreateTexture(nil, "OVERLAY")
    headerDivider:SetTexture("Interface\\Common\\UI-TooltipDivider-Transparent")
    headerDivider:SetPoint("TOPLEFT", 18, -62)
    headerDivider:SetPoint("TOPRIGHT", -18, -62)
    headerDivider:SetHeight(8)

    local close = CreateFrame("Button", nil, Panel, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -4, -4)

    -- Footer band
    local footerBand = Panel:CreateTexture(nil, "ARTWORK")
    footerBand:SetPoint("BOTTOMLEFT", 14, 14)
    footerBand:SetPoint("BOTTOMRIGHT", -14, 14)
    footerBand:SetHeight(20)
    footerBand:SetColorTexture(0.12, 0.10, 0.06, 0.85)

    local footer = Panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    footer:SetPoint("BOTTOM", 0, 18)
    footer:SetText("|cff888888/ttb to toggle  •  drag header to move|r")

    -- Action buttons (Keybindings / Default Settings) — declared here so
    -- their OnClick closures capture the right upvalues, but PARENTED
    -- and POSITIONED below after `content` is created.  Living inside
    -- the scroll content means they scroll out of view like everything
    -- else instead of floating over and clipping the rows underneath.
    local resetBtn = makeButton(Panel, "Default Settings", 130, 22)
    resetBtn:SetScript("OnClick", function()
        if NS.API and NS.API.inCombat and NS.API.inCombat() then
            print("|cffffd000TTB:|r can't reset to defaults in combat.")
            return
        end
        if NS.API and NS.API.resetAllDefaults then
            NS.API.resetAllDefaults()
            -- Refresh the panel's widgets so checkboxes / sliders /
            -- dropdowns visually pick up the reset values.
            if Panel then Panel:Hide(); Panel:Show() end
        end
    end)
    resetBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText("|cffffd200Default Settings|r", 1, 1, 1)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Restores every option (scales, layouts, alert styles, modifier, combine flags, show flags, situational toggle, etc.) and every bar's screen position to the factory default.", 0.9, 0.9, 0.9, true)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Your saved Sequences, Totem Stacks and Utility Stacks are preserved.", 0.6, 0.8, 1, true)
        GameTooltip:Show()
    end)
    resetBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    local keybindBtn = makeButton(Panel, "Keybindings…", 130, 22)
    keybindBtn:SetScript("OnClick", function()
        -- Open Blizzard's native Key Bindings panel direct.  Classic
        -- 1.15+ uses the modern Settings system, which stores the
        -- Keybindings category under a known constant ID — passing
        -- that ID is reliable, whereas a localized name string is not.
        if Settings and Settings.OpenToCategory then
            local id = Settings.KEYBINDINGS_CATEGORY_ID
            if not id and SettingsPanel and SettingsPanel.GetCategory then
                -- Some builds expose categories by name; resolve the
                -- ID dynamically.
                local cat = SettingsPanel:GetCategory("Keybindings")
                if cat and cat.GetID then id = cat:GetID() end
            end
            if id then
                Settings.OpenToCategory(id)
                return
            end
            -- Last-resort name fallback.
            Settings.OpenToCategory("Keybindings")
            return
        end
        -- Pre-Settings UI: legacy InterfaceOptionsFrame.  Double call
        -- works around the well-known first-call-doesn't-stick bug.
        if InterfaceOptionsFrame_OpenToCategory then
            InterfaceOptionsFrame_OpenToCategory("Key Bindings")
            InterfaceOptionsFrame_OpenToCategory("Key Bindings")
            return
        end
        -- Standalone keybind frame (very old fallback).
        if KeyBindingFrame_LoadUI then
            KeyBindingFrame_LoadUI()
            if KeyBindingFrame then ShowUIPanel(KeyBindingFrame) end
        else
            openKeybindPanel()
        end
    end)

    --------------------------------------------------------------------
    -- Scrollable content area: holds all sections.  Top-right buttons
    -- stay pinned above; the scroll region is everything below them.
    --------------------------------------------------------------------
    local scrollFrame = CreateFrame("ScrollFrame", "TotemTommysBarsOptionsScroll",
        Panel, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 18, -90)
    scrollFrame:SetPoint("BOTTOMRIGHT", -34, 40)

    local content = CreateFrame("Frame", nil, scrollFrame)
    content:SetSize(PANEL_W - 50, 3600)  -- tall enough for all sections
    scrollFrame:SetScrollChild(content)

    --------------------------------------------------------------------
    -- Smooth mouse-wheel scrolling.  The default UIPanelScrollFrame
    -- handler jumps a large fraction of the viewport per click which
    -- feels clunky on a long form like this.  Override with a small,
    -- fixed pixel step so the wheel feels responsive but precise.
    --------------------------------------------------------------------
    local MAIN_SCROLL_STEP = 48  -- px per wheel notch (~60% faster than baseline 30)
    scrollFrame:EnableMouseWheel(true)
    scrollFrame:SetScript("OnMouseWheel", function(self, delta)
        local cur = self:GetVerticalScroll()
        local maxV = self:GetVerticalScrollRange()
        cur = cur - delta * MAIN_SCROLL_STEP
        if cur < 0 then cur = 0 end
        if cur > maxV then cur = maxV end
        self:SetVerticalScroll(cur)
    end)

    -- Re-parent the action buttons into the scroll content and pin them
    -- to its TOP-right corner.  They live inline at the top of the
    -- scrollable area so scrolling down rolls them out of view (same as
    -- every other section), eliminating the overlap with later rows.
    resetBtn:SetParent(content)
    keybindBtn:SetParent(content)
    resetBtn:ClearAllPoints()
    keybindBtn:ClearAllPoints()
    resetBtn:SetPoint("TOPRIGHT", content, "TOPRIGHT", -6, -6)
    keybindBtn:SetPoint("RIGHT", resetBtn, "LEFT", -8, 0)

    -- Helper: wrap a content region in a scroll frame so its inner list
    -- shows only `visibleRows` at a time and the user scrolls within.
    -- Used for the three "Saved …" lists below.
    local function makeListScroll(parent, w, visibleRows, maxRows)
        -- Gold-bordered backdrop around the scroll window so the user
        -- can see where the inner scrollable region starts and ends.
        local frame = CreateFrame("Frame", nil, parent, "BackdropTemplate")
        frame:SetSize(w, visibleRows * 22 + 8)
        if frame.SetBackdrop then
            frame:SetBackdrop({
                bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
                edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                tile = true, tileSize = 16, edgeSize = 12,
                insets = { left = 3, right = 3, top = 3, bottom = 3 },
            })
            frame:SetBackdropColor(0, 0, 0, 0.35)
            frame:SetBackdropBorderColor(0.85, 0.7, 0.2, 1)  -- gold
        end

        local sf = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
        sf:SetPoint("TOPLEFT", frame, "TOPLEFT", 4, -4)
        sf:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -4, 4)
        local inner = CreateFrame("Frame", nil, sf)
        inner:SetSize(w - 32, maxRows * 22)
        sf:SetScrollChild(inner)
        sf:EnableMouseWheel(true)
        sf:SetScript("OnMouseWheel", function(self, delta)
            local cur = self:GetVerticalScroll()
            local maxV = self:GetVerticalScrollRange()
            cur = cur - delta * 22
            if cur < 0 then cur = 0 end
            if cur > maxV then cur = maxV end
            self:SetVerticalScroll(cur)
        end)
        -- Callers anchor `frame` (the bordered outer) and parent rows to
        -- `inner` (the scroll child).  Return `frame` first so existing
        -- `:SetPoint` calls position the bordered wrapper.
        return frame, inner
    end

    -- Helper: scroll the main panel so a section sits near the top of
    -- the viewport.  Called by Edit buttons in the saved lists.
    local function snapToSection(sectionY)
        -- sectionY is the negative Y offset passed to makeSection
        -- (e.g. -1580 for Custom Totem Sequence).  Subtract a small
        -- margin so the title isn't flush against the top.
        local target = (-sectionY) - 30
        local maxV = scrollFrame:GetVerticalScrollRange()
        if target < 0 then target = 0 end
        if target > maxV then target = maxV end
        scrollFrame:SetVerticalScroll(target)
    end

    --------------------------------------------------------------------
    -- Section 1: Bar appearance
    --------------------------------------------------------------------
    local s1 = makeSection(content, "Bar appearance", 6, -10)

    local lock = makeCheckbox(content, "Lock bar (disable drag)",
        function() return DB.locked end,
        function(v) DB.locked = v and true or false; NS.API.layout() end)
    lock:SetPoint("TOPLEFT", s1, "BOTTOMLEFT", 0, -4)

    local alerts = makeCheckbox(content, "Missing-buff alert (In Combat Missing Only)",
        function() return DB.alerts end,
        function(v) DB.alerts = v and true or false; NS.API.updateAll() end)
    alerts:SetPoint("TOPLEFT", lock, "BOTTOMLEFT", 0, -2)

    local hideUnlearned = makeCheckbox(content, "Hide Unlearned Tooltips",
        function() return DB.hideUnlearned end,
        function(v) DB.hideUnlearned = v and true or false; NS.API.updateAll() end)
    hideUnlearned:SetPoint("TOPLEFT", alerts, "BOTTOMLEFT", 0, -2)

    --------------------------------------------------------------------
    -- Main Cycle Modifier: which modifier (when held with a "Drop X"
    -- keybind) cycles that slot instead of casting.  Shift-clicking the
    -- on-screen button always cycles regardless of this setting.
    --
    -- Wrapped in do/end so the local widgets/lookup tables release
    -- their slots — buildPanel is right up against Lua's 200-local cap.
    --------------------------------------------------------------------
    local cycleModAnchor  -- frame the next section anchors below
    do
        local CYCLE_MOD_CHOICES   = { "Shift", "Alt", "Ctrl", "None" }
        local CYCLE_MOD_TO_KEY    = { Shift = "shift", Alt = "alt", Ctrl = "ctrl", None = "none" }
        local CYCLE_KEY_TO_LABEL  = { shift = "Shift", alt = "Alt", ctrl = "Ctrl", none = "None" }
        local cycleModDD = makeDynamicDropdown(content, "Main Cycle Modifier  (affects all keybinds)", 160,
            function() return CYCLE_MOD_CHOICES end,
            function() return CYCLE_KEY_TO_LABEL[DB.cycleModifier or "shift"] or "Shift" end,
            function(v)
                DB.cycleModifier = CYCLE_MOD_TO_KEY[v] or "shift"
                if NS.API and NS.API.refreshCycleModifier then
                    NS.API.refreshCycleModifier()
                end
            end)
        cycleModDD:SetPoint("TOPLEFT", hideUnlearned, "BOTTOMLEFT", -16, -4)

        local cycleModDesc = content:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        cycleModDesc:SetPoint("TOPLEFT", cycleModDD, "BOTTOMLEFT", 18, 2)
        cycleModDesc:SetWidth(440); cycleModDesc:SetJustifyH("LEFT")
        cycleModDesc:SetText("Holding this modifier while pressing any 'Drop' keybind cycles that slot instead of casting (e.g. with Alt selected, Alt+A on 'Drop Fire Totem' cycles fire). Shift-clicking the on-screen button always cycles. WoW's secure-click engine only supports Shift / Alt / Ctrl as cycle modifiers — arbitrary keys (Q, F1, etc.) can't act as modifier prefixes.")
        cycleModAnchor = cycleModDesc
    end

    --------------------------------------------------------------------
    -- Combine sub-section: which groups merge onto a shared bar.
    --------------------------------------------------------------------
    local combineLabel = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    -- x=0 (was -18 — that was wrong, cycleModAnchor already inherits
    -- the dropdown's -16 internal padding which would have left the
    -- final position at content.left - 10, clipping "C" of "Combine"
    -- and "S" of "Show on screen" against the panel's gold border).
    combineLabel:SetPoint("TOPLEFT", cycleModAnchor, "BOTTOMLEFT", 0, -8)
    combineLabel:SetText("|cffffd200Combine|r  |cff888888(check 2+ to merge those groups onto one bar)|r")

    local function makeCombineCB(label, key)
        local cb = CreateFrame("CheckButton", nil, content, "InterfaceOptionsCheckButtonTemplate")
        cb.Text:SetText(label)
        cb:SetScript("OnShow", function(self) self:SetChecked(DB[key] and true or false) end)
        cb:SetScript("OnClick", function(self)
            DB[key] = self:GetChecked() and true or false
            NS.API.layout()
        end)
        return cb
    end

    local cbTotems  = makeCombineCB("Totems",  "combineTotems")
    local cbUtility = makeCombineCB("Utility", "combineUtility")
    local cbImbue   = makeCombineCB("Imbue",   "combineImbue")
    cbTotems:SetPoint("TOPLEFT",  combineLabel, "BOTTOMLEFT",   0, -2)
    cbUtility:SetPoint("TOPLEFT", combineLabel, "BOTTOMLEFT", 110, -2)
    cbImbue:SetPoint("TOPLEFT",   combineLabel, "BOTTOMLEFT", 220, -2)

    --------------------------------------------------------------------
    -- Show sub-section: which groups are visible on screen at all.
    --------------------------------------------------------------------
    local showLabel = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    showLabel:SetPoint("TOPLEFT", cbTotems, "BOTTOMLEFT", 0, -10)
    showLabel:SetText("|cffffd200Show on screen|r  |cff888888(uncheck to hide that group's bar)|r")

    local function makeShowCB(label, key)
        local cb = CreateFrame("CheckButton", nil, content, "InterfaceOptionsCheckButtonTemplate")
        cb.Text:SetText(label)
        cb:SetScript("OnShow", function(self) self:SetChecked(DB[key] ~= false) end)
        cb:SetScript("OnClick", function(self)
            DB[key] = self:GetChecked() and true or false
            if NS.API and NS.API.updateAll then NS.API.updateAll() end
            -- showTotemSequence / showTotemStacks gate whole sub-frames
            -- (StackBar, TotemStackBar) inside layout() rather than via
            -- refreshVisibility's per-button loop, so updateAll alone
            -- wouldn't re-hide them.  Force a layout pass.
            if NS.API and NS.API.layout then NS.API.layout() end
        end)
        return cb
    end

    local showT  = makeShowCB("Totems",         "showTotems")
    local showU  = makeShowCB("Utility",        "showUtility")
    local showI  = makeShowCB("Imbue",          "showImbue")
    local showSq = makeShowCB("Totem Sequence", "showTotemSequence")
    local showTS = makeShowCB("Totem Stacks",   "showTotemStacks")
    showT:SetPoint("TOPLEFT",  showLabel, "BOTTOMLEFT",   0, -2)
    showU:SetPoint("TOPLEFT",  showLabel, "BOTTOMLEFT", 110, -2)
    showI:SetPoint("TOPLEFT",  showLabel, "BOTTOMLEFT", 220, -2)
    showSq:SetPoint("TOPLEFT", showT,     "BOTTOMLEFT",   0, -2)
    showTS:SetPoint("TOPLEFT", showT,     "BOTTOMLEFT", 130, -2)

    --------------------------------------------------------------------
    -- Layout sub-section: one dropdown per group.
    --------------------------------------------------------------------
    local LAYOUT_LABELS = {
        horizontal = "Horizontal Row",
        vertical   = "Vertical Row",
        grid       = "Grid",
    }
    local LAYOUT_FROM_LABEL = {}
    for k, v in pairs(LAYOUT_LABELS) do LAYOUT_FROM_LABEL[v] = k end

    local function makeLayoutDD(label, dbKey)
        local dd = makeDynamicDropdown(content, label, 140,
            function() return { "Horizontal Row", "Vertical Row", "Grid" } end,
            function() return LAYOUT_LABELS[DB[dbKey] or "horizontal"] or "Horizontal Row" end,
            function(v)
                DB[dbKey] = LAYOUT_FROM_LABEL[v] or "horizontal"
                NS.API.layout()
            end)
        return dd
    end

    local totemLayoutDD    = makeLayoutDD("Totem layout",     "totemLayout")
    local utilLayoutDD     = makeLayoutDD("Utility layout",   "utilLayout")
    local imbueLayoutDD    = makeLayoutDD("Imbue layout",     "imbueLayout")
    local combinedLayoutDD = makeLayoutDD("Combined Setting", "combinedLayout")
    -- Stacked vertically so the wider dropdowns don't run off the panel edge.
    -- 4-across layout: Totem / Utility / Imbue / Combined sit on one
    -- row.  Spacing is computed from content width so the row scales
    -- with the panel size.
    totemLayoutDD:SetPoint("TOPLEFT",     showSq,          "BOTTOMLEFT", -2, -16)
    utilLayoutDD:SetPoint("TOPLEFT",      totemLayoutDD,   "TOPRIGHT",  30,   0)
    imbueLayoutDD:SetPoint("TOPLEFT",     utilLayoutDD,    "TOPRIGHT",  30,   0)
    combinedLayoutDD:SetPoint("TOPLEFT",  imbueLayoutDD,   "TOPRIGHT",  30,   0)

    --------------------------------------------------------------------
    -- Scale sliders — all four on a single row, mirroring the
    -- 4-across layout dropdowns above.
    --   Scale | Totem Bar | Imbue Bar | Utility Bar
    --------------------------------------------------------------------
    local scale = makeSlider(content, "Scale", 0.5, 2.0, 0.05,
        function() return DB.scale end,
        function(v) DB.scale = v; NS.API.layout() end)
    scale:SetPoint("TOPLEFT", totemLayoutDD, "BOTTOMLEFT", 18, -28)

    local totemScaleS = makeSlider(content, "Totem Bar scale", 0.5, 2.0, 0.05,
        function() return DB.totemScale or 1.0 end,
        function(v) DB.totemScale = v; NS.API.layout() end)
    totemScaleS:SetPoint("LEFT", scale, "RIGHT", 40, 0)

    local imbueScale = makeSlider(content, "Imbue bar scale", 0.5, 2.0, 0.05,
        function() return DB.imbueScale or 1.5 end,
        function(v) DB.imbueScale = v; NS.API.layout() end)
    imbueScale:SetPoint("LEFT", totemScaleS, "RIGHT", 40, 0)

    local utilScaleS = makeSlider(content, "Utility Bar scale", 0.5, 2.0, 0.05,
        function() return DB.utilScale or 1.0 end,
        function(v) DB.utilScale = v; NS.API.layout() end)
    utilScaleS:SetPoint("LEFT", imbueScale, "RIGHT", 40, 0)

    --------------------------------------------------------------------
    -- Combined-bar scale preference
    --------------------------------------------------------------------
    local combinedScaleNote = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    combinedScaleNote:SetPoint("TOPLEFT", scale, "BOTTOMLEFT", -18, -28)
    combinedScaleNote:SetWidth(460); combinedScaleNote:SetJustifyH("LEFT")
    combinedScaleNote:SetText("|cffaaaaaaWhen combining, all combined bars use the scale of the:|r")

    local cbHigher = CreateFrame("CheckButton", nil, content, "InterfaceOptionsCheckButtonTemplate")
    cbHigher.Text:SetText("Higher scale setting")
    cbHigher:SetPoint("TOPLEFT", combinedScaleNote, "BOTTOMLEFT", 0, -2)

    local cbLower = CreateFrame("CheckButton", nil, content, "InterfaceOptionsCheckButtonTemplate")
    cbLower.Text:SetText("Lower scale setting")
    cbLower:SetPoint("LEFT", cbHigher, "RIGHT", 140, 0)

    -- Mutually exclusive: clicking one un-checks the other.  Exactly one
    -- is always set; clicking the already-checked one is a no-op.
    local function applyScalePref(pref)
        DB.combinedScalePref = pref
        cbHigher:SetChecked(pref == "higher")
        cbLower:SetChecked(pref == "lower")
        NS.API.layout()
    end
    cbHigher:SetScript("OnShow", function() cbHigher:SetChecked((DB.combinedScalePref or "higher") == "higher") end)
    cbLower:SetScript("OnShow",  function() cbLower:SetChecked((DB.combinedScalePref or "higher") == "lower") end)
    cbHigher:SetScript("OnClick", function(self)
        if not self:GetChecked() then self:SetChecked(true) end  -- can't un-check
        applyScalePref("higher")
    end)
    cbLower:SetScript("OnClick", function(self)
        if not self:GetChecked() then self:SetChecked(true) end
        applyScalePref("lower")
    end)

    --------------------------------------------------------------------
    -- Section 2 (formerly "Utility (tick to show)") was removed.  Bar
    -- utility slots now draw freely from any known shaman utility — pick
    -- via right-click on the slot, or via Utility Stacks below.
    --------------------------------------------------------------------

    --------------------------------------------------------------------
    -- Section 2.5: In Combat Missing Alert (per-button toggles)
    --------------------------------------------------------------------
    local sAlert = makeSection(content, "In Combat Missing Alert", 6, -710)

    -- Test Animations button — fires every enabled alert on screen for ~3s
    local testBtn = makeButton(content, "Test Animations", 130, 22)
    testBtn:SetPoint("TOPRIGHT", content, "TOPRIGHT", -10, -636)
    testBtn:SetScript("OnClick", function()
        if NS.API and NS.API.previewAlerts then NS.API.previewAlerts() end
    end)

    local function makeAlertCB(key, label)
        local cb = CreateFrame("CheckButton", nil, content, "InterfaceOptionsCheckButtonTemplate")
        cb.Text:SetText(label)
        cb:SetScript("OnShow", function(self)
            self:SetChecked(DB.combatAlerts and DB.combatAlerts[key] == true)
        end)
        cb:SetScript("OnClick", function(self)
            DB.combatAlerts = DB.combatAlerts or {}
            DB.combatAlerts[key] = self:GetChecked() and true or false
            NS.API.updateAll()
        end)
        return cb
    end

    local function makeSubHeader(text, fontTemplate)
        local fs = content:CreateFontString(nil, "OVERLAY", fontTemplate or "GameFontNormalSmall")
        fs:SetText("|cffffd200" .. text .. "|r")
        return fs
    end

    -- Style catalogues come from Data.lua so they stay in sync with Core.
    local function labelsOf(catalog)
        local out = {}
        for _, entry in ipairs(catalog) do out[#out + 1] = entry.label end
        return out
    end
    local function keyForLabel(catalog, label)
        for _, entry in ipairs(catalog) do
            if entry.label == label then return entry.key end
        end
        return catalog[1] and catalog[1].key
    end
    local function labelForKey(catalog, key)
        for _, entry in ipairs(catalog) do
            if entry.key == key then return entry.label end
        end
        return catalog[1] and catalog[1].label
    end

    -- One row = enable-checkbox + "Style:" dropdown.  Anchored below the
    -- given anchor frame.  Returns the checkbox so the caller can use it
    -- as the next row's anchor.
    local function makeStyleRow(group, subkey, label, catalog, anchor)
        local cb = CreateFrame("CheckButton", nil, content, "InterfaceOptionsCheckButtonTemplate")
        cb.Text:SetText(label)
        cb:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2)
        cb:SetScript("OnShow", function(self)
            self:SetChecked(DB.alertStyles[group][subkey] ~= false)
        end)
        cb:SetScript("OnClick", function(self)
            DB.alertStyles[group][subkey] = self:GetChecked() and true or false
            NS.API.updateAll()
        end)

        local styleKey = subkey .. "Style"
        -- No label on the dropdown itself — a single "Style" caption is
        -- drawn separately next to the middle row by the caller.
        local dd = makeDynamicDropdown(content, "", 200,
            function() return labelsOf(catalog) end,
            function() return labelForKey(catalog, DB.alertStyles[group][styleKey]) end,
            function(lbl)
                DB.alertStyles[group][styleKey] = keyForLabel(catalog, lbl)
            end)
        dd:SetPoint("LEFT", cb, "RIGHT", 110, 0)
        return cb, dd
    end

    -- "Style" caption.  Anchored on the same baseline as the section's
    -- sub-header (Imbue / Utility / Totems) so it reads as a column
    -- header on the right side, horizontally aligned with the dropdown
    -- column.
    local function addStyleCaption(headerFrame, firstDD)
        local fs = content:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        fs:SetText("|cffd0a35aStyle|r")
        -- Vertical: inline with the section sub-header.
        -- Horizontal: pinned over the start of the dropdown column.
        fs:SetPoint("TOP",  headerFrame, "TOP",   0, 0)
        fs:SetPoint("LEFT", firstDD,     "LEFT",  0, 0)
        return fs
    end

    -- Adds the "Running out timer" checkbox under the Flashes row of a
    -- subsection.  Toggles DB.alertStyles[group].warning.
    local function addWarningRow(group, anchor)
        local cb = CreateFrame("CheckButton", nil, content, "InterfaceOptionsCheckButtonTemplate")
        cb.Text:SetText("Running out timer  |cff888888(Red border @10% duration)|r")
        cb:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2)
        cb:SetScript("OnShow", function(self)
            self:SetChecked(DB.alertStyles[group].warning ~= false)
        end)
        cb:SetScript("OnClick", function(self)
            DB.alertStyles[group].warning = self:GetChecked() and true or false
            NS.API.updateAll()
        end)
        return cb
    end

    -- Adds the "Duration Timer" checkbox under the Running-out row.
    -- Toggles DB.alertStyles[group].duration (yellow text above button).
    local function addDurationRow(group, anchor)
        local cb = CreateFrame("CheckButton", nil, content, "InterfaceOptionsCheckButtonTemplate")
        cb.Text:SetText("Duration Timer  |cff888888(Yellow text above button)|r")
        cb:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2)
        cb:SetScript("OnShow", function(self)
            self:SetChecked(DB.alertStyles[group].duration ~= false)
        end)
        cb:SetScript("OnClick", function(self)
            DB.alertStyles[group].duration = self:GetChecked() and true or false
            NS.API.updateAll()
        end)
        return cb
    end

    -- Adds the "CD Timer" checkbox under the Duration row.  Toggles
    -- DB.alertStyles[group].cd (cooldown swipe + built-in countdown).
    local function addCDRow(group, anchor)
        local cb = CreateFrame("CheckButton", nil, content, "InterfaceOptionsCheckButtonTemplate")
        cb.Text:SetText("CD Timer  |cff888888(Cooldown swipe + clock)|r")
        cb:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2)
        cb:SetScript("OnShow", function(self)
            self:SetChecked(DB.alertStyles[group].cd ~= false)
        end)
        cb:SetScript("OnClick", function(self)
            DB.alertStyles[group].cd = self:GetChecked() and true or false
            NS.API.updateAll()
        end)
        return cb
    end

    -- Imbue subsection (50px below section title, 30px before options)
    local imbueHdr = makeSubHeader("Imbue", "GameFontNormalLarge")
    imbueHdr:SetPoint("TOPLEFT", sAlert, "BOTTOMLEFT", 0, -50)
    local mhAlertCB = makeAlertCB("mh", "Main Hand")
    local ohAlertCB = makeAlertCB("oh", "Off-Hand")
    local lsAlertCB = makeAlertCB("ls", "Shield")
    mhAlertCB:SetPoint("TOPLEFT", imbueHdr, "BOTTOMLEFT",   0, -30)
    ohAlertCB:SetPoint("TOPLEFT", imbueHdr, "BOTTOMLEFT", 150, -30)
    lsAlertCB:SetPoint("TOPLEFT", imbueHdr, "BOTTOMLEFT", 290, -30)

    local imbueMoveCB,  imbueMoveDD  = makeStyleRow("imbue", "movement", "Movement", NS.MOVEMENT_STYLES, mhAlertCB)
    local imbueAudioCB, imbueAudioDD = makeStyleRow("imbue", "audio",    "Audio",    NS.AUDIO_STYLES,    imbueMoveCB)
    local imbueFlashCB, imbueFlashDD = makeStyleRow("imbue", "flashes",  "Flashes",  NS.FLASH_STYLES,    imbueAudioCB)
    addStyleCaption(imbueHdr, imbueMoveDD)
    local imbueWarnCB = addWarningRow("imbue", imbueFlashCB)
    local imbueDurCB  = addDurationRow("imbue", imbueWarnCB)
    local imbueCDCB   = addCDRow("imbue", imbueDurCB)

    -- Utility subsection (50px below previous block, 30px before options)
    local utilHdr = makeSubHeader("Utility", "GameFontNormalLarge")
    utilHdr:SetPoint("TOPLEFT", imbueCDCB, "BOTTOMLEFT", 0, -50)
    local u1AlertCB = makeAlertCB("util_1", "Utility 1")
    local u2AlertCB = makeAlertCB("util_2", "Utility 2")
    u1AlertCB:SetPoint("TOPLEFT", utilHdr, "BOTTOMLEFT",   0, -30)
    u2AlertCB:SetPoint("TOPLEFT", utilHdr, "BOTTOMLEFT", 150, -30)

    local utilMoveCB,  utilMoveDD  = makeStyleRow("util", "movement", "Movement", NS.MOVEMENT_STYLES, u1AlertCB)
    local utilAudioCB, utilAudioDD = makeStyleRow("util", "audio",    "Audio",    NS.AUDIO_STYLES,    utilMoveCB)
    local utilFlashCB, utilFlashDD = makeStyleRow("util", "flashes",  "Flashes",  NS.FLASH_STYLES,    utilAudioCB)
    addStyleCaption(utilHdr, utilMoveDD)
    local utilWarnCB = addWarningRow("util", utilFlashCB)
    local utilDurCB  = addDurationRow("util", utilWarnCB)
    local utilCDCB   = addCDRow("util", utilDurCB)

    -- Totems subsection (50px below previous block, 30px before options)
    local totemHdr = makeSubHeader("Totems", "GameFontNormalLarge")
    totemHdr:SetPoint("TOPLEFT", utilCDCB, "BOTTOMLEFT", 0, -50)
    local tFireCB  = makeAlertCB("totem_fire",  "Fire")
    local tWaterCB = makeAlertCB("totem_water", "Water")
    local tEarthCB = makeAlertCB("totem_earth", "Earth")
    local tAirCB   = makeAlertCB("totem_air",   "Air")
    tFireCB:SetPoint("TOPLEFT",  totemHdr, "BOTTOMLEFT",   0, -30)
    tWaterCB:SetPoint("TOPLEFT", totemHdr, "BOTTOMLEFT", 110, -30)
    tEarthCB:SetPoint("TOPLEFT", totemHdr, "BOTTOMLEFT", 220, -30)
    tAirCB:SetPoint("TOPLEFT",   totemHdr, "BOTTOMLEFT", 330, -30)

    -- Situational totems toggle (Earthbind, Tremor, Stoneclaw, etc.)
    local situationalCB = CreateFrame("CheckButton", nil, content, "InterfaceOptionsCheckButtonTemplate")
    situationalCB.Text:SetText("Enable situational totem animation")
    situationalCB:SetPoint("TOPLEFT", tFireCB, "BOTTOMLEFT", 0, -2)
    situationalCB:SetScript("OnShow", function(self)
        self:SetChecked(DB.enableSituationalTotemAlerts and true or false)
    end)
    situationalCB:SetScript("OnClick", function(self)
        DB.enableSituationalTotemAlerts = self:GetChecked() and true or false
        NS.API.updateAll()
    end)

    -- Description below the checkbox so the user understands what
    -- "situational" means before enabling.
    local situationalDesc = content:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    situationalDesc:SetPoint("TOPLEFT", situationalCB, "BOTTOMLEFT", 28, -2)
    situationalDesc:SetWidth(420); situationalDesc:SetJustifyH("LEFT")
    situationalDesc:SetText("Situational totems (Earthbind, Stoneclaw, Tremor, Grounding, Sentry, Fire Nova, Disease/Poison Cleansing) are dropped on demand — not meant to stay up. By default they never pulse the 'missing totem' alert even when set as the active default for their element, since they'd alert constantly while sitting on cooldown. Enable this only if you intentionally keep a situational totem up as your standard and want the missing-alert behavior to match.")

    local totemMoveCB,  totemMoveDD  = makeStyleRow("totem", "movement", "Movement", NS.MOVEMENT_STYLES, situationalDesc)
    local totemAudioCB, totemAudioDD = makeStyleRow("totem", "audio",    "Audio",    NS.AUDIO_STYLES,    totemMoveCB)
    local totemFlashCB, totemFlashDD = makeStyleRow("totem", "flashes",  "Flashes",  NS.FLASH_STYLES,    totemAudioCB)
    addStyleCaption(totemHdr, totemMoveDD)
    local totemWarnCB = addWarningRow("totem", totemFlashCB)
    local totemDurCB  = addDurationRow("totem", totemWarnCB)
    local totemCDCB   = addCDRow("totem", totemDurCB)

    --------------------------------------------------------------------
    -- Section 3: Custom Stacks
    --------------------------------------------------------------------
    local s3 = makeSection(content, "Custom Totem Sequence", 6, -1700)

    -- Section description
    local s3Desc = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    s3Desc:SetPoint("TOPLEFT", s3, "BOTTOMLEFT", 0, -4)
    s3Desc:SetWidth(440); s3Desc:SetJustifyH("LEFT")
    s3Desc:SetText("|cffaaaaaaCustom totem sequences are customizable pre-loaded totem setups. Choose which 4 to save as a sequence, then one button fires through them, placing each totem down one after another with each click.|r")

    -- These must be declared before any closure that captures them.
    local showUnlearned = false
    local filterableDDs = {}

    -- Three identical "Show Unlearned Spells" checkboxes — one under
    -- each builder's section description (Sequence / Totem Stacks /
    -- Utility Stacks).  All three are kept in `showUnlearnedCBs` and
    -- sync via a shared OnClick that updates `showUnlearned` and ticks
    -- every other checkbox to match.
    local showUnlearnedCBs = {}
    local function makeShowUnlearnedCB(anchor)
        local cb = CreateFrame("CheckButton", nil, content, "InterfaceOptionsCheckButtonTemplate")
        cb.Text:SetText("Show Unlearned Spells")
        cb:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -8)
        cb:SetScript("OnShow", function(self) self:SetChecked(showUnlearned) end)
        cb:SetScript("OnClick", function(self)
            showUnlearned = self:GetChecked() and true or false
            for _, peer in ipairs(showUnlearnedCBs) do
                if peer ~= self then peer:SetChecked(showUnlearned) end
            end
            for _, dd in ipairs(filterableDDs) do
                if dd and dd.refresh then dd.refresh() end
            end
        end)
        showUnlearnedCBs[#showUnlearnedCBs + 1] = cb
        return cb
    end

    local showUnlearnedCB = makeShowUnlearnedCB(s3Desc)

    -- Name editbox
    local nameLabel = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    nameLabel:SetPoint("TOPLEFT", showUnlearnedCB, "BOTTOMLEFT", 4, -4)
    nameLabel:SetText("Stack name:")

    local nameBox = CreateFrame("EditBox", nil, content, "InputBoxTemplate")
    nameBox:SetSize(200, 22)
    nameBox:SetAutoFocus(false)
    nameBox:SetPoint("LEFT", nameLabel, "RIGHT", 12, 0)
    nameBox:SetMaxLetters(20)

    -- Pending-stack state (what the editor is building)
    local pending = { nil, nil, nil, nil }  -- fire, water, earth, air
    local pendingIconChoice  -- 1..4 (slot index) or nil for "auto"
    local refreshIconBtn  -- forward declaration; defined below

    -- (`showUnlearned` and `filterableDDs` were declared earlier, above
    -- the showUnlearnedCB OnClick that captures them.)

    local function knownOnly(list)
        if showUnlearned then
            -- pass through all options unchanged
            local out = {}
            for _, n in ipairs(list) do out[#out + 1] = n end
            return out
        end
        local out = {}
        for _, n in ipairs(list) do
            local _, _, _, _, _, _, spellID = GetSpellInfo(n)
            if spellID and IsPlayerSpell and IsPlayerSpell(spellID) then
                out[#out + 1] = n
            elseif GetSpellBookItemInfo then
                local _, id = GetSpellBookItemInfo(n)
                if id then out[#out + 1] = n end
            end
        end
        return out
    end

    local function makeElementPicker(idx, element, totems)
        local dd = makeDynamicDropdown(content, element:upper(), 170,
            function()
                local out = { "(none)" }
                for _, n in ipairs(knownOnly(totems)) do
                    out[#out + 1] = n
                end
                return out
            end,
            function() return pending[idx] or "(none)" end,
            function(v)
                pending[idx] = (v == "(none)") and nil or v
                if refreshIconBtn then refreshIconBtn() end
            end,
            true)  -- show icons
        return dd
    end

    local fireDD  = makeElementPicker(1, "fire",  NS.TOTEMS.fire)
    local waterDD = makeElementPicker(2, "water", NS.TOTEMS.water)
    local earthDD = makeElementPicker(3, "earth", NS.TOTEMS.earth)
    local airDD   = makeElementPicker(4, "air",   NS.TOTEMS.air)
    filterableDDs[#filterableDDs + 1] = fireDD
    filterableDDs[#filterableDDs + 1] = waterDD
    filterableDDs[#filterableDDs + 1] = earthDD
    filterableDDs[#filterableDDs + 1] = airDD

    -- 4 element dropdowns stacked vertically (one per line)
    -- 2x2 element-picker grid.  Each element DD has its Order DD on
    -- the immediate right (anchored below).  Column 2 starts ~360 px
    -- to the right of column 1 so both fit inside the wider panel.
    fireDD:SetPoint("TOPLEFT",  nameLabel, "BOTTOMLEFT", 0,   -8)
    waterDD:SetPoint("TOPLEFT", fireDD,    "TOPRIGHT", 110,   0)
    earthDD:SetPoint("TOPLEFT", fireDD,    "BOTTOMLEFT", 0,  -4)
    airDD:SetPoint("TOPLEFT",   earthDD,   "TOPRIGHT", 110,   0)

    --------------------------------------------------------------------
    -- Per-element order picker — sits to the right of each totem
    -- dropdown.  Order values 1..4 must be unique; picking N for an
    -- element automatically swaps with whichever element previously held N.
    --------------------------------------------------------------------
    local pendingOrder = { 1, 2, 3, 4 }  -- fire, water, earth, air

    local function setOrder(idx, newVal)
        if pendingOrder[idx] == newVal then return end
        for i = 1, 4 do
            if i ~= idx and pendingOrder[i] == newVal then
                pendingOrder[i] = pendingOrder[idx]
                break
            end
        end
        pendingOrder[idx] = newVal
    end

    local orderDDs = {}
    local function makeOrderPicker(idx)
        local dd = makeDynamicDropdown(content, "Order", 60,
            function() return { "1", "2", "3", "4" } end,
            function() return tostring(pendingOrder[idx]) end,
            function(v)
                setOrder(idx, tonumber(v) or pendingOrder[idx])
                for _, o in ipairs(orderDDs) do
                    if o and o.refresh then o.refresh() end
                end
                if refreshIconBtn then refreshIconBtn() end
            end)
        return dd
    end

    local orderFire  = makeOrderPicker(1)
    local orderWater = makeOrderPicker(2)
    local orderEarth = makeOrderPicker(3)
    local orderAir   = makeOrderPicker(4)
    orderDDs[1] = orderFire
    orderDDs[2] = orderWater
    orderDDs[3] = orderEarth
    orderDDs[4] = orderAir

    orderFire:SetPoint("LEFT",  fireDD,  "RIGHT", 18, 0)
    orderWater:SetPoint("LEFT", waterDD, "RIGHT", 18, 0)
    orderEarth:SetPoint("LEFT", earthDD, "RIGHT", 18, 0)
    orderAir:SetPoint("LEFT",   airDD,   "RIGHT", 18, 0)

    --------------------------------------------------------------------
    -- editTotemStack(name) — loads a saved stack into the editor fields
    -- so the user can modify and re-Save it.
    --------------------------------------------------------------------
    local ELEM_TO_IDX = { fire = 1, water = 2, earth = 3, air = 4 }
    local function totemElement(totemName)
        for elem, list in pairs(NS.TOTEMS) do
            for _, n in ipairs(list) do
                if n == totemName then return elem end
            end
        end
    end

    -- Forward-declared so editTotemStack can write into them.  Real
    -- assignment happens in the "Reset timer" UI block further down.
    local pendingReset = 8
    local resetBox  -- editbox widget

    local function editTotemStack(name)
        local set = DB.sets and DB.sets[name]
        if not set then return end
        nameBox:SetText(name)
        for i = 1, 4 do pending[i] = nil end
        pendingOrder = { 1, 2, 3, 4 }
        for setIdx, totem in ipairs(set) do
            local elem = totemElement(totem)
            local idx = elem and ELEM_TO_IDX[elem]
            if idx then
                pending[idx] = totem
                pendingOrder[idx] = setIdx
            end
        end
        -- Assign trailing orders to unfilled elements
        local nextOrder = #set + 1
        for i = 1, 4 do
            if not pending[i] then
                pendingOrder[i] = nextOrder
                nextOrder = nextOrder + 1
            end
        end
        pendingIconFileID = DB.stackIcons and DB.stackIcons[name] or nil
        pendingLink       = DB.linkedUtil and DB.linkedUtil[name] or nil
        pendingReset      = (DB.setReset and DB.setReset[name]) or 8
        if resetBox then resetBox:SetText(tostring(pendingReset)) end
        if refreshIconBtn then refreshIconBtn() end
        for _, dd in ipairs({ fireDD, waterDD, earthDD, airDD }) do dd.refresh() end
        for _, dd in ipairs(orderDDs) do if dd.refresh then dd.refresh() end end
    end

    -- Wraps editTotemStack so the Edit button in the Saved Sequence list
    -- also snaps the panel scroll to the Custom Totem Sequence editor.
    local function sequenceEditAndSnap(name)
        editTotemStack(name)
        snapToSection(-1700)  -- s3
    end

    --------------------------------------------------------------------
    -- Stack icon picker: click to cycle through the four chosen totems'
    -- icons.  pendingIconChoice is 1..4 (which slot's icon to use), or
    -- nil = auto (first non-empty totem).
    --------------------------------------------------------------------
    local iconLabel2 = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    iconLabel2:SetText("Stack icon:")
    -- Now that the 4 element DDs are in a 2x2 grid, anchor the icon
    -- row below earthDD (row 2 col 1) instead of airDD (row 2 col 2)
    -- so it stays on the left side of the panel.
    iconLabel2:SetPoint("TOPLEFT", earthDD, "BOTTOMLEFT", 18, -8)

    -- Stack icon button — uses the same ActionButtonTemplate the bar
    -- buttons use, so it picks up the standard WoW border + highlight.
    local iconBtn = CreateFrame("Button", nil, content, "ActionButtonTemplate")
    iconBtn:SetSize(40, 40)
    iconBtn:SetPoint("LEFT", iconLabel2, "RIGHT", 12, 0)
    if iconBtn.icon then
        iconBtn.icon:ClearAllPoints()
        iconBtn.icon:SetPoint("TOPLEFT",     iconBtn, "TOPLEFT",      2, -2)
        iconBtn.icon:SetPoint("BOTTOMRIGHT", iconBtn, "BOTTOMRIGHT", -2,  2)
        iconBtn.icon:SetTexture(134400)
        iconBtn.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    end

    -- `pendingIconChoice` was the slot-index cycle; replaced by an
    -- explicit fileID stored on this same local so the rest of the editor
    -- code (Save / Clear) still works without changes.
    local pendingIconFileID  -- explicit fileID picked from the icon picker

    -- Auto-icon = spell-icon of whichever element holds the lowest
    -- pendingOrder value (i.e. the first totem in the cast sequence).
    local function autoIconFileID()
        for orderPos = 1, 4 do
            for i = 1, 4 do
                if pendingOrder[i] == orderPos and pending[i] then
                    return select(3, GetSpellInfo(pending[i]))
                end
            end
        end
        return nil
    end

    refreshIconBtn = function()
        local fileID = pendingIconFileID or autoIconFileID()
        if iconBtn.icon then
            iconBtn.icon:SetTexture(fileID or 134400)
            iconBtn.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        end
    end

    iconBtn:SetScript("OnClick", function()
        openIconPicker(function(fileID)
            pendingIconFileID = fileID
            refreshIconBtn()
        end)
    end)
    iconBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Stack icon", 1, 1, 1)
        GameTooltip:AddLine("Click to pick from the full icon library.", 0.7, 0.7, 0.7)
        GameTooltip:AddLine("Auto = first totem in this stack.", 0.5, 0.8, 1)
        GameTooltip:Show()
    end)
    iconBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- (Link Utility Stack moved to the Totem Stacks section.)
    -- Keep pendingLink as a no-op so the Save block can still reference it.
    local pendingLink = nil

    --------------------------------------------------------------------
    -- Reset timer — per-sequence customizable rollback window.
    --
    -- The /castsequence engine and the addon's idle-reset poll both
    -- read this value.  If the next totem in this sequence isn't cast
    -- within N seconds (or you change target), the sequence rolls back
    -- to step 1 and the Sequence button's icon reverts to the first
    -- totem.  Default 8s; lower it for tight rotations, raise it for
    -- slow leveling pulls.
    --------------------------------------------------------------------
    -- (pendingReset and resetBox are forward-declared above editTotemStack.)

    do
        local resetLabel1 = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        resetLabel1:SetPoint("LEFT", iconBtn, "RIGHT", 24, 8)
        resetLabel1:SetText("Reset timer (seconds):")

        resetBox = CreateFrame("EditBox", nil, content, "InputBoxTemplate")
        resetBox:SetSize(48, 22)
        resetBox:SetAutoFocus(false)
        resetBox:SetNumeric(true)
        resetBox:SetMaxLetters(3)
        resetBox:SetPoint("LEFT", resetLabel1, "RIGHT", 8, 0)
        resetBox:SetText("8")
    resetBox:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
        local v = tonumber(self:GetText()) or 8
        if v < 1 then v = 1 end
        if v > 120 then v = 120 end
        pendingReset = v
        self:SetText(tostring(v))
    end)
    resetBox:SetScript("OnEditFocusLost", function(self)
        local v = tonumber(self:GetText()) or 8
        if v < 1 then v = 1 end
        if v > 120 then v = 120 end
        pendingReset = v
        self:SetText(tostring(v))
    end)
    end  -- end do-block wrapping the reset-timer label/editbox

    -- Description for the reset timer.  Anchored below the Save/Clear
    -- button row (see resetDesc:SetPoint after clearBtn is created) so
    -- it doesn't overlap any other widget or spill past the panel edge.

    -- (Saved-stacks list is built further down in its own section.)
    local listFrame  -- forward-declared; populated below
    local countLabel -- forward-declared; populated below

    -- Save / Clear buttons (placed below the icon-picker row)
    local saveBtn = makeButton(content, "Save Stack", 110, 24)
    saveBtn:SetPoint("TOPLEFT", iconLabel2, "BOTTOMLEFT", 0, -16)
    saveBtn:SetScript("OnClick", function()
        local nm = nameBox:GetText():match("^%s*(.-)%s*$")
        if not nm or nm == "" then
            print("|cffff5555TTB:|r enter a stack name first.")
            return
        end
        local count = 0
        for _ in pairs(DB.sets) do count = count + 1 end
        if not DB.sets[nm] and count >= MAX_STACKS then
            print(string.format("|cffff5555TTB:|r max %d stacks. Delete one first.", MAX_STACKS))
            return
        end
        -- Build the set in the order the user chose.  pendingOrder maps
        -- each element index → its cast-sequence position (1..4).
        local byOrder = {}
        for i = 1, 4 do
            if pending[i] then byOrder[pendingOrder[i]] = pending[i] end
        end
        local set = {}
        for i = 1, 4 do
            if byOrder[i] then set[#set + 1] = byOrder[i] end
        end
        if #set == 0 then
            print("|cffff5555TTB:|r select at least one totem.")
            return
        end
        DB.sets[nm] = set
        -- Persist chosen icon (or nil for auto = first totem)
        DB.stackIcons = DB.stackIcons or {}
        -- If the user hasn't manually picked an icon, persist the
        -- order-1 totem's icon (matches what the preview was showing).
        DB.stackIcons[nm] = pendingIconFileID or autoIconFileID()
        -- Persist per-sequence reset timer (seconds).  Read directly
        -- from the editbox so a Save click before pressing Enter or
        -- tabbing away still picks up the user's typed value.
        if resetBox then
            local v = tonumber(resetBox:GetText())
            if v then
                if v < 1 then v = 1 end
                if v > 120 then v = 120 end
                pendingReset = v
                resetBox:SetText(tostring(v))
            end
        end
        DB.setReset = DB.setReset or {}
        DB.setReset[nm] = pendingReset or 8
        -- (Linked utility stacks are now persisted on Totem Stacks, not
        -- on Totem Sequences.)
        if not DB.activeSet or not DB.sets[DB.activeSet] then
            DB.activeSet = nm
            if not NS.API.inCombat() then NS.API.refresh() end
        end
        -- If the just-saved set is the active one, refresh the bar's stack icon
        if DB.activeSet == nm and not NS.API.inCombat() then NS.API.refresh() end
        nameBox:SetText("")
        for i = 1, 4 do pending[i] = nil end
        pendingIconChoice = nil
        pendingIconFileID = nil
        pendingOrder = { 1, 2, 3, 4 }
        for _, o in ipairs(orderDDs) do
            if o and o.refresh then o.refresh() end
        end
        pendingLink = nil
        pendingReset = 8
        if resetBox then resetBox:SetText("8") end
        refreshIconBtn()
        for _, dd in ipairs({ fireDD, waterDD, earthDD, airDD }) do dd.refresh() end
        refreshStackList(listFrame, countLabel, sequenceEditAndSnap)
        -- Active sequence's reset timer may have changed — re-apply the
        -- castsequence macro so the running button picks up the new value.
        if DB.activeSet == nm and NS.API and NS.API.refresh and not NS.API.inCombat() then
            NS.API.refresh()
        end
        print("|cff00ff88TTB:|r saved stack '" .. nm .. "'.")
    end)

    local clearBtn = makeButton(content, "Clear", 70, 24)
    clearBtn:SetPoint("LEFT", saveBtn, "RIGHT", 8, 0)
    clearBtn:SetScript("OnClick", function()
        nameBox:SetText("")
        for i = 1, 4 do pending[i] = nil end
        pendingIconChoice = nil
        pendingIconFileID = nil
        pendingOrder = { 1, 2, 3, 4 }
        for _, o in ipairs(orderDDs) do
            if o and o.refresh then o.refresh() end
        end
        pendingLink = nil
        pendingReset = 8
        if resetBox then resetBox:SetText("8") end
        refreshIconBtn()
        for _, dd in ipairs({ fireDD, waterDD, earthDD, airDD }) do dd.refresh() end
    end)

    -- Reset-timer description: anchored below the Save/Clear row, full
    -- content width, two lines.  Lives here (not next to the editbox)
    -- so it never overlaps the buttons or runs off the panel edge.
    do
        local d = content:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        d:SetPoint("TOPLEFT", saveBtn, "BOTTOMLEFT", 0, -6)
        d:SetWidth(440); d:SetJustifyH("LEFT")
        d:SetText("Reset timer: rolls back to step 1 if the next totem in this sequence isn't cast within this many seconds (or you change target). Default 8.")
    end

    --------------------------------------------------------------------
    -- Section 3b: Totem Stacks (per-element presets)
    --   Saves a snapshot of the four element defaults (Fire/Water/
    --   Earth/Air).  Selecting a stack overwrites the bar's element
    --   defaults all at once, via right-click / shift-click on the
    --   "Preset" button next to the totem bar.
    --------------------------------------------------------------------
    local MAX_TOTEM_STACKS = 20
    local s3b = makeSection(content, "Totem Stacks", 6, -2200)
    local s3bDesc = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    s3bDesc:SetPoint("TOPLEFT", s3b, "BOTTOMLEFT", 0, -4)
    s3bDesc:SetWidth(440); s3bDesc:SetJustifyH("LEFT")
    s3bDesc:SetText("|cffaaaaaaTotem stacks are saved per-element presets. Selecting one overwrites the four element defaults at once. Right-click or shift-click the preset button (right of the totem bar) to switch.|r")

    local s3bShowUnlearned = makeShowUnlearnedCB(s3bDesc)

    local tsNameLabel = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    tsNameLabel:SetPoint("TOPLEFT", s3bShowUnlearned, "BOTTOMLEFT", 4, -4)
    tsNameLabel:SetText("Stack name:")

    local tsNameBox = CreateFrame("EditBox", nil, content, "InputBoxTemplate")
    tsNameBox:SetSize(200, 22)
    tsNameBox:SetAutoFocus(false)
    tsNameBox:SetMaxLetters(20)
    tsNameBox:SetPoint("LEFT", tsNameLabel, "RIGHT", 12, 0)

    local tsPending = { fire = nil, water = nil, earth = nil, air = nil }
    local tsPendingIcon
    local tsRefreshIcon  -- forward
    local tsAutoIconFileID  -- forward

    local function tsMakePicker(element, totems)
        local dd = makeDynamicDropdown(content, element:upper(), 170,
            function()
                local out = { "(none)" }
                for _, n in ipairs(knownOnly(totems)) do out[#out + 1] = n end
                return out
            end,
            function() return tsPending[element] or "(none)" end,
            function(v)
                tsPending[element] = (v == "(none)") and nil or v
                if tsRefreshIcon then tsRefreshIcon() end
            end,
            true)
        return dd
    end

    local tsFireDD  = tsMakePicker("fire",  NS.TOTEMS.fire)
    local tsWaterDD = tsMakePicker("water", NS.TOTEMS.water)
    local tsEarthDD = tsMakePicker("earth", NS.TOTEMS.earth)
    local tsAirDD   = tsMakePicker("air",   NS.TOTEMS.air)
    -- 2x2 element-picker grid: Fire+Water on row 1, Earth+Air on row 2.
    tsFireDD:SetPoint("TOPLEFT",  tsNameLabel, "BOTTOMLEFT", 0, -10)
    tsWaterDD:SetPoint("TOPLEFT", tsFireDD,    "TOPRIGHT", 60,   0)
    tsEarthDD:SetPoint("TOPLEFT", tsFireDD,    "BOTTOMLEFT", 0,  -4)
    tsAirDD:SetPoint("TOPLEFT",   tsEarthDD,   "TOPRIGHT", 60,   0)
    filterableDDs[#filterableDDs + 1] = tsFireDD
    filterableDDs[#filterableDDs + 1] = tsWaterDD
    filterableDDs[#filterableDDs + 1] = tsEarthDD
    filterableDDs[#filterableDDs + 1] = tsAirDD

    -- Icon picker for the totem stack
    local tsIconLabel = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    tsIconLabel:SetText("Stack icon:")
    -- Anchored below tsEarthDD (row 2 col 1) — the 2x2 grid means
    -- tsAirDD lives in column 2, so anchoring under tsEarthDD keeps
    -- the icon picker on the left.
    tsIconLabel:SetPoint("TOPLEFT", tsEarthDD, "BOTTOMLEFT", 18, -10)

    local tsIconBtn = CreateFrame("Button", nil, content, "ActionButtonTemplate")
    tsIconBtn:SetSize(40, 40)
    tsIconBtn:SetPoint("LEFT", tsIconLabel, "RIGHT", 12, 0)
    if tsIconBtn.icon then
        tsIconBtn.icon:ClearAllPoints()
        tsIconBtn.icon:SetPoint("TOPLEFT",     tsIconBtn, "TOPLEFT",      2, -2)
        tsIconBtn.icon:SetPoint("BOTTOMRIGHT", tsIconBtn, "BOTTOMRIGHT", -2,  2)
        tsIconBtn.icon:SetTexture(134400)
        tsIconBtn.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    end

    tsAutoIconFileID = function()
        local first = tsPending.fire or tsPending.water or tsPending.earth or tsPending.air
        if first then return select(3, GetSpellInfo(first)) end
    end

    tsRefreshIcon = function()
        local fileID = tsPendingIcon or tsAutoIconFileID()
        if tsIconBtn.icon then
            tsIconBtn.icon:SetTexture(fileID or 134400)
            tsIconBtn.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        end
    end

    tsIconBtn:SetScript("OnClick", function()
        openIconPicker(function(fileID)
            tsPendingIcon = fileID
            tsRefreshIcon()
        end)
    end)

    -- Link Utility Stack — applied automatically when this totem stack
    -- is activated.  Saved in DB.linkedUtil[totemStackName].
    local tsPendingLink = nil

    local function tsUtilStackNamesPlusNone()
        local out = { "(none — don't link)" }
        local sorted = {}
        for n in pairs(DB.utilStacks or {}) do sorted[#sorted + 1] = n end
        table.sort(sorted)
        for _, n in ipairs(sorted) do out[#out + 1] = n end
        return out
    end

    local tsLinkDD = makeDynamicDropdown(content,
        "", 220,
        tsUtilStackNamesPlusNone,
        function() return tsPendingLink or "(none — don't link)" end,
        function(v) tsPendingLink = (v == "(none — don't link)") and nil or v end)
    refreshLinkDropdown = function()
        if tsLinkDD and tsLinkDD.refresh then tsLinkDD.refresh() end
    end

    -- Save / Clear
    local tsSaveBtn = makeButton(content, "Save Stack", 110, 24)
    tsSaveBtn:SetPoint("TOPLEFT", tsIconLabel, "BOTTOMLEFT", 0, -16)

    local tsClearBtn = makeButton(content, "Clear", 70, 24)
    tsClearBtn:SetPoint("LEFT", tsSaveBtn, "RIGHT", 8, 0)

    -- Anchor "Pair with Utility stack" BELOW Save/Clear so it doesn't
    -- overlap the AIR dropdown row above.  Title on top, description
    -- below it, dropdown at the bottom — same layout as the symmetric
    -- "Pair with Totem stack" in the Utility Stacks section.
    tsLinkDD:SetPoint("TOPLEFT", tsSaveBtn, "BOTTOMLEFT", 0, -28)
    do
        local desc = content:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        desc:SetPoint("BOTTOMLEFT", tsLinkDD, "TOPLEFT", 18, 2)
        desc:SetWidth(360); desc:SetJustifyH("LEFT")
        desc:SetText("When loading totem stack, paired utility stack loads as well.")
        local title = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        title:SetPoint("BOTTOMLEFT", desc, "TOPLEFT", 0, 4)
        title:SetText("Pair with Utility stack")
    end

    -- Saved totem stacks list — anchored to its own section further down
    -- (see "Saved Totem Stacks" section).
    local tsCountLabel = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    -- Created later in the "Saved Totem Stacks" section so it can live
    -- inside a scrollable window.  Rows below parent to this frame.
    local tsListFrame
    local tsListScroll

    local tsRows = {}

    local function tsEditStack(name)
        local stk = DB.totemStacks and DB.totemStacks[name]
        if not stk then return end
        tsNameBox:SetText(name)
        tsPending.fire  = stk.fire
        tsPending.water = stk.water
        tsPending.earth = stk.earth
        tsPending.air   = stk.air
        tsPendingIcon = DB.totemStackIcons and DB.totemStackIcons[name] or nil
        tsPendingLink = DB.linkedUtil and DB.linkedUtil[name] or nil
        tsRefreshIcon()
        if tsLinkDD and tsLinkDD.refresh then tsLinkDD.refresh() end
        for _, dd in ipairs({ tsFireDD, tsWaterDD, tsEarthDD, tsAirDD }) do
            if dd.refresh then dd.refresh() end
        end
    end

    local function refreshTotemStackList()
        local names = {}
        for n in pairs(DB.totemStacks or {}) do names[#names + 1] = n end
        table.sort(names)
        tsCountLabel:SetText(string.format("Saved totem stacks (%d / %d)", #names, MAX_TOTEM_STACKS))
        for _, r in ipairs(tsRows) do r:Hide() end
        for i, name in ipairs(names) do
            local row = tsRows[i]
            if not row then
                row = CreateFrame("Frame", nil, tsListFrame)
                row:SetSize(810, 20)
                row.name = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                row.name:SetPoint("LEFT", 0, 0)
                row.name:SetWidth(154); row.name:SetHeight(20)
                row.name:SetJustifyH("LEFT"); row.name:SetJustifyV("MIDDLE")
                row.name:SetWordWrap(false); row.name:SetMaxLines(1)
                row.detail = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                row.detail:SetPoint("LEFT", row.name, "RIGHT", 4, 0)
                row.detail:SetWidth(405); row.detail:SetHeight(20)
                row.detail:SetJustifyH("LEFT"); row.detail:SetJustifyV("MIDDLE")
                row.detail:SetWordWrap(false); row.detail:SetMaxLines(1)
                row.paired = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                row.paired:SetPoint("LEFT", row.detail, "RIGHT", 4, 0)
                row.paired:SetWidth(154); row.paired:SetHeight(20)
                row.paired:SetJustifyH("LEFT"); row.paired:SetJustifyV("MIDDLE")
                row.paired:SetWordWrap(false); row.paired:SetMaxLines(1)
                row.editBtn = makeButton(row, "Edit", 42, 20)
                row.editBtn:SetPoint("RIGHT", -47, 0)
                row.delBtn = makeButton(row, "Del", 42, 20)
                row.delBtn:SetPoint("RIGHT", 0, 0)
                tsRows[i] = row
            end
            row:Show()
            row:SetPoint("TOPLEFT", tsListFrame, "TOPLEFT", 0, -((i - 1) * 22))
            local prefix = (DB.activeTotemStack == name) and "|cff00ff88* |r" or "  "
            row.name:SetText(prefix .. name)
            local stk = DB.totemStacks[name] or {}
            local parts = {}
            for _, el in ipairs(NS.ELEMENT_ORDER) do
                if stk[el] then
                    local s = stk[el]:gsub(" Totem", "")
                    parts[#parts + 1] = (NS.TOTEM_SHORT and NS.TOTEM_SHORT[s]) or s
                end
            end
            row.detail:SetText(table.concat(parts, ", "))
            -- Paired utility-stack name (or em-dash if none)
            local pairedUtil = DB.linkedUtil and DB.linkedUtil[name]
            if pairedUtil and pairedUtil ~= "" then
                row.paired:SetText("|cff7ec8ff" .. pairedUtil .. "|r")
            else
                row.paired:SetText("|cff888888—|r")
            end
            row.editBtn:SetScript("OnClick", function()
                tsEditStack(name)
                snapToSection(-2200)  -- s3b (Totem Stacks editor)
            end)
            row.delBtn:SetScript("OnClick", function()
                DB.totemStacks[name] = nil
                if DB.totemStackIcons then DB.totemStackIcons[name] = nil end
                if DB.activeTotemStack == name then DB.activeTotemStack = nil end
                if DB.linkedUtil then DB.linkedUtil[name] = nil end
                if DB.linkedTotem then
                    for uname, tname in pairs(DB.linkedTotem) do
                        if tname == name then DB.linkedTotem[uname] = nil end
                    end
                end
                refreshTotemStackList()
                if refreshTotemLinkDropdown then refreshTotemLinkDropdown() end
                -- Cleared linkedTotem entries that pointed here → the
                -- utility list's Paired column needs to repaint.
                if refreshUtilStackList then refreshUtilStackList() end
            end)
        end
    end

    tsSaveBtn:SetScript("OnClick", function()
        local nm = tsNameBox:GetText():match("^%s*(.-)%s*$")
        if not nm or nm == "" then
            print("|cffff5555TTB:|r enter a stack name first."); return
        end
        local count = 0
        for _ in pairs(DB.totemStacks) do count = count + 1 end
        if not DB.totemStacks[nm] and count >= MAX_TOTEM_STACKS then
            print(string.format("|cffff5555TTB:|r max %d totem stacks.", MAX_TOTEM_STACKS))
            return
        end
        if not (tsPending.fire or tsPending.water or tsPending.earth or tsPending.air) then
            print("|cffff5555TTB:|r pick at least one totem."); return
        end
        DB.totemStacks[nm] = {
            fire = tsPending.fire, water = tsPending.water,
            earth = tsPending.earth, air = tsPending.air,
        }
        DB.totemStackIcons = DB.totemStackIcons or {}
        DB.totemStackIcons[nm] = tsPendingIcon or tsAutoIconFileID()
        DB.linkedUtil  = DB.linkedUtil  or {}
        DB.linkedTotem = DB.linkedTotem or {}
        -- Bidirectional pairing.  Setting linkedUtil[T] = U also writes
        -- linkedTotem[U] = T, and clears any stale reverse pointers so
        -- a one-to-one relationship stays consistent.
        local oldUtil = DB.linkedUtil[nm]
        if oldUtil and oldUtil ~= tsPendingLink then
            -- This totem stack used to point at a different util — drop
            -- the reverse pointer there so we don't leave it dangling.
            if DB.linkedTotem[oldUtil] == nm then
                DB.linkedTotem[oldUtil] = nil
            end
        end
        DB.linkedUtil[nm] = tsPendingLink  -- nil if "none" selected
        if tsPendingLink then
            -- If the chosen util stack was already paired with another
            -- totem stack, break that link first.
            local prevTotem = DB.linkedTotem[tsPendingLink]
            if prevTotem and prevTotem ~= nm then
                DB.linkedUtil[prevTotem] = nil
            end
            DB.linkedTotem[tsPendingLink] = nm
        end
        tsNameBox:SetText("")
        tsPending = { fire = nil, water = nil, earth = nil, air = nil }
        tsPendingIcon = nil
        tsPendingLink = nil
        tsRefreshIcon()
        if tsLinkDD and tsLinkDD.refresh then tsLinkDD.refresh() end
        if refreshTotemLinkDropdown then refreshTotemLinkDropdown() end
        for _, dd in ipairs({ tsFireDD, tsWaterDD, tsEarthDD, tsAirDD }) do
            if dd.refresh then dd.refresh() end
        end
        refreshTotemStackList()
        -- Mirror the pairing change in the utility list's Paired column.
        if refreshUtilStackList then refreshUtilStackList() end
        print("|cff00ff88TTB:|r saved totem stack '" .. nm .. "'.")
    end)

    tsClearBtn:SetScript("OnClick", function()
        tsNameBox:SetText("")
        tsPending = { fire = nil, water = nil, earth = nil, air = nil }
        tsPendingIcon = nil
        tsPendingLink = nil
        tsRefreshIcon()
        if tsLinkDD and tsLinkDD.refresh then tsLinkDD.refresh() end
        for _, dd in ipairs({ tsFireDD, tsWaterDD, tsEarthDD, tsAirDD }) do
            if dd.refresh then dd.refresh() end
        end
    end)

    --------------------------------------------------------------------
    -- Section 4: Utility Stacks (below Custom Stacks)
    --   Same pattern as Custom Stacks, but with two slot dropdowns
    --   instead of four element dropdowns.
    --------------------------------------------------------------------
    local s4 = makeSection(content, "Utility Stacks", 6, -2700)

    -- Section description
    local s4Desc = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    s4Desc:SetPoint("TOPLEFT", s4, "BOTTOMLEFT", 0, -4)
    s4Desc:SetWidth(440); s4Desc:SetJustifyH("LEFT")
    s4Desc:SetText("|cffaaaaaaUtility stacks are customizable pre-loaded utility setups. Choose which 2 to save as a stack, then one button loads them into your utility slots.|r")

    local s4ShowUnlearned = makeShowUnlearnedCB(s4Desc)

    local uNameLabel = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    uNameLabel:SetPoint("TOPLEFT", s4ShowUnlearned, "BOTTOMLEFT", 4, -4)
    uNameLabel:SetText("Stack name:")

    local uNameBox = CreateFrame("EditBox", nil, content, "InputBoxTemplate")
    uNameBox:SetSize(200, 22)
    uNameBox:SetAutoFocus(false)
    uNameBox:SetMaxLetters(20)
    uNameBox:SetPoint("LEFT", uNameLabel, "RIGHT", 12, 0)

    local uPending1, uPending2

    local function knownEnabledUtils()
        -- "Show Unlearned Spells" → list all utilities regardless of state
        if showUnlearned then
            local out = {}
            for _, n in ipairs(NS.UTILITY_OPTIONS) do out[#out + 1] = n end
            return out
        end
        local out = {}
        for _, n in ipairs(NS.UTILITY_OPTIONS) do
            local _, _, _, _, _, _, sid = GetSpellInfo(n)
            if sid and IsPlayerSpell and IsPlayerSpell(sid) then
                out[#out + 1] = n
            elseif GetSpellBookItemInfo and GetSpellBookItemInfo(n) then
                out[#out + 1] = n
            end
        end
        return out
    end

    local uSlot1DD = makeDynamicDropdown(content, "Slot 1", 170,
        knownEnabledUtils,
        function() return uPending1 end,
        function(v) uPending1 = v end,
        true)
    uSlot1DD:SetPoint("TOPLEFT", uNameLabel, "BOTTOMLEFT", 0, -8)

    local uSlot2DD = makeDynamicDropdown(content, "Slot 2", 170,
        knownEnabledUtils,
        function() return uPending2 end,
        function(v) uPending2 = v end,
        true)
    uSlot2DD:SetPoint("TOPLEFT", uSlot1DD, "TOPRIGHT", 18, 0)
    filterableDDs[#filterableDDs + 1] = uSlot1DD
    filterableDDs[#filterableDDs + 1] = uSlot2DD

    -- "Pair with Totem stack" — vice-versa of the totem-stack side.
    -- When the user activates this utility stack, the linked totem stack
    -- is auto-applied as well.  Saved in DB.linkedTotem[utilStackName].
    local usPendingLink = nil

    local function totemStackNamesPlusNone()
        local out = { "(none — don't link)" }
        local sorted = {}
        for n in pairs(DB.totemStacks or {}) do sorted[#sorted + 1] = n end
        table.sort(sorted)
        for _, n in ipairs(sorted) do out[#out + 1] = n end
        return out
    end

    local usLinkDD = makeDynamicDropdown(content, "", 220,
        totemStackNamesPlusNone,
        function() return usPendingLink or "(none — don't link)" end,
        function(v) usPendingLink = (v == "(none — don't link)") and nil or v end)
    -- Anchor below the Slot 1 / Slot 2 row so it stays inside the panel
    -- (three dropdowns side-by-side overflows the 470 px content width).
    -- Anchor BELOW where Save/Clear will sit (uSaveBtn is created
    -- further down, at uSlot1DD BOTTOMLEFT 18,-8; with a 24-px-tall
    -- button + gap = -60 keeps Pair-with-Totem clear of the buttons).
    usLinkDD:SetPoint("TOPLEFT", uSlot1DD, "BOTTOMLEFT", 0, -60)
    do
        local desc = content:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        desc:SetPoint("BOTTOMLEFT", usLinkDD, "TOPLEFT", 18, 2)
        desc:SetWidth(360); desc:SetJustifyH("LEFT")
        desc:SetText("When loading utility stack, paired totem stack loads as well.")
        local title = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        title:SetPoint("BOTTOMLEFT", desc, "TOPLEFT", 0, 4)
        title:SetText("Pair with Totem stack")
    end
    refreshTotemLinkDropdown = function()
        if usLinkDD and usLinkDD.refresh then usLinkDD.refresh() end
    end

    -- (Saved util-stacks list is built further down in its own section.)
    local uListFrame  -- forward-declared; populated below
    local uCountLabel -- forward-declared; populated below

    local uRows = {}

    local function editUtilStack(name)
        local stk = DB.utilStacks and DB.utilStacks[name]
        if not stk then return end
        uNameBox:SetText(name)
        uPending1 = stk[1]
        uPending2 = stk[2]
        usPendingLink = DB.linkedTotem and DB.linkedTotem[name] or nil
        uSlot1DD.refresh(); uSlot2DD.refresh()
        if usLinkDD and usLinkDD.refresh then usLinkDD.refresh() end
    end

    local function refreshUtilStackList()
        local names = {}
        for n in pairs(DB.utilStacks or {}) do names[#names + 1] = n end
        table.sort(names)
        uCountLabel:SetText(string.format("Saved utility stacks (%d / %d)", #names, MAX_UTIL_STACKS))
        for _, r in ipairs(uRows) do r:Hide() end
        for i, name in ipairs(names) do
            local row = uRows[i]
            if not row then
                row = CreateFrame("Frame", nil, uListFrame)
                row:SetSize(810, 20)
                row.name = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                row.name:SetPoint("LEFT", 0, 0)
                row.name:SetWidth(154); row.name:SetHeight(20)
                row.name:SetJustifyH("LEFT"); row.name:SetJustifyV("MIDDLE")
                row.name:SetWordWrap(false); row.name:SetMaxLines(1)
                row.detail = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                row.detail:SetPoint("LEFT", row.name, "RIGHT", 4, 0)
                row.detail:SetWidth(405); row.detail:SetHeight(20)
                row.detail:SetJustifyH("LEFT"); row.detail:SetJustifyV("MIDDLE")
                row.detail:SetWordWrap(false); row.detail:SetMaxLines(1)
                row.paired = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                row.paired:SetPoint("LEFT", row.detail, "RIGHT", 4, 0)
                row.paired:SetWidth(154); row.paired:SetHeight(20)
                row.paired:SetJustifyH("LEFT"); row.paired:SetJustifyV("MIDDLE")
                row.paired:SetWordWrap(false); row.paired:SetMaxLines(1)
                row.editBtn = makeButton(row, "Edit", 42, 20)
                row.editBtn:SetPoint("RIGHT", -47, 0)
                row.delBtn = makeButton(row, "Del", 42, 20)
                row.delBtn:SetPoint("RIGHT", 0, 0)
                uRows[i] = row
            end
            row:Show()
            row:SetPoint("TOPLEFT", uListFrame, "TOPLEFT", 0, -((i - 1) * 22))
            row.name:SetText(name)
            local stk = DB.utilStacks[name] or {}
            row.detail:SetText((stk[1] or "(none)") .. "  +  " .. (stk[2] or "(none)"))
            -- Paired totem-stack name (or em-dash if none)
            local pairedTotem = DB.linkedTotem and DB.linkedTotem[name]
            if pairedTotem and pairedTotem ~= "" then
                row.paired:SetText("|cff7ec8ff" .. pairedTotem .. "|r")
            else
                row.paired:SetText("|cff888888—|r")
            end
            row.editBtn:SetScript("OnClick", function()
                editUtilStack(name)
                snapToSection(-2700)  -- s4 (Utility Stacks editor)
            end)
            row.delBtn:SetScript("OnClick", function()
                DB.utilStacks[name] = nil
                if DB.linkedUtil then
                    for tname, uname in pairs(DB.linkedUtil) do
                        if uname == name then DB.linkedUtil[tname] = nil end
                    end
                end
                if DB.linkedTotem then DB.linkedTotem[name] = nil end
                refreshUtilStackList()
                if refreshLinkDropdown then refreshLinkDropdown() end
                -- Cleared linkedUtil entries that pointed here → the
                -- totem-stacks list's Paired column needs to repaint.
                if refreshTotemStackList then refreshTotemStackList() end
            end)
        end
    end

    local uSaveBtn = makeButton(content, "Save Util Stack", 130, 24)
    uSaveBtn:SetPoint("TOPLEFT", uSlot1DD, "BOTTOMLEFT", 18, -8)
    uSaveBtn:SetScript("OnClick", function()
        local nm = uNameBox:GetText():match("^%s*(.-)%s*$")
        if not nm or nm == "" then
            print("|cffff5555TTB:|r enter a name first."); return
        end
        local count = 0
        for _ in pairs(DB.utilStacks) do count = count + 1 end
        if not DB.utilStacks[nm] and count >= MAX_UTIL_STACKS then
            print(string.format("|cffff5555TTB:|r max %d util stacks. Delete one first.", MAX_UTIL_STACKS))
            return
        end
        if not uPending1 and not uPending2 then
            print("|cffff5555TTB:|r pick at least one slot."); return
        end
        DB.utilStacks[nm] = { uPending1, uPending2 }
        DB.linkedTotem = DB.linkedTotem or {}
        DB.linkedUtil  = DB.linkedUtil  or {}
        -- Bidirectional pairing.  Setting linkedTotem[U] = T also
        -- writes linkedUtil[T] = U and clears any stale reverse
        -- pointers so the relationship stays one-to-one.
        local oldTotem = DB.linkedTotem[nm]
        if oldTotem and oldTotem ~= usPendingLink then
            if DB.linkedUtil[oldTotem] == nm then
                DB.linkedUtil[oldTotem] = nil
            end
        end
        DB.linkedTotem[nm] = usPendingLink
        if usPendingLink then
            local prevUtil = DB.linkedUtil[usPendingLink]
            if prevUtil and prevUtil ~= nm then
                DB.linkedTotem[prevUtil] = nil
            end
            DB.linkedUtil[usPendingLink] = nm
        end
        uNameBox:SetText("")
        uPending1, uPending2 = nil, nil
        usPendingLink = nil
        uSlot1DD.refresh(); uSlot2DD.refresh()
        if usLinkDD and usLinkDD.refresh then usLinkDD.refresh() end
        refreshUtilStackList()
        if refreshLinkDropdown then refreshLinkDropdown() end
        -- Mirror the pairing in the totem-stacks list's Paired column.
        if refreshTotemStackList then refreshTotemStackList() end
        print("|cff00ff88TTB:|r saved util stack '" .. nm .. "'.")
    end)

    local uClearBtn = makeButton(content, "Clear", 70, 24)
    uClearBtn:SetPoint("LEFT", uSaveBtn, "RIGHT", 8, 0)
    uClearBtn:SetScript("OnClick", function()
        uNameBox:SetText("")
        uPending1, uPending2 = nil, nil
        usPendingLink = nil
        uSlot1DD.refresh(); uSlot2DD.refresh()
        if usLinkDD and usLinkDD.refresh then usLinkDD.refresh() end
    end)

    --------------------------------------------------------------------
    -- Section 5: Saved Stacks (totem stacks list)
    --------------------------------------------------------------------
    local s5 = makeSection(content, "Saved Sequence", 6, -3000)
    countLabel = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    countLabel:SetPoint("TOPLEFT", s5, "BOTTOMLEFT", 0, -4)
    -- Scroll window: 5 rows visible, up to MAX_STACKS rows inside.
    local s5_scroll, s5_inner = makeListScroll(content, 842, 5, MAX_STACKS)
    s5_scroll:SetPoint("TOPLEFT", countLabel, "BOTTOMLEFT", 0, -22)  -- room for column headers above
    listFrame = s5_inner
    -- Column headers, 5 px above the scroll frame's gold border.
    -- Column X offsets mirror the row layout inside the inner content
    -- (4-px scroll inset + name(160) / detail(240) / paired(200)).
    do
        local h1 = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        h1:SetPoint("BOTTOMLEFT", s5_scroll, "TOPLEFT", 4,   5)
        h1:SetText("|cffffd200Name|r")
        local h2 = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        h2:SetPoint("BOTTOMLEFT", s5_scroll, "TOPLEFT", 162, 5)
        h2:SetText("|cffffd200Totem|r")
        local h3 = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        h3:SetPoint("BOTTOMLEFT", s5_scroll, "TOPLEFT", 571, 5)
        h3:SetText("|cffffd200Paired with|r")
    end

    --------------------------------------------------------------------
    -- Section 5b: Saved Totem Stacks
    --------------------------------------------------------------------
    local s5b = makeSection(content, "Saved Totem Stacks", 6, -3180)
    tsCountLabel:SetPoint("TOPLEFT", s5b, "BOTTOMLEFT", 0, -4)
    tsListScroll, tsListFrame = makeListScroll(content, 842, 5, MAX_TOTEM_STACKS)
    tsListScroll:SetPoint("TOPLEFT", tsCountLabel, "BOTTOMLEFT", 0, -22)
    do
        local h1 = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        h1:SetPoint("BOTTOMLEFT", tsListScroll, "TOPLEFT", 4,   5)
        h1:SetText("|cffffd200Name|r")
        local h2 = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        h2:SetPoint("BOTTOMLEFT", tsListScroll, "TOPLEFT", 162, 5)
        h2:SetText("|cffffd200Totem|r")
        local h3 = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        h3:SetPoint("BOTTOMLEFT", tsListScroll, "TOPLEFT", 571, 5)
        h3:SetText("|cffffd200Paired with|r")
    end

    --------------------------------------------------------------------
    -- Section 6: Saved Utility Stacks
    --------------------------------------------------------------------
    local s6 = makeSection(content, "Saved Utility Stacks", 6, -3360)
    uCountLabel = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    uCountLabel:SetPoint("TOPLEFT", s6, "BOTTOMLEFT", 0, -4)
    local uListScroll
    uListScroll, uListFrame = makeListScroll(content, 842, 5, MAX_UTIL_STACKS)
    uListScroll:SetPoint("TOPLEFT", uCountLabel, "BOTTOMLEFT", 0, -22)
    do
        local h1 = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        h1:SetPoint("BOTTOMLEFT", uListScroll, "TOPLEFT", 4,   5)
        h1:SetText("|cffffd200Name|r")
        local h2 = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        h2:SetPoint("BOTTOMLEFT", uListScroll, "TOPLEFT", 162, 5)
        h2:SetText("|cffffd200Spell|r")
        local h3 = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        h3:SetPoint("BOTTOMLEFT", uListScroll, "TOPLEFT", 571, 5)
        h3:SetText("|cffffd200Paired with|r")
    end

    --------------------------------------------------------------------
    -- OnShow: refresh everything
    --------------------------------------------------------------------
    -- Bundle every widget that needs OnShow refresh into tables so the
    -- Panel:OnShow closure only captures a couple of upvalues
    -- (Lua's hard cap is 60 per function).
    local onShowCBs = {
        lock, alerts, hideUnlearned,
        cbTotems, cbUtility, cbImbue,
        showT, showU, showI, showSq, showTS,
        scale, totemScaleS, imbueScale, utilScaleS,
        cbHigher, cbLower,
        mhAlertCB, ohAlertCB, lsAlertCB,
        u1AlertCB, u2AlertCB,
        tFireCB, tWaterCB, tEarthCB, tAirCB,
        situationalCB,
        imbueMoveCB, imbueAudioCB, imbueFlashCB, imbueWarnCB, imbueDurCB, imbueCDCB,
        utilMoveCB,  utilAudioCB,  utilFlashCB,  utilWarnCB,  utilDurCB,  utilCDCB,
        totemMoveCB, totemAudioCB, totemFlashCB, totemWarnCB, totemDurCB, totemCDCB,
    }
    local onShowDDs = {
        totemLayoutDD, utilLayoutDD, imbueLayoutDD, combinedLayoutDD,
        imbueMoveDD, imbueAudioDD, imbueFlashDD,
        utilMoveDD,  utilAudioDD,  utilFlashDD,
        totemMoveDD, totemAudioDD, totemFlashDD,
        fireDD, waterDD, earthDD, airDD,
        uSlot1DD, uSlot2DD,
        tsFireDD, tsWaterDD, tsEarthDD, tsAirDD,
        tsLinkDD,
    }

    Panel:SetScript("OnShow", function()
        for _, cb in ipairs(onShowCBs) do
            local f = cb:GetScript("OnShow")
            if f then f(cb) end
        end
        -- All three "Show Unlearned Spells" checkboxes share state via
        -- the `showUnlearned` upvalue; sync their visual checkmark.
        for _, cb in ipairs(showUnlearnedCBs) do
            local f = cb:GetScript("OnShow")
            if f then f(cb) end
        end
        for _, dd in ipairs(onShowDDs) do
            if dd and dd.refresh then dd.refresh() end
        end
        refreshUtilStackList()
        refreshStackList(listFrame, countLabel, sequenceEditAndSnap)
        refreshTotemStackList()
    end)
end

------------------------------------------------------------------------
-- Open / toggle
------------------------------------------------------------------------
local function openOptions()
    if not ensureDB() then
        print("|cffff5555TTB:|r addon not initialized yet.")
        return
    end
    if not Panel then buildPanel() end
    if Panel:IsShown() then Panel:Hide() else Panel:Show() end
end

------------------------------------------------------------------------
-- Register a stub in Interface > AddOns so the panel is discoverable
------------------------------------------------------------------------
local function registerInterfaceOptionsStub()
    local host = CreateFrame("Frame")
    host.name = "Totem Tommys Bars"

    local title = host:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("Totem Tommys Bars")

    local desc = host:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    desc:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    desc:SetWidth(540); desc:SetJustifyH("LEFT")
    desc:SetText("Movable shaman bar — totems, custom stacks, Lightning Shield, "
        .. "utilities, and a separate imbue mini-bar.\n\n"
        .. "Click below (or type |cffaaccff/ttb|r) to open the configuration window.")

    local btn = CreateFrame("Button", nil, host, "UIPanelButtonTemplate")
    btn:SetSize(220, 28)
    btn:SetText("Open Totem Tommys Bars Options")
    btn:SetPoint("TOPLEFT", desc, "BOTTOMLEFT", 0, -16)
    btn:SetScript("OnClick", function() openOptions() end)

    -- Modern API (Dragonflight+/Era 1.15)
    if Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory then
        local category = Settings.RegisterCanvasLayoutCategory(host, host.name)
        category.ID = host.name
        Settings.RegisterAddOnCategory(category)
    -- Legacy API
    elseif InterfaceOptions_AddCategory then
        InterfaceOptions_AddCategory(host)
    end
end

------------------------------------------------------------------------
-- Wire into NS.API after PLAYER_LOGIN
------------------------------------------------------------------------
local hookFrame = CreateFrame("Frame")
hookFrame:RegisterEvent("PLAYER_LOGIN")
hookFrame:SetScript("OnEvent", function()
    if NS.API then
        NS.API.openOptions = openOptions
    end
    registerInterfaceOptionsStub()
end)
