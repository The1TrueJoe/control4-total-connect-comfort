-- Runtime state and configuration defaults.
-- All shared module-level variables are declared here so every subsequent
-- source file can reference them after concatenation.

local DRIVER_VERSION = '1.0.0'
local LOG_PREFIX = '[Total Connect Comfort] '
local BASE_URL = 'https://mytotalconnectcomfort.com'
local THERMOSTAT_BINDING_ID = 5001

-- TCC has no official API and forum reports (e.g. pyhtcc/homebridge-tcc
-- issue trackers) describe accounts/IPs getting rate-limited or banned from
-- polling too aggressively. Default to a conservative interval; the honest
-- fix if this is ever still too hot is to raise "Poll Interval" further, not
-- to poll faster.
local DEFAULT_POLL_SECONDS = 300
local MIN_POLL_SECONDS = 60

-- After a command from the proxy (e.g. a setpoint drag), wait this long with
-- no further commands before re-fetching status, so a burst of UI changes
-- costs one refresh instead of one per keystroke.
local REFRESH_DEBOUNCE_MS = 5000

-- SystemSwitch values used by both the read-back (SystemSwitchPosition) and
-- the SubmitControlScreenChanges write API. Values 1/2/3 are confirmed
-- identical in both directions by the reference pyhtcc client; TCC does not
-- expose a documented write value for Auto, so Auto is not offered as a
-- settable HVAC_MODE (see hvac_modes capability in driver.xml).
local SYSTEM_SWITCH = {
	EM_HEAT = 0,
	HEAT = 1,
	OFF = 2,
	COOL = 3,
	AUTO_HEAT = 4,
	AUTO_COOL = 5,
	SOUTHERN_AWAY = 6,
}

local HVAC_MODE_FROM_SWITCH = {
	[SYSTEM_SWITCH.EM_HEAT] = 'Heat',
	[SYSTEM_SWITCH.HEAT] = 'Heat',
	[SYSTEM_SWITCH.OFF] = 'Off',
	[SYSTEM_SWITCH.COOL] = 'Cool',
	[SYSTEM_SWITCH.AUTO_HEAT] = 'Heat',
	[SYSTEM_SWITCH.AUTO_COOL] = 'Cool',
	[SYSTEM_SWITCH.SOUTHERN_AWAY] = 'Off',
}

local HVAC_MODE_TO_SWITCH = {
	OFF = SYSTEM_SWITCH.OFF,
	HEAT = SYSTEM_SWITCH.HEAT,
	COOL = SYSTEM_SWITCH.COOL,
}

local HEATING_SWITCHES = {[SYSTEM_SWITCH.HEAT] = true, [SYSTEM_SWITCH.AUTO_HEAT] = true, [SYSTEM_SWITCH.EM_HEAT] = true}
local COOLING_SWITCHES = {[SYSTEM_SWITCH.COOL] = true, [SYSTEM_SWITCH.AUTO_COOL] = true}

-- fanData.fanMode values from CheckDataSession.
local FAN_MODE_FROM_VALUE = {
	[0] = 'Auto',
	[1] = 'On',
	[2] = 'Circulate',
	[3] = 'Auto',
}

local FAN_MODE_TO_VALUE = {
	AUTO = 0,
	ON = 1,
	CIRCULATE = 2,
}

-- Runtime (non-persisted) state.
local USERNAME = ''
local PASSWORD = ''
local DEVICE_ID = ''
local LOCATION_ID = nil
-- Signed in to the portal (its session cookies are valid). Not the same as knowing a location:
-- a signed-in session can land straight on a device page.
local SIGNED_IN = false
local AUTH_BLOCKED = false
local AUTH_BLOCKED_REASON = ''
local SCALE = 'F'
local POLL_SECONDS = DEFAULT_POLL_SECONDS
local DEBUGPRINT = false

local POLL_TIMER = nil
local REFRESH_DEBOUNCE_TIMER = nil
local LATE_INIT_DONE = false
local DRIVER_DESTROYING = false
local LOGIN_IN_FLIGHT = false
local PENDING_AFTER_LOGIN = {}

-- Last-sent proxy values, used to suppress redundant NOTIFYs on every poll.
local LAST_SENT = {}
