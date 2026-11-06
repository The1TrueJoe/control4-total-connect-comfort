-- Translates a CheckDataSession response into THERMOSTAT proxy notifications.

local function SendNotify(command, params)
	SafeCall(function()
		C4:SendToProxy(THERMOSTAT_BINDING_ID, command, params or {}, 'NOTIFY')
	end)
end

-- Only sends a notify when the value actually changed since the last poll,
-- so we don't spam Director (and the UI) every poll interval.
-- `extra` adds fixed params (a temperature's SCALE).
local function NotifyIfChanged(key, value, command, paramName, extra)
	if (LAST_SENT[key] == value) then
		return
	end
	LAST_SENT[key] = value
	local params = {[paramName] = tostring(value)}
	for k, v in pairs(extra or {}) do params[k] = v end
	SendNotify(command, params)
end

local function ApplyStatus(data)
	local latest = (type(data) == 'table' and data.latestData) or {}
	local ui = latest.uiData or {}
	local fan = latest.fanData or {}

	local switchPos = tonumber(ui.SystemSwitchPosition)
	local equipmentOn = (tonumber(ui.EquipmentOutputStatus) or 0) ~= 0
	local curTemp = tonumber(ui.DispTemperature)
	local heatSetpoint = tonumber(ui.HeatSetpoint)
	local coolSetpoint = tonumber(ui.CoolSetpoint)
	local humidity = tonumber(ui.IndoorHumidity)
	local fanModeVal = tonumber(fan.fanMode)
	local fanRunning = (fan.fanIsRunning == true or fan.fanIsRunning == 1)

	local hvacMode = switchPos and HVAC_MODE_FROM_SWITCH[switchPos]
	local hvacState = 'Off'
	if (equipmentOn and HEATING_SWITCHES[switchPos]) then
		hvacState = 'Heating'
	elseif (equipmentOn and COOLING_SWITCHES[switchPos]) then
		hvacState = 'Cooling'
	end
	local fanMode = fanModeVal and FAN_MODE_FROM_VALUE[fanModeVal]
	local fanState = fanRunning and 'On' or 'Off'

	DebugLog(string.format('status: temp %s, heat %s, cool %s, humidity %s, switch %s, units %s',
		tostring(curTemp), tostring(heatSetpoint), tostring(coolSetpoint), tostring(humidity),
		tostring(switchPos), tostring(ui.DisplayedUnits)))

	-- Temperatures carry their scale: without SCALE the proxy left TEMPERATURE at -40 and both
	-- setpoints at the 39 F minimum while every other value arrived (seen on a controller).
	local scale = {SCALE = SCALE}
	if (curTemp) then
		NotifyIfChanged('temp', curTemp, 'TEMPERATURE_CHANGED', 'TEMPERATURE', scale)
	end
	if (heatSetpoint) then
		NotifyIfChanged('heat_setpoint', heatSetpoint, 'HEAT_SETPOINT_CHANGED', 'SETPOINT', scale)
	end
	if (coolSetpoint) then
		NotifyIfChanged('cool_setpoint', coolSetpoint, 'COOL_SETPOINT_CHANGED', 'SETPOINT', scale)
	end
	if (humidity) then
		NotifyIfChanged('humidity', humidity, 'HUMIDITY_CHANGED', 'HUMIDITY')
	end
	if (hvacMode) then
		NotifyIfChanged('hvac_mode', hvacMode, 'HVAC_MODE_CHANGED', 'MODE')
	end
	NotifyIfChanged('hvac_state', hvacState, 'HVAC_STATE_CHANGED', 'STATE')
	if (fanMode) then
		NotifyIfChanged('fan_mode', fanMode, 'FAN_MODE_CHANGED', 'MODE')
	end
	NotifyIfChanged('fan_state', fanState, 'FAN_STATE_CHANGED', 'STATE')

	-- SCALE isn't reported by the portal for this endpoint; it reflects the
	-- user-configured "Temperature Scale" property instead.
	NotifyIfChanged('scale', SCALE, 'SCALE_CHANGED', 'SCALE')

	UpdateDriverProperty('Last Update', os.date('%Y-%m-%d %H:%M:%S'))
	SetServiceStatus('Connected')
end

-- Reads the values already declared in driver.xml's <capabilities> block
-- via C4:GetCapability() instead of re-stating them here, so the two never
-- drift out of sync. Must run after OnDriverInit (LateInit or later).
local function GetCapabilityString(name, fallback)
	local value = SafeCall(function() return C4:GetCapability(name) end)
	if (value == nil or value == '') then
		return fallback
	end
	return value
end

local function SendInitialCapabilities()
	SendNotify('ALLOWED_HVAC_MODES_CHANGED', {
		MODES = GetCapabilityString('hvac_modes', 'Off,Heat,Cool'),
		CAN_HEAT = GetCapabilityString('can_heat', 'true'),
		CAN_COOL = GetCapabilityString('can_cool', 'true'),
		CAN_AUTO = GetCapabilityString('can_do_auto', 'false'),
	})
	SendNotify('ALLOWED_FAN_MODES_CHANGED', {MODES = GetCapabilityString('fan_modes', 'Auto,On,Circulate')})
	SendNotify('SCALE_CHANGED', {SCALE = SCALE})
end
