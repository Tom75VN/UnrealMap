--[[
unrealMap / SupportPopup.lua

A support reminder shown a few seconds after the UI loads. Two answers:
"I already liked it" stops it for good (account-wide); "OK, I will add a like"
only closes it until the next login. Its art is UnrealUI's Modern WoW popup set,
imported under Media/Textures/UI (provenance in assets/manifest.json). Every
region is created on first show only, so a dismissed popup costs one timer
frame for a few seconds and no texture.

While the required unrealMap_World pack is missing, the same popup explains
how to install the data packs instead. That notice has one Close button
and ignores the support dismissal: it returns every login until the pack is
installed, because no map is shown in HD without it.
]]

local SHOW_DELAY = 6
local DISMISSED_KEY = "supportPopupDismissed"
local REQUIRED_PACK = "unrealMap_World"
local OPTIONAL_PACKS = { "unrealMap_Unexplored", "unrealMap_Instances" }

local MEDIA = "Interface\\AddOns\\unrealMap\\Media\\Textures\\UI\\"
local PLAIN_TEXTURE = "Interface\\Buttons\\WHITE8X8"

local WIDTH = 368
local HEIGHT = 148
local PACK_HEIGHT = 196
local TEXT_WIDTH = 312
local BUTTON_WIDTH = 132
local BUTTON_HEIGHT = 30
local BUTTON_BOTTOM = 16
local THANKS_GAP = 6
-- UnrealUI M.modernWow.corpsePopupButton: the two-button row geometry.
local SIDE_INSET = 18
local PAIR_GAP = 19

local TITLE = "|cffffffffUnreal |cfff5ae0aMap|r"
local ACCENT = "|cfff5ae0a"
-- Translated when the popup is built, never at file scope (Locale.lua).
local L = unrealMapLocale.L

-- UnrealUI M.modernWow.metalFrame: the diamond-metal housing cells.
local METAL = {
  path = MEDIA .. "unrealmap-popup-metal",
  atlasWidth = 512,
  atlasHeight = 2048,
  scale = 0.12,
  inset = 5,
  outer = 52,
  arm = 120,
  fill = { 0.03, 0.03, 0.03, 0.78 },
  corners = {
    { point = "TOPLEFT",     x = 68,  y = 1104, h = -1, v = 1 },
    { point = "TOPRIGHT",    x = 189, y = 1362, h = 1,  v = 1 },
    { point = "BOTTOMLEFT",  x = 68,  y = 701,  h = -1, v = -1 },
    { point = "BOTTOMRIGHT", x = 189, y = 959,  h = 1,  v = -1 },
  },
  top    = { u1 = 64,  u2 = 448, v1 = 304,  v2 = 356 },
  bottom = { u1 = 64,  u2 = 448, v1 = 159,  v2 = 211 },
  left   = { u1 = 38,  u2 = 98,  v1 = 1190, v2 = 1280 },
  right  = { u1 = 159, u2 = 219, v1 = 1450, v2 = 1540 },
}

-- UnrealUI M.modernWow.button128Red: three-slice cells, pressed row and glow.
local BUTTON = {
  path = MEDIA .. "unrealmap-popup-button",
  atlasWidth = 512,
  atlasHeight = 2048,
  cellHeight = 125,
  barWidth = 291,
  barLeft = 1,
  leftWidth = 113,
  cap = 40,
  normal  = { barTop = 523, capLeft = 392, capTop = 913 },
  pressed = { barTop = 783, capLeft = 378, capTop = 1043 },
  glow = { 15, 424, 418, 490 },
  glowMargin = -4,
  glowIntensity = 0.8,
}

local popup

-- Side by side with the other Unreal addons' like popups (unrealUI,
-- unrealQuest all show theirs a few seconds after login, centred). Shared
-- protocol, identical in each addon: every popup adds its frame once to the
-- global UnrealSupportPopups list, and showing or hiding one re-lays every
-- shown popup in centred rows, wrapping when a row would leave the screen.
local stack = { gap = 12 }

function stack.Layout()
  local list = UnrealSupportPopups
  if type(list) ~= "table" then return end
  local shown = {}
  local width, height = 0, 0
  local i
  for i = 1, table.getn(list) do
    local f = list[i]
    local ok, visible = pcall(f.IsShown, f)
    if ok and visible then
      table.insert(shown, f)
      local okW, w = pcall(f.GetWidth, f)
      local okH, h = pcall(f.GetHeight, f)
      w = okW and tonumber(w) or 0
      h = okH and tonumber(h) or 0
      if w > width then width = w end
      if h > height then height = h end
    end
  end
  local n = table.getn(shown)
  if n == 0 then return end

  local gap = stack.gap
  local okP, screen = pcall(UIParent.GetWidth, UIParent)
  screen = okP and tonumber(screen) or 0
  local perRow = n
  if screen > 0 and width > 0 then
    perRow = math.floor((screen - gap) / (width + gap))
    if perRow < 1 then perRow = 1 end
    if perRow > n then perRow = n end
  end
  local rows = math.ceil(n / perRow)
  for i = 1, n do
    local row = math.floor((i - 1) / perRow)
    local col = (i - 1) - row * perRow
    local inRow = math.min(perRow, n - row * perRow)
    local x = (col - (inRow - 1) / 2) * (width + gap)
    local y = ((rows - 1) / 2 - row) * (height + gap)
    pcall(shown[i].ClearAllPoints, shown[i])
    pcall(shown[i].SetPoint, shown[i], "CENTER", UIParent, "CENTER", x, y)
  end
end

function stack.Register(frame)
  if type(UnrealSupportPopups) ~= "table" then UnrealSupportPopups = {} end
  local i
  for i = 1, table.getn(UnrealSupportPopups) do
    if UnrealSupportPopups[i] == frame then return end
  end
  table.insert(UnrealSupportPopups, frame)
end

local function Dismissed()
  local db = _G["unrealMapDB"]
  return type(db) == "table" and db[DISMISSED_KEY] == true
end

local function SetDismissed()
  if type(unrealMapDB) ~= "table" then unrealMapDB = {} end
  unrealMapDB[DISMISSED_KEY] = true
end

-- Without unrealMap.lua's pack check the support popup is shown as before.
local function RequiredPackMissing()
  local addon = _G["unrealMap"]
  if type(addon) ~= "table" or type(addon.IsPackInstalled) ~= "function" then return false end
  local ok, installed = pcall(addon.IsPackInstalled, REQUIRED_PACK)
  return ok and not installed
end

local function Accent(text)
  return ACCENT .. text .. "|r"
end

local function Texture(parent, layer, path, u1, u2, v1, v2)
  local ok, texture = pcall(parent.CreateTexture, parent, nil, layer)
  if not ok or not texture then return nil end
  pcall(texture.SetTexture, texture, path)
  if u1 then pcall(texture.SetTexCoord, texture, u1, u2, v1, v2) end
  return texture
end

local function Label(parent, template, text)
  local ok, label = pcall(parent.CreateFontString, parent, nil, "OVERLAY", template)
  if not ok or not label then return nil end
  pcall(label.SetText, label, text)
  return label
end

local function MetalFrame(frame, width, height)
  local t = METAL
  local aw, ah, s, inset, e = t.atlasWidth, t.atlasHeight, t.scale, t.inset, t.outer

  local fill = Texture(frame, "BACKGROUND", PLAIN_TEXTURE)
  if fill then
    pcall(fill.SetVertexColor, fill, t.fill[1], t.fill[2], t.fill[3], t.fill[4])
    pcall(fill.SetPoint, fill, "TOPLEFT", frame, "TOPLEFT", inset, -inset)
    pcall(fill.SetPoint, fill, "BOTTOMRIGHT", frame, "BOTTOMRIGHT", -inset, inset)
  end

  local n = math.min(t.arm, (math.min(width, height) / 2 - inset) / s)
  if n < 0 then n = 0 end
  local shift = e * s - inset
  local i
  for i = 1, table.getn(t.corners) do
    local c = t.corners[i]
    local u1, u2, v1, v2
    if c.h < 0 then u1, u2 = c.x - e, c.x + n else u1, u2 = c.x - n, c.x + e end
    if c.v > 0 then v1, v2 = c.y - e, c.y + n else v1, v2 = c.y - n, c.y + e end
    local piece = Texture(frame, "BORDER", t.path, u1 / aw, u2 / aw, v1 / ah, v2 / ah)
    if piece then
      pcall(piece.SetWidth, piece, (e + n) * s)
      pcall(piece.SetHeight, piece, (e + n) * s)
      pcall(piece.SetPoint, piece, c.point, frame, c.point, c.h * shift, c.v * shift)
    end
  end

  local function Edge(slice)
    return Texture(frame, "BORDER", t.path,
      slice.u1 / aw, slice.u2 / aw, slice.v1 / ah, slice.v2 / ah)
  end
  local reach = inset + n * s
  local halfT = (t.top.v2 - t.top.v1) / 2 * s
  local halfB = (t.bottom.v2 - t.bottom.v1) / 2 * s
  local halfL = (t.left.u2 - t.left.u1) / 2 * s
  local halfR = (t.right.u2 - t.right.u1) / 2 * s
  pcall(function()
    local top = Edge(t.top)
    top:SetHeight(halfT * 2)
    top:SetPoint("TOPLEFT", frame, "TOPLEFT", reach, -inset + halfT)
    top:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -reach, -inset + halfT)
    local bottom = Edge(t.bottom)
    bottom:SetHeight(halfB * 2)
    bottom:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", reach, inset - halfB)
    bottom:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -reach, inset - halfB)
    local left = Edge(t.left)
    left:SetWidth(halfL * 2)
    left:SetPoint("TOPLEFT", frame, "TOPLEFT", inset - halfL, -reach)
    left:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", inset - halfL, reach)
    local right = Edge(t.right)
    right:SetWidth(halfR * 2)
    right:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -inset + halfR, -reach)
    right:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -inset + halfR, reach)
  end)
end

local function RedButton(parent, text, width, onClick)
  local ok, button = pcall(CreateFrame, "Button", nil, parent)
  if not ok or not button then return nil end
  local t = BUTTON
  pcall(button.SetWidth, button, width)
  pcall(button.SetHeight, button, BUTTON_HEIGHT)
  pcall(button.EnableMouse, button, true)
  pcall(button.RegisterForClicks, button, "LeftButtonUp")

  local scale = BUTTON_HEIGHT / t.cellHeight
  local left = Texture(button, "BACKGROUND", t.path)
  local middle = Texture(button, "BACKGROUND", t.path)
  local right = Texture(button, "BACKGROUND", t.path)
  if not left or not middle or not right then return nil end
  pcall(left.SetWidth, left, t.leftWidth * scale)
  pcall(right.SetWidth, right, t.cap * scale)
  pcall(left.SetPoint, left, "TOPLEFT", button, "TOPLEFT", 0, 0)
  pcall(left.SetPoint, left, "BOTTOMLEFT", button, "BOTTOMLEFT", 0, 0)
  pcall(right.SetPoint, right, "TOPRIGHT", button, "TOPRIGHT", 0, 0)
  pcall(right.SetPoint, right, "BOTTOMRIGHT", button, "BOTTOMRIGHT", 0, 0)
  pcall(middle.SetPoint, middle, "TOPLEFT", left, "TOPRIGHT", 0, 0)
  pcall(middle.SetPoint, middle, "BOTTOMRIGHT", right, "BOTTOMLEFT", 0, 0)

  local g = t.glow
  local glow = Texture(button, "OVERLAY", t.path, g[1] / t.atlasWidth,
    g[2] / t.atlasWidth, g[3] / t.atlasHeight, g[4] / t.atlasHeight)
  if glow then
    pcall(glow.SetBlendMode, glow, "ADD")
    pcall(glow.SetVertexColor, glow, t.glowIntensity, t.glowIntensity, t.glowIntensity, 1)
    pcall(glow.SetPoint, glow, "TOPLEFT", button, "TOPLEFT", -t.glowMargin, t.glowMargin)
    pcall(glow.SetPoint, glow, "BOTTOMRIGHT", button, "BOTTOMRIGHT", t.glowMargin, -t.glowMargin)
    pcall(glow.Hide, glow)
  end

  local function Slice(texture, u1, u2, top)
    pcall(texture.SetTexCoord, texture, u1 / t.atlasWidth, u2 / t.atlasWidth,
      top / t.atlasHeight, (top + t.cellHeight) / t.atlasHeight)
  end
  local hovered, pressed = false, false
  local function Paint()
    local cell = pressed and t.pressed or t.normal
    Slice(left, cell.capLeft, cell.capLeft + t.leftWidth, cell.capTop)
    Slice(middle, t.barLeft, t.barWidth - t.cap, cell.barTop)
    Slice(right, t.barWidth - t.cap, t.barWidth, cell.barTop)
    if glow then
      if hovered and not pressed then pcall(glow.Show, glow) else pcall(glow.Hide, glow) end
    end
  end
  Paint()

  local label = Label(button, "GameFontNormal", text)
  if label then
    pcall(label.SetPoint, label, "CENTER", button, "CENTER", 0, 0)
    pcall(label.SetTextColor, label, 1, 1, 1)
  end

  pcall(button.SetScript, button, "OnEnter", function() hovered = true; Paint() end)
  pcall(button.SetScript, button, "OnLeave", function()
    hovered, pressed = false, false
    Paint()
  end)
  pcall(button.SetScript, button, "OnMouseDown", function() pressed = true; Paint() end)
  pcall(button.SetScript, button, "OnMouseUp", function() pressed = false; Paint() end)
  pcall(button.SetScript, button, "OnClick", onClick)
  return button
end

-- lines: centred paragraphs stacked under the title, each { text, gap }.
-- buttons: { { text, onClick or nil }, ... }, one or two.
local function Build(height, lines, buttons)
  local ok, frame = pcall(CreateFrame, "Frame", "unrealMapSupportPopup", UIParent)
  if not ok or not frame then return nil end
  pcall(frame.SetFrameStrata, frame, "DIALOG")
  pcall(frame.SetWidth, frame, WIDTH)
  pcall(frame.SetHeight, frame, height)
  pcall(frame.SetPoint, frame, "CENTER", UIParent, "CENTER", 0, 0)
  pcall(frame.EnableMouse, frame, true)
  MetalFrame(frame, WIDTH, height)

  local title = Label(frame, "GameFontNormalLarge", TITLE)
  if title then pcall(title.SetPoint, title, "TOP", frame, "TOP", 0, -20) end

  local previous
  local i
  for i = 1, table.getn(lines) do
    local line = Label(frame, "GameFontHighlight", lines[i][1])
    if line then
      pcall(line.SetWidth, line, TEXT_WIDTH)
      pcall(line.SetJustifyH, line, "CENTER")
      if previous then
        pcall(line.SetPoint, line, "TOP", previous, "BOTTOM", 0, -lines[i][2])
      else
        pcall(line.SetPoint, line, "TOP", frame, "TOP", 0, -46)
      end
      previous = line
    end
  end

  -- Child frames are shown and hidden explicitly; this client does not
  -- reliably carry parent visibility to them (rendering.parent_alpha_not_propagated).
  local parts = {}
  local function Close()
    local k
    for k = 1, table.getn(parts) do pcall(parts[k].Hide, parts[k]) end
    pcall(frame.Hide, frame)
    stack.Layout()
  end

  -- buttons: one centred, or two side by side; each closes before its onClick.
  local count = table.getn(buttons)
  local width = BUTTON_WIDTH
  if count > 1 then width = (WIDTH - 2 * SIDE_INSET - PAIR_GAP) / 2 end
  for i = 1, count do
    local spec = buttons[i]
    local button = RedButton(frame, spec[1], width, function()
      Close()
      if spec[2] then spec[2]() end
    end)
    if not button then return nil end
    if count == 1 then
      pcall(button.SetPoint, button, "BOTTOM", frame, "BOTTOM", 0, BUTTON_BOTTOM)
    elseif i == 1 then
      pcall(button.SetPoint, button, "BOTTOMRIGHT", frame, "BOTTOM", -PAIR_GAP / 2, BUTTON_BOTTOM)
    else
      pcall(button.SetPoint, button, "BOTTOMLEFT", frame, "BOTTOM", PAIR_GAP / 2, BUTTON_BOTTOM)
    end
    table.insert(parts, button)
  end
  frame.parts = parts
  return frame
end

local function BuildSupport()
  return Build(HEIGHT, {
    { L("POPUP_QUESTION"), 0 },
    { L("POPUP_MESSAGE"), 0 },
    { L("POPUP_THANKS"), THANKS_GAP },
  }, {
    { L("POPUP_ALREADY_LIKED"), SetDismissed },
    { L("POPUP_WILL_LIKE") },
  })
end

local function BuildPackNotice()
  return Build(PACK_HEIGHT, {
    { L("POPUP_PACK_REQUIRED"), 0 },
    { L("POPUP_PACK_MESSAGE", Accent(REQUIRED_PACK)), THANKS_GAP },
    { L("POPUP_PACK_OPTIONAL", Accent(OPTIONAL_PACKS[1]), Accent(OPTIONAL_PACKS[2])), THANKS_GAP },
  }, { { L("COMMON_CLOSE") } })
end

local timer = CreateFrame("Frame", "unrealMapSupportPopupTimer", UIParent)
local started, fired
timer:SetScript("OnUpdate", function()
  if fired then return end
  local now = type(GetTime) == "function" and GetTime() or 0
  if not started then started = now end
  if now - started < SHOW_DELAY then return end
  fired = true
  timer:SetScript("OnUpdate", nil)
  timer:Hide()
  if RequiredPackMissing() then
    popup = popup or BuildPackNotice()
  else
    if Dismissed() then return end
    popup = popup or BuildSupport()
  end
  if not popup then return end
  stack.Register(popup)
  pcall(popup.Show, popup)
  local i
  for i = 1, table.getn(popup.parts) do pcall(popup.parts[i].Show, popup.parts[i]) end
  stack.Layout()
end)
