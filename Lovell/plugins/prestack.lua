--
-- prestack.lua
--

local _M = {
    NAME = ...,
    VERSION = "2026.11.09",
    AUTHOR = "AK Booer",
    DESCRIPTION = "PLUGIN – Prestack processing options",
  }

require "logger" (_M)

-- 2026.11.06  Version 0 (extracted from prestacking.lua)
-- 2026.11.08  added bespoke reset() function
-- 2026.11.09  use love.event rather than target and pager threads


local love = _G.love
local le = love.event

local BayerOptions    = require "shaders.debayer"   .BayerOptions


local plugin = {
    id = "Prestack",
    static = true,
    bayopt = {size = {100, 20}},
    do_dark   = {checked = true, default = true, text = "dark calibration"},
    do_flat   = {checked = true, default = true, text = "flat calibration"},
    badpixel  = {checked = true, default = true, text = "bad pixel removal"},
    badratio  = {id = "ratio", value = 2.5, default = 2.5, min = 1, max = 5, format = "%.1f", style = "inline" },
    bayer_opt = BayerOptions,
    
}

plugin.documentation = [[

View Masters displays the calibration database.

The Bayer Pattern dropdown overrides any setting from the FITS file headers.  Useful for capture software which doesn't include a definition in the headers.  Once set, this value is saved in the observation metadata, so that on subsequent reloads the Auto setting will work correctly.

The dark/flat checkboxes emable/disable that type of calibration processing, even if a matching master is found.

The bad pixel checkbox does the same for hot pixels. If the bad pixel threshold ratio slider is moved then the bad pixel option is deselected and should be manually checked to enable it again (avoids constant reprocessing as the slider is moved.)

Automatically reloads the stack if any of these prestack options (Bayer pattern / hot pixels / darks / flats / ...) are changed.  
 
]]

-- RESET

-- explicit reset function to ensure that RELOAD happens when plugin reset
function plugin: reset()
  self.do_dark.checked = self.do_dark.default
  self.do_flat.checked = self.do_flat.default
  self.badpixel.checked = self.badpixel.default
  self.badratio.value = self.badratio.default
  self.bayer_opt.value = self.bayer_opt.default
  le.push("target", "RELOAD")
end

-- RUN and DRAW methods


function plugin: run(workflow, frame, bayerpat)
  local ratio = self.badpixel.checked and self.badratio.value or 1e6   -- turn it on/off

  workflow: calibrate(frame, self.do_dark.checked, self.do_flat.checked)
  workflow: badpixel(bayerpat, ratio)           -- hot pixel removal is different if there's a Bayer matrix  
  workflow: debayer(bayerpat)                   -- debayer or replicate to R,G,B, and A channels
end

 
function plugin: draw(suit)  
  local sl = suit.layout
  local W, Hb = 180, 25
  if suit: Button("View Masters...", sl:row(W - 30, Hb)) .hit then 
    le.push ("page", "database, calibration")
  end 
  
  local hit = false
  hit = hit or suit: Choosable(self.bayer_opt, self.bayopt, sl:row(W, Hb)) .hit   -- narrow menu (short options)
  
  hit = hit or suit: Checkbox(self.do_dark, sl:row (W, 20)) .hit
  hit = hit or suit: Checkbox(self.do_flat, sl:row ()) .hit
  
  hit = hit or suit: Checkbox(self.badpixel, sl:row()) .hit
  
  if suit: Slideable(self.badratio, sl:row (W, 15)) .changed then
    self.badpixel.checked = false         -- turn off bad pixel option if we're changing the threshold
  end
  
  if hit then
    le.push ("target", "RELOAD")
  end
end


return plugin

-----

