-- WirePlumber

-- Copyright © 2026 Collabora Ltd.

-- SPDX-License-Identifier: MIT

-- Script is a Lua Module of utility functions for ranking device profiles

local putils = {}

local NO_ROUTES = { yes = 0, unknown = 0 }

-- Counts, for every profile index, the output routes that profile offers,
-- split by whether they are known to be available ("yes") or merely not known
-- to be unavailable ("unknown"). Routes that do not name the profiles they
-- belong to apply to every profile, so they cannot tell profiles apart and are
-- skipped; the same goes for input routes, whose availability says nothing
-- about where playback can go.
function putils.buildOutputRouteScores (routes)
  local scores = {}

  for _, route in ipairs (routes) do
    if route.direction == "Output" and route.profiles then
      local available = route.available or "unknown"

      for _, index in ipairs (route.profiles) do
        index = tonumber (index)
        local score = scores [index]

        if not score then
          score = { yes = 0, unknown = 0 }
          scores [index] = score
        end

        if available == "yes" then
          score.yes = score.yes + 1
        elseif available ~= "no" then
          score.unknown = score.unknown + 1
        end
      end
    end
  end

  return scores
end

-- Returns true if profile 'a' should be preferred over profile 'b'.
--
-- A profile's "available" flag is set if any single one of its routes is
-- available, which on cards that bundle HDMI outputs together with the
-- speakers or the headphones is true almost all the time. Ranking on the
-- priority number alone therefore keeps selecting profiles whose analog output
-- is not plugged in.
--
-- Compare first on how many output routes the profile can actually play on,
-- which is the test that decides whether a profile is available at all,
-- applied per profile and counted instead of OR'ed. Routes of unknown
-- availability have to count here: built-in speakers get no jack detection and
-- are never reported as available, so counting only the available ones would
-- rank a profile offering a connected monitor above the one offering the
-- speakers.
--
-- The priority breaks the tie, which keeps the behaviour unchanged for devices
-- that expose no per-profile route information, and the number of routes known
-- to be available breaks it further when the priorities are equal as well.
function putils.compareProfiles (a, b, scores)
  local sa = scores [tonumber (a.index)] or NO_ROUTES
  local sb = scores [tonumber (b.index)] or NO_ROUTES
  local usable_a = sa.yes + sa.unknown
  local usable_b = sb.yes + sb.unknown
  local priority_a = a.priority or 0
  local priority_b = b.priority or 0

  if usable_a ~= usable_b then
    return usable_a > usable_b
  elseif priority_a ~= priority_b then
    return priority_a > priority_b
  else
    return sa.yes > sb.yes
  end
end

local OUTPUT_PREFIX = "output:"
local OUTPUT_HDMI = "output:hdmi"
local OUTPUT_ANALOG = "output:analog"

-- ACP profile names are '+' joined mappings, e.g.
-- output:analog-stereo+output:hdmi-stereo+input:analog-stereo
local function splitProfileParts (name)
  local parts = {}
  local set = {}
  for part in string.gmatch (name or "", "[^+]+") do
    table.insert (parts, part)
    set [part] = true
  end
  return parts, set
end

local function hasOutputPrefix (name, prefix)
  for _, part in ipairs (splitProfileParts (name)) do
    if string.sub (part, 1, #prefix) == prefix then
      return true
    end
  end
  return false
end

-- Stored HDMI-only profiles are a deliberate TV / lid-closed choice.
-- Analog+HDMI also contains those HDMI mappings, so restore must keep
-- HDMI-only rather than following the best profile.
local function isHdmiOnlyOutput (name)
  return hasOutputPrefix (name, OUTPUT_HDMI)
      and not hasOutputPrefix (name, OUTPUT_ANALOG)
end

-- Returns true if the candidate ACP profile name contains every mapping in
-- the stored name and at least one extra output mapping. An extra input
-- mapping is not enough. Analog-only and HDMI-only do not contain each
-- other, so neither name follows the other here.
function putils.offersExtraOutput (candidate, stored)
  local candidate_parts, candidate_set = splitProfileParts (candidate)
  local _, stored_set = splitProfileParts (stored)
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

-- Returns true if restore should leave selected-profile unset so
-- find-best-profile can run. That is the device.restore-profile.follow-best
-- policy: an available profile that still offers the stored mappings, plus
-- extra outputs, and that compareProfiles ranks above the stored profile.
--
-- off and pro-audio match find-best-profile.lua, which keeps those names
-- out of the best-profile ranking. HDMI-only stays restored.
function putils.shouldFollowBestProfile (stored, candidates, scores)
  if not stored or stored.name == "off" or stored.name == "pro-audio"
      or isHdmiOnlyOutput (stored.name) then
    return false
  end

  for _, profile in ipairs (candidates) do
    if profile.available ~= "no"
        and putils.offersExtraOutput (profile.name, stored.name)
        and putils.compareProfiles (profile, stored, scores) then
      return true
    end
  end
  return false
end

return putils
