--
-- obsession.lua
--

local _M = {
    NAME = ...,
    VERSION = "2025.02.24",
    AUTHOR = "AK Booer",
    DESCRIPTION = "observations and sessions database manager",
  }

-- 2025.01.12  Version 0
-- 2025.01.20  separate title line
-- 2024.02.24  add tally of unique object names


local _log = require "logger" (_M)

local json = require "lib.json"
local utils = require "utils"

local newTimer = utils.newTimer
local formatSeconds = utils.formatSeconds

local love = _G.love
local lf = love.filesystem

-----

local Nsess = 0

local tally = {}          -- {name = count, name2 = count2, ...},   used by observing list

local observations = {
      titles = {"Object", "Session", "Telescope", "Notes"} ,  -- , "Path"}
      tally = tally, 
    }


_M.cols = {
        {"Name",      w = 200, },
        {"OT",        w =  40, },
        {"Con",       w =  50, },
        {"Session",   w =  90, align = "center", },
        {'Time',      w =  50, align = "center", },
        {"Frames",    w =  40, align = "center", type = "number", label = 'N'},
        {"Expo",      w =  70, align = "center", type = "number", format = formatSeconds, },
        {"Filts",     w =  60, },
        {"Size",      w = 100, align = "center", },
        {"Telescope", w = 200, },
        {"Notes",     w = 300, },
        {"Path",      w = 300, },   -- not shown on screen
      }
      
_M.col_index = {1, --[[2,3,]] 4,5,6,7, --[[8,]] 9, 10, 11}

-------------------------
--
-- LOADER
--

function _M.load()
  
  if #observations > 0 then return observations end
  
  local sess_path = "sessions/"
  local tally = tally
  local elapsed = newTimer()
  local sessions = lf.getDirectoryItems(sess_path)
  --
  -- for each session
  --
  for _, filename in ipairs(sessions) do
    local sess_name = filename: match "(%d+)%.json$"
    if sess_name then
      local session = json.read (sess_path .. filename)
      Nsess = Nsess + 1
      --
      -- for each observation
      --
      for folder, obs in pairs(session.observations) do
        local name = obs.object or '?'
        tally[name] = (tally[name] or 0) + 1
        observations[#observations + 1] = {
            name, 
            'ot',
            'con',
            sess_name,
            obs.time or '',
            obs.frames or '',     -- number of frames
            obs.exposure or '',
            'filt',
            obs.size,
            obs.telescope or '', 
            obs.notes or '',
            folder,
          }
      end
    end
  end
  
  local Nobs = #observations
  for _ in pairs(tally) do
    Nobs = Nobs + 1
  end
  tally.n = Nobs
    
  _log(elapsed("%.3f ms, loaded %d observations from %d sessions", Nobs, Nsess))
  return observations
end


-------------------------------
--
-- SAVE/LOAD SESSION 
--

local info    -- current session

local function sessionID(epoch)
  return os.date("%Y%m%d", epoch)   -- YYYYMMDD
end


-- construct session and observation IDs and info
local function getInfo(stack)
  local sesID = sessionID(stack.epoch)            -- use observation date as session ID
  local obsID = stack.folder                      -- use observation folder as observation ID
  local path = "sessions/%s.json" % sesID                  -- create path for meta file
  return sesID, obsID, path
end

local function non_blank(text)
  return #text > 0 and text or nil
end


function _M.saveSession(stack, controls)
  
  if not stack then return end
  local sesID, obsID, path = getInfo(stack)
  
  -- update info from controls
  info.session.notes = non_blank(controls.ses_notes.text)
  local obs = info.observations[obsID or '']
  obs.object = non_blank(controls.object.text)
--  controls.object.cursor = 1                  -- put the cursor at the start (looks better)
  obs.notes = non_blank(controls.obs_notes.text)
  obs.flipUD = controls.flipUD.checked or nil
  obs.flipLR = controls.flipLR.checked or nil
  obs.time = os.date("%H:%M", stack.epoch)
  obs.frames = stack.subs and #stack.subs or 0
  obs.exposure = stack.subs and stack.exposure / #stack.subs or 0   -- AVERAGE exposure per sub (seconds)
  obs.size = "%dx%d" % {stack.image: getDimensions()}
  obs.rotate = controls.rotate.value ~= 0 and tonumber("%f.3" % controls.rotate.value) or nil
  obs.telescope = non_blank(controls.telescope.text)
  info.observations[obsID] = obs
  
  -- write file
  json.write(path,  info)
  info = nil
end


function _M.loadSession(stack, controls)
  
  if not stack then return end

  local sesID, obsID, path = getInfo(stack)
  info = json.read(path) or {}
  info.session = {ID = sesID}
  
  -- update controls from metadata
  local obs = info.observations or {}
  local thisObs = obs[obsID] or {}
  obs[obsID]= thisObs
  info.observations = obs

  -- scale pixel size by binning
  local pix do
    pix = stack.keywords.XPIXSZ
    if pix then
      local bin = stack.keywords.XBINNING or 1
      pix = pix * bin
    end
    pix = tostring(pix or '')
  end
  
  local scope = stack.telescope or thisObs.telescope or ''

  controls.object.text    = stack.object or thisObs.object or ''
  controls.telescope.text = scope
  controls.pixelsize.text = pix
  controls.ses_notes.text = info.session.notes or ''
  controls.obs_notes.text = thisObs.notes or ''
  controls.flipUD.checked = thisObs.flipUD or false
  controls.flipLR.checked = thisObs.flipLR or false
  controls.rotate.value   = thisObs.rotate or 0
  controls.X, controls.Y = 0, 0
  return info
end

return _M

-----
