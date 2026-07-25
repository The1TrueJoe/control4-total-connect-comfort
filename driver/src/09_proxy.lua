-- Commands received from the bound THERMOSTAT proxy (Control4 UI/programming).

local function HandleSubmitResult(ok, err)
	if (ok) then
		-- Refresh shortly after the portal confirms the change, instead of
		-- waiting a full poll interval. Debounced so a burst of commands
		-- (e.g. a setpoint drag) only costs one refresh, not one per command.
		ScheduleRefresh()
	else
		SetServiceStatus('Error', err)
	end
end

function ReceivedFromProxy(idBinding, strCommand, tParams)
	if (DRIVER_DESTROYING or idBinding ~= THERMOSTAT_BINDING_ID) then
		return
	end

	tParams = tParams or {}
	DebugLog('ReceivedFromProxy: ' .. tostring(strCommand))

	if (strCommand == 'SET_SETPOINT_HEAT') then
		local setpoint = tonumber(tParams.SETPOINT)
		if (setpoint) then
			SubmitChanges({HeatSetpoint = setpoint, StatusHeat = 2, StatusCool = 2, SystemSwitch = SYSTEM_SWITCH.HEAT}, HandleSubmitResult)
		end

	elseif (strCommand == 'SET_SETPOINT_COOL') then
		local setpoint = tonumber(tParams.SETPOINT)
		if (setpoint) then
			SubmitChanges({CoolSetpoint = setpoint, StatusHeat = 2, StatusCool = 2, SystemSwitch = SYSTEM_SWITCH.COOL}, HandleSubmitResult)
		end

	elseif (strCommand == 'SET_MODE_HVAC') then
		local switchVal = HVAC_MODE_TO_SWITCH[Normalize(tParams.MODE)]
		if (switchVal) then
			SubmitChanges({SystemSwitch = switchVal}, HandleSubmitResult)
		else
			DebugLog('Unsupported HVAC mode requested: ' .. tostring(tParams.MODE))
		end

	elseif (strCommand == 'SET_MODE_FAN') then
		local fanVal = FAN_MODE_TO_VALUE[Normalize(tParams.MODE)]
		if (fanVal) then
			SubmitChanges({FanMode = fanVal}, HandleSubmitResult)
		else
			DebugLog('Unsupported fan mode requested: ' .. tostring(tParams.MODE))
		end

	else
		DebugLog('Unhandled thermostat command: ' .. tostring(strCommand))
	end
end
