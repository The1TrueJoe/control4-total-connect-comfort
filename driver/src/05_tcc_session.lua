-- Total Connect Comfort session handling: login, and an authenticated
-- request helper that transparently logs in (once) before the first call
-- and retries a single time if the portal reports us as unauthenticated.

-- Once a login attempt comes back as a rejected credential or a "too many
-- attempts" response, we stop attempting to log in automatically — the TCC
-- portal locks accounts out (with a timeout) after repeated bad attempts,
-- and our poll timer would otherwise retry the same bad credentials forever
-- and keep re-triggering (or extending) that lockout. The block only lifts
-- when the user changes Username/Password (see 10_properties.lua) or
-- explicitly asks via the Refresh Now / Log Out commands (11_callbacks.lua).
local function BlockAuth(reason)
	AUTH_BLOCKED = true
	AUTH_BLOCKED_REASON = reason
	SetServiceStatus('Auth Blocked', reason)
end

local function Login(afterLogin)
	if (AUTH_BLOCKED) then
		-- Hard stop: no network request at all while blocked.
		SafeCall(function() afterLogin(false, AUTH_BLOCKED_REASON) end)
		return
	end

	if (LOGIN_IN_FLIGHT) then
		table.insert(PENDING_AFTER_LOGIN, afterLogin)
		return
	end

	if (Trim(USERNAME) == '' or Trim(PASSWORD) == '') then
		SafeCall(function() afterLogin(false, 'Username and Password are not configured') end)
		return
	end

	LOGIN_IN_FLIGHT = true

	local function finish(success, err)
		LOGIN_IN_FLIGHT = false
		SIGNED_IN = success
		local pending = PENDING_AFTER_LOGIN
		PENDING_AFTER_LOGIN = {}
		DebugLog('login result: ' .. (success and ('signed in (device ' .. tostring(DEVICE_ID) ..
			', location ' .. tostring(LOCATION_ID) .. ')') or tostring(err)))
		if (success) then
			SetServiceStatus('Connected')
		elseif (not AUTH_BLOCKED) then
			SetServiceStatus('Auth Failed', err)
		end
		afterLogin(success, err)
		for _, cb in ipairs(pending) do
			SafeCall(function() cb(success, err) end)
		end
	end

	-- A signed-in session is redirected from /portal/ to a device or location page; take the
	-- ids from there (a blank Device ID is filled from the device page).
	local function signedInFrom(redirects)
		for _, location in ipairs(redirects or {}) do
			local device = string.match(location, 'Device/Control/(%d+)')
			local locationId = string.match(location, 'portal/(%d+)/')
			if (device or locationId) then
				if (device and Trim(DEVICE_ID) == '') then
					DEVICE_ID = device
					UpdateDriverProperty('Active Device ID', DEVICE_ID)
				end
				if (locationId) then LOCATION_ID = tonumber(locationId) end
				return true
			end
		end
		return false
	end

	local body = 'UserName=' .. UrlEncode(USERNAME) .. '&Password=' .. UrlEncode(PASSWORD) ..
		'&RememberMe=false&timeOffset=0'
	-- The portal wants Basic auth alongside the form: without it the same login came back as
	-- a plain 200 with no auth cookie (rejected); with it, 302 and signed in (on a controller).
	local headers = {['Content-Type'] = 'application/x-www-form-urlencoded'}
	local basicAuth = SafeCall(function()
		return C4:Base64Encode(USERNAME .. ':' .. PASSWORD)
	end)
	if (basicAuth) then
		headers['Authorization'] = 'Basic ' .. basicAuth
	end

	-- 1. Load /portal/ as a browser does: it sets the session and cookie-check cookies the
	-- login needs, and if the session is still signed in it redirects to a device page and
	-- there is nothing to log in to (seen on a controller after a "failed" login).
	-- A redirect to a device page counts even when loading that page then times out.
	HttpRequest('GET', BASE_URL .. '/portal/', {}, nil, function(ok, code, text, errMsg, redirects)
		if (signedInFrom(redirects)) then
			finish(true)
			return
		end

		-- 2. The login itself.
		DebugLog('Logging in as ' .. USERNAME)
		HttpRequest('POST', BASE_URL .. '/portal/', headers, body, function(ok2, code2, text2, errMsg2, redirects2)
			-- The lockout is a redirect to /portal/Error/TooManyAttempts. Its words in the page
			-- are not proof: on a controller, the page after a login that worked (auth cookies
			-- set, no lockout redirect) still matched them, and the driver blocked itself.
			for _, location in ipairs(redirects2 or {}) do
				if (string.find(string.lower(location), 'error/toomanyattempts', 1, true)) then
					BlockAuth('Portal reported too many login attempts (account may be temporarily locked) — use Refresh Now once you are sure the wait has passed')
					finish(false, AUTH_BLOCKED_REASON)
					return
				end
			end
			if (signedInFrom(redirects2)) then
				finish(true)
				return
			end
			if (ok2) then
				local locationId = ExtractLocationId(text2)
				if (locationId) then
					LOCATION_ID = locationId or LOCATION_ID
					finish(true)
					return
				end
				local lower = string.lower(text2 or '')
				if (string.find(lower, 'email or password provided is incorrect', 1, true) or
						string.find(lower, 'email address is not in the correct format', 1, true)) then
					BlockAuth('Username or password was rejected — fix Username/Password to retry')
					finish(false, AUTH_BLOCKED_REASON)
					return
				end
			end
			-- 3. After a good login the portal can loop on its RememberMe redirects until the
			-- client gives up (Error 47), though the session is signed in by then. Look again.
			HttpRequest('GET', BASE_URL .. '/portal/', {}, nil, function(_, _, _, _, redirects3)
				if (signedInFrom(redirects3)) then
					finish(true)
				else
					finish(false, errMsg2 or 'Login did not land on a device or location page')
				end
			end)
		end)
	end)
end

-- Performs an authenticated JSON call against the TCC portal. Logs in first
-- if we don't yet have a location id, and retries once if the portal comes
-- back looking unauthenticated (session cookie expired).
local function TccRequest(method, path, jsonBody, onResult, isRetry)
	local function doRequest()
		local headers = {
			['Accept'] = 'application/json',
			['X-Requested-With'] = 'XMLHttpRequest',
		}
		local body = nil
		if (jsonBody ~= nil) then
			headers['Content-Type'] = 'application/json'
			body = JsonEncode(jsonBody)
		end

		HttpRequest(method, BASE_URL .. path, headers, body, function(ok, code, text, errMsg)
			if (not ok) then
				onResult(false, nil, errMsg)
				return
			end

			local looksUnauthorized = (code == 401) or string.find(text or '', 'Unauthorized', 1, true)
			if (looksUnauthorized and not isRetry) then
				DebugLog('Session expired, logging in again before retrying ' .. path)
				SIGNED_IN = false
				Login(function(success, err)
					if (not success) then
						onResult(false, nil, err)
						return
					end
					TccRequest(method, path, jsonBody, onResult, true)
				end)
				return
			end

			if (code ~= 200) then
				onResult(false, nil, 'HTTP ' .. tostring(code) .. ' from ' .. path)
				return
			end

			local data, decodeErr = JsonDecode(text)
			if (data == nil) then
				onResult(false, nil, decodeErr or 'Invalid JSON response')
				return
			end

			onResult(true, data, nil)
		end)
	end

	if (not SIGNED_IN) then
		Login(function(success, err)
			if (not success) then
				onResult(false, nil, err)
				return
			end
			doRequest()
		end)
	else
		doRequest()
	end
end

local function LogOut()
	LOCATION_ID = nil
	SIGNED_IN = false
	LOGIN_IN_FLIGHT = false
	PENDING_AFTER_LOGIN = {}
	AUTH_BLOCKED = false
	AUTH_BLOCKED_REASON = ''
	SetServiceStatus('Stopped')
end
