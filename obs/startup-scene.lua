-- startup-scene.lua — open a scene collection on a fixed scene (and optionally start
-- the Virtual Camera). OBS normally reopens on whatever scene was live when you quit.
-- Each collection keeps its own settings: Tools → Scripts → startup-scene.lua.
obs = obslua

local scene_name = "2 · Talking Head"
local start_virtualcam = false

local function on_startup()
  obs.timer_remove(on_startup)                 -- run once
  local src = obs.obs_get_source_by_name(scene_name)
  if src == nil then
    obs.script_log(obs.LOG_WARNING, "scene not found: " .. scene_name)
  else
    obs.obs_frontend_set_current_scene(src)
    obs.obs_source_release(src)
    obs.script_log(obs.LOG_INFO, "opened on " .. scene_name)
  end
  if start_virtualcam and not obs.obs_frontend_virtualcam_active() then
    obs.obs_frontend_start_virtualcam()
    obs.script_log(obs.LOG_INFO, "started virtual camera")
  end
end

function script_description()
  return "Opens this scene collection on a chosen scene at startup, and can start the Virtual Camera for Meet / Zoom."
end

function script_properties()
  local p = obs.obs_properties_create()
  obs.obs_properties_add_text(p, "scene", "Scene to open", obs.OBS_TEXT_DEFAULT)
  obs.obs_properties_add_bool(p, "start_virtualcam", "Start Virtual Camera on launch")
  return p
end

function script_defaults(settings)
  obs.obs_data_set_default_string(settings, "scene", "2 · Talking Head")
  obs.obs_data_set_default_bool(settings, "start_virtualcam", false)
end

function script_update(settings)
  scene_name = obs.obs_data_get_string(settings, "scene")
  start_virtualcam = obs.obs_data_get_bool(settings, "start_virtualcam")
end

function script_load(settings)
  script_update(settings)
  -- Wait a moment so the frontend has finished loading the collection.
  obs.timer_add(on_startup, 1000)
end
