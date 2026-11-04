MZMechanicContracts = MZMechanicContracts or {}

local Contracts = MZMechanicContracts

Contracts.SchemaVersion = 1
Contracts.TerminalStates = { completed = true, cancelled = true, failed = true }
Contracts.Transitions = {
  created = { diagnosed = true, cancelled = true, failed = true },
  diagnosed = { quoted = true, cancelled = true, failed = true },
  quoted = { accepted = true, cancelled = true, failed = true },
  accepted = { in_progress = true, cancelled = true, failed = true },
  in_progress = { pending_apply = true, pending_reconciliation = true, failed = true },
  pending_apply = { completed = true, pending_reconciliation = true, failed = true },
  pending_reconciliation = { completed = true, failed = true }
}

local actionFields = {
  getContext = { netId = true, requestId = true, view = true },
  requestRepair = { netId = true, requestKey = true },
  createOrder = { netId = true, workshopCode = true, requestKey = true },
  beginCustomization = { netId = true },
  quoteCustomization = { orderId = true, revision = true, requestKey = true, token = true, items = true },
  toggleDuty = { workshopCode = true, duty = true },
  acceptOrder = { orderId = true, revision = true, requestKey = true },
  diagnoseOrder = { orderId = true, revision = true, requestKey = true },
  acceptQuote = { orderId = true, revision = true, requestKey = true },
  executeOrder = { orderId = true, revision = true, requestKey = true },
  cancelOrder = { orderId = true, revision = true, requestKey = true, reason = true },
  confirmApply = { orderId = true, token = true, netId = true, applied = true }
}

local function trim(value)
  return tostring(value or ''):gsub('^%s+', ''):gsub('%s+$', '')
end

local function integer(value, minimum, maximum)
  value = tonumber(value)
  if not value or value ~= value or value == math.huge or value == -math.huge
      or value % 1 ~= 0 or value < minimum or value > maximum then return nil end
  return math.floor(value)
end

local function token(value, minimum, maximum)
  value = trim(value)
  if #value < minimum or #value > maximum or not value:match('^[%w_:%-]+$') then return nil end
  return value
end

local function closed(value, fields)
  if type(value) ~= 'table' then return false end
  for key in pairs(value) do if fields[key] ~= true then return false end end
  return true
end

function Contracts.CanTransition(fromState, toState)
  fromState, toState = trim(fromState), trim(toState)
  return Contracts.Transitions[fromState] and Contracts.Transitions[fromState][toState] == true or false
end

function Contracts.ValidateIntent(action, value)
  local fields = actionFields[action]
  if not fields or not closed(value, fields) then return nil, 'invalid_payload' end
  value = value or {}

  if action == 'getContext' then
    local netId = value.netId == nil and 0 or integer(value.netId, 0, 2147483647)
    local requestId = value.requestId == nil and 0 or integer(value.requestId, 1, 2147483647)
    local view = value.view == nil and 'atendimento' or trim(value.view)
    if not netId then return nil, 'invalid_net_id' end
    if not requestId then return nil, 'invalid_request_id' end
    if view ~= 'atendimento' and view ~= 'tuning' then return nil, 'invalid_view' end
    return { netId = netId, requestId = requestId, view = view }
  end

  if action == 'createOrder' then
    local netId = integer(value.netId, 1, 2147483647)
    local workshopCode = token(value.workshopCode, 2, 48)
    local requestKey = token(value.requestKey, 16, 64)
    if not netId then return nil, 'invalid_net_id' end
    if not workshopCode then return nil, 'invalid_workshop' end
    if not requestKey then return nil, 'invalid_request_key' end
    return { netId = netId, workshopCode = workshopCode, requestKey = requestKey }
  end

  if action == 'requestRepair' then
    local netId = integer(value.netId, 1, 2147483647)
    local requestKey = token(value.requestKey, 16, 64)
    if not netId then return nil, 'invalid_net_id' end
    if not requestKey then return nil, 'invalid_request_key' end
    return { netId = netId, requestKey = requestKey }
  end

  if action == 'beginCustomization' then
    local netId = integer(value.netId, 1, 2147483647)
    if not netId then return nil, 'invalid_net_id' end
    return { netId = netId }
  end

  if action == 'quoteCustomization' then
    local orderId = token(value.orderId, 8, 40)
    local revision = integer(value.revision, 1, 2147483647)
    local requestKey = token(value.requestKey, 16, 64)
    local previewToken = token(value.token, 24, 64)
    local limit = tonumber(MZMechanicConfig.Customization and MZMechanicConfig.Customization.MaxItems) or 16
    if not orderId then return nil, 'invalid_order_id' end
    if not revision then return nil, 'invalid_revision' end
    if not requestKey then return nil, 'invalid_request_key' end
    if not previewToken then return nil, 'invalid_preview_token' end
    if type(value.items) ~= 'table' or #value.items < 1 or #value.items > limit then return nil, 'invalid_customization_items' end
    local items, seen = {}, {}
    for index, item in ipairs(value.items) do
      if not closed(item, { code = true, value = true }) then return nil, 'invalid_customization_item' end
      local code = token(item.code, 2, 48)
      if not code or seen[code] then return nil, 'invalid_customization_item' end
      local itemValue = item.value
      if type(itemValue) == 'number' then itemValue = integer(itemValue, -1, 0xffffff) end
      if type(itemValue) ~= 'boolean' and type(itemValue) ~= 'number' then return nil, 'invalid_customization_value' end
      seen[code] = true
      items[index] = { code = code, value = itemValue }
    end
    return { orderId = orderId, revision = revision, requestKey = requestKey, token = previewToken, items = items }
  end

  if action == 'toggleDuty' then
    local workshopCode = token(value.workshopCode, 2, 48)
    if not workshopCode or type(value.duty) ~= 'boolean' then return nil, 'invalid_payload' end
    return { workshopCode = workshopCode, duty = value.duty }
  end

  local orderId = token(value.orderId, 8, 40)
  if not orderId then return nil, 'invalid_order_id' end

  if action == 'confirmApply' then
    local applyToken = token(value.token, 24, 64)
    local netId = integer(value.netId, 1, 2147483647)
    if not applyToken or not netId or type(value.applied) ~= 'boolean' then return nil, 'invalid_payload' end
    return { orderId = orderId, token = applyToken, netId = netId, applied = value.applied }
  end

  local revision = integer(value.revision, 1, 2147483647)
  local requestKey = token(value.requestKey, 16, 64)
  if not revision then return nil, 'invalid_revision' end
  if not requestKey then return nil, 'invalid_request_key' end

  local normalized = { orderId = orderId, revision = revision, requestKey = requestKey }
  if action == 'cancelOrder' then
    local reason = trim(value.reason):gsub('%c', ' '):gsub('%s+', ' '):sub(1, 120)
    if #reason < 3 then return nil, 'invalid_reason' end
    normalized.reason = reason
  end
  return normalized
end

function Contracts.CalculateQuote(diagnostic, services)
  diagnostic, services = type(diagnostic) == 'table' and diagnostic or {}, services or {}
  local engine = math.max(0, math.min(1000, tonumber(diagnostic.engine) or 1000))
  local body = math.max(0, math.min(1000, tonumber(diagnostic.body) or 1000))
  local damage = math.ceil(((1000 - engine) + (1000 - body)) / 10)
  local definition = services.full_repair or {}
  if definition.enabled ~= true or damage <= 0 then
    return { services = {}, total = 0, available = false, reason = damage <= 0 and 'vehicle_not_damaged' or 'service_unavailable' }
  end
  local total = math.floor((tonumber(definition.basePrice) or 0) + damage * (tonumber(definition.pricePerDamagePoint) or 0))
  total = math.max(1, math.min(math.floor(tonumber(definition.maxPrice) or total), total))
  return {
    services = { { code = 'full_repair', label = tostring(definition.label or 'Reparo completo'), price = total } },
    total = total,
    available = true
  }
end

function Contracts.OperationKey(prefix, value)
  prefix = token(prefix, 2, 16) or 'op'
  value = trim(value):gsub('[^%w_-]', '_')
  return (prefix .. '_' .. value):sub(1, 64)
end

function Contracts.Fingerprint(action, orderId, revision)
  return ('action=%s;order=%s;revision=%s'):format(trim(action), trim(orderId), tostring(revision or 0))
end

