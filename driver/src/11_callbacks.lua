-- DriverWorks callbacks invoked by Control4 Director.

function OnDriverInit(driverInitType)
	DRIVER_DESTROYING = false
	LATE_INIT_DONE = false
	LOCATION_ID = nil
	LOGIN_IN_FLIGHT = false
	PENDING_AFTER_LOGIN = {}
	AUTH_BLOCKED = false
	AUTH_BLOCKED_REASON = ''
	LAST_SENT = {}

	UpdateDriverProperty('Driver Version', DRIVER_VERSION)
end

function OnDriverLateInit(driverInitType)
	for name, _ in pairs(Properties or {}) do
		ApplyProperty(name)
	end
	LATE_INIT_DONE = true
	SendInitialCapabilities()
	StartPolling()
end

function OnDriverDestroyed(driverInitType)
	DRIVER_DESTROYING = true
	LATE_INIT_DONE = false
	StopPolling()
end

function OnPropertyChanged(name)
	if (DRIVER_DESTROYING) then
		return
	end
	ApplyProperty(name)
end

function ExecuteCommand(strCommand, tParams)
	if (DRIVER_DESTROYING) then
		return
	end

	tParams = tParams or {}
	local command = Normalize(strCommand)
	if (command == 'LUA_ACTION') then
		command = Normalize(tParams.ACTION or tParams.action or '')
	end

	if (command == 'REFRESH_NOW') then
		-- A deliberate, explicit user action is allowed to clear an auth
		-- block and try again; the automatic poll timer is not (see
		-- 05_tcc_session.lua Login()/BlockAuth()).
		AUTH_BLOCKED = false
		AUTH_BLOCKED_REASON = ''
		PollStatus()
	elseif (command == 'LOG_OUT') then
		LogOut()
	else
		DebugLog('Unhandled ExecuteCommand: ' .. tostring(strCommand))
	end
end
