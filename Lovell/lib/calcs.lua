--
--  calcs.lua
--
--  translated directly from Jocular's calcs.py
--

local _M = {
    NAME = ...,
    VERSION = "2025.02.19",
    AUTHOR = "AK Booer",
    DESCRIPTION = "translated directly from Jocular's calcs.py",

  }

-- 2025.02.15  translated directly from Jocular's calcs.py
-- 2025.02.19  added _M.utc_offset ... used in observinglist


local _log = require "logger" (_M)

--
-- Various astro calcs mainly based on Meuss. 
--

local int= math.floor

local np = math
      np.arcsin = math.asin
      np.arctan2 = math.atan2


_M.utc_offset = os.difftime(os.time(), os.time(os.date "!*t")) / 3600   -- useful constant

local function julian_date(when)
  --from Meuss p 61; 'when' is a datetime object

  local y, m, d
  y = when.year
  m = when.month
  d = when.day + when.hour / 24 + when.min / (24 * 60) + when.sec / (24 * 3600)

  if m < 3 then
    y = y - 1
    m = m + 12
  end

  local a,b
  a = int(y / 100)

  if y >= 1582 and m >= 10 then
    --Gregorian
    a = int(y / 100)
    b = 2 - a + int(a / 4)
  else
    -- Julian
    b = 0
  end

  local jd = int(365.25 * (y + 4716)) + int(30.6001 * (m + 1)) + d + b - 1524.5
  return jd
end

_M.julian_date = julian_date

local function to_range(x, d)
  -- reduce x to range 0-d by adding or subtracting multiples of d
  return x % d
--  if x < 0 then
--    return x - int((x / d) - 1) * d
--  end
--  return x - int((x / d)) * d
end

function _M.local_sidereal_time(when, longitude)
    -- direct method of Meuss p87

    -- when must be in UT
    local jd, t, mst, lst
    jd = julian_date(when)
    t = (jd - 2451545.0) / 36525.0
    mst = (
        280.46061837
        + 360.98564736629 * (jd - 2451545.0)
        + 0.000387933 * t^2
        - t^3 / 38710000
    )

    -- convert to 0-360
    mst = to_range(mst, 360)

    -- convert from Greenwich to local
    lst = mst + longitude

    return lst
end

function _M.sun_altitude(when, latitude, longitude)
    -- Meuss p163+

    local jd, rads, t
    local L0, M, C
    jd = julian_date(when)
    rads = math.pi / 180.0

    t = (jd - 2451545.0) / 36525.0
    L0 = 280.46646 + 36000.76983 * t + 0.0003032 * t * t
    L0 = to_range(L0, 360)
    M = 357.52911 + 35999.05029 * t - 0.0001537 * t * t
    -- e = 0.016708634 - 0.000042037 * t - 0.0000001267 * t * t
    C = (
        (1.914602 - 0.004817 * t - 0.000014 * t * t) * np.sin(M * rads)
        + (0.019993 - 0.000101 * t) * np.sin(2 * M * rads)
        + 0.000289 * np.sin(3 * M * rads)
    )
    
    local long_sun, sigma, lam, ep
    long_sun = L0 + C
    -- v = M + C
    -- R = (1.000001018 * (1 - e * e)) / (1 + e * np.cos(v * rads))
    sigma = 125.04 - 1934.136 * t
    lam = long_sun - 0.00569 - 0.00478 * np.sin(sigma * rads)
    ep = (
        23
        + (26 / 60)
        + (21.448 / 3600)
        - (46.815 * t + 0.00059 * t^2 - 0.001813 * t^3) / 3600
    )
    local ep_corr, ra, dec
    ep_corr = ep + 0.00256 * np.cos(sigma * rads)
    ra = (
        np.arctan2(np.cos(ep_corr * rads) * np.sin(lam * rads), np.cos(lam * rads))
        / rads
    )
    ra = to_range(ra, 360)
    dec = np.arcsin(np.sin(ep_corr * rads) * np.sin(lam * rads)) / rads

    -- now convert to locale

    local utc_offset, lst, lat, H, alt
    utc_offset = _M.utc_offset

    lst = _M.local_sidereal_time(when, longitude)
    lat = latitude * rads
    H = (-utc_offset * 15 + lst - ra) * rads
    alt = (
        np.arcsin(
            np.sin(lat) * np.sin(dec * rads)
            + np.cos(lat) * np.cos(dec * rads) * np.cos(H)
        )
        / rads
    )

    return alt
end

return _M

-----
