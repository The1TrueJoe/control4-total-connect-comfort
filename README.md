# control4-total-connect-comfort

Control4 driver for Honeywell Total Connect Comfort thermostats. Talks to the same
unofficial `mytotalconnectcomfort.com` portal API reverse-engineered by
[pyhtcc](https://github.com/csm10495/pyhtcc), exposed to Control4 as a standard
`thermostatV2` proxy so it works with the built-in Thermostat UI, programming, and
Room Selection.

## Structure

Modeled after [control4-roomcontrol-webhook](https://github.com/The1TrueJoe/control4-roomcontrol-webhook):
`driver/src/*.lua` is concatenated by `build.sh` into `driver/driver.lua`, then packaged
into `total_connect_comfort.c4z` with Snap One's `driverpackager`. `driver/driver.lua`,
`total_connect_comfort.c4z`, and the local `tools/` packager checkout are build output —
gitignored, not committed.

| File | Purpose |
|---|---|
| `01_globals.lua` | Constants and runtime state (mode/switch lookup tables, session state) |
| `02_utils.lua` | Trim/Normalize/SafeCall/logging/property helpers |
| `03_json.lua` | JSON encode/decode (native `C4:JsonEncode`/`C4:JsonDecode`) |
| `04_http.lua` | `C4:url()` wrapper for outbound HTTPS calls |
| `05_tcc_session.lua` | Login and an authenticated request helper (auto re-login on session expiry) |
| `06_tcc_api.lua` | Device discovery, status fetch, and control-change submission |
| `07_state.lua` | Maps portal JSON to `THERMOSTAT` proxy `NOTIFY`s |
| `08_poll.lua` | Poll timer and a debounced post-command refresh |
| `09_proxy.lua` | `ReceivedFromProxy` — translates thermostat UI commands into portal calls |
| `10_properties.lua` | Composer property change handling |
| `11_callbacks.lua` | `OnDriverInit`/`OnDriverLateInit`/`OnDriverDestroyed`/`ExecuteCommand` |

## Setup

1. Run `./build.sh` to produce `total_connect_comfort.c4z` (or download it from a
   [release](../../releases) or the latest [GitHub Actions run](../../actions)).
2. Add the driver to a room in Composer Pro.
3. Set **Username** / **Password** to your mytotalconnectcomfort.com credentials.
4. Leave **Device ID** blank to auto-select the account's first thermostat, or set it
   explicitly if the account has more than one (visible in the portal URL as
   `portal/Device/Control/<id>`).
5. Set **Temperature Scale** to match the account's configured units.

## Rate limiting

mytotalconnectcomfort.com has no official API, and forum/GitHub reports (pyhtcc,
homebridge-tcc, and others) describe accounts/IPs getting rate-limited or banned for polling
too aggressively. This driver is deliberately conservative: **Poll Interval** defaults to 300s
and can't go below 60s, setpoint/mode changes from the UI schedule a debounced refresh a few
seconds later instead of polling immediately (so a setpoint drag costs one request, not one per
step), and the login session is reused rather than re-authenticating on every call. If you need
tighter sync, raise the poll interval's usefulness with **Refresh Now** rather than lowering the
interval.

**Auth lockout protection:** the portal temporarily locks accounts out after repeated failed
logins. The first time a login attempt comes back as a rejected credential or a "too many
attempts" response, the driver stops making any further login requests at all — the poll timer
will not retry, no matter how long it runs — and **Connection Status** shows `Auth Blocked`. It
only tries again when you correct **Username**/**Password** (which clears the block) or run
**Refresh Now** (the one action that deliberately clears the block and retries). Don't mash
**Refresh Now** while unsure the credentials are right — each click is a real login attempt
against the portal.

## Known limitations

- Auto HVAC mode isn't settable — the portal API has no documented write value for it, so
  only Off/Heat/Cool are exposed. A thermostat physically in Auto is reported as whichever
  of Heat/Cool is currently active.
- Outdoor temperature and humidify/dehumidify setpoints aren't exposed; the portal only
  surfaces those via HTML scraping, which this driver intentionally doesn't do.
- Humidity is reported read-only.
