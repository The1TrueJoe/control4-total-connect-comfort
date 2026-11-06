-- Thin wrapper around C4:url() for outbound HTTPS calls to the TCC portal.

-- Fires callback(ok, code, bodyText, errMsg). ok is true only for a
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
		if (errCode ~= 0) then
			SafeCall(function() callback(false, 0, '', errMsg or ('transfer error ' .. tostring(errCode))) end)
			return
		end
		local resp = responses[#responses] or {}
		SafeCall(function() callback(true, resp.code or 0, resp.body or '', nil) end)
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
