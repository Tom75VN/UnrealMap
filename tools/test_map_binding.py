import json
from pathlib import Path

from lupa import LuaRuntime


ROOT = Path(__file__).resolve().parents[1]
PROBE = ROOT.parent / "UnrealRuntimeProbe" / "MapOverlayProbe.lua"


MOCK_RUNTIME = r'''
clock = 0
setTextureCalls = 0
frames = {}
UIParent = { _shown = false }
table.getn = table.getn or function(value) return #value end
inInstance = false
instanceType = nil
zoneText = "Elwynn Forest"
realZoneText = "Elwynn Forest"
minimapZoneText = "Elwynn Forest"
subZoneText = ""
instanceName = nil

function NewRegion(name, width, height, x, y)
  local object = {
    _name = name,
    _width = width,
    _height = height,
    _x = x,
    _y = y,
    _shown = true,
    _visible = false,
    _texture = nil,
  }
  function object:GetName() return self._name end
  function object:GetWidth() return self._width end
  function object:GetHeight() return self._height end
  function object:IsShown() return self._shown end
  function object:IsVisible() return self._visible end
  function object:Show() self._shown = true end
  function object:Hide() self._shown = false end
  function object:GetTexture() return self._texture end
  function object:SetTexture(path)
    setTextureCalls = setTextureCalls + 1
    self._texture = path
  end
  function object:GetPoint()
    return "TOPLEFT", WorldMapDetailFrame, "TOPLEFT", self._x, self._y
  end
  return object
end

function NewFrame(name, width, height)
  local object = NewRegion(name, width, height, 0, 0)
  object._scripts = {}
  object._events = {}
  function object:GetScript(kind) return self._scripts[kind] end
  function object:SetScript(kind, callback) self._scripts[kind] = callback end
  function object:RegisterEvent(kind) self._events[kind] = true end
  function object:Show() self._shown = true end
  function object:Hide() self._shown = false end
  frames[table.getn(frames) + 1] = object
  return object
end

WorldMapFrame = NewFrame("WorldMapFrame", 1018, 745)
WorldFrame = NewFrame("WorldFrame", 1835, 768)
WorldMapPositioningGuide = NewFrame("WorldMapPositioningGuide", 1024, 768)
WorldMapDetailFrame = NewFrame("WorldMapDetailFrame", 1002, 668)
WorldMapButton = NewFrame("WorldMapButton", 1002, 668)
WorldMapHighlight = NewRegion("WorldMapHighlight", 128, 128, 0, 0)
WorldMapHighlight._shown = false
WorldMapTooltip = NewFrame("WorldMapTooltip", 0, 0)
WorldMapTooltip._shown = false
WorldMapContinentDropDown = NewFrame("WorldMapContinentDropDown", 180, 32)

for i = 1, 12 do
  _G["WorldMapDetailTile" .. i] = NewRegion(
    "WorldMapDetailTile" .. i, 256, 256, ((i - 1) % 4) * 256,
    -math.floor((i - 1) / 4) * 256)
end

overlayNames = {
  "STORMWIND1", "STORMWIND2", "STORMWIND3", "STORMWIND4",
  "GOLDSHIRE1", "FORESTSEDGE1", "FORESTSEDGE2", "FARGODEEPMINE1",
  "NORTHSHIREVALLEY1", "JERODSLANDING1", "TOWEROFAZORA1",
  "BRACKWELLPUMPKINPATCH1", "EASTVALELOGGINGCAMP1",
  "RIDGEPOINTTOWER1", "RIDGEPOINTTOWER2", "CRYSTALLAKE1",
  "STONECAIRNLAKE1", "STONECAIRNLAKE2",
}

redridgeOverlayNames = {
  "STONEWATCH1", "STONEWATCH2", "GALARDELLVALLEY1", "ALTHERSMILL1",
  "ALTHERSMILL2", "RENDERSVALLEY1", "RENDERSVALLEY2", "LAKEEVERSTILL1",
  "LAKEEVERSTILL2", "LAKEEVERSTILL3", "LAKEEVERSTILL4", "LAKEEVERSTILL5",
  "LAKEEVERSTILL6", "REDRIDGECANYONS1", "REDRIDGECANYONS2",
  "STONEWATCHFALLS1", "STONEWATCHFALLS2", "LAKESHIRE1", "LAKESHIRE2",
  "RENDERSCAMP1", "RENDERSCAMP2", "THREECORNERS1", "THREECORNERS2",
  "THREECORNERS3", "THREECORNERS4", "LAKERIDGEHIGHWAY1",
  "LAKERIDGEHIGHWAY2", "LAKERIDGEHIGHWAY3", "LAKERIDGEHIGHWAY4",
}
alteracOverlayNames = {
  "DALARAN1", "DALARAN2", "DALARAN3", "DALARAN4",
  "STRAHNBRAD1", "STRAHNBRAD2", "STRAHNBRAD3", "STRAHNBRAD4",
}
battlegroundOverlayNames = {
  "DUNBALDAR1", "DUNBALDAR2", "FROSTWOLFKEEP1", "FROSTWOLFKEEP2",
  "ICEBLOODGARRISON1", "ICEBLOODGARRISON2", "ICEBLOODGARRISON3",
  "ICEBLOODGARRISON4",
}
mapOverlayNames = {
  Alterac = alteracOverlayNames, Elwynn = overlayNames, Redridge = redridgeOverlayNames,
  AlteracValley = battlegroundOverlayNames, ArathiBasin = {}, WarsongGulch = {},
  Azeroth = {}, Kalimdor = {}, Ogrimmar = {}, Orgrimmar = {}, Stormwind = {},
  Undercity = {}, World = {}, Darnassis = {}, Darnassus = {}, Ironforge = {},
  ThunderBluff = {},
  DunMorogh = { "IRONFORGE1", "IRONFORGE2" },
  Mulgore = { "THUNDERBLUFF1", "THUNDERBLUFF2" },
}
currentMap = "Elwynn"

for i = 1, 64 do
  _G["WorldMapOverlay" .. i] = NewRegion(
    "WorldMapOverlay" .. i, 256, 256, (i - 1) * 7, -(i - 1) * 5)
end

function GetTime() return clock end
function GetMapInfo()
  if currentMap == nil then return nil, 0, 0 end
  return currentMap, 256, 256
end
function IsInInstance() return inInstance, instanceType end
function GetZoneText() return zoneText end
function GetRealZoneText() return realZoneText end
function GetMinimapZoneText() return minimapZoneText end
function GetSubZoneText() return subZoneText end
function GetInstanceInfo() return instanceName end
function GetCurrentMapContinent() return 1 end
function GetCurrentMapZone() return 1 end
function GetNumMapOverlays() return 12 end
function GetMapOverlayInfo(index)
  return "Interface/WorldMap/Elwynn/AREA" .. index, 256, 256, index, index, 0, 0
end

-- Like the native updater: rebinds tiles and the overlays it uses, and
-- leaves unused overlay slots holding their previous texture.
function BindNativeMap()
  local nativeMap = currentMap or "World"
  for i = 1, 12 do
    _G["WorldMapDetailTile" .. i]._texture =
      "Interface/WorldMap/" .. nativeMap .. "/" .. nativeMap .. i
  end
  local names = mapOverlayNames[currentMap] or {}
  for i = 1, table.getn(names) do
    local overlay = _G["WorldMapOverlay" .. i]
    overlay._texture = "Interface/WorldMap/" .. currentMap .. "/" .. names[i]
  end
end

function TriggerEvent(kind)
  for i = 1, table.getn(frames) do
    local callback = frames[i]._events[kind] and frames[i]._scripts["OnEvent"] or nil
    if callback then callback() end
  end
end

function ClearNativeMap()
  for i = 1, 12 do _G["WorldMapDetailTile" .. i]._texture = nil end
  for i = 1, 64 do
    _G["WorldMapOverlay" .. i]._texture = nil
  end
end

function NativeWorldMapUpdate()
  for i = 1, 12 do GetMapOverlayInfo(i) end
end
function WorldMapFrame_Update() NativeWorldMapUpdate() end

function ToggleWorldMap()
  local opening = _mapPresented ~= true
  _mapPresented = opening
  if opening then BindNativeMap() else ClearNativeMap() end
  NativeWorldMapUpdate()
end

function ShowUIPanel() end
function HideUIPanel() end
function CreateFrame(kind, name, parent)
  local frame = NewFrame(name, 1, 1)
  frame._parent = parent
  _G[name] = frame
  return frame
end

function Step(seconds)
  if clock == 0 then clock = 3923000 end
  local target = clock + seconds
  while clock < target do
    clock = clock + 0.05
    local callbacks = {}
    for i = 1, table.getn(frames) do
      local parent = frames[i]._parent
      local parentBlocksDriver = frames[i]._name == "unrealMapBindingDriver"
        and parent and parent._shown == false
      local callback = not parentBlocksDriver and frames[i]._scripts["OnUpdate"] or nil
      if callback then callbacks[table.getn(callbacks) + 1] = callback end
    end
    for i = 1, table.getn(callbacks) do callbacks[i]() end
  end
end

committedRun = nil
UnrealRuntimeProbeTargeted = {
  helpers = {
    Chat = function() end,
    TrimString = function(value, limit) return string.sub(value, 1, limit) end,
    NewRun = function(group) return { group = group, tests = {}, context = {} } end,
    CommitRun = function(run) committedRun = run end,
  },
  extraRunners = {},
}
'''


def redridge_switch(lua):
    g = lua.globals()
    hd_root = "interface/addons/unrealmap/media/textures/maps/world/"

    def texture(name):
        value = g[name]._texture
        return value.lower().replace("\\", "/") if value else value

    g.currentMap = "Redridge"
    g.ToggleWorldMap()
    g.Step(1)
    for index in range(1, 13):
        assert texture(f"WorldMapDetailTile{index}") == f"{hd_root}redridge/redridge{index}"
    names = list(g.redridgeOverlayNames.values())
    for index, name in enumerate(names, 1):
        expected = f"{hd_root}redridge/{name.lower()}"
        assert texture(f"WorldMapOverlay{index}") == expected, (index, texture(f"WorldMapOverlay{index}"))

    g.currentMap = "Elwynn"
    g.BindNativeMap()
    g.WorldMapFrame_Update()
    g.Step(1)
    for index in range(1, 13):
        actual = texture(f"WorldMapDetailTile{index}")
        expected = f"{hd_root}_unexplored/elwynn/elwynn{index}"
        assert actual == expected, (index, actual, expected)
    for index in range(1, 19):
        assert texture(f"WorldMapOverlay{index}").startswith(f"{hd_root}elwynn/")
    for index in range(19, len(names) + 1):
        assert not (texture(f"WorldMapOverlay{index}") or "").startswith(hd_root),             "stale Redridge HD binding kept"

    g.ToggleWorldMap()
    for index in range(1, len(names) + 1):
        assert not (texture(f"WorldMapOverlay{index}") or "").startswith(hd_root)


def city_without_overlays(lua):
    g = lua.globals()
    hd_root = "interface/addons/unrealmap/media/textures/maps/capitals/"

    def texture(name):
        value = g[name]._texture
        return value.lower().replace("\\", "/") if value else value

    for city, asset_name in (("Stormwind", "Stormwind"),
                             ("Ogrimmar", "Ogrimmar"),
                             ("Orgrimmar", "Ogrimmar"),
                             ("Undercity", "Undercity"),
                             ("Darnassis", "Darnassis"),
                             ("Darnassus", "Darnassis"),
                             ("Ironforge", "Ironforge"),
                             ("ThunderBluff", "ThunderBluff")):
        g.currentMap = city
        g.ToggleWorldMap()
        g.Step(3)
        assert g.unrealMapBindingDriver._parent._name == "WorldFrame", \
            "binding driver must remain active while fullscreen map hides UIParent"
        key = asset_name.lower()
        for index in range(1, 13):
            assert texture(f"WorldMapDetailTile{index}") == f"{hd_root}{key}/{key}{index}"
        for index in range(1, 30):
            assert not (texture(f"WorldMapOverlay{index}") or "").startswith(hd_root)
        assert g.unrealMap.IsMapPresentationActive() is True, \
            f"{city} presentation stopped while open"

        g.ToggleWorldMap()
        g.Step(1)
        for index in range(1, 13):
            assert texture(f"WorldMapDetailTile{index}") in (None, "")
        assert g.unrealMap.IsMapPresentationActive() is False

    # Zone overlays named like a capital carry their map name on disk so the
    # basename-resolved city tiles stay intact.
    world_root = "interface/addons/unrealmap/media/textures/maps/world/"
    for zone, stem in (("DunMorogh", "ironforge"), ("Mulgore", "thunderbluff")):
        g.currentMap = zone
        g.ToggleWorldMap()
        g.Step(3)
        for index in (1, 2):
            assert texture(f"WorldMapOverlay{index}") ==                 f"{world_root}{zone.lower()}/{zone.lower()}{stem}{index}",                 f"{zone} {stem}{index} overlay not prefixed"
        g.ToggleWorldMap()
        g.Step(1)


def world_and_continent_maps(lua):
    g = lua.globals()
    root = "interface/addons/unrealmap/media/textures/maps/continents/"

    def texture(index):
        value = g[f"WorldMapDetailTile{index}"]._texture
        return value.lower().replace("\\", "/") if value else value

    for map_name, get_map_info_name in (("World", None), ("Kalimdor", "Kalimdor"),
                                        ("Azeroth", "Azeroth")):
        g.currentMap = get_map_info_name
        g.ToggleWorldMap()
        g.Step(1)
        key = map_name.lower()
        for index in range(1, 13):
            assert texture(index) == f"{root}{key}/{key}{index}"
        assert g.unrealMap.IsMapPresentationActive() is True
        g.ToggleWorldMap()
        for index in range(1, 13):
            assert texture(index) in (None, "")


def battleground_maps(lua):
    g = lua.globals()
    root = "interface/addons/unrealmap/media/textures/maps/battlegrounds/"

    for map_name in ("AlteracValley", "ArathiBasin", "WarsongGulch"):
        g.currentMap = map_name
        g.ToggleWorldMap()
        g.Step(1)
        key = map_name.lower()
        for index in range(1, 13):
            texture = g[f"WorldMapDetailTile{index}"]._texture
            assert texture.lower().replace("\\", "/") == \
                f"{root}{key}/{key}{index}"
        if map_name == "AlteracValley":
            for index, name in enumerate(g.battlegroundOverlayNames.values(), 1):
                texture = g[f"WorldMapOverlay{index}"]._texture
                assert texture.lower().replace("\\", "/") == \
                    f"{root}{key}/{name.lower()}"
        assert g.unrealMap.IsMapPresentationActive() is True
        g.ToggleWorldMap()
        for index in range(1, 13):
            assert g[f"WorldMapDetailTile{index}"]._texture in (None, "")


def alterac_world_zone(lua):
    g = lua.globals()
    root = "interface/addons/unrealmap/media/textures/maps/world/alterac/"
    g.currentMap = "Alterac"
    g.ToggleWorldMap()
    g.Step(1)
    for index in range(1, 13):
        texture = g[f"WorldMapDetailTile{index}"]._texture.lower().replace("\\", "/")
        assert texture == f"{root}alterac{index}"
    for index in range(1, 9):
        texture = g[f"WorldMapOverlay{index}"]._texture.lower().replace("\\", "/")
        assert texture.startswith(root)
    g.ToggleWorldMap()


def city_click_transition(lua):
    g = lua.globals()
    g.currentMap = "Stormwind"
    g.ToggleWorldMap()
    g.Step(1)
    assert g.WorldMapDetailTile1._texture.lower().replace("\\", "/").endswith(
        "/stormwind/stormwind1")

    g.currentMap = "Elwynn"
    g.BindNativeMap()
    g.WorldMapFrame_Update()
    g.Step(1)
    assert g.WorldMapDetailTile1._texture.lower().replace("\\", "/").endswith(
        "/_unexplored/elwynn/elwynn1")

    g.currentMap = "Stormwind"
    g.ClearNativeMap()
    g.WorldMapFrame_Update()
    g.Step(0.05)
    assert g.unrealMap.IsMapPresentationActive() is True, \
        "driver stopped during the in-map transition texture gap"
    assert not g.WorldMapDetailTile1._shown, \
        "capital tiles were visible while the native update had no textures"

    g.BindNativeMap()
    g.WorldMapFrame_Update()
    assert g.WorldMapDetailTile1._texture == "Interface/WorldMap/Stormwind/Stormwind1", \
        "HD binding ran inside the native click/update transaction"
    assert not g.WorldMapDetailTile1._shown, \
        "native capital tiles remained visible during the deferred HD bind"
    g.Step(0.05)
    assert g.WorldMapDetailTile1._texture.lower().replace("\\", "/").endswith(
        "/stormwind/stormwind1")
    assert not g.WorldMapDetailTile1._shown, \
        "capital tiles were revealed in the same update as the HD path change"
    for index in range(1, 5):
        g[f"WorldMapDetailTile{index}"]._texture = f"Interface/WorldMap/Azeroth/Azeroth{index}"
    g.Step(0.05)
    assert not g.WorldMapDetailTile1._shown, \
        "mixed previous-map and city tiles were revealed after an asynchronous overwrite"
    g.Step(0.05)
    assert not g.WorldMapDetailTile1._shown, \
        "repaired city tiles were revealed in the same update as the rebind"
    g.Step(0.1)
    assert g.WorldMapDetailTile1._shown, \
        "HD capital tiles were not revealed after the repaired binding settled"

    for index in range(1, 5):
        g[f"WorldMapDetailTile{index}"]._texture = f"Interface/WorldMap/Elwynn/Elwynn{index}"
    g.Step(0.05)
    assert not g.WorldMapDetailTile1._shown, \
        "late previous-map tiles stayed visible after the city was revealed"
    g.Step(0.2)
    assert g.WorldMapDetailTile1._shown, \
        "capital tiles were not revealed after repairing a late overwrite"
    for index in range(1, 13):
        assert g[f"WorldMapDetailTile{index}"]._texture.lower().replace("\\", "/").endswith(
            f"/stormwind/stormwind{index}")
    g.ToggleWorldMap()


def ragefire_dungeon(lua):
    g = lua.globals()
    hd_root = "interface/addons/unrealmap/media/textures/maps/dungeons/ragefire/dungeonragefire"

    def texture(index):
        value = g[f"WorldMapDetailTile{index}"]._texture
        return value.lower().replace("\\", "/") if value else value

    # A confirmed character already inside survives every reopen even though
    # all native location/map identity calls are blank.
    g.currentMap = None
    g.zoneText = ""
    g.realZoneText = ""
    g.minimapZoneText = ""
    g.subZoneText = ""
    g.inInstance = True
    g.instanceType = "party"
    ok, _ = g.unrealMap.SetRagefireMapActive(True)
    assert ok is True
    for _ in range(3):
        g.ToggleWorldMap()
        assert not g.WorldMapButton._shown, \
            "continent hit target stayed active before the first driver tick"
        g.Step(1)
        for index in range(1, 13):
            assert texture(index) == f"{hd_root}{index}"
        assert g.unrealMap.GetActiveDungeonMap() == "Ragefire"
        assert not g.WorldMapContinentDropDown._shown
        # Hover shows the continent highlight; a native update re-shows the button.
        g.WorldMapHighlight._shown = True
        g.WorldMapButton._shown = True
        g.WorldMapFrame_Update()
        assert not g.WorldMapButton._shown and not g.WorldMapHighlight._shown, \
            "native update restored the continent interaction layer"
        g.ToggleWorldMap()
        g.Step(0.2)
        assert g.WorldMapButton._shown and g.WorldMapContinentDropDown._shown, \
            "world map controls were not restored after closing Ragefire"
        assert not g.WorldMapHighlight._shown and not g.WorldMapTooltip._shown, \
            "transient hover state was re-shown on close"

    # Leaving clears the saved latch so another party dungeon cannot inherit
    # Ragefire accidentally.
    g.inInstance = False
    g.currentMap = "Elwynn"
    g.zoneText = "Elwynn Forest"
    g.realZoneText = "Elwynn Forest"
    g.TriggerEvent("PLAYER_ENTERING_WORLD")
    assert g.unrealMap.GetActiveDungeonMap() is None

    # A normal entry from Orgrimmar identifies Ragefire without a command.
    g.currentMap = "Ogrimmar"
    g.zoneText = "Orgrimmar"
    g.realZoneText = "Orgrimmar"
    g.TriggerEvent("ZONE_CHANGED_NEW_AREA")
    # Zoning transition: not yet inside, location blank, then already named.
    g.currentMap = "Kalimdor"
    g.zoneText = ""
    g.realZoneText = ""
    g.TriggerEvent("ZONE_CHANGED_NEW_AREA")
    g.zoneText = "Ragefire Chasm"
    g.TriggerEvent("ZONE_CHANGED")
    g.currentMap = None
    g.zoneText = ""
    g.inInstance = True
    g.instanceType = "party"
    g.TriggerEvent("PLAYER_ENTERING_WORLD")
    assert g.unrealMap.GetActiveDungeonMap() == "Ragefire"
    g.ToggleWorldMap()
    g.Step(1)
    for index in range(1, 13):
        assert texture(index) == f"{hd_root}{index}"
    g.ToggleWorldMap()


def vanilla_dungeon_maps(lua):
    g = lua.globals()
    catalog = json.loads((ROOT / "assets" / "dungeon_catalog.json").read_text(
        encoding="utf-8"))
    map_names = [map_name for dungeon in catalog["dungeons"]
                 for map_name in dungeon["maps"]]
    root = "interface/addons/unrealmap/media/textures/maps/dungeons/"

    g.inInstance = True
    g.instanceType = "party"
    g.zoneText = ""
    g.realZoneText = ""
    g.minimapZoneText = ""
    g.subZoneText = ""
    g.instanceName = None

    for map_name in map_names:
        g.currentMap = map_name
        g.TriggerEvent("ZONE_CHANGED_INDOORS")
        g.ToggleWorldMap()
        g.Step(1)
        expected_root = f"{root}{map_name.lower()}/dungeon{map_name.lower()}"
        for index in range(1, 13):
            texture = g[f"WorldMapDetailTile{index}"]._texture
            texture = texture.lower().replace("\\", "/") if texture else texture
            assert texture == f"{expected_root}{index}", (map_name, index, texture)
        assert g.unrealMap.GetActiveDungeonMap() == map_name
        assert not g.WorldMapButton._shown, map_name
        g.ToggleWorldMap()
        g.Step(0.2)

    # Runtime map-key aliases resolve to the exact shipped folder spelling.
    g.currentMap = "BlackfathomDeeps"
    g.TriggerEvent("ZONE_CHANGED_INDOORS")
    g.ToggleWorldMap()
    g.Step(1)
    assert g.WorldMapDetailTile1._texture.lower().replace("\\", "/") == \
        f"{root}blackfathomdeeps/dungeonblackfathomdeeps1"
    g.ToggleWorldMap()

    # A localized instance name provides the default floor when the native map
    # context is blank, matching the Ragefire behavior measured in game.
    g.currentMap = None
    g.zoneText = "影牙城堡"
    g.TriggerEvent("ZONE_CHANGED_INDOORS")
    assert g.unrealMap.GetActiveDungeonMap() == "ShadowfangKeep"
    g.ToggleWorldMap()
    g.Step(1)
    assert g.WorldMapDetailTile1._texture.lower().replace("\\", "/") == \
        f"{root}shadowfangkeep/dungeonshadowfangkeep1"
    g.ToggleWorldMap()

    # Explicit selection covers clients that expose no map or location name;
    # exact floor keys are accepted and persist while the party instance lasts.
    g.zoneText = ""
    ok, _ = g.unrealMap.SetDungeonMapActive("ShadowfangKeep7f")
    assert ok is True
    g.ToggleWorldMap()
    g.Step(1)
    assert g.WorldMapDetailTile1._texture.lower().replace("\\", "/") == \
        f"{root}shadowfangkeep7f/dungeonshadowfangkeep7f1"
    g.ToggleWorldMap()

    g.inInstance = False
    g.currentMap = "Elwynn"
    g.zoneText = "Elwynn Forest"
    g.realZoneText = "Elwynn Forest"
    g.TriggerEvent("PLAYER_ENTERING_WORLD")
    assert g.unrealMap.GetActiveDungeonMap() is None


def vanilla_raid_maps(lua):
    g = lua.globals()
    catalog = json.loads((ROOT / "assets" / "raid_catalog.json").read_text(
        encoding="utf-8"))
    map_names = [map_name for raid in catalog["raids"]
                 for map_name in raid["maps"]]
    root = "interface/addons/unrealmap/media/textures/maps/raids/"

    g.inInstance = True
    g.instanceType = "raid"
    g.zoneText = ""
    g.realZoneText = ""
    g.minimapZoneText = ""
    g.subZoneText = ""
    g.instanceName = None

    for map_name in map_names:
        g.currentMap = map_name
        g.TriggerEvent("ZONE_CHANGED_INDOORS")
        g.ToggleWorldMap()
        g.Step(1)
        expected_root = f"{root}{map_name.lower()}/raid{map_name.lower()}"
        for index in range(1, 13):
            texture = g[f"WorldMapDetailTile{index}"]._texture
            texture = texture.lower().replace("\\", "/") if texture else texture
            assert texture == f"{expected_root}{index}", (map_name, index, texture)
        assert g.unrealMap.GetActiveRaidMap() == map_name
        assert not g.WorldMapButton._shown, map_name
        assert g.unrealMap.GetActiveDungeonMap() is None
        g.ToggleWorldMap()
        g.Step(0.2)

    g.currentMap = "RuinsOfAhnQiraj"
    g.TriggerEvent("ZONE_CHANGED_INDOORS")
    g.ToggleWorldMap()
    g.Step(1)
    assert g.WorldMapDetailTile1._texture.lower().replace("\\", "/") == \
        f"{root}ruinsofahnqiraj/raidruinsofahnqiraj1"
    g.ToggleWorldMap()

    g.currentMap = None
    g.zoneText = "黑翼之巢"
    g.TriggerEvent("ZONE_CHANGED_INDOORS")
    assert g.unrealMap.GetActiveRaidMap() == "BlackwingLair"
    g.ToggleWorldMap()
    g.Step(1)
    assert g.WorldMapDetailTile1._texture.lower().replace("\\", "/") == \
        f"{root}blackwinglair/raidblackwinglair1"
    g.ToggleWorldMap()

    g.zoneText = ""
    ok, _ = g.unrealMap.SetRaidMapActive("BlackwingLair4f")
    assert ok is True
    g.ToggleWorldMap()
    g.Step(1)
    assert g.WorldMapDetailTile1._texture.lower().replace("\\", "/") == \
        f"{root}blackwinglair4f/raidblackwinglair4f1"
    g.ToggleWorldMap()

    g.inInstance = False
    g.currentMap = "BurningSteppes"
    g.zoneText = "Burning Steppes"
    g.realZoneText = "Burning Steppes"
    g.TriggerEvent("PLAYER_ENTERING_WORLD")
    assert g.unrealMap.GetActiveRaidMap() is None


FOG_RUNTIME = r'''
exploredNames = { "GOLDSHIRE", "NORTHSHIREVALLEY" }
exploredGeometry = {
  GOLDSHIRE = { 240, 220, 250, 270 },
  NORTHSHIREVALLEY = { 256, 256, 381, 147 },
}
function GetNumMapOverlays() return table.getn(exploredNames) end
function GetMapOverlayInfo(index)
  local name = exploredNames[index]
  local g = exploredGeometry[name]
  return "Interface/WorldMap/Elwynn/" .. name, g[1], g[2], g[3], g[4], 0, 0
end

-- Like the vanilla updater: enumerates overlays, splits each into 256px
-- pieces and binds <path><piece> on consecutive WorldMapOverlay slots.
drawnPieces = 0
function NativeWorldMapUpdate()
  local used = 0
  for i = 1, GetNumMapOverlays() do
    local path, width, height = GetMapOverlayInfo(i)
    local pieces = math.ceil(width / 256) * math.ceil(height / 256)
    for k = 1, pieces do
      used = used + 1
      _G["WorldMapOverlay" .. used]._texture = path .. k
    end
  end
  for i = used + 1, 64 do
    _G["WorldMapOverlay" .. i]._texture = nil
  end
  drawnPieces = used
end
function BindNativeMap()
  for i = 1, 12 do
    _G["WorldMapDetailTile" .. i]._texture = "Interface/WorldMap/Elwynn/Elwynn" .. i
  end
end
function WorldMapFrame:IsVisible() return _mapPresented == true end
SlashCmdList = {}
DEFAULT_CHAT_FRAME = { AddMessage = function() end }
'''



def load_locale(lua):
    # TOC order: the translation layer loads before unrealMap.lua.
    for name in ("Locale.lua", "Locales/enUS.lua", "Locales/ruRU.lua", "Locales/zhCN.lua"):
        lua.execute((ROOT / name).read_text(encoding="utf-8"))


def load_map_data(lua):
    lua.execute((ROOT / "MapOverlayData.lua").read_text(encoding="utf-8"))
    lua.execute((ROOT / "DungeonMapData.lua").read_text(encoding="utf-8"))
    lua.execute((ROOT / "RaidMapData.lua").read_text(encoding="utf-8"))

def fog_reveal():
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute(MOCK_RUNTIME)
    lua.execute(FOG_RUNTIME)
    load_locale(lua)
    load_map_data(lua)
    lua.execute((ROOT / "unrealMap.lua").read_text(encoding="utf-8"))
    lua.execute((ROOT / "Settings.lua").read_text(encoding="utf-8"))
    g = lua.globals()
    hd_root = "interface/addons/unrealmap/media/textures/maps/world/elwynn/"
    assert g.setTextureCalls == 0, "startup bound map textures"

    def texture(index):
        value = g[f"WorldMapOverlay{index}"]._texture
        return value.lower().replace("\\", "/") if value else value

    assert g.unrealMap.GetFogRevealEnabled() is True
    assert g.GetNumMapOverlays() == 12, "fog reveal was not enabled by default"

    lua.execute('SlashCmdList["UNREALMAP"]("fog off")')
    assert g.unrealMapDB.revealFog is False
    assert g.GetNumMapOverlays() == 2, "explicit fog setting was not preserved"

    g.ToggleWorldMap()
    g.Step(1)
    assert g.drawnPieces == 2

    lua.execute('SlashCmdList["UNREALMAP"]("fog on")')
    assert g.unrealMapDB.revealFog is True
    assert g.GetNumMapOverlays() == 12, g.GetNumMapOverlays()
    revealed = [g.GetMapOverlayInfo(i)[0] for i in range(3, 13)]
    assert "Interface/WorldMap/Elwynn/GOLDSHIRE" not in revealed
    assert "Interface/WorldMap/Elwynn/STORMWIND" in revealed
    g.Step(1)
    assert g.drawnPieces == 18, g.drawnPieces
    for index in range(1, 19):
        assert texture(index).startswith(hd_root), (index, texture(index))

    alias_cases = (
        ("UnGoroCrater", "ungorocrater", 7, 30),
        ("HinterLands", "hinterlands", 14, 20),
        ("Blastedlands", "blastedlands", 9, 13),
        ("TheHinterlands", "hinterlands", 14, 20),
        ("TheBlastedLands", "blastedlands", 9, 13),
    )
    for runtime_name, asset_name, logical_count, piece_count in alias_cases:
        lua.execute(f'currentMap = "{runtime_name}"; exploredNames = {{}}; WorldMapFrame_Update()')
        g.Step(1)
        assert g.GetNumMapOverlays() == logical_count, runtime_name
        first_path = g.GetMapOverlayInfo(1)[0]
        assert first_path.startswith(f"Interface/WorldMap/{runtime_name}/"), first_path
        assert g.drawnPieces == piece_count, (runtime_name, g.drawnPieces)
        alias_root = f"interface/addons/unrealmap/media/textures/maps/world/{asset_name}/"
        assert texture(1).startswith(alias_root), (runtime_name, texture(1))
        for index in range(1, piece_count + 1):
            assert texture(index).startswith(alias_root), (runtime_name, index, texture(index))

    lua.execute('currentMap = "Elwynn"; exploredNames = { "GOLDSHIRE", "NORTHSHIREVALLEY" }; WorldMapFrame_Update()')
    g.Step(1)

    lua.execute('SlashCmdList["UNREALMAP"]("fog off")')
    assert g.GetNumMapOverlays() == 2
    g.Step(1)
    assert g.drawnPieces == 2
    for index in range(3, 30):
        assert not (texture(index) or "").startswith(hd_root), "revealed HD binding kept"

    g.ToggleWorldMap()
    g.Step(1)
    assert g.unrealMapSettings.GetHost() is None, "host decided before the grace period"
    assert g.unrealMapMinimapButton is not None, "provisional minimap button missing"
    g.Step(15)
    assert g.unrealMapSettings.GetHost() == "standalone"
    assert g.unrealMapSettings.Open() is True
    # The window frame must not replace the API table through its global name.
    assert g.unrealMapSettings.Close is not None, "settings API replaced by a frame"
    lua.execute('unrealMapSettingsWindowClose:GetScript("OnClick")()')
    assert g.unrealMapSettingsWindow._shown is False, "Close did not hide the window"


def unrealui_host():
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute(MOCK_RUNTIME)
    lua.execute(FOG_RUNTIME)
    lua.execute('''
      registered = {}
      UnrealUI = {
        RegisterSettingsGroup = function(id, label, options)
          registered[id] = { group = true, label = label, defaultPage = options.defaultPage }
          return registered[id]
        end,
        RegisterSettingsTab = function(id, label, build, options)
          registered[id] = { label = label, build = build, parent = options.parent }
          return registered[id]
        end,
        OpenSettingsPage = function(id) openedPage = id return true end,
      }
    ''')
    load_locale(lua)
    load_map_data(lua)
    lua.execute((ROOT / "unrealMap.lua").read_text(encoding="utf-8"))
    lua.execute((ROOT / "Settings.lua").read_text(encoding="utf-8"))
    g = lua.globals()
    g.Step(1)
    assert g.unrealMapSettings.GetHost() == "unrealui"
    assert g.registered.unrealmap.group is True, "no unrealmap settings group"
    assert g.registered["unrealmap.general"].parent == "unrealmap"
    assert g.unrealMapMinimapButton is None, "minimap button created under unrealUI"
    assert g.unrealMapSettings.Open() is True
    assert g.openedPage == "unrealmap.general"


def main():
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute(MOCK_RUNTIME)
    load_locale(lua)
    load_map_data(lua)
    lua.execute((ROOT / "unrealMap.lua").read_text(encoding="utf-8"))
    assert lua.globals().setTextureCalls == 0, "startup bound map textures"

    lua.execute(PROBE.read_text(encoding="utf-8"))
    lua.execute('UnrealRuntimeProbeTargeted.mapOverlay.HD_ROOT = '
                '"Interface/AddOns/unrealMap/Media/Textures/Maps/World/"')
    assert lua.globals().setTextureCalls == 0, "probe registration bound map textures"
    lua.execute('UnrealRuntimeProbeTargeted.extraRunners["mapoverlay"]()')
    assert lua.globals().setTextureCalls == 0, "manual probe arming bound map textures"

    lua.globals().ToggleWorldMap()
    lua.globals().Step(3)

    run = lua.globals().committedRun
    assert run is not None, "probe did not commit a result"
    result = run.tests["map.elwynn_overlay_binding.v5"]
    assert result.status == "SUPPORTED", result.reason
    verification = result.evidence.verification
    assert verification.passed is True
    assert verification.nativeActive == 18
    assert verification.hdActive == 18
    assert verification.changedCount == 18
    assert verification.geometryMatchCount == 18
    assert verification.baseHDPaths == 12
    assert result.evidence.completion.completed is True

    lua.globals().ToggleWorldMap()
    for index in range(1, 13):
      assert lua.globals()[f"WorldMapDetailTile{index}"]._texture in (None, "")
    for index in range(1, 19):
      assert lua.globals()[f"WorldMapOverlay{index}"]._texture in (None, "")

    redridge_switch(lua)
    alterac_world_zone(lua)
    city_click_transition(lua)
    city_without_overlays(lua)
    world_and_continent_maps(lua)
    battleground_maps(lua)
    ragefire_dungeon(lua)
    vanilla_dungeon_maps(lua)
    vanilla_raid_maps(lua)
    fog_reveal()
    unrealui_host()
    print("Offline lifecycle simulation passed: no startup loads, 18/18 overlays rebound, geometry preserved, result committed, close cleared bindings, Redridge bound with all generated HD pieces, map switch cleared stale bindings, in-map texture gaps kept the driver alive, native city click/update completed before the deferred Stormwind binding, early and late previous-map tile restoration stayed concealed through repair, World, continents, capitals, battlegrounds, all 55 Vanilla dungeon/floor maps, and all 13 Vanilla raid/floor maps bound and cleared, instance map-key aliases, localized instance-name fallback, persisted exact-floor selection, and Ragefire entry detection passed, Alterac Valley native overlays were replaced by transparent suppressions, Dun Morogh/Mulgore capital-named overlays bound to prefixed files, fog reveal defaulted on while preserving an explicit off choice, settings resolved to both hosts")


if __name__ == "__main__":
    main()
