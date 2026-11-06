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
	DebugLog('Logging in as ' .. USERNAME)

	local body = 'UserName=' .. UrlEncode(USERNAME) .. '&Password=' .. UrlEncode(PASSWORD) ..
		'&RememberMe=false&timeOffset=0'
	local basicAuth = SafeCall(function()
		return C4:Base64Encode(USERNAME .. ':' .. PASSWORD)
	end)

	local headers = {['Content-Type'] = 'application/x-www-form-urlencoded'}
	if (basicAuth) then
		headers['Authorization'] = 'Basic ' .. basicAuth
	end

	-- Load the login page first, as a browser (and pyhtcc) does: it sets the session and
	-- cookie-check cookies the login POST relies on. Posting cold redirected in a loop
	-- ("Error 47: Number of redirects hit maximum amount") on a controller.
	HttpRequest('GET', BASE_URL .. '/portal/', {}, nil, function()
	HttpRequest('POST', BASE_URL .. '/portal/', headers, body, function(ok, code, text, errMsg)
		LOGIN_IN_FLIGHT = false
		local pending = PENDING_AFTER_LOGIN
		PENDING_AFTER_LOGIN = {}

		local success, err = false, nil
		local lower = string.lower(text or '')
		if (not ok) then
			err = errMsg or 'Login request failed'
		elseif (string.find(lower, 'email or password provided is incorrect', 1, true) or
				string.find(lower, 'email address is not in the correct format', 1, true)) then
			BlockAuth('Username or password was rejected — fix Username/Password to retry')
			err = AUTH_BLOCKED_REASON
		elseif (string.find(lower, 'toomanyattempts', 1, true) or
				string.find(lower, 'too many attempts', 1, true) or
				string.find(lower, 'temporarily locked', 1, true)) then
			BlockAuth('Portal reported too many login attempts (account may be temporarily locked) — use Refresh Now once you are sure the wait has passed')
			err = AUTH_BLOCKED_REASON
		else
			local locationId = ExtractLocationId(text)
			if (not locationId) then
				err = 'Login did not return a location id (unexpected response)'
			else
				LOCATION_ID = locationId
				success = true
			end
		end

		if (success) then
			SetServiceStatus('Connected')
		elseif (not AUTH_BLOCKED) then
			SetServiceStatus('Auth Failed', err)
		end

		afterLogin(success, err)
		for _, cb in ipairs(pending) do
			SafeCall(function() cb(success, err) end)
		end
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

	if (not LOCATION_ID) then
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
	LOGIN_IN_FLIGHT = false
	PENDING_AFTER_LOGIN = {}
	AUTH_BLOCKED = false
	AUTH_BLOCKED_REASON = ''
	SetServiceStatus('Stopped')
end
