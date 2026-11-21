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

-- ── Phone remote (tools/remote/server.py) ───────────────────
local phone_remote = false
local remote_port = 8777
local last_seq = -1
local remote_ticks = 0

local function json_str(v)
  return '"' .. tostring(v):gsub('\\', '\\\\'):gsub('"', '\\"'):gsub('\n', ' ') .. '"'
end

local function read_cmd()
  local data = obs.obs_data_create_from_json_file(root .. "/state/remote-cmd.json")
  if data == nil then return 0, "" end
  local seq, scene = obs.obs_data_get_int(data, "seq"), obs.obs_data_get_string(data, "scene")
  obs.obs_data_release(data)
  return seq, scene
end

local function write_obs_info()
  local names = obs.obs_frontend_get_scene_names() or {}
  local parts = {}
  for _, n in ipairs(names) do parts[#parts + 1] = json_str(n) end
  local body = '{"scene":' .. json_str(current_scene_name()) .. ',"scenes":[' .. table.concat(parts, ",")
            .. '],"at":' .. string.format("%d", os.time() * 1000) .. '}'
  local tmp = root .. "/state/.obs.json.tmp"
  local f = io.open(tmp, "w")
  if f == nil then return end
  f:write(body); f:close()
  os.rename(tmp, root .. "/state/obs.json")
end

local function tick_remote()
  local seq, scene = read_cmd()
  if seq > last_seq then
    last_seq = seq
    if scene ~= "" and scene ~= current_scene_name() and switch_to(scene) then log("phone remote → " .. scene) end
  end
  remote_ticks = remote_ticks + 1
  if remote_ticks % 2 == 0 then write_obs_info() end   -- every second
end

local function start_remote()
  os.execute('mkdir -p "' .. root .. '/state"')
  last_seq = read_cmd()                                  -- ignore commands from before this launch
  -- Starts the server unless one is already listening on the port
  os.execute('/usr/sbin/lsof -nP -iTCP:' .. remote_port .. ' -sTCP:LISTEN >/dev/null 2>&1 || '
    .. '(cd "' .. root .. '" && nohup /usr/bin/python3 tools/remote/server.py --port ' .. remote_port
    .. ' >/dev/null 2>&1 &)')
  write_obs_info()
  obs.timer_add(tick_remote, 500)
  log("phone remote on port " .. remote_port)
end

local function stop_remote()
  obs.timer_remove(tick_remote)
  local f = io.open(root .. "/state/remote-server-" .. remote_port .. ".pid", "r")
  if f then
    local pid = tonumber(f:read("*l") or "")
    f:close()
    if pid then os.execute("kill " .. pid .. " >/dev/null 2>&1") end
  end
end

-- ── Meeting hotkeys (work while Zoom / Meet / Teams has focus) ──
-- Bindings live in OBS Settings → Hotkeys ("Meeting: …"); the Meetings collection ships defaults.
-- They run through the phone remote's server so the phone, dock and overlays stay in sync.
local HOTKEYS = {
  { name = "obskit.brb",   desc = "Meeting: Be right back (5 min)",  action = "brb",   minutes = 5 },
  { name = "obskit.back",  desc = "Meeting: I'm back (camera)",      action = "back" },
  { name = "obskit.soon",  desc = "Meeting: Starting soon (3 min)",  action = "soon",  minutes = 3 },
  { name = "obskit.next",  desc = "Meeting: Next agenda item",       action = "next" },
  { name = "obskit.prev",  desc = "Meeting: Previous agenda item",   action = "prev" },
  { name = "obskit.clear", desc = "Meeting: Clear agenda bar",       action = "clear" },
  { name = "obskit.reload", desc = "Meeting: Refresh overlays",      action = "reload" },
}
local hotkey_ids = {}

local function post_action(action, minutes)
  if not phone_remote then log("meeting hotkeys need 'Phone remote' turned on"); return end
  local body = '{"action":"' .. action .. '"' .. (minutes and (',"minutes":' .. minutes) or '') .. '}'
  os.execute("/usr/bin/curl -s -m 3 -X POST -H 'Content-Type: text/plain' -d '" .. body
    .. "' http://127.0.0.1:" .. remote_port .. "/local/action >/dev/null 2>&1 &")
  log("hotkey → " .. action)
end

local function register_hotkeys(settings)
  for _, h in ipairs(HOTKEYS) do
    local id = obs.obs_hotkey_register_frontend(h.name, h.desc, function(pressed)
      if pressed then post_action(h.action, h.minutes) end
    end)
    hotkey_ids[h.name] = id
    local arr = obs.obs_data_get_array(settings, h.name)
    obs.obs_hotkey_load(id, arr)
    obs.obs_data_array_release(arr)
  end
end

function script_save(settings)
  for name, id in pairs(hotkey_ids) do
    local arr = obs.obs_hotkey_save(id)
    obs.obs_data_set_array(settings, name, arr)
    obs.obs_data_array_release(arr)
  end
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
  if phone_remote then start_remote() end
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
  obs.obs_properties_add_bool(p, "phone_remote", "Phone remote (control overlays and scenes from your phone)")
  obs.obs_properties_add_int(p, "remote_port", "Phone remote port", 1024, 65535, 1)
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
  obs.obs_data_set_default_bool(settings, "phone_remote", false)
  obs.obs_data_set_default_int(settings, "remote_port", 8777)
end

function script_update(settings)
  scene_name = obs.obs_data_get_string(settings, "scene")
  start_virtualcam = obs.obs_data_get_bool(settings, "start_virtualcam")
  cal_autopilot = obs.obs_data_get_bool(settings, "calendar_autopilot")
  cal_switch = obs.obs_data_get_bool(settings, "calendar_switch")
  lead_minutes = obs.obs_data_get_int(settings, "lead_minutes")
  cam_scene = obs.obs_data_get_string(settings, "cam_scene")
  soon_scene = obs.obs_data_get_string(settings, "soon_scene")
  phone_remote = obs.obs_data_get_bool(settings, "phone_remote")
  remote_port = obs.obs_data_get_int(settings, "remote_port")
end

function script_load(settings)
  root = script_path():gsub("/obs/?$", ""):gsub("/$", "")
  script_update(settings)
  register_hotkeys(settings)
  -- Wait a moment so the frontend has finished loading the collection.
  obs.timer_add(on_startup, 1000)
end

function script_unload()
  obs.timer_remove(tick_refresh)
  obs.timer_remove(tick_check)
  if phone_remote then stop_remote() end
end
