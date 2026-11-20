-- startup-scene.lua — open the Social Media Kit on a fixed scene.
-- OBS normally reopens on whatever scene was live when you quit; this overrides that.
-- Loaded automatically by the "Social Media Kit" collection (Tools → Scripts to view/remove).
obs = obslua

local DEFAULT_SCENE = "2 · Talking Head"

local function switch_to_default()
  obs.timer_remove(switch_to_default)          -- run once
  local src = obs.obs_get_source_by_name(DEFAULT_SCENE)
  if src == nil then
    obs.script_log(obs.LOG_WARNING, "scene not found: " .. DEFAULT_SCENE)
    return
  end
  obs.obs_frontend_set_current_scene(src)
  obs.obs_source_release(src)
  obs.script_log(obs.LOG_INFO, "opened on " .. DEFAULT_SCENE)
end

function script_description()
  return "Opens the Social Media Kit on '" .. DEFAULT_SCENE .. "' at startup."
end

function script_load(settings)
  -- Wait a moment so the frontend has finished loading the collection.
  obs.timer_add(switch_to_default, 1000)
end
