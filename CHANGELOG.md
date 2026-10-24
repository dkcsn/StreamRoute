# Changelog

## 1.4.0 - 2026-10-24

- Added exact 128x128 Danish and US flag icons.
- Switch the QuickApp icon to the US flag only after US routing is confirmed.
- Restore the Danish flag for DK, PBR off, unknown, and error states.
- Store both controller-local custom icon IDs in hidden internal storage.

## 1.3.3 - 2026-10-24

- Publish QuickApp errors through the `log` property so external automations
  can clear stale status indicators.
- Make the EventRunner7 US LED behavior explicitly persistent and clear its
  override for every non-US state.

## 1.3.2 - 2026-10-24

- Added a persistent version and developer label to the QuickApp UI.
- Added explicit versioned startup and ready messages to the HC3 debug log.

## 1.3.1 - 2026-10-24

- Added runtime repair and verification of the stable QuickApp UUID, developer,
  and model metadata through HC3's dedicated plugin-property API.
- Fixed HC3 copies starting with empty metadata despite source directives.

## 1.3.0 - 2026-10-18

- Split the QuickApp into five focused Lua files.
- Added English setup documentation inside the QuickApp.
- Reduced visible settings to a native Secret API key and an optional controller fallback.
- Added automatic UniFi controller discovery through the HC3 default gateway.
- Moved policy identities and operational settings to verified hidden internal storage.
- Added safe first-run learning and explicit relearning of routing identifiers.
- Added the `PBR off` mode and external `setMode("OFF")` action.
- Added developer, model version, and stable QuickApp UUID metadata.
- Added automatic installation of the supplied StreamRoute PNG as the QA icon.
