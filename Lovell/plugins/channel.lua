--
-- channel.lua
--

local _M = {
    NAME = ...,
    VERSION = "2026.07.24",
    AUTHOR = "AK Booer",
    DESCRIPTION = "PLUGIN – Channel for display (including inverted)",
  }

require "logger" (_M)

-- 2026.07.24  Version 0, extracted from shaders.colour


local love = _G.love
local lg = love.graphics


--  channel selector

local selector = lg.newShader[[
    uniform vec3 mix;

    vec4 effect( vec4 color, Image texture, vec2 texture_coords, vec2 _ ){
      vec3 z = Texel(texture, texture_coords) .rgb ;
      float l = dot(mix, z);
      return vec4(l, l, l, 1.0);
    }
  ]]

local invert = lg.newShader [[
    
    vec4 effect( vec4 color, Image texture, vec2 texture_coords, vec2 _ ){
      vec3 rgb = Texel(texture, texture_coords) .rgb;
      float l = clamp(1.0 - dot(rgb, vec3(1.0/3.0)), 0, 1);
      return vec4(vec3(l), 1.0);
    }
]]


local rgb = {Red = {1,0,0}, Green = {0,1,0}, Blue = {0,0,1}, Luminance = {0.3, 0.6, 0.1}}

-- PLUGIN with controls (in this case, just a Choosable)

local plugin = {"LRGB", "Luminance", "Inverted", "Red", "Green", "Blue", id = "Channel: ", default = 1, selected = 1}


-- RUN and DRAW methods


function plugin: run(workflow)

  local selected = self[self.selected]
  local selection = rgb[selected] 
  
  if selection then
    workflow: shadeWith(selector, {mix = selection})
  end

  if selected == "Inverted" then 
    workflow: shadeWith(invert)
  end
end

 
function plugin: draw()  
  -- required, but null, since Choosable does it all
end


return plugin

-----

