--[[
STREAMROUTE 1.3.0 - INSTALLATION AND OPERATION
Developer: Christian Søgaard
QuickApp UUID: 089576b5-83a3-4456-a05f-754afdb7ca77

QUICKAPP ICON
The supplied StreamRoute PNG is embedded in icon.lua. On a fresh HC3 the
QuickApp uploads and selects it automatically. The controller-local icon ID is
stored in hidden internal storage and is not a user setting.

PURPOSE
This QuickApp switches only the TV-SmartDNS network between the regular Danish
internet connection and a US VPN client. Never select the Default network as
the source of either policy.

UNIFI NETWORK PREPARATION
1. Create or verify the "TV-SmartDNS" network. Connect only the TV or other
   intended streaming devices to this network.
2. Create and connect the VPN client "US_Tunnel". It must show Established.
3. Create the Policy-Based Route "TV-ProtonVPN":
   - Traffic Type: All Traffic / Internet
   - Source: TV-SmartDNS only
   - Destination: Any
   - Interface/VPN Tunnel: US_Tunnel
4. Create the Policy-Based Route "Netflix-DK":
   - Traffic Type: All Traffic / Internet
   - Source: TV-SmartDNS only
   - Destination: Any
   - Interface: Internet 1
5. Verify again that neither policy includes the Default network as source.
6. Create a local UniFi API key with read and write access to Network.

HC3 CONFIGURATION
- UNIFI_API_KEY: enter the key using the Secret variable type.
- UNIFI_CONTROLLER: leave blank. The QuickApp uses the HC3 default gateway as
  https://<gateway>. Enter a URL or IP only when the gateway is not the UniFi
  console; the manual address is then used as fallback.

All installation-specific routing identifiers are held in hidden HC3 internal
storage under "sr_config". On first successful connection, the QuickApp learns
the common source-network ID and both interface IDs from the two exact policy
names, validates their shape, and freezes the identifiers for future writes.

If either policy is deleted and recreated, relearn the identifiers after
checking the policies carefully:
  fibaro.call(QA_ID, "relearnRoutingIdentity")

OPERATION
- Denmark: TV-ProtonVPN disabled, Netflix-DK enabled.
- USA: TV-ProtonVPN enabled, Netflix-DK disabled.
- PBR off: both policies disabled; UniFi uses normal routing.

SCENES AND OTHER QUICKAPPS
  fibaro.call(QA_ID, "setMode", "DK")
  fibaro.call(QA_ID, "setMode", "US")
  fibaro.call(QA_ID, "setMode", "OFF")

SAFETY MODEL
Before every write, the QuickApp verifies the exact policy names, frozen
interface IDs, frozen source-network ID, Internet matching type and one source
network per policy. It changes only the "enabled" field and reads the state
back from UniFi. If the second write fails, it attempts a rollback.
]]
