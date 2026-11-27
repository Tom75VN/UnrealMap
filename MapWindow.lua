--[[
unrealMap / MapWindow.lua

World map window: a minimize toggle beside the native close X, a minimized
map that can be dragged and resized while the game stays playable, and the
smooth zoom and drag-pan of MapZoom.lua. Ported from unrealUI's
modules/worldmap.lua and modules/worldmapzoom.lua (user request, 2026-11-27)
so the map has them without unrealUI.

One owner. With unrealMap installed these features run here only: unrealUI's
copies stand down and forward their U.WorldMapZoom* API to this table.
unrealUI keeps its own additions on the map (zone level label, cursor
readout); it registers them with W.Pin and W.UseExternalZoneLabel.

Client constraints carried over from unrealUI's measurements (knowledge.json):
  * map.worldmap_positioning_guide_owns_layout: the map is shrunk only with
    WorldMapFrame:SetScale, which every native child follows; no native
    anchor, size or script is changed.
  * frames.scaled_frame_edge_coordinates_mixed_space: on a scaled frame,
    GetWidth/GetHeight stay consistent, edge reads mix spaces.
  * map.worldmap_child_render_user_confirmed: addon controls on the map draw
    only as a level-120 Button child of WorldMapButton carrying file-backed
    textures; never hidden, cleared with alpha and mouse instead.
  * scripts.keyboard_frame_captures_all_input: a shown keyboard-enabled map
    takes the whole keyboard, so the minimized map turns its keyboard off.
  * UIParent is hidden by the client while the map is open. It is shown
    again around the minimized map, and at alpha 0 under the full-size map
    (the zoom's wheel catcher only receives the wheel as a UIParent child).
]]

if type(unrealMap) ~= "table" then return end

local W = {}
unrealMap.MapWindow = W

local MEDIA = "Interface\\AddOns\\unrealMap\\Media\\Textures\\UI\\"
W.texture = {
  -- Copies of unrealUI's modern-wow red-button and plus-minus atlases and its
  -- resize mark, renamed to unique basenames (assets/manifest.json ui.mapwindow).
  windowButton = MEDIA .. "unrealmap-window-button",
  zoomButton = MEDIA .. "unrealmap-zoom-button",
  resizeGrip = MEDIA .. "unrealmap-resize-grip",
  -- pandaUI's mouse-wheel icon for the "Zoom" hint (assets/manifest.json
  -- ui.mapwindow).
  zoomHint = MEDIA .. "unrealmap-mousewheel-zoom",
  plain = "Interface\\BUTTONS\\WHITE8X8",
}

-- unrealUI's M.worldMapWindow values, measured on this map (mapblackout.scan.v1,
-- mapwindow probe) and tuned in game by the user. The toggle sits one button
-- left of the native close X; offsets are from the canvas (WorldMapButton).
W.layout = {
  buttonSize = 20,
  buttonX = -28,
  buttonY = 57,
  minimizedScale = 0.6,
  minScale = 0.35,
  maxScale = 0.9,
  -- Drag strip along the minimized map's top edge, short of the close X.
  dragHeight = 32,
  dragRightInset = 56,
  gripSize = 20,
  gripX = 0,
  gripY = -15,
  zoneLabelWidth = 700,
  zoneLabelHeight = 40,
  zoneLabelY = -3,
  zoneLabelFontScale = 0.4,
  zoomButtonX = 8,
  zoomButtonY = 8,
  zoomButtonGap = 24,
  -- "Zoom" hint: its RIGHT this far from the canvas TOPRIGHT, on the native
  -- Zoom Out button's line in the header (21 above the canvas,
  -- mapblackout.scan.v1).
  zoomHintIcon = 22,
  zoomHintX = -8,
  zoomHintY = 21,
}

local layout = W.layout
local state = { pins = {} }
W.state = state

local FALLBACK_FONT = "Fonts\\FRIZQT__.TTF"
local FALLBACK_FONT_SIZE = 20
-- The native label's text before the client's first hover update.
local PLACEHOLDER_TEXT = "BLAH!"
local OPEN_TICK_SECONDS = 0.2

local function Num(object, method)
  if not object or type(object[method]) ~= "function" then return nil end
  local ok, value = pcall(object[method], object)
  if ok then return tonumber(value) end
  return nil
end
W.Num = Num

local function Now()
  if type(GetTime) ~= "function" then return 0 end
  local ok, t = pcall(GetTime)
  return ok and tonumber(t) or 0
end
W.Now = Now

local function CursorPixels()
  if type(GetCursorPosition) ~= "function" then return nil end
  local ok, x, y = pcall(GetCursorPosition)
  if not ok or not tonumber(x) or not tonumber(y) then return nil end
  return tonumber(x), tonumber(y)
end
W.CursorPixels = CursorPixels

-- Runs callback after the frame's current handler for script.
local function PostHookScript(frame, script, callback)
  if not frame or type(frame.GetScript) ~= "function" or
     type(frame.SetScript) ~= "function" then
    return false
  end
  local ok, previous = pcall(frame.GetScript, frame, script)
  if not ok then return false end
  if not previous then return pcall(frame.SetScript, frame, script, callback) end
  return pcall(frame.SetScript, frame, script, function(...)
    previous(...)
    callback(...)
  end)
end
W.PostHookScript = PostHookScript

-- The button name may arrive first, second (after the frame) or only in arg1.
local function IsLeftButton(a, b)
  local button
  if type(a) == "string" then
    button = a
  elseif type(b) == "string" then
    button = b
  else
    button = _G["arg1"]
  end
  return button == nil or button == "LeftButton"
end
W.IsLeftButton = IsLeftButton

local function ControlLevel(canvas)
  return math.max((Num(canvas, "GetFrameLevel") or 0) + 20, 120)
end
W.ControlLevel = ControlLevel

-- Read only once the map has been shown, after SavedVariables have loaded.
local function Config()
  if type(unrealMapDB) ~= "table" then unrealMapDB = {} end
  local config = unrealMapDB.mapWindow
  if type(config) ~= "table" then
    config = {}
    unrealMapDB.mapWindow = config
  end
  if config.minimizedScale ~= nil and type(config.minimizedScale) ~= "number" then
    config.minimizedScale = nil
  end
  return config
end

local function IsMinimized()
  return Config().minimized and true or false
end

-- ---------------------------------------------------------------------------
-- Public API, for unrealUI's forwarders and for other map addons.
-- ---------------------------------------------------------------------------

function W.IsMinimized()
  return IsMinimized()
end

-- Whether the world map is being drawn: the window driver, a WorldMapFrame
-- child, ticked this frame or the one before. WorldMapFrame:IsVisible does
-- not track the fullscreen presentation reliably on this client.
function W.IsOpen()
  return state.mapTickAt ~= nil and Now() - state.mapTickAt <= OPEN_TICK_SECONDS
end

-- Keeps a named frame on the map fixed while zoomed: counter-scaled and
-- anchored to the zoom view (MapZoom.lua), at point/relativePoint x, y.
function W.Pin(name, point, relativePoint, x, y)
  if type(name) ~= "string" then return false end
  local pins = state.pins
  -- MapZoom.lua re-pins only when the zoom or this counter changed.
  state.pinsVersion = (state.pinsVersion or 0) + 1
  local i
  for i = 1, table.getn(pins) do
    if pins[i].name == name then
      pins[i].point, pins[i].relativePoint = point, relativePoint
      pins[i].x, pins[i].y = x or 0, y or 0
      return true
    end
  end
  table.insert(pins, { name = name, point = point, relativePoint = relativePoint,
                       x = x or 0, y = y or 0 })
  return true
end

-- Another addon draws the hovered zone name itself (unrealUI's zone level
-- label); this file then leaves the native label and its own label alone.
function W.UseExternalZoneLabel()
  W.externalZoneLabel = true
  if state.zoneLabel then pcall(state.zoneLabel.SetText, state.zoneLabel, "") end
  state.zoneLabelText = ""
end

-- ---------------------------------------------------------------------------
-- Red glyph button (minimize / maximize), from the red-button atlas: a 5x3
-- grid of 34x38 cells on 256x128, the first at (2,2), stepping 38 across and
-- 40 down; columns minimize, close, maximize, minus; rows normal, disabled,
-- pushed. Cell (3,0) is the shared hover glow.
-- ---------------------------------------------------------------------------

local function AtlasCell(column, row)
  local left = 2 + 38 * column
  local top = 2 + 40 * row
  return { left / 256, (left + 34) / 256, top / 128, (top + 38) / 128 }
end

local GLYPH_CELLS = {
  minimizeNormal = AtlasCell(0, 0),
  minimizePushed = AtlasCell(0, 2),
  maximizeNormal = AtlasCell(2, 0),
  maximizePushed = AtlasCell(2, 2),
  highlight = AtlasCell(3, 0),
}

local function CreateGlyphButton(parent, name, size, glyph, onClick)
  local ok, button = pcall(CreateFrame, "Button", name, parent)
  if not ok or not button then return nil end
  button:SetWidth(size)
  button:SetHeight(size)
  pcall(button.EnableMouse, button, true)

  local function Piece(layer)
    local made, texture = pcall(button.CreateTexture, button, nil, layer)
    if not made or not texture then return nil end
    pcall(texture.SetTexture, texture, W.texture.windowButton)
    pcall(texture.SetAllPoints, texture, button)
    return texture
  end
  local face, glow = Piece("ARTWORK"), Piece("OVERLAY")
  if glow then
    local cell = GLYPH_CELLS.highlight
    pcall(glow.SetTexCoord, glow, cell[1], cell[2], cell[3], cell[4])
    pcall(glow.SetBlendMode, glow, "ADD")
    pcall(glow.Hide, glow)
  end

  local paint = { over = false, down = false, glyph = glyph }
  local function Paint()
    if not face then return end
    local cell = (paint.down and GLYPH_CELLS[paint.glyph .. "Pushed"]) or
                 GLYPH_CELLS[paint.glyph .. "Normal"]
    pcall(face.SetTexCoord, face, cell[1], cell[2], cell[3], cell[4])
    if glow then
      if paint.over then pcall(glow.Show, glow) else pcall(glow.Hide, glow) end
    end
  end
  button:SetScript("OnEnter", function() paint.over = true; Paint() end)
  button:SetScript("OnLeave", function() paint.over, paint.down = false, false; Paint() end)
  button:SetScript("OnMouseDown", function() paint.down = true; Paint() end)
  button:SetScript("OnMouseUp", function() paint.down = false; Paint() end)
  button:SetScript("OnClick", function() onClick() end)
  button.unrealMapSetGlyph = function(value)
    if not GLYPH_CELLS[tostring(value) .. "Normal"] then return end
    paint.glyph = value
    Paint()
  end
  Paint()
  return button
end

-- ---------------------------------------------------------------------------
-- Zone name on the map
--
-- The client draws WorldMapFrameAreaLabel twice: once in the map, scaled with
-- it, and once at the full-size map's place on screen. Both coincide at full
-- size; minimized, the second floats above the map. The second copy follows
-- the label's text and alpha, so it cannot be hidden alone: the native label
-- is faded and this label, a level-120 Button child of WorldMapButton with a
-- transparent file-backed texture, shows its text, smaller (zoneLabelFontScale)
-- and outlined, at both map sizes.
-- ---------------------------------------------------------------------------

local function AreaLabel()
  return _G["WorldMapFrameAreaLabel"]
end

-- Compared against the live alpha, not only the last write: something else
-- can restore the native label's alpha.
local function SetNativeLabelAlpha(area, alpha)
  if not area or type(area.SetAlpha) ~= "function" then return end
  local live = Num(area, "GetAlpha")
  if live then
    if math.abs(live - alpha) < 0.01 then
      state.nativeAlpha = alpha
      return
    end
  elseif state.nativeAlpha == alpha then
    return
  end
  if pcall(area.SetAlpha, area, alpha) then state.nativeAlpha = alpha end
end

local function EnsureZoneLabel()
  if state.zoneLabel then return state.zoneLabel end
  if state.zoneLabelFailed then return nil end
  local canvas = _G["WorldMapButton"]
  if not canvas then return nil end

  local ok, frame = pcall(CreateFrame, "Button", "unrealMapWorldMapZoneLabel", canvas)
  if not ok or not frame then
    state.zoneLabelFailed = true
    return nil
  end
  frame:SetWidth(layout.zoneLabelWidth)
  frame:SetHeight(layout.zoneLabelHeight)
  frame:SetPoint("TOP", canvas, "TOP", 0, layout.zoneLabelY)
  frame:SetFrameLevel(ControlLevel(canvas))
  if frame.EnableMouse then frame:EnableMouse(false) end

  local fill = frame:CreateTexture(nil, "BACKGROUND")
  fill:SetTexture(W.texture.plain)
  fill:SetAllPoints(frame)
  pcall(fill.SetVertexColor, fill, 0, 0, 0, 0)
  pcall(fill.SetAlpha, fill, 0)

  local made, label = pcall(frame.CreateFontString, frame, nil, "OVERLAY",
                            "GameFontNormalHuge")
  if not made or not label then
    made, label = pcall(frame.CreateFontString, frame, nil, "OVERLAY")
  end
  if not made or not label then
    state.zoneLabelFailed = true
    return nil
  end
  pcall(label.SetWidth, label, layout.zoneLabelWidth)
  pcall(label.SetHeight, label, layout.zoneLabelHeight)
  pcall(label.SetJustifyH, label, "CENTER")
  label:SetPoint("CENTER", frame, "CENTER", 0, 0)

  -- The native label's face at zoneLabelFontScale of its size. FontString:
  -- SetFont does nothing while a font object is assigned, so the size goes on
  -- a named Font attached with SetFontObject (fonts.named_font_justification_wins).
  local area = AreaLabel()
  local path, size, flags
  if area and type(area.GetFont) == "function" then
    local gotFont, p, s, f = pcall(area.GetFont, area)
    if gotFont and type(p) == "string" and tonumber(s) then
      path, size, flags = p, tonumber(s), f
    end
  end
  path = path or FALLBACK_FONT
  size = math.floor((size or FALLBACK_FONT_SIZE) * layout.zoneLabelFontScale + 0.5)
  local sx, sy, sr, sg, sb, sa = 1, -1, 0, 0, 0, 1
  if area and type(area.GetShadowOffset) == "function" then
    local got, x, y = pcall(area.GetShadowOffset, area)
    if got and tonumber(x) and tonumber(y) and (x ~= 0 or y ~= 0) then sx, sy = x, y end
  end
  if area and type(area.GetShadowColor) == "function" then
    local got, r, g, b, a = pcall(area.GetShadowColor, area)
    if got and tonumber(r) and tonumber(g) and tonumber(b) and (tonumber(a) or 1) > 0 then
      sr, sg, sb, sa = r, g, b, tonumber(a) or 1
    end
  end
  if type(CreateFont) == "function" and type(label.SetFontObject) == "function" then
    pcall(function()
      local font = CreateFont("unrealMapWorldMapZoneFont")
      font:SetFont(path, size, flags)
      if font.SetShadowColor then pcall(font.SetShadowColor, font, sr, sg, sb, sa) end
      if font.SetShadowOffset then pcall(font.SetShadowOffset, font, sx, sy) end
      label:SetFontObject(font)
    end)
  end
  if area and type(area.GetTextColor) == "function" then
    local gotColor, r, g, b = pcall(area.GetTextColor, area)
    if gotColor and tonumber(r) and tonumber(g) and tonumber(b) then
      pcall(label.SetTextColor, label, r, g, b)
    end
  end

  -- A thick outline, through FontString:SetFont with the stock face. That
  -- route draws larger than the font object at the same number, so the size
  -- is fitted to the font object's width of a sample. OUTLINE when THICK does
  -- not read back; the shadow stays when no outline reads back.
  local SAMPLE = "Ashenvale 18-30"
  local function SampleWidth()
    pcall(label.SetText, label, SAMPLE)
    local got, w = pcall(label.GetStringWidth, label)
    return got and tonumber(w) or nil
  end
  local outlined = false
  local wanted = SampleWidth()
  local outline = "THICKOUTLINE"
  if type(label.SetFont) == "function" and
     pcall(label.SetFont, label, FALLBACK_FONT, size, outline) then
    local gotThick, _, _, thickFlags = pcall(label.GetFont, label)
    if not (gotThick and type(thickFlags) == "string" and string.find(thickFlags, "THICK")) then
      outline = "OUTLINE"
      pcall(label.SetFont, label, FALLBACK_FONT, size, outline)
    end
    local drawn = SampleWidth()
    if wanted and drawn and wanted > 0 and drawn > 0 and
       math.abs(drawn - wanted) > wanted * 0.05 then
      local fitted = math.max(6, math.floor(size * wanted / drawn + 0.5))
      pcall(label.SetFont, label, FALLBACK_FONT, fitted, outline)
    end
    local got, _, _, gotFlags = pcall(label.GetFont, label)
    outlined = got and type(gotFlags) == "string" and
      string.find(gotFlags, "OUTLINE") ~= nil and true or false
  end
  if outlined then
    pcall(label.SetShadowColor, label, 0, 0, 0, 0)
    pcall(label.SetShadowOffset, label, 0, 0)
  else
    pcall(label.SetShadowOffset, label, sx, sy)
    pcall(label.SetShadowColor, label, sr, sg, sb, sa)
  end

  label:SetText("")
  state.zoneLabel = label
  state.zoneLabelText = ""
  return label
end

local function SetZoneLabelText(text)
  local label = state.zoneLabel
  if not label then
    if text == "" then return end
    label = EnsureZoneLabel()
    if not label then return end
  end
  if text ~= state.zoneLabelText then
    pcall(label.SetText, label, text)
    state.zoneLabelText = text
  end
end

local function RefreshZoneLabel()
  if W.externalZoneLabel then return end
  local area = AreaLabel()
  if not EnsureZoneLabel() then
    SetNativeLabelAlpha(area, 1)
    return
  end
  SetNativeLabelAlpha(area, 0)
  local text = ""
  if area and type(area.GetText) == "function" then
    local ok, value = pcall(area.GetText, area)
    if ok and type(value) == "string" and value ~= PLACEHOLDER_TEXT then text = value end
  end
  SetZoneLabelText(text)
end

-- ---------------------------------------------------------------------------
-- Map scale and placement
-- ---------------------------------------------------------------------------

-- The surround is faded, never hidden: the client's own show/hide of it is
-- untouched. BlackoutWorld, the black texture behind the map art, showed as
-- a black box around a minimized map.
local function HideBlackout()
  local blackout = _G["WorldMapBlackout"]
  if blackout and blackout.SetAlpha then pcall(blackout.SetAlpha, blackout, 0) end
  local backing = _G["BlackoutWorld"]
  if backing and backing.SetAlpha then pcall(backing.SetAlpha, backing, 0) end
end

-- Keeps the whole minimized map on screen. Offsets are in the map's own
-- scaled units, so the free room on WorldFrame is divided by the map scale.
local function ClampMapOffset(map, x, y, scale)
  local world = _G["WorldFrame"]
  local worldWidth, worldHeight = Num(world, "GetWidth"), Num(world, "GetHeight")
  local width, height = Num(map, "GetWidth"), Num(map, "GetHeight")
  x, y = tonumber(x) or 0, tonumber(y) or 0
  if not worldWidth or not worldHeight or not width or not height or scale <= 0 then
    return x, y
  end
  local maxX = math.max(0, (worldWidth - width * scale) / 2 / scale)
  local maxY = math.max(0, (worldHeight - height * scale) / 2 / scale)
  return math.max(-maxX, math.min(maxX, x)), math.max(-maxY, math.min(maxY, y))
end

-- The native anchor is CENTER on WorldFrame's CENTER at 0, 0, so the
-- full-size map is put back exactly there.
local function PlaceMap(map, x, y)
  local world = _G["WorldFrame"]
  if not map or not world then return end
  if state.placedX == x and state.placedY == y then return end
  pcall(map.ClearAllPoints, map)
  if pcall(map.SetPoint, map, "CENTER", world, "CENTER", x, y) then
    state.placedX, state.placedY = x, y
  end
end

local function MinimizedScale()
  local scale = tonumber(Config().minimizedScale) or layout.minimizedScale
  return math.max(layout.minScale, math.min(layout.maxScale, scale))
end

-- WorldMapBlackout is the only full-screen frame the map adds, so it stops
-- taking the mouse while minimized; its first state is put back at full size.
local function SetBlackoutMouse(minimized)
  local blackout = _G["WorldMapBlackout"]
  if not blackout or type(blackout.EnableMouse) ~= "function" then return end
  if state.blackoutMouse == nil and type(blackout.IsMouseEnabled) == "function" then
    local ok, enabled = pcall(blackout.IsMouseEnabled, blackout)
    if ok then state.blackoutMouse = enabled and true or false end
  end
  local want = (not minimized) and state.blackoutMouse or false
  pcall(blackout.EnableMouse, blackout, want and true or false)
end

-- Minimized: the HUD the client hid for the map is shown again, and hidden
-- again only if this file showed it.
local function SetHudForMap(minimized)
  local parent = _G["UIParent"]
  if not parent or type(parent.IsShown) ~= "function" then return end
  local ok, shown = pcall(parent.IsShown, parent)
  if not ok then return end
  if minimized then
    if not shown and parent.Show and pcall(parent.Show, parent) then
      state.hudForced = true
    end
  elseif state.hudForced then
    state.hudForced = nil
    if shown and parent.Hide then pcall(parent.Hide, parent) end
  end
end

-- Full size: UIParent is shown at alpha 0 ("veiled") under the map so the
-- zoom's wheel catcher, a UIParent child, receives the wheel while the HUD
-- stays unseen. The alpha goes back once the map closes or is minimized.
local veilDriver
local CheckHudVeil

local function SetHudVeil(on)
  local parent = _G["UIParent"]
  if not parent or type(parent.SetAlpha) ~= "function" or
     type(parent.IsShown) ~= "function" then
    return
  end
  if on then
    if not state.hudVeiled then
      state.hudAlpha = Num(parent, "GetAlpha") or 1
      -- Faded before it is shown, so the HUD never flashes over the map.
      if not pcall(parent.SetAlpha, parent, 0) then return end
      state.hudVeiled = true
      if veilDriver then
        veilDriver:SetScript("OnUpdate", CheckHudVeil)
        veilDriver:Show()
      end
    end
    local ok, shown = pcall(parent.IsShown, parent)
    if ok and not shown and parent.Show then pcall(parent.Show, parent) end
  elseif state.hudVeiled then
    state.hudVeiled = nil
    pcall(parent.SetAlpha, parent, state.hudAlpha or 1)
    if veilDriver then
      veilDriver:SetScript("OnUpdate", nil)
      veilDriver:Hide()
    end
  end
end

-- The map's own tick going stale is the close signal: the fullscreen
-- presentation does not track WorldMapFrame:IsShown reliably.
CheckHudVeil = function()
  if not state.hudVeiled then return end
  if IsMinimized() or not W.IsOpen() then SetHudVeil(false) end
end

-- A WorldFrame child, so it ticks with the map closed and UIParent hidden.
veilDriver = CreateFrame("Frame", "unrealMapWindowVeilDriver", _G["WorldFrame"] or UIParent)
veilDriver:Hide()

local function ApplyMapScale()
  local minimized = IsMinimized()
  local config = Config()
  local map = _G["WorldMapFrame"]
  if map and type(map.SetScale) == "function" then
    local scale = minimized and MinimizedScale() or 1
    if Num(map, "GetScale") ~= scale then pcall(map.SetScale, map, scale) end
    if minimized then
      PlaceMap(map, ClampMapOffset(map, config.mapX, config.mapY, scale))
    else
      PlaceMap(map, 0, 0)
    end
  end
  -- The glyph names the action: minimize while full size, maximize while small.
  local button = state.minimizeButton
  if button and button.unrealMapSetGlyph then
    button.unrealMapSetGlyph(minimized and "maximize" or "minimize")
  end
  local handle = state.dragHandle
  if handle and handle.EnableMouse then pcall(handle.EnableMouse, handle, minimized) end
  local grip = state.resizeGrip
  if grip then
    pcall(grip.EnableMouse, grip, minimized)
    if grip.unrealMapPaint then grip.unrealMapPaint() end
  end
  SetBlackoutMouse(minimized)
  -- The stock map is created keyboard-enabled and IsKeyboardEnabled does not
  -- exist here, so full size restores true. Written only on a change.
  local keyboard = not minimized
  if map and type(map.EnableKeyboard) == "function" and state.mapKeyboard ~= keyboard and
     (minimized or state.mapKeyboard ~= nil) then
    if pcall(map.EnableKeyboard, map, keyboard) then state.mapKeyboard = keyboard end
  end
  if minimized then SetHudVeil(false) else SetHudForMap(false) end
end

-- The client's hide of UIParent is undone in the same frame: on the map's
-- OnShow, and in UIParent's OnHide when the map opened this frame (GetTime is
-- a per-frame snapshot) or ticked in the last 0.2 s. A HUD hidden with the map
-- closed (Alt+Z) is left alone.
local function OnHudHidden()
  if not state.built then return end
  local now = Now()
  local opening = state.mapShownAt == now
  if not opening and not W.IsOpen() then return end
  if IsMinimized() then SetHudForMap(true) else SetHudVeil(true) end
end

-- ---------------------------------------------------------------------------
-- Dragging and resizing the minimized map
--
-- Not StartMoving: the map is a scaled native frame parented to WorldFrame,
-- where edge reads mix spaces. The CENTER offset follows the cursor delta on
-- the map's own per-frame tick, divided by the map's effective scale, and is
-- saved on release. The size is fixed by the positioning guide, so the grip
-- sets the scale, keeping the top-left corner where it was.
-- ---------------------------------------------------------------------------

-- No documented mouse-button query: a missing one reads "still held" and the
-- release scripts end the drag.
local function LeftButtonStillDown()
  if type(IsMouseButtonDown) ~= "function" then return true end
  local ok, down = pcall(IsMouseButtonDown, "LeftButton")
  if not ok then return true end
  return down and down ~= 0 and true or false
end

local function MoveMapToCursor()
  local drag = state.drag
  local map = _G["WorldMapFrame"]
  if not drag or not map then return end
  local x, y = CursorPixels()
  if not x then return end
  local offsetX = drag.startX + (x - drag.cursorX) / drag.effective
  local offsetY = drag.startY + (y - drag.cursorY) / drag.effective
  offsetX, offsetY = ClampMapOffset(map, offsetX, offsetY, drag.scale)
  drag.x, drag.y = offsetX, offsetY
  PlaceMap(map, offsetX, offsetY)
end

local function StopMapDrag()
  local drag = state.drag
  if not drag then return end
  MoveMapToCursor()
  state.drag = nil
  local config = Config()
  config.mapX, config.mapY = drag.x, drag.y
end

local function StartMapDrag()
  if state.drag or state.resize then return end
  local config = Config()
  local map = _G["WorldMapFrame"]
  if not config.minimized or not map then return end
  local x, y = CursorPixels()
  local scale = Num(map, "GetScale")
  local effective = Num(map, "GetEffectiveScale")
  if not x or not scale or scale <= 0 or not effective or effective <= 0 then return end
  local startX, startY = ClampMapOffset(map, config.mapX, config.mapY, scale)
  state.drag = {
    cursorX = x, cursorY = y, startX = startX, startY = startY,
    x = startX, y = startY, scale = scale, effective = effective,
  }
end

local function ResizeMapToCursor()
  local resize = state.resize
  local map = _G["WorldMapFrame"]
  if not resize or not map then return end
  local x, y = CursorPixels()
  if not x then return end
  local dx = (x - resize.cursorX) / resize.parentScale
  local dy = (y - resize.cursorY) / resize.parentScale
  local w, h = resize.width, resize.height
  local scale = math.max((w * resize.scale + dx) / w, (h * resize.scale - dy) / h)
  local maxScale = math.min(layout.maxScale, resize.fitScale)
  scale = math.max(layout.minScale, math.min(maxScale, scale))
  -- Steps of 1/200 keep a still cursor from re-laying the map out each frame.
  scale = math.floor(scale * 200 + 0.5) / 200
  local offsetX = (resize.topLeftX + w / 2 * scale) / scale
  local offsetY = (resize.topLeftY - h / 2 * scale) / scale
  offsetX, offsetY = ClampMapOffset(map, offsetX, offsetY, scale)
  if scale ~= resize.current then
    pcall(map.SetScale, map, scale)
    resize.current = scale
  end
  resize.x, resize.y = offsetX, offsetY
  PlaceMap(map, offsetX, offsetY)
end

local function StopMapResize()
  local resize = state.resize
  if not resize then return end
  ResizeMapToCursor()
  state.resize = nil
  local config = Config()
  config.minimizedScale = resize.current
  config.mapX, config.mapY = resize.x, resize.y
  if state.resizeGrip and state.resizeGrip.unrealMapPaint then
    state.resizeGrip.unrealMapPaint()
  end
end

local function StartMapResize()
  if state.resize or state.drag then return end
  local config = Config()
  local map, world = _G["WorldMapFrame"], _G["WorldFrame"]
  if not config.minimized or not map or not world then return end
  local x, y = CursorPixels()
  local scale = Num(map, "GetScale")
  local effective = Num(map, "GetEffectiveScale")
  local width, height = Num(map, "GetWidth"), Num(map, "GetHeight")
  local worldWidth, worldHeight = Num(world, "GetWidth"), Num(world, "GetHeight")
  if not x or not scale or scale <= 0 or not effective or effective <= 0 or
     not width or width <= 0 or not height or height <= 0 or
     not worldWidth or not worldHeight then
    return
  end
  local offsetX, offsetY = ClampMapOffset(map, config.mapX, config.mapY, scale)
  state.resize = {
    cursorX = x, cursorY = y, scale = scale, current = scale,
    parentScale = effective / scale, width = width, height = height,
    fitScale = math.min(worldWidth / width, worldHeight / height),
    topLeftX = offsetX * scale - width / 2 * scale,
    topLeftY = offsetY * scale + height / 2 * scale,
    x = offsetX, y = offsetY,
  }
end

local function UpdateMapDrag()
  if not state.drag and not state.resize then return end
  if not LeftButtonStillDown() then
    StopMapDrag()
    StopMapResize()
    return
  end
  if state.drag then MoveMapToCursor() end
  if state.resize then ResizeMapToCursor() end
end

local function BuildDragHandle(map)
  local ok, handle = pcall(CreateFrame, "Button", "unrealMapWorldMapDragHandle", map)
  if not ok or not handle then return end
  handle:SetPoint("TOPLEFT", map, "TOPLEFT", 0, 0)
  handle:SetPoint("TOPRIGHT", map, "TOPRIGHT", -layout.dragRightInset, 0)
  handle:SetHeight(layout.dragHeight)
  handle:SetFrameLevel((Num(map, "GetFrameLevel") or 0) + 2)
  pcall(handle.RegisterForDrag, handle, "LeftButton")
  handle:SetScript("OnMouseDown", function(a, b)
    if IsLeftButton(a, b) then StartMapDrag() end
  end)
  handle:SetScript("OnMouseUp", function(a, b)
    if IsLeftButton(a, b) then StopMapDrag() end
  end)
  handle:SetScript("OnDragStop", StopMapDrag)
  handle:SetScript("OnHide", StopMapDrag)
  pcall(handle.EnableMouse, handle, false)
  state.dragHandle = handle
end

-- Built like the minimize toggle (never hidden; the full-size map clears it
-- with alpha and mouse). Dim at rest, full hovered or held.
local function BuildResizeGrip(canvas)
  local ok, grip = pcall(CreateFrame, "Button", "unrealMapWorldMapResizeGrip", canvas)
  if not ok or not grip then return end
  grip:SetWidth(layout.gripSize)
  grip:SetHeight(layout.gripSize)
  grip:SetPoint("CENTER", canvas, "BOTTOMRIGHT", layout.gripX, layout.gripY)
  grip:SetFrameLevel(ControlLevel(canvas))
  pcall(grip.EnableMouse, grip, true)
  pcall(grip.RegisterForDrag, grip, "LeftButton")
  local icon = grip:CreateTexture(nil, "ARTWORK")
  pcall(icon.SetTexture, icon, W.texture.resizeGrip)
  pcall(icon.SetAllPoints, icon, grip)

  local over = false
  local function Paint()
    local alpha = 0
    if IsMinimized() then alpha = (over or state.resize) and 1 or 0.7 end
    pcall(icon.SetAlpha, icon, alpha)
  end
  grip.unrealMapPaint = Paint
  grip:SetScript("OnEnter", function() over = true; Paint() end)
  grip:SetScript("OnLeave", function() over = false; Paint() end)
  grip:SetScript("OnMouseDown", function(a, b)
    if IsLeftButton(a, b) then StartMapResize(); Paint() end
  end)
  grip:SetScript("OnMouseUp", function(a, b)
    if IsLeftButton(a, b) then StopMapResize() end
  end)
  grip:SetScript("OnDragStop", StopMapResize)
  grip:SetScript("OnHide", StopMapResize)
  Paint()
  state.resizeGrip = grip
end

local function ToggleMinimized()
  local config = Config()
  config.minimized = not config.minimized
  ApplyMapScale()
end

local function BuildMinimizeButton(canvas)
  local button = CreateGlyphButton(canvas, "unrealMapWorldMapMinimizeButton",
                                   layout.buttonSize, "minimize", ToggleMinimized)
  if not button then return end
  button:SetPoint("CENTER", canvas, "TOPRIGHT", layout.buttonX, layout.buttonY)
  button:SetFrameLevel(ControlLevel(canvas))
  state.minimizeButton = button
end

-- ---------------------------------------------------------------------------
-- Lifecycle
-- ---------------------------------------------------------------------------

-- One tick while the map is drawn: a WorldMapFrame child, so it runs with
-- UIParent hidden and also while a dungeon view hides WorldMapButton.
local function OnMapTick()
  state.mapTickAt = Now()
  if IsMinimized() then SetHudForMap(true) else SetHudVeil(true) end
  UpdateMapDrag()
  RefreshZoneLabel()
  if W.ZoomDrive then W.ZoomDrive() end
end

local function Build()
  if state.built then return true end
  local map, canvas = _G["WorldMapFrame"], _G["WorldMapButton"]
  if not map or not canvas then return false end
  state.built = true
  W.Pin("unrealMapWorldMapZoneLabel", "TOP", "TOP", 0, layout.zoneLabelY)
  W.Pin("unrealMapWorldMapMinimizeButton", "CENTER", "TOPRIGHT",
        layout.buttonX, layout.buttonY)
  W.Pin("unrealMapWorldMapResizeGrip", "CENTER", "BOTTOMRIGHT",
        layout.gripX, layout.gripY)
  BuildMinimizeButton(canvas)
  BuildDragHandle(map)
  BuildResizeGrip(canvas)
  if W.ZoomBuild then W.ZoomBuild(map, canvas) end
  local driver = CreateFrame("Frame", "unrealMapWindowDriver", map)
  driver:SetScript("OnUpdate", OnMapTick)
  PostHookScript(_G["UIParent"], "OnHide", OnHudHidden)
  return true
end

-- The client may re-anchor its map when it opens, so the placement cache is
-- dropped and the scale and offset are written again on every show.
local function OnMapShow()
  if not Build() then return end
  HideBlackout()
  state.mapShownAt = Now()
  state.placedX, state.placedY = nil, nil
  if IsMinimized() then state.mapKeyboard = nil end
  ApplyMapScale()
  if IsMinimized() then SetHudForMap(true) else SetHudVeil(true) end
end

PostHookScript(_G["WorldMapFrame"], "OnShow", OnMapShow)
