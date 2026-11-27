--[[
unrealMap / MapZoomBench.lua

/umap bench: measures what a drag on the zoomed world map costs (user
report, 2026-11-27: still laggy after the placement cache). This client has no
per-addon CPU readers and no sub-frame clock, so cost is read as frame length
(GetTime deltas, one per draw) with parts of the drag switched off in turn
(knowledge.json / perf.no_addon_cpu_profiling_or_subframe_clock); its frame
cost tracks on-screen regions more than Lua
(actionbars.frame_cost_scales_with_regions), so the phases separate the two.

Phases, rotated every PHASE_FRAMES drag frames that moved the map:
  all     everything on
  follow  the move counter frozen: other addons' markers do not follow
  hide    other addons' markers hidden while moving (W.ZoomMarkersHidden)
  move    the pan moves nothing (the floor)
Run 1 (2026-11-27, Barrens at 4x, 1180 WorldMapButton children) also had a
"crop" phase (no cropping or re-placing): 25.4 ms against 22.8 ms for "all",
so cropping costs nothing measurable and that phase is gone (MapZoom.lua keeps
the switch). Run 3 (Barrens at 3.5x, 964 children), mean drag frame: all
22.4 ms, follow 16.3, insets 23.6, move 11.0, still map 9.1 -- the hit-rect
insets cost nothing; markers following the drag ~6 ms; moving the canvas ~5 ms.
Run 4, after unrealQuest's edge-only follow: all 20.1, follow 18.4, insets
22.2, move 11.4 -- following ~1.7 ms, moving the canvas ~7 ms; the insets
phase is gone (MapZoom.lua keeps the switch) for "hide".

Armed while the map is closed (no chat with the fullscreen map open), driven
from the map tick, saved to unrealMapDB.diag.zoomBench on completion. Stats are
a fixed histogram per phase; nothing grows with the run's length.
]]

local W = type(unrealMap) == "table" and unrealMap.MapWindow
if type(W) ~= "table" or type(W.zoomState) ~= "table" then return end

local state = W.zoomState

local PHASES = {
  { name = "all" },
  { name = "follow", follow = true },
  { name = "hide", hide = true },
  { name = "move", move = true },
}
-- 4 phases x 2 rounds x (60 + 8) drag frames: about 20 s of dragging at the
-- measured 40 fps (run 2 at 3 x 88 frames was never finished).
local PHASE_FRAMES = 60
local SETTLE_FRAMES = 8
local ROUNDS = 2
local BUCKET_MS, BUCKETS = 2, 60

local bench = { armed = false }

local function NewStat()
  local stat = { frames = 0, total = 0, worst = 0, hist = {} }
  local i
  for i = 1, BUCKETS do stat.hist[i] = 0 end
  return stat
end

local function Charge(stat, ms)
  stat.frames = stat.frames + 1
  stat.total = stat.total + ms
  if ms > stat.worst then stat.worst = ms end
  local bucket = math.floor(ms / BUCKET_MS) + 1
  if bucket > BUCKETS then bucket = BUCKETS end
  stat.hist[bucket] = stat.hist[bucket] + 1
end

local function Percentile(stat, share)
  local want, seen = stat.frames * share, 0
  local i
  for i = 1, BUCKETS do
    seen = seen + stat.hist[i]
    if seen >= want then return i * BUCKET_MS end
  end
  return BUCKETS * BUCKET_MS
end

local function Round2(value)
  return math.floor(value * 100 + 0.5) / 100
end

local function Summary(stat)
  if stat.frames == 0 then return { frames = 0 } end
  return {
    frames = stat.frames,
    meanMs = Round2(stat.total / stat.frames),
    p50Ms = Percentile(stat, 0.5),
    p90Ms = Percentile(stat, 0.9),
    worstMs = Round2(stat.worst),
  }
end

local function Count(frame, method)
  if not frame or type(frame[method]) ~= "function" then return nil end
  local ok, value = pcall(frame[method], frame)
  if ok then return tonumber(value) end
  return nil
end

-- One read when the first drag frame lands, with the map populated; counts
-- only, never a child walk (nameplates.flicker_probe_walk_crash).
local function Context()
  local button, detail = _G["WorldMapButton"], _G["WorldMapDetailFrame"]
  local context = {
    buttonChildren = Count(button, "GetNumChildren"),
    buttonRegions = Count(button, "GetNumRegions"),
    detailChildren = Count(detail, "GetNumChildren"),
    detailRegions = Count(detail, "GetNumRegions"),
    zoom = Round2(state.zoom or 1),
  }
  if type(GetNumFrames) == "function" then
    local ok, frames = pcall(GetNumFrames)
    if ok then context.frames = tonumber(frames) end
  end
  if type(GetMapInfo) == "function" then
    local ok, map = pcall(GetMapInfo)
    if ok then context.map = map end
  end
  return context
end

local function SetPhase(index)
  bench.phase = index
  bench.counted, bench.settle = 0, SETTLE_FRAMES
  local spec = PHASES[index]
  local off = bench.off
  off.follow, off.crop, off.move = spec.follow, spec.crop, spec.move
  off.insets, off.hide = spec.insets, spec.hide
  off.moveVersion = state.moveVersion
  state.benchOff = off
end

-- Written at every phase change too, so a run cut short (map closed, too
-- little dragging) still leaves what it measured; `complete` tells them apart.
local function Save(complete)
  local result = { phases = {}, still = Summary(bench.still), context = bench.context,
                   phaseFrames = PHASE_FRAMES, rounds = ROUNDS,
                   complete = complete and true or false,
                   round = bench.round, phase = PHASES[bench.phase].name }
  local i
  for i = 1, table.getn(PHASES) do
    result.phases[PHASES[i].name] = Summary(bench.stats[PHASES[i].name])
  end
  if type(date) == "function" then
    local ok, stamp = pcall(date, "%Y-%m-%d %H:%M:%S")
    if ok then result.savedAt = stamp end
  end
  if type(unrealMapDB) ~= "table" then unrealMapDB = {} end
  if type(unrealMapDB.diag) ~= "table" then unrealMapDB.diag = {} end
  unrealMapDB.diag.zoomBench = result
end

local function Stop(complete)
  if bench.stats then Save(complete) end
  state.benchOff = nil
  bench.armed = false
  bench.stats, bench.still = nil, nil
end

-- Map tick, before this frame's drag step: the delta since the last tick is
-- the length of the frame that ran the previous step, so it is charged to
-- that step's kind.
function W.BenchTick(now)
  if not bench.armed then return end
  local last = bench.lastNow
  bench.lastNow = now
  local kind = bench.kind
  if state.dragMoved then
    bench.kind = "drag"
  elseif not state.down and not state.gliding and state.zoom == state.targetZoom then
    bench.kind = "still"
  else
    bench.kind = nil
  end
  if not last or not kind then return end
  local ms = (now - last) * 1000
  -- A gap longer than this is the map having been closed, not a frame.
  if ms <= 0 or ms > 1000 then return end
  if kind == "still" then
    Charge(bench.still, ms)
    return
  end
  if not bench.context then bench.context = Context() end
  if bench.settle > 0 then
    bench.settle = bench.settle - 1
    return
  end
  Charge(bench.stats[PHASES[bench.phase].name], ms)
  bench.counted = bench.counted + 1
  if bench.counted < PHASE_FRAMES then return end
  if bench.phase < table.getn(PHASES) then
    Save(false)
    SetPhase(bench.phase + 1)
  elseif bench.round < ROUNDS then
    Save(false)
    bench.round = bench.round + 1
    SetPhase(1)
  else
    Stop(true)
  end
end

-- /umap bench [off]. Returns the locale key to print.
function W.BenchCommand(value)
  if value == "off" then
    Stop(false)
    return "BENCH_STOPPED"
  end
  bench.armed = true
  bench.lastNow, bench.kind, bench.context = nil, nil, nil
  bench.stats, bench.still = {}, NewStat()
  local i
  for i = 1, table.getn(PHASES) do bench.stats[PHASES[i].name] = NewStat() end
  bench.off = bench.off or {}
  bench.round = 1
  SetPhase(1)
  return "BENCH_ARMED"
end
