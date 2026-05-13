-- Core.lua — Totem Tommys Bars
-- Movable bar of secure buttons for Classic Era shaman: 4 totem elements,
-- a stack button (castsequence), Totemic Recall, MH/OH imbues, Lightning
-- Shield, utility slot.  Right-click any button to open its dropdown.

local addonName, NS = ...

local BUTTON_SIZE = 36
local PADDING     = 4
local BAR_PAD     = 6

------------------------------------------------------------------------
-- Keybinding actions (registered at runtime via SetBindingClick).
-- Each entry: { id, label, button = global frame name }
-- The options panel's Keybindings section lets the user assign a key per
-- action; the assignment is applied via SetBindingClick on PLAYER_LOGIN.
------------------------------------------------------------------------
NS.BINDING_ACTIONS = {
    { id = "totem_fire",   label = "Drop Fire totem  (Shift: cycle)",        button = "TotemTommysBars_Totem_fire" },
    { id = "totem_water",  label = "Drop Water totem  (Shift: cycle)",       button = "TotemTommysBars_Totem_water" },
    { id = "totem_earth",  label = "Drop Earth totem  (Shift: cycle)",       button = "TotemTommysBars_Totem_earth" },
    { id = "totem_air",    label = "Drop Air totem  (Shift: cycle)",         button = "TotemTommysBars_Totem_air" },
    { id = "stack",        label = "Stack: drop next  (Shift: cycle stack)", button = "TotemTommysBars_Stack" },
    { id = "ls",           label = "Cast Lightning Shield",                  button = "TotemTommysBars_LS" },
    { id = "mh",           label = "MH imbue  (Shift: secondary)",           button = "TotemTommysBars_MH" },
    { id = "oh",           label = "OH imbue  (Shift: secondary)",           button = "TotemTommysBars_OH" },
    { id = "util_1",       label = "Utility slot 1  (Shift: cycle)",         button = "TotemTommysBars_Util_1" },
    { id = "util_2",       label = "Utility slot 2  (Shift: cycle)",         button = "TotemTommysBars_Util_2" },
}

------------------------------------------------------------------------
-- SavedVars
------------------------------------------------------------------------
local DB

local function deepcopy(t)
    if type(t) ~= "table" then return t end
    local out = {}
    for k, v in pairs(t) do out[k] = deepcopy(v) end
    return out
end

local function initDB()
    -- Rebrand migration: addon was previously "Shears Shaman Bar" with
    -- SV global ShearsShamanBarDB.  If the new TotemTommysBarsDB doesn't
    -- exist yet but the old one does, copy it over (one-time).  Both
    -- SVs are declared in the .toc so this runs safely after load.
    if not TotemTommysBarsDB and ShearsShamanBarDB then
        TotemTommysBarsDB = ShearsShamanBarDB
        ShearsShamanBarDB = nil  -- let the old SV expire on next save
    end
    if not TotemTommysBarsDB then TotemTommysBarsDB = {} end
    DB = TotemTommysBarsDB
    for k, v in pairs(NS.DEFAULTS) do
        if DB[k] == nil then DB[k] = deepcopy(v) end
    end
    if not DB.sets then DB.sets = deepcopy(NS.DEFAULT_SETS) end

    -- Legacy migrations -----------------------------------------------
    -- Old single "Combine totems and utility" checkbox: when true it
    -- meant totem + util shared a bar (no imbue combined).
    if DB.combinedBars ~= nil then
        if DB.combinedBars == true then
            DB.combineTotems  = true
            DB.combineUtility = true
        else
            DB.combineTotems  = false
            DB.combineUtility = false
        end
        DB.combinedBars = nil
    end
    -- Old single "layout" applied to the master bar — copy into totemLayout
    if DB.layout and not DB.totemLayout then
        DB.totemLayout = DB.layout
    end
end

------------------------------------------------------------------------
-- Helpers
------------------------------------------------------------------------
local function isShaman()
    local _, class = UnitClass("player")
    return class == "SHAMAN"
end

local function knowsSpell(name)
    if not name then return false end
    return GetSpellInfo(name) ~= nil and IsPlayerSpell and true or (GetSpellBookItemInfo and true) or true
end

local function spellIcon(name)
    if not name then return 134400 end
    local _, _, icon = GetSpellInfo(name)
    return icon or 134400
end

local function isKnown(name)
    if not name or name == "" then return false end
    local info = GetSpellInfo(name)
    if not info then return false end
    -- GetSpellInfo by name returns spellID at position 7 in Classic Era
    local _, _, _, _, _, _, spellID = GetSpellInfo(name)
    if spellID and IsPlayerSpell and IsPlayerSpell(spellID) then return true end
    -- Fallback: spellbook scan
    if GetSpellBookItemInfo then
        local _, id = GetSpellBookItemInfo(name)
        if id then return true end
    end
    return false
end

local function knownOnly(list)
    local out = {}
    for _, name in ipairs(list) do
        if isKnown(name) then out[#out + 1] = name end
    end
    return out
end

local function inCombat()
    return InCombatLockdown() or UnitAffectingCombat("player")
end

------------------------------------------------------------------------
-- Main frame
------------------------------------------------------------------------
local Bar = CreateFrame("Frame", "TotemTommysBars", UIParent, "BackdropTemplate")
Bar:SetMovable(true)
Bar:SetClampedToScreen(true)
Bar:EnableMouse(true)
Bar:RegisterForDrag("LeftButton")
Bar:SetScript("OnDragStart", function(self)
    if not DB.locked then self:StartMoving() end
end)
Bar:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local p, _, rp, x, y = self:GetPoint(1)
    DB.point = { p, "UIParent", rp, x, y }
end)
if Bar.SetBackdrop then
    Bar:SetBackdrop({
        bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    Bar:SetBackdropColor(0.05, 0.05, 0.07, 0.6)
    Bar:SetBackdropBorderColor(0.85, 0.7, 0.2, 1)  -- gold
end

local Title = Bar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
Title:SetPoint("TOPLEFT", Bar, "TOPLEFT", 6, -3)
Title:SetText("|cffffd200Totem Tommys Bars|r")
Title:Hide()

-- Separate, independently-movable Imbue bar (MH + OH only)
local ImbueBar = CreateFrame("Frame", "ShearsShamanImbueBar", UIParent, "BackdropTemplate")
ImbueBar:SetMovable(true)
ImbueBar:SetClampedToScreen(true)
ImbueBar:EnableMouse(true)
ImbueBar:RegisterForDrag("LeftButton")
ImbueBar:SetScript("OnDragStart", function(self)
    if not DB.locked then self:StartMoving() end
end)
ImbueBar:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local p, _, rp, x, y = self:GetPoint(1)
    DB.imbuePoint = { p, "UIParent", rp, x, y }
end)
if ImbueBar.SetBackdrop then
    ImbueBar:SetBackdrop({
        bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
end
local ImbueTitle = ImbueBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
ImbueTitle:SetPoint("TOPLEFT", ImbueBar, "TOPLEFT", 6, -3)
ImbueTitle:SetText("|cffffd200Imbues|r")
ImbueTitle:Hide()

-- Optional standalone Util bar (only used when DB.combinedBars = false).
-- Layout-managed in the same place as the imbue bar.
local UtilBar = CreateFrame("Frame", "ShearsShamanUtilBar", UIParent, "BackdropTemplate")
UtilBar:SetMovable(true)
UtilBar:SetClampedToScreen(true)
UtilBar:EnableMouse(true)
UtilBar:RegisterForDrag("LeftButton")
UtilBar:SetScript("OnDragStart", function(self)
    if not DB.locked then self:StartMoving() end
end)
UtilBar:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local p, _, rp, x, y = self:GetPoint(1)
    DB.utilPoint = { p, "UIParent", rp, x, y }
end)
if UtilBar.SetBackdrop then
    UtilBar:SetBackdrop({
        bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
end
local UtilTitle = UtilBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
UtilTitle:SetPoint("TOPLEFT", UtilBar, "TOPLEFT", 6, -3)
UtilTitle:SetText("|cffffd200Utility|r")
UtilTitle:Hide()

-- StackBar — holds only the Stack button.  Always anchored adjacent to
-- whichever frame currently contains the totem buttons, with its own gold
-- border so it visually stands apart from the elements.
local StackBar = CreateFrame("Frame", "ShearsShamanStackBar", UIParent, "BackdropTemplate")
StackBar:EnableMouse(false)
if StackBar.SetBackdrop then
    StackBar:SetBackdrop({
        bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
end
local StackTitle = StackBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
StackTitle:SetText("|cffffd200Stack|r")
StackTitle:Hide()

-- TotemStackBar — single-button frame for the saved "Totem Stack" switcher.
-- Sits to the RIGHT of the totem element frame, mirroring StackBar's left
-- placement.  Its button switches the four element defaults to a saved
-- preset (right-click menu / shift-click cycle).
local TotemStackBar = CreateFrame("Frame", "ShearsShamanTotemStackBar", UIParent, "BackdropTemplate")
TotemStackBar:EnableMouse(false)
if TotemStackBar.SetBackdrop then
    TotemStackBar:SetBackdrop({
        bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
end
local TotemStackTitle = TotemStackBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
TotemStackTitle:SetText("|cffffd200Preset|r")
TotemStackTitle:Hide()

-- RecallBar — single-button movable frame that, when clicked, calls
-- DestroyTotem on all four slots.  Classic Era doesn't have the WotLK+
-- "Totemic Recall" spell, but DestroyTotem(slot) is exposed by the
-- game's API and silently removes a totem with no cost / GCD / cast.
local RecallBar = CreateFrame("Frame", "TotemTommysBarsRecallBar", UIParent, "BackdropTemplate")
RecallBar:EnableMouse(true)
RecallBar:SetMovable(true)
RecallBar:RegisterForDrag("LeftButton")
if RecallBar.SetBackdrop then
    RecallBar:SetBackdrop({
        bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
end

------------------------------------------------------------------------
-- Buttons
------------------------------------------------------------------------
-- Each button: secure action template, attribute "type"/"spell"/"macrotext"
-- updated out of combat.  Right-click handled insecurely (opens dropdown).
local Buttons = {}

local function createButton(name, parent)
    local b = CreateFrame("Button", "TotemTommysBars_" .. name, parent, "SecureActionButtonTemplate, ActionButtonTemplate")
    b:SetSize(BUTTON_SIZE, BUTTON_SIZE)
    b:RegisterForClicks("AnyDown")
    -- Don't set "type" globally; setButtonSpell/Macro use type1 so cast is
    -- left-click only (right-click stays free for our dropdown).

    -- Cooldown swipe — radial animation + Blizzard's built-in countdown
    -- numbers shown in the centre.  Fires the GCD swipe whenever a click
    -- triggers any spell.
    local cd = CreateFrame("Cooldown", nil, b, "CooldownFrameTemplate")
    cd:SetAllPoints(b)
    if cd.SetHideCountdownNumbers then cd:SetHideCountdownNumbers(false) end
    b.cooldown = cd

    -- Duration text — top-right corner, white.  Shows remaining time of
    -- whatever buff / totem / enchant is keeping the slot "active".
    b.durText = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    b.durText:SetPoint("TOPRIGHT", b, "TOPRIGHT", -2, -2)
    b.durText:SetTextColor(1, 1, 1, 1)
    b.durText:SetShadowColor(0, 0, 0, 1)
    b.durText:SetShadowOffset(1, -1)
    b.durText:SetDrawLayer("OVERLAY", 7)

    -- Cooldown text — top-left, half-size, red.  Shows the spell's own
    -- cooldown countdown (skips GCD).
    b.cdText = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    b.cdText:SetPoint("TOPLEFT", b, "TOPLEFT", 2, -2)
    b.cdText:SetTextColor(1, 0.2, 0.2, 1)
    b.cdText:SetShadowColor(0, 0, 0, 1)
    b.cdText:SetShadowOffset(1, -1)
    b.cdText:SetDrawLayer("OVERLAY", 7)

    -- Duration timer — yellow text floating above the button, centered.
    -- Shows remaining buff / totem / imbue duration when the group's
    -- "Duration Timer" option is enabled.
    b.durTimer = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    b.durTimer:SetPoint("BOTTOM", b, "TOP", 0, 5)
    b.durTimer:SetTextColor(1, 1, 0, 1)
    b.durTimer:SetShadowColor(0, 0, 0, 1)
    b.durTimer:SetShadowOffset(1, -1)
    b.durTimer:SetDrawLayer("OVERLAY", 7)

    -- Small "currently active totem" icon — for the Totems group's
    -- "Show active totem" option.  Sits centered above the duration
    -- timer, hidden by default.  Set in updateAll's totem branch.
    b.activeTotemIcon = b:CreateTexture(nil, "OVERLAY", nil, 7)
    b.activeTotemIcon:SetSize(16, 16)
    b.activeTotemIcon:SetPoint("BOTTOM", b.durTimer, "TOP", 0, 2)
    b.activeTotemIcon:Hide()

    -- Icon (ActionButtonTemplate provides .icon, but we ensure it exists)
    if not b.icon then
        b.icon = b:CreateTexture(nil, "ARTWORK")
    end
    -- 1px padding inside the button so the icon doesn't touch the border
    b.icon:ClearAllPoints()
    b.icon:SetPoint("TOPLEFT",     b, "TOPLEFT",      1, -1)
    b.icon:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -1,  1)

    -- Border for "missing" state (out-of-combat — soft yellow/white pulse)
    local glow = b:CreateTexture(nil, "OVERLAY")
    glow:SetTexture("Interface\\Buttons\\CheckButtonGlow")
    glow:SetBlendMode("ADD")
    glow:SetPoint("TOPLEFT", b, "TOPLEFT", -4, 4)
    glow:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 4, -4)
    glow:Hide()
    b.glow = glow

    local ag = glow:CreateAnimationGroup()
    ag:SetLooping("REPEAT")
    local a1 = ag:CreateAnimation("Alpha")
    a1:SetFromAlpha(0.2); a1:SetToAlpha(1); a1:SetDuration(0.4); a1:SetOrder(1)
    local a2 = ag:CreateAnimation("Alpha")
    a2:SetFromAlpha(1); a2:SetToAlpha(0.2); a2:SetDuration(0.4); a2:SetOrder(2)
    b.glowAnim = ag

    -- PANIC glow: in-combat missing alert.  Much larger, bright red,
    -- fast pulse PLUS a second "shockwave" ring that scales outward.
    local panic = b:CreateTexture(nil, "OVERLAY", nil, 6)
    panic:SetTexture("Interface\\Buttons\\CheckButtonGlow")
    panic:SetBlendMode("ADD")
    panic:SetPoint("TOPLEFT", b, "TOPLEFT", -16, 16)
    panic:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 16, -16)
    panic:SetVertexColor(1, 0.82, 0, 1)  -- gold
    panic:Hide()
    b.panicGlow = panic

    local panicAnim = panic:CreateAnimationGroup()
    panicAnim:SetLooping("REPEAT")
    local pa1 = panicAnim:CreateAnimation("Alpha")
    pa1:SetFromAlpha(0.3); pa1:SetToAlpha(1); pa1:SetDuration(0.25); pa1:SetOrder(1)
    local pa2 = panicAnim:CreateAnimation("Alpha")
    pa2:SetFromAlpha(1); pa2:SetToAlpha(0.3); pa2:SetDuration(0.25); pa2:SetOrder(2)
    b.panicAnim = panicAnim

    -- Outer shockwave ring (scales from the icon outward, fades)
    local ring = b:CreateTexture(nil, "OVERLAY", nil, 5)
    ring:SetTexture("Interface\\Cooldown\\star4")
    ring:SetBlendMode("ADD")
    ring:SetSize(BUTTON_SIZE * 2, BUTTON_SIZE * 2)
    ring:SetPoint("CENTER", b, "CENTER", 0, 0)
    ring:SetVertexColor(1, 0.82, 0, 0.9)  -- gold
    ring:Hide()
    b.ringGlow = ring

    local ringAnim = ring:CreateAnimationGroup()
    ringAnim:SetLooping("REPEAT")
    local ra1 = ringAnim:CreateAnimation("Scale")
    ra1:SetScale(0.8, 0.8); ra1:SetDuration(0); ra1:SetOrder(1)
    local ra2 = ringAnim:CreateAnimation("Scale")
    ra2:SetScale(2.0, 2.0); ra2:SetDuration(0.7); ra2:SetOrder(2)
    local ra3 = ringAnim:CreateAnimation("Alpha")
    ra3:SetFromAlpha(0.9); ra3:SetToAlpha(0); ra3:SetDuration(0.7); ra3:SetOrder(2)
    b.ringAnim = ringAnim

    -- Vertical bounce — symmetric around the anchor.  Goes UP first, sweeps
    -- DOWN through center to the same distance below, then back to center.
    local bounce = b.icon:CreateAnimationGroup()
    bounce:SetLooping("REPEAT")
    local bUp = bounce:CreateAnimation("Translation")
    bUp:SetOffset(0, 5);   bUp:SetDuration(0.12); bUp:SetOrder(1); bUp:SetSmoothing("OUT")
    local bDown = bounce:CreateAnimation("Translation")
    bDown:SetOffset(0, -10); bDown:SetDuration(0.20); bDown:SetOrder(2); bDown:SetSmoothing("IN_OUT")
    local bBack = bounce:CreateAnimation("Translation")
    bBack:SetOffset(0, 5);  bBack:SetDuration(0.12); bBack:SetOrder(3); bBack:SetSmoothing("IN")
    b.bounceAnim = bounce

    -- Horizontal shake — centered on the icon: goes LEFT first, sweeps
    -- through center to RIGHT, then back.  Net motion always returns to
    -- the icon's anchor point.
    local shake = b.icon:CreateAnimationGroup()
    shake:SetLooping("REPEAT")
    -- Horizontal range = 25% of vertical (vertical = ±5, horizontal = ±1.25).
    local sLeft = shake:CreateAnimation("Translation")
    sLeft:SetOffset(-1.25, 0); sLeft:SetDuration(0.12); sLeft:SetOrder(1); sLeft:SetSmoothing("OUT")
    local sRight = shake:CreateAnimation("Translation")
    sRight:SetOffset(2.5, 0);  sRight:SetDuration(0.20); sRight:SetOrder(2); sRight:SetSmoothing("IN_OUT")
    local sBack = shake:CreateAnimation("Translation")
    sBack:SetOffset(-1.25, 0); sBack:SetDuration(0.12); sBack:SetOrder(3); sBack:SetSmoothing("IN")
    b.shakeAnim = shake

    -- Icon flash — alpha pulse on the icon texture (parallel group so it
    -- runs simultaneously with the bounce)
    local flash = b.icon:CreateAnimationGroup()
    flash:SetLooping("REPEAT")
    local fadeOut = flash:CreateAnimation("Alpha")
    fadeOut:SetFromAlpha(1); fadeOut:SetToAlpha(0.35)
    fadeOut:SetDuration(0.18); fadeOut:SetOrder(1)
    local fadeIn = flash:CreateAnimation("Alpha")
    fadeIn:SetFromAlpha(0.35); fadeIn:SetToAlpha(1)
    fadeIn:SetDuration(0.18); fadeIn:SetOrder(2)
    b.flashAnim = flash

    -- Scale pulse — icon grows and shrinks rhythmically
    local pulse = b.icon:CreateAnimationGroup()
    pulse:SetLooping("REPEAT")
    local pUp = pulse:CreateAnimation("Scale")
    pUp:SetScale(1.2, 1.2); pUp:SetDuration(0.18); pUp:SetOrder(1)
    pUp:SetSmoothing("OUT")
    local pDown = pulse:CreateAnimation("Scale")
    pDown:SetScale(1/1.2, 1/1.2); pDown:SetDuration(0.18); pDown:SetOrder(2)
    pDown:SetSmoothing("IN")
    b.pulseAnim = pulse

    -- Spin — icon rotates a full turn
    local spin = b.icon:CreateAnimationGroup()
    spin:SetLooping("REPEAT")
    local rot = spin:CreateAnimation("Rotation")
    rot:SetDegrees(360); rot:SetDuration(0.9); rot:SetOrder(1)
    b.spinAnim = spin

    -- "Running out" warning — solid red overlay covering the icon at
    -- ~75% opacity, with a slow pulse for extra attention.  Sits on top
    -- of the icon but below the panic glow + ring.
    local rb = b:CreateTexture(nil, "OVERLAY", nil, 4)
    rb:SetTexture("Interface\\Buttons\\WHITE8x8")
    rb:SetVertexColor(1, 0.1, 0.1, 0.7)
    rb:SetPoint("TOPLEFT",     b.icon, "TOPLEFT",      0,  0)
    rb:SetPoint("BOTTOMRIGHT", b.icon, "BOTTOMRIGHT",  0,  0)
    rb:Hide()
    b.redBorder = rb

    -- Reversed pulse: starts at 35%, fades up to 70%, then back down.
    local rbAnim = rb:CreateAnimationGroup()
    rbAnim:SetLooping("REPEAT")
    local rbUp = rbAnim:CreateAnimation("Alpha")
    rbUp:SetFromAlpha(0.35); rbUp:SetToAlpha(0.7)
    rbUp:SetDuration(0.5); rbUp:SetOrder(1)
    local rbDn = rbAnim:CreateAnimation("Alpha")
    rbDn:SetFromAlpha(0.7); rbDn:SetToAlpha(0.35)
    rbDn:SetDuration(0.5); rbDn:SetOrder(2)
    b.redBorderAnim = rbAnim

    -- Tooltip — show the spell's real WoW tooltip (stats, description, etc.)
    -- plus our click-instruction footer.  Stack button keeps its custom
    -- preview because its "spell" is a castsequence, not a single spell.
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")

        ----------------------------------------------------------------
        -- Stack button (left) — Totem Sequence
        ----------------------------------------------------------------
        if self.kind == "stack" then
            GameTooltip:SetText("|cffffd200Totem Sequence|r", 1, 1, 1)
            local active = DB and DB.activeSet
            if active then
                GameTooltip:AddLine("Active: " .. active, 0.9, 0.9, 0.9)
            end
            local set = active and DB.sets and DB.sets[active]
            if set then
                for i, totem in ipairs(set) do
                    local marker = (self.seqStep and i == self.seqStep + 1) and "|cff00ff88▶ |r" or "  "
                    GameTooltip:AddLine(marker .. i .. ". " .. totem, 0.7, 0.7, 0.7)
                end
            end
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("|cff7ec8ffClick:|r drop next totem in sequence", 0.7, 0.85, 1)
            GameTooltip:AddLine("|cff7ec8ffShift-click:|r cycle saved sequences", 0.7, 0.85, 1)
            GameTooltip:AddLine("|cff7ec8ffRight-click:|r pick a sequence", 0.7, 0.85, 1)
            GameTooltip:Show()
            return
        end

        ----------------------------------------------------------------
        -- Totem Stack switcher button (right) — Totem Stacks
        ----------------------------------------------------------------
        if self.kind == "totemStack" then
            GameTooltip:SetText("|cffffd200Totem Stacks|r", 1, 1, 1)
            local active = DB and DB.activeTotemStack
            if active then
                GameTooltip:AddLine("Active: " .. active, 0.9, 0.9, 0.9)
                local stk = DB.totemStacks and DB.totemStacks[active]
                if stk then
                    for _, elem in ipairs(NS.ELEMENT_ORDER) do
                        if stk[elem] then
                            GameTooltip:AddLine("  " .. elem:upper() .. ": " .. stk[elem], 0.7, 0.7, 0.7)
                        end
                    end
                end
            else
                GameTooltip:AddLine("(no stack active)", 0.7, 0.7, 0.7)
            end
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("|cff7ec8ffClick:|r swap preset totems (apply active)", 0.7, 0.85, 1)
            GameTooltip:AddLine("|cff7ec8ffShift-click:|r cycle saved stacks", 0.7, 0.85, 1)
            GameTooltip:AddLine("|cff7ec8ffRight-click:|r pick a stack", 0.7, 0.85, 1)
            GameTooltip:Show()
            return
        end

        ----------------------------------------------------------------
        -- Everything else: resolve the spell name for this button, then
        -- ask the game for its native tooltip via SetSpellByID.
        ----------------------------------------------------------------
        local spellName
        if self.kind == "totem"  then spellName = DB.defaults and DB.defaults[self.element]
        elseif self.kind == "mh" then spellName = DB.defaults and DB.defaults.mh
        elseif self.kind == "oh" then spellName = DB.defaults and DB.defaults.oh
        elseif self.kind == "util" then
            spellName = DB.utilSelected and DB.utilSelected[self.utilSlot]
        elseif self.kind == "ls" then spellName = NS.LIGHTNING_SHIELD
        end

        if spellName then
            local _, _, _, _, _, _, spellID = GetSpellInfo(spellName)
            if spellID then
                GameTooltip:SetSpellByID(spellID)
            else
                GameTooltip:SetText(spellName, 1, 1, 1)
            end

            -- Click-instruction footer
            GameTooltip:AddLine(" ")
            if self.kind == "totem" then
                GameTooltip:AddLine("|cff7ec8ffClick:|r drop totem", 0.7, 0.85, 1)
                GameTooltip:AddLine("|cff7ec8ffShift-click:|r cycle "
                    .. (self.element or "") .. " totems", 0.7, 0.85, 1)
                GameTooltip:AddLine("|cff7ec8ffRight-click:|r pick a totem", 0.7, 0.85, 1)
            elseif self.kind == "mh" or self.kind == "oh" then
                local sec = DB.defaults and DB.defaults[self.kind .. "2"]
                GameTooltip:AddLine("|cff7ec8ffClick:|r apply primary imbue", 0.7, 0.85, 1)
                if sec then
                    GameTooltip:AddLine("|cff7ec8ffShift-click:|r " .. sec, 0.7, 0.85, 1)
                end
                GameTooltip:AddLine("|cff7ec8ffRight-click:|r change imbues", 0.7, 0.85, 1)
            elseif self.kind == "util" then
                GameTooltip:AddLine("|cff7ec8ffClick:|r cast", 0.7, 0.85, 1)
                GameTooltip:AddLine("|cff7ec8ffShift-click:|r cycle utilities", 0.7, 0.85, 1)
                GameTooltip:AddLine("|cff7ec8ffRight-click:|r pick a utility", 0.7, 0.85, 1)
            elseif self.kind == "ls" then
                GameTooltip:AddLine("|cff7ec8ffClick:|r cast", 0.7, 0.85, 1)
            end
        elseif self.kind == "util" then
            GameTooltip:SetText("Empty utility slot " .. (self.utilSlot or ""), 1, 1, 1)
            GameTooltip:AddLine("Right-click to assign a spell.", 0.7, 0.7, 0.7)
            GameTooltip:AddLine("Shift-click to cycle utilities.", 0.7, 0.85, 1)
        else
            GameTooltip:Hide(); return
        end
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)

    return b
end

-- Cast happens only on LEFT-click (type1).  We deliberately leave type2 unset
-- so right-click does NOT trigger a secure cast — it only opens our dropdown.
-- Main Cycle Modifier helpers ----------------------------------------
-- When the user binds a "Drop X" action to a key and presses it with
-- the configured modifier held, the click should CYCLE instead of
-- casting.  This requires two cooperating pieces:
--   1. PreClick checks isCycleMod() and routes to the cycle function.
--   2. The matching `<mod>-type1` secure attribute is set to "macro"
--      with an empty body so the secure path does NOT fire the spell.
-- Shift is always treated as a cycle modifier (mouse shift-click).
local function isCycleMod()
    if IsShiftKeyDown() then return true end
    local m = DB and DB.cycleModifier or "shift"
    if m == "alt"  then return IsAltKeyDown() end
    if m == "ctrl" then return IsControlKeyDown() end
    return false
end

-- Apply the cycle-modifier suppression to a single button.  shift-type1
-- is always neutered; alt-/ctrl- get neutered only when the user has
-- selected them, and cleared when they haven't.
local function applyCycleModSecure(b)
    b:SetAttribute("shift-type1",      "macro")
    b:SetAttribute("shift-macrotext1", "")
    local m = DB and DB.cycleModifier or "shift"
    if m == "alt" then
        b:SetAttribute("alt-type1",      "macro")
        b:SetAttribute("alt-macrotext1", "")
        b:SetAttribute("ctrl-type1", nil); b:SetAttribute("ctrl-macrotext1", nil)
    elseif m == "ctrl" then
        b:SetAttribute("ctrl-type1",      "macro")
        b:SetAttribute("ctrl-macrotext1", "")
        b:SetAttribute("alt-type1", nil); b:SetAttribute("alt-macrotext1", nil)
    else
        b:SetAttribute("alt-type1", nil);  b:SetAttribute("alt-macrotext1", nil)
        b:SetAttribute("ctrl-type1", nil); b:SetAttribute("ctrl-macrotext1", nil)
    end
end

local function setButtonSpell(b, spell)
    -- Note: SetAttribute on a SecureActionButton is allowed in combat in
    -- Classic Era. Frame manipulation (Show/Hide/SetPoint) is what's
    -- restricted. So we don't gate this — totem swaps work mid-pull.
    b:SetAttribute("type",  nil)
    b:SetAttribute("type2", nil)
    b:SetAttribute("type1", "spell")
    b:SetAttribute("spell1", spell)
    b:SetAttribute("spell",  nil)
    -- Cycle modifier(s) → empty macro so the secure click doesn't
    -- fall back to type1=spell when the modifier is held.
    applyCycleModSecure(b)
    b.icon:SetTexture(spellIcon(spell))
    b.spell = spell
    b.macrotext = nil
    return true
end

local function setButtonMacro(b, macrotext, displayIcon)
    b:SetAttribute("type",  nil)
    b:SetAttribute("type2", nil)
    b:SetAttribute("type1", "macro")
    b:SetAttribute("macrotext1", macrotext)
    b:SetAttribute("macrotext",  nil)
    b.icon:SetTexture(displayIcon or 134400)
    b.spell = nil
    b.macrotext = macrotext
    return true
end

-- Wipe all secure click attributes so a stale click doesn't fire an old
-- spell.  Used when a util slot is cleared.
local function clearButton(b)
    b:SetAttribute("type",   nil)
    b:SetAttribute("type1",  nil)
    b:SetAttribute("type2",  nil)
    b:SetAttribute("spell",       nil)
    b:SetAttribute("spell1",      nil)
    b:SetAttribute("macrotext",   nil)
    b:SetAttribute("macrotext1",  nil)
    b:SetAttribute("shift-type1",      nil)
    b:SetAttribute("shift-macrotext1", nil)
    b.icon:SetTexture(134400)  -- generic ? icon
    b.icon:SetDesaturated(true)
    b.spell = nil
    b.macrotext = nil
end

-- Imbue buttons: primary on left-click, secondary on shift+left-click.
-- Right-click is a dropdown (handled via PreClick, no secure type set).
local function setImbueButton(b, slotID, primary, secondary)
    b:SetAttribute("type",   nil)
    b:SetAttribute("type2",  nil)
    -- Left-click: primary
    b:SetAttribute("type1",       "macro")
    b:SetAttribute("macrotext1",  primary and ("/cast " .. primary .. "\n/use " .. slotID) or "")
    -- Shift+left-click: secondary (no-op if nil)
    b:SetAttribute("shift-type1",      "macro")
    b:SetAttribute("shift-macrotext1", secondary and ("/cast " .. secondary .. "\n/use " .. slotID) or "")
    b.icon:SetTexture(spellIcon(primary))
    if b.secIcon then
        if secondary then
            b.secIcon:SetTexture(spellIcon(secondary))
            b.secIcon:Show()
        else
            b.secIcon:Hide()
        end
    end
    b.spell  = primary
    b.spell2 = secondary
    return true
end

------------------------------------------------------------------------
-- Dropdown menus (UIDropDownMenu / EasyMenu)
------------------------------------------------------------------------
local Menu = CreateFrame("Frame", "TotemTommysBarsMenu", UIParent, "UIDropDownMenuTemplate")

local function showMenu(button, items)
    UIDropDownMenu_Initialize(Menu, function(_, level)
        for _, info in ipairs(items) do
            UIDropDownMenu_AddButton(info, level)
        end
    end, "MENU")
    ToggleDropDownMenu(1, nil, Menu, "cursor", 0, 0)
end

-- Prefix a spell name with its inline icon for dropdown text.
local function iconLabel(spellName)
    local _, _, icon = GetSpellInfo(spellName)
    if icon then
        return "|T" .. icon .. ":20:20:0:0:64:64:4:60:4:60|t  " .. spellName
    end
    return spellName
end

local function totemMenu(element, button)
    local items = { { text = element:upper() .. " TOTEMS", isTitle = true, notCheckable = true } }
    for _, name in ipairs(knownOnly(NS.TOTEMS[element])) do
        items[#items + 1] = {
            text = iconLabel(name),
            checked = (DB.defaults[element] == name),
            func = function()
                if setButtonSpell(button, name) then
                    DB.defaults[element] = name
                end
            end,
        }
    end
    showMenu(button, items)
end

local function spellListMenu(list, button, dbKey)
    local items = { { text = "SELECT", isTitle = true, notCheckable = true } }
    for _, name in ipairs(list) do
        items[#items + 1] = {
            text = name,
            checked = (DB.defaults[dbKey] == name),
            func = function()
                if setButtonSpell(button, name) then
                    DB.defaults[dbKey] = name
                end
            end,
        }
    end
    showMenu(button, items)
end

------------------------------------------------------------------------
-- Stack button (castsequence)
------------------------------------------------------------------------
local function sequenceResetSeconds(setName)
    -- Per-sequence customizable rollback timer (Options → Custom Totem
    -- Sequence → Reset timer).  Falls back to 8 if unset.
    local v = DB and DB.setReset and DB.setReset[setName]
    if type(v) == "number" and v >= 1 and v <= 120 then return v end
    return 8
end

local function buildSequenceMacro(setName)
    local set = DB.sets[setName]
    if not set or #set == 0 then return nil end
    return "/castsequence reset=" .. sequenceResetSeconds(setName) .. "/target " .. table.concat(set, ", ")
end

-- Stack icon depends on seqStep:
--   step 0  → custom stack icon (or first totem icon if no custom)
--   step N  → icon of set[N+1] (the NEXT totem to drop)
--   step >= #set → reset to 0
local function stackIconForStep(setName, step)
    local set = DB.sets and DB.sets[setName]
    if not set or #set == 0 then return 134400 end
    if step and step > 0 and step < #set then
        return spellIcon(set[step + 1])
    end
    -- Neutral (step 0 / sequence completed): custom or first-totem fallback
    return (DB.stackIcons and DB.stackIcons[setName]) or spellIcon(set[1])
end

local function updateStackIcon(button)
    button.icon:SetTexture(stackIconForStep(DB.activeSet, button.seqStep or 0))
end

local function applyStack(button)
    local macro = buildSequenceMacro(DB.activeSet)
    if not macro then
        setButtonMacro(button, "/run print('No active stack set')", 134400)
    else
        local set = DB.sets[DB.activeSet]
        setButtonMacro(button, macro, stackIconForStep(DB.activeSet, 0))
        button.hint = "Stack: " .. DB.activeSet .. " (Shift+click cycles)"
    end
    -- Shift+leftclick is reserved for cycleStack (handled in PreClick).
    -- Override the secure action with an empty macro so it doesn't fall
    -- back to type1 (which would re-fire the castsequence).
    button:SetAttribute("shift-type1", "macro")
    button:SetAttribute("shift-macrotext1", "")
    button.seqStep = 0
end

local applyUtilStack  -- forward declaration; defined further down

local function stackMenu(button)
    local items = { { text = "TOTEM SEQUENCE", isTitle = true, notCheckable = true } }
    -- Sorted iteration so menu order is stable
    local sortedNames = {}
    for n in pairs(DB.sets or {}) do sortedNames[#sortedNames + 1] = n end
    table.sort(sortedNames)
    for _, name in ipairs(sortedNames) do
        local set = DB.sets[name]
        local previewIcon = set and set[1] and ("|T" .. (select(3, GetSpellInfo(set[1])) or 134400) .. ":20:20:0:0:64:64:4:60:4:60|t  ") or ""
        items[#items + 1] = {
            text = previewIcon .. name,
            checked = (DB.activeSet == name),
            func = function()
                DB.activeSet = name
                local set = DB.sets[name]
                if set then
                    for _, totem in ipairs(set) do
                        for element, list in pairs(NS.TOTEMS) do
                            for _, n in ipairs(list) do
                                if n == totem then DB.defaults[element] = totem end
                            end
                        end
                    end
                end
                applyStack(button)
                -- refresh element buttons via NS.API.refresh once it's wired
                if NS.API and NS.API.refresh then NS.API.refresh() end
            end,
        }
    end
    items[#items + 1] = { text = "", disabled = true, notCheckable = true }
    items[#items + 1] = {
        text = "Open options (/ttb)",
        disabled = true,
        notCheckable = true,
    }
    showMenu(button, items)
end

-- Available utilities = every utility option the player has learned.
-- (DB.utilities is no longer used for gating; util stacks + slot picks
-- are the source of truth.)
local function enabledUtilities()
    local out = {}
    for _, name in ipairs(NS.UTILITY_OPTIONS) do
        if isKnown(name) then out[#out + 1] = name end
    end
    return out
end

local function cycleUtility(button)
    local list = enabledUtilities()
    if #list == 0 then return end
    local slot = button.utilSlot
    local cur = DB.utilSelected and DB.utilSelected[slot]
    local idx = 0
    for i, n in ipairs(list) do
        if n == cur then idx = i; break end
    end
    local nextName = list[(idx % #list) + 1]
    DB.utilSelected[slot] = nextName
    setButtonSpell(button, nextName)
end

local function utilityMenu(button)
    local slot = button.utilSlot
    local items = { { text = "UTILITY SLOT " .. slot, isTitle = true, notCheckable = true } }
    local list = enabledUtilities()
    if #list == 0 then
        items[#items + 1] = {
            text = "(no shaman utility spells learned yet)",
            disabled = true, notCheckable = true,
        }
    else
        for _, name in ipairs(list) do
            items[#items + 1] = {
                text = iconLabel(name),
                checked = (DB.utilSelected[slot] == name),
                func = function()
                    DB.utilSelected[slot] = name
                    setButtonSpell(button, name)
                    if NS.API and NS.API.updateAll then NS.API.updateAll() end
                end,
            }
        end
    end
    items[#items + 1] = { text = "", disabled = true, notCheckable = true }
    items[#items + 1] = {
        text = "(none — empty slot)",
        checked = (DB.utilSelected[slot] == nil),
        func = function()
            DB.utilSelected[slot] = nil
            clearButton(button)
            if NS.API and NS.API.updateAll then NS.API.updateAll() end
        end,
    }
    showMenu(button, items)
end

-- Shift+left-click on an element button: cycle to the next known totem of
-- that element. Independent of the active stack; the stack is only re-synced
-- when the user picks one (Use button or right-click stack menu).
local function cycleElement(element, button)
    local known = knownOnly(NS.TOTEMS[element])
    if #known == 0 then return end
    local cur = DB.defaults[element]
    local idx = 0
    for i, n in ipairs(known) do
        if n == cur then idx = i; break end
    end
    local nextName = known[(idx % #known) + 1]
    DB.defaults[element] = nextName
    setButtonSpell(button, nextName)
    -- Immediate visual refresh: cooldown swipe + missing-state for this
    -- element, instead of waiting for the next 0.5s OnUpdate tick.
    if NS.API and NS.API.updateAll then NS.API.updateAll() end
end

-- Shift+left-click on Stack: cycle to next saved stack (alphabetical wrap-around).
local function cycleStack(stackButton)
    local names = {}
    for n in pairs(DB.sets) do names[#names + 1] = n end
    if #names < 2 then
        print("|cffffd000TTB:|r need at least 2 saved stacks to cycle.")
        return
    end
    table.sort(names)
    local idx = 1
    for i, n in ipairs(names) do
        if n == DB.activeSet then idx = i; break end
    end
    local nextName = names[(idx % #names) + 1]
    DB.activeSet = nextName
    local set = DB.sets[nextName]
    if set then
        for _, totem in ipairs(set) do
            for element, list in pairs(NS.TOTEMS) do
                for _, n in ipairs(list) do
                    if n == totem then DB.defaults[element] = totem end
                end
            end
        end
    end
    applyStack(stackButton)
    if NS.API and NS.API.refresh then NS.API.refresh() end
    print("|cff00ff88TTB:|r stack → '" .. nextName .. "'")
end

------------------------------------------------------------------------
-- Build all buttons
------------------------------------------------------------------------
local function buildImbueButton(slotName, slotID, dbKey, label)
    local b = createButton(slotName, ImbueBar)
    -- Secondary spell icon overlay — sits INSIDE the primary icon's
    -- bottom-right corner so it never extends past the imbue button.
    local sec = b:CreateTexture(nil, "OVERLAY")
    sec:SetPoint("BOTTOMRIGHT", b.icon, "BOTTOMRIGHT", 0, 0)
    sec:SetSize(19, 19)
    sec:Hide()
    b.secIcon = sec
    -- Thin frame around the secondary icon — sized to match exactly so it
    -- hugs the icon's edge instead of bleeding outside.
    local secBorder = b:CreateTexture(nil, "OVERLAY", nil, -1)
    secBorder:SetTexture("Interface\\Buttons\\UI-Quickslot2")
    secBorder:SetPoint("TOPLEFT",     sec, "TOPLEFT",     -1, 1)
    secBorder:SetPoint("BOTTOMRIGHT", sec, "BOTTOMRIGHT",  1, -1)
    secBorder:SetVertexColor(0.7, 0.7, 0.7, 0.7)
    secBorder:Hide()
    b.secBorder = secBorder
    sec:HookScript("OnShow", function() secBorder:Show() end)
    sec:HookScript("OnHide", function() secBorder:Hide() end)

    b.kind   = dbKey  -- "mh" or "oh"
    b.slotID = slotID
    b.dbKey2 = dbKey .. "2"
    b.hint   = label .. "  (Shift+click = secondary)"

    setImbueButton(b, slotID, DB.defaults[dbKey], DB.defaults[b.dbKey2])

    b:SetScript("PreClick", function(self, btn)
        if btn ~= "RightButton" then return end
        local key1, key2 = dbKey, self.dbKey2
        UIDropDownMenu_Initialize(Menu, function(_, level)
            level = level or 1
            if level == 1 then
                local hdr = UIDropDownMenu_CreateInfo()
                hdr.text = label:upper(); hdr.isTitle = true; hdr.notCheckable = true
                UIDropDownMenu_AddButton(hdr, level)

                local cur1 = DB.defaults[key1]
                local p = UIDropDownMenu_CreateInfo()
                p.text = "Primary (click): " .. (cur1 and iconLabel(cur1) or "(none)")
                p.hasArrow = true; p.notCheckable = true; p.value = "primary"
                UIDropDownMenu_AddButton(p, level)

                local cur2 = DB.defaults[key2]
                local s = UIDropDownMenu_CreateInfo()
                s.text = "Secondary (shift): " .. (cur2 and iconLabel(cur2) or "(none)")
                s.hasArrow = true; s.notCheckable = true; s.value = "secondary"
                UIDropDownMenu_AddButton(s, level)
            elseif level == 2 then
                local target = UIDROPDOWNMENU_MENU_VALUE
                local key = (target == "primary") and key1 or key2
                for _, name in ipairs(knownOnly(NS.IMBUES)) do
                    local info = UIDropDownMenu_CreateInfo()
                    info.text = iconLabel(name)
                    info.checked = (DB.defaults[key] == name)
                    info.func = function()
                        DB.defaults[key] = name
                        setImbueButton(b, slotID, DB.defaults[key1], DB.defaults[key2])
                        CloseDropDownMenus()
                    end
                    UIDropDownMenu_AddButton(info, level)
                end
                if target == "secondary" then
                    local none = UIDropDownMenu_CreateInfo()
                    none.text = "(none — disable shift-click)"
                    none.checked = (DB.defaults[key2] == nil)
                    none.func = function()
                        DB.defaults[key2] = nil
                        setImbueButton(b, slotID, DB.defaults[key1], nil)
                        CloseDropDownMenus()
                    end
                    UIDropDownMenu_AddButton(none, level)
                end
            end
        end, "MENU")
        ToggleDropDownMenu(1, nil, Menu, "cursor", 0, 0)
    end)

    Buttons[#Buttons + 1] = b
    return b
end

-- Forward declarations so buildButtons can wire up the TotemStackBar
-- switch button before the totem-stack helpers are defined further down.
local useTotemStack, cycleTotemStack, totemStackMenu
local refreshTotemStackSwitchIcon

local function buildButtons()
    local order = {}

    -- Totem element buttons
    -- Click       : drop the current default totem for this element
    -- Shift+click : cycle to next known totem of this element
    -- Right-click : pick a specific totem
    for _, element in ipairs(NS.ELEMENT_ORDER) do
        local b = createButton("Totem_" .. element, Bar)
        setButtonSpell(b, DB.defaults[element])
        b.hint = element:upper() .. " totem  (Shift+click cycles)"
        b.kind = "totem"
        b.element = element
        b:SetScript("PreClick", function(self, btn)
            if btn == "LeftButton" and isCycleMod() then
                cycleElement(element, self)
            elseif btn == "RightButton" then
                totemMenu(element, self)
            end
        end)
        Buttons[#Buttons + 1] = b
        order[#order + 1] = b
    end

    -- Stack button — parented to its own bar so it gets a separate gold
    -- border and sits visually beside the totem element row.
    local stack = createButton("Stack", StackBar)
    stack.kind = "stack"
    applyStack(stack)
    stack.hint = "Click: drop next  |  Shift+click: cycle stacks  |  Right-click: menu"
    stack:SetScript("PreClick", function(self, btn)
        if btn == "LeftButton" and isCycleMod() then
            cycleStack(self)
        elseif btn == "RightButton" then
            stackMenu(self)
        end
    end)
    -- Sequence position is now driven authoritatively by
    -- UNIT_SPELLCAST_SUCCEEDED (only advances on a real cast).  No
    -- PostClick handler needed — clicks that fail to cast no longer
    -- desync the icon.
    Buttons[#Buttons + 1] = stack
    Bar.stackButton = stack
    StackBar.order = { stack }
    -- (NOT added to `order` — stack lives on its own StackBar frame.)

    -- Totem Stack switcher button — mirrors the Stack button on the right.
    -- Left-click re-applies the active stack, Shift-click cycles, Right-click
    -- opens the menu.
    local tsSwitch = createButton("TotemStackSwitch", TotemStackBar)
    tsSwitch.kind = "totemStack"
    tsSwitch.hint = "Click: apply  |  Shift+click: cycle  |  Right-click: pick"
    tsSwitch:SetAttribute("type1", nil)  -- no spell cast
    tsSwitch:SetAttribute("type2", nil)
    tsSwitch:SetAttribute("shift-type1", "macro")
    tsSwitch:SetAttribute("shift-macrotext1", "")
    tsSwitch:SetScript("PreClick", function(self, btn)
        if btn == "LeftButton" and isCycleMod() then
            cycleTotemStack()
        elseif btn == "LeftButton" then
            if DB.activeTotemStack then useTotemStack(DB.activeTotemStack) end
        elseif btn == "RightButton" then
            totemStackMenu(self)
        end
    end)
    Buttons[#Buttons + 1] = tsSwitch
    Bar.tsSwitch = tsSwitch
    TotemStackBar.order = { tsSwitch }

    refreshTotemStackSwitchIcon = function()
        local fileID
        local activeName = DB.activeTotemStack
        if activeName and DB.totemStackIcons then
            fileID = DB.totemStackIcons[activeName]
        end
        if not fileID and activeName and DB.totemStacks then
            local stk = DB.totemStacks[activeName]
            if stk then
                local first = stk.fire or stk.water or stk.earth or stk.air
                if first then fileID = select(3, GetSpellInfo(first)) end
            end
        end
        if not fileID then fileID = 134400 end  -- ? placeholder
        if tsSwitch.icon then
            tsSwitch.icon:SetTexture(fileID)
            -- Match the Stack/Sequence button: no TexCoord crop, so the
            -- icon's natural border looks identical on both sides.
            tsSwitch.icon:SetTexCoord(0, 1, 0, 1)
        end
    end
    refreshTotemStackSwitchIcon()

    -- Lightning Shield now lives on the Imbue mini-bar (see below).

    -- Two utility slots.  Each behaves like an element button: the slot
    -- holds a single spell drawn from the user's enabled utility pool.
    -- Click casts; Shift-click cycles through the pool; right-click picks.
    for slot = 1, 2 do
        local u = createButton("Util_" .. slot, Bar)
        u.kind = "util"
        u.utilSlot = slot
        local current = DB.utilSelected and DB.utilSelected[slot]
        if current then
            setButtonSpell(u, current)
        else
            clearButton(u)  -- placeholder ? icon, no secure attrs
        end
        u.hint = "Utility slot " .. slot .. "  (Shift+click cycles)"
        u:SetScript("PreClick", function(self, btn)
            if btn == "LeftButton" and isCycleMod() then
                cycleUtility(self)
            elseif btn == "RightButton" then
                utilityMenu(self)
            end
        end)
        Buttons[#Buttons + 1] = u
        order[#order + 1] = u
    end

    Bar.order = order

    -- Imbue mini-bar (separate frame): MH | OH | Lightning Shield
    local mh = buildImbueButton("MH", 16, "mh", "Mainhand imbue")
    local oh = buildImbueButton("OH", 17, "oh", "Offhand imbue")
    -- Lightning Shield (kind="ls" so the in-combat panic alert still fires)
    local ls = createButton("LS", ImbueBar)
    setButtonSpell(ls, NS.LIGHTNING_SHIELD)
    ls.hint = "Lightning Shield"
    ls.kind = "ls"
    Buttons[#Buttons + 1] = ls
    Bar.lsButton  = ls
    Bar.mhButton  = mh
    Bar.ohButton  = oh
    ImbueBar.order = { mh, oh, ls }

    ------------------------------------------------------------------
    -- Recall All — single non-secure button parented to RecallBar.
    -- DestroyTotem(slot) is a plain API call, no spell, no GCD, no
    -- mana cost.  Iterates all 4 slots so it works as a "clear board"
    -- panic button.
    ------------------------------------------------------------------
    local recall = CreateFrame("Button", "TotemTommysBars_RecallAll", RecallBar, "ActionButtonTemplate")
    recall:SetSize(BUTTON_SIZE, BUTTON_SIZE)
    if recall.icon then
        -- "Boot to the rear" / pull icon: Spell_Nature_AstralRecal works
        -- thematically for "recall" even without the spell.
        recall.icon:SetTexture("Interface\\Icons\\Spell_Nature_AstralRecal")
        recall.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    end
    recall:SetScript("OnClick", function()
        for slot = 1, 4 do
            if DestroyTotem then DestroyTotem(slot) end
        end
        if NS.API and NS.API.updateAll then NS.API.updateAll() end
    end)
    recall:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("|cffffd200Recall All Totems|r", 1, 1, 1)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Instantly destroys all four active totems.", 0.9, 0.9, 0.9, true)
        GameTooltip:AddLine("No mana cost, no GCD, works in combat.", 0.6, 0.85, 0.6, true)
        GameTooltip:Show()
    end)
    recall:SetScript("OnLeave", function() GameTooltip:Hide() end)
    Bar.recallButton = recall
end

------------------------------------------------------------------------
-- Layout
------------------------------------------------------------------------
-- Compute (cols, rows) from a layout mode and button count.
local function layoutDims(mode, n)
    if mode == "row"     then mode = "horizontal" end
    if mode == "stacked" then mode = "vertical"   end
    if mode == "horizontal" then return n, 1
    elseif mode == "vertical" then return 1, n
    else return math.ceil(n / 2), 2  -- grid
    end
end

-- Position buttons inside a frame in a given layout, set the frame's size
-- accordingly, apply scale + position, and toggle the unlocked/locked look.
-- Titles are always hidden — the gold border alone signals "draggable".
local function layoutFrame(frame, title, visible, mode, scaleFactor, pos)
    if #visible == 0 then frame:Hide(); return end
    frame:Show()
    local n = #visible
    local cols, rows = layoutDims(mode, n)
    local w = cols * BUTTON_SIZE + (cols - 1) * PADDING + BAR_PAD * 2
    local h = rows * BUTTON_SIZE + (rows - 1) * PADDING + BAR_PAD * 2
    frame:SetSize(w, h)
    for i, b in ipairs(visible) do
        local row = math.floor((i - 1) / cols)
        local col = (i - 1) % cols
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", frame, "TOPLEFT",
            BAR_PAD + col * (BUTTON_SIZE + PADDING),
            -(BAR_PAD + row * (BUTTON_SIZE + PADDING)))
    end
    frame:SetScale(DB.scale * (scaleFactor or 1))
    frame:ClearAllPoints()
    frame:SetPoint(pos[1], UIParent, pos[3], pos[4], pos[5])
    if title then title:Hide() end  -- always hidden; gold border = drag handle
    if DB.locked then
        frame:EnableMouse(false)
        if frame.SetBackdropBorderColor then
            frame:SetBackdropColor(0, 0, 0, 0)
            frame:SetBackdropBorderColor(0, 0, 0, 0)
        end
    else
        frame:EnableMouse(true)
        if frame.SetBackdropBorderColor then
            frame:SetBackdropColor(0.05, 0.05, 0.07, 0.6)
            frame:SetBackdropBorderColor(0.85, 0.7, 0.2, 1)
        end
    end
end

local function layout()
    local combatNow = inCombat()

    -- Master hide: shift-clicking the minimap button toggles this.
    -- Hides every bar wholesale until toggled back on.
    if DB and DB.barsHidden then
        if not combatNow then
            Bar:Hide(); ImbueBar:Hide(); UtilBar:Hide()
            StackBar:Hide(); TotemStackBar:Hide()
            RecallBar:Hide()
        end
        return
    end

    -- Determine if we have an actual "combined" cluster (need 2+ flags).
    local cnt = (DB.combineTotems and 1 or 0)
              + (DB.combineUtility and 1 or 0)
              + (DB.combineImbue and 1 or 0)
    local doCombine = cnt >= 2

    -- Choose the host frame for combined buttons.  Priority: Totems > Util > Imbue.
    -- Combined-bar scale uses either the HIGHER or LOWER of the combined
    -- groups' scales depending on DB.combinedScalePref.  Uncombining
    -- instantly restores each bar to its own slider value.
    local host, hostLayout, hostScale, hostPos, hostTitle
    if doCombine then
        local pickHigher = (DB.combinedScalePref or "higher") == "higher"
        local resultScale
        local function consider(v)
            if not v then return end
            if not resultScale then resultScale = v
            elseif pickHigher then resultScale = math.max(resultScale, v)
            else                   resultScale = math.min(resultScale, v) end
        end
        if DB.combineTotems  then consider(DB.totemScale or 1.0) end
        if DB.combineUtility then consider(DB.utilScale  or 1.0) end
        if DB.combineImbue   then consider(DB.imbueScale or 1.5) end
        local maxScale = resultScale or 1.0

        if DB.combineTotems then
            host, hostPos, hostTitle = Bar,      DB.point,      Title
        elseif DB.combineUtility then
            host, hostPos, hostTitle = UtilBar,  DB.utilPoint,  UtilTitle
        else
            host, hostPos, hostTitle = ImbueBar, DB.imbuePoint, ImbueTitle
        end
        -- Combined bars use the dedicated combinedLayout setting rather
        -- than any single group's solo layout.
        hostLayout = DB.combinedLayout or "horizontal"
        hostScale  = maxScale
    end

    -- Bucket every visible button into the right group's visible list.
    local visT, visU, visI, visH = {}, {}, {}, {}
    local function dispatch(b, kindGroup)
        local combined =
            (kindGroup == "totem" and DB.combineTotems) or
            (kindGroup == "util"  and DB.combineUtility) or
            (kindGroup == "imbue" and DB.combineImbue)
        local targetVis
        local targetFrame
        if doCombine and combined then
            targetVis = visH
            targetFrame = host
        elseif kindGroup == "totem" then
            targetVis = visT
            targetFrame = Bar
        elseif kindGroup == "util" then
            targetVis = visU
            targetFrame = UtilBar
        else
            targetVis = visI
            targetFrame = ImbueBar
        end
        targetVis[#targetVis + 1] = b
        if b:GetParent() ~= targetFrame and not combatNow then
            b:SetParent(targetFrame)
        end
    end

    for _, b in ipairs(Bar.order) do
        if b:IsShown() then
            if b.kind == "util" then dispatch(b, "util")
            else dispatch(b, "totem")  -- totem | stack
            end
        end
    end
    if ImbueBar.order then
        for _, b in ipairs(ImbueBar.order) do
            if b:IsShown() then dispatch(b, "imbue") end
        end
    end

    -- Layout the host (combined) frame, then any solo frames.
    if doCombine then
        layoutFrame(host, hostTitle, visH, hostLayout, hostScale, hostPos)
    end

    if (not doCombine) or (not DB.combineTotems) then
        layoutFrame(Bar, Title, visT, DB.totemLayout, DB.totemScale or 1.0, DB.point)
    end
    if (not doCombine) or (not DB.combineUtility) then
        layoutFrame(UtilBar, UtilTitle, visU, DB.utilLayout,
                    DB.utilScale or 1.0, DB.utilPoint)
    end
    if (not doCombine) or (not DB.combineImbue) then
        layoutFrame(ImbueBar, ImbueTitle, visI, DB.imbueLayout,
                    DB.imbueScale or 1.5, DB.imbuePoint)
    end

    -- Hide any frame that ended up empty (e.g. the host frame's "solo"
    -- list when it was absorbed into the combined view).
    if doCombine then
        if host ~= Bar      and #visT == 0 then Bar:Hide() end
        if host ~= UtilBar  and #visU == 0 then UtilBar:Hide() end
        if host ~= ImbueBar and #visI == 0 then ImbueBar:Hide() end
    end

    -- StackBar (left) and TotemStackBar (right) — both 1-button frames
    -- anchored to whichever frame is currently showing the totem elements.
    local stack = Bar.stackButton
    local tsSw  = Bar.tsSwitch
    local totemHost = (doCombine and DB.combineTotems) and host or Bar
    local totemHostHasVisible = (totemHost == host and #visH > 0)
                             or (totemHost == Bar  and #visT > 0)
    local showAdjacent = totemHostHasVisible and DB.showTotems ~= false
    local stackScale
    if doCombine and DB.combineTotems then
        stackScale = hostScale
    else
        stackScale = DB.totemScale or 1.0
    end

    local function placeAdjacent(frame, btn, anchor)
        if not (btn and btn:IsShown() and showAdjacent) then frame:Hide() return end
        frame:Show()
        local pad = BAR_PAD
        local w = BUTTON_SIZE + pad * 2
        local h = BUTTON_SIZE + pad * 2
        frame:SetSize(w, h)
        btn:ClearAllPoints()
        btn:SetPoint("TOPLEFT", frame, "TOPLEFT", pad, -pad)
        frame:SetScale(DB.scale * (stackScale or 1.0))
        frame:ClearAllPoints()
        if anchor == "left" then
            frame:SetPoint("TOPRIGHT", totemHost, "TOPLEFT", -2, 0)
        else  -- "right"
            frame:SetPoint("TOPLEFT", totemHost, "TOPRIGHT", 2, 0)
        end
        if frame.SetBackdropBorderColor then
            if DB.locked then
                frame:SetBackdropColor(0, 0, 0, 0)
                frame:SetBackdropBorderColor(0, 0, 0, 0)
            else
                frame:SetBackdropColor(0.05, 0.05, 0.07, 0.6)
                frame:SetBackdropBorderColor(0.85, 0.7, 0.2, 1)
            end
        end
    end

    if DB.showTotemSequence ~= false then
        placeAdjacent(StackBar, stack, "left")
    else
        StackBar:Hide()
    end
    if DB.showTotemStacks ~= false then
        placeAdjacent(TotemStackBar, tsSw, "right")
    else
        TotemStackBar:Hide()
    end

    -- Recall bar — standalone movable single-button frame.  Position
    -- is saved in DB.recallPoint.  Lock state mirrors the global Lock
    -- bar checkbox (drag enabled only when unlocked).
    do
        local rb = Bar.recallButton
        if rb and DB.showRecall ~= false then
            RecallBar:Show()
            local pad = BAR_PAD or 6
            local size = (BUTTON_SIZE or 36) + pad * 2
            RecallBar:SetSize(size, size)
            rb:ClearAllPoints()
            rb:SetPoint("TOPLEFT", RecallBar, "TOPLEFT", pad, -pad)
            RecallBar:SetScale(DB.scale or 1.0)
            RecallBar:ClearAllPoints()
            local p = DB.recallPoint or { "CENTER", "UIParent", "CENTER", 0, 0 }
            RecallBar:SetPoint(p[1], _G[p[2]] or UIParent, p[3], p[4] or 0, p[5] or 0)
            if RecallBar.SetBackdropBorderColor then
                if DB.locked then
                    RecallBar:SetBackdropColor(0, 0, 0, 0)
                    RecallBar:SetBackdropBorderColor(0, 0, 0, 0)
                    RecallBar:EnableMouse(false)
                    RecallBar:SetScript("OnDragStart", nil)
                    RecallBar:SetScript("OnDragStop", nil)
                else
                    RecallBar:SetBackdropColor(0.05, 0.05, 0.07, 0.6)
                    RecallBar:SetBackdropBorderColor(0.85, 0.7, 0.2, 1)
                    RecallBar:EnableMouse(true)
                    RecallBar:SetScript("OnDragStart", function(self) self:StartMoving() end)
                    RecallBar:SetScript("OnDragStop", function(self)
                        self:StopMovingOrSizing()
                        local pt, _, rpt, x, y = self:GetPoint()
                        DB.recallPoint = { pt, "UIParent", rpt, x, y }
                    end)
                end
            end
        else
            RecallBar:Hide()
        end
    end
end

------------------------------------------------------------------------
-- State tracker (cooldowns, missing alerts)
------------------------------------------------------------------------
local function totemActiveFor(element)
    local slot = NS.ELEMENT_SLOT[element]
    if not slot then return false end
    local have, _, startTime, duration = GetTotemInfo(slot)
    return have and duration and duration > 0, startTime, duration
end

local function findBuff(name)
    for i = 1, 40 do
        local n, _, _, _, dur, expiration = UnitBuff("player", i)
        if not n then return false end
        if n == name then return true, expiration, dur end
    end
    return false
end

local buttonSpellName  -- forward declaration; defined further down

-- Preview mode: when true, setMissing pretends we're in combat and that
-- every button is missing.  Used by the "Test Animations" button in the
-- options panel.  Toggled off automatically after 3 seconds.
local previewMode = false

-- Map a button to its DB.combatAlerts key.
local function alertKey(b)
    if b.kind == "totem" and b.element  then return "totem_" .. b.element end
    if b.kind == "util"  and b.utilSlot then return "util_"  .. b.utilSlot end
    if b.kind == "mh" or b.kind == "oh" or b.kind == "ls" then return b.kind end
end

-- Map a button to its alert-group name (matches DB.alertStyles).
local function buttonGroup(b)
    if b.kind == "mh" or b.kind == "oh" or b.kind == "ls" then return "imbue" end
    if b.kind == "util" then return "util" end
    if b.kind == "totem" then return "totem" end
end

local function setMissing(b, missing)
    local function stopAlerts()
        b.glow:Hide()
        if b.glowAnim:IsPlaying() then b.glowAnim:Stop() end
        if b.panicGlow then b.panicGlow:Hide() end
        if b.panicAnim and b.panicAnim:IsPlaying() then b.panicAnim:Stop() end
        if b.ringGlow then b.ringGlow:Hide() end
        if b.ringAnim and b.ringAnim:IsPlaying() then b.ringAnim:Stop() end
        if b.bounceAnim and b.bounceAnim:IsPlaying() then b.bounceAnim:Stop() end
        if b.shakeAnim  and b.shakeAnim:IsPlaying()  then b.shakeAnim:Stop()  end
        if b.flashAnim  and b.flashAnim:IsPlaying()  then b.flashAnim:Stop()  end
        b.icon:SetAlpha(1)
    end

    -- If the spell isn't learned yet, show the button greyed and skip alerts
    if not isKnown(buttonSpellName(b)) then
        stopAlerts()
        b.icon:SetDesaturated(true)
        b:SetAlpha(0.4)
        return
    end
    b:SetAlpha(1)

    -- All alerts are now per-slot and ONLY fire while in combat.  Each
    -- slot has its own toggle in DB.combatAlerts[alertKey(b)].
    local key        = alertKey(b)
    local perKindOn  = key and DB.combatAlerts and DB.combatAlerts[key] == true
    local panicAlert = missing and DB.alerts and (inCombat() or previewMode) and perKindOn

    if panicAlert then
        local group = buttonGroup(b)
        local styles = (DB.alertStyles and DB.alertStyles[group]) or {}
        local doMove  = styles.movement ~= false
        local doFlash = styles.flashes  ~= false

        b.glow:Hide()
        if b.glowAnim:IsPlaying() then b.glowAnim:Stop() end

        -- Helpers: start/stop each animation idempotently
        local function play(anim) if anim and not anim:IsPlaying() then anim:Play() end end
        local function stop(anim) if anim and anim:IsPlaying() then anim:Stop() end end

        ----------------------------------------------------------------
        -- Flashes
        ----------------------------------------------------------------
        if doFlash then
            local style = styles.flashesStyle or "glowring"
            if style == "glowring" then
                if b.panicGlow then b.panicGlow:SetVertexColor(1, 0.82, 0, 1); b.panicGlow:Show() end
                play(b.panicAnim)
                if b.ringGlow then b.ringGlow:SetVertexColor(1, 0.82, 0, 0.9); b.ringGlow:Show() end
                play(b.ringAnim)
                play(b.flashAnim)
            elseif style == "goldsolid" then
                if b.panicGlow then b.panicGlow:SetVertexColor(1, 0.82, 0, 1); b.panicGlow:Show() end
                play(b.panicAnim)
                if b.ringGlow then b.ringGlow:Hide() end; stop(b.ringAnim)
                stop(b.flashAnim); b.icon:SetAlpha(1)
            elseif style == "redpanic" then
                if b.panicGlow then b.panicGlow:SetVertexColor(1, 0.1, 0.1, 1); b.panicGlow:Show() end
                play(b.panicAnim)
                if b.ringGlow then b.ringGlow:Hide() end; stop(b.ringAnim)
                play(b.flashAnim)
            elseif style == "ringonly" then
                if b.panicGlow then b.panicGlow:Hide() end; stop(b.panicAnim)
                if b.ringGlow then b.ringGlow:SetVertexColor(1, 0.82, 0, 0.9); b.ringGlow:Show() end
                play(b.ringAnim)
                stop(b.flashAnim); b.icon:SetAlpha(1)
            elseif style == "subtle" then
                if b.panicGlow then b.panicGlow:SetVertexColor(1, 0.82, 0, 0.4); b.panicGlow:Show() end
                play(b.panicAnim)
                if b.ringGlow then b.ringGlow:Hide() end; stop(b.ringAnim)
                stop(b.flashAnim); b.icon:SetAlpha(1)
            end
        else
            if b.panicGlow then b.panicGlow:Hide() end; stop(b.panicAnim)
            if b.ringGlow then b.ringGlow:Hide() end; stop(b.ringAnim)
            stop(b.flashAnim); b.icon:SetAlpha(1)
        end

        ----------------------------------------------------------------
        -- Movement
        ----------------------------------------------------------------
        if doMove then
            local style = styles.movementStyle or "wobble"
            -- Stop everything first, then play the chosen ones.
            stop(b.bounceAnim); stop(b.shakeAnim); stop(b.pulseAnim); stop(b.spinAnim)
            if style == "wobble" then
                play(b.bounceAnim); play(b.shakeAnim)
            elseif style == "bounce" then
                play(b.bounceAnim)
            elseif style == "shake" then
                play(b.shakeAnim)
            elseif style == "pulse" then
                play(b.pulseAnim)
            elseif style == "spin" then
                play(b.spinAnim)
            end
        else
            stop(b.bounceAnim); stop(b.shakeAnim); stop(b.pulseAnim); stop(b.spinAnim)
        end

        b.icon:SetDesaturated(false)
    else
        stopAlerts()
        if b.pulseAnim and b.pulseAnim:IsPlaying() then b.pulseAnim:Stop() end
        if b.spinAnim  and b.spinAnim:IsPlaying()  then b.spinAnim:Stop()  end
        b.icon:SetDesaturated(false)
    end
end

local function applyCooldown(b, start, duration)
    if start and duration and duration > 0 then
        b.cooldown:SetCooldown(start, duration)
    else
        b.cooldown:Clear()
    end
end

function buttonSpellName(b)  -- assigning to forward-declared local
    if b.kind == "totem" then return DB.defaults[b.element]
    elseif b.kind == "mh"  then return DB.defaults.mh
    elseif b.kind == "oh"  then return DB.defaults.oh
    elseif b.kind == "util" then return DB.utilSelected and DB.utilSelected[b.utilSlot]
    elseif b.kind == "ls"   then return NS.LIGHTNING_SHIELD
    elseif b.kind == "recall" then return NS.TOTEMIC_RECALL
    elseif b.kind == "stack" then
        local set = DB.sets[DB.activeSet]
        return set and set[1] or nil
    elseif b.kind == "totemStack" then
        local stk = DB.totemStacks and DB.activeTotemStack and DB.totemStacks[DB.activeTotemStack]
        if stk then return stk.fire or stk.water or stk.earth or stk.air end
        return nil
    end
end

-- Returns true if the button's group is enabled via showTotems /
-- showUtility / showImbue toggles.
local function groupShown(b)
    if b.kind == "totem" or b.kind == "stack" then
        return DB.showTotems ~= false
    elseif b.kind == "util" then
        return DB.showUtility ~= false
    elseif b.kind == "mh" or b.kind == "oh" or b.kind == "ls" then
        return DB.showImbue ~= false
    end
    return true
end

local function refreshVisibility()
    -- Show/Hide on secure buttons is protected in combat; defer until combat
    -- ends.  PLAYER_REGEN_ENABLED triggers updateAll → refreshVisibility().
    if inCombat() then return end
    -- Layered visibility:
    --   1. Group toggle (Show on screen: Totems / Utility / Imbue).
    --   2. Per-button condition (LS learned, util slot assigned, etc.)
    local changed = false
    for _, b in ipairs(Buttons) do
        local shouldShow = groupShown(b)
        if shouldShow and b.kind == "ls" then
            shouldShow = isKnown(NS.LIGHTNING_SHIELD)
        end
        -- "Hide Unlearned Tooltips" — drop any button whose chosen spell
        -- isn't in the player's spellbook.  Empty util slots also hide
        -- (no spell to test means nothing to learn for that slot).
        -- Stack / Totem-stack-switcher aren't tied to a single spell, so
        -- they're never hidden by this rule.
        if shouldShow and DB.hideUnlearned
           and b.kind ~= "stack" and b.kind ~= "totemStack" then
            local sName = buttonSpellName(b)
            if not sName or not isKnown(sName) then
                shouldShow = false
            end
        end
        if shouldShow and not b:IsShown() then
            b:Show(); changed = true
        elseif not shouldShow and b:IsShown() then
            b:Hide(); changed = true
        end
    end
    if changed then layout() end
end

-- Render an integer seconds → short countdown string.
local function formatTime(seconds)
    if not seconds or seconds <= 0 then return "" end
    if seconds < 10 then return string.format("%.1f", seconds) end
    if seconds < 60 then return tostring(math.floor(seconds)) end
    if seconds < 3600 then return string.format("%dm", math.floor(seconds / 60)) end
    return string.format("%dh", math.floor(seconds / 3600))
end

local function updateAll()
    refreshVisibility()
    local now = GetTime()
    for _, b in ipairs(Buttons) do
        if b:IsShown() then
            local missing = false
            local durRemain, cdRemain = 0, 0
            -- Missing-state detection + duration tracking for the
            -- "running out" warning border.
            local durRemain, durTotal = 0, 0
            if b.kind == "totem" then
                local slot = NS.ELEMENT_SLOT[b.element]
                local have, totemName, st, dur = GetTotemInfo(slot)
                local displayed = DB.defaults[b.element]
                missing = not (have and totemName == displayed)
                if have and totemName == displayed and dur and dur > 0 then
                    durRemain = (st + dur) - now
                    durTotal  = dur
                end
                if displayed
                   and NS.NO_ALERT_TOTEMS
                   and NS.NO_ALERT_TOTEMS[displayed]
                   and not DB.enableSituationalTotemAlerts then
                    missing = false
                end
            elseif b.kind == "ls" then
                local present, exp, dur = findBuff(NS.LIGHTNING_SHIELD)
                missing = not present
                if present and exp and dur and dur > 0 then
                    durRemain = exp - now
                    durTotal  = dur
                end
            elseif b.kind == "mh" then
                local hasMH, mhExp = GetWeaponEnchantInfo()
                local equipped = GetInventoryItemID("player", 16) ~= nil
                missing = equipped and not hasMH
                if hasMH and mhExp then
                    durRemain = mhExp / 1000
                    durTotal  = 300  -- weapon imbues last ~5 min
                end
            elseif b.kind == "oh" then
                local _, _, _, _, hasOH, ohExp = GetWeaponEnchantInfo()
                local equipped = GetInventoryItemID("player", 17) ~= nil
                missing = equipped and not hasOH
                if hasOH and ohExp then
                    durRemain = ohExp / 1000
                    durTotal  = 300
                end
            elseif b.kind == "util" then
                local sp = DB.utilSelected and DB.utilSelected[b.utilSlot]
                if sp and NS.UTILITY_BUFFS and NS.UTILITY_BUFFS[sp] then
                    local present, exp, dur = findBuff(sp)
                    missing = not present
                    if present and exp and dur and dur > 0 then
                        durRemain = exp - now
                        durTotal  = dur
                    end
                end
            end
            if previewMode then
                missing  = true
                -- Preview overrides — show what a 1-minute buff with
                -- 30s cooldown would look like for this slot.
                durRemain, durTotal = 60, 60
            end

            -- "Running out" warning border @ ≤10% duration remaining
            local group   = buttonGroup(b)
            local styles  = group and DB.alertStyles and DB.alertStyles[group] or {}
            local warning = false
            if durRemain > 0 and durTotal > 0 and styles.warning ~= false then
                if (durRemain / durTotal) <= 0.10 then warning = true end
            end

            -- Yellow duration timer above the button
            if b.durTimer then
                if styles.duration ~= false and durRemain > 0 then
                    b.durTimer:SetText(formatTime(durRemain))
                else
                    b.durTimer:SetText("")
                end
            end
            if b.redBorder then
                if warning then
                    b.redBorder:Show()
                    if b.redBorderAnim and not b.redBorderAnim:IsPlaying() then
                        b.redBorderAnim:Play()
                    end
                else
                    b.redBorder:Hide()
                    if b.redBorderAnim and b.redBorderAnim:IsPlaying() then
                        b.redBorderAnim:Stop()
                    end
                end
            end

            -- Spell-cooldown swipe — only shown when this group's "CD Timer"
            -- option is enabled.  Preview mode shows a fake 30s cooldown.
            if styles.cd ~= false then
                if previewMode then
                    applyCooldown(b, GetTime(), 30)
                else
                    local sName = buttonSpellName(b)
                    if sName and GetSpellCooldown then
                        local cdStart, cdDur = GetSpellCooldown(sName)
                        if cdStart and cdDur and cdDur > 0 then
                            applyCooldown(b, cdStart, cdDur)
                        else
                            applyCooldown(b, nil, nil)
                        end
                    else
                        applyCooldown(b, nil, nil)
                    end
                end
            else
                applyCooldown(b, nil, nil)
            end

            -- Duration text overlays are unused now; keep them empty.
            if b.durText then b.durText:SetText("") end
            if b.cdText  then b.cdText:SetText("")  end

            -- setMissing also handles the "spell not learned" grey-out
            setMissing(b, missing)
        end
    end
end

------------------------------------------------------------------------
-- Combat-end queue: changes deferred during combat
------------------------------------------------------------------------
local pending = {}
local function flushPending()
    for _, fn in ipairs(pending) do pcall(fn) end
    wipe(pending)
end

------------------------------------------------------------------------
-- Public API (used by Options.lua)
------------------------------------------------------------------------
local function refreshAllButtons()
    -- SetAttribute on secure buttons is allowed in combat in Classic Era,
    -- so don't gate this. Visibility changes are gated separately inside
    -- refreshVisibility().
    for _, b in ipairs(Buttons) do
        if b.kind == "totem" then
            setButtonSpell(b, DB.defaults[b.element])
        elseif b.kind == "mh" then
            setImbueButton(b, 16, DB.defaults.mh, DB.defaults.mh2)
        elseif b.kind == "oh" then
            setImbueButton(b, 17, DB.defaults.oh, DB.defaults.oh2)
        elseif b.kind == "stack" then
            applyStack(b)
        elseif b.kind == "util" then
            local sp = DB.utilSelected and DB.utilSelected[b.utilSlot]
            if sp then
                setButtonSpell(b, sp)
            else
                -- Slot empty: clear secure attrs so click doesn't cast stale spell
                clearButton(b)
            end
        end
    end
    updateAll()
    return true
end

local function totemToElement(totemName)
    for element, list in pairs(NS.TOTEMS) do
        for _, n in ipairs(list) do
            if n == totemName then return element end
        end
    end
end

-- Apply a saved Totem Stack — overwrites DB.defaults for the 4 elements,
-- updates each element button to show the new icon, and refreshes the
-- TotemStackBar switcher's own icon.
function useTotemStack(name)
    local stk = DB.totemStacks and DB.totemStacks[name]
    if not stk then return end
    DB.activeTotemStack = name
    for _, elem in ipairs(NS.ELEMENT_ORDER) do
        if stk[elem] then DB.defaults[elem] = stk[elem] end
    end
    -- If this totem stack has a linked utility stack, apply it too
    local linked = DB.linkedUtil and DB.linkedUtil[name]
    if linked and applyUtilStack then applyUtilStack(linked) end
    if NS.API and NS.API.refresh then NS.API.refresh() end
    if refreshTotemStackSwitchIcon then refreshTotemStackSwitchIcon() end
end

function cycleTotemStack()
    local names = {}
    for n in pairs(DB.totemStacks or {}) do names[#names + 1] = n end
    if #names == 0 then
        print("|cffffd000TTB:|r no Totem Stacks saved.")
        return
    end
    table.sort(names)
    local idx = 0
    for i, n in ipairs(names) do
        if n == DB.activeTotemStack then idx = i; break end
    end
    local nextName = names[(idx % #names) + 1]
    useTotemStack(nextName)
    print("|cff00ff88TTB:|r totem stack → '" .. nextName .. "'")
end

function totemStackMenu(button)
    local items = { { text = "TOTEM STACKS", isTitle = true, notCheckable = true } }
    local sorted = {}
    for n in pairs(DB.totemStacks or {}) do sorted[#sorted + 1] = n end
    table.sort(sorted)
    if #sorted == 0 then
        items[#items + 1] = {
            text = "(no totem stacks saved — use /ttb to add)",
            disabled = true, notCheckable = true,
        }
    else
        for _, name in ipairs(sorted) do
            local stk = DB.totemStacks[name]
            local previewIcon = ""
            if stk then
                local firstSpell = stk.fire or stk.water or stk.earth or stk.air
                if firstSpell then
                    local _, _, icon = GetSpellInfo(firstSpell)
                    if icon then
                        previewIcon = "|T" .. icon .. ":20:20:0:0:64:64:4:60:4:60|t  "
                    end
                end
            end
            items[#items + 1] = {
                text = previewIcon .. name,
                checked = (DB.activeTotemStack == name),
                func = function() useTotemStack(name) end,
            }
        end
    end
    showMenu(button, items)
end

-- Apply a saved util stack: writes to DB.utilSelected[1..2].  Each entry
-- in the stack must be either a known+enabled utility spell name, or nil
-- (which clears that slot).  Assigns to the forward-declared `applyUtilStack`.
function applyUtilStack(name)
    if not name then return end
    local stk = DB.utilStacks and DB.utilStacks[name]
    if not stk then return end
    DB.utilSelected = DB.utilSelected or {}
    DB.utilSelected[1] = stk[1] or nil
    DB.utilSelected[2] = stk[2] or nil
    -- Vice-versa: if this util stack has a paired totem stack, load it too.
    -- Guard against ping-pong: only apply if the totem stack isn't already
    -- the active one.
    local pairedTotem = DB.linkedTotem and DB.linkedTotem[name]
    if pairedTotem and pairedTotem ~= DB.activeTotemStack
       and useTotemStack and DB.totemStacks and DB.totemStacks[pairedTotem] then
        useTotemStack(pairedTotem)
    end
end

local function useStack(setName)
    local set = DB.sets[setName]
    if not set then return false end
    DB.activeSet = setName
    -- Sync per-element defaults so element buttons mirror this stack
    for _, totem in ipairs(set) do
        local elem = totemToElement(totem)
        if elem then DB.defaults[elem] = totem end
    end
    -- (Linked utility stacks are now applied through Totem Stacks, not
    -- Custom Totem Sequences.)
    refreshAllButtons()
    return true
end

-- Build / update a real WoW macro that invokes the bar's Stack button.
-- The user drags this macro onto an action bar slot.  Modifier keys
-- (Shift) propagate through /click, so Shift+actionbar key still cycles.
local STACK_MACRO_NAME = "TTB Stack"

local function createStackMacro()
    if inCombat() then
        print("|cffffd000TTB:|r can't edit macros in combat.")
        return
    end
    local body = "#showtooltip\n/click TotemTommysBars_Stack LeftButton"
    -- Pick an icon: first totem of the active stack, fallback to a generic.
    local set = DB.sets[DB.activeSet]
    local iconID = (set and set[1] and select(3, GetSpellInfo(set[1]))) or 136102
    local idx = GetMacroIndexByName(STACK_MACRO_NAME)
    if idx and idx > 0 then
        EditMacro(idx, STACK_MACRO_NAME, iconID, body)
        print("|cff00ff88TTB:|r updated macro '" .. STACK_MACRO_NAME .. "'.")
    else
        local n = CreateMacro(STACK_MACRO_NAME, iconID, body, false)
        if n then
            print("|cff00ff88TTB:|r created macro '" .. STACK_MACRO_NAME
                .. "'.  Open |cffaaccff/macro|r and drag it onto your action bar.")
        else
            print("|cffff5555TTB:|r couldn't create macro (account macro slots full?).")
        end
    end
end

-- Bindings: apply user's saved key→action mappings.
-- Uses SetOverrideBindingClick so the binding is per-character at runtime
-- and doesn't persist into Blizzard's account-wide binding file.
local bindingOwner = CreateFrame("Frame")  -- a frame that "owns" our overrides

local function clearBindings()
    if ClearOverrideBindings then ClearOverrideBindings(bindingOwner) end
end

local function applyBindings()
    if inCombat() then return end
    clearBindings()
    if not DB.bindings then return end
    for _, action in ipairs(NS.BINDING_ACTIONS) do
        local key = DB.bindings[action.id]
        if key and key ~= "" then
            SetOverrideBindingClick(bindingOwner, true, key, action.button, "LeftButton")
        end
    end
end

local function setBinding(actionId, key)
    if inCombat() then
        print("|cffffd000TTB:|r can't change keybinds in combat.")
        return false
    end
    DB.bindings = DB.bindings or {}
    -- If this key was bound to another action, clear that first
    for id, k in pairs(DB.bindings) do
        if k == key and id ~= actionId then DB.bindings[id] = nil end
    end
    DB.bindings[actionId] = key
    applyBindings()
    return true
end

local function clearBinding(actionId)
    if inCombat() then return end
    if DB.bindings then DB.bindings[actionId] = nil end
    applyBindings()
end

local function useUtilStack(name)
    applyUtilStack(name)
    refreshAllButtons()
end

local function previewAlerts()
    if previewMode then return end  -- already running
    previewMode = true
    updateAll()
    if C_Timer and C_Timer.After then
        C_Timer.After(3, function()
            previewMode = false
            updateAll()
        end)
    end
end

------------------------------------------------------------------------
-- Master bar visibility — shift-clicked from the minimap button.
------------------------------------------------------------------------
local function toggleBars()
    if inCombat() then
        print("|cffffd000TTB:|r can't toggle bars in combat.")
        return
    end
    DB.barsHidden = not DB.barsHidden
    layout()
    print("|cff00ff88TTB:|r bars " .. (DB.barsHidden and "hidden" or "shown") .. ".")
end

------------------------------------------------------------------------
-- Minimap button.  Sits on the minimap rim at the user-configured
-- angle.  Drag with right-click to reposition.  Left-click opens the
-- options panel; shift+left-click toggles master bar visibility.
------------------------------------------------------------------------
local MinimapBtn = CreateFrame("Button", "TotemTommysBarsMinimapButton", Minimap)
MinimapBtn:SetSize(31, 31)
MinimapBtn:SetFrameStrata("MEDIUM")
MinimapBtn:SetFrameLevel(8)
MinimapBtn:RegisterForClicks("AnyUp")
MinimapBtn:SetMovable(true)

-- Icon (a Shaman-themed spell icon)
local mmIcon = MinimapBtn:CreateTexture(nil, "BACKGROUND")
mmIcon:SetSize(20, 20)
mmIcon:SetTexture("Interface\\Icons\\Spell_Nature_Lightning")
mmIcon:SetPoint("CENTER", MinimapBtn, "CENTER", 0, 1)
mmIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

-- Standard gold minimap-button ring (Blizzard tracking-icon border)
local mmRing = MinimapBtn:CreateTexture(nil, "OVERLAY")
mmRing:SetSize(53, 53)
mmRing:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
mmRing:SetPoint("TOPLEFT")

local mmHighlight = MinimapBtn:CreateTexture(nil, "HIGHLIGHT")
mmHighlight:SetTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
mmHighlight:SetBlendMode("ADD")
mmHighlight:SetAllPoints(MinimapBtn)

-- Position along the minimap rim at the saved angle.
local function positionMinimapBtn()
    local angle = (DB and DB.minimap and DB.minimap.angle) or 215
    local rad = math.rad(angle)
    -- Minimap circle radius ~ 80 px from center.
    local radius = 80
    local x = math.cos(rad) * radius
    local y = math.sin(rad) * radius
    MinimapBtn:ClearAllPoints()
    MinimapBtn:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

-- Drag handler: while dragging, compute angle from cursor relative
-- to minimap center and pin the button to that point on the rim.
MinimapBtn:RegisterForDrag("RightButton")
MinimapBtn:SetScript("OnDragStart", function(self)
    self.dragging = true
    self:SetScript("OnUpdate", function()
        local mx, my = Minimap:GetCenter()
        local scale = Minimap:GetEffectiveScale()
        local cx, cy = GetCursorPosition()
        cx, cy = cx / scale, cy / scale
        local angle = math.deg(math.atan2(cy - my, cx - mx))
        DB.minimap = DB.minimap or {}
        DB.minimap.angle = angle
        positionMinimapBtn()
    end)
end)
MinimapBtn:SetScript("OnDragStop", function(self)
    self.dragging = nil
    self:SetScript("OnUpdate", nil)
end)

MinimapBtn:SetScript("OnClick", function(self, button)
    if button == "LeftButton" then
        if IsShiftKeyDown() then
            toggleBars()
        else
            if NS.API and NS.API.openOptions then NS.API.openOptions() end
        end
    end
end)

MinimapBtn:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:SetText("|cffffd200Totem Tommys Bars|r", 1, 1, 1)
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("|cff7ec8ffLeft-click:|r open options", 0.9, 0.9, 0.9)
    GameTooltip:AddLine("|cff7ec8ffShift-click:|r hide / show all bars", 0.9, 0.9, 0.9)
    GameTooltip:AddLine("|cff7ec8ffRight-click + drag:|r reposition", 0.9, 0.9, 0.9)
    if DB and DB.barsHidden then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("|cffff5555Bars are currently hidden.|r", 1, 0.4, 0.4)
    end
    GameTooltip:Show()
end)
MinimapBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

------------------------------------------------------------------------
-- LibDataBroker launcher + LibDBIcon registration.
--
-- Why: button-collector addons (Bagnon Buttons, MBB, ChocolateBar,
-- Titan Panel, etc.) scan for minimap buttons.  If they find ours and
-- it isn't registered through LibDataBroker, they show a "please use
-- LibDBIcon" warning instead of our actual tooltip.  Publishing an
-- LDB launcher gives those addons our title, icon, click handlers and
-- tooltip metadata.
--
-- We don't bundle libs.  Runtime-detect via LibStub: if LDB is present
-- (almost always, when a collector is loaded), we publish a launcher.
-- If LibDBIcon is also present, it manages a native minimap button for
-- us — in that case we hide our custom one to avoid duplication.
------------------------------------------------------------------------
local function ssbTooltip(tooltip)
    tooltip:ClearLines()
    tooltip:AddLine("|cffffd200Totem Tommys Bars|r")
    tooltip:AddLine(" ")
    tooltip:AddLine("|cff7ec8ffLeft-click:|r open options", 0.9, 0.9, 0.9)
    tooltip:AddLine("|cff7ec8ffShift-click:|r hide / show all bars", 0.9, 0.9, 0.9)
    tooltip:AddLine("|cff7ec8ffRight-click + drag:|r reposition", 0.9, 0.9, 0.9)
    if DB and DB.barsHidden then
        tooltip:AddLine(" ")
        tooltip:AddLine("|cffff5555Bars are currently hidden.|r", 1, 0.4, 0.4)
    end
end

if LibStub then
    local LDB = LibStub:GetLibrary("LibDataBroker-1.1", true)
    if LDB then
        local launcher = LDB:NewDataObject("TotemTommysBars", {
            type  = "launcher",
            label = "Totem Tommys Bars",
            text  = "Totem Tommys Bars",
            icon  = "Interface\\Icons\\Spell_Nature_Lightning",
            OnClick = function(_, button)
                if button == "LeftButton" then
                    if IsShiftKeyDown() then
                        toggleBars()
                    else
                        if NS.API and NS.API.openOptions then NS.API.openOptions() end
                    end
                end
            end,
            OnTooltipShow = ssbTooltip,
            OnEnter = function(self)
                GameTooltip:SetOwner(self, "ANCHOR_LEFT")
                ssbTooltip(GameTooltip)
                GameTooltip:Show()
            end,
            OnLeave = function() GameTooltip:Hide() end,
        })

        local LDBIcon = LibStub:GetLibrary("LibDBIcon-1.0", true)
        if LDBIcon and launcher then
            -- Use a separate SV bucket from our `minimap.angle` so
            -- LibDBIcon's drag state doesn't clobber ours.  Created
            -- lazily here; persists in TotemTommysBarsDB.
            TotemTommysBarsDB = TotemTommysBarsDB or {}
            TotemTommysBarsDB.minimapLDB = TotemTommysBarsDB.minimapLDB or { hide = false }
            LDBIcon:Register("TotemTommysBars", launcher, TotemTommysBarsDB.minimapLDB)
            -- LibDBIcon now owns the on-screen minimap button — hide
            -- our hand-rolled one to avoid two buttons on the rim.
            MinimapBtn:Hide()
            MinimapBtn:UnregisterAllEvents()
            MinimapBtn:SetScript("OnUpdate", nil)
        end
    end
end

NS.API = {
    getDB     = function() return DB end,
    layout    = function() layout() end,
    refresh   = refreshAllButtons,
    updateAll = function() updateAll() end,
    inCombat  = inCombat,
    useStack  = useStack,
    useUtilStack = useUtilStack,
    useTotemStack = useTotemStack,
    createStackMacro = createStackMacro,
    setBinding   = setBinding,
    clearBinding = clearBinding,
    applyBindings = applyBindings,
    previewAlerts = previewAlerts,
    toggleBars   = toggleBars,
    positionMinimapBtn = positionMinimapBtn,
    resetPoint = function()
        DB.point      = deepcopy(NS.DEFAULTS.point)
        DB.imbuePoint = deepcopy(NS.DEFAULTS.imbuePoint)
        DB.utilPoint  = deepcopy(NS.DEFAULTS.utilPoint)
        layout()
    end,
    -- Full reset to factory defaults — fires from the "Default Settings"
    -- button in the options panel.  Wipes every preference (scales,
    -- layouts, alert styles, modifier, combine flags, show flags,
    -- situational toggle, etc.) and every bar's screen position, then
    -- re-applies NS.DEFAULTS.  PRESERVES the user's saved Sequences,
    -- Totem Stacks, Utility Stacks and their pairings.
    resetAllDefaults = function()
        if inCombat() then
            print("|cffffd000TTB:|r can't reset to defaults in combat.")
            return
        end
        -- Stash the per-character saved collections so they survive.
        local savedSets       = DB.sets
        local stackIcons      = DB.stackIcons
        local setReset        = DB.setReset
        local activeSet       = DB.activeSet
        local utilStacks      = DB.utilStacks
        local linkedUtil      = DB.linkedUtil
        local linkedTotem     = DB.linkedTotem
        local totemStacks     = DB.totemStacks
        local totemStackIcons = DB.totemStackIcons
        local activeTotemStack = DB.activeTotemStack
        local bindings        = DB.bindings  -- legacy bindings — keep
        local minimapLDB      = DB.minimapLDB
        local userDefPoints   = DB.userDefaultPoints  -- /ttb savepos snapshot

        -- Wipe every other key, then re-seed from defaults.
        for k in pairs(DB) do DB[k] = nil end
        for k, v in pairs(NS.DEFAULTS) do DB[k] = deepcopy(v) end

        -- Restore the preserved collections.
        DB.sets             = savedSets             or deepcopy(NS.DEFAULT_SETS)
        DB.stackIcons       = stackIcons            or {}
        DB.setReset         = setReset              or {}
        DB.activeSet        = activeSet             or "DPS"
        DB.utilStacks       = utilStacks            or {}
        DB.linkedUtil       = linkedUtil            or {}
        DB.linkedTotem      = linkedTotem           or {}
        DB.totemStacks      = totemStacks           or {}
        DB.totemStackIcons  = totemStackIcons       or {}
        DB.activeTotemStack = activeTotemStack
        DB.bindings         = bindings              or {}
        DB.minimapLDB       = minimapLDB
        DB.userDefaultPoints = userDefPoints

        -- Re-anchor each bar.  If the user saved their own preferred
        -- layout with `/ttb savepos`, use that (we re-stashed it just
        -- above); otherwise use the factory defaults from NS.DEFAULTS.
        local custom = DB.userDefaultPoints
        if custom then
            DB.point       = deepcopy(custom.point)       or deepcopy(NS.DEFAULTS.point)
            DB.imbuePoint  = deepcopy(custom.imbuePoint)  or deepcopy(NS.DEFAULTS.imbuePoint)
            DB.utilPoint   = deepcopy(custom.utilPoint)   or deepcopy(NS.DEFAULTS.utilPoint)
            DB.recallPoint = deepcopy(custom.recallPoint) or deepcopy(NS.DEFAULTS.recallPoint)
        else
            DB.point       = deepcopy(NS.DEFAULTS.point)
            DB.imbuePoint  = deepcopy(NS.DEFAULTS.imbuePoint)
            DB.utilPoint   = deepcopy(NS.DEFAULTS.utilPoint)
            DB.recallPoint = deepcopy(NS.DEFAULTS.recallPoint)
        end

        -- Re-render everything from the new state.
        refreshAllButtons()
        for _, b in ipairs(Buttons) do
            if b.kind == "totem" or b.kind == "util" or b.kind == "ls"
               or b.kind == "stack" or b.kind == "totemStack" then
                applyCycleModSecure(b)
            end
        end
        layout()
        updateAll()
        positionMinimapBtn()
        print("|cff00ff88TTB:|r all settings restored to defaults. (Saved Sequences / Stacks preserved.)")
    end,
    -- Re-apply the cycle-modifier secure suppression to every spell
    -- button.  Called by the options panel when the user changes the
    -- "Main Cycle Modifier" dropdown.
    refreshCycleModifier = function()
        for _, b in ipairs(Buttons) do
            if b.kind == "totem" or b.kind == "util" or b.kind == "ls"
               or b.kind == "stack" or b.kind == "totemStack" then
                applyCycleModSecure(b)
            end
        end
    end,
}

------------------------------------------------------------------------
-- Global cycle entry points for Bindings.xml.
-- Each <Binding>'s script body fires this table's methods directly,
-- so cycling via a "Cycle X" keybind doesn't have to round-trip
-- through a hidden secure button.
------------------------------------------------------------------------
local function cycleElementByName(element)
    local b = _G["TotemTommysBars_Totem_" .. element]
    if b then cycleElement(element, b) end
end

_G["TotemTommysBarsCycle"] = {
    sequence = function()
        if Bar and Bar.stackButton then cycleStack(Bar.stackButton) end
    end,
    totemStack = function() cycleTotemStack() end,
    fire  = function() cycleElementByName("fire")  end,
    water = function() cycleElementByName("water") end,
    earth = function() cycleElementByName("earth") end,
    air   = function() cycleElementByName("air")   end,
    util1 = function()
        local b = _G["TotemTommysBars_Util_1"]
        if b then cycleUtility(b) end
    end,
    util2 = function()
        local b = _G["TotemTommysBars_Util_2"]
        if b then cycleUtility(b) end
    end,
}

------------------------------------------------------------------------
-- Slash commands
------------------------------------------------------------------------
local function printHelp()
    print("|cff00ff88Totem Tommys Bars|r")
    print("  /ttb lock        — toggle lock (drag to move)")
    print("  /ttb layout row|stacked|grid")
    print("  /ttb scale 0.8   — bar scale")
    print("  /ttb alerts      — toggle missing-buff flash")
    print("  /ttb sets        — list saved totem stacks")
    print("  /ttb set add <name> <t1>;<t2>;<t3>;<t4>")
    print("  /ttb set del <name>")
    print("  /ttb set use <name>")
    print("  /ttb reset       — reset position")
end

SLASH_TTB1 = "/ttb"
SlashCmdList.TTB = function(msg)
    msg = msg or ""
    local cmd, rest = msg:match("^(%S+)%s*(.-)$")
    cmd = cmd and cmd:lower() or ""
    if cmd == "" or cmd == "config" or cmd == "options" or cmd == "opts" then
        if NS.API and NS.API.openOptions then
            NS.API.openOptions()
        else
            printHelp()
        end
    elseif cmd == "help" then
        printHelp()
    elseif cmd == "lock" then
        DB.locked = not DB.locked
        layout()
        print("|cff00ff88TTB:|r locked = " .. tostring(DB.locked))
    elseif cmd == "layout" then
        if rest == "row" or rest == "stacked" or rest == "grid" then
            DB.layout = rest
            layout()
        else
            print("|cff00ff88TTB:|r layout = " .. DB.layout)
        end
    elseif cmd == "scale" then
        local n = tonumber(rest)
        if n and n >= 0.5 and n <= 2 then
            DB.scale = n
            layout()
        else
            print("|cff00ff88TTB:|r scale = " .. DB.scale .. " (0.5–2.0)")
        end
    elseif cmd == "alerts" then
        DB.alerts = not DB.alerts
        print("|cff00ff88TTB:|r alerts = " .. tostring(DB.alerts))
        updateAll()
    elseif cmd == "sets" then
        print("|cff00ff88TTB:|r saved stacks:")
        for name, set in pairs(DB.sets) do
            local marker = (DB.activeSet == name) and " *" or ""
            print("  - " .. name .. marker .. ": " .. table.concat(set, ", "))
        end
    elseif cmd == "set" then
        local sub, args = rest:match("^(%S+)%s*(.-)$")
        if sub == "add" then
            local name, totems = args:match("^(%S+)%s+(.+)$")
            if not name or not totems then
                print("|cffff5555TTB:|r usage: /ttb set add <name> <t1>;<t2>;<t3>;<t4>")
                return
            end
            local list = {}
            for t in (totems .. ";"):gmatch("([^;]+);") do
                list[#list + 1] = t:match("^%s*(.-)%s*$")
            end
            DB.sets[name] = list
            print("|cff00ff88TTB:|r saved stack '" .. name .. "'")
            if not inCombat() then applyStack(Bar.stackButton) end
        elseif sub == "del" then
            DB.sets[args] = nil
            print("|cff00ff88TTB:|r deleted '" .. args .. "'")
        elseif sub == "use" then
            if DB.sets[args] then
                DB.activeSet = args
                if not inCombat() then applyStack(Bar.stackButton) end
                print("|cff00ff88TTB:|r active stack = " .. args)
            else
                print("|cffff5555TTB:|r no such set: " .. args)
            end
        else
            print("|cffff5555TTB:|r set add|del|use")
        end
    elseif cmd == "reset" then
        DB.point = deepcopy(NS.DEFAULTS.point)
        DB.scale = 1
        layout()
    elseif cmd == "pos" or cmd == "coords" then
        -- Print every bar's current anchor in a copy-pastable form so
        -- the user can either share the values OR paste them back as
        -- defaults in Data.lua.
        local function fmt(p)
            if not p then return "(unset)" end
            return string.format('{ "%s", "%s", "%s", %s, %s }',
                tostring(p[1]), tostring(p[2]), tostring(p[3]),
                tostring(p[4]), tostring(p[5]))
        end
        print("|cff00ff88TTB:|r current bar positions —")
        print("  point       = " .. fmt(DB.point))
        print("  imbuePoint  = " .. fmt(DB.imbuePoint))
        print("  utilPoint   = " .. fmt(DB.utilPoint))
        print("  recallPoint = " .. fmt(DB.recallPoint))
        print("Use |cff7ec8ff/ttb savepos|r to bake these as your 'Default Settings' positions.")
    elseif cmd == "savepos" then
        -- Snapshot current positions into DB.userDefaultPoints — the
        -- "Default Settings" button (resetAllDefaults) will use these
        -- instead of the hard-coded NS.DEFAULTS values when present.
        DB.userDefaultPoints = {
            point       = deepcopy(DB.point),
            imbuePoint  = deepcopy(DB.imbuePoint),
            utilPoint   = deepcopy(DB.utilPoint),
            recallPoint = deepcopy(DB.recallPoint),
        }
        print("|cff00ff88TTB:|r current bar positions saved as your personal defaults. 'Default Settings' will now snap to here.")
    elseif cmd == "clearpos" then
        DB.userDefaultPoints = nil
        print("|cff00ff88TTB:|r personal default positions cleared — reverting to factory defaults.")
    elseif cmd == "macro" then
        createStackMacro()
    else
        printHelp()
    end
end

------------------------------------------------------------------------
-- Events
------------------------------------------------------------------------
local ev = CreateFrame("Frame")
ev:RegisterEvent("ADDON_LOADED")
ev:RegisterEvent("PLAYER_LOGIN")
ev:RegisterEvent("PLAYER_ENTERING_WORLD")
ev:RegisterEvent("UNIT_AURA")
ev:RegisterEvent("UNIT_INVENTORY_CHANGED")
ev:RegisterEvent("PLAYER_TOTEM_UPDATE")
ev:RegisterEvent("PLAYER_REGEN_ENABLED")
ev:RegisterEvent("PLAYER_REGEN_DISABLED")
ev:RegisterEvent("LEARNED_SPELL_IN_TAB")
ev:RegisterEvent("SPELLS_CHANGED")
ev:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
ev:RegisterEvent("SPELL_UPDATE_COOLDOWN")

ev:SetScript("OnEvent", function(_, event, arg1, arg2, arg3)
    if event == "ADDON_LOADED" and arg1 == addonName then
        initDB()
    elseif event == "PLAYER_LOGIN" then
        if not isShaman() then
            Bar:Hide()
            if MinimapBtn then MinimapBtn:Hide() end
            return
        end
        buildButtons()
        layout()
        updateAll()
        applyBindings()
        positionMinimapBtn()
        print("|cff00ff88Totem Tommys Bars|r loaded.  /ttb for options.")
    elseif event == "PLAYER_ENTERING_WORLD" then
        updateAll()
    elseif event == "UNIT_AURA" and arg1 == "player" then
        updateAll()
    elseif event == "UNIT_INVENTORY_CHANGED" and arg1 == "player" then
        updateAll()
    elseif event == "PLAYER_TOTEM_UPDATE" then
        updateAll()
    elseif event == "PLAYER_REGEN_DISABLED" then
        -- entering combat: re-evaluate so totem alerts stop and
        -- LS / MH / OH alerts start if those are missing.
        updateAll()
        -- One-shot audible warning if entering combat with anything that
        -- has its alert toggle enabled AND is currently missing AND its
        -- group's Audio sub-style is enabled.
        if DB.alerts then
            local ca = DB.combatAlerts or {}
            local styles = DB.alertStyles or {}
            local function audioOn(g)
                return styles[g] and styles[g].audio ~= false
            end

            local missingImbue, missingUtil, missingTotem = false, false, false
            local hasMH, _, _, _, hasOH = GetWeaponEnchantInfo()
            if ca.mh and GetInventoryItemID("player", 16) and not hasMH then missingImbue = true end
            if ca.oh and GetInventoryItemID("player", 17) and not hasOH then missingImbue = true end
            if ca.ls and isKnown(NS.LIGHTNING_SHIELD) and not findBuff(NS.LIGHTNING_SHIELD) then
                missingImbue = true
            end
            for elem, slot in pairs(NS.ELEMENT_SLOT) do
                if ca["totem_" .. elem] then
                    local have = GetTotemInfo(slot)
                    local def = DB.defaults and DB.defaults[elem]
                    if def and not have then missingTotem = true end
                end
            end
            for s = 1, 2 do
                if ca["util_" .. s] then
                    local sp = DB.utilSelected and DB.utilSelected[s]
                    if sp and NS.UTILITY_BUFFS and NS.UTILITY_BUFFS[sp]
                       and not findBuff(sp) then
                        missingUtil = true
                    end
                end
            end

            -- Pick a sound ID from the first triggering group's audio style.
            local function soundIDFor(g)
                local key = styles[g] and styles[g].audioStyle or "raidwarning"
                for _, entry in ipairs(NS.AUDIO_STYLES or {}) do
                    if entry.key == key then return entry.soundID end
                end
                return 8959
            end
            local soundToPlay
            if     missingImbue and audioOn("imbue") then soundToPlay = soundIDFor("imbue")
            elseif missingUtil  and audioOn("util")  then soundToPlay = soundIDFor("util")
            elseif missingTotem and audioOn("totem") then soundToPlay = soundIDFor("totem") end
            if soundToPlay and PlaySound then
                pcall(PlaySound, soundToPlay, "Master")
            end
        end
    elseif event == "PLAYER_REGEN_ENABLED" then
        flushPending()
        updateAll()
    elseif event == "LEARNED_SPELL_IN_TAB" or event == "SPELLS_CHANGED" then
        if not inCombat() then
            -- Re-sync defaults in case we just learned the chosen spell
            if NS.API and NS.API.refresh then NS.API.refresh() end
            updateAll()
        end
    elseif event == "SPELL_UPDATE_COOLDOWN" then
        -- Refresh the cooldown swipe immediately when any spell goes on or
        -- off cooldown (includes the GCD on every click).
        updateAll()
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" and arg1 == "player" then
        -- Sync the Stack button's seqStep to the actual castsequence
        -- position by matching the spell that just landed against the
        -- active stack's totem list.
        local stk = Bar.stackButton
        local set = stk and DB.sets and DB.sets[DB.activeSet]
        if stk and set then
            local spellID = arg3
            local castName = spellID and GetSpellInfo(spellID) or nil
            if castName then
                for i, totem in ipairs(set) do
                    if totem == castName then
                        stk.seqStep = (i < #set) and i or 0
                        stk.lastClick = GetTime()
                        updateStackIcon(stk)
                        break
                    end
                end
            end
        end
    end
end)

-- Periodic refresh for totem timers (cooldown swipe doesn't auto-refresh
-- the missing-flag without an event), and idle-reset of the stack icon.
local timer = 0
Bar:HookScript("OnUpdate", function(_, elapsed)
    timer = timer + elapsed
    if timer > 0.5 then
        timer = 0
        updateAll()
        local stk = Bar.stackButton
        if stk and stk.seqStep and stk.seqStep > 0 and stk.lastClick
           and (GetTime() - stk.lastClick) > sequenceResetSeconds(DB.activeSet) then
            stk.seqStep = 0
            updateStackIcon(stk)
        end
    end
end)
