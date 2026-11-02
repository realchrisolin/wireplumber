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

function u.splitProfileParts (name)
  local parts = {}
  local set = {}
  for part in string.gmatch (name or "", "[^+]+") do
    table.insert (parts, part)
    set [part] = true
  end
  return parts, set
end

function u.offersExtraOutput (candidate, stored)
  local candidate_parts, candidate_set = u.splitProfileParts (candidate)
  local _, stored_set = u.splitProfileParts (stored)
  local stored_count = 0
  for part, _ in pairs (stored_set) do
    stored_count = stored_count + 1
    if not candidate_set [part] then
      return false
    end
  end
  if stored_count == 0 then
    return false
  end
  for _, part in ipairs (candidate_parts) do
    if not stored_set [part]
        and string.sub (part, 1, #OUTPUT_PREFIX) == OUTPUT_PREFIX then
      return true
    end
  end
  return false
end

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
