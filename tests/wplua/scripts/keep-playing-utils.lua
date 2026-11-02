-- WirePlumber
--
-- SPDX-License-Identifier: MIT

kputils = require ("keep-playing-utils")

assert (not kputils.shouldHonorUserDefault (nil, "hdmi"))
assert (not kputils.shouldHonorUserDefault ("hdmi", "analog"))
assert (kputils.shouldHonorUserDefault ("hdmi", "hdmi"))

assert (not kputils.shouldHoldPlayingDefault (false, "analog", "hdmi"))
assert (not kputils.shouldHoldPlayingDefault (true, "analog", "analog"))
assert (kputils.shouldHoldPlayingDefault (true, "analog", "hdmi"))

assert (kputils.noteConfiguredWrite (true, "hdmi") == nil)
assert (kputils.noteConfiguredWrite (false, "hdmi") == "hdmi")
assert (kputils.noteConfiguredWrite (false, "analog") == "analog")
assert (kputils.noteConfiguredWrite (false, nil) == nil)

local ANALOG = "output:analog-stereo+input:analog-stereo"
local DUAL = "output:analog-stereo+output:hdmi-stereo+input:analog-stereo"
local HDMI = "output:hdmi-stereo+input:analog-stereo"

assert (kputils.profileHasMapping (DUAL, "analog-stereo"))
assert (kputils.profileHasMapping (DUAL, "hdmi-stereo"))
assert (not kputils.profileHasMapping (HDMI, "analog-stereo"))
assert (not kputils.profileHasMapping (ANALOG, "hdmi"))
assert (kputils.profileHasMapping ("output:analog-stereo", "analog-stereo"))
