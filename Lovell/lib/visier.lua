--
-- Visier.lua
--

local _M = {
    NAME = ...,
    VERSION = "2026.10.16",
    AUTHOR = "AK Booer",
    DESCRIPTION = "VisieR database access",
  }

-- 2026.10.16  version 0


local http = require "socket.http"
local ltn12 = require "ltn12"

local love = _G.love
local ls = love.system

local base_url = "http://vizier.cds.unistra.fr/viz-bin/VizieR"

local function request(params)
  local url = base_url .. "?" .. table.concat(params, "&")

  local response_chunks = {}
  local _, status_code = http.request{
    url = url,
    sink = ltn12.sink.table(response_chunks)
  }

  if status_code == 200 then
    return table.concat(response_chunks)
  else
    return nil, "Failed to fetch catalog. HTTP Status: " .. tostring(status_code)
  end
end


function _M.fetchVizieR3D(catalog, ra, dec, radius_arcsec, max_results)

  local params = {
    "-source=" .. catalog,
    string.format("-c=%.6f,%.6f", ra, dec),
    "-c.rs=" .. tostring(radius_arcsec),
    "-out.max=" .. tostring(max_results),
    "-sort=_r",      -- Sorts by closest distance first
    "-out.add=_r",   -- Includes distance column (_r)
    "-out.form=json"
  }

  return request(params)

end


function _M.fetchAnnotations(catalog_id, ra, dec, radius_deg, max_results)

  local params = {
    "-source=" .. catalog_id,
    string.format("-c=%.6f,%.6f", ra, dec),
    string.format("-c.rs=%.4f", radius_deg * 60), -- VizieR expects arcminutes for -c.rs when using .rm, or use degrees via -c.rd
    "-out.max=" .. tostring(max_results or 100),
    "-sort=_r",
    "-out.add=_r",
    "-out.form=json"
  }

  -- Note: If using degrees directly, use -c.rd instead of -c.rs
  params[3] = string.format("-c.rd=%.6f", radius_deg)

  return request(params)

end

-- Example usage for a 2-degree field centered on M42 (Orion Nebula):
-- local ra_center, dec_center = 83.822, -5.391
-- local fov_radius_deg = 1.5 
-- local ngc_data = fetchAnnotations("VII/118/ngc2000", ra_center, dec_center, fov_radius_deg, 50)
-- local stars_data = fetchAnnotations("V/50", ra_center, dec_center, fov_radius_deg, 100)

function _M.fetchGalaxies(ra, dec, radius_deg, max_results)

  local params = {
    "-source=VII/237",
    string.format("-c=%.6f,%.6f", ra, dec),
    string.format("-c.rd=%.6f", radius_deg),
    "-out.max=" .. tostring(max_results or 100),
    "-sort=_r",
    "-out.add=_r",
    -- Requesting specific columns: PGC ID, RA, Dec, B magnitude, and major axis diameter
    "-out=PGC,RA1950,DE1950,BTmag,LogD25", 
    "-out.form=json"
  }

  return request(params)

end


function _M.openVizieRInBrowser(catalog, ra, dec, radius_arcsec)
    local base_url = "http://vizier.cds.unistra.fr/viz-bin/VizieR"
    
    local params = {
        "-source=" .. (catalog or ''),
        string.format("-c=%.6f,%.6f", ra, dec),
        "-c.rs=" .. tostring(radius_arcsec),
        "-sort=_r",
        "-out.add=_r"
        -- Omitting -out.form=json causes VizieR to render its interactive HTML interface
    }
    
    local url = base_url .. "?" .. table.concat(params, "&")
    
    -- Opens the URL in the default web browser on macOS
    local success, message = love.system.openURL(url)
    if not success then
        print("Failed to open browser:", message)
    end
end

-- Example usage :
-- openVizieRInBrowser("VII/118/ngc2000", 83.822, -5.391, 120) -- 2 arcminute search around M42

function _M.openVizieRInBrowser(catalog, ra, dec, radius_arcsec)
    local base_url = "http://vizier.cds.unistra.fr/viz-bin/VizieR"
    
    local params = {
        "-source=" .. catalog,
        string.format("-c=%.6f,%.6f", ra, dec),
        "-c.rs=" .. tostring(radius_arcsec),
        "-sort=_r",
        "-out.add=_r"
        -- Omitting -out.form=json causes VizieR to render its interactive HTML interface
    }
    
    local url = base_url .. "?" .. table.concat(params, "&")
    
    -- Opens the URL in the default web browser on macOS
    local success, message = love.system.openURL(url)
    if not success then
        print("Failed to open browser:", message)
    end
end


-- Example: Open a 1.5-degree DSS color sky view centered on your solved target
-- openAladinSkyView(83.822, -5.391, 1.5)
function _M.openAladinSkyView(ra, dec, fov_deg)
    -- Aladin Lite URL constructor
    local Aladin = "https://aladin.u-strasbg.fr/AladinLite/?target=%.6f%+.6f&fov=%.4f&survey=P/DSS2/color"
    local url = string.format(Aladin, ra, dec, fov_deg)
    ls.openURL(url)
end

return _M

-----

