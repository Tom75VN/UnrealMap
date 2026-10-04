--[[
unrealMap / SupportPopup.lua

A one-time support reminder shown a few seconds after the UI loads, until the
player ticks "Don't show again". Its art is UnrealUI's Modern WoW popup set,
imported under Media/Textures/UI (provenance in assets/manifest.json). Every
region is created on first show only, so a dismissed popup costs one timer
frame for a few seconds and no texture.
]]

local SHOW_DELAY = 6
local DISMISSED_KEY = "supportPopupDismissed"

local MEDIA = "Interface\\AddOns\\unrealMap\\Media\\Textures\\UI\\"
local PLAIN_TEXTURE = "Interface\\Buttons\\WHITE8X8"

local WIDTH = 368
local HEIGHT = 168
local TEXT_WIDTH = 312
local BUTTON_WIDTH = 132
local BUTTON_HEIGHT = 30
local BUTTON_BOTTOM = 16
local CHECK_BOTTOM = 60
local THANKS_GAP = 6
local CHECK_WIDTH = 16
local CHECK_HEIGHT = 15

local TITLE = "|cffffffffUnreal |cfff5ae0aMap|r"
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

-- UnrealUI M.foreverWow.control.checkbox: box and tick on one 64x64 sheet.
local CHECK = {
  path = MEDIA .. "unrealmap-popup-checkmark",
  sheet = 64,
  box = { 1, 31, 1, 30 },
  tick = { 1, 31, 32, 61 },
}

local popup

local function Dismissed()
  local db = _G["unrealMapDB"]
  return type(db) == "table" and db[DISMISSED_KEY] == true
end

local function SetDismissed(value)
  if type(unrealMapDB) ~= "table" then unrealMapDB = {} end
  unrealMapDB[DISMISSED_KEY] = value and true or nil
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

local function RedButton(parent, text, onClick)
  local ok, button = pcall(CreateFrame, "Button", nil, parent)
  if not ok or not button then return nil end
  local t = BUTTON
  pcall(button.SetWidth, button, BUTTON_WIDTH)
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

-- The whole row (box and label) is one Button so the text toggles too.
local function Checkbox(parent, text, onChange)
  local ok, row = pcall(CreateFrame, "Button", nil, parent)
  if not ok or not row then return nil end
  pcall(row.EnableMouse, row, true)
  pcall(row.RegisterForClicks, row, "LeftButtonUp")
  pcall(row.SetHeight, row, CHECK_HEIGHT)

  local s = CHECK.sheet
  local b, k = CHECK.box, CHECK.tick
  local box = Texture(row, "ARTWORK", CHECK.path, b[1] / s, b[2] / s, b[3] / s, b[4] / s)
  local tick = Texture(row, "OVERLAY", CHECK.path, k[1] / s, k[2] / s, k[3] / s, k[4] / s)
  if not box or not tick then return nil end
  local parts = { box, tick }
  local i
  for i = 1, 2 do
    pcall(parts[i].SetWidth, parts[i], CHECK_WIDTH)
    pcall(parts[i].SetHeight, parts[i], CHECK_HEIGHT)
    pcall(parts[i].SetPoint, parts[i], "LEFT", row, "LEFT", 0, 0)
  end

  local label = Label(row, "GameFontHighlightSmall", text)
  local width = CHECK_WIDTH + 6
  if label then
    pcall(label.SetPoint, label, "LEFT", row, "LEFT", CHECK_WIDTH + 6, 0)
    local measured, value = pcall(label.GetStringWidth, label)
    value = measured and tonumber(value) or 0
    width = width + (value > 0 and value or 100)
  end
  pcall(row.SetWidth, row, width)

  local checked = false
  local function Sync()
    if checked then pcall(tick.Show, tick) else pcall(tick.Hide, tick) end
  end
  Sync()
  pcall(row.SetScript, row, "OnClick", function()
    checked = not checked
    Sync()
    onChange(checked)
  end)
  return row
end

local function Build()
  local ok, frame = pcall(CreateFrame, "Frame", "unrealMapSupportPopup", UIParent)
  if not ok or not frame then return nil end
  pcall(frame.SetFrameStrata, frame, "DIALOG")
  pcall(frame.SetWidth, frame, WIDTH)
  pcall(frame.SetHeight, frame, HEIGHT)
  pcall(frame.SetPoint, frame, "CENTER", UIParent, "CENTER", 0, 0)
  pcall(frame.EnableMouse, frame, true)
  MetalFrame(frame, WIDTH, HEIGHT)

  local title = Label(frame, "GameFontNormalLarge", TITLE)
  if title then pcall(title.SetPoint, title, "TOP", frame, "TOP", 0, -20) end

  local question = Label(frame, "GameFontHighlight", L("POPUP_QUESTION"))
  if question then
    pcall(question.SetWidth, question, TEXT_WIDTH)
    pcall(question.SetJustifyH, question, "CENTER")
    pcall(question.SetPoint, question, "TOP", frame, "TOP", 0, -46)
  end

  local message = Label(frame, "GameFontHighlight", L("POPUP_MESSAGE"))
  if message and question then
    pcall(message.SetWidth, message, TEXT_WIDTH)
    pcall(message.SetJustifyH, message, "CENTER")
    pcall(message.SetPoint, message, "TOP", question, "BOTTOM", 0, 0)
  end

  local thanks = Label(frame, "GameFontHighlight", L("POPUP_THANKS"))
  if thanks and message then
    pcall(thanks.SetWidth, thanks, TEXT_WIDTH)
    pcall(thanks.SetJustifyH, thanks, "CENTER")
    pcall(thanks.SetPoint, thanks, "TOP", message, "BOTTOM", 0, -THANKS_GAP)
  end

  local check = Checkbox(frame, L("POPUP_DONT_SHOW"), SetDismissed)
  if check then
    local width = 0
    local measured, value = pcall(check.GetWidth, check)
    if measured and tonumber(value) then width = tonumber(value) end
    pcall(check.SetPoint, check, "BOTTOMLEFT", frame, "BOTTOM", -width / 2, CHECK_BOTTOM)
  end

  -- Child frames are shown and hidden explicitly; this client does not
  -- reliably carry parent visibility to them (rendering.parent_alpha_not_propagated).
  local close
  close = RedButton(frame, L("COMMON_CLOSE"), function()
    pcall(check.Hide, check)
    pcall(close.Hide, close)
    pcall(frame.Hide, frame)
  end)
  if not check or not close then return nil end
  pcall(close.SetPoint, close, "BOTTOM", frame, "BOTTOM", 0, BUTTON_BOTTOM)
  frame.parts = { check, close }
  return frame
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
  if Dismissed() then return end
  popup = popup or Build()
  if not popup then return end
  pcall(popup.Show, popup)
  local i
  for i = 1, table.getn(popup.parts) do pcall(popup.parts[i].Show, popup.parts[i]) end
end)
