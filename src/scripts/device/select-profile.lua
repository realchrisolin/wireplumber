-- WirePlumber
--
-- Copyright © 2022 Collabora Ltd.
--
-- SPDX-License-Identifier: MIT

-- raise select-profile events when devices are added or their profiles change.

cutils = require ("common-utils")
log = Log.open_topic ("s-device")

SimpleEventHook {
  name = "device/select-profile-on-device-added",
  interests = {
    EventInterest {
      Constraint { "event.type", "=", "device-added" },
    },
  },
  execute = function (event)
    local source = event:get_source ()
    local device = event:get_subject ()
    source:call ("push-event", "select-profile", device, nil)
  end
}:register()

SimpleEventHook {
  name = "device/select-profile-on-device-enumprofile-changed",
  interests = {
    EventInterest {
      Constraint { "event.type", "=", "device-params-changed" },
      Constraint { "event.subject.param-id", "=", "EnumProfile" },
    },
  },
  execute = function (event)
    local device = event:get_subject ()
    if device.properties ["device.api"] == "bluez5" and
        Settings.get_boolean ("bluetooth.autoswitch-to-headset-profile") then
      return
    end

    local source = event:get_source ()
    source:call ("push-event", "select-profile", device, nil)
  end
}:register()

-- HDMI/DP jack availability often updates EnumRoute without EnumProfile.
-- Re-run profile selection so restore can skip a stored analog-only profile
-- when a richer analog+HDMI profile is available. apply-profile no-ops if
-- the selected index is unchanged.
SimpleEventHook {
  name = "device/select-profile-on-device-enumroute-changed",
  interests = {
    EventInterest {
      Constraint { "event.type", "=", "device-params-changed" },
      Constraint { "event.subject.param-id", "=", "EnumRoute" },
    },
  },
  execute = function (event)
    if not Settings.get_boolean ("device.restore-profile.follow-best") then
      return
    end
    local device = event:get_subject ()
    if device.properties ["device.api"] ~= "alsa" then
      return
    end
    local source = event:get_source ()
    source:call ("push-event", "select-profile", device, nil)
  end
}:register()

Settings.subscribe ("bluetooth.profile-preference", function ()
  source = source or Plugin.find ("standard-event-source")
  local device_om = source:call ("get-object-manager", "device")
  for device in device_om:iterate () do
    source:call ("push-event", "select-profile", device, nil)
  end
end)

Settings.subscribe ("device.restore-profile.follow-best", function ()
  source = source or Plugin.find ("standard-event-source")
  local device_om = source:call ("get-object-manager", "device")
  for device in device_om:iterate () do
    if device.properties ["device.api"] == "alsa" then
      source:call ("push-event", "select-profile", device, nil)
    end
  end
end)
