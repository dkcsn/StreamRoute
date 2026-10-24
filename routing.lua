StreamRouteModes = {
  US = "US",
  DK = "DK",
  NONE = "NONE",
  CONFLICT = "CONFLICT",
}

local function asString(value)
  if value == nil then return "" end
  return tostring(value)
end

local function findUniqueRoute(routes, name)
  local found = nil
  local count = 0
  for _, route in ipairs(routes or {}) do
    if route.description == name then
      found = route
      count = count + 1
    end
  end
  if count == 0 then return nil, "Reglen '" .. name .. "' blev ikke fundet" end
  if count > 1 then return nil, "Flere regler hedder '" .. name .. "'" end
  return found, nil
end

local function validateTarget(route, sourceNetworkId)
  local targets = route.target_devices
  if type(targets) ~= "table" or #targets ~= 1 then
    return false, route.description .. " skal have præcis ét source-netværk"
  end
  local target = targets[1]
  if target.type ~= "NETWORK" or asString(target.network_id) ~= sourceNetworkId then
    return false, route.description .. " peger ikke kun på TV-SmartDNS"
  end
  return true, nil
end

local function validateRoute(route, expectedInterfaceId, sourceNetworkId)
  if route.matching_target ~= "INTERNET" then
    return false, route.description .. " er ikke en All Traffic/Internet-regel"
  end
  if asString(route.network_id) ~= expectedInterfaceId then
    return false, route.description .. " peger på et uventet interface"
  end
  return validateTarget(route, sourceNetworkId)
end

local function classifyMode(usRoute, dkRoute)
  local usEnabled = usRoute.enabled == true
  local dkEnabled = dkRoute.enabled == true
  if usEnabled and not dkEnabled then return StreamRouteModes.US end
  if dkEnabled and not usEnabled then return StreamRouteModes.DK end
  if not usEnabled and not dkEnabled then return StreamRouteModes.NONE end
  return StreamRouteModes.CONFLICT
end

local function normalizeRequestedMode(mode)
  if mode == true or mode == 1 then return StreamRouteModes.US end
  if mode == false or mode == 0 then return StreamRouteModes.NONE end
  if type(mode) ~= "string" then return nil end

  local normalized = mode:upper():gsub("^%s+", ""):gsub("%s+$", "")
  if normalized == "US" or normalized == "USA" or normalized == "ON" then
    return StreamRouteModes.US
  end
  if normalized == "DK" or normalized == "DENMARK" or normalized == "DANMARK" then
    return StreamRouteModes.DK
  end
  if normalized == "OFF" or normalized == "NONE" or normalized == "DISABLED" then
    return StreamRouteModes.NONE
  end
  return nil
end

function QuickApp:setStatus(mode, detail)
  local labels = {
    [StreamRouteModes.US] = "Tilstand: USA via US_Tunnel",
    [StreamRouteModes.DK] = "Tilstand: Danmark via Internet 1",
    [StreamRouteModes.NONE] = "Tilstand: Normal routing (begge PBR pauset)",
    [StreamRouteModes.CONFLICT] = "Tilstand: FEJL - begge PBR-regler er aktive",
  }
  self.mode = mode
  self:updateView("modeLabel", "text", labels[mode] or "Tilstand: Ukendt")
  self:updateView("detailLabel", "text", detail or "")
  self:updateProperty("log", labels[mode] or "Ukendt")
  self:updateStreamRouteIcon(mode)
end

function QuickApp:setError(message)
  self.mode = nil
  self:updateView("modeLabel", "text", "Tilstand: FEJL")
  self:updateView("detailLabel", "text", tostring(message))
  self:updateProperty("log", "Tilstand: FEJL - " .. tostring(message))
  self:updateStreamRouteIcon(StreamRouteModes.DK)
  self:error(message)
end

function QuickApp:loadAndValidateRoutes(callback)
  self.client:listRoutes(function(ok, result)
    if not ok then callback(false, result); return end
    if type(result) ~= "table" then
      callback(false, "UniFi returnerede ikke en liste med routes")
      return
    end

    local usRoute, usError = findUniqueRoute(result, self.config.usRouteName)
    if not usRoute then callback(false, usError); return end
    local dkRoute, dkError = findUniqueRoute(result, self.config.dkRouteName)
    if not dkRoute then callback(false, dkError); return end

    local identityOk, identityError = StreamRouteConfig.ensureRoutingIdentity(
      self, self.config, usRoute, dkRoute
    )
    if not identityOk then callback(false, identityError); return end

    local validUs, validUsError = validateRoute(
      usRoute, self.config.usInterfaceId, self.config.sourceNetworkId
    )
    if not validUs then callback(false, validUsError); return end
    local validDk, validDkError = validateRoute(
      dkRoute, self.config.dkInterfaceId, self.config.sourceNetworkId
    )
    if not validDk then callback(false, validDkError); return end
    callback(true, { us = usRoute, dk = dkRoute })
  end)
end

function QuickApp:refreshState(callback)
  if self.busy then
    if callback then callback(false, "Et skift er allerede i gang") end
    return
  end
  self:loadAndValidateRoutes(function(ok, result)
    if not ok then
      self:setError(result)
      if callback then callback(false, result) end
      return
    end
    self.routes = result
    local mode = classifyMode(result.us, result.dk)
    self:setStatus(mode, "Kontrolleret " .. os.date("%H:%M:%S"))
    if callback then callback(true, mode) end
  end)
end

function QuickApp:writeRoute(route, enabled, callback)
  self.client:updateRoute(route, enabled, function(ok, result)
    if not ok then callback(false, result); return end
    callback(true, result)
  end)
end

function QuickApp:finishSwitch(targetMode)
  self:loadAndValidateRoutes(function(ok, result)
    self.busy = false
    if not ok then self:setError(result); return end
    self.routes = result
    local actualMode = classifyMode(result.us, result.dk)
    if actualMode ~= targetMode then
      self:setStatus(actualMode, "Verifikation fejlede: ønskede " .. targetMode)
      self:error("UniFi bekræftede ikke den ønskede routingtilstand")
      return
    end
    self:setStatus(actualMode, "Skift bekræftet " .. os.date("%H:%M:%S"))
    self:debug("Routing skiftet til " .. targetMode)
  end)
end

function QuickApp:rollbackRoute(route, originalEnabled, reason)
  self:warning("Andet route-kald fejlede; forsøger rollback")
  self:writeRoute(route, originalEnabled, function()
    self.busy = false
    self:setError(reason .. " (rollback forsøgt)")
  end)
end

function QuickApp:disableAllRoutes(routes)
  local usWasEnabled = routes.us.enabled == true
  local function disableDenmark()
    if routes.dk.enabled ~= true then self:finishSwitch(StreamRouteModes.NONE); return end
    self:writeRoute(routes.dk, false, function(ok, errorMessage)
      if not ok then
        if usWasEnabled then self:rollbackRoute(routes.us, true, errorMessage)
        else self.busy = false; self:setError(errorMessage) end
        return
      end
      self:finishSwitch(StreamRouteModes.NONE)
    end)
  end
  if routes.us.enabled ~= true then disableDenmark(); return end
  self:writeRoute(routes.us, false, function(ok, errorMessage)
    if not ok then self.busy = false; self:setError(errorMessage); return end
    disableDenmark()
  end)
end

function QuickApp:applyMode(targetMode, routes)
  if targetMode == StreamRouteModes.NONE then self:disableAllRoutes(routes); return end
  local primary = targetMode == StreamRouteModes.US and routes.us or routes.dk
  local secondary = targetMode == StreamRouteModes.US and routes.dk or routes.us
  local originalPrimary = primary.enabled == true

  local function disableSecondary()
    if secondary.enabled ~= true then self:finishSwitch(targetMode); return end
    self:writeRoute(secondary, false, function(ok, errorMessage)
      if not ok then self:rollbackRoute(primary, originalPrimary, errorMessage); return end
      self:finishSwitch(targetMode)
    end)
  end

  if primary.enabled == true then disableSecondary(); return end
  self:writeRoute(primary, true, function(ok, errorMessage)
    if not ok then self.busy = false; self:setError(errorMessage); return end
    disableSecondary()
  end)
end

function QuickApp:requestMode(targetMode)
  if self.busy then self:warning("Ignorerer tryk: et skift er allerede i gang"); return end
  self.busy = true
  self:updateView("detailLabel", "text", "Skifter routing...")
  self:loadAndValidateRoutes(function(ok, result)
    if not ok then self.busy = false; self:setError(result); return end
    self:applyMode(targetMode, result)
  end)
end

function QuickApp:setMode(mode)
  local normalized = normalizeRequestedMode(mode)
  if not normalized then self:setError("Ugyldig mode. Brug DK, US eller OFF"); return end
  self:requestMode(normalized)
end
