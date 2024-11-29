--  conf.lua

function love.conf(t)

  t.window.title = "Lövell"            -- The window title (string)
  -- <a target="_blank" href="https://icons8.com/icon/VbQAZ9BeRzB0/gps-antenna">GPS Antenna</a> icon by <a target="_blank" href="https://icons8.com">Icons8</a
  t.window.icon = "resources/icons8-gps-antenna-80.png"       -- Filepath to an image to use as the window's icon (string)
  t.window.width = 1280                -- The window width (number)
  t.window.height = 800                -- The window height (number)
--  t.window.borderless = false         -- Remove all border visuals from the window (boolean)
  t.window.resizable = true           -- Let the window be user-resizable (boolean)
  t.window.minwidth = 800               -- Minimum window width if the window is resizable (number)
  t.window.minheight = 640              -- Minimum window height if the window is resizable (number)
--  t.window.fullscreen = false         -- Enable fullscreen (boolean)
--  t.window.fullscreentype = "desktop" -- Choose between "desktop" fullscreen or "exclusive" fullscreen mode (string)
--  t.window.vsync = 1                  -- Vertical sync mode (number)
--  t.window.msaa = 0                   -- The number of samples to use with multi-sampled antialiasing (number)
--  t.window.depth = nil                -- The number of bits per sample in the depth buffer
--  t.window.stencil = nil              -- The number of bits per sample in the stencil buffer
--  t.window.display = 1                -- Index of the monitor to show the window in (number)
  t.window.highdpi = true            -- Enable high-dpi mode for the window on a Retina display (boolean)
--  t.window.usedpiscale = true         -- Enable automatic DPI scaling when highdpi is set to true as well (boolean)
--  t.window.x = nil                    -- The x-coordinate of the window's position in the specified display (number)
--  t.window.y = nil                    -- The y-coordinate of the window's position in the specified display (number)


  t.modules.audio = false              -- Enable the audio module (boolean)
--  t.modules.data = true               -- Enable the data module (boolean)
--  t.modules.event = true              -- Enable the event module (boolean)
--  t.modules.font = true               -- Enable the font module (boolean)
--  t.modules.graphics = true           -- Enable the graphics module (boolean)
--  t.modules.image = true              -- Enable the image module (boolean)
  t.modules.joystick = false           -- Enable the joystick module (boolean)
--  t.modules.keyboard = true           -- Enable the keyboard module (boolean)
--  t.modules.math = true               -- Enable the math module (boolean)
--  t.modules.mouse = true              -- Enable the mouse module (boolean)
  t.modules.physics = false            -- Enable the physics module (boolean)
  t.modules.sound = false              -- Enable the sound module (boolean)
--  t.modules.system = true             -- Enable the system module (boolean)
--  t.modules.thread = true             -- Enable the thread module (boolean)
--  t.modules.timer = true              -- Enable the timer module (boolean), Disabling it will result 0 delta time in love.update
  t.modules.touch = false              -- Enable the touch module (boolean)
  t.modules.video = false              -- Enable the video module (boolean)
--  t.modules.window = true             -- Enable the window module (boolean)

end
