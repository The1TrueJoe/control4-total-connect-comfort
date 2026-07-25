-- Higher-level Total Connect Comfort calls, built on TccRequest().

-- Finds the first zone on the account and caches its DeviceID. Only used
-- when the "Device ID" property is left blank; if the account has more
-- than one thermostat, the user should set Device ID explicitly instead.
local function DiscoverDevice(callback)
	local path = '/portal/Device/GetZoneListData?locationId=' .. tostring(LOCATION_ID) .. '&page=1'
	TccRequest('POST', path, nil, function(ok, data, err)
		if (not ok) then
			callback(false, err)
			return
		end
		if (type(data) ~= 'table' or data[1] == nil or data[1].DeviceID == nil) then
			callback(false, 'No zones were found on this Total Connect Comfort account')
			return
		end

		DEVICE_ID = tostring(data[1].DeviceID)
		UpdateDriverProperty('Active Device ID', DEVICE_ID)
		DebugLog('Discovered device id ' .. DEVICE_ID)
		callback(true, nil)
	end)
end

local function FetchStatus(callback)
	TccRequest('GET', '/portal/Device/CheckDataSession/' .. tostring(DEVICE_ID), nil, callback)
end

-- fields is a table of only the keys that should change; the rest are left
-- out of the payload, which the portal treats the same as an explicit null
-- (no change to that control).
local function SubmitChanges(fields, callback)
	local payload = {}
	for key, value in pairs(fields) do
		payload[key] = value
	end
	payload.DeviceID = tonumber(DEVICE_ID) or DEVICE_ID

	TccRequest('POST', '/portal/Device/SubmitControlScreenChanges', payload, function(ok, data, err)
		if (not ok) then
			callback(false, err)
			return
		end
		if (type(data) ~= 'table' or tonumber(data.success) ~= 1) then
			callback(false, 'Portal rejected the change')
			return
		end
		callback(true, nil)
	end)
end
