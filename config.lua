StreamRouteConfig = {}

local STORAGE_KEY = "sr_config"
local SECRET_TYPE = "password"
local QUICKAPP_UUID = "089576b5-83a3-4456-a05f-754afdb7ca77"
local QUICKAPP_MANUFACTURER = "Christian Søgaard"
local QUICKAPP_MODEL = "StreamRoute 1.3.1"

local DEFAULT_CONFIG = {
  schemaVersion = 1,
  site = "default",
  pollSeconds = 60,
  timeoutMs = 12000,
  sourceNetworkId = "",
  usRouteName = "TV-ProtonVPN",
  usInterfaceId = "",
  dkRouteName = "Netflix-DK",
  dkInterfaceId = "",
}

local function copyTable(value)
  return json.decode(json.encode(value))
end

local function trim(value)
  return tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local function normalizeControllerUrl(value)
  local url = trim(value)
  if url == "" then return nil end
  if not url:match("^https?://") then url = "https://" .. url end
  return url:gsub("/+$", "")
end

local function decodeStoredConfig(raw)
  if type(raw) == "table" then return raw end
  if type(raw) ~= "string" or raw == "" then return nil end
  local ok, decoded = pcall(json.decode, raw)
  if ok and type(decoded) == "table" then return decoded end
  return nil
end

local function mergeDefaults(stored)
  local config = copyTable(DEFAULT_CONFIG)
  for key, value in pairs(stored or {}) do
    if config[key] ~= nil then config[key] = value end
  end
  return config
end

local function findDefaultGateway()
  local network, status = api.get("/settings/network")
  if tonumber(status) ~= 200 or type(network) ~= "table" then return nil end

  local interfaces = network.networkConfig or {}
  local preferred = { "eth0", "wlan0", "wlan1" }
  for _, name in ipairs(preferred) do
    local interface = interfaces[name]
    local ipConfig = interface and interface.ipConfig
    if interface and interface.enabled == true and ipConfig and ipConfig.gateway then
      return trim(ipConfig.gateway)
    end
  end

  for _, interface in pairs(interfaces) do
    local ipConfig = interface and interface.ipConfig
    if interface and interface.enabled == true and ipConfig and ipConfig.gateway then
      return trim(ipConfig.gateway)
    end
  end
  return nil
end

function StreamRouteConfig.ensureQuickAppMetadata(qa)
  local required = {
    quickAppUuid = QUICKAPP_UUID,
    manufacturer = QUICKAPP_MANUFACTURER,
    model = QUICKAPP_MODEL,
  }
  local changed = false

  for propertyName, expectedValue in pairs(required) do
    if trim(qa.properties[propertyName]) ~= expectedValue then
      local _, updateStatus = api.post("/plugins/updateProperty", {
        deviceId = qa.id,
        propertyName = propertyName,
        value = expectedValue,
      })
      local status = tonumber(updateStatus)
      if not status or status < 200 or status >= 300 then
        return false, "QuickApp metadata kunne ikke gemmes: " .. propertyName
      end
      changed = true
    end
  end

  local device, readStatus = api.get("/devices/" .. qa.id)
  local properties = device and device.properties or {}
  if tonumber(readStatus) ~= 200 then
    return false, "QuickApp metadata kunne ikke læses tilbage"
  end
  for propertyName, expectedValue in pairs(required) do
    if trim(properties[propertyName]) ~= expectedValue then
      return false, "QuickApp metadata kunne ikke verificeres: " .. propertyName
    end
    qa.properties[propertyName] = expectedValue
  end

  if changed then
    qa:debug("QuickApp UUID, developer og model repareret og verificeret")
  end
  return true, nil
end

function StreamRouteConfig.ensureSecretVariable(qa, variableName)
  local variables = qa.properties.quickAppVariables or {}
  for _, variable in ipairs(variables) do
    if variable.name == variableName then
      if variable.type ~= SECRET_TYPE then
        variable.type = SECRET_TYPE
        local _, status = api.put("/devices/" .. qa.id, {
          properties = { quickAppVariables = variables },
        })
        if tonumber(status) and tonumber(status) >= 300 then
          qa:warning("Kunne ikke ændre " .. variableName .. " til Secret")
        else
          qa:debug(variableName .. " er sikret som native HC3 Secret")
        end
      end
      return
    end
  end
  qa:warning(variableName .. " findes ikke under Variables")
end

function StreamRouteConfig.load(qa)
  local stored = decodeStoredConfig(qa:internalStorageGet(STORAGE_KEY))
  local config = mergeDefaults(stored)
  qa:internalStorageSet(STORAGE_KEY, json.encode(config), true)
  local verified = decodeStoredConfig(qa:internalStorageGet(STORAGE_KEY))
  if not verified then
    return nil, "Hidden internal storage kunne ikke verificeres"
  end
  return mergeDefaults(verified), nil
end

local function saveConfig(qa, config)
  qa:internalStorageSet(STORAGE_KEY, json.encode(config), true)
  local verified = decodeStoredConfig(qa:internalStorageGet(STORAGE_KEY))
  if not verified then return nil, "Hidden internal storage could not be verified" end
  return mergeDefaults(verified), nil
end

function StreamRouteConfig.ensureRoutingIdentity(qa, config, usRoute, dkRoute)
  local hasSource = trim(config.sourceNetworkId) ~= ""
  local hasUs = trim(config.usInterfaceId) ~= ""
  local hasDk = trim(config.dkInterfaceId) ~= ""
  if hasSource and hasUs and hasDk then return true, nil end
  if hasSource or hasUs or hasDk then
    return false, "Internal routing identity is incomplete; run relearnRoutingIdentity"
  end

  local usTargets = usRoute.target_devices
  local dkTargets = dkRoute.target_devices
  if type(usTargets) ~= "table" or #usTargets ~= 1 or
     type(dkTargets) ~= "table" or #dkTargets ~= 1 then
    return false, "Both policies must have exactly one source network"
  end

  local usTarget = usTargets[1]
  local dkTarget = dkTargets[1]
  local sourceId = trim(usTarget.network_id)
  local usInterfaceId = trim(usRoute.network_id)
  local dkInterfaceId = trim(dkRoute.network_id)
  if usTarget.type ~= "NETWORK" or dkTarget.type ~= "NETWORK" or
     sourceId == "" or sourceId ~= trim(dkTarget.network_id) then
    return false, "The two policies must use the same single source network"
  end
  if usInterfaceId == "" or dkInterfaceId == "" or usInterfaceId == dkInterfaceId then
    return false, "The US and Denmark policies must use different interfaces"
  end

  config.sourceNetworkId = sourceId
  config.usInterfaceId = usInterfaceId
  config.dkInterfaceId = dkInterfaceId
  local saved, saveError = saveConfig(qa, config)
  if not saved then return false, saveError end
  qa.config = saved
  qa:debug("Routing identity learned and stored internally")
  return true, nil
end

function StreamRouteConfig.clearRoutingIdentity(qa, config)
  config.sourceNetworkId = ""
  config.usInterfaceId = ""
  config.dkInterfaceId = ""
  local saved, saveError = saveConfig(qa, config)
  if not saved then return false, saveError end
  qa.config = saved
  return true, nil
end

function StreamRouteConfig.controllerUrls(qa)
  local urls = {}
  local gateway = findDefaultGateway()
  local manual = normalizeControllerUrl(qa:getVariable("UNIFI_CONTROLLER"))

  if gateway and gateway ~= "" then
    urls[#urls + 1] = normalizeControllerUrl(gateway)
  end
  if manual and manual ~= urls[1] then
    urls[#urls + 1] = manual
  end

  if #urls == 0 then
    return nil, "Default gateway kunne ikke findes; angiv UNIFI_CONTROLLER"
  end
  return urls, nil
end
