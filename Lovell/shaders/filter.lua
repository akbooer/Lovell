--
-- filter – 
--

local _M = {
    NAME = ...,
    VERSION = "2025.05.14",
    AUTHOR = "AK Booer",
    DESCRIPTION = "sundry processing filters (BOX, TNR, APF, ...)",
  }

local _log = require "logger" (_M)

local moonbridge  = require "shaders.moonbridge"   -- Moonshine proxy

-- 2024.11.07  Version 0, @akbooer
-- 2024.12.09  use workflow() function to acquire buffers and control parameters

-- 2025.01.29  incorporate moonshine bridge shaders
-- 2025.03.21  use named buffers (possibly) in tnr() and apf()
-- 2025.05.14  consolidate apf() for different numbers of backgrounds into one single code


local love = _G.love
local lg = love.graphics


-------------------------------
--
-- GAUSSIAN, from Moonshine
--

local gaussian = {}        -- list of already built gaussians

function _M.gaussian(workflow, sigma)
  local gauss = gaussian[sigma]
  if not gauss then
    _log ("creating moonshine GaussianBlur shader, sigma = " .. sigma)
    gauss = moonbridge "gaussianblur"
    gauss.setters.sigma(sigma)
    gaussian[sigma] = gauss
  end
  
  gauss.filter(workflow)
end

-------------------------------
--
-- GAUSSIAN (fast), from Moonshine
--

local fastgaussian = {}        -- list of already built fast gaussians

function _M.fastgaussian(workflow, taps)
  local gauss = fastgaussian[taps]
  if not gauss then
    _log ("creating moonshine FastGaussianBlur shader, #taps = " .. taps)
    gauss = moonbridge "fastgaussianblur"
    gauss.setters.taps(taps)
    fastgaussian[taps] = gauss
  end
  
  gauss.filter(workflow)
end


return _M

-----
