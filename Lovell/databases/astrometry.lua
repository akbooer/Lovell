--
-- astrometry.lua
--

local _M = {
    NAME = ...,
    VERSION = "2025.07.14",
    AUTHOR = "AK Booer",
    DESCRIPTION = "Astrometry database for plate solving",
  }

-- 2025.07.14  Version 0


local _log = require "logger" (_M)

local session = require "session"
local http    = require "socket.http"
local multi   = require "lib/multipart-post"

local json = _G.json

local love = _G.love
local lf = love.filesystem


local url = "https://nova.astrometry.net/api/login"
local key = session.controls.settings.apikey.text

local body = "request-json=" .. json.encode {apikey = key}

print(http.request (url, body))

--[[

  returns:
      {"status": "success", "message": "authenticated user: xxx", "session": "bw3c7a9e7es9r08rew2f4t60d59yksww"}
      
      200 	
      table: 0x556b162d89e0 	
      HTTP/1.1 200 OK

]]
