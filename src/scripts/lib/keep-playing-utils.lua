-- WirePlumber
--
-- SPDX-License-Identifier: MIT

-- Predicates for node.keep-playing-default.

local u = {}

function u.shouldHonorUserDefault (pending, selected)
  return pending ~= nil and selected == pending
end

function u.shouldHoldPlayingDefault (is_playing, current, selected)
  return is_playing and current ~= nil and selected ~= nil
      and selected ~= current
end

-- Writes that happen while default-nodes/metadata-added is running are
-- restore from the state file. Later writes are wpctl / the audio panel.
function u.noteConfiguredWrite (restoring, name)
  if restoring then
    return nil
  end
  return name
end

local OUTPUT_PREFIX = "output:"

-- mapping is device.profile.name (e.g. analog-stereo). Match a whole ACP
-- part, not a substring of another mapping.
function u.profileHasMapping (profile_name, mapping)
  if not profile_name or not mapping or mapping == "" then
    return false
  end
  local output = OUTPUT_PREFIX .. mapping
  for part in string.gmatch (profile_name, "[^+]+") do
    if part == mapping or part == output then
      return true
    end
  end
  return false
end

return u
