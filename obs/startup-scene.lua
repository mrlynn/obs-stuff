-- startup-scene.lua — per scene collection:
--   • open on a chosen scene at launch (OBS normally reopens on the last scene used)
--   • optionally start the Virtual Camera for Meet / Zoom / Teams
--   • Calendar autopilot: refresh your meetings every minute (tools/calendar), switch to the
--     "Starting soon" scene a few minutes before each meeting and back to your camera at the start
-- Settings: Tools → Scripts → startup-scene.lua (each collection keeps its own).
obs = obslua

local scene_name = "2 · Talking Head"
local start_virtualcam = false
local cal_autopilot = false
local cal_switch = true
local lead_minutes = 3
local cam_scene = "M1 · Cam"
local soon_scene = "M3 · Starting Soon"

local root = ""                -- repo root (parent of obs/)
local switched_for = {}        -- meeting id → "soon" | "back"

local function log(msg) obs.script_log(obs.LOG_INFO, msg) end

local function current_scene_name()
  local src = obs.obs_frontend_get_current_scene()
  if src == nil then return "" end
  local n = obs.obs_source_get_name(src)
  obs.obs_source_release(src)
  return n
end

local function switch_to(name)
  local src = obs.obs_get_source_by_name(name)
  if src == nil then log("scene not found: " .. name); return false end
  obs.obs_frontend_set_current_scene(src)
  obs.obs_source_release(src)
  return true
end

-- ── Calendar autopilot ──────────────────────────────────────
local function refresh_calendar()
  local app = root .. "/tools/calendar/build/ObsKit Calendar.app"
  local f = io.open(app .. "/Contents/MacOS/obskit-calendar", "r")
  if f == nil then return end                      -- not built yet: tools/calendar/build.sh --run
  f:close()
  -- Runs in the background (open returns at once); writes state/calendar.json + .js
  os.execute('/usr/bin/open -n -g -j "' .. app .. '" --args --out "' .. root .. '/state" >/dev/null 2>&1 &')
end

local function check_calendar()
  if not cal_switch then return end
  local data = obs.obs_data_create_from_json_file(root .. "/state/calendar.json")
  if data == nil then return end
  if obs.obs_data_get_string(data, "status") ~= "ok" then obs.obs_data_release(data); return end
  local now = os.time() * 1000
  local arr = obs.obs_data_get_array(data, "events")
  local n = obs.obs_data_array_count(arr)
  local here = current_scene_name()
  for i = 0, n - 1 do
    local ev = obs.obs_data_array_item(arr, i)
    local id = obs.obs_data_get_string(ev, "id")
    local start = obs.obs_data_get_int(ev, "start")
    obs.obs_data_release(ev)
    local lead = lead_minutes * 60 * 1000
    if now >= start - lead and now < start and switched_for[id] == nil and here == cam_scene then
      if switch_to(soon_scene) then
        switched_for[id] = "soon"
        log("autopilot: meeting starts in " .. math.ceil((start - now) / 60000) .. " min → " .. soon_scene)
      end
    elseif now >= start and now < start + 10 * 60 * 1000 and switched_for[id] == "soon" then
      switched_for[id] = "back"
      if here == soon_scene and switch_to(cam_scene) then
        log("autopilot: meeting started → " .. cam_scene)
      end
    end
  end
  obs.obs_data_array_release(arr)
  obs.obs_data_release(data)
end

local function tick_refresh() refresh_calendar() end
local function tick_check() check_calendar() end

-- ── Startup ─────────────────────────────────────────────────
local function on_startup()
  obs.timer_remove(on_startup)                 -- run once
  if scene_name ~= "" and switch_to(scene_name) then log("opened on " .. scene_name) end
  if start_virtualcam and not obs.obs_frontend_virtualcam_active() then
    obs.obs_frontend_start_virtualcam()
    log("started virtual camera")
  end
  if cal_autopilot then
    refresh_calendar()
    obs.timer_add(tick_refresh, 60 * 1000)
    obs.timer_add(tick_check, 10 * 1000)
    log("calendar autopilot on (switch " .. (cal_switch and ("on, " .. lead_minutes .. " min before") or "off") .. ")")
  end
end

function script_description()
  return "Opens this collection on a chosen scene, can start the Virtual Camera, and can follow your calendar: "
      .. "'Starting soon' a few minutes before each meeting, then back to your camera."
end

function script_properties()
  local p = obs.obs_properties_create()
  obs.obs_properties_add_text(p, "scene", "Scene to open", obs.OBS_TEXT_DEFAULT)
  obs.obs_properties_add_bool(p, "start_virtualcam", "Start Virtual Camera on launch")
  obs.obs_properties_add_bool(p, "calendar_autopilot", "Calendar autopilot (refresh meetings every minute)")
  obs.obs_properties_add_bool(p, "calendar_switch", "Switch scenes around meetings")
  obs.obs_properties_add_int(p, "lead_minutes", "Show 'Starting soon' this many minutes before", 0, 30, 1)
  obs.obs_properties_add_text(p, "cam_scene", "Camera scene", obs.OBS_TEXT_DEFAULT)
  obs.obs_properties_add_text(p, "soon_scene", "Starting-soon scene", obs.OBS_TEXT_DEFAULT)
  return p
end

function script_defaults(settings)
  obs.obs_data_set_default_string(settings, "scene", "2 · Talking Head")
  obs.obs_data_set_default_bool(settings, "start_virtualcam", false)
  obs.obs_data_set_default_bool(settings, "calendar_autopilot", false)
  obs.obs_data_set_default_bool(settings, "calendar_switch", true)
  obs.obs_data_set_default_int(settings, "lead_minutes", 3)
  obs.obs_data_set_default_string(settings, "cam_scene", "M1 · Cam")
  obs.obs_data_set_default_string(settings, "soon_scene", "M3 · Starting Soon")
end

function script_update(settings)
  scene_name = obs.obs_data_get_string(settings, "scene")
  start_virtualcam = obs.obs_data_get_bool(settings, "start_virtualcam")
  cal_autopilot = obs.obs_data_get_bool(settings, "calendar_autopilot")
  cal_switch = obs.obs_data_get_bool(settings, "calendar_switch")
  lead_minutes = obs.obs_data_get_int(settings, "lead_minutes")
  cam_scene = obs.obs_data_get_string(settings, "cam_scene")
  soon_scene = obs.obs_data_get_string(settings, "soon_scene")
end

function script_load(settings)
  root = script_path():gsub("/obs/?$", ""):gsub("/$", "")
  script_update(settings)
  -- Wait a moment so the frontend has finished loading the collection.
  obs.timer_add(on_startup, 1000)
end

function script_unload()
  obs.timer_remove(tick_refresh)
  obs.timer_remove(tick_check)
end
