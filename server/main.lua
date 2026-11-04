local callbacks = {
  ['mz_mechanic:server:getContext'] = MZMechanicService.GetContext,
  ['mz_mechanic:server:requestRepair'] = MZMechanicService.RequestRepair,
  ['mz_mechanic:server:beginCustomization'] = MZMechanicService.BeginCustomization,
  ['mz_mechanic:server:quoteCustomization'] = MZMechanicService.QuoteCustomization,
  ['mz_mechanic:server:toggleDuty'] = MZMechanicService.ToggleDuty,
  ['mz_mechanic:server:acceptQuote'] = MZMechanicService.AcceptQuote,
  ['mz_mechanic:server:cancelOrder'] = MZMechanicService.CancelOrder,
  ['mz_mechanic:server:confirmApply'] = MZMechanicService.ConfirmApply
}

local lastCall = {}
local tracedCallbacks = {
  ['mz_mechanic:server:getContext'] = true,
  ['mz_mechanic:server:requestRepair'] = true,
  ['mz_mechanic:server:confirmApply'] = true
}

local function debugCallback(name, source, payload, stage, result)
  if MZMechanicConfig.Debug ~= true or tracedCallbacks[name] ~= true then return end
  local requestId = type(payload) == 'table' and tonumber(payload.requestId) or nil
  local pending = stage == 'received'
  print(('[mz_mechanic][callback] action=%s request=%s source=%s source_type=%s stage=%s result_type=%s ok=%s error=%s'):format(
    tostring(name), tostring(requestId or 0), tostring(source), type(source), tostring(stage), pending and 'pending' or type(result),
    pending and 'pending' or tostring(type(result) == 'table' and result.ok == true),
    tostring(type(result) == 'table' and result.error or 'none')
  ))
end

for name, handler in pairs(callbacks) do
  lib.callback.register(name, function(source, payload)
    debugCallback(name, source, payload, 'received')
    source = tonumber(source)
    if not source or source <= 0 or source % 1 ~= 0 then
      local rejected = { ok = false, error = 'invalid_source' }
      debugCallback(name, source, payload, 'rejected', rejected)
      return rejected
    end
    source = math.floor(source)
    local now = GetGameTimer()
    local key = ('%s:%s'):format(source, name)
    if now - (lastCall[key] or -10000) < 250 then
      local rejected = { ok = false, error = 'rate_limited' }
      debugCallback(name, source, payload, 'rate_limit', rejected)
      return rejected
    end
    lastCall[key] = now
    local ok, result = xpcall(function() return handler(source, payload or {}) end, debug.traceback)
    if not ok then
      print(('[mz_mechanic] callback=%s source=%s failed: %s'):format(name, source, tostring(result)))
      return { ok = false, error = 'internal_error' }
    end
    result = type(result) == 'table' and result or { ok = false, error = 'invalid_service_response' }
    debugCallback(name, source, payload, 'response', result)
    return result
  end)
end

print('[mz_mechanic] atendimento instantaneo ready')

AddEventHandler('playerDropped', function()
  local prefix = tostring(source) .. ':'
  for key in pairs(lastCall) do
    if key:sub(1, #prefix) == prefix then lastCall[key] = nil end
  end
  MZMechanicService.HandlePlayerDrop(source)
end)

exports('GetMechanicCapabilities', function()
  local capabilities = MZMechanicAdapters.Capabilities()
  capabilities.m1 = true
  capabilities.customization = MZMechanicConfig.Customization.Enabled == true and capabilities.vehicles == true
  capabilities.customDecals = false
  return capabilities
end)

