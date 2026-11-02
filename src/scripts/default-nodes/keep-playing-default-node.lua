-- WirePlumber
--
-- SPDX-License-Identifier: MIT

-- Keep the applied default sink while it is playing, except when the user
-- just chose a different default (wpctl set-default / the audio panel).
-- Restore and find-best may still switch when that sink is idle.

cutils = require ("common-utils")
kputils = require ("keep-playing-utils")
log = Log.open_topic ("s-default-nodes")

-- node.name -> true while that sink last reported state "running"
local playing = {}
-- ignore the first idle/suspended after a node-added (profile recreate)
local skip_idle_clear = {}
-- last seen ACP mapping (device.profile.name) and device.id for a sink
local sink_info = {}
-- node.name from a user default.configured.audio.sink write
local pending_user_sink = nil
local restoring_configured = false

local function parseDefaultName (metadata, def_node_type)
  if not metadata then
    return nil
  end
  local obj = metadata:find (0, "default." .. def_node_type)
  if not obj then
    return nil
  end
  local parsed = Json.Raw (obj):parse ()
  return parsed and parsed.name
end

local function availableHasName (available_nodes, name)
  for _, node_props in ipairs (available_nodes) do
    if node_props ["node.name"] == name then
      return true
    end
  end
  return false
end

local function deviceProfileHasMapping (device, mapping)
  if not device or not mapping then
    return false
  end
  for p in device:iterate_params ("Profile") do
    local profile = cutils.parseParam (p, "Profile")
    if profile and kputils.profileHasMapping (profile.name, mapping) then
      return true
    end
  end
  return false
end

local function shouldKeepPlaying (source, name, available_nodes)
  if not name or not playing [name] then
    return false
  end
  if availableHasName (available_nodes, name) then
    return true
  end

  -- Profile switch recreates the PCM; keep the name if the card still
  -- offers that mapping so find-best cannot pick a sibling HDMI sink.
  local info = sink_info [name]
  if not info or not info.device_id or not info.profile then
    return false
  end
  local devices_om = source:call ("get-object-manager", "device")
  local device = devices_om:lookup {
    Constraint { "bound-id", "=", info.device_id, type = "gobject" },
  }
  return deviceProfileHasMapping (device, info.profile)
end

SimpleEventHook {
  name = "default-nodes/keep-playing-default-node",
  after = { "default-nodes/find-selected-default-node",
            "default-nodes/find-stored-default-node",
            "default-nodes/find-best-default-node" },
  before = "default-nodes/apply-default-node",
  interests = {
    EventInterest {
      Constraint { "event.type", "=", "select-default-node" },
    },
  },
  execute = function (event)
    if not Settings.get_boolean ("node.keep-playing-default") then
      return
    end

    local props = event:get_properties ()
    local def_node_type = props ["default-node.type"]
    if def_node_type ~= "audio.sink" then
      return
    end

    local available_nodes = event:get_data ("available-nodes")
    available_nodes = available_nodes and available_nodes:parse ()
    if not available_nodes then
      return
    end

    local source = event:get_source ()
    local metadata_om = source:call ("get-object-manager", "metadata")
    local metadata = metadata_om:lookup {
      Constraint { "metadata.name", "=", "default" },
    }
    local current = parseDefaultName (metadata, def_node_type)
    if not current then
      return
    end

    local selected = event:get_data ("selected-node")
    if kputils.shouldHonorUserDefault (pending_user_sink, selected) then
      log:info ("honoring user default sink " .. selected)
      pending_user_sink = nil
      return
    end

    if not shouldKeepPlaying (source, current, available_nodes) then
      return
    end

    if not kputils.shouldHoldPlayingDefault (true, current, selected) then
      return
    end

    log:info ("keeping playing default sink " .. current
        .. " instead of " .. tostring (selected))
    event:set_data ("selected-node", current)
    event:set_data ("selected-node-priority", 40000)
  end
}:register ()

SimpleEventHook {
  name = "default-nodes/track-playing-sinks-on-added",
  interests = {
    EventInterest {
      Constraint { "event.type", "=", "node-added" },
      Constraint { "media.class", "=", "Audio/Sink" },
    },
  },
  execute = function (event)
    local node = event:get_subject ()
    local name = node.properties ["node.name"]
    if name then
      skip_idle_clear [name] = true
      sink_info [name] = {
        profile = node.properties ["device.profile.name"],
        device_id = node.properties ["device.id"],
      }
    end
  end
}:register ()

SimpleEventHook {
  name = "default-nodes/track-playing-sinks-on-state-changed",
  interests = {
    EventInterest {
      Constraint { "event.type", "=", "node-state-changed" },
      Constraint { "media.class", "=", "Audio/Sink" },
    },
  },
  execute = function (event)
    local node = event:get_subject ()
    local name = node.properties ["node.name"]
    if not name then
      return
    end
    local new_state = event:get_properties () ["event.subject.new-state"]
    sink_info [name] = {
      profile = node.properties ["device.profile.name"],
      device_id = node.properties ["device.id"],
    }
    if new_state == "running" then
      playing [name] = true
      skip_idle_clear [name] = false
    elseif new_state == "idle" or new_state == "suspended" then
      if skip_idle_clear [name] then
        return
      end
      playing [name] = nil
    end
  end
}:register ()

SimpleEventHook {
  name = "default-nodes/keep-playing-before-restore",
  before = "default-nodes/metadata-added",
  interests = {
    EventInterest {
      Constraint { "event.type", "=", "metadata-added" },
      Constraint { "metadata.name", "=", "default" },
    },
  },
  execute = function ()
    restoring_configured = true
  end
}:register ()

SimpleEventHook {
  name = "default-nodes/keep-playing-after-restore",
  after = "default-nodes/metadata-added",
  interests = {
    EventInterest {
      Constraint { "event.type", "=", "metadata-added" },
      Constraint { "metadata.name", "=", "default" },
    },
  },
  execute = function ()
    restoring_configured = false
  end
}:register ()

SimpleEventHook {
  name = "default-nodes/track-user-configured-default-sink",
  interests = {
    EventInterest {
      Constraint { "event.type", "=", "metadata-changed" },
      Constraint { "metadata.name", "=", "default" },
      Constraint { "event.subject.key", "=", "default.configured.audio.sink" },
    },
  },
  execute = function (event)
    local value = event:get_properties () ["event.subject.value"]
    local name = nil
    if value then
      local parsed = Json.Raw (value):parse ()
      name = parsed and parsed.name
    end
    pending_user_sink = kputils.noteConfiguredWrite (restoring_configured, name)
  end
}:register ()
