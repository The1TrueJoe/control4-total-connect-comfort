-- Poll loop: keeps the THERMOSTAT proxy in sync with the TCC portal.

local function PollStatus()
	if (DRIVER_DESTROYING) then
		return
	end

	if (Trim(DEVICE_ID) == '') then
		if (not SIGNED_IN or not LOCATION_ID) then
			Login(function(success, err)
				if (success and Trim(DEVICE_ID) ~= '') then
					-- Signing in landed on the device page, which named the device.
					PollStatus()
				elseif (success) then
					DiscoverDevice(function(ok, discErr)
						if (ok) then
							PollStatus()
						else
							SetServiceStatus('Error', discErr)
						end
					end)
				else
					SetServiceStatus('Auth Failed', err)
				end
			end)
		else
			DiscoverDevice(function(ok, discErr)
				if (ok) then
					PollStatus()
				else
					SetServiceStatus('Error', discErr)
				end
			end)
		end
		return
	end

	FetchStatus(function(ok, data, err)
		if (not ok) then
			SetServiceStatus('Error', err)
			return
		end
		ApplyStatus(data)
	end)
end

local function StopPolling()
	if (POLL_TIMER) then
		SafeCall(function() POLL_TIMER:Cancel() end)
		POLL_TIMER = nil
	end
end

local function StartPolling()
	StopPolling()
	if (DRIVER_DESTROYING or not LATE_INIT_DONE) then
		return
	end

	local intervalMs = math.max(MIN_POLL_SECONDS, POLL_SECONDS) * 1000
	POLL_TIMER = C4:SetTimer(intervalMs, function()
		PollStatus()
	end, true)

	-- Kick off an immediate poll instead of waiting a full interval.
	PollStatus()
end

-- Coalesces bursts of proxy commands (e.g. a setpoint drag sends many
-- SET_SETPOINT_HEAT calls in a row) into a single refresh, instead of
-- hitting the portal once per command.
local function ScheduleRefresh()
	if (DRIVER_DESTROYING) then
		return
	end
	if (REFRESH_DEBOUNCE_TIMER) then
		SafeCall(function() REFRESH_DEBOUNCE_TIMER:Cancel() end)
	end
	REFRESH_DEBOUNCE_TIMER = C4:SetTimer(REFRESH_DEBOUNCE_MS, function()
		REFRESH_DEBOUNCE_TIMER = nil
		PollStatus()
	end)
end
