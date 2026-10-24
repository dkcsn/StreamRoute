# StreamRoute Netflix DK-USA

![StreamRoute icon](streamroute-icon.png)

Fibaro HC3 QuickApp for switching a dedicated TV network between regular
Danish internet, a US UniFi VPN client, and normal routing with both policies
disabled.

- Device type: `com.fibaro.deviceController`
- QuickApp UUID: `089576b5-83a3-4456-a05f-754afdb7ca77`
- Developer: Christian Søgaard
- Version: 1.3.2

## Project structure

- `main.lua` — startup, UI callbacks, and public actions
- `icon.lua` — embedded PNG installation and controller-local icon selection
- `config.lua` — native Secret handling, hidden internal storage, and gateway detection
- `unifi.lua` — UniFi HTTP client and controller fallback
- `routing.lua` — policy validation, switching, verification, and rollback
- `documentation.lua` — installation and operating guide included in the QuickApp

HC3 QuickApps support multiple Lua files. All six files are packaged in one
QuickApp; `main.lua` remains the required main file.

The supplied `streamroute-icon.png` is embedded in `icon.lua`. On a fresh HC3,
the QuickApp uploads and selects it automatically, then keeps the controller-
local icon ID in hidden internal storage.

## Installation

1. Download `StreamRoute-1.3.2.fqa` from the GitHub release.
2. In HC3, open **Settings → Devices → Other Device → Quick App → File** and
   import the package.
3. Open the QuickApp's **Variables** tab and enter the UniFi API key in
   `UNIFI_API_KEY`. Keep its type as **Secret**.
4. Leave `UNIFI_CONTROLLER` blank when the UniFi console is the HC3 default
   gateway. Otherwise enter the console URL or IP as a fallback.
5. Save and restart the QuickApp, then press **Update status**.

## Visible QuickApp variables

- `UNIFI_API_KEY` — required, HC3 type `password` (Secret)
- `UNIFI_CONTROLLER` — optional manual URL/IP fallback

The controller address is normally read from the active HC3 interface's
default gateway (`GET /settings/network`). A configured manual address is tried
only if the gateway address does not respond as a UniFi console.

All other settings are saved in hidden internal storage under `sr_config`.
Fresh installations learn the source-network ID and both interface IDs from
the two existing policies, then freeze those identifiers for all later writes.

At every startup, the QuickApp verifies its stable `quickAppUuid`, developer,
and model metadata. If an HC3 copy operation removes or changes them,
StreamRoute restores and verifies them through HC3's dedicated plugin-property
API. The stable UUID is `089576b5-83a3-4456-a05f-754afdb7ca77`.

The QuickApp UI always shows the installed StreamRoute version and developer.
The same version is written explicitly to the HC3 debug log during startup.

## Required UniFi configuration

Create these two Policy-Based Routes before starting the QuickApp:

| Policy | Source | Destination | Interface |
| --- | --- | --- | --- |
| `TV-ProtonVPN` | `TV-SmartDNS` only | Any | `US_Tunnel` |
| `Netflix-DK` | `TV-SmartDNS` only | Any | `Internet 1` |

Do not include the `Default` network. Both policies must use the same single
source network and different output interfaces.

The QuickApp changes only the `enabled` property of these two policies. It
validates the exact names and frozen identifiers before every write and checks
the resulting state afterward.

## Actions for scenes and other QuickApps

```lua
fibaro.call(QUICKAPP_ID, "setMode", "US")
fibaro.call(QUICKAPP_ID, "setMode", "DK")
fibaro.call(QUICKAPP_ID, "setMode", "OFF")
```

Accepted aliases are `USA`, `DENMARK`, `DANMARK`, `ON`, `NONE`, and `DISABLED`.
Boolean `true` selects USA and `false` disables both policies.

If either UniFi policy is deleted and recreated, verify its configuration and
allow the QuickApp to learn the new identifiers:

```lua
fibaro.call(QUICKAPP_ID, "relearnRoutingIdentity")
```

## Security

- The API key is stored as a native HC3 Secret variable.
- No API keys, HC3 credentials, controller addresses, internal network IDs, or
  `.env` files are included in this repository.
- TLS certificate validation is disabled because local UniFi consoles commonly
  use locally issued certificates. Keep HC3 and UniFi on a trusted LAN.

See `documentation.lua` for the same setup guide inside the QuickApp editor.
