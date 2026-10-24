MODULE = MODULE or {}

local MODULE_NAME = "xStreamRoute"
local VERSION = "1.0.0"
local ENABLED = true

-- StreamRoute is normally found by its stable QuickApp UUID. The fallback is
-- the local QA ID on this HC3 and is used only if UUID lookup is unavailable.
local STREAMROUTE_UUID = "089576b5-83a3-4456-a05f-754afdb7ca77"
local STREAMROUTE_FALLBACK_ID = 2900

-- Living-room Matrix configuration:
--   scene device 218 is HT.livingroom.switch
--   Matrix root 217 is HT.livingroom.matrix_root
-- Button 2 toggles DK/US. Holding button 2 disables both PBR policies.
local BUTTON_NUMBER = 2
local LED_NUMBER = 2
local US_LED_COLOR = "signalBlue"

local function setup(er)
  local rule = er.eval
  local var = er.variables
  local streamRouteId = nil

  local function resolveStreamRoute()
    if streamRouteId then return streamRouteId end

    local matches = {}
    for _, device in ipairs(api.get("/devices") or {}) do
      local properties = device.properties or {}
      if properties.quickAppUuid == STREAMROUTE_UUID then
        matches[#matches + 1] = device.id
      end
    end

    if #matches == 1 then
      streamRouteId = matches[1]
      fibaro.debug(MODULE_NAME, "StreamRoute found by UUID: " .. streamRouteId)
    else
      streamRouteId = STREAMROUTE_FALLBACK_ID
      fibaro.warning(
        MODULE_NAME,
        "Expected one StreamRoute UUID match, using fallback QA " .. streamRouteId
      )
    end

    return streamRouteId
  end

  local function confirmedMode()
    local device = api.get("/devices/" .. resolveStreamRoute()) or {}
    local log = tostring((device.properties or {}).log or "")

    if log:find("USA via US_Tunnel", 1, true) then return "US" end
    if log:find("Danmark via Internet 1", 1, true) then return "DK" end
    if log:find("Normal routing", 1, true) then return "OFF" end
    return "UNKNOWN"
  end

  function var.streamRouteSyncLed()
    if confirmedMode() == "US" then
      bgSet(HT.livingroom.matrix_root, LED_NUMBER, US_LED_COLOR)
    else
      bgClear(HT.livingroom.matrix_root, LED_NUMBER)
    end
  end

  function var.streamRouteToggle()
    local target = confirmedMode() == "US" and "DK" or "US"
    fibaro.call(resolveStreamRoute(), "setMode", target)
    fibaro.debug(MODULE_NAME, "Button 2 requested StreamRoute mode " .. target)
  end

  function var.streamRouteDisable()
    fibaro.call(resolveStreamRoute(), "setMode", "OFF")
    fibaro.debug(MODULE_NAME, "Button 2 hold requested PBR OFF")
  end

  -- Make the resolved ID available to the EventRunner event expression.
  var.StreamRouteQA = resolveStreamRoute()

  rule(
    "HT.livingroom.switch:key == '" .. BUTTON_NUMBER .. ":Pressed' => streamRouteToggle()",
    {name = MODULE_NAME .. ".Livingroom.Button2.Toggle"}
  )

  rule(
    "HT.livingroom.switch:key == '" .. BUTTON_NUMBER .. ":HeldDown' => streamRouteDisable()",
    {name = MODULE_NAME .. ".Livingroom.Button2.Disable"}
  )

  -- StreamRoute changes its log property only after UniFi has confirmed the
  -- resulting routing state, so the LED represents confirmed US routing.
  rule([[
    #device{id=StreamRouteQA, property='log'} => streamRouteSyncLed()
  ]], {
    name = MODULE_NAME .. ".ConfirmedState.LedSync"
  })

  -- Synchronize the LED when EventRunner starts.
  rule("post(#streamRouteLedSync)")
  rule("#streamRouteLedSync => streamRouteSyncLed()", {
    name = MODULE_NAME .. ".Startup.LedSync"
  })

  fibaro.debug(MODULE_NAME, "Loaded " .. MODULE_NAME .. " v" .. VERSION)
end

if ENABLED then
  MODULE[#MODULE + 1] = {
    name = MODULE_NAME,
    prio = 20,
    code = setup,
  }
end
