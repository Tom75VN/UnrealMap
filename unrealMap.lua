local TILE_COUNT = 12
local MAX_OVERLAY_TILES = 64
local DRIVER_INTERVAL = 0.1
local ADDON_ROOT = "Interface\\AddOns\\"

-- HD textures ship as separate launcher data packs, one addon folder each.
-- Every pack folder starts with this prefix, which marks an HD binding.
local PACK_PREFIX = ADDON_ROOT .. "unrealMap_"
local UNEXPLORED_CATEGORY = "World_Unexplored"
local CATEGORY_PACKS = {
  Battlegrounds = "unrealMap_World",
  Capitals = "unrealMap_World",
  Continents = "unrealMap_World",
  World = "unrealMap_World",
  World_Unexplored = "unrealMap_Unexplored",
  Dungeons = "unrealMap_Instances",
  Raids = "unrealMap_Instances",
}
-- Every data pack, in the order the settings page lists them.
local PACKS = { "unrealMap_World", "unrealMap_Unexplored", "unrealMap_Instances" }

local function CategoryRoot(category)
  return ADDON_ROOT .. CATEGORY_PACKS[category] .. "\\" .. category .. "\\"
end

local MAP_CATEGORIES = {
  AlteracValley = "Battlegrounds",
  ArathiBasin = "Battlegrounds",
  Azeroth = "Continents",
  Darnassis = "Capitals",
  Ironforge = "Capitals",
  Kalimdor = "Continents",
  Ogrimmar = "Capitals",
  Stormwind = "Capitals",
  ThunderBluff = "Capitals",
  Undercity = "Capitals",
  WarsongGulch = "Battlegrounds",
  World = "Continents",
}

local UNEXPLORED_BASE_MAPS = {
  Alterac = true,
  Arathi = true,
  Ashenvale = true,
  Durotar = true,
  Elwynn = true,
}

local MAP_OVERLAYS = {
  AlteracValley = {
    "DunBaldar1", "DunBaldar2", "FrostwolfKeep1", "FrostwolfKeep2",
    "IcebloodGarrison1", "IcebloodGarrison2", "IcebloodGarrison3",
    "IcebloodGarrison4",
  },
  ArathiBasin = {},
  Azeroth = {},
  Darnassis = {},
  Ironforge = {},
  Kalimdor = {},
  Ogrimmar = {},
  Stormwind = {},
  ThunderBluff = {},
  Undercity = {},
  WarsongGulch = {},
  World = {},
}

local DUNGEON_MAP_DEFAULT = {}
local DUNGEON_NAME_MAP = {}
local RAID_MAP_DEFAULT = {}
local RAID_NAME_MAP = {}

local function DungeonTextKey(value)
  if type(value) ~= "string" then return nil end
  return string.gsub(string.lower(value), "[%s%p]", "")
end

do
  local familyIndex
  for familyIndex = 1, table.getn(unrealMapRaidData) do
    local family = unrealMapRaidData[familyIndex]
    local mapIndex
    for mapIndex = 1, table.getn(family.maps) do
      local mapName = family.maps[mapIndex]
      MAP_CATEGORIES[mapName] = "Raids"
      MAP_OVERLAYS[mapName] = {}
      RAID_MAP_DEFAULT[mapName] = family.default
      RAID_NAME_MAP[DungeonTextKey(mapName)] = mapName
    end
    local aliasIndex
    for aliasIndex = 1, table.getn(family.aliases) do
      RAID_NAME_MAP[DungeonTextKey(family.aliases[aliasIndex])] = family.default
    end
  end
end

do
  local familyIndex
  for familyIndex = 1, table.getn(unrealMapDungeonData) do
    local family = unrealMapDungeonData[familyIndex]
    local mapIndex
    for mapIndex = 1, table.getn(family.maps) do
      local mapName = family.maps[mapIndex]
      MAP_CATEGORIES[mapName] = "Dungeons"
      MAP_OVERLAYS[mapName] = {}
      DUNGEON_MAP_DEFAULT[mapName] = family.default
      DUNGEON_NAME_MAP[DungeonTextKey(mapName)] = mapName
    end
    local aliasIndex
    for aliasIndex = 1, table.getn(family.aliases) do
      DUNGEON_NAME_MAP[DungeonTextKey(family.aliases[aliasIndex])] = family.default
    end
  end
end

local OVERLAY_EXCLUSIONS = {
  DeadwindPass = {
    karazhan1 = true, karazhan2 = true, thevice1 = true, thevice2 = true,
    thevice3 = true, thevice4 = true,
  },
}

do
  local mapName, encoded
  for mapName, encoded in pairs(unrealMapOverlayData) do
    if mapName ~= "AlteracValley" then
      MAP_CATEGORIES[mapName] = "World"
      local names = {}
      local excluded = OVERLAY_EXCLUSIONS[mapName] or {}
      local i
      for i = 1, table.getn(encoded) do
        local _, _, stem, width, height = string.find(
          encoded[i], "^(%w+):(%d+):(%d+):%d+:%d+$")
        width, height = tonumber(width), tonumber(height)
        if stem and width and height then
          local wide = math.floor((width + 255) / 256)
          local tall = math.floor((height + 255) / 256)
          local piece
          for piece = 1, wide * tall do
            local name = stem .. piece
            if not excluded[string.lower(name)] then
              table.insert(names, name)
            end
          end
        end
      end
      table.insert(names, mapName .. "Highlight")
      MAP_OVERLAYS[mapName] = names
    end
  end
end

-- Emberveil can report corrected or legacy map keys that differ from the
-- shipped asset catalog names.
local MAP_ASSET_NAMES = {
  BlackfathomDeeps = "BlackFathomDeeps",
  Blastedlands = "BlastedLands",
  Deadmines = "TheDeadmines",
  Darnassus = "Darnassis",
  HinterLands = "Hinterlands",
  Orgrimmar = "Ogrimmar",
  TheBlastedLands = "BlastedLands",
  TheHinterlands = "Hinterlands",
  TheStockades = "TheStockade",
  TheTempleofAtalHakkar = "TheTempleOfAtalHakkar",
  RuinsOfAhnQiraj = "RuinsofAhnQiraj",
  SunkenTemple = "TheTempleOfAtalHakkar",
  UnGoroCrater = "UngoroCrater",
}

local function AssetMapName(mapName)
  return MAP_ASSET_NAMES[mapName] or mapName
end

local function AssetRoot(mapName)
  local assetMapName = AssetMapName(mapName)
  local category = MAP_CATEGORIES[assetMapName]
  if not category then return nil end
  return CategoryRoot(category) .. assetMapName
end

-- SetTexture cannot detect a missing file (textures.gettexture_echoes_missing_path),
-- so a map binds only when the pack it reads from is installed. The client
-- lists addons once per session; the cache holds one entry per pack.
local packInstalled = {}
local packReported = {}

local function IsPackInstalled(pack)
  if packInstalled[pack] == nil then
    local ok, name = false, nil
    if type(GetAddOnInfo) == "function" then ok, name = pcall(GetAddOnInfo, pack) end
    packInstalled[pack] = ok and type(name) == "string" and name ~= ""
  end
  return packInstalled[pack]
end

local function RequirePack(pack)
  if IsPackInstalled(pack) then return true end
  if not packReported[pack] then
    packReported[pack] = true
    local frame = _G["DEFAULT_CHAT_FRAME"]
    if frame and type(frame.AddMessage) == "function" then
      -- Settings.lua's chat style; the pack name stands out in the accent.
      pcall(frame.AddMessage, frame, "|cffffffffUnreal |cfff5ae0aMap|r |cffb3b3b3: "
        .. unrealMapLocale.L("PACK_MISSING", "|cfff5ae0a" .. pack .. "|cffb3b3b3") .. "|r")
    end
  end
  return false
end

local function MapPacksInstalled(mapName)
  local category = MAP_CATEGORIES[AssetMapName(mapName)]
  return category ~= nil and RequirePack(CATEGORY_PACKS[category])
end

-- A zone with a themed unexplored master keeps its standard base in
-- unrealMap_World. The optional unrealMap_Unexplored pack adds a second base,
-- <Map>_Unexplored1..12, used instead when installed; overlays are shared.
local function UsesUnexploredBase(assetMapName)
  return UNEXPLORED_BASE_MAPS[assetMapName] == true
    and IsPackInstalled(CATEGORY_PACKS[UNEXPLORED_CATEGORY])
end

local function AssetTileRoot(mapName)
  local assetMapName = AssetMapName(mapName)
  if UsesUnexploredBase(assetMapName) then
    return CategoryRoot(UNEXPLORED_CATEGORY) .. assetMapName
  end
  return AssetRoot(assetMapName)
end

local function AssetTileStem(mapName)
  local assetMapName = AssetMapName(mapName)
  if UsesUnexploredBase(assetMapName) then
    return assetMapName .. "_Unexplored"
  elseif MAP_CATEGORIES[assetMapName] == "Dungeons" then
    return "Dungeon" .. assetMapName
  elseif MAP_CATEGORIES[assetMapName] == "Raids" then
    return "Raid" .. assetMapName
  end
  return assetMapName
end

local function IsDungeonMap(mapName)
  local assetMapName = mapName and AssetMapName(mapName) or nil
  return assetMapName ~= nil and MAP_CATEGORIES[assetMapName] == "Dungeons"
end

local function IsRaidMap(mapName)
  local assetMapName = mapName and AssetMapName(mapName) or nil
  return assetMapName ~= nil and MAP_CATEGORIES[assetMapName] == "Raids"
end

local function IsInstanceMap(mapName)
  return IsDungeonMap(mapName) or IsRaidMap(mapName)
end

local function InstanceTypeForMap(mapName)
  if IsDungeonMap(mapName) then return "party" end
  if IsRaidMap(mapName) then return "raid" end
  return nil
end

-- The client resolves addon texture paths by basename alone (probe
-- mapbasename.v1), so overlay stems shared with another shipped file carry
-- their map name on disk. Keep in sync with map_geometry.RUNTIME_PREFIXED.
local OVERLAY_FILE_PREFIXED = {
  BlastedLands = { altarofstorms = true },
  BurningSteppes = { altarofstorms = true },
  DunMorogh = { ironforge = true },
  EasternPlaguelands = { thondrorilriver = true },
  Elwynn = { stormwind = true },
  Mulgore = { thunderbluff = true },
  WesternPlaguelands = { thondrorilriver = true },
}

-- Keep only the active map's basename lookup. The geometry catalog is bounded,
-- but duplicating every overlay name at startup wastes memory for maps that
-- are not being viewed.
local overlayLookupMap
local overlayLookup = {}
local function OverlayNames(mapName)
  if overlayLookupMap == mapName then return overlayLookup end
  local key
  for key in pairs(overlayLookup) do overlayLookup[key] = nil end
  local names = MAP_OVERLAYS[mapName] or {}
  local prefixed = OVERLAY_FILE_PREFIXED[mapName]
  local i
  for i = 1, table.getn(names) do
    local key = string.lower(names[i])
    local stem = string.gsub(key, "%d+$", "")
    if prefixed and prefixed[stem] then
      overlayLookup[key] = mapName .. names[i]
    else
      overlayLookup[key] = names[i]
    end
  end
  overlayLookupMap = mapName
  return overlayLookup
end

local activeMap
local presentationActive = false
local overlayReplacementEnabled = true
local driver
local driverLastTick = 0
local driverStartedAt = 0
local driverAwaitingTextures = false
local tilesConcealed = false
local revealTicks = 0
local worldMap = _G["WorldMapFrame"]
local activeDungeonMap
local lastOutdoorWasOrgrimmar = false
local pendingDungeonMap
local pendingDungeonAt = 0
local activeRaidMap
local pendingRaidMap
local pendingRaidAt = 0
local dungeonWorldLayerBaseline

-- These belong to the native world/continent interaction layer, not to the
-- 12-tile artwork. Dungeon maps replace the artwork while the client may still
-- believes it is showing the cosmic map, so the hit target, hover label,
-- highlight, landmarks and navigation controls must be suspended together.
local DUNGEON_WORLD_LAYER_OBJECTS = {
  "WorldMapButton",
  "WorldMapHighlight",
  "WorldMapFrameAreaLabel",
  "WorldMapFrameAreaDescription",
  "WorldMapTooltip",
  "WorldMapContinentDropDown",
  "WorldMapZoneDropDown",
  "WorldMapZoomOutButton",
  "WorldMapMagnifyingGlassButton",
}

-- Hover state: never re-shown on restore, the native updater shows it on demand.
local DUNGEON_WORLD_LAYER_TRANSIENT = {
  WorldMapHighlight = true,
  WorldMapTooltip = true,
}

local function Now()
  if type(GetTime) ~= "function" then return 0 end
  local ok, value = pcall(GetTime)
  return ok and type(value) == "number" and value or 0
end

local function NormalizePath(path)
  if type(path) ~= "string" then return nil end
  return string.lower(string.gsub(path, "\\", "/"))
end

local function HasPrefix(path, prefix)
  path = NormalizePath(path)
  prefix = NormalizePath(prefix)
  return path and prefix and string.sub(path, 1, string.len(prefix)) == prefix
end

local function TextureBasename(path)
  local normalized = NormalizePath(path)
  if not normalized then return nil end
  return string.match(normalized, "([^/]+)$")
end

local function SafeTexture(region)
  if not region or type(region.GetTexture) ~= "function" then return nil end
  local ok, value = pcall(region.GetTexture, region)
  return ok and value or nil
end

local function IsShown(object)
  if not object or type(object.IsShown) ~= "function" then return false end
  local ok, shown = pcall(object.IsShown, object)
  return ok and shown and true or false
end

local function SuspendDungeonWorldLayer()
  if not dungeonWorldLayerBaseline then
    dungeonWorldLayerBaseline = {}
    local i
    for i = 1, table.getn(DUNGEON_WORLD_LAYER_OBJECTS) do
      local name = DUNGEON_WORLD_LAYER_OBJECTS[i]
      local object = _G[name]
      dungeonWorldLayerBaseline[name] = {
        object = object,
        shown = not DUNGEON_WORLD_LAYER_TRANSIENT[name] and IsShown(object),
      }
    end
  end

  local name, saved
  for name, saved in pairs(dungeonWorldLayerBaseline) do
    if saved.object and type(saved.object.Hide) == "function" then
      pcall(saved.object.Hide, saved.object)
    end
  end
end

local function RestoreDungeonWorldLayer()
  if not dungeonWorldLayerBaseline then return end
  local _, saved
  for _, saved in pairs(dungeonWorldLayerBaseline) do
    if saved.object then
      if saved.shown and type(saved.object.Show) == "function" then
        pcall(saved.object.Show, saved.object)
      elseif not saved.shown and type(saved.object.Hide) == "function" then
        pcall(saved.object.Hide, saved.object)
      end
    end
  end
  dungeonWorldLayerBaseline = nil
end

local function ResolveTiles()
  local tiles = {}
  local i
  for i = 1, TILE_COUNT do
    local tile = _G["WorldMapDetailTile" .. i]
    if not tile or type(tile.SetTexture) ~= "function" then
      return nil
    end
    tiles[i] = tile
  end
  return tiles
end

local function CurrentMapName()
  if type(GetMapInfo) ~= "function" then return nil end
  local ok, name = pcall(GetMapInfo)
  if ok and type(name) == "string" then return name end
  local texture = NormalizePath(SafeTexture(_G["WorldMapDetailTile1"]))
  if texture and string.find(texture, "/world/world1$") then return "World" end
  return nil
end

local function Database()
  if type(unrealMapDB) ~= "table" then unrealMapDB = {} end
  return unrealMapDB
end

local function CurrentInstance()
  if type(IsInInstance) ~= "function" then return false, nil end
  local ok, inside, instanceType = pcall(IsInInstance)
  if not ok then return false, nil end
  return inside == true, instanceType
end

local function SafeLocationText(functionName)
  local fn = _G[functionName]
  if type(fn) ~= "function" then return nil end
  local ok, value = pcall(fn)
  if not ok or type(value) ~= "string" or value == "" then return nil end
  return string.lower(value)
end

local LOCATION_FUNCTIONS = {
  "GetZoneText", "GetRealZoneText", "GetMinimapZoneText", "GetSubZoneText",
}

-- fragment nil: true when any location text is available.
local function LocationContains(fragment)
  local i
  for i = 1, table.getn(LOCATION_FUNCTIONS) do
    local text = SafeLocationText(LOCATION_FUNCTIONS[i])
    if text and (not fragment or string.find(text, fragment, 1, true)) then
      return true
    end
  end
  return false
end

local function DungeonMapFromText(value)
  local key = DungeonTextKey(value)
  if not key or key == "" then return nil end
  local exact = DUNGEON_NAME_MAP[key]
  if exact then return exact end
  local alias, mapName
  for alias, mapName in pairs(DUNGEON_NAME_MAP) do
    if string.find(key, alias, 1, true) then return mapName end
  end
  return nil
end

local function DungeonMapFromContext()
  local current = AssetMapName(CurrentMapName())
  if IsDungeonMap(current) then return current end

  if type(GetInstanceInfo) == "function" then
    local ok, name = pcall(GetInstanceInfo)
    if ok then
      local mapName = DungeonMapFromText(name)
      if mapName then return mapName end
    end
  end

  local i
  for i = 1, table.getn(LOCATION_FUNCTIONS) do
    local fn = _G[LOCATION_FUNCTIONS[i]]
    if type(fn) == "function" then
      local ok, text = pcall(fn)
      if ok then
        local mapName = DungeonMapFromText(text)
        if mapName then return mapName end
      end
    end
  end
  return nil
end

local function RaidMapFromText(value)
  local key = DungeonTextKey(value)
  if not key or key == "" then return nil end
  local exact = RAID_NAME_MAP[key]
  if exact then return exact end
  local alias, mapName
  for alias, mapName in pairs(RAID_NAME_MAP) do
    if string.find(key, alias, 1, true) then return mapName end
  end
  return nil
end

local function RaidMapFromContext()
  local current = AssetMapName(CurrentMapName())
  if IsRaidMap(current) then return current end

  if type(GetInstanceInfo) == "function" then
    local ok, name = pcall(GetInstanceInfo)
    if ok then
      local mapName = RaidMapFromText(name)
      if mapName then return mapName end
    end
  end

  local i
  for i = 1, table.getn(LOCATION_FUNCTIONS) do
    local fn = _G[LOCATION_FUNCTIONS[i]]
    if type(fn) == "function" then
      local ok, text = pcall(fn)
      if ok then
        local mapName = RaidMapFromText(text)
        if mapName then return mapName end
      end
    end
  end
  return nil
end

-- Zoning fires events whose instance state and location texts can be blank or
-- already name Ragefire before IsInInstance turns true. Only a named
-- non-Orgrimmar location may clear the entry memory.
local function RememberOutdoorContext()
  local dungeonMap = DungeonMapFromContext()
  if dungeonMap then
    pendingDungeonMap = DUNGEON_MAP_DEFAULT[dungeonMap] or dungeonMap
    pendingDungeonAt = Now()
  end
  if LocationContains("orgrimmar") or LocationContains("ogrimmar")
      or LocationContains("ragefire") then
    lastOutdoorWasOrgrimmar = true
  elseif LocationContains(nil) then
    lastOutdoorWasOrgrimmar = false
  end
end

local function StoreDungeonMap(mapName)
  if mapName and not IsDungeonMap(mapName) then return false end
  activeDungeonMap = mapName
  Database().activeDungeonMap = mapName
  return true
end

local function RememberOutdoorRaidContext()
  local raidMap = RaidMapFromContext()
  if raidMap then
    pendingRaidMap = RAID_MAP_DEFAULT[raidMap] or raidMap
    pendingRaidAt = Now()
  end
end

local function StoreRaidMap(mapName)
  if mapName and not IsRaidMap(mapName) then return false end
  activeRaidMap = mapName
  Database().activeRaidMap = mapName
  return true
end

local function RefreshDungeonContext()
  local inside, instanceType = CurrentInstance()
  if not inside or instanceType ~= "party" then
    StoreDungeonMap(nil)
    RememberOutdoorContext()
    return nil
  end

  local detected = DungeonMapFromContext()
  if detected then
    StoreDungeonMap(detected)
    return activeDungeonMap
  end

  if IsDungeonMap(activeDungeonMap) then return activeDungeonMap end
  local saved = Database().activeDungeonMap
  if IsDungeonMap(saved) then
    activeDungeonMap = saved
    return activeDungeonMap
  end

  local now = Now()
  if pendingDungeonMap and (pendingDungeonAt <= 0 or now <= 0
      or now - pendingDungeonAt <= 30) then
    StoreDungeonMap(pendingDungeonMap)
    pendingDungeonMap = nil
    pendingDungeonAt = 0
    return activeDungeonMap
  end
  pendingDungeonMap = nil
  pendingDungeonAt = 0
  if lastOutdoorWasOrgrimmar then
    StoreDungeonMap("Ragefire")
    return activeDungeonMap
  end
  return nil
end

local function RefreshRaidContext()
  local inside, instanceType = CurrentInstance()
  if not inside or instanceType ~= "raid" then
    StoreRaidMap(nil)
    RememberOutdoorRaidContext()
    return nil
  end

  local detected = RaidMapFromContext()
  if detected then
    StoreRaidMap(detected)
    return activeRaidMap
  end

  if IsRaidMap(activeRaidMap) then return activeRaidMap end
  local saved = Database().activeRaidMap
  if IsRaidMap(saved) then
    activeRaidMap = saved
    return activeRaidMap
  end

  local now = Now()
  if pendingRaidMap and (pendingRaidAt <= 0 or now <= 0
      or now - pendingRaidAt <= 30) then
    StoreRaidMap(pendingRaidMap)
    pendingRaidMap = nil
    pendingRaidAt = 0
    return activeRaidMap
  end
  pendingRaidMap = nil
  pendingRaidAt = 0
  return nil
end

local function IsSupportedMap(name)
  local assetMapName = name and AssetMapName(name) or nil
  return assetMapName ~= nil and MAP_OVERLAYS[assetMapName] ~= nil
    and MAP_CATEGORIES[assetMapName] ~= nil
end

local function HasActiveOverlayTexture()
  local i
  for i = 1, MAX_OVERLAY_TILES do
    local overlay = _G["WorldMapOverlay" .. i]
    local texture = SafeTexture(overlay)
    if type(texture) == "string" and texture ~= "" then return true end
  end
  return false
end

local function HasHDBaseTile()
  return HasPrefix(SafeTexture(_G["WorldMapDetailTile1"]), PACK_PREFIX)
end

local function SelectedMap()
  local dungeonMap = RefreshDungeonContext()
  if dungeonMap then return dungeonMap end
  local raidMap = RefreshRaidContext()
  if raidMap then return raidMap end
  local name = CurrentMapName()
  if IsSupportedMap(name) then return name end
  if activeMap and not IsInstanceMap(activeMap) and HasHDBaseTile() then
    return activeMap
  end
  return nil
end

-- A map whose pack is missing stays native.
local function BindingMap()
  local mapName = SelectedMap()
  if mapName and MapPacksInstalled(mapName) then return mapName end
  return nil
end

local function IsWorldMapVisible()
  if not worldMap or type(worldMap.IsVisible) ~= "function" then return false end
  local ok, visible = pcall(worldMap.IsVisible, worldMap)
  return ok and visible and true or false
end

-- Overlay textures are the verified open-map signal; maps without overlays
-- (cities) fall back to a bound base tile. A zone with nothing explored and
-- fog kept draws no overlay, so it uses the base tile while the map is visible.
local function IsPresented(mapName)
  if HasActiveOverlayTexture() then return true end
  local assetMapName = mapName and AssetMapName(mapName) or nil
  if not assetMapName then return false end
  if table.getn(MAP_OVERLAYS[assetMapName]) > 0 and not IsWorldMapVisible() then
    return false
  end
  local texture = SafeTexture(_G["WorldMapDetailTile1"])
  return type(texture) == "string" and texture ~= ""
end

local function ConcealCityTiles(mapName)
  local assetMapName = mapName and AssetMapName(mapName) or nil
  if not assetMapName or table.getn(MAP_OVERLAYS[assetMapName]) > 0 then return end
  local tiles = ResolveTiles()
  if not tiles then return end
  local i
  for i = 1, TILE_COUNT do
    if type(tiles[i].Hide) == "function" then pcall(tiles[i].Hide, tiles[i]) end
  end
  tilesConcealed = true
  revealTicks = 1
end

local function CityTilesReady(mapName)
  local assetMapName = mapName and AssetMapName(mapName) or nil
  if not assetMapName or table.getn(MAP_OVERLAYS[assetMapName]) > 0 then
    return true
  end
  local tiles = ResolveTiles()
  if not tiles then return false end
  local root = AssetTileRoot(assetMapName) .. "\\" .. AssetTileStem(assetMapName)
  local i
  for i = 1, TILE_COUNT do
    if NormalizePath(SafeTexture(tiles[i])) ~= NormalizePath(root .. i) then
      return false
    end
  end
  return true
end

local function RevealTiles()
  revealTicks = 0
  if not tilesConcealed then return end
  local tiles = ResolveTiles()
  local i
  if tiles then
    for i = 1, TILE_COUNT do
      if type(tiles[i].Show) == "function" then pcall(tiles[i].Show, tiles[i]) end
    end
  end
  tilesConcealed = false
end

local function ClearBindings(keepConcealed)
  local tiles = ResolveTiles()
  local i
  if tiles then
    for i = 1, TILE_COUNT do
      if HasPrefix(SafeTexture(tiles[i]), PACK_PREFIX) then
        pcall(tiles[i].SetTexture, tiles[i], "")
      end
    end
  end

  for i = 1, MAX_OVERLAY_TILES do
    local overlay = _G["WorldMapOverlay" .. i]
    if overlay and type(overlay.SetTexture) == "function"
        and HasPrefix(SafeTexture(overlay), PACK_PREFIX) then
      pcall(overlay.SetTexture, overlay, "")
    end
  end
  RestoreDungeonWorldLayer()
  activeMap = nil
  if not keepConcealed then RevealTiles() end
end

local function ApplyOverlays(mapName)
  if not overlayReplacementEnabled then return 0 end
  local assetMapName = AssetMapName(mapName)
  local names = OverlayNames(assetMapName)
  local root = AssetRoot(assetMapName) .. "\\"
  local bound = 0
  local i
  for i = 1, MAX_OVERLAY_TILES do
    local overlay = _G["WorldMapOverlay" .. i]
    if overlay and type(overlay.SetTexture) == "function" then
      local current = SafeTexture(overlay)
      local basename = TextureBasename(current)
      local replacement = basename and names[basename] or nil
      if replacement then
        local path = root .. replacement
        if NormalizePath(current) ~= NormalizePath(path) then
          pcall(overlay.SetTexture, overlay, path)
        end
        bound = bound + 1
      end
    end
  end
  return bound
end

local function ApplyReplacement(force)
  if not presentationActive and not force then return false end
  local mapName = BindingMap()
  if not mapName then
    ClearBindings()
    return false
  end
  -- Map switch: drop the previous map's bindings, including hidden overlay
  -- slots the native updater did not reuse.
  if activeMap and activeMap ~= mapName then ClearBindings(tilesConcealed) end

  local tiles = ResolveTiles()
  if not tiles then
    RevealTiles()
    return false
  end

  local assetMapName = AssetMapName(mapName)
  local root = AssetTileRoot(assetMapName) .. "\\" .. AssetTileStem(assetMapName)
  local i
  for i = 1, TILE_COUNT do
    local path = root .. i
    if NormalizePath(SafeTexture(tiles[i])) ~= NormalizePath(path) then
      pcall(tiles[i].SetTexture, tiles[i], path)
    end
  end
  ApplyOverlays(mapName)
  activeMap = mapName
  local inside, instanceType = CurrentInstance()
  if IsInstanceMap(assetMapName)
      and inside and instanceType == InstanceTypeForMap(assetMapName) then
    SuspendDungeonWorldLayer()
  else
    RestoreDungeonWorldLayer()
  end
  if tilesConcealed then revealTicks = 1 end
  return true
end

local function StopDriver(clear)
  presentationActive = false
  driverAwaitingTextures = false
  driverStartedAt = 0
  if driver then
    driver:SetScript("OnUpdate", nil)
    driver:Hide()
  end
  if clear then ClearBindings() end
end

local function DriverUpdate()
  local now = Now()
  if driverStartedAt <= 0 then driverStartedAt = now end
  local mapName = BindingMap()
  if not mapName then
    StopDriver(true)
    return
  end
  if not IsPresented(mapName) then
    if driverAwaitingTextures and now - driverStartedAt < 2 then return end
    StopDriver(true)
    return
  end
  driverAwaitingTextures = false
  if not CityTilesReady(mapName) then
    ConcealCityTiles(mapName)
  end
  if tilesConcealed and revealTicks > 0 then
    if CityTilesReady(mapName) then
      revealTicks = revealTicks - 1
      if revealTicks == 0 then RevealTiles() end
    else
      revealTicks = 1
    end
  end
  if now - driverLastTick < DRIVER_INTERVAL then return end
  driverLastTick = now
  ApplyReplacement()
end

local function StartDriver(deferApply)
  if deferApply then
    local mapName = BindingMap()
    ConcealCityTiles(mapName)
    -- Suspend before the first driver tick so no continent hover can flash.
    if IsInstanceMap(mapName) then SuspendDungeonWorldLayer() end
  end
  if presentationActive then
    if deferApply then
      driverAwaitingTextures = true
      driverStartedAt = Now()
      driverLastTick = 0
    else
      ApplyReplacement()
    end
    return
  end
  if not driver then
    driver = CreateFrame("Frame", "unrealMapBindingDriver",
      _G["WorldFrame"] or UIParent)
  end
  presentationActive = true
  driverAwaitingTextures = deferApply and true or false
  driverStartedAt = 0
  driverLastTick = 0
  driver:Show()
  driver:SetScript("OnUpdate", DriverUpdate)
  if not deferApply then ApplyReplacement() end
end

local nativeUpdate = _G["WorldMapFrame_Update"]
if type(nativeUpdate) == "function" then
  _G["WorldMapFrame_Update"] = function()
    nativeUpdate()
    local mapName = BindingMap()
    if mapName and (presentationActive or IsPresented(mapName)) then
      -- Let the native click/update transaction finish before rebinding tiles.
      StartDriver(true)
    elseif presentationActive then
      StopDriver(true)
    end
  end
end

-- Fog of war. With the revealFog setting on, the overlay enumeration also
-- reports the current zone's unexplored overlays (unrealMapOverlayData), after
-- the explored ones. The native updater then draws them with its own texture
-- pool, geometry and texcoords, and the HD binding rebinds them by basename
-- like any explored piece. Only the map being drawn is parsed, into reused
-- arrays capped at REVEAL_MAX entries.
local REVEAL_MAX = 64
local nativeGetNumMapOverlays = _G["GetNumMapOverlays"]
local nativeGetMapOverlayInfo = _G["GetMapOverlayInfo"]
local revealEnabled, revealMap, revealNative
local revealCount = 0
local revealName, revealWidth, revealHeight, revealX, revealY = {}, {}, {}, {}, {}
local exploredNames = {}

local function IsFogRevealEnabled()
  local db = _G["unrealMapDB"]
  return type(db) ~= "table" or db.revealFog ~= false
end

local function NativeOverlayCount()
  if type(nativeGetNumMapOverlays) ~= "function" then return 0 end
  local ok, count = pcall(nativeGetNumMapOverlays)
  return ok and type(count) == "number" and count or 0
end

-- Rebuilds the unexplored list only when the map, the explored count or the
-- setting changed since the last call.
local function EnsureReveal(nativeCount)
  local enabled = IsFogRevealEnabled()
  local mapName = enabled and CurrentMapName() or nil
  if enabled == revealEnabled and mapName == revealMap
      and nativeCount == revealNative then
    return
  end
  revealEnabled, revealMap, revealNative = enabled, mapName, nativeCount
  revealCount = 0
  local dataMapName = mapName and AssetMapName(mapName) or nil
  local data = dataMapName and type(unrealMapOverlayData) == "table"
    and unrealMapOverlayData[dataMapName] or nil
  if type(data) ~= "table" or type(nativeGetMapOverlayInfo) ~= "function" then
    return
  end

  local key
  for key in pairs(exploredNames) do exploredNames[key] = nil end
  local i
  for i = 1, nativeCount do
    local ok, path = pcall(nativeGetMapOverlayInfo, i)
    local basename = ok and TextureBasename(path) or nil
    if basename then exploredNames[basename] = true end
  end

  for i = 1, table.getn(data) do
    local _, _, name, width, height, x, y =
      string.find(data[i], "^(%w+):(%d+):(%d+):(%d+):(%d+)$")
    if name and not exploredNames[string.lower(name)]
        and revealCount < REVEAL_MAX then
      revealCount = revealCount + 1
      revealName[revealCount] = name
      revealWidth[revealCount] = tonumber(width)
      revealHeight[revealCount] = tonumber(height)
      revealX[revealCount] = tonumber(x)
      revealY[revealCount] = tonumber(y)
    end
  end
end

if type(nativeGetNumMapOverlays) == "function" then
  _G["GetNumMapOverlays"] = function()
    if not IsFogRevealEnabled() then return nativeGetNumMapOverlays() end
    local count = NativeOverlayCount()
    EnsureReveal(count)
    return count + revealCount
  end
end

if type(nativeGetMapOverlayInfo) == "function" then
  _G["GetMapOverlayInfo"] = function(index)
    local currentMap = CurrentMapName()
    if IsSupportedMap(currentMap) and MapPacksInstalled(currentMap) then
      StartDriver(true)
    end
    if IsFogRevealEnabled() and type(index) == "number" then
      local nativeCount = NativeOverlayCount()
      EnsureReveal(nativeCount)
      local slot = index - nativeCount
      if slot >= 1 and slot <= revealCount then
        -- Same form as the native paths: Interface/WorldMap/<map>/<NAME>.
        return "Interface/WorldMap/" .. revealMap .. "/" .. revealName[slot],
          revealWidth[slot], revealHeight[slot], revealX[slot], revealY[slot],
          0, 0
      end
    end
    return nativeGetMapOverlayInfo(index)
  end
end

-- Redraws an open map after the setting changed. A closed map is left alone:
-- running the updater while closed populates stale native paths.
local function RefreshOpenMap()
  if not IsWorldMapVisible() then return end
  -- Overlay slots the redraw stops using would keep their HD binding.
  ClearBindings()
  local update = _G["WorldMapFrame_Update"]
  if type(update) == "function" then pcall(update) end
end

local function SetDungeonMapActive(mapName)
  if mapName == nil or mapName == "" or mapName == "off" then
    StoreDungeonMap(nil)
    pendingDungeonMap = nil
    pendingDungeonAt = 0
    RefreshOpenMap()
    return true, unrealMapLocale.L("DUNGEON_CLEARED")
  end

  local inside, instanceType = CurrentInstance()
  if not inside or instanceType ~= "party" then
    return false, unrealMapLocale.L("DUNGEON_NEEDS_INSTANCE")
  end
  local resolved = DungeonMapFromText(mapName)
  if not resolved then
    return false, unrealMapLocale.L("DUNGEON_UNKNOWN", mapName)
  end
  StoreDungeonMap(resolved)
  pendingDungeonMap = nil
  pendingDungeonAt = 0
  RefreshOpenMap()
  return true, unrealMapLocale.L("DUNGEON_ENABLED", resolved)
end

local function SetRaidMapActive(mapName)
  if mapName == nil or mapName == "" or mapName == "off" then
    StoreRaidMap(nil)
    pendingRaidMap = nil
    pendingRaidAt = 0
    RefreshOpenMap()
    return true, unrealMapLocale.L("RAID_CLEARED")
  end

  local inside, instanceType = CurrentInstance()
  if not inside or instanceType ~= "raid" then
    return false, unrealMapLocale.L("RAID_NEEDS_INSTANCE")
  end
  local resolved = RaidMapFromText(mapName)
  if not resolved then
    return false, unrealMapLocale.L("RAID_UNKNOWN", mapName)
  end
  StoreRaidMap(resolved)
  pendingRaidMap = nil
  pendingRaidAt = 0
  RefreshOpenMap()
  return true, unrealMapLocale.L("RAID_ENABLED", resolved)
end

local function SetRagefireMapActive(enabled)
  return SetDungeonMapActive(enabled and "Ragefire" or "off")
end

if worldMap and type(worldMap.GetScript) == "function"
    and type(worldMap.SetScript) == "function" then
  local nativeOnHide = worldMap:GetScript("OnHide")
  worldMap:SetScript("OnHide", function()
    if nativeOnHide then nativeOnHide() end
    StopDriver(true)
  end)
end

local nativeShowPanel = _G["ShowUIPanel"]
if worldMap and type(nativeShowPanel) == "function" then
  _G["ShowUIPanel"] = function(...)
    local frame = arg[1]
    nativeShowPanel(unpack(arg, 1, arg.n))
    if frame == worldMap then StartDriver(true) end
  end
end

local nativeHidePanel = _G["HideUIPanel"]
if worldMap and type(nativeHidePanel) == "function" then
  _G["HideUIPanel"] = function(...)
    local frame = arg[1]
    nativeHidePanel(unpack(arg, 1, arg.n))
    if frame == worldMap then StopDriver(true) end
  end
end

local nativeToggle = _G["ToggleWorldMap"]
if type(nativeToggle) == "function" then
  _G["ToggleWorldMap"] = function()
    local opening = not presentationActive
    nativeToggle()
    if opening then
      StartDriver(true)
    else
      StopDriver(true)
    end
  end
end

-- Keep the instance-map latches current without depending on the world map
-- being opened. Saved selections survive reloads or client restarts only
-- while the character remains inside the matching party or raid instance.
local dungeonContextFrame = CreateFrame("Frame", "unrealMapDungeonContext",
  _G["WorldFrame"] or UIParent)
local dungeonEvents = {
  "PLAYER_ENTERING_WORLD", "ZONE_CHANGED", "ZONE_CHANGED_INDOORS",
  "ZONE_CHANGED_NEW_AREA",
}
local dungeonEventIndex
for dungeonEventIndex = 1, table.getn(dungeonEvents) do
  pcall(dungeonContextFrame.RegisterEvent, dungeonContextFrame,
    dungeonEvents[dungeonEventIndex])
end
dungeonContextFrame:SetScript("OnEvent", function()
  local previousDungeon = activeDungeonMap
  local previousRaid = activeRaidMap
  RefreshDungeonContext()
  RefreshRaidContext()
  if previousDungeon ~= activeDungeonMap or previousRaid ~= activeRaidMap then
    RefreshOpenMap()
  end
end)
RefreshDungeonContext()
RefreshRaidContext()

unrealMap = {
  version = "0.6.0",
  ApplyReplacement = ApplyReplacement,
  ClearBindings = ClearBindings,
  GetFogRevealEnabled = IsFogRevealEnabled,
  GetPacks = function()
    return PACKS
  end,
  IsPackInstalled = IsPackInstalled,
  GetOverlayReplacementEnabled = function()
    return overlayReplacementEnabled
  end,
  IsMapPresentationActive = function()
    return presentationActive
  end,
  GetActiveDungeonMap = function()
    return RefreshDungeonContext()
  end,
  GetActiveRaidMap = function()
    return RefreshRaidContext()
  end,
  SetDungeonMapActive = SetDungeonMapActive,
  SetRaidMapActive = SetRaidMapActive,
  SetRagefireMapActive = SetRagefireMapActive,
  SetFogRevealEnabled = function(enabled)
    if type(unrealMapDB) ~= "table" then unrealMapDB = {} end
    unrealMapDB.revealFog = enabled and true or false
    RefreshOpenMap()
    return unrealMapDB.revealFog
  end,
  SetOverlayReplacementEnabled = function(enabled)
    overlayReplacementEnabled = enabled and true or false
    return overlayReplacementEnabled
  end,
}
