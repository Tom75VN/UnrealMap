--[[
unrealMap / MapZoom.lua

Smooth zoom and drag-pan on the world map, minimized and full size. Ported
from unrealUI's modules/worldmapzoom.lua (user request, 2026-11-27); built and
driven by MapWindow.lua, which owns the map window.

Evidence (knowledge.json / map.worldmap_zoom_scaled_canvas_unclipped,
UnrealRuntimeProbe mapzoom.v1-v2):
  * WorldMapDetailFrame and WorldMapButton can be reparented into an addon
    frame and scaled: every hover/pin child follows and the move restores.
  * Nothing clips them (a ScrollFrame did not), so the zoom clips by hand:
    every WorldMapDetailTileN and WorldMapOverlayN is re-anchored, resized
    and SetTexCoord-cropped (4-value form) to the visible window. The HD
    bindings of unrealMap.lua only call SetTexture on those same regions, so
    the crop survives a rebind.
  * The wheel reaches only a never-mouse-enabled catcher ScrollFrame parented
    to UIParent; MapWindow.lua keeps UIParent shown while the map is open.
  * The drag ends on WorldMapButton's OnMouseUp, whose native handler (the
    zoom in/out click) is skipped after a drag.

  WorldMapFrame
    unrealMapWorldMapZoomView     (the canvas rectangle, never scaled)
      unrealMapWorldMapZoomContent  (scaled by the zoom, anchored -pan)
        WorldMapDetailFrame, WorldMapButton

Installed on the first zoom only; at zoom 1 the content sits exactly where the
canvases were. Pinned chrome (MapWindow.Pin) is counter-scaled and anchored to
the view so it does not zoom or move.
]]

local W = type(unrealMap) == "table" and unrealMap.MapWindow
if type(W) ~= "table" then return end

local Num, Now, Cursor = W.Num, W.Now, W.CursorPixels
local layout = W.layout

local MIN_ZOOM = 1
-- One stop per wheel notch, each about x1.12 so every notch feels the same
-- (user request, 2026-11-27: even steps instead of +0.5).
local ZOOM_STOPS = { 1, 1.12, 1.26, 1.41, 1.59, 1.78, 2, 2.24, 2.52, 2.83, 3.17, 3.56, 4 }
local DRAG_PIXELS = 4
local SWEEP_SECONDS = 0.25 -- re-crop interval while zoomed
local OPEN_TICK_SECONDS = 0.2
-- The zoom eases toward its target in log space (about 95% of a step in
-- 0.25 s) and snaps onto it; a fast drag release glides with exponential
-- friction. Speeds are in view units per second.
local ZOOM_RATE = 12
local ZOOM_SNAP = 0.002
local MAX_FRAME_TIME = 0.1
local GLIDE_FRICTION = 5
local GLIDE_START_SPEED = 60
local GLIDE_STOP_SPEED = 15
local GLIDE_MAX_SPEED = 4000
local GLIDE_RELEASE_WINDOW = 0.08
-- WorldMapDetailFrame's place on the 1024x768 guide (mapblackout.scan.v1).
local ANCHOR_X, ANCHOR_Y = -502, -69
-- unrealMap.lua binds 12 tiles and at most 64 overlays.
local TILE_SLOTS, OVERLAY_SLOTS, POI_SLOTS = 16, 64, 64

local state = {
  installed = false,
  zoom = 1, panX = 0, panY = 0,
  targetZoom = 1,
  gliding = false, velX = 0, velY = 0,
  -- Bumped when the zoom or the visible window settles; other addons repaint
  -- their markers when it changes (W.ZoomState).
  version = 0,
  -- Bumped on every placement, drag frames included.
  moveVersion = 0,
  regions = {},
  pois = {},
  -- Last placement of frames placed through W.ZoomPlace, by frame.
  markers = {},
  sweepAt = 0,
}
W.zoomState = state

local function Clamp(value, low, high)
  if value < low then return low end
  if value > high then return high end
  return value
end

-- Cursor in view units from its TOPLEFT (y down), and whether it is inside.
local function CursorInView()
  local view = state.view
  local x, y = Cursor()
  local scale = Num(view, "GetEffectiveScale")
  local left, top = Num(view, "GetLeft"), Num(view, "GetTop")
  if not x or not scale or scale <= 0 or not left or not top then return nil end
  local cx, cy = x / scale - left, top - y / scale
  return cx, cy, cx >= 0 and cy >= 0 and cx <= state.width and cy <= state.height
end

-- The visible window, in canvas (WorldMapDetailFrame) units.
local function Window()
  return state.panX, state.panY,
         state.panX + state.width / state.zoom, state.panY + state.height / state.zoom
end

-- ---------------------------------------------------------------------------
-- Cropping. A region's base (place, size, texcoords) is read only while the
-- canvas is at zoom 1: on the scaled canvas the edge reads drift.
-- ---------------------------------------------------------------------------

-- Position of a region inside WorldMapDetailFrame, in its units (y down).
local function RegionBox(region)
  local detail = state.detail
  local dScale = Num(detail, "GetEffectiveScale")
  local rScale = Num(region, "GetEffectiveScale") or dScale
  local dLeft, dTop = Num(detail, "GetLeft"), Num(detail, "GetTop")
  local left, top = Num(region, "GetLeft"), Num(region, "GetTop")
  local w, h = Num(region, "GetWidth"), Num(region, "GetHeight")
  if not dScale or dScale <= 0 or not dLeft or not dTop or not left or
     not top or not w or not h then
    return nil
  end
  return (left * rScale - dLeft * dScale) / dScale,
         (dTop * dScale - top * rScale) / dScale, w, h
end

local function TexCoords(region)
  if type(region.GetTexCoord) ~= "function" then return 0, 1, 0, 1 end
  local ok, a, b, c, d, e = pcall(region.GetTexCoord, region)
  if not ok or not tonumber(a) or not tonumber(e) then return 0, 1, 0, 1 end
  -- 8-value readback (UL, LL, UR, LR); only the 4-value form draws here
  -- (textures.settexcoord_rotated_8_value_form_ignored).
  return a, e, b, d
end

local function TakeBase(entry)
  local x, y, w, h = RegionBox(entry.region)
  if not x or w <= 0 or h <= 0 then
    entry.base = nil
    return
  end
  local l, r, t, b = TexCoords(entry.region)
  local base = entry.base or {}
  base.x, base.y, base.w, base.h = x, y, w, h
  base.l, base.r, base.t, base.b = l, r, t, b
  entry.base = base
end

-- Only the values that changed since the entry was last placed are written:
-- a drag frame moves only the regions on the window's edges, while interior
-- and out-of-view ones keep their placement. `force` writes everything, for
-- when the client may have rewritten the region itself.
local function Place(entry, x, y, w, h, l, r, t, b, alpha, force)
  local region = entry.region
  if force or entry.pa ~= alpha then
    pcall(region.SetAlpha, region, alpha)
    entry.pa = alpha
  end
  if force or entry.px ~= x or entry.py ~= y then
    pcall(region.ClearAllPoints, region)
    pcall(region.SetPoint, region, "TOPLEFT", state.detail, "TOPLEFT", x, -y)
    entry.px, entry.py = x, y
  end
  if force or entry.pw ~= w then
    pcall(region.SetWidth, region, w)
    entry.pw = w
  end
  if force or entry.ph ~= h then
    pcall(region.SetHeight, region, h)
    entry.ph = h
  end
  if force or entry.pl ~= l or entry.pr ~= r or entry.pt ~= t or entry.pb ~= b then
    pcall(region.SetTexCoord, region, l, r, t, b)
    entry.pl, entry.pr, entry.pt, entry.pb = l, r, t, b
  end
end

local function CropRegion(entry, restore, force)
  local base = entry.base
  if not base then return end
  if restore then
    Place(entry, base.x, base.y, base.w, base.h, base.l, base.r, base.t, base.b, 1, force)
    return
  end
  local vx0, vy0, vx1, vy1 = Window()
  local ix0, iy0 = math.max(base.x, vx0), math.max(base.y, vy0)
  local ix1, iy1 = math.min(base.x + base.w, vx1), math.min(base.y + base.h, vy1)
  if ix1 <= ix0 or iy1 <= iy0 then
    -- Out of view: kept at its base, faded (never hidden, so the client's own
    -- show/hide of overlays stays in charge).
    Place(entry, base.x, base.y, base.w, base.h, base.l, base.r, base.t, base.b, 0, force)
    return
  end
  local du, dv = base.r - base.l, base.b - base.t
  Place(entry, ix0, iy0, ix1 - ix0, iy1 - iy0,
        base.l + (ix0 - base.x) / base.w * du, base.l + (ix1 - base.x) / base.w * du,
        base.t + (iy0 - base.y) / base.h * dv, base.t + (iy1 - base.y) / base.h * dv, 1,
        force)
end

local function CollectRegions()
  local i
  for i = 1, TILE_SLOTS do
    local tile = _G["WorldMapDetailTile" .. i]
    if tile then table.insert(state.regions, { region = tile, tile = true }) end
  end
  for i = 1, OVERLAY_SLOTS do
    local overlay = _G["WorldMapOverlay" .. i]
    if overlay then table.insert(state.regions, { region = overlay }) end
  end
end

-- tilesOnly: after a map change the client has just rewritten the overlays
-- for the new map, so only the tiles (whose place never changes) go back;
-- overlays only get their alpha back.
local function CropAll(restore, tilesOnly, force)
  local i
  for i = 1, table.getn(state.regions) do
    local entry = state.regions[i]
    if not tilesOnly or entry.tile then
      CropRegion(entry, restore, force)
    else
      -- The client re-placed this overlay but never resets its alpha: one
      -- faded out of view on the old map would stay invisible (fog). Its
      -- base and placement cache belong to the old map too.
      pcall(entry.region.SetAlpha, entry.region, 1)
      entry.base = nil
      entry.px, entry.py, entry.pw, entry.ph = nil, nil, nil, nil
      entry.pl, entry.pr, entry.pt, entry.pb = nil, nil, nil, nil
      entry.pa = 1
    end
  end
end

-- ---------------------------------------------------------------------------
-- Markers keep their size and vanish out of view. A marker at canvas point
-- (x, y) is drawn at scale 1/zoom and anchored with offsets times the zoom,
-- because SetPoint offsets are in the frame's own scaled units. The anchor is
-- on WorldMapDetailFrame, which the pan carries, so a drag changes neither:
-- only what differs from the last placement (kept on `cache`) is written.
-- ---------------------------------------------------------------------------

local function PlaceMarker(frame, x, y, cache, force)
  local zoom = state.zoom
  local vx0, vy0, vx1, vy1 = Window()
  local inside = zoom <= MIN_ZOOM or (x >= vx0 and x <= vx1 and y >= vy0 and y <= vy1)
  local scale, ox, oy = 1 / zoom, x * zoom, -y * zoom
  if force or cache.zoomScale ~= scale then
    pcall(frame.SetScale, frame, scale)
    cache.zoomScale = scale
  end
  if force or cache.zoomX ~= ox or cache.zoomY ~= oy then
    pcall(frame.ClearAllPoints, frame)
    pcall(frame.SetPoint, frame, "CENTER", state.detail, "TOPLEFT", ox, oy)
    cache.zoomX, cache.zoomY = ox, oy
  end
  return inside
end

-- The client's landmark icons, WorldMapFramePOIn, found by name -- never by
-- walking WorldMapButton's children (nameplates.flicker_probe_walk_crash).
-- Pooled entries; the count in use is poiCount.
local function TakePoiBases()
  local count = 0
  local i
  for i = 1, POI_SLOTS do
    local poi = _G["WorldMapFramePOI" .. i]
    if not poi then break end
    local x, y, w, h = RegionBox(poi)
    if x then
      count = count + 1
      local entry = state.pois[count] or {}
      entry.frame, entry.x, entry.y = poi, x + w / 2, y + h / 2
      entry.zoomScale, entry.zoomX, entry.zoomY, entry.alpha = nil, nil, nil, nil
      state.pois[count] = entry
    end
  end
  state.poiCount = count
end

-- restore: back to scale 1 at the base. mapChanged: the client has just
-- placed them for a new map, so only the scale and alpha go back.
local function ApplyPois(restore, mapChanged, force)
  local i
  for i = 1, state.poiCount or 0 do
    local entry = state.pois[i]
    local frame = entry.frame
    local alpha = 1
    if mapChanged then
      pcall(frame.SetScale, frame, 1)
      force = true
    elseif restore then
      if force or entry.zoomScale ~= 1 then
        pcall(frame.SetScale, frame, 1)
        entry.zoomScale = 1
      end
      if force or entry.zoomX ~= entry.x or entry.zoomY ~= -entry.y then
        pcall(frame.ClearAllPoints, frame)
        pcall(frame.SetPoint, frame, "CENTER", state.detail, "TOPLEFT", entry.x, -entry.y)
        entry.zoomX, entry.zoomY = entry.x, -entry.y
      end
    elseif not PlaceMarker(frame, entry.x, entry.y, entry, force) then
      alpha = 0
    end
    if force or entry.alpha ~= alpha then
      pcall(frame.SetAlpha, frame, alpha)
      entry.alpha = alpha
    end
  end
  if mapChanged then state.poiCount = 0 end
end

-- Leaving zoom 1 the bases are read again, and what the client may have
-- rewritten since is placed in full on the next Apply.
local function TakeBases()
  local i
  for i = 1, table.getn(state.regions) do TakeBase(state.regions[i]) end
  TakePoiBases()
  state.forcePlace = true
end

-- Pinned chrome: counter-scaled, anchored to the view, which neither the pan
-- nor the zoom moves, so it is written only when the zoom or the pin list
-- (W.Pin) changed, or on a forced pass.
local function ApplyPinned(force)
  local pinsVersion = W.state.pinsVersion or 0
  if not force and state.pinnedZoom == state.zoom and
     state.pinnedVersion == pinsVersion then
    return
  end
  state.pinnedZoom, state.pinnedVersion = state.zoom, pinsVersion
  local pins = W.state.pins
  local i
  for i = 1, table.getn(pins) do
    local pin = pins[i]
    local frame = _G[pin.name]
    if frame then
      pcall(frame.SetScale, frame, 1 / state.zoom)
      pcall(frame.ClearAllPoints, frame)
      pcall(frame.SetPoint, frame, pin.point, state.view, pin.relativePoint, pin.x, pin.y)
    end
  end
end

-- ---------------------------------------------------------------------------
-- Zoom state
-- ---------------------------------------------------------------------------

-- A call that changes neither the zoom nor the clamped pan (a drag held
-- against the map's edge) writes nothing and leaves the move counter alone,
-- so marker owners that follow it skip that frame too.
-- A zone map's art also draws its neighbours; the zoomed window is kept on
-- the zone itself (user request 2026-11-27). Its box is the union of the
-- zone's exploration overlays (MapOverlayData.lua, 1002x668 canvas);
-- continents and battlegrounds have none and pan over the whole canvas.
local CANVAS_W, CANVAS_H = 1002, 668
local NO_ZONE_BOX = { AlteracValley = true }
local zoneData

local function ZoneData(name)
  if not zoneData then
    zoneData = {}
    local key, value
    if type(unrealMapOverlayData) == "table" then
      for key, value in pairs(unrealMapOverlayData) do
        if not NO_ZONE_BOX[key] then zoneData[string.lower(key)] = value end
      end
    end
  end
  name = string.lower(name)
  return zoneData[name] or zoneData[string.gsub(name, "^the", "")]
end

-- The current map's zone box in canvas units, or nil; cached per map.
local function ZoneBox()
  if state.boxKey == state.mapKey then return state.box end
  state.boxKey, state.box = state.mapKey, nil
  local ok, name = false, nil
  if type(GetMapInfo) == "function" then ok, name = pcall(GetMapInfo) end
  if not ok or type(name) ~= "string" then return nil end
  local data = ZoneData(name)
  if type(data) ~= "table" then return nil end
  local left, top, right, bottom
  local i
  for i = 1, table.getn(data) do
    local _, _, w, h, x, y = string.find(data[i], ":(%d+):(%d+):(%d+):(%d+)$")
    w, h, x, y = tonumber(w), tonumber(h), tonumber(x), tonumber(y)
    if w and h and x and y then
      left = left and math.min(left, x) or x
      top = top and math.min(top, y) or y
      right = right and math.max(right, x + w) or x + w
      bottom = bottom and math.max(bottom, y + h) or y + h
    end
  end
  if not left then return nil end
  local sx, sy = state.width / CANVAS_W, state.height / CANVAS_H
  state.box = { left * sx, top * sy, math.min(right, CANVAS_W) * sx,
                math.min(bottom, CANVAS_H) * sy }
  return state.box
end

-- A window wider than the zone is centred on it; a narrower one stays inside.
local function ClampAxis(pan, window, total, low, high)
  if window >= high - low then
    pan = (low + high - window) / 2
  else
    pan = Clamp(pan, low, high - window)
  end
  return Clamp(pan, 0, total - window)
end

local function Apply(tilesOnly)
  if not state.installed then return end
  local force = state.forcePlace
  state.forcePlace = false
  local zoom = state.zoom
  local box = ZoneBox()
  local w, h = state.width / zoom, state.height / zoom
  state.panX = ClampAxis(state.panX, w, state.width,
                         box and box[1] or 0, box and box[3] or state.width)
  state.panY = ClampAxis(state.panY, h, state.height,
                         box and box[2] or 0, box and box[4] or state.height)
  local panX, panY = state.panX, state.panY
  local zoomed = force or state.appliedZoom ~= zoom
  if not zoomed and state.appliedX == panX and state.appliedY == panY then return end
  -- /umap bench phases (MapZoomBench.lua): a pan that moves nothing, or one
  -- that moves the canvas without cropping. nil outside a benchmark.
  local off = state.benchOff
  if off and off.move and not zoomed then return end
  local content = state.content
  if zoomed then pcall(content.SetScale, content, zoom) end
  pcall(content.ClearAllPoints, content)
  pcall(content.SetPoint, content, "TOPLEFT", state.view, "TOPLEFT", -panX, panY)
  state.appliedZoom, state.appliedX, state.appliedY = zoom, panX, panY
  state.moveVersion = state.moveVersion + 1
  -- The zoomed canvas extends past the window, undrawn; its hover and clicks
  -- are kept to the window. Not runtime-verified here, so guarded.
  local button = state.button
  if button and type(button.SetHitRectInsets) == "function" and
     not (off and off.insets and not zoomed) then
    pcall(button.SetHitRectInsets, button, panX,
          state.width - panX - state.width / zoom, panY,
          state.height - panY - state.height / zoom)
  end
  if off and off.crop and not zoomed then return end
  if zoom <= MIN_ZOOM then
    CropAll(true, tilesOnly, force)
    ApplyPois(true, tilesOnly, force)
  else
    CropAll(false, nil, force)
    ApplyPois(false, nil, force)
  end
  ApplyPinned(force)
  if W.TerrainPlace then W.TerrainPlace() end
end

-- The client rewrites overlays and landmarks on its own map updates, which
-- the placement cache cannot see: everything is written again.
local function SweepPlacement()
  CropAll(false, nil, true)
  ApplyPois(false, nil, true)
  ApplyPinned(true)
end

local function Install()
  local map = _G["WorldMapFrame"]
  local guide = _G["WorldMapPositioningGuide"]
  local detail = _G["WorldMapDetailFrame"]
  local button = _G["WorldMapButton"]
  if not map or not guide or not detail or not button then
    return false, "native map frames missing"
  end
  local width, height = Num(detail, "GetWidth"), Num(detail, "GetHeight")
  if not width or not height or width <= 0 or height <= 0 then
    return false, "no WorldMapDetailFrame size"
  end
  local detailLevel = Num(detail, "GetFrameLevel")
  local buttonLevel = Num(button, "GetFrameLevel")
  state.width, state.height = width, height
  state.map, state.detail, state.button = map, detail, button

  local ok, view = pcall(CreateFrame, "Frame", "unrealMapWorldMapZoomView", map)
  if not ok or not view then return false, "no view frame" end
  local made, content = pcall(CreateFrame, "Frame", "unrealMapWorldMapZoomContent", view)
  if not made or not content then return false, "no content frame" end
  local built = pcall(function()
    view:SetWidth(width)
    view:SetHeight(height)
    view:SetPoint("TOPLEFT", guide, "TOP", ANCHOR_X, ANCHOR_Y)
    if detailLevel then view:SetFrameLevel(detailLevel) end
    content:SetWidth(width)
    content:SetHeight(height)
    content:SetPoint("TOPLEFT", view, "TOPLEFT", 0, 0)
    if detailLevel then content:SetFrameLevel(detailLevel) end
  end)
  if not built then return false, "view setup failed" end
  state.view, state.content = view, content

  -- Regions are collected before the move, at the native placement.
  CollectRegions()

  detail:SetParent(content)
  detail:ClearAllPoints()
  detail:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
  button:SetParent(content)
  if detailLevel then pcall(detail.SetFrameLevel, detail, detailLevel) end
  if buttonLevel then pcall(button.SetFrameLevel, button, buttonLevel) end

  -- The wheel catcher sat on the canvas; the canvas now scales, the view not.
  local catcher = state.catcher
  if catcher then
    pcall(catcher.ClearAllPoints, catcher)
    pcall(catcher.SetAllPoints, catcher, view)
  end

  state.installed = true
  return true
end

local function EnsureInstalled()
  if state.installed then return true end
  if state.failure then return false end
  local ok, installed, failure = pcall(Install)
  if not ok then
    state.failure = tostring(installed)
  elseif not installed then
    state.failure = failure
  end
  return state.failure == nil
end

-- MapTerrain.lua has its own stops (and a higher ceiling) on zones with a
-- terrain view.
local function Stops()
  return W.TerrainZoomStops and W.TerrainZoomStops() or ZOOM_STOPS
end

local function MaxZoom()
  local stops = Stops()
  return stops[table.getn(stops)]
end

-- The next stop of `stops` in the notch's direction, held at either end.
local function NextStop(stops, from, steps)
  local n, i = table.getn(stops)
  if steps > 0 then
    for i = 1, n do
      if stops[i] > from + 0.001 then return stops[i] end
    end
    return stops[n]
  end
  for i = n, 1, -1 do
    if stops[i] < from - 0.001 then return stops[i] end
  end
  return stops[1]
end

-- Keeps the map point under the cursor fixed; outside the map, the centre.
local function ZoomTo(zoom)
  zoom = Clamp(zoom, MIN_ZOOM, MaxZoom())
  if zoom == state.zoom then return end
  if not EnsureInstalled() then return end
  local cx, cy, inside = CursorInView()
  if not cx or not inside then cx, cy = state.width / 2, state.height / 2 end
  local mapX, mapY = state.panX + cx / state.zoom, state.panY + cy / state.zoom
  -- Leaving zoom 1: the canvas is unscaled right now, the one state where the
  -- bases read true.
  if state.zoom <= MIN_ZOOM then TakeBases() end
  state.zoom = zoom
  state.panX, state.panY = mapX - cx / zoom, mapY - cy / zoom
  Apply()
end

local function ZoomBy(steps)
  local target = Clamp(NextStop(Stops(), state.targetZoom, steps), MIN_ZOOM, MaxZoom())
  if target == state.targetZoom then return end
  if not EnsureInstalled() then return end
  state.targetZoom = target
  state.gliding = false
end

-- math.exp and math.log are not runtime-verified on this client; without them
-- the ease falls back to a linear share and a linear zoom.
local HAS_EXP = type(math.exp) == "function" and type(math.log) == "function"

local function Decay(rate, dt)
  if HAS_EXP then return math.exp(-rate * dt) end
  return Clamp(1 - rate * dt, 0, 1)
end

-- Eases in log space so each step feels the same at any zoom.
local function StepZoom(dt)
  local target = state.targetZoom
  if state.zoom == target then return end
  local t = 1 - Decay(ZOOM_RATE, dt)
  local zoom
  if HAS_EXP then
    local from = math.log(state.zoom)
    zoom = math.exp(from + (math.log(target) - from) * t)
  else
    zoom = state.zoom + (target - state.zoom) * t
  end
  if math.abs(zoom - target) < ZOOM_SNAP then zoom = target end
  ZoomTo(zoom)
  if state.zoom == target then state.version = state.version + 1 end
end

local function StopMotion()
  state.gliding, state.velX, state.velY = false, 0, 0
  if state.zoom ~= state.targetZoom then
    ZoomTo(state.targetZoom)
    state.version = state.version + 1
  end
end

local function Reset(mapChanged)
  state.dragging, state.justDragged, state.down = false, false, false
  state.gliding, state.velX, state.velY = false, 0, 0
  state.targetZoom = MIN_ZOOM
  if state.zoom == MIN_ZOOM and state.panX == 0 and state.panY == 0 then return end
  state.zoom, state.panX, state.panY = MIN_ZOOM, 0, 0
  Apply(mapChanged)
  state.version = state.version + 1
end

-- ---------------------------------------------------------------------------
-- Public API (same contract as unrealUI's U.WorldMapZoom* functions)
-- ---------------------------------------------------------------------------

-- Place `frame` at canvas fraction (u, v) of WorldMapDetailFrame at the map's
-- own icon size. nil: the zoom is not installed (place it normally); false:
-- that point is out of the zoomed view, for the caller to hide.
-- The zoom owns the frame's scale and anchor from then on; its last placement
-- is kept per frame (bounded by the callers: unrealUI's player arrow).
function W.ZoomPlace(frame, u, v)
  if not state.installed or not frame then return nil end
  local cache = state.markers[frame]
  if not cache then
    cache = {}
    state.markers[frame] = cache
  end
  return PlaceMarker(frame, u * state.width, v * state.height, cache)
end

-- The canvas rectangle as drawn, once the canvas has moved into the zoom.
function W.ZoomView()
  if state.installed then return state.view end
  return nil
end

-- A 0..1 point in the visible window, as a point on the whole canvas.
function W.ZoomToCanvas(u, v)
  if not state.installed or state.zoom <= MIN_ZOOM then return u, v end
  return state.panX / state.width + u / state.zoom,
         state.panY / state.height + v / state.zoom
end

-- Zoom factor, settle counter, move counter (every placement).
function W.ZoomState()
  if not state.installed then return 1, state.version, state.moveVersion end
  -- A benchmark phase without marker following reports a frozen counter.
  local off = state.benchOff
  if off and off.follow then return state.zoom, state.version, off.moveVersion end
  return state.zoom, state.version, state.moveVersion
end

-- True while other addons' map markers should be hidden: the map is moving (a
-- drag, a glide, a zoom easing) and the player turned on "hideMarkersOnMove"
-- (Settings.lua), or a /umap bench phase asks for it. Moving the canvas costs
-- frame time per frame it carries (MapZoomBench.lua, run 3); owners hide their
-- own markers while this holds and place them again once it ends, when the
-- settle counter (W.ZoomState's second value) has also moved. Polled per frame.
function W.ZoomMarkersHidden()
  if not state.installed then return false end
  local off = state.benchOff
  local wanted = off and off.hide
  if not wanted then
    local db = _G["unrealMapDB"]
    wanted = type(db) == "table" and db.hideMarkersOnMove == true
  end
  if not wanted then return false end
  return (state.dragging or state.gliding or state.zoom ~= state.targetZoom) and true or false
end

-- The visible part of the canvas as 0..1 fractions (left, top, right, bottom).
function W.ZoomWindow()
  if not state.installed or state.zoom <= MIN_ZOOM then return 0, 0, 1, 1 end
  local x0, y0, x1, y1 = Window()
  return x0 / state.width, y0 / state.height, x1 / state.width, y1 / state.height
end

-- ---------------------------------------------------------------------------
-- Input
-- ---------------------------------------------------------------------------

local function OnMouseDown(a1, a2)
  local which = a2 or _G["arg1"]
  if type(a1) == "string" then which = a1 end
  state.justDragged = false
  -- A press catches a gliding map.
  if state.gliding then
    state.gliding = false
    state.version = state.version + 1
  end
  if which ~= nil and which ~= "LeftButton" then return end
  if state.zoom <= MIN_ZOOM and state.targetZoom <= MIN_ZOOM then return end
  state.downX, state.downY = Cursor()
  state.lastX, state.lastY = state.downX, state.downY
  state.velX, state.velY = 0, 0
  state.lastMoveAt = Now()
  state.down = state.downX ~= nil
end

-- A release soon after a fast move glides on.
local function StartGlide()
  local speed = math.sqrt(state.velX * state.velX + state.velY * state.velY) * state.zoom
  local recent = state.lastMoveAt and Now() - state.lastMoveAt < GLIDE_RELEASE_WINDOW
  if not recent or speed < GLIDE_START_SPEED then
    state.velX, state.velY = 0, 0
    return false
  end
  if speed > GLIDE_MAX_SPEED then
    state.velX = state.velX * GLIDE_MAX_SPEED / speed
    state.velY = state.velY * GLIDE_MAX_SPEED / speed
  end
  state.gliding = true
  return true
end

-- WorldMapButton's native OnMouseUp is the zoom in/out click; it is skipped
-- after a drag. Wrapped once, the original kept.
local function WrapMouseUp(button)
  local ok, previous = pcall(button.GetScript, button, "OnMouseUp")
  if not ok then return end
  pcall(button.SetScript, button, "OnMouseUp", function(a1, a2, a3, a4, a5)
    local dragged = state.dragging
    state.down, state.dragging = false, false
    if dragged then
      state.justDragged = true
      if not StartGlide() then state.version = state.version + 1 end
      return
    end
    if previous then previous(a1, a2, a3, a4, a5) end
  end)
end

-- Pans by the cursor's move since the last frame and tracks the release
-- velocity.
local function StepDrag()
  local x, y = Cursor()
  if not x then return end
  if not state.dragging and (math.abs(x - state.downX) > DRAG_PIXELS or
                             math.abs(y - state.downY) > DRAG_PIXELS) then
    state.dragging = true
  end
  if not state.dragging then return end
  local scale = Num(state.view, "GetEffectiveScale")
  if not scale or scale <= 0 then return end
  local dx = (x - state.lastX) / scale / state.zoom
  local dy = (y - state.lastY) / scale / state.zoom
  state.lastX, state.lastY = x, y
  if dx == 0 and dy == 0 then return end
  state.dragMoved = true
  state.panX = state.panX - dx
  state.panY = state.panY + dy
  local now = Now()
  local span = now - (state.lastMoveAt or now)
  if span > 0 and span < MAX_FRAME_TIME then
    state.velX = state.velX * 0.5 - dx / span * 0.5
    state.velY = state.velY * 0.5 + dy / span * 0.5
  end
  state.lastMoveAt = now
  Apply()
end

-- For unrealUI's U.WorldMapZoomDragging (other addons' mouse-enabled canvas
-- pins, such as unrealQuest's objective areas, forward their press and, when
-- this says "dragging", their release to WorldMapButton). True while a drag
-- runs and from its release to the next press. The pin asks only on its left
-- release (user report 2026-11-27: the map kept following the cursor after a
-- release on an area), so a move since the last frame is taken first, and a
-- press that never became a drag ends here: the canvas sees no release.
function W.ZoomDragging()
  if state.down then
    StepDrag()
    if not state.dragging then state.down = false end
  end
  return (state.dragging or state.justDragged) and true or false
end

local function StepGlide(dt)
  local x, y = state.panX + state.velX * dt, state.panY + state.velY * dt
  state.panX, state.panY = x, y
  Apply()
  -- Apply clamps the pan to the map; the axis that hit an edge stops.
  if state.panX ~= x then state.velX = 0 end
  if state.panY ~= y then state.velY = 0 end
  local decay = Decay(GLIDE_FRICTION, dt)
  state.velX, state.velY = state.velX * decay, state.velY * decay
  local speed = math.sqrt(state.velX * state.velX + state.velY * state.velY) * state.zoom
  if speed < GLIDE_STOP_SPEED then
    state.gliding, state.velX, state.velY = false, 0, 0
    state.version = state.version + 1
  end
end

-- Called from MapWindow.lua's map tick.
function W.ZoomDrive()
  local now = Now()
  local last = state.tickAt
  state.tickAt = now
  -- The map was closed: motion ends at once instead of resuming on reopen.
  if not last or now - last > OPEN_TICK_SECONDS then
    -- A press whose release went unseen while the map was closed; a drag left
    -- set would keep markers hidden (W.ZoomMarkersHidden) after reopening.
    if state.dragging then state.version = state.version + 1 end
    state.down, state.dragging = false, false
    if state.installed then StopMotion() end
    last = now
  end
  local dt = Clamp(now - last, 0, MAX_FRAME_TIME)
  if W.BenchTick then W.BenchTick(now) end
  state.dragMoved = false
  if state.down then
    StepDrag()
  elseif state.gliding then
    StepGlide(dt)
  end
  if state.installed then StepZoom(dt) end
  if W.TerrainDrive then W.TerrainDrive(dt) end
  -- The client rewrites overlays on its own map updates; they are placed
  -- again in full a few times a second while zoomed, and at once after a
  -- WORLD_MAP_UPDATE that kept the map.
  local off = state.benchOff
  if state.installed and state.zoom > MIN_ZOOM and not (off and off.crop) and
     (state.sweepDue or now - state.sweepAt >= SWEEP_SECONDS) then
    state.sweepAt, state.sweepDue = now, false
    SweepPlacement()
  end
end

-- The zone hover highlight is rewritten whole by the map's own OnUpdate every
-- frame, so on a zoomed map it is drawn again straight after, from the
-- cursor's canvas point, and cropped to the window like the tiles.
local function CropHighlight()
  if not state.installed or state.zoom <= MIN_ZOOM then return end
  if state.benchOff and state.benchOff.crop then return end
  local highlight = _G["WorldMapHighlight"]
  local hitTest = _G["UpdateMapHighlight"]
  if not highlight or type(hitTest) ~= "function" then return end
  local cx, cy, inside = CursorInView()
  if not cx or not inside then
    pcall(highlight.SetAlpha, highlight, 0)
    return
  end
  local u = (state.panX + cx / state.zoom) / state.width
  local v = (state.panY + cy / state.zoom) / state.height
  local ok, name, file, texX, texY, sizeX, sizeY, offsetX, offsetY = pcall(hitTest, u, v)
  if not ok or not name or type(file) ~= "string" or file == "" or
     not tonumber(sizeX) or not tonumber(sizeY) or sizeX <= 0 or sizeY <= 0 then
    return
  end
  local x, y = (tonumber(offsetX) or 0) * state.width, (tonumber(offsetY) or 0) * state.height
  local w, h = sizeX * state.width, sizeY * state.height
  local vx0, vy0, vx1, vy1 = Window()
  local ix0, iy0 = math.max(x, vx0), math.max(y, vy0)
  local ix1, iy1 = math.min(x + w, vx1), math.min(y + h, vy1)
  if ix1 <= ix0 or iy1 <= iy0 then
    pcall(highlight.SetAlpha, highlight, 0)
    return
  end
  local du, dv = tonumber(texX) or 1, tonumber(texY) or 1
  if state.highlightFile ~= file then
    pcall(highlight.SetTexture, highlight,
          "Interface\\WorldMap\\" .. file .. "\\" .. file .. "Highlight")
    state.highlightFile = file
  end
  pcall(highlight.SetTexCoord, highlight, (ix0 - x) / w * du, (ix1 - x) / w * du,
        (iy0 - y) / h * dv, (iy1 - y) / h * dv)
  pcall(highlight.ClearAllPoints, highlight)
  pcall(highlight.SetPoint, highlight, "TOPLEFT", state.detail, "TOPLEFT", ix0, -iy0)
  pcall(highlight.SetWidth, highlight, ix1 - ix0)
  pcall(highlight.SetHeight, highlight, iy1 - iy0)
  pcall(highlight.SetAlpha, highlight, 1)
  pcall(highlight.Show, highlight)
end

-- The wheel: only a ScrollFrame parented to UIParent receives it with the map
-- open. It takes the wheel only while the map is drawn and ticking, so the
-- camera keeps the wheel once the map is closed.
local function UiParentShown()
  local parent = _G["UIParent"]
  if not parent or type(parent.IsShown) ~= "function" then return false end
  local ok, shown = pcall(parent.IsShown, parent)
  return ok and shown and true or false
end

local function BuildWheelCatcher(canvas)
  local parent = _G["UIParent"]
  if not parent then return end
  local ok, catcher = pcall(CreateFrame, "ScrollFrame", nil, parent)
  if not ok or not catcher then return end
  local built = pcall(function()
    local child = CreateFrame("Frame", nil, catcher)
    child:SetWidth(1)
    child:SetHeight(1)
    catcher:SetScrollChild(child)
    catcher:SetFrameStrata("FULLSCREEN")
    catcher:SetFrameLevel(math.max((Num(canvas, "GetFrameLevel") or 1) + 30, 60))
    catcher:SetAllPoints(canvas)
    if catcher.EnableMouse then catcher:EnableMouse(false) end
    catcher:EnableMouseWheel(false)
    catcher:SetScript("OnMouseWheel", function(_, wheel)
      local delta = tonumber(wheel) or tonumber(_G["arg1"])
      if not delta or delta == 0 then return end
      ZoomBy(delta > 0 and 1 or -1)
    end)
  end)
  if not built then return end
  local on = false
  catcher:SetScript("OnUpdate", function()
    local shown = state.view or canvas
    local open = shown.IsVisible and shown:IsVisible() and
                 Now() - (state.tickAt or 0) <= OPEN_TICK_SECONDS and UiParentShown()
    open = open and true or false
    if open ~= on then
      on = open
      pcall(catcher.EnableMouseWheel, catcher, on)
    end
  end)
  state.catcher = catcher
end

-- + / - on the canvas, built like the minimize toggle, with the plus-minus
-- art: four 20x22 cells on a 64x64 sheet, plus over minus, normal left and
-- pushed right.
local ZOOM_CELLS = {
  sheet = 64, width = 20, height = 22,
  plusNormal = { 2, 22, 0, 22 },
  plusPushed = { 26, 46, 0, 22 },
  minusNormal = { 2, 22, 24, 46 },
  minusPushed = { 26, 46, 24, 46 },
}

local function BuildZoomButton(canvas, name, which, onClick)
  local cells = ZOOM_CELLS
  local ok, button = pcall(CreateFrame, "Button", name, canvas)
  if not ok or not button then return nil end
  button:SetWidth(cells.width)
  button:SetHeight(cells.height)
  -- +25 over the shared control level: above every map marker (unrealQuest
  -- pins sit at that level plus boosts up to 19), below its giver menu (+30).
  button:SetFrameLevel(W.ControlLevel(canvas) + 25)
  pcall(button.EnableMouse, button, true)
  local face = button:CreateTexture(nil, "ARTWORK")
  pcall(face.SetTexture, face, W.texture.zoomButton)
  pcall(face.SetAllPoints, face, button)
  local function Paint(down)
    local cell = cells[which .. (down and "Pushed" or "Normal")]
    pcall(face.SetTexCoord, face, cell[1] / cells.sheet, cell[2] / cells.sheet,
          cell[3] / cells.sheet, cell[4] / cells.sheet)
  end
  button:SetScript("OnMouseDown", function() Paint(true) end)
  button:SetScript("OnMouseUp", function() Paint(false) end)
  button:SetScript("OnClick", onClick)
  Paint(false)
  return button
end

-- "Zoom" hint in the header, on the Zoom Out button's line at the right, as
-- in PandaMap (user requests, 2026-11-27): a level-120 Button child of WorldMapButton with a file-backed
-- fill, the wheel icon and a label; mouse off so the map keeps its hover and
-- clicks. With unrealUI installed it draws its own hint and pins it here.
local HINT_BACKGROUND = { 0.06, 0.06, 0.06, 0.85 }
local HINT_TEXT = { 0.90, 0.90, 0.90, 1.00 }

local function BuildZoomHint(canvas)
  if type(_G["UnrealUI"]) == "table" then return end
  local size = layout.zoomHintIcon
  local ok, frame = pcall(CreateFrame, "Button", "unrealMapWorldMapZoomHint", canvas)
  if not ok or not frame then return end
  frame:SetHeight(size + 4)
  frame:SetPoint("RIGHT", canvas, "TOPRIGHT", layout.zoomHintX, layout.zoomHintY)
  frame:SetFrameLevel(W.ControlLevel(canvas))
  if frame.EnableMouse then frame:EnableMouse(false) end

  local fill = frame:CreateTexture(nil, "BACKGROUND")
  fill:SetTexture(W.texture.plain)
  fill:SetAllPoints(frame)
  pcall(fill.SetVertexColor, fill, HINT_BACKGROUND[1], HINT_BACKGROUND[2],
        HINT_BACKGROUND[3], HINT_BACKGROUND[4])

  local icon = frame:CreateTexture(nil, "ARTWORK")
  pcall(icon.SetTexture, icon, W.texture.zoomHint)
  icon:SetWidth(size)
  icon:SetHeight(size)
  icon:SetPoint("LEFT", frame, "LEFT", 4, 0)

  local width = 4 + size + 7
  local made, label = pcall(frame.CreateFontString, frame, nil, "OVERLAY", "GameFontNormal")
  if made and label then
    label:SetPoint("LEFT", icon, "RIGHT", 4, 0)
    pcall(label.SetJustifyH, label, "LEFT")
    pcall(label.SetTextColor, label, HINT_TEXT[1], HINT_TEXT[2], HINT_TEXT[3], HINT_TEXT[4])
    label:SetText(unrealMapLocale.L("MAP_ZOOM_HINT"))
    local textWidth = W.Num(label, "GetStringWidth") or 0
    if textWidth <= 0 then textWidth = 40 end
    width = width + 4 + textWidth
  end
  frame:SetWidth(width)
  W.Pin("unrealMapWorldMapZoomHint", "RIGHT", "TOPRIGHT", layout.zoomHintX,
        layout.zoomHintY)
end

local function MapKey()
  local continent, zone
  if type(GetCurrentMapContinent) == "function" then
    local ok, value = pcall(GetCurrentMapContinent)
    if ok then continent = value end
  end
  if type(GetCurrentMapZone) == "function" then
    local ok, value = pcall(GetCurrentMapZone)
    if ok then zone = value end
  end
  return tostring(continent) .. ":" .. tostring(zone)
end

-- A new map starts unzoomed; its overlays are taken again on the next zoom.
local function OnMapUpdate()
  local key = MapKey()
  if key ~= state.mapKey then
    state.mapKey = key
    Reset(true)
  else
    state.sweepDue = true
  end
end

-- Called once from MapWindow.lua's Build, on the first map show.
function W.ZoomBuild(map, canvas)
  local inX, outX = layout.zoomButtonX, layout.zoomButtonX + layout.zoomButtonGap
  local zoomIn = BuildZoomButton(canvas, "unrealMapWorldMapZoomIn", "plus",
                                 function() ZoomBy(1) end)
  local zoomOut = BuildZoomButton(canvas, "unrealMapWorldMapZoomOut", "minus",
                                  function() ZoomBy(-1) end)
  -- Placed on the canvas until the zoom installs and pins them to its view.
  if zoomIn then
    zoomIn:SetPoint("BOTTOMLEFT", canvas, "BOTTOMLEFT", inX, layout.zoomButtonY)
  end
  if zoomOut then
    zoomOut:SetPoint("BOTTOMLEFT", canvas, "BOTTOMLEFT", outX, layout.zoomButtonY)
  end
  W.Pin("unrealMapWorldMapZoomIn", "BOTTOMLEFT", "BOTTOMLEFT", inX, layout.zoomButtonY)
  W.Pin("unrealMapWorldMapZoomOut", "BOTTOMLEFT", "BOTTOMLEFT", outX, layout.zoomButtonY)
  BuildZoomHint(canvas)

  W.PostHookScript(canvas, "OnMouseDown", OnMouseDown)
  -- After the map's own OnUpdate, which redraws the highlight unzoomed.
  W.PostHookScript(canvas, "OnUpdate", CropHighlight)
  WrapMouseUp(canvas)
  BuildWheelCatcher(canvas)

  state.mapKey = MapKey()
  local events = CreateFrame("Frame", "unrealMapWorldMapZoomEvents", _G["WorldFrame"] or map)
  events:RegisterEvent("WORLD_MAP_UPDATE")
  events:SetScript("OnEvent", OnMapUpdate)
end
