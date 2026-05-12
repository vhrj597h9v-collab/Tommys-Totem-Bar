-- Data.lua
-- Classic Era (1.15.x) spell lists for Shaman.
-- Spell names are localized server-side; these strings match enUS / enGB.
-- For other locales, edit the strings or use GetSpellInfo(<id>) to fetch.

local _, NS = ...

------------------------------------------------------------------------
-- Display strings for Blizzard's Key Bindings UI.
-- These MUST be true globals (use _G[] explicit form to be safe).
-- Pattern lifted from Details! Damage Meter:
--   * The `category="Totem Tommys Bars"` attribute on each <Binding>
--     in Bindings.xml is used verbatim as the section title — Blizzard
--     does NOT look up a `BINDING_CATEGORY_*` global for it.
--   * `header="TTB_HEADER_*"` attributes create sub-group dividers
--     within the category; their display text comes from
--     `BINDING_HEADER_TTB_HEADER_*` globals below.
--   * Each binding row's label comes from `BINDING_NAME_<name>`.
------------------------------------------------------------------------
_G["BINDING_HEADER_TTB_HEADER_CYCLEMOD"]   = "Main Cycle Modifier — Affects All"
_G["BINDING_HEADER_TTB_HEADER_SEQUENCE"]   = "Sequence"
_G["BINDING_HEADER_TTB_HEADER_TOTEMS"]     = "Element Totems"
_G["BINDING_HEADER_TTB_HEADER_TOTEMSTACK"] = "Totem Stack"
_G["BINDING_HEADER_TTB_HEADER_IMBUES"]     = "Imbues & Shield"
_G["BINDING_HEADER_TTB_HEADER_UTILITY"]    = "Utility Slots"

_G["BINDING_NAME_TOTEMTOMMYSBARS_CYCLE_MOD_NOTE"] = "(info row — set the modifier in addon options, or set individual modifier binds below)"

_G["BINDING_NAME_TOTEMTOMMYSBARS_STACK"]          = "Drop Sequence Totem"
_G["BINDING_NAME_TOTEMTOMMYSBARS_CYCLE_SEQUENCE"] = "Cycle Sequence"

_G["BINDING_NAME_TOTEMTOMMYSBARS_TOTEM_FIRE"]   = "Drop Fire Totem"
_G["BINDING_NAME_TOTEMTOMMYSBARS_CYCLE_FIRE"]   = "Cycle Fire Totem"
_G["BINDING_NAME_TOTEMTOMMYSBARS_TOTEM_WATER"]  = "Drop Water Totem"
_G["BINDING_NAME_TOTEMTOMMYSBARS_CYCLE_WATER"]  = "Cycle Water Totem"
_G["BINDING_NAME_TOTEMTOMMYSBARS_TOTEM_EARTH"]  = "Drop Earth Totem"
_G["BINDING_NAME_TOTEMTOMMYSBARS_CYCLE_EARTH"]  = "Cycle Earth Totem"
_G["BINDING_NAME_TOTEMTOMMYSBARS_TOTEM_AIR"]    = "Drop Air Totem"
_G["BINDING_NAME_TOTEMTOMMYSBARS_CYCLE_AIR"]    = "Cycle Air Totem"

_G["BINDING_NAME_TOTEMTOMMYSBARS_TOTEMSTACK"]       = "Load Totem Stack"
_G["BINDING_NAME_TOTEMTOMMYSBARS_CYCLE_TOTEMSTACK"] = "Cycle Totem Stack"

_G["BINDING_NAME_TOTEMTOMMYSBARS_MH"] = "Mainhand Imbue"
_G["BINDING_NAME_TOTEMTOMMYSBARS_OH"] = "Off Hand Imbue"
_G["BINDING_NAME_TOTEMTOMMYSBARS_LS"] = "Lightning Shield"

_G["BINDING_NAME_TOTEMTOMMYSBARS_UTIL_1"]       = "Utility Slot 1"
_G["BINDING_NAME_TOTEMTOMMYSBARS_CYCLE_UTIL_1"] = "Cycle Utility Slot 1"
_G["BINDING_NAME_TOTEMTOMMYSBARS_UTIL_2"]       = "Utility Slot 2"
_G["BINDING_NAME_SHEARSSHAMANBAR_CYCLE_UTIL_2"] = "Cycle Utility Slot 2"

NS.TOTEMS = {
    fire = {
        "Searing Totem",
        "Magma Totem",
        "Fire Nova Totem",
        "Flametongue Totem",
        "Frost Resistance Totem",
    },
    water = {
        "Healing Stream Totem",
        "Mana Spring Totem",
        "Fire Resistance Totem",
        "Poison Cleansing Totem",
        "Disease Cleansing Totem",
    },
    earth = {
        "Stoneskin Totem",
        "Strength of Earth Totem",
        "Stoneclaw Totem",
        "Tremor Totem",
        "Earthbind Totem",
    },
    air = {
        "Windfury Totem",
        "Grace of Air Totem",
        "Nature Resistance Totem",
        "Grounding Totem",
        "Sentry Totem",
        "Wrath of Air Totem", -- 60 quest reward
        "Windwall Totem",
    },
}

-- Element → totem slot index (matches GetTotemInfo slot numbering).
NS.ELEMENT_SLOT = {
    fire = 1,
    earth = 2,
    water = 3,
    air = 4,
}

NS.ELEMENT_ORDER = { "fire", "water", "earth", "air" }

NS.IMBUES = {
    "Rockbiter Weapon",
    "Flametongue Weapon",
    "Frostbrand Weapon",
    "Windfury Weapon",
}

NS.UTILITY_OPTIONS = {
    "Ghost Wolf",
    "Water Breathing",
    "Water Walking",
    "Far Sight",
    "Astral Recall",
    "Reincarnation",
    "Cure Poison",
    "Cure Disease",
}

-- Default sets ("stomps").  Ship empty so a fresh install (or a
-- "Default Settings" reset) starts with no pre-made sequences — the
-- user builds their own via the Custom Totem Sequence editor.
NS.DEFAULT_SETS = {}

NS.DEFAULTS = {
    locked = false,
    -- Main Cycle Modifier: which modifier turns a "Drop" keybind into
    -- a "Cycle" action.  When the user binds e.g. "Drop Fire Totem" to
    -- A and sets this to "alt", pressing Alt+A cycles the element
    -- instead of casting.  Shift-clicking the on-screen button always
    -- cycles regardless of this setting.
    -- Values: "none" | "shift" | "alt" | "ctrl".  Default "shift" to
    -- preserve the existing shift-click-cycle behavior for keybinds.
    cycleModifier = "shift",
    -- Master visibility flag.  Shift-clicking the minimap button flips
    -- this — when true, all five bars (totem, imbue, util, sequence,
    -- preset) are hidden until toggled back on.  Persists across logins.
    barsHidden = false,
    -- Minimap button: position around the rim is a polar angle (deg),
    -- 0 = right, 90 = top, 180 = left, 270 = bottom.
    minimap = { angle = 215, hidden = false },
    -- Per-group layouts (each frame can be different when solo)
    totemLayout = "horizontal",  -- "horizontal" | "vertical" | "grid"
    utilLayout  = "horizontal",
    imbueLayout = "horizontal",
    -- Combined-bar layout — used for the host frame whenever 2+ groups
    -- are merged.  Independent of any individual group's solo layout.
    combinedLayout = "horizontal",
    -- Legacy combined layout key, kept for migration
    layout = "horizontal",
    scale = 0.75,
    -- Per-group scales (multipliers on top of the global Scale)
    totemScale = 1.0,
    imbueScale = 1.40,
    utilScale  = 1.0,
    -- When bars are combined, use the higher or lower of the combined
    -- groups' scales as the host scale.  "higher" | "lower"
    combinedScalePref = "lower",
    alerts = true,
    -- 3-way combine flags.  When 2+ are checked, those groups share one
    -- "combined" frame.  Host is whichever combined group has priority:
    -- Totems > Utility > Imbue.  Unchecked groups stay on their own bar.
    combineTotems  = false,
    combineUtility = false,
    combineImbue   = false,
    -- Show flags — uncheck a group to hide its bar entirely
    showTotems        = true,
    showUtility       = true,
    showImbue         = true,
    showTotemSequence = true,
    showTotemStacks   = true,
    -- When true, any button whose spell isn't learned yet is hidden
    -- entirely (rather than greyed at 40% alpha).
    hideUnlearned = false,
    -- Per-button toggles for the in-combat panic alert (glow + bounce + flash + ring + sound).
    -- Disable individually if a particular alert is too distracting.
    --   mh / oh / ls           — imbue + Lightning Shield
    --   util_1 / util_2        — utility slots
    --   totem_<element>        — fire / water / earth / air
    combatAlerts = {
        mh = true, oh = true, ls = true,
        util_1 = false, util_2 = false,
        totem_fire = false, totem_water = false, totem_earth = false, totem_air = false,
    },
    -- When false, situational totems (Earthbind, Stoneclaw, Tremor, etc.)
    -- never trigger missing alerts even if their element box is checked.
    -- When true, they DO alert when missing.
    enableSituationalTotemAlerts = false,
    -- Per-bar style customization for the in-combat alert.  Each group
    -- (imbue / util / totem) can independently turn the Movement, Audio
    -- and Flashes effects on/off, and pick a style for each.
    alertStyles = {
        imbue = { movement = true, movementStyle = "shake",
                  audio    = true, audioStyle    = "raidwarning",
                  flashes  = true, flashesStyle  = "glowring",
                  warning  = true,
                  duration = true,
                  cd       = true },
        util  = { movement = true, movementStyle = "shake",
                  audio    = true, audioStyle    = "raidwarning",
                  flashes  = true, flashesStyle  = "goldsolid",
                  warning  = true,
                  duration = true,
                  cd       = true },
        totem = { movement = true, movementStyle = "shake",
                  audio    = true, audioStyle    = "raidwarning",
                  flashes  = true, flashesStyle  = "goldsolid",
                  warning  = true,
                  duration = true,
                  cd       = true,
                  showActive = false },  -- show duration of whichever totem is actually dropped
    },
    point      = { "TOP", "UIParent", "TOP", 395.55502319336, -283.55572509766 },
    imbuePoint = { "TOP", "UIParent", "TOP", 279.36535644531, -148.69831848145 },
    utilPoint  = { "TOP", "UIParent", "TOP", 392.88833618164, -142.2218170166 },
    defaults = {
        fire  = "Searing Totem",
        water = "Healing Stream Totem",
        earth = "Stoneskin Totem",
        air   = "Windfury Totem",
        mh    = "Rockbiter Weapon",
        oh    = "Rockbiter Weapon",
    },
    -- Pool of utilities user can pick from (ticked = available for util slots)
    utilities = {
        ["Ghost Wolf"] = true,
    },
    -- Two utility slots on the bar; each slot holds a spell from the pool.
    -- Click casts; Shift-click cycles through the pool's enabled+known spells.
    utilSelected = { "Ghost Wolf", nil },
    sets = nil,  -- copied from DEFAULT_SETS on first load
    stackIcons = {},  -- per-stack custom icon (fileID); nil = use first totem
    -- Per-sequence reset timer (seconds).  If the next totem in the cast
    -- sequence isn't dropped within this many seconds, the sequence rolls
    -- back to step 1.  Built into the /castsequence reset=N/target macro
    -- AND used by the addon's idle-reset OnUpdate poll for the icon.
    -- Missing entry → default of 8s.
    setReset = {},
    activeSet = "DPS",
    bindings = {},   -- { [actionId] = "KEYNAME", ... }

    -- Utility stacks: named pairs of (slot1, slot2) utility spells.
    --   utilStacks    : { ["StackName"] = { "Ghost Wolf", "Cure Poison" }, ... }
    --   linkedUtil    : maps a totem-stack name → util-stack name.  When the
    --                   totem stack is activated, the linked util stack is
    --                   auto-applied to the bar's two util slots.
    utilStacks = {},
    linkedUtil = {},
    -- Symmetric to linkedUtil: maps a util-stack name → totem-stack name.
    -- When the util stack is activated, the linked totem stack is also
    -- auto-applied (vice-versa of linkedUtil).
    linkedTotem = {},

    -- Totem stacks: named per-element default snapshots (Fire/Water/Earth/Air).
    -- Selecting a totem stack overwrites DB.defaults for those 4 elements.
    --   totemStacks      : { ["StackName"] = { fire = "...", water = "...", earth = "...", air = "..." }, ... }
    --   totemStackIcons  : per-stack chosen icon (fileID), nil = auto
    --   activeTotemStack : currently applied stack name
    totemStacks = {},
    totemStackIcons = {},
    activeTotemStack = nil,
}

-- Display abbreviations for long totem names — only the ones that
-- visually crowd the saved-lists "Totem" column.  Most totems fit
-- comfortably without the trailing " Totem" so they're not listed.
NS.TOTEM_SHORT = {
    ["Strength of Earth"]  = "Str of Earth",
    ["Fire Resistance"]    = "Fire Res",
    ["Frost Resistance"]   = "Frost Res",
    ["Nature Resistance"]  = "Nature Res",
    ["Disease Cleansing"]  = "Dis Cleanse",
    ["Poison Cleansing"]   = "Pois Cleanse",
}

NS.LIGHTNING_SHIELD = "Lightning Shield"
NS.TOTEMIC_RECALL   = "Totemic Recall"

-- Utility spells that produce a player buff we can detect.  Other utilities
-- (Cure Poison, Astral Recall, etc.) are one-shot actions — they can't be
-- "missing", so their alert toggle is a no-op.
NS.UTILITY_BUFFS = {
    ["Ghost Wolf"]       = true,
    ["Water Breathing"]  = true,
    ["Water Walking"]    = true,
}

-- Alert-style catalogues.  One entry per style: { key, label }.
-- The dropdowns in the options panel show `label`; DB stores `key`.
-- The actual visual/audio behavior is implemented in Core.lua.

NS.MOVEMENT_STYLES = {
    { key = "wobble",  label = "Wobble (bounce + shake)" },
    { key = "bounce",  label = "Vertical Bounce" },
    { key = "shake",   label = "Horizontal Shake" },
    { key = "pulse",   label = "Scale Pulse" },
    { key = "spin",    label = "Spin" },
}

-- Each entry maps to a WoW SoundKit ID played once on combat entry.
NS.AUDIO_STYLES = {
    { key = "raidwarning", label = "Raid Warning",  soundID = 8959  },
    { key = "mapping",     label = "Map Ping",      soundID = 5274  },
    { key = "lvlup",       label = "Level Up Burst", soundID = 888   },
    { key = "ready",       label = "Ready Check",   soundID = 8960  },
    { key = "questdone",   label = "Quest Complete", soundID = 619   },
}

NS.FLASH_STYLES = {
    { key = "glowring", label = "Gold Glow + Shockwave" },
    { key = "goldsolid", label = "Gold Glow Only" },
    { key = "redpanic", label = "Red Panic Glow" },
    { key = "ringonly", label = "Shockwave Ring Only" },
    { key = "subtle",   label = "Subtle Pulse" },
}

-- Situational totems — drop on demand, not meant to be kept up.
-- The bar will not pulse a "missing" alert when these are the active default.
NS.NO_ALERT_TOTEMS = {
    ["Earthbind Totem"]          = true,
    ["Stoneclaw Totem"]          = true,
    ["Tremor Totem"]             = true,
    ["Grounding Totem"]          = true,
    ["Sentry Totem"]             = true,
    ["Fire Nova Totem"]          = true,
    ["Disease Cleansing Totem"]  = true,
    ["Poison Cleansing Totem"]   = true,
}
