UnifiClient = {}
UnifiClient.__index = UnifiClient

local function trimTrailingSlashes(value)
  return tostring(value or ""):gsub("/+$", "")
end

local function decodeJson(data)
  if type(data) == "table" then return true, data end
  local ok, decoded = pcall(json.decode, data or "")
  if not ok then return false, "Ugyldigt JSON-svar fra UniFi" end
  return true, decoded
end

function UnifiClient.new(config)
  local self = setmetatable({}, UnifiClient)
  self.baseUrls = {}
  for _, url in ipairs(config.baseUrls or {}) do
    local normalized = trimTrailingSlashes(url)
    if normalized ~= "" then self.baseUrls[#self.baseUrls + 1] = normalized end
  end
  self.site = tostring(config.site or "default")
  self.apiKey = tostring(config.apiKey or "")
  self.timeoutMs = tonumber(config.timeoutMs) or 12000
  self.http = net.HTTPClient({ timeout = self.timeoutMs })
  return self
end

function UnifiClient:routesPath()
  return "/proxy/network/v2/api/site/" .. self.site .. "/trafficroutes"
end

function UnifiClient:request(method, path, body, callback)
  local headers = {
    ["Accept"] = "application/json",
    ["X-API-Key"] = self.apiKey,
  }
  local payload = nil
  if body ~= nil then
    headers["Content-Type"] = "application/json"
    payload = json.encode(body)
  end

  local function attempt(index, lastError)
    local baseUrl = self.baseUrls[index]
    if not baseUrl then
      callback(false, lastError or "Ingen UniFi-controlleradresse")
      return
    end

    self.http:request(baseUrl .. path, {
      options = {
        method = method,
        headers = headers,
        data = payload,
        timeout = self.timeoutMs,
        checkCertificate = false,
      },
      success = function(response)
        local status = tonumber(response.status) or 0
        if status < 200 or status >= 300 then
          attempt(index + 1, "UniFi HTTP " .. tostring(status))
          return
        end

        local ok, decoded = decodeJson(response.data)
        if not ok then
          attempt(index + 1, decoded)
          return
        end

        if index > 1 then
          self.baseUrls[1], self.baseUrls[index] = self.baseUrls[index], self.baseUrls[1]
        end
        callback(true, decoded, status)
      end,
      error = function(message)
        attempt(index + 1, "UniFi-forbindelse: " .. tostring(message))
      end,
    })
  end

  attempt(1, nil)
end

function UnifiClient:listRoutes(callback)
  self:request("GET", self:routesPath(), nil, callback)
end

function UnifiClient:updateRoute(route, enabled, callback)
  route.enabled = enabled == true
  local routeId = tostring(route._id or "")
  if routeId == "" then
    callback(false, "Route mangler _id")
    return
  end
  self:request("PUT", self:routesPath() .. "/" .. routeId, route, callback)
end
