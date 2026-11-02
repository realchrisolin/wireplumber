-- WirePlumber
--
-- SPDX-License-Identifier: MIT
--
-- If a stored analog-only profile is selected but analog+HDMI is available,
-- drop the stored choice so find-best-profile can pick the dual profile.
-- Does not persist the upgrade (apply-profile does not set save).
-- Does not override device.profile, pro-audio, off, or HDMI-only.

cutils = require ("common-utils")
log = Log.open_topic ("s-device")

local function has_part (name, part)
  for p in string.gmatch (name, "[^+]+") do
    if p == part then
      return true
    end
  end
  return false
end

local function is_analog_only_output (name)
  return has_part (name, "output:analog-stereo")
      and not has_part (name, "output:hdmi-stereo")
end

local function is_analog_plus_hdmi (name)
  return has_part (name, "output:analog-stereo")
      and has_part (name, "output:hdmi-stereo")
end

local function dual_available (device)
  for p in device:iterate_params ("EnumProfile") do
    local profile = cutils.parseParam (p, "EnumProfile")
    if profile and is_analog_plus_hdmi (profile.name)
        and profile.available ~= "no" then
      return true
    end
  end
  return false
end

local function prefer_enabled ()
  local v = Settings.get_boolean ("device.profile.prefer-analog-plus-hdmi")
  if v == false then
    return false
  end
  return true
end

SimpleEventHook {
  name = "device/prefer-analog-plus-hdmi",
  after = "device/find-stored-profile",
  before = { "device/find-preferred-profile", "device/find-best-profile" },
  interests = {
    EventInterest {
      Constraint { "event.type", "=", "select-profile" },
    },
  },
  execute = function (event)
    if not prefer_enabled () then
      return
    end

    local device = event:get_subject ()
    if device.properties ["device.api"] ~= "alsa" then
      return
    end
    if device.properties ["device.profile"] then
      return
    end

    local selected = event:get_data ("selected-profile")
    if not selected or not is_analog_only_output (selected.name) then
      return
    end

    if not dual_available (device) then
      return
    end

    log:info (device, string.format (
        "Ignoring stored analog-only profile '%s' on %s; analog+hdmi is available",
        selected.name, device.properties ["device.name"] or ""))
    event:set_data ("selected-profile", nil)
  end
}:register ()

SimpleEventHook {
  name = "device/prefer-analog-plus-hdmi-on-route-changed",
  interests = {
    EventInterest {
      Constraint { "event.type", "=", "device-params-changed" },
      Constraint { "event.subject.param-id", "=", "EnumRoute" },
    },
  },
  execute = function (event)
    if not prefer_enabled () then
      return
    end
    local device = event:get_subject ()
    if device.properties ["device.api"] ~= "alsa" then
      return
    end
    local source = event:get_source ()
    source:call ("push-event", "select-profile", device, nil)
  end
}:register ()
