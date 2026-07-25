-- Generic helpers shared by the rest of the driver.

local function Trim(value)
	value = tostring(value or '')
	return (string.gsub(value, '^%s*(.-)%s*$', '%1'))
end

local function Normalize(value)
	value = Trim(value)
	value = string.gsub(value, '[%s%-/]+', '_')
	return string.upper(value)
end

local function SafeCall(fn)
	local ok, result = pcall(fn)
	if (ok) then
		return result
	end
	return nil
end

local function DebugLog(message)
	if (DEBUGPRINT) then
		print(LOG_PREFIX .. tostring(message))
	end
end

local function UpdateDriverProperty(name, value)
	if (C4 and C4.UpdateProperty) then
		SafeCall(function()
			C4:UpdateProperty(name, tostring(value or ''))
		end)
	end
end

local function SetServiceStatus(status, err)
	UpdateDriverProperty('Connection Status', status)
	if (err and err ~= '') then
		UpdateDriverProperty('Last Error', err)
		DebugLog('Error: ' .. tostring(err))
	end
end

local function UrlEncode(value)
	value = tostring(value or '')
	value = string.gsub(value, '([^%w%-%.%_%~])', function(c)
		return string.format('%%%02X', string.byte(c))
	end)
	return value
end

-- Extracts the first numeric TCC locationId from a login response body,
-- either from a redirect-style "portal/<id>/..." fragment or from a
-- "locationId=<id>" query fragment embedded in the page.
local function ExtractLocationId(text)
	text = tostring(text or '')
	local id = string.match(text, 'portal/(%d+)/')
	if (id) then
		return tonumber(id)
	end
	id = string.match(text, 'locationId=(%d+)')
	return tonumber(id)
end
