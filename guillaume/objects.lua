--
-- objects.lua
--

local _M = {
    NAME = ...,
    VERSION = "2024.11.24",
    AUTHOR = "AK Booer",
    DESCRIPTION = "GUI objects",
  }

-- Generic GUI mode

-- 2024.11.23  Version 0

--[[

  Different GUI modes may overload any or all of the following callback functions
  
--]]

local function noop () end

function _M.GUIobject ()
  
  return {
  
    -------------------------
    --
    -- UPDATE / DRAW
    --

    update  = noop,           -- (dt)
    draw    = noop,
    
    -------------------------
    --
    -- KEYBOARD
    --

    keypressed  = noop,     -- (key)
    keyreleased = noop,     -- (key)
    textedited  = noop,
    textinput   = noop,

    -------------------------
    --
    -- MOUSE
    --

    mousepressed  = noop,   -- (mx, my, btn)
    mousereleased = noop,   -- (mx, my, btn)
    mousemoved    = noop,   -- (mx, my, dx, dy)
    wheelmoved    = noop,   -- (wx, wy)
    
    }
 
end


return _M

-----
