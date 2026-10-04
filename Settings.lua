--[[
unrealMap / Settings.lua

The options page, and which window draws it. Same contract as UnrealQuest's
Core/Settings.lua, scaled down to one page:

  * If unrealUI is installed, the page is registered with its settings window
    (U.RegisterSettingsTab) and uses its shared checkbox component, so it looks
    and opens like every other unrealUI page.
  * Otherwise unrealMap builds its own small window and hands the same builder
    its content frame, with a button beside the minimap to open it.

Neither addon depends on the other. unrealUI is detected by POLLING for the
UnrealUI global and type-checking RegisterSettingsTab, not by load order,
IsAddOnLoaded or ADDON_LOADED, none of which has a probed record here. The host
is decided once and never changes during the session.

Nothing here touches map textures; the page only writes unrealMapDB and calls
the unrealMap API.

Language (Locale.lua) follows the same split: under unrealUI the page is drawn
in unrealUI's language and has no selector; standalone, the window header
carries an EN / CN / RU flag row. The same poll settles both decisions.
Every label is translated when it is built; a language change asks for a
/reload instead of rebuilding anything.
]]

local L = unrealMapLocale.L

-- Under unrealUI the addon is a settings group (its own "Unreal Map" category
-- in unrealUI's Game Settings window) holding one page.
local TAB_ID = "unrealmap"
local TAB_LABEL = "UnrealMap"
local GENERAL_PAGE_ID = TAB_ID .. ".general"

-- Never the name of the global API table below: CreateFrame assigns the
-- frame to a global of its name, which would replace that table.
local WINDOW_NAME = "unrealMapSettingsWindow"
local MINIMAP_BUTTON_NAME = "unrealMapMinimapButton"
local MINIMAP_ICON = "Interface\\Icons\\INV_Misc_Map_01"
local PLAIN_TEXTURE = "Interface\\Buttons\\WHITE8X8"

-- Standalone window metrics, the same header/footer/padding UnrealQuest uses.
local HEADER_HEIGHT = 32
local FOOTER_HEIGHT = 46
local PADDING = 12
local CONTENT_WIDTH = 360
local CONTENT_HEIGHT = 152
local TEXT_WIDTH = CONTENT_WIDTH - 12
local NOTE_INDENT = 20
local CHECKBOX_SIZE = 14
local CHECKBOX_INSET = 3
local MINIMAP_BUTTON_SIZE = 24

-- Standalone language flags, unrealUI/UnrealQuest's header row: opacity alone
-- marks the selection (full when active, dim when idle, near-full on hover).
local FLAG_WIDTH = 18
local FLAG_HEIGHT = 14
local FLAG_GAP = 3
local FLAG_RIGHT_INSET = 12
local FLAG_SHADE_SELECTED = 1
local FLAG_SHADE_IDLE = 0.3
local FLAG_SHADE_HOVER = 0.95

local HOST_POLL_INTERVAL = 0.5
local HOST_POLL_SECONDS = 15

local ACCENT = { 0.96, 0.68, 0.04, 1.00 }
local ACCENT_HEX = "f5ae0a"
local BACKGROUND = { 0.06, 0.06, 0.06 }
local BORDER = { 0.16, 0.16, 0.16, 1.00 }
local NOTE_GREY = 0.70

local DEFAULTS = {
  revealFog = true,
  minimapButton = true,
}

local host            -- nil while undecided, then "unrealui" or "standalone"
local hostPageId      -- the page unrealUI opens: the group's page or the tab
local Close, Toggle   -- defined with the window lifecycle below
local hostWaited = 0
local window, content
local page            -- the standalone page: { widgets = {}, refresh = fn }
local chrome = {}     -- standalone window parts shown/hidden explicitly
local flagButtons = {} -- standalone language flags, created once with the window
local minimapButton

-- Saved settings ------------------------------------------------------------

-- Read at call time, never cached at file scope: the saved table may be
-- assigned after this file runs.
local function Setting(key)
  local db = _G["unrealMapDB"]
  if type(db) == "table" and db[key] ~= nil then return db[key] end
  return DEFAULTS[key]
end

local function Store(key, value)
  if type(unrealMapDB) ~= "table" then unrealMapDB = {} end
  unrealMapDB[key] = value
end

local function Print(text)
  local frame = _G["DEFAULT_CHAT_FRAME"]
  if frame and type(frame.AddMessage) == "function" then
    pcall(frame.AddMessage, frame, "|cff33ffccunreal|cffffffffMap|r: " .. text)
  end
end

local function PrintLoaded(text)
  local frame = _G["DEFAULT_CHAT_FRAME"]
  if frame and type(frame.AddMessage) == "function" then
    pcall(frame.AddMessage, frame,
      "|cffffffffUnreal |cff" .. ACCENT_HEX
        .. "Map|r |cffb3b3b3: " .. text .. "|r")
  end
end

local function PageTitle()
  local version = unrealMap and unrealMap.version or "?"
  return "|cff33ffccunreal|cffffffffMap|r |cff888888v" .. tostring(version) .. "|r"
end

-- unrealUI's namespace, only if it carries the function this needs.
local function UnrealUI()
  local found = _G["UnrealUI"]
  if type(found) ~= "table" or type(found.RegisterSettingsTab) ~= "function" then
    return nil
  end
  return found
end

-- Small widget helpers ------------------------------------------------------

local function Show(object, shown)
  if not object then return end
  if shown then
    if type(object.Show) == "function" then pcall(object.Show, object) end
  elseif type(object.Hide) == "function" then
    pcall(object.Hide, object)
  end
end

-- Shows one page region, including unrealUI composite controls, which carry
-- their own parts. Parent visibility is not relied on to reach children.
local function SetRegionShown(region, shown)
  if not region then return end
  if type(region.uuiSetShown) == "function" then
    region.uuiSetShown(shown)
    return
  end
  if region.uuiParts then
    local i
    for i = 1, table.getn(region.uuiParts) do
      SetRegionShown(region.uuiParts[i], shown)
    end
    return
  end
  Show(region, shown)
  Show(region.label, shown)
end

local function Solid(parent, layer, r, g, b, a)
  local ok, texture = pcall(parent.CreateTexture, parent, nil, layer)
  if not ok or not texture then return nil end
  pcall(texture.SetTexture, texture, PLAIN_TEXTURE)
  pcall(texture.SetVertexColor, texture, r, g, b, a or 1)
  return texture
end

-- 1px edges drawn as textures; this client does not rasterize fractional
-- backdrop edges.
local function FlatBorder(frame)
  local edges = {}
  local spec = {
    { "TOPLEFT", "TOPRIGHT", true }, { "BOTTOMLEFT", "BOTTOMRIGHT", true },
    { "TOPLEFT", "BOTTOMLEFT", false }, { "TOPRIGHT", "BOTTOMRIGHT", false },
  }
  local i
  for i = 1, 4 do
    local edge = Solid(frame, "OVERLAY", BORDER[1], BORDER[2], BORDER[3], BORDER[4])
    if edge then
      pcall(edge.SetPoint, edge, spec[i][1], frame, spec[i][1], 0, 0)
      pcall(edge.SetPoint, edge, spec[i][2], frame, spec[i][2], 0, 0)
      if spec[i][3] then
        pcall(edge.SetHeight, edge, 1)
      else
        pcall(edge.SetWidth, edge, 1)
      end
      edges[i] = edge
    end
  end
  frame.unrealMapEdges = edges
end

local function SetBorderColor(frame, color)
  local edges = frame and frame.unrealMapEdges
  if not edges then return end
  local i
  for i = 1, 4 do
    if edges[i] then
      pcall(edges[i].SetVertexColor, edges[i], color[1], color[2], color[3], color[4])
    end
  end
end

local function HoverBorder(frame)
  pcall(frame.SetScript, frame, "OnEnter", function() SetBorderColor(frame, ACCENT) end)
  pcall(frame.SetScript, frame, "OnLeave", function() SetBorderColor(frame, BORDER) end)
end

local function FontString(parent, template, x, y, width, text, grey)
  local ok, label = pcall(parent.CreateFontString, parent, nil, "OVERLAY", template)
  if not ok or not label then return nil end
  pcall(label.SetPoint, label, "TOPLEFT", parent, "TOPLEFT", x, y)
  pcall(label.SetJustifyH, label, "LEFT")
  if width then pcall(label.SetWidth, label, width) end
  pcall(label.SetShadowOffset, label, 0, 0)
  if grey then pcall(label.SetTextColor, label, grey, grey, grey) end
  pcall(label.SetText, label, text or "")
  return label
end

-- The standalone checkbox: a flat box with an accent mark, the same look as
-- UnrealQuest's standalone settings toggle.
local function CreateFlatCheckbox(parent, name, text, x, y, width, onChange)
  local ok, box = pcall(CreateFrame, "Button", name, parent)
  if not ok or not box then return nil end
  pcall(box.SetWidth, box, CHECKBOX_SIZE)
  pcall(box.SetHeight, box, CHECKBOX_SIZE)
  pcall(box.SetPoint, box, "TOPLEFT", parent, "TOPLEFT", x, y)
  pcall(box.EnableMouse, box, true)
  pcall(box.RegisterForClicks, box, "LeftButtonUp")
  local fill = Solid(box, "BACKGROUND", BACKGROUND[1], BACKGROUND[2], BACKGROUND[3], 1)
  if fill then pcall(fill.SetAllPoints, fill, box) end
  FlatBorder(box)
  local mark = Solid(box, "OVERLAY", ACCENT[1], ACCENT[2], ACCENT[3], 1)
  if mark then
    pcall(mark.SetPoint, mark, "TOPLEFT", box, "TOPLEFT", CHECKBOX_INSET, -CHECKBOX_INSET)
    pcall(mark.SetPoint, mark, "BOTTOMRIGHT", box, "BOTTOMRIGHT", -CHECKBOX_INSET, CHECKBOX_INSET)
  end
  local label = FontString(parent, "GameFontHighlightSmall", 0, 0, width, text)
  if label then
    pcall(label.ClearAllPoints, label)
    pcall(label.SetPoint, label, "LEFT", box, "RIGHT", 6, 0)
    pcall(label.SetTextColor, label, 1, 1, 1)
  end
  box.label = label

  local control = { box = box, label = label, value = false }
  control.SetValue = function(value)
    control.value = value and true or false
    Show(mark, control.value)
  end
  HoverBorder(box)
  pcall(box.SetScript, box, "OnClick", function()
    control.SetValue(not control.value)
    onChange(control.value)
  end)
  return control
end

-- The page ------------------------------------------------------------------
--
-- unrealUI's contract (modules/settings.lua, RegisterSettingsTab):
-- build(parent) returns the regions the page owns and a refresh function run
-- on every open. The standalone window honours the same contract.

local function BuildPage(parent, standalone)
  local widgets, syncs = {}, {}
  local y = standalone and -10 or 0

  local function Add(region)
    if region then table.insert(widgets, region) end
    return region
  end

  -- One bound option. Uses unrealUI's shared checkbox when it hosts the page.
  local function Checkbox(key, text, onChange)
    local function Changed(checked)
      if type(onChange) == "function" then
        onChange(checked)
      else
        Store(key, checked and true or false)
      end
    end
    local hostUI = not standalone and UnrealUI() or nil
    local control
    if hostUI and type(hostUI.CreateCheckbox) == "function" then
      local ok, created = pcall(hostUI.CreateCheckbox, parent, {
        name = WINDOW_NAME .. key,
        text = text,
        textWidth = TEXT_WIDTH - NOTE_INDENT,
        value = Setting(key) and true or false,
        onChange = Changed,
      })
      if ok and created then
        control = created
        control.SetPoint("TOPLEFT", parent, "TOPLEFT", 0, y)
        Add(control)
      end
    end
    if not control then
      control = CreateFlatCheckbox(parent, WINDOW_NAME .. key, text, 0, y,
        TEXT_WIDTH - NOTE_INDENT, Changed)
      if not control then return end
      Add(control.box)
    end
    y = y - 18
    table.insert(syncs, function() control.SetValue(Setting(key) and true or false) end)
  end

  local function Note(text)
    local label = Add(FontString(parent, "GameFontHighlightSmall", NOTE_INDENT, y,
      TEXT_WIDTH - NOTE_INDENT, text, NOTE_GREY))
    local height = 26
    if label and type(label.GetHeight) == "function" then
      local ok, measured = pcall(label.GetHeight, label)
      if ok and type(measured) == "number" and measured > 0 then height = measured end
    end
    y = y - height - 12
  end

  local heading = Add(FontString(parent, "GameFontNormal", 0, y, nil, L("SETTINGS_HEADING_WORLD_MAP")))
  if heading then pcall(heading.SetTextColor, heading, ACCENT[1], ACCENT[2], ACCENT[3]) end
  y = y - 22

  Checkbox("revealFog", L("SETTINGS_REVEAL_FOG"), function(checked)
    if unrealMap and type(unrealMap.SetFogRevealEnabled) == "function" then
      unrealMap.SetFogRevealEnabled(checked)
    else
      Store("revealFog", checked and true or false)
    end
  end)
  Note(L("SETTINGS_REVEAL_FOG_NOTE"))

  if standalone then
    Checkbox("minimapButton", L("SETTINGS_MINIMAP_BUTTON"), function(checked)
      Store("minimapButton", checked and true or false)
      Show(minimapButton, checked)
    end)
  end

  local function Refresh()
    local i
    for i = 1, table.getn(syncs) do syncs[i]() end
  end
  return widgets, Refresh
end

-- Standalone window ---------------------------------------------------------

local function ApplyStoredPosition()
  local point, x, y = Setting("settingsPoint"), Setting("settingsX"), Setting("settingsY")
  if type(point) ~= "string" or type(x) ~= "number" or type(y) ~= "number" then
    point, x, y = "CENTER", 0, 0
  end
  pcall(window.ClearAllPoints, window)
  pcall(window.SetPoint, window, point, UIParent, point, x, y)
end

local function CapturePosition()
  local ok, point, _, _, x, y = pcall(window.GetPoint, window)
  if ok and type(point) == "string" and type(x) == "number" and type(y) == "number" then
    Store("settingsPoint", point)
    Store("settingsX", x)
    Store("settingsY", y)
  end
end

-- Language flags --------------------------------------------------------------
--
-- Standalone window only: with unrealUI installed the language is set there,
-- and a second selector would be two controls writing one value. A flag whose
-- artwork will not load keeps its ASCII badge, so the way back to a readable
-- language is always visible.

local function ShadeFlag(button, shade, selected)
  if button.unrealMapIcon then
    pcall(button.unrealMapIcon.SetVertexColor, button.unrealMapIcon, 1, 1, 1, shade)
  end
  local badge = button.unrealMapBadge
  if badge then
    if selected then
      pcall(badge.SetTextColor, badge, ACCENT[1], ACCENT[2], ACCENT[3])
    else
      pcall(badge.SetTextColor, badge, 0.6, 0.6, 0.6)
    end
  end
end

local function RefreshLanguageFlags()
  local active = unrealMapLocale.GetLanguage()
  local i
  for i = 1, table.getn(flagButtons) do
    local button = flagButtons[i]
    button.unrealMapSelected = button.unrealMapLanguage == active
    ShadeFlag(button, button.unrealMapSelected and FLAG_SHADE_SELECTED or FLAG_SHADE_IDLE,
      button.unrealMapSelected)
  end
end

local function BuildLanguageFlags(frame)
  if unrealMapLocale.IsFollowingUnrealUI() then return end
  local languages = unrealMapLocale.GetLanguages()
  local count = table.getn(languages)
  local level = 0
  local levelOk, frameLevel = pcall(frame.GetFrameLevel, frame)
  if levelOk and type(frameLevel) == "number" then level = frameLevel end
  local i
  for i = 1, count do
    local entry = languages[i]
    local code, label = entry.code, entry.label
    local ok, button = pcall(CreateFrame, "Button", WINDOW_NAME .. "Language" .. code, frame)
    if ok and button then
      pcall(button.SetWidth, button, FLAG_WIDTH)
      pcall(button.SetHeight, button, FLAG_HEIGHT)
      pcall(button.SetPoint, button, "TOPRIGHT", frame, "TOPRIGHT",
        -FLAG_RIGHT_INSET - (count - i) * (FLAG_WIDTH + FLAG_GAP),
        -(HEADER_HEIGHT - FLAG_HEIGHT) / 2)
      pcall(button.SetFrameLevel, button, level + 20)
      pcall(button.EnableMouse, button, true)
      pcall(button.RegisterForClicks, button, "LeftButtonUp")

      local iconOk, icon = pcall(button.CreateTexture, button, nil, "ARTWORK")
      if iconOk and icon and pcall(icon.SetTexture, icon, unrealMapLocale.FlagTexture(code)) then
        pcall(icon.SetAllPoints, icon, button)
        button.unrealMapIcon = icon
      else
        if iconOk and icon then pcall(icon.Hide, icon) end
        local badge = FontString(button, "GameFontHighlightSmall", 0, 0, nil, entry.short)
        if badge then
          pcall(badge.ClearAllPoints, badge)
          pcall(badge.SetPoint, badge, "CENTER", button, "CENTER", 0, 0)
          button.unrealMapBadge = badge
        end
      end

      button.unrealMapLanguage = code
      pcall(button.SetScript, button, "OnClick", function()
        if not unrealMapLocale.SetLanguage(code) then return end
        RefreshLanguageFlags()
        -- Printed in the language just chosen: an unreadable line is the
        -- fastest sign the client font lacks its glyphs.
        Print(L("SETTINGS_LANGUAGE_CHANGED", label))
        Print(L("SETTINGS_LANGUAGE_RELOAD"))
      end)
      pcall(button.SetScript, button, "OnEnter", function()
        if not button.unrealMapSelected then ShadeFlag(button, FLAG_SHADE_HOVER, false) end
      end)
      pcall(button.SetScript, button, "OnLeave", function()
        if not button.unrealMapSelected then ShadeFlag(button, FLAG_SHADE_IDLE, false) end
      end)
      table.insert(flagButtons, button)
      table.insert(chrome, button)
    end
  end
  RefreshLanguageFlags()
end

local function BuildWindow()
  if window then return window end
  local ok, frame = pcall(CreateFrame, "Frame", WINDOW_NAME, UIParent)
  if not ok or not frame then
    Print(L("SETTINGS_WINDOW_FAILED"))
    return nil
  end
  window = frame
  pcall(frame.SetFrameStrata, frame, "HIGH")
  pcall(frame.EnableMouse, frame, true)
  pcall(frame.SetWidth, frame, CONTENT_WIDTH + PADDING * 2)
  pcall(frame.SetHeight, frame, CONTENT_HEIGHT + HEADER_HEIGHT + FOOTER_HEIGHT)

  local background = Solid(frame, "BACKGROUND", BACKGROUND[1], BACKGROUND[2], BACKGROUND[3], 0.94)
  if background then pcall(background.SetAllPoints, background, frame) end
  FlatBorder(frame)
  local accent = Solid(frame, "ARTWORK", ACCENT[1], ACCENT[2], ACCENT[3], 1)
  if accent then
    pcall(accent.SetPoint, accent, "TOPLEFT", frame, "TOPLEFT", 0, 0)
    pcall(accent.SetWidth, accent, 2)
    pcall(accent.SetHeight, accent, HEADER_HEIGHT)
  end
  local rules = { { "TOP", -HEADER_HEIGHT }, { "BOTTOM", FOOTER_HEIGHT } }
  local i
  for i = 1, 2 do
    local rule = Solid(frame, "ARTWORK", BORDER[1], BORDER[2], BORDER[3], 1)
    if rule then
      pcall(rule.SetPoint, rule, rules[i][1] .. "LEFT", frame, rules[i][1] .. "LEFT", 0, rules[i][2])
      pcall(rule.SetPoint, rule, rules[i][1] .. "RIGHT", frame, rules[i][1] .. "RIGHT", 0, rules[i][2])
      pcall(rule.SetHeight, rule, 1)
    end
  end
  FontString(frame, "GameFontNormal", 2 + PADDING,
    -(math.floor((HEADER_HEIGHT - 14) / 2) + 4), nil, PageTitle())

  -- Drag handle over the header: a Button child raised by frame level, never
  -- by strata, moved with the warm-up StartMoving/StopMovingOrSizing pair
  -- (frames.movable_drag_requires_button_handle).
  -- The handle stops short of the flag row so the flags stay clickable; when
  -- unrealUI owns the language there is no row and it spans the header.
  local handleInset = 0
  if not unrealMapLocale.IsFollowingUnrealUI() then
    handleInset = FLAG_RIGHT_INSET
      + table.getn(unrealMapLocale.GetLanguages()) * (FLAG_WIDTH + FLAG_GAP)
  end
  local handleOk, handle = pcall(CreateFrame, "Button", WINDOW_NAME .. "Handle", frame)
  if handleOk and handle then
    pcall(handle.SetPoint, handle, "TOPLEFT", frame, "TOPLEFT", 0, 0)
    pcall(handle.SetPoint, handle, "TOPRIGHT", frame, "TOPRIGHT", -handleInset, 0)
    pcall(handle.SetHeight, handle, HEADER_HEIGHT)
    local levelOk, level = pcall(frame.GetFrameLevel, frame)
    if levelOk and type(level) == "number" then
      pcall(handle.SetFrameLevel, handle, level + 10)
    end
    pcall(handle.EnableMouse, handle, true)
    pcall(handle.RegisterForClicks, handle, "LeftButtonUp")
    pcall(handle.RegisterForDrag, handle, "LeftButton")
    pcall(handle.SetScript, handle, "OnDragStart", function()
      pcall(frame.SetMovable, frame, true)
      pcall(frame.StartMoving, frame)
      pcall(frame.StopMovingOrSizing, frame)
      if not pcall(frame.StartMoving, frame) then
        Print(L("SETTINGS_WINDOW_NOT_MOVABLE"))
      end
    end)
    pcall(handle.SetScript, handle, "OnDragStop", function()
      pcall(frame.StopMovingOrSizing, frame)
      CapturePosition()
    end)
    table.insert(chrome, handle)
  end
  BuildLanguageFlags(frame)

  local closeOk, close = pcall(CreateFrame, "Button", WINDOW_NAME .. "Close", frame)
  if closeOk and close then
    pcall(close.SetWidth, close, 80)
    pcall(close.SetHeight, close, 22)
    pcall(close.SetPoint, close, "BOTTOMRIGHT", frame, "BOTTOMRIGHT", -PADDING, PADDING)
    pcall(close.EnableMouse, close, true)
    pcall(close.RegisterForClicks, close, "LeftButtonUp")
    local fill = Solid(close, "BACKGROUND", BACKGROUND[1], BACKGROUND[2], BACKGROUND[3], 1)
    if fill then pcall(fill.SetAllPoints, fill, close) end
    FlatBorder(close)
    local label = FontString(close, "GameFontHighlightSmall", 0, 0, nil, L("COMMON_CLOSE"))
    if label then
      pcall(label.ClearAllPoints, label)
      pcall(label.SetPoint, label, "CENTER", close, "CENTER", 0, 0)
    end
    HoverBorder(close)
    pcall(close.SetScript, close, "OnClick", function() Close() end)
    table.insert(chrome, close)
  end

  local contentOk, frameContent = pcall(CreateFrame, "Frame", WINDOW_NAME .. "Content", frame)
  if contentOk and frameContent then
    content = frameContent
    pcall(content.SetPoint, content, "TOPLEFT", frame, "TOPLEFT", PADDING, -HEADER_HEIGHT)
    pcall(content.SetPoint, content, "BOTTOMRIGHT", frame, "BOTTOMRIGHT", -PADDING, FOOTER_HEIGHT)
    pcall(content.EnableMouse, content, false)
  end

  ApplyStoredPosition()
  pcall(frame.Hide, frame)
  return frame
end

local function SetPageShown(shown)
  local i
  if page then
    for i = 1, table.getn(page.widgets) do SetRegionShown(page.widgets[i], shown) end
  end
  for i = 1, table.getn(chrome) do Show(chrome[i], shown) end
end

-- Minimap button ------------------------------------------------------------
--
-- Standalone only; unrealUI already has a settings button that opens the
-- window holding this page. Placed beside the minimap's left edge, one slot
-- below the settings-button position UnrealQuest and unrealUI use.

local function EnsureMinimapButton()
  if minimapButton then return minimapButton end
  local ok, button = pcall(CreateFrame, "Button", MINIMAP_BUTTON_NAME, UIParent)
  if not ok or not button then return nil end
  minimapButton = button
  pcall(button.SetWidth, button, MINIMAP_BUTTON_SIZE)
  pcall(button.SetHeight, button, MINIMAP_BUTTON_SIZE)
  pcall(button.SetFrameStrata, button, "MEDIUM")
  pcall(button.EnableMouse, button, true)
  pcall(button.RegisterForClicks, button, "LeftButtonUp")
  local fill = Solid(button, "BACKGROUND", BACKGROUND[1], BACKGROUND[2], BACKGROUND[3], 0.85)
  if fill then pcall(fill.SetAllPoints, fill, button) end
  FlatBorder(button)

  local iconOk, icon = pcall(button.CreateTexture, button, nil, "ARTWORK")
  if iconOk and icon and pcall(icon.SetTexture, icon, MINIMAP_ICON) then
    pcall(icon.SetPoint, icon, "TOPLEFT", button, "TOPLEFT", 1, -1)
    pcall(icon.SetPoint, icon, "BOTTOMRIGHT", button, "BOTTOMRIGHT", -1, 1)
    pcall(icon.SetTexCoord, icon, 0.08, 0.92, 0.08, 0.92)
  else
    local label = FontString(button, "GameFontNormal", 0, 0, nil, "M")
    if label then
      pcall(label.ClearAllPoints, label)
      pcall(label.SetPoint, label, "CENTER", button, "CENTER", 0, -1)
      pcall(label.SetTextColor, label, ACCENT[1], ACCENT[2], ACCENT[3])
    end
  end

  local below = -(MINIMAP_BUTTON_SIZE + 4)
  local minimap = _G["Minimap"]
  local cluster = _G["MinimapCluster"]
  if not (minimap and pcall(button.SetPoint, button, "TOPRIGHT", minimap, "TOPLEFT", -6, below))
      and not (cluster and pcall(button.SetPoint, button, "TOPRIGHT", cluster, "TOPLEFT", -6, below - 6)) then
    pcall(button.SetPoint, button, "TOPRIGHT", UIParent, "TOPRIGHT", -8, -8 + below)
  end

  pcall(button.SetScript, button, "OnClick", function() Toggle() end)
  pcall(button.SetScript, button, "OnEnter", function()
    SetBorderColor(button, ACCENT)
    local tooltip = _G["GameTooltip"]
    if tooltip then
      pcall(tooltip.SetOwner, tooltip, button, "ANCHOR_LEFT")
      pcall(tooltip.SetText, tooltip, TAB_LABEL, ACCENT[1], ACCENT[2], ACCENT[3])
      pcall(tooltip.AddLine, tooltip, L("MINIMAP_TOOLTIP"), 0.7, 0.7, 0.7)
      pcall(tooltip.Show, tooltip)
    end
  end)
  pcall(button.SetScript, button, "OnLeave", function()
    SetBorderColor(button, BORDER)
    local tooltip = _G["GameTooltip"]
    if tooltip then pcall(tooltip.Hide, tooltip) end
  end)

  Show(button, Setting("minimapButton") ~= false)
  return button
end

-- Host resolution -----------------------------------------------------------

-- A group with one page where unrealUI supports groups; unrealUI lists a
-- group registered as "unrealmap" as its own category. An older unrealUI
-- without groups gets a single row instead.
local function RegisterWithUnrealUI(hostUI)
  local function Build(parent) return BuildPage(parent, false) end
  if type(hostUI.RegisterSettingsGroup) == "function" then
    local ok, group = pcall(hostUI.RegisterSettingsGroup, TAB_ID, TAB_LABEL,
      { after = "profiles", defaultPage = GENERAL_PAGE_ID })
    if not ok or not group then return false end
    local pageOk, entry = pcall(hostUI.RegisterSettingsTab, GENERAL_PAGE_ID,
      L("SETTINGS_PAGE_GENERAL"), Build, { parent = TAB_ID, after = TAB_ID })
    if not pageOk or not entry then return false end
    hostPageId = GENERAL_PAGE_ID
    return true
  end
  local ok, entry = pcall(hostUI.RegisterSettingsTab, TAB_ID, TAB_LABEL, Build,
    { after = "profiles" })
  if not ok or not entry then return false end
  hostPageId = TAB_ID
  return true
end

local function ResolveHost(force)
  if host then return host end
  local hostUI = UnrealUI()
  if hostUI then
    if RegisterWithUnrealUI(hostUI) then
      host = "unrealui"
      Show(minimapButton, false)
    else
      host = "standalone"
      Print(L("SETTINGS_HOST_REFUSED"))
      EnsureMinimapButton()
    end
  elseif force then
    host = "standalone"
    EnsureMinimapButton()
  end
  return host
end

-- One poll frame, stopped as soon as the host and the language are decided
-- (both within the same grace period). It creates nothing map-related; the first standalone tick shows the minimap button straight
-- away instead of after the full grace period.
local function Now()
  if type(GetTime) ~= "function" then return 0 end
  local ok, value = pcall(GetTime)
  return ok and type(value) == "number" and value or 0
end

local poll = CreateFrame("Frame", "unrealMapSettingsPoll", UIParent)
local pollStarted, pollLast
-- SetScript(type, nil) does not detach a script on this client (UnrealQuest's
-- bootstrap), so the handler also gates itself once both are decided.
local pollDone
poll:SetScript("OnUpdate", function()
  if pollDone then return end
  local now = Now()
  if not pollStarted then
    pollStarted = now
    PrintLoaded(L("CHAT_LOADED", tostring(unrealMap and unrealMap.version or "?")))
  elseif now - pollLast < HOST_POLL_INTERVAL then
    return
  end
  pollLast = now
  hostWaited = now - pollStarted
  local expired = hostWaited >= HOST_POLL_SECONDS
  if not ResolveHost(expired) and not minimapButton then
    EnsureMinimapButton()
  end
  if host and unrealMapLocale.Resolve(expired) then
    pollDone = true
    poll:SetScript("OnUpdate", nil)
    poll:Hide()
  end
end)

-- Opening and closing -------------------------------------------------------

local function Open()
  local resolved = ResolveHost(true)
  -- Final before any label or the flag row is built.
  unrealMapLocale.Resolve(true)
  if resolved == "unrealui" then
    local hostUI = UnrealUI()
    if hostUI and type(hostUI.OpenSettingsPage) == "function" then
      local ok, opened = pcall(hostUI.OpenSettingsPage, hostPageId)
      if ok and opened then return true end
    end
    if hostUI and type(hostUI.OpenSettings) == "function"
        and pcall(hostUI.OpenSettings, true) then
      return true
    end
    Print(L("SETTINGS_IN_UNREALUI"))
    return false
  end

  if not BuildWindow() or not content then return false end
  if not page then
    local widgets, refresh = BuildPage(content, true)
    page = { widgets = widgets or {}, refresh = refresh }
  end
  SetPageShown(true)
  if type(page.refresh) == "function" then page.refresh() end
  Show(window, true)
  return true
end

local function IsWindowShown()
  if not window or type(window.IsShown) ~= "function" then return false end
  local ok, shown = pcall(window.IsShown, window)
  return ok and shown and true or false
end

Close = function()
  if host == "unrealui" or not window then return false end
  SetPageShown(false)
  Show(window, false)
  return true
end

Toggle = function()
  if host ~= "unrealui" and IsWindowShown() then return Close() end
  return Open()
end

unrealMapSettings = {
  Open = Open,
  Close = Close,
  Toggle = Toggle,
  GetHost = function() return host end,
}

-- Slash command -------------------------------------------------------------

SLASH_UNREALMAP1 = "/umap"
SLASH_UNREALMAP2 = "/unrealmap"
SlashCmdList["UNREALMAP"] = function(message)
  local _, _, command, value = string.find(string.lower(message or ""), "^%s*(%S*)%s*(%S*)")
  if command == "fog" then
    local enabled
    if value == "on" then
      enabled = true
    elseif value == "off" then
      enabled = false
    else
      enabled = Setting("revealFog") ~= true
    end
    if unrealMap and type(unrealMap.SetFogRevealEnabled) == "function" then
      unrealMap.SetFogRevealEnabled(enabled)
    else
      Store("revealFog", enabled)
    end
    if page and type(page.refresh) == "function" then page.refresh() end
    Print(L(enabled and "CHAT_FOG_REMOVED" or "CHAT_FOG_RESTORED"))
  elseif command == "minimap" then
    local shown = Setting("minimapButton") == false
    Store("minimapButton", shown)
    Show(minimapButton, shown)
    Print(L(shown and "CHAT_MINIMAP_SHOWN" or "CHAT_MINIMAP_HIDDEN"))
  elseif command == "ragefire" then
    local enabled = value ~= "off"
    if unrealMap and type(unrealMap.SetRagefireMapActive) == "function" then
      local ok, result = unrealMap.SetRagefireMapActive(enabled)
      Print(result or L(ok and "CHAT_RAGEFIRE_UPDATED" or "CHAT_RAGEFIRE_FAILED"))
    else
      Print(L("CHAT_RAGEFIRE_UNAVAILABLE"))
    end
  elseif command == "dungeon" then
    if unrealMap and type(unrealMap.SetDungeonMapActive) == "function" then
      local ok, result = unrealMap.SetDungeonMapActive(value)
      Print(result or L(ok and "DUNGEON_ENABLED" or "DUNGEON_UNKNOWN", value))
    else
      Print(L("CHAT_RAGEFIRE_UNAVAILABLE"))
    end
  elseif command == "raid" then
    if unrealMap and type(unrealMap.SetRaidMapActive) == "function" then
      local ok, result = unrealMap.SetRaidMapActive(value)
      Print(result or L(ok and "RAID_ENABLED" or "RAID_UNKNOWN", value))
    else
      Print(L("RAID_UNAVAILABLE"))
    end
  elseif command == "" or command == "config" or command == "settings" then
    Open()
  else
    Print(L("CHAT_HELP"))
  end
end
