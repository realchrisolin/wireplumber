-- WirePlumber
--
-- SPDX-License-Identifier: MIT

-- Hold the ALSA profile while a sink on that card is playing, except when
-- the selected profile offers the current mappings plus an extra output
-- (analog-only -> analog+HDMI). MPRIS pause on analog PCM recreate is
-- skipped in mpris-pause.lua.

cutils = require ("common-utils")
kputils = require ("keep-playing-utils")
log = Log.open_topic ("s-device")

-- bound-id -> true when we held a profile; idle then re-runs select-profile
local held_device = {}

local function currentProfile (device)
  local current = nil
  for p in device:iterate_params ("Profile") do
    local profile = cutils.parseParam (p, "Profile")
    if profile then
      current = profile
    end
  end
  return current
end

local function deviceHasRunningSink (source, device)
  local node_om = source:call ("get-object-manager", "node")
  local bound_id = device ["bound-id"]
  if not bound_id then
    return false
  end
  for node in node_om:iterate {
      Constraint { "media.class", "matches", "Audio/Sink", type = "pw-global" },
      Constraint { "device.id", "=", bound_id, type = "pw-global" },
  } do
    if node ["state"] == "running" then
      return true
    end
  end
  return false
end

SimpleEventHook {
  name = "device/keep-playing-profile",
  after = { "device/find-stored-profile",
            "device/find-preferred-profile",
            "device/find-best-profile" },
  before = "device/apply-profile",
  interests = {
    EventInterest {
      Constraint { "event.type", "=", "select-profile" },
    },
  },
  execute = function (event)
    if not Settings.get_boolean ("node.keep-playing-default") then
      return
    end

    local device = event:get_subject ()
    if device.properties ["device.api"] ~= "alsa" then
      return
    end

    local selected = event:get_data ("selected-profile")
    if not selected then
      return
    end

    local current = currentProfile (device)
    if not current or tonumber (current.index) == tonumber (selected.index) then
      return
    end

    if kputils.offersExtraOutput (selected.name, current.name) then
      return
    end

    local source = event:get_source ()
    if not deviceHasRunningSink (source, device) then
      return
    end

    log:info (device, string.format (
        "keeping profile '%s' (%d); a sink is playing (not '%s')",
        current.name, current.index, selected.name))
    held_device [tostring (device ["bound-id"])] = true
    event:set_data ("selected-profile", current)
  end
}:register ()

SimpleEventHook {
  name = "device/select-profile-when-sink-idle",
  interests = {
    EventInterest {
      Constraint { "event.type", "=", "node-state-changed" },
      Constraint { "media.class", "=", "Audio/Sink" },
      Constraint { "device.api", "=", "alsa" },
    },
  },
  execute = function (event)
    if not Settings.get_boolean ("node.keep-playing-default") then
      return
    end
    local new_state = event:get_properties () ["event.subject.new-state"]
    if new_state ~= "idle" and new_state ~= "suspended" then
      return
    end
    local node = event:get_subject ()
    local device_id = node.properties ["device.id"]
    if not device_id or not held_device [tostring (device_id)] then
      return
    end
    local source = event:get_source ()
    local devices_om = source:call ("get-object-manager", "device")
    local device = devices_om:lookup {
      Constraint { "bound-id", "=", device_id, type = "gobject" },
    }
    if device and device.properties ["device.api"] == "alsa" then
      held_device [tostring (device_id)] = nil
      source:call ("push-event", "select-profile", device, nil)
    end
  end
}:register ()
