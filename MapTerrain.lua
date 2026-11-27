--[[
unrealMap / MapTerrain.lua

Terrain view (user request, 2026-11-27): on a zone map, the rendered 3D
terrain of the unrealMap_World pack cross-fades over the painted map between
FADE_FROM and FADE_TO zoom, and such a zone zooms on to 14.1x (TERRAIN_STOPS).

Source: Packs/unrealMap_World/Terrain/Azeroth, the 13000x12000 Barrens Chat
terrain composite cut into 26x24 pages of 512 px (assets/
terrain_atlas_manifest.json). Kalimdor fills its left part, the Eastern
Kingdoms its right part, both at 0.48 px per yard (256 px per ADT tile).

Placement: a zone's rectangle is its WorldMapArea bounds (vanilla
WorldMapArea.dbc, ZONES below); a world point (x north, y west) lands on atlas
pixel (8192 - 0.48 y - ox, 8192 - 0.48 x - oy), with one (ox, oy) per continent
measured offline against the native zone maps (calibration in the manifest).

Memory (.claude/rules/map-memory.md): nothing loads at login. A fixed pool of
PAGE_SLOTS textures on WorldMapDetailFrame is created on the first fade, holds
only the pages crossing the visible window, and is cleared when the fade ends,
the map changes or the map closes. Placed in canvas units like MapZoom.lua's
cropped tiles, so the zoom's scale and pan carry it.

NOT_TESTED in game: an addon texture on WorldMapDetailFrame's OVERLAY layer
drawing above the native tiles and overlays.
]]

local W = type(unrealMap) == "table" and unrealMap.MapWindow
if type(W) ~= "table" then return end

local PACK = "unrealMap_World"
-- First pack version that ships the terrain pages (.claude/rules/release.md).
local PACK_MIN_VERSION = "1.1.0"
local PAGE_ROOT = "Interface\\AddOns\\unrealMap_World\\Terrain\\Azeroth\\TerrainClassic"
local PAGE_SIZE, PAGE_COLUMNS, PAGE_ROWS = 512, 26, 24
local ATLAS_WIDTH, ATLAS_HEIGHT = 13000, 12000
local PIXELS_PER_YARD = 0.48
local GRID_ORIGIN = 8192
-- The worst window at the fade's lowest zoom (The Barrens at 2.7x) crosses
-- 5x4 pages.
local PAGE_SLOTS = 20
-- Zoom span of the parchment-to-terrain cross-fade (user request: a long,
-- gentle blend), seven wheel notches from 3.12x to 6.3x, eased at both ends.
local FADE_FROM, FADE_TO = 2.7, 6.3
-- The drawn blend trails the zoom with this time constant, so a notch melts in
-- over about a second instead of jumping with the zoom's 0.25 s ease.
local BLEND_SECONDS = 0.35
-- MapZoom.lua's wheel stops on a zone with terrain, each about x1.12 (user
-- request): painted map, cross-fade, then terrain up to the 14.1x ceiling.
local TERRAIN_STOPS = {
  1, 1.12, 1.26, 1.41, 1.58, 1.77, 1.98, 2.22, 2.49, 2.79, 3.12, 3.5,
  4, 4.5, 5,
  5.6, 6.3, 7.1, 7.9, 8.9, 10, 11.2, 12.6, 14.1,
}

-- Atlas offset per continent (0 Eastern Kingdoms, 1 Kalimdor).
local CONTINENT_OFFSET = {
  [0] = { -953, 3981 },
  [1] = { 5609, 2220 },
}

-- continent, west edge (y max), north edge (x max), width and height in yards.
local ZONES = {
  Alterac = { 0, 783.33, 1500, 2800, 1866.67 },
  Arathi = { 0, -866.67, -133.33, 3600, 2400 },
  Ashenvale = { 1, 1700, 4672.92, 5766.67, 3843.75 },
  Aszhara = { 1, -3277.08, 5341.67, 5070.83, 3381.25 },
  Badlands = { 0, -2079.17, -5889.58, 2487.5, 1658.33 },
  Barrens = { 1, 2622.92, 1612.5, 10133.33, 6756.25 },
  BlastedLands = { 0, -1241.67, -10566.67, 3350, 2233.33 },
  BurningSteppes = { 0, -266.67, -7031.25, 2929.17, 1952.08 },
  Darkshore = { 1, 2941.67, 8333.33, 6550, 4366.67 },
  DeadwindPass = { 0, -833.33, -9866.67, 2500, 1666.67 },
  Desolace = { 1, 4233.33, 452.08, 4495.83, 2997.92 },
  DunMorogh = { 0, 1802.08, -3877.08, 4925, 3283.33 },
  Durotar = { 1, -1962.5, 1808.33, 5287.5, 3525 },
  Duskwood = { 0, 833.33, -9716.67, 2700, 1800 },
  Dustwallow = { 1, -975, -2033.33, 5250, 3500 },
  EasternPlaguelands = { 0, -2185.42, 3800, 3870.83, 2581.25 },
  Elwynn = { 0, 1535.42, -7939.58, 3470.83, 2314.58 },
  Felwood = { 1, 1641.67, 7133.33, 5750, 3833.33 },
  Feralas = { 1, 5441.67, -2366.67, 6950, 4633.33 },
  Hilsbrad = { 0, 1066.67, 400, 3200, 2133.33 },
  Hinterlands = { 0, -1575, 1466.67, 3850, 2566.67 },
  LochModan = { 0, -1993.75, -4487.5, 2758.33, 1839.58 },
  Moonglade = { 1, -1381.25, 8491.67, 2308.33, 1539.58 },
  Mulgore = { 1, 2047.92, -272.92, 5137.5, 3425 },
  Redridge = { 0, -1570.83, -8575, 2170.83, 1447.92 },
  SearingGorge = { 0, -322.92, -6100, 2231.25, 1487.5 },
  Silithus = { 1, 2537.5, -5958.33, 3483.33, 2322.92 },
  Silverpine = { 0, 3450, 1666.67, 4200, 2800 },
  StonetalonMountains = { 1, 3245.83, 2916.67, 4883.33, 3256.25 },
  Stranglethorn = { 0, 2220.83, -11168.75, 6381.25, 4254.17 },
  SwampOfSorrows = { 0, -2222.92, -9620.83, 2293.75, 1529.17 },
  Tanaris = { 1, -218.75, -5875, 6900, 4600 },
  Teldrassil = { 1, 3814.58, 11831.25, 5091.67, 3393.75 },
  ThousandNeedles = { 1, -433.33, -3966.67, 4400, 2933.33 },
  Tirisfal = { 0, 3033.33, 3837.5, 4518.75, 3012.5 },
  UngoroCrater = { 1, 533.33, -5966.67, 3700, 2466.67 },
  WesternPlaguelands = { 0, 416.67, 3366.67, 4300, 2866.67 },
  Westfall = { 0, 3016.67, -9400, 3500, 2333.33 },
  Wetlands = { 0, -389.58, -2147.92, 4135.42, 2756.25 },
  Winterspring = { 1, -316.67, 8533.33, 7100, 4733.33 },
}

local zoom = W.zoomState
local terrain = {
  -- Drawn alpha, 0..1, trailing BlendTarget (W.TerrainDrive).
  alpha = 0,
  slots = {},
  used = 0,
  -- The zone the atlas rectangle below belongs to.
  zone = nil,
  x = 0, y = 0, w = 0, h = 0,
}

local function Clamp(value, low, high)
  if value < low then return low end
  if value > high then return high end
  return value
end

-- The bound zone's atlas rectangle, or nil when it has no terrain.
local function ZoneRect()
  local name = type(unrealMap.GetActiveMap) == "function" and unrealMap.GetActiveMap() or nil
  local zone = name and ZONES[name]
  if not zone then return nil end
  if terrain.zone ~= name then
    local offset = CONTINENT_OFFSET[zone[1]]
    terrain.zone = name
    terrain.x = GRID_ORIGIN - PIXELS_PER_YARD * zone[2] - offset[1]
    terrain.y = GRID_ORIGIN - PIXELS_PER_YARD * zone[3] - offset[2]
    terrain.w = PIXELS_PER_YARD * zone[4]
    terrain.h = PIXELS_PER_YARD * zone[5]
  end
  return true
end

local function PackReady()
  return type(unrealMap.IsPackAtLeast) == "function" and
         unrealMap.IsPackAtLeast(PACK, PACK_MIN_VERSION)
end

local function Slot(i)
  local slot = terrain.slots[i]
  if slot then return slot end
  local detail = zoom.detail
  if not detail or type(detail.CreateTexture) ~= "function" then return nil end
  local ok, region = pcall(detail.CreateTexture, detail,
                           "unrealMapTerrainPage" .. i, "OVERLAY")
  if not ok or not region then return nil end
  slot = { region = region, path = nil }
  terrain.slots[i] = slot
  return slot
end

local function ClearSlot(slot)
  local region = slot.region
  if slot.path then
    pcall(region.SetTexture, region, "")
    slot.path = nil
  end
  slot.page, slot.shown, slot.x, slot.y, slot.w, slot.h = nil, nil, nil, nil, nil, nil
  slot.l, slot.r, slot.t, slot.b, slot.alpha = nil, nil, nil, nil, nil
  pcall(region.SetTexCoord, region, 0, 1, 0, 1)
  pcall(region.SetAlpha, region, 0)
  pcall(region.Hide, region)
end

local function ClearFrom(first)
  local i
  for i = first, table.getn(terrain.slots) do ClearSlot(terrain.slots[i]) end
  terrain.used = first - 1
end

-- The blend the zoom asks for: its share of the cross-fade span, smoothstep
-- eased so the blend starts and settles gently.
local function BlendTarget()
  local a = Clamp((zoom.zoom - FADE_FROM) / (FADE_TO - FADE_FROM), 0, 1)
  return a * a * (3 - 2 * a)
end

-- Binds and places the pages crossing the visible window.
local function Place()
  -- Zoom 1 is a reset or a map change: the blend ends at once.
  if not zoom.installed or zoom.zoom <= 1 then terrain.alpha = 0 end
  local alpha = terrain.alpha
  if alpha <= 0 or not ZoneRect() then
    if terrain.used > 0 then ClearFrom(1) end
    return
  end
  local u0, v0, u1, v1 = W.ZoomWindow()
  local zx, zy, zw, zh = terrain.x, terrain.y, terrain.w, terrain.h
  local ax0 = Clamp(zx + u0 * zw, 0, ATLAS_WIDTH)
  local ax1 = Clamp(zx + u1 * zw, 0, ATLAS_WIDTH)
  local ay0 = Clamp(zy + v0 * zh, 0, ATLAS_HEIGHT)
  local ay1 = Clamp(zy + v1 * zh, 0, ATLAS_HEIGHT)
  local detail, width, height = zoom.detail, zoom.width, zoom.height
  local used = 0
  if ax1 > ax0 and ay1 > ay0 then
    local c0, c1 = math.floor(ax0 / PAGE_SIZE), math.floor((ax1 - 0.01) / PAGE_SIZE)
    local r0, r1 = math.floor(ay0 / PAGE_SIZE), math.floor((ay1 - 0.01) / PAGE_SIZE)
    local row, column
    for row = r0, math.min(r1, PAGE_ROWS - 1) do
      for column = c0, math.min(c1, PAGE_COLUMNS - 1) do
        local slot = used < PAGE_SLOTS and Slot(used + 1) or nil
        if slot then
          used = used + 1
          local px0, py0 = column * PAGE_SIZE, row * PAGE_SIZE
          local x0, x1 = math.max(ax0, px0), math.min(ax1, px0 + PAGE_SIZE)
          local y0, y1 = math.max(ay0, py0), math.min(ay1, py0 + PAGE_SIZE)
          local region = slot.region
          -- Per drag frame only what changed is written; the path string is
          -- built only when the slot takes another page.
          local page = row * PAGE_COLUMNS + column
          if slot.page ~= page then
            local path = string.format("%sR%02dC%02d", PAGE_ROOT, row + 1, column + 1)
            if slot.path ~= path then
              pcall(region.SetTexture, region, path)
              slot.path = path
            end
            slot.page = page
          end
          local x, y = (x0 - zx) / zw * width, -(y0 - zy) / zh * height
          if slot.x ~= x or slot.y ~= y then
            pcall(region.ClearAllPoints, region)
            pcall(region.SetPoint, region, "TOPLEFT", detail, "TOPLEFT", x, y)
            slot.x, slot.y = x, y
          end
          local w, h = (x1 - x0) / zw * width, (y1 - y0) / zh * height
          if slot.w ~= w then
            pcall(region.SetWidth, region, w)
            slot.w = w
          end
          if slot.h ~= h then
            pcall(region.SetHeight, region, h)
            slot.h = h
          end
          local l, r = (x0 - px0) / PAGE_SIZE, (x1 - px0) / PAGE_SIZE
          local t, b = (y0 - py0) / PAGE_SIZE, (y1 - py0) / PAGE_SIZE
          if slot.l ~= l or slot.r ~= r or slot.t ~= t or slot.b ~= b then
            pcall(region.SetTexCoord, region, l, r, t, b)
            slot.l, slot.r, slot.t, slot.b = l, r, t, b
          end
          if slot.alpha ~= alpha then
            pcall(region.SetAlpha, region, alpha)
            slot.alpha = alpha
          end
          if not slot.shown then
            pcall(region.Show, region)
            slot.shown = true
          end
        end
      end
    end
  end
  if used < terrain.used then ClearFrom(used + 1) end
  terrain.used = used
end
W.TerrainPlace = Place

-- MapZoom.lua's wheel stops: TERRAIN_STOPS on a zone with terrain, else nil.
function W.TerrainZoomStops()
  if PackReady() and ZoneRect() then return TERRAIN_STOPS end
  return nil
end

-- Map tick (MapZoom.lua's ZoomDrive): the drawn alpha trails BlendTarget.
-- Back at zoom 1 (map change, reset) or off a terrain zone it drops at once,
-- so another zone's pages never show over the wrong map.
function W.TerrainDrive(dt)
  local want, alpha = 0, terrain.alpha
  if zoom.installed and zoom.zoom > 1 and PackReady() and ZoneRect() then
    want = BlendTarget()
    local diff = want - alpha
    if diff > 0.004 or diff < -0.004 then
      want = alpha + diff * Clamp((tonumber(dt) or 0) / BLEND_SECONDS, 0, 1)
    end
  end
  if want == alpha then return end
  terrain.alpha = want
  Place()
end

-- Closing the map drops every page binding.
W.PostHookScript(_G["WorldMapFrame"], "OnHide", function()
  terrain.alpha = 0
  if terrain.used > 0 then ClearFrom(1) end
end)
