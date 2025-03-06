--
--  solution methods
--

local matrix = require "lib.matrix"
  
local T = 'T'   -- transpose operator

getmetatable(matrix {}).__concat = function(self, mat) return self:concath(mat) end -- add missing '..' meta function

    
local _M = {}


-- solve Ax = b
function _M.solve(A, b)
	A = matrix(A)
	b = matrix(b)

  local AT = A ^ T
  local ATA = AT * A
  local ATb = AT * b
  local ATAATb = ATA .. ATb
 
 	ATAATb: dogauss()             -- Gauss-Jordan Method, result is in last column

  local abc = ATAATb ^ T
  return unpack( abc[#abc] )    -- result is in last row

end 


--[[

  %LMS_STEP                            [ A.K.Booer 19-Oct-1993 ]

  %  [y,e,mu] = lms_step(A,x,b,mu)
  %        solve A * x = b
  %        single iteration, avoiding calc of A'
  %        return:
  %          y, a better estimate of solution than x
  %          e, vector of errors (b-A*x)
  %
  e = b - A * x;      % error
  Ae = (e' * A)';     % correction
  y = x + mu * Ae;    % update
  %

--]]

-- TODO: refactor LMS without matrix module
local function LMS_step(A, x, b, mu)
  local e = b - A * x
  local Ae = (e ^ T * A) ^ T
  local y = x + Ae * mu
  return y, e
end


function _M.lmsXYZ(x, y, z, mu, N)
  N = N or 10
 	
	local A, Z = {}, {}
	local sum = 0
  for i = 1, #x do
		A[i] = { 1, x[i], y[i] }
		Z[i] = { z[i] }
    sum = sum + z[i]
	end

	A = matrix(A)
	Z = matrix(Z)
  
  local soln = matrix {sum / #z, 0, 0}
  for _ = 1, N do
--    print('\n', soln)
    soln = LMS_step(A, soln, Z, mu)
  end
  
  return unpack((soln^T) [1])
 
end


return _M

-----
