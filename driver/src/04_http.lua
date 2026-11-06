-- Thin wrapper around C4:url() for outbound HTTPS calls to the TCC portal.

-- With Debug Mode on: one line per response in the transfer (each redirect hop), with the
-- status, where it redirected, and the NAMES of the cookies it set (never their values),
-- then the cookie names Director's jar holds for the portal. Enough to see a login loop.
local function LogTransfer(method, url, responses, errCode, errMsg)
	DebugLog(string.format('%s %s -> %s', method, url, errCode == 0 and 'done' or ('error ' .. tostring(errCode) .. ' ' .. tostring(errMsg))))
	for i, r in ipairs(responses or {}) do
		local h = r.headers or {}
		local location = h.Location or h.location or ''
		local cookies = {}
		local setCookie = h['Set-Cookie'] or h['set-cookie']
		for _, c in ipairs(type(setCookie) == 'table' and setCookie or { setCookie }) do
			local name = string.match(tostring(c or ''), '^%s*([^=;]+)=')
			if (name) then cookies[#cookies + 1] = name end
		end
		DebugLog(string.format('  hop %d: HTTP %s%s%s', i, tostring(r.code),
			location ~= '' and (' -> ' .. location) or '',
			#cookies > 0 and (' sets ' .. table.concat(cookies, ',')) or ''))
	end
	local ok, jar = pcall(function() return C4:urlGetCookies() end)
	if (ok and type(jar) == 'table') then
		for domain, tab in pairs(jar) do
			if (string.find(tostring(domain), 'totalconnect', 1, true)) then
				local names = {}
				for name, _ in pairs(tab) do names[#names + 1] = name end
				DebugLog('  cookie jar ' .. tostring(domain) .. ': ' .. table.concat(names, ','))
			end
		end
	end
end

-- Fires callback(ok, code, bodyText, errMsg, redirects). ok is true only for a
-- transport-level success (errCode == 0); callers still need to check code
-- for HTTP-level failures (401, 500, etc).
local function HttpRequest(method, url, headers, body, callback)
	if (not C4 or not C4.url) then
		SafeCall(function() callback(false, 0, '', 'C4:url is unavailable') end)
		return
	end

	local transfer = C4:url()
	transfer:SetOptions({
		cookies_enable = true,
		fail_on_error = false,
		-- The portal sometimes takes 8-15 s to answer a login (seen 2026-11-05); 20 s
		-- timed out a real sign-in from a controller.
		timeout = 45,
		connect_timeout = 10,
	})

	transfer:OnDone(function(_, responses, errCode, errMsg)
		if (DEBUGPRINT) then
			LogTransfer(method, url, responses, errCode, errMsg)
		end
		if (errCode ~= 0) then
			SafeCall(function() callback(false, 0, '', errMsg or ('transfer error ' .. tostring(errCode))) end)
			return
		end
		local resp = responses[#responses] or {}
		-- Every redirect the transfer followed, so callers can tell where the portal sent them.
		local redirects = {}
		for _, r in ipairs(responses) do
			local h = r.headers or {}
			local location = h.Location or h.location
			if (location) then redirects[#redirects + 1] = tostring(location) end
		end
		SafeCall(function() callback(true, resp.code or 0, resp.body or '', nil, redirects) end)
	end)

	method = string.upper(method)
	if (method == 'GET') then
		transfer:Get(url, headers or {})
	elseif (method == 'POST') then
		transfer:Post(url, body or '', headers or {})
	else
		transfer:Custom(url, method, body or '', headers or {})
	end
end
