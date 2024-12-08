--
-- smoother – 3x3 shader
--

local _M = {
    NAME = ...,
    VERSION = "2024.11.07",
    AUTHOR = "AK Booer",
    DESCRIPTION = "3x3 box smoother",
  }

local _log = require "logger" (_M)

local newTimer = require "utils" .newTimer

-- 2024.11.07  @akbooer
--

local love = _G.love
local lg = love.graphics


-------------------------------
--
-- MOONSHINE - simple framework to apply Moonshine shaders
-- see: https://github.com/vrld/moonshine
--

local moonshine = {}

function moonshine.Effect(...) return ... end

function moonshine.draw_shader(buffer)
  
end

-------------------------------
--

local smooth3x3 = lg.newShader [[
  uniform vec2 dx;
  uniform vec2 dy;
  
  vec4 effect(vec4 color, Image texture, vec2 tc, vec2 _) {
  
      vec2 y = tc;
      vec4 d = vec4(0.0);
      
      d += Texel(texture, y     );
      d += Texel(texture, y + dx);
      d += Texel(texture, y - dx);
      
      y = tc + dy;
      d += Texel(texture, y     );
      d += Texel(texture, y + dx);
      d += Texel(texture, y - dx);
      
      y = tc - dy;
      d += Texel(texture, y     );
      d += Texel(texture, y + dx);
      d += Texel(texture, y - dx);
      
      return d / 9.0;
  }
]]


function _M.smooth(input, output)
  
  local w, h = input: getDimensions()
  smooth3x3: send("dx", {1 / w, 0})
  smooth3x3: send("dy", {0, 1 / h})
  
  lg.setShader(smooth3x3) 
  output:renderTo(lg.draw, input)
  lg.setShader()
  return output
end

-------------------------------
--
-- BOXBLUR, from Moonshine
--

local boxblur = love.graphics.newShader[[
  extern vec2 direction;
  extern number radius;
  vec4 effect(vec4 color, Image texture, vec2 tc, vec2 _) {
    vec4 c = vec4(0.0);

    for (float i = -radius; i <= radius; i += 1.0)
    {
      c += Texel(texture, tc + i * direction);
    }
    return c / (2.0 * radius + 1.0) * color;
  }]]

function _M.boxblur(input, output, controls)
  local radius_x = controls.filter.radius
  local radius_y = radius_x
  local shader = boxblur
  local w,h = input: getDimensions()
  lg.setShader(shader)
  shader:send('direction', {1 / w, 0})
  shader:send('radius', math.floor(radius_x + .5))
  output: renderTo (lg.draw, input)

  shader:send('direction', {0, 1 / h})
  shader:send('radius', math.floor(radius_y + .5))
  input: renderTo (lg.draw, output)
  lg.setShader()
  
  output: renderTo(lg.draw, input)    -- swap input to output
  return output
end

-------------------------------
--
-- TNR - Tony's noise reduction
--
--[[
Radius = 17;
Strength = 30;

($T - medfilt($T, Radius))                   // signal - model
   * (1 / (1 + Strength * exp (-27 * $T)))   // window
   + medfilt($T, Radius)                     // + model

]]

local tnr = love.graphics.newShader[[
  extern float strength;
  extern Image background;
  const vec3 one = vec3(1.0);
  
  vec4 effect(vec4 color, Image texture, vec2 tc, vec2 _) {
    vec3 image = Texel(texture, tc) .rgb;
    vec3 backg = Texel(background, tc) .rgb;
    vec3 window = one / (1.0 + strength * exp (-7.0 * image));
    vec3 tnr = (image - backg) * window + image;
    return vec4(clamp(tnr, 0.0, 1.0), 1.0);
  }]]

function _M.tnr(background, input, output, controls)
  local strength = 30 * controls.denoise.value
  local shader = tnr
  lg.setShader(shader)
  shader: send("background", background)
  shader: send("strength", strength)
  output: renderTo(lg.draw, input)
  lg.setShader()
  return output
end

-------------------------------
--
-- APF0 - two scales: 3x3, plus whatever additional smoothed background is supplied
--
--[[
$T ^ (2^(gconv($T,3) - $T))
for 3, 6, 12, 24

]]

local apf0 = love.graphics.newShader[[
  extern vec2 dx, dy;
  extern float strength;
  extern Image background;
  const vec3 one = vec3(1.0);

  vec4 effect(vec4 color, Image texture, vec2 tc, vec2 _) {
    vec4 d = Texel(texture, tc);
    vec3 image = d.rgb;
    
    d += Texel(texture, tc + dx + dy);
    d += Texel(texture, tc - dx + dy);
    d += Texel(texture, tc + dx - dy);
    d += Texel(texture, tc - dx - dy);
    d += Texel(texture, tc + dx);
    d += Texel(texture, tc - dx);
    d += Texel(texture, tc + dy);
    d += Texel(texture, tc - dy);
    vec3 back0 = d .rgb / 9.0;
    
    vec3 backg = Texel(background,  tc) .rgb;
    vec3 foo = image;
    image = pow(image, pow(vec3(2.0), 6.0 * strength * (back0 - image)));
    image = pow(image, pow(vec3(2.0), 3.0 * strength * (backg - image)));
    return vec4(clamp(image, 0.0, 1.0), 1.0);
  }]]

function _M.apf0(background, input, output, controls)
  local strength = controls.sharpen.value
  local shader = apf0
  local w, h = input: getDimensions()
  lg.setShader(shader)
  shader: send("dx", {1 / (w - 1), 0})
  shader: send("dy", {0, 1 / (h - 1)})
  shader: send("background",  background)
  shader: send("strength", strength)
  output: renderTo(lg.draw, input)
  lg.setShader()
  return output
end

-------------------------------
--
-- APF - 2 scales
--
--[[
$T ^ (2^(gconv($T,3) - $T))
for 3, 6, 12, 24

]]

local apf2 = love.graphics.newShader[[
  extern float strength;
  extern Image background, background2;
  const vec3 one = vec3(1.0);

  vec4 effect(vec4 color, Image texture, vec2 tc, vec2 _) {
    vec3 image = Texel(texture, tc) .rgb;
    vec3 backg = Texel(background,  tc) .rgb;
    vec3 back2 = Texel(background2, tc) .rgb;
    image = pow(image, pow(vec3(2.0), 3.0 * strength * (backg - image)));
    image = pow(image, pow(vec3(2.0), 3.0 * strength * (back2 - image)));
    return vec4(clamp(image, 0.0, 1.0), 1.0);
  }]]

function _M.apf2(background, background2, input, output, controls)
  local strength = controls.sharpen.value
  local shader = apf2
  lg.setShader(shader)
  shader: send("background",  background)
  shader: send("background2", background2)
  shader: send("strength", strength)
  output: renderTo(lg.draw, input)
  lg.setShader()
  return output
end

-------------------------------
--
-- APF
--
--[[
$T ^ (2^(gconv($T,3) - $T))
for 3, 6, 12, 24

]]

local apf = love.graphics.newShader[[
  extern float strength;
  extern Image background;
  const vec3 one = vec3(1.0);

  vec4 effect(vec4 color, Image texture, vec2 tc, vec2 _) {
    vec3 image = Texel(texture, tc) .rgb;
    vec3 backg = Texel(background, tc) .rgb;
    vec3 apf = pow(image, pow(vec3(2.0), 3.0 * strength * (backg - image)));
    return vec4(clamp(apf, 0.0, 1.0), 1.0);
  }]]

function _M.apf(background, input, output, controls)
  local strength = controls.sharpen.value
  local shader = apf
  lg.setShader(shader)
  shader: send("background", background)
  shader: send("strength", strength)
  output: renderTo(lg.draw, input)
  lg.setShader()
  return output
end

-------------------------------
--
-- STARS
--

local stars = love.graphics.newShader[[
  extern float strength;
  extern Image background;
  
  vec4 effect(vec4 color, Image texture, vec2 tc, vec2 _) {
    vec3 image = Texel(texture, tc) .rgb;
    vec3 backg = Texel(background, tc) .rgb;
    vec3 stars = image - backg * strength;
    return vec4(clamp(stars, 0.0, 1.0), 1.0);
  }]]

function _M.stars(background, input, output, controls)
  local strength = controls.stars.value
  local shader = stars
--  local t = love.timer.getTime() % 1
  lg.setShader(shader)
  shader: send("background", background)
--  shader: send("strength", t > 0.5 and strength or 0)
  shader: send("strength", strength)
  output: renderTo(lg.draw, input)
  lg.setShader()
  return output
end

-----

return _M

-----
