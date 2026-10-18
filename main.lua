--%%name:StreamRoute Netflix DK-USA
--%%type:com.fibaro.deviceController
--%%uid:089576b5-83a3-4456-a05f-754afdb7ca77
--%%manufacturer:Christian Søgaard
--%%model:StreamRoute 1.3.0
--%%description:Skifter TV-SmartDNS mellem Internet 1 (DK), US_Tunnel (USA) og normal routing
--%%file:icon.lua,icon
--%%file:config.lua,config
--%%file:unifi.lua,unifi
--%%file:routing.lua,routing
--%%file:documentation.lua,documentation

-- UNIFI_API_KEY skal have HC3-typen "password" (Secret).
-- Koden retter automatisk typen ved første start, hvis et værktøj har oprettet
-- variablen som en almindelig string.
--%%var:UNIFI_API_KEY=""
-- Valgfri fallback. Tom værdi betyder: brug HC3'ens default gateway.
--%%var:UNIFI_CONTROLLER=""

--%%u:{label="modeLabel",text="Tilstand: Starter..."}
--%%u:{label="detailLabel",text="UniFi: ikke kontrolleret"}
--%%u:{{button="btnDk",text="Danmark",onReleased="selectDenmark"},{button="btnUs",text="USA",onReleased="selectUsa"}}
--%%u:{button="btnDisable",text="PBR fra",onReleased="disablePolicies"}
--%%u:{button="btnRefresh",text="Opdater status",onReleased="refreshButton"}

function QuickApp:turnOn()
  self:setMode(StreamRouteModes.US)
end

function QuickApp:turnOff()
  self:setMode(StreamRouteModes.NONE)
end

function QuickApp:selectUsa()
  self:setMode(StreamRouteModes.US)
end

function QuickApp:selectDenmark()
  self:setMode(StreamRouteModes.DK)
end

function QuickApp:disablePolicies()
  self:setMode(StreamRouteModes.NONE)
end

function QuickApp:refreshButton()
  self:refreshState()
end

function QuickApp:relearnRoutingIdentity()
  local ok, errorMessage = StreamRouteConfig.clearRoutingIdentity(self, self.config)
  if not ok then
    self:setError(errorMessage)
    return
  end
  self:refreshState()
end

function QuickApp:onInit()
  self.busy = false
  self.mode = nil

  self:ensureStreamRouteIcon()

  StreamRouteConfig.ensureSecretVariable(self, "UNIFI_API_KEY")
  local config, configError = StreamRouteConfig.load(self)
  if not config then
    self:setError(configError)
    return
  end
  self.config = config

  local apiKey = tostring(self:getVariable("UNIFI_API_KEY") or "")
  if apiKey == "" then
    self:setError("Angiv UNIFI_API_KEY som Secret under Variables")
    return
  end

  local controllerUrls, controllerError = StreamRouteConfig.controllerUrls(self)
  if not controllerUrls then
    self:setError(controllerError)
    return
  end

  self.client = UnifiClient.new({
    baseUrls = controllerUrls,
    apiKey = apiKey,
    site = self.config.site,
    timeoutMs = self.config.timeoutMs,
  })

  self:debug("StreamRoute 1.3.0 startet; hidden internal storage verificeret")
  self:refreshState()
  setInterval(function()
    if not self.busy then self:refreshState() end
  end, math.max(15, self.config.pollSeconds) * 1000)
end
