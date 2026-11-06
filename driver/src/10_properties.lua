-- Composer property change handling.

local function ApplyProperty(name)
	local value = (Properties and Properties[name]) or ''

	if (name == 'Driver Version') then
		UpdateDriverProperty('Driver Version', DRIVER_VERSION)

	elseif (name == 'Debug Mode') then
		DEBUGPRINT = (value == 'On')

	elseif (name == 'Username') then
		local newValue = Trim(value)
		if (newValue ~= USERNAME) then
			USERNAME = newValue
			LOCATION_ID = nil
			SIGNED_IN = false
			AUTH_BLOCKED = false
			AUTH_BLOCKED_REASON = ''
			LAST_SENT = {}
			StartPolling()
		end

	elseif (name == 'Password') then
		local newValue = Trim(value)
		if (newValue ~= PASSWORD) then
			PASSWORD = newValue
			LOCATION_ID = nil
			SIGNED_IN = false
			AUTH_BLOCKED = false
			AUTH_BLOCKED_REASON = ''
			LAST_SENT = {}
			StartPolling()
		end

	elseif (name == 'Device ID') then
		local newValue = Trim(value)
		if (newValue ~= DEVICE_ID) then
			DEVICE_ID = newValue
			LAST_SENT = {}
			StartPolling()
		end

	elseif (name == 'Temperature Scale') then
		SCALE = (value == 'Celsius') and 'C' or 'F'

	elseif (name == 'Poll Interval (seconds)') then
		POLL_SECONDS = tonumber(value) or DEFAULT_POLL_SECONDS
		StartPolling()
	end
end
