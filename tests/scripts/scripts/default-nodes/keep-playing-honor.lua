-- analog is running as the applied default. A later
-- default.configured.audio.sink write (wpctl) must still win.

local tu = require ("test-utils")

Script.async_activation = true

assert (Settings.set ("node.keep-playing-default", Json.Boolean (true)))

tu.createDeviceNode ("analog-sink", "Audio/Sink", {
  ["priority.session"] = "1000",
})
tu.createDeviceNode ("hdmi-sink", "Audio/Sink", {
  ["priority.session"] = "100",
})

local stream_started = false

local function appliedSink ()
  local obj = tu.default_metadata:find (0, "default.audio.sink")
  if not obj then
    return nil
  end
  return Json.Raw (obj):parse ().name
end

SimpleEventHook {
  name = "linkable-added@test-keep-playing-honor",
  after = "linkable-added@test-utils-linking",
  interests = {
    EventInterest {
      Constraint { "event.type", "=", "session-item-added" },
      Constraint { "event.session-item.interface", "=", "linkable" },
    },
  },
  execute = function (event)
    if tu.linkablesReady () and not stream_started then
      stream_started = true
      tu.default_metadata:set (0, "default.configured.audio.sink",
          "Spa:String:JSON", Json.Object { ["name"] = "analog-sink" }:to_string ())
      tu.createStreamNode ("playback")
    end
  end
}:register ()

SimpleEventHook {
  name = "node-state@test-keep-playing-honor",
  interests = {
    EventInterest {
      Constraint { "event.type", "=", "node-state-changed" },
      Constraint { "node.name", "=", "analog-sink" },
    },
  },
  execute = function (event)
    local new_state = event:get_properties () ["event.subject.new-state"]
    if new_state ~= "running" then
      return
    end
    tu.default_metadata:set (0, "default.configured.audio.sink",
        "Spa:String:JSON", Json.Object { ["name"] = "hdmi-sink" }:to_string ())
    Core.timeout_add (400, function ()
      assert (appliedSink () == "hdmi-sink")
      Script:finish_activation ()
      return false
    end)
  end
}:register ()
