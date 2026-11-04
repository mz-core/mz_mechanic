MZMechanicService = MZMechanicService or {}

local Service = MZMechanicService
local Contracts = MZMechanicContracts
local Repository = MZMechanicRepository
local Adapters = MZMechanicAdapters
local StandaloneDuty = {}
local KnownIdentities = {}
local PreviewPermits = {}
local InstantServices = {}
local schemaReady, schemaReason = false, 'preparing'

local function debugContext(source, stage, result, netId, requestId)
  if MZMechanicConfig.Debug ~= true then return end
  print(('[mz_mechanic][context] request=%s source=%s stage=%s result=%s vehicle_request=%s'):format(
    tostring(requestId or 0), tostring(source), tostring(stage), tostring(result or 'ok'),
    tostring((tonumber(netId) or 0) > 0)
  ))
end

local function distance(a, b)
  local dx, dy, dz = a.x - b.x, a.y - b.y, a.z - b.z
  return math.sqrt(dx * dx + dy * dy + dz * dz)
end

local function clone(value)
  if type(value) ~= 'table' then return value end
  local copy = {}
  for key, item in pairs(value) do copy[key] = clone(item) end
  return copy
end

local function customizationCatalog()
  local catalog, codes = {}, {}
  for code in pairs(MZMechanicConfig.Customization and MZMechanicConfig.Customization.Items or {}) do
    codes[#codes + 1] = code
  end
  table.sort(codes)
  for _, code in ipairs(codes) do
    local item = MZMechanicConfig.Customization.Items[code]
    catalog[#catalog + 1] = {
      code = code, label = tostring(item.label), category = tostring(item.category),
      field = tostring(item.field), slot = tonumber(item.slot), kind = tostring(item.kind),
      maxIndex = tonumber(item.maxIndex), basePrice = tonumber(item.basePrice),
      minIndex = tonumber(item.minIndex), stepPrice = tonumber(item.stepPrice),
      fixedPrice = tonumber(item.fixedPrice), key = item.key, extraId = tonumber(item.extraId),
      requiresSlot = tonumber(item.requiresSlot), counter = item.counter and tostring(item.counter) or nil,
      group = item.group and tostring(item.group) or nil,
      optionLabel = item.optionLabel and tostring(item.optionLabel) or nil,
      originalLabel = item.originalLabel and tostring(item.originalLabel) or nil
    }
  end
  return catalog
end

local function customizationValue(definition, rawValue)
  if definition.kind == 'toggle' then
    if type(rawValue) ~= 'boolean' then return nil, 'invalid_customization_value' end
    return rawValue
  end

  local value = tonumber(rawValue)
  local minIndex = definition.kind == 'rgb' and 0 or (tonumber(definition.minIndex) or -1)
  local maxIndex = definition.kind == 'rgb' and 0xffffff or (tonumber(definition.maxIndex) or 99)
  if not value or value % 1 ~= 0 or value < minIndex or value > maxIndex then
    return nil, 'invalid_customization_value'
  end
  value = math.floor(value)
  if definition.kind == 'rgb' then
    return {
      math.floor(value / 0x10000) % 0x100,
      math.floor(value / 0x100) % 0x100,
      value % 0x100
    }
  end
  return value
end

local function setCustomizationProperty(props, definition, value)
  if definition.key == nil then
    props[definition.field] = clone(value)
    return
  end
  if type(props[definition.field]) ~= 'table' then props[definition.field] = {} end
  props[definition.field][definition.key] = clone(value)
end

local function buildCustomizationQuote(vehicle, items)
  local definitions = MZMechanicConfig.Customization and MZMechanicConfig.Customization.Items or {}
  local props = clone(vehicle.persisted and vehicle.persisted.props_json or {})
  local services, total, selectedProperties = {}, 0, {}
  for _, selected in ipairs(items) do
    local definition = definitions[selected.code]
    if not definition then return nil, nil, 'customization_not_allowed' end
    local propertyId = tostring(definition.field) .. ':' .. tostring(definition.key or '')
    if selectedProperties[propertyId] then return nil, nil, 'duplicate_customization_property' end
    selectedProperties[propertyId] = true

    local value, valueErr = customizationValue(definition, selected.value)
    if valueErr then return nil, nil, valueErr end
    local price = 0
    if definition.kind == 'indexed' then
      if value >= 0 then
        price = math.floor((tonumber(definition.basePrice) or 0) + (value + 1) * (tonumber(definition.stepPrice) or 0))
      else
        price = math.floor(tonumber(definition.basePrice) or 0)
      end
    elseif definition.kind == 'toggle' then
      local fixedPrice = math.floor(tonumber(definition.fixedPrice) or 0)
      price = value and fixedPrice or math.floor(fixedPrice * 0.25)
    else
      price = math.floor(tonumber(definition.fixedPrice) or 0)
    end
    price = math.max(0, math.min(price, 1000000))
    setCustomizationProperty(props, definition, value)
    total = total + price
    services[#services + 1] = {
      code = 'custom_' .. selected.code,
      label = tostring(definition.label),
      price = price,
      customization = {
        code = selected.code, field = tostring(definition.field), slot = tonumber(definition.slot),
        key = definition.key, kind = tostring(definition.kind), value = clone(value)
      }
    }
  end
  if total <= 0 then return nil, nil, 'empty_customization_quote' end
  return { available = true, kind = 'customization', services = services, total = total }, props
end

local function workshopByCode(code)
  local workshop = MZMechanicConfig.Workshops[tostring(code or '')]
  return workshop and workshop or nil
end

local function workshopAt(coords)
  for code, workshop in pairs(MZMechanicConfig.Workshops or {}) do
    if distance(coords, workshop.coords) <= (tonumber(workshop.radius) or 30.0) then
      workshop.code = code
      return workshop
    end
  end
end

local function bayForVehicle(workshop, coords)
  local nearest, nearestDistance
  for _, bay in ipairs(workshop.bays or {}) do
    local bayDistance = distance(coords, bay.coords)
    if not nearestDistance or bayDistance < nearestDistance then
      nearest, nearestDistance = bay, bayDistance
    end
  end
  if nearest and nearestDistance <= (tonumber(nearest.radius) or 5.0) then return nearest, nearestDistance end
  return nil, nearestDistance
end

local function debugVehicleContext(workshop, vehicle, bay, bayDistance, result)
  if MZMechanicConfig.Debug ~= true then return end
  print(('[mz_mechanic][vehicle] workshop=%s bay=%s bay_distance=%.2f entity_exists=%s net_id=%s speed=%.2f result=%s'):format(
    tostring(workshop and workshop.code or 'none'), tostring(bay and bay.code or 'nearest'),
    tonumber(bayDistance) or -1, tostring(vehicle and vehicle.entity and DoesEntityExist(vehicle.entity) or false),
    tostring(vehicle and vehicle.netId or 0), tonumber(vehicle and vehicle.speed) or 0, tostring(result)
  ))
end

local function publicOrder(order)
  if not order then return nil end
  return {
    id = order.public_id,
    workshopCode = order.workshop_code,
    bayCode = order.bay_code,
    vehicle = { id = order.vehicle_id, plate = order.vehicle_plate },
    customerCitizenId = order.customer_citizenid,
    assignedMechanicCitizenId = order.assigned_mechanic_citizenid,
    state = order.state,
    revision = order.revision,
    diagnostic = order.diagnostic,
    quote = order.quote,
    payment = order.payment and {
      status = order.payment.status,
      amount = order.payment.amount
    } or nil,
    application = {
      status = order.application and order.application.status,
      netId = order.application and order.application.netId,
      kind = order.application and order.application.kind,
      itemCount = order.application and order.application.itemCount,
      engine = order.application and order.application.engine,
      body = order.application and order.application.body,
      completedAt = order.application and order.application.completedAt
    },
    failureCode = order.failure_code,
    cancelReason = order.cancel_reason,
    createdAt = order.created_at,
    updatedAt = order.updated_at,
    expiresAt = order.expires_at
  }
end

local function responseOrder(order, extra)
  local result = { ok = true, order = publicOrder(order) }
  for key, value in pairs(extra or {}) do result[key] = value end
  return result
end

local function requireReady()
  if MZMechanicConfig.Enabled ~= true then return false, 'feature_disabled' end
  return true
end

local function resolveContext(source, workshopCode, requestId)
  local identity, identityErr = Adapters.ResolveIdentity(source, requestId)
  if not identity then return nil, identityErr, 'identity' end
  KnownIdentities[source] = identity.citizenid
  local coords, coordsErr = Adapters.GetPlayerCoords(source)
  if not coords then return nil, coordsErr, 'position' end
  local workshop = workshopCode and workshopByCode(workshopCode) or workshopAt(coords)
  if not workshop then return nil, 'not_at_workshop', 'workshop' end
  workshop.code = workshopCode or workshop.code
  if distance(coords, workshop.coords) > (tonumber(workshop.radius) or 30.0) then return nil, 'too_far', 'workshop' end
  return { source = source, identity = identity, coords = coords, workshop = workshop }
end

local function mechanicStatus(source, context)
  local org, orgErr = Adapters.GetOrgMechanic(source, context.workshop)
  if org and org.linked == true then
    return {
      linked = true,
      onDuty = MZMechanicConfig.Authorization.RequireOrgDuty ~= true or org.onDuty == true,
      rawDuty = org.onDuty == true,
      mode = 'org',
      orgCode = org.orgCode,
      grade = org.grade
    }
  end

  local standalone = MZMechanicConfig.Authorization.Standalone or {}
  if standalone.Enabled == true then
    local binding = Repository.GetStandaloneBinding(context.identity.citizenid, context.workshop.code)
    if binding then
      local dutyKey = ('%s:%s'):format(source, context.workshop.code)
      return { linked = true, onDuty = StandaloneDuty[dutyKey] == true, rawDuty = StandaloneDuty[dutyKey] == true, mode = 'standalone', role = binding.role }
    end
  end
  local reason = (org and org.reason) or orgErr or 'not_mechanic'
  if reason == 'not_org_mechanic' then reason = 'not_mechanic' end
  return { linked = false, onDuty = false, mode = 'none', reason = reason }
end

local function requireMechanic(source, workshopCode)
  local context, contextErr = resolveContext(source, workshopCode)
  if not context then return nil, contextErr end
  local mechanic = mechanicStatus(source, context)
  if mechanic.linked ~= true then return nil, mechanic.reason or 'not_mechanic' end
  if mechanic.onDuty ~= true then return nil, 'not_on_duty' end
  context.mechanic = mechanic
  return context
end

local function transition(order, action, intent, actor, toState, patch, eventPayload, operationKey)
  if order.state ~= toState and not Contracts.CanTransition(order.state, toState) then return nil, 'invalid_transition' end
  return Repository.Transition(order, {
    fromState = order.state,
    toState = toState,
    expectedVersion = intent.revision or order.revision,
    operationKey = operationKey or intent.requestKey,
    fingerprint = Contracts.Fingerprint(action, order.public_id, intent.revision or order.revision),
    actorId = actor.citizenid,
    actorRole = actor.role,
    eventType = action,
    eventPayload = eventPayload,
    patch = patch
  })
end

local function validateOrderVehicle(order, context)
  local vehicle, vehicleErr = Adapters.ResolveVehicle(order.application and order.application.netId or 0)
  if not vehicle then return nil, vehicleErr or 'vehicle_not_found' end
  if vehicle.id ~= order.vehicle_id or vehicle.plate ~= order.vehicle_plate then return nil, 'vehicle_identity_mismatch' end
  if vehicle.bucket ~= GetPlayerRoutingBucket(context.source) then return nil, 'routing_bucket_mismatch' end
  if distance(context.coords, vehicle.coords) > MZMechanicConfig.Order.InteractionDistance then return nil, 'too_far_from_vehicle' end
  if not bayForVehicle(context.workshop, vehicle.coords) then return nil, 'vehicle_not_in_bay' end
  return vehicle
end

local function notifyOrder(order)
  local payload = publicOrder(order)
  local customerSource = Adapters.GetSourceByCitizenId(order.customer_citizenid)
  if customerSource then
    TriggerClientEvent('mz_mechanic:client:orderUpdated', customerSource, payload)
    if order.state == 'quoted' then
      TriggerClientEvent('mz_mechanic:client:quoteDecisionRequested', customerSource, payload)
    end
  end
  for _, source in ipairs(GetPlayers()) do
    local sourceId = tonumber(source)
    if sourceId and sourceId ~= customerSource then
      local context = requireMechanic(sourceId, order.workshop_code)
      if context then TriggerClientEvent('mz_mechanic:client:orderUpdated', sourceId, payload) end
    end
  end
end

local function audit(action, source, identity, order, result, reason)
  Adapters.Log(action, {
    actor = { type = 'player', id = identity and identity.citizenid or tostring(source), source = source },
    target = { type = 'mechanic_order', id = order and order.public_id or 'unknown' },
    context = { workshop_code = order and order.workshop_code, vehicle_id = order and order.vehicle_id },
    after = { result = result },
    meta = { reason = reason }
  })
end

function Service.SetSchemaState(ready, reason)
  schemaReady, schemaReason = ready == true, tostring(reason or (ready and 'ready' or 'schema_unavailable'))
end

function Service.GetContext(source, raw)
  local rawRequestId = type(raw) == 'table' and tonumber(raw.requestId) or nil
  local ready, readyErr = requireReady()
  if not ready then
    debugContext(source, 'resource', readyErr, raw and raw.netId, rawRequestId)
    return { ok = false, error = readyErr }
  end
  local intent, intentErr = Contracts.ValidateIntent('getContext', raw or {})
  if not intent then
    debugContext(source, 'request', intentErr, raw and raw.netId, rawRequestId)
    return { ok = false, error = intentErr }
  end
  local context, contextErr, contextStage = resolveContext(source, nil, intent.requestId)
  if not context then
    debugContext(source, contextStage or 'context', contextErr, intent.netId, intent.requestId)
    return { ok = false, error = contextErr }
  end
  local mechanic = mechanicStatus(source, context)
  debugContext(source, 'authorization', mechanic.linked and (mechanic.onDuty and 'authorized' or 'not_on_duty') or mechanic.reason, intent.netId, intent.requestId)
  local vehicle
  if intent.netId > 0 then
    local resolved, vehicleErr = Adapters.ResolveVehicle(intent.netId)
    if not resolved then
      debugContext(source, 'vehicle', vehicleErr, intent.netId, intent.requestId)
      return { ok = false, error = vehicleErr }
    end
    if resolved.bucket ~= GetPlayerRoutingBucket(source) then
      debugContext(source, 'vehicle', 'routing_bucket_mismatch', intent.netId, intent.requestId)
      return { ok = false, error = 'routing_bucket_mismatch' }
    end
    if distance(context.coords, resolved.coords) > MZMechanicConfig.Order.InteractionDistance then
      debugContext(source, 'vehicle', 'too_far_from_vehicle', intent.netId, intent.requestId)
      return { ok = false, error = 'too_far_from_vehicle' }
    end
    local bay, bayDistance = bayForVehicle(context.workshop, resolved.coords)
    if intent.view == 'tuning' and not bay then
      debugVehicleContext(context.workshop, resolved, nil, bayDistance, 'vehicle_not_in_bay')
      debugContext(source, 'vehicle', 'vehicle_not_in_bay', intent.netId, intent.requestId)
      return { ok = false, error = 'vehicle_not_in_bay' }
    end
    if intent.view == 'tuning' and (tonumber(resolved.speed) or 0) > 0.1 then
      debugVehicleContext(context.workshop, resolved, bay, bayDistance, 'vehicle_not_stopped')
      debugContext(source, 'vehicle', 'vehicle_not_stopped', intent.netId, intent.requestId)
      return { ok = false, error = 'vehicle_not_stopped' }
    end
    if intent.view == 'tuning' and resolved.state ~= 'out' then
      debugVehicleContext(context.workshop, resolved, bay, bayDistance, 'vehicle_not_out')
      debugContext(source, 'vehicle', 'vehicle_not_out', intent.netId, intent.requestId)
      return { ok = false, error = 'vehicle_not_out' }
    end
    if not (mechanic.linked and mechanic.onDuty) then
      local access, accessErr = Adapters.CanAccessVehicle(source, resolved.plate)
      if access ~= true then
        local denied = mechanic.linked and 'not_on_duty'
          or (mechanic.reason == 'missing_permission' and 'missing_permission')
          or accessErr or 'vehicle_access_denied'
        debugContext(source, 'vehicle_access', denied, intent.netId, intent.requestId)
        return { ok = false, error = denied }
      end
    end
    debugVehicleContext(context.workshop, resolved, bay, bayDistance, 'accepted')
    vehicle = {
      id = resolved.id, plate = resolved.plate, model = resolved.model, netId = resolved.netId,
      engine = resolved.engine, body = resolved.body, dirt = resolved.dirt,
      bayCode = bay and bay.code or nil, inBay = bay ~= nil
    }
  end
  local capabilities = Adapters.Capabilities()
  capabilities.schema = false
  capabilities.instantService = true
  capabilities.customization = MZMechanicConfig.Customization.Enabled == true and capabilities.vehicles == true
  debugContext(source, 'complete', 'ok', intent.netId, intent.requestId)
  return {
    ok = true,
    workshop = { code = context.workshop.code, label = context.workshop.label },
    user = { citizenId = context.identity.citizenid, isMechanic = mechanic.linked, onDuty = mechanic.onDuty, dutyMode = mechanic.mode, mechanicError = mechanic.linked and (mechanic.onDuty and nil or 'not_on_duty') or mechanic.reason },
    vehicle = vehicle,
    orders = {},
    queue = {},
    services = MZMechanicConfig.Services,
    capabilities = capabilities
  }
end

function Service.BeginCustomization(source, raw)
  local ready, readyErr = requireReady()
  if not ready then return { ok = false, error = readyErr } end
  if MZMechanicConfig.Customization.Enabled ~= true then return { ok = false, error = 'customization_disabled' } end
  local intent, intentErr = Contracts.ValidateIntent('beginCustomization', raw)
  if not intent then return { ok = false, error = intentErr } end
  local order = Repository.GetOrder(intent.orderId)
  if not order then return { ok = false, error = 'order_not_found' } end
  if order.state ~= 'created' or order.revision ~= intent.revision then return { ok = false, error = 'order_conflict' } end
  local context, contextErr = requireMechanic(source, order.workshop_code)
  if not context then return { ok = false, error = contextErr } end
  if order.assigned_mechanic_citizenid ~= context.identity.citizenid then return { ok = false, error = 'not_assigned_mechanic' } end
  local vehicle, vehicleErr = validateOrderVehicle(order, context)
  if not vehicle then return { ok = false, error = vehicleErr } end
  local token = ('preview_%08x_%08x_%08x'):format(
    os.time() % 0xffffffff, GetGameTimer() % 0xffffffff, math.random(0, 0xffffff)
  )
  local ttlSeconds = math.max(15, math.min(180, tonumber(MZMechanicConfig.Customization.PreviewTtlSeconds) or 90))
  PreviewPermits[source] = {
    token = token,
    orderId = order.public_id,
    vehicleId = order.vehicle_id,
    netId = vehicle.netId,
    expiresAt = GetGameTimer() + ttlSeconds * 1000
  }
  return {
    ok = true,
    token = token,
    orderId = order.public_id,
    revision = order.revision,
    netId = vehicle.netId,
    ttlSeconds = ttlSeconds,
    catalog = customizationCatalog()
  }
end

function Service.QuoteCustomization(source, raw)
  local intent, intentErr = Contracts.ValidateIntent('quoteCustomization', raw)
  if not intent then return { ok = false, error = intentErr } end
  local permit = PreviewPermits[source]
  if type(permit) ~= 'table' or permit.token ~= intent.token or permit.orderId ~= intent.orderId then
    return { ok = false, error = 'preview_not_authorized' }
  end
  if GetGameTimer() > permit.expiresAt then
    PreviewPermits[source] = nil
    return { ok = false, error = 'preview_expired' }
  end
  local order = Repository.GetOrder(intent.orderId)
  if not order then return { ok = false, error = 'order_not_found' } end
  if permit.lastRequestKey == intent.requestKey and order.state == 'quoted' then
    return responseOrder(order, { replayed = true })
  end
  if order.state ~= 'created' or order.revision ~= intent.revision then return { ok = false, error = 'order_conflict' } end
  local context, contextErr = requireMechanic(source, order.workshop_code)
  if not context then return { ok = false, error = contextErr } end
  if order.assigned_mechanic_citizenid ~= context.identity.citizenid then return { ok = false, error = 'not_assigned_mechanic' } end
  local vehicle, vehicleErr = validateOrderVehicle(order, context)
  if not vehicle then return { ok = false, error = vehicleErr } end
  if vehicle.id ~= permit.vehicleId or vehicle.netId ~= permit.netId then return { ok = false, error = 'vehicle_identity_mismatch' } end
  local quote, finalProps, quoteErr = buildCustomizationQuote(vehicle, intent.items)
  if not quote then return { ok = false, error = quoteErr } end
  local diagnostic = {
    engine = math.floor(vehicle.engine), body = math.floor(vehicle.body),
    dirt = vehicle.dirt, capturedAt = os.time()
  }
  local diagnosed, diagnoseErr = transition(
    order, 'customization_diagnosed', intent,
    { citizenid = context.identity.citizenid, role = 'mechanic' }, 'diagnosed', {
      diagnostic = diagnostic,
      application = {
        netId = vehicle.netId, status = 'not_started', kind = 'customization',
        props = finalProps, itemCount = #quote.services
      }
    }, { itemCount = #quote.services }, Contracts.OperationKey('custom_diag', intent.requestKey)
  )
  if not diagnosed then return { ok = false, error = diagnoseErr } end
  local quoted, quoteStateErr, replayed = transition(
    diagnosed, 'customization_quoted', { revision = diagnosed.revision, requestKey = intent.requestKey },
    { citizenid = context.identity.citizenid, role = 'mechanic' }, 'quoted',
    { quote = quote }, { total = quote.total, itemCount = #quote.services },
    Contracts.OperationKey('custom_quote', intent.requestKey)
  )
  if not quoted then return { ok = false, error = quoteStateErr } end
  permit.lastRequestKey = intent.requestKey
  notifyOrder(quoted)
  return responseOrder(quoted, { replayed = replayed == true })
end

function Service.CreateOrder(source, raw)
  local ready, readyErr = requireReady()
  if not ready then return { ok = false, error = readyErr } end
  local intent, intentErr = Contracts.ValidateIntent('createOrder', raw)
  if not intent then return { ok = false, error = intentErr } end
  local context, contextErr = resolveContext(source, intent.workshopCode)
  if not context then return { ok = false, error = contextErr } end
  local vehicle, vehicleErr = Adapters.ResolveVehicle(intent.netId)
  if not vehicle then return { ok = false, error = vehicleErr } end
  if vehicle.bucket ~= GetPlayerRoutingBucket(source) then return { ok = false, error = 'routing_bucket_mismatch' } end
  if distance(context.coords, vehicle.coords) > MZMechanicConfig.Order.InteractionDistance then return { ok = false, error = 'too_far_from_vehicle' } end
  local bay = bayForVehicle(context.workshop, vehicle.coords)
  if not bay then return { ok = false, error = 'vehicle_not_in_bay' } end
  local access, accessErr = Adapters.CanAccessVehicle(source, vehicle.plate)
  if access ~= true then return { ok = false, error = accessErr or 'vehicle_access_denied' } end
  if vehicle.state ~= 'out' then return { ok = false, error = 'vehicle_not_out' } end
  local publicId = ('mzo_%x_%x_%04x'):format(os.time(), GetGameTimer() % 0xffffff, math.random(0, 0xffff))
  local order, createErr, replayed = Repository.CreateOrder({
    publicId = publicId,
    workshopCode = context.workshop.code,
    bayCode = bay.code,
    vehicleId = vehicle.id,
    netId = vehicle.netId,
    vehiclePlate = vehicle.plate,
    customerCitizenId = context.identity.citizenid,
    requestKey = intent.requestKey,
    maxOpenOrders = MZMechanicConfig.Order.MaxOpenOrdersPerCustomer,
    ttlSeconds = MZMechanicConfig.Order.TtlSeconds,
    lockTtlSeconds = MZMechanicConfig.Order.LockTtlSeconds
  })
  if not order then return { ok = false, error = createErr } end
  audit('order.created', source, context.identity, order, replayed and 'replayed' or 'created')
  notifyOrder(order)
  return responseOrder(order, { replayed = replayed == true })
end

function Service.ToggleDuty(source, raw)
  local intent, intentErr = Contracts.ValidateIntent('toggleDuty', raw)
  if not intent then return { ok = false, error = intentErr } end
  local context, contextErr = resolveContext(source, intent.workshopCode)
  if not context then return { ok = false, error = contextErr } end
  local mechanic = mechanicStatus(source, context)
  if mechanic.linked ~= true then return { ok = false, error = 'not_mechanic' } end
  if mechanic.mode == 'org' then
    local ok, result = Adapters.SetOrgDuty(source, context.workshop, intent.duty)
    if ok ~= true then return { ok = false, error = result or 'duty_failed' } end
  else
    StandaloneDuty[('%s:%s'):format(source, context.workshop.code)] = intent.duty
  end
  return { ok = true, duty = intent.duty }
end

function Service.AcceptOrder(source, raw)
  local intent, intentErr = Contracts.ValidateIntent('acceptOrder', raw)
  if not intent then return { ok = false, error = intentErr } end
  local order = Repository.GetOrder(intent.orderId)
  if not order then return { ok = false, error = 'order_not_found' } end
  if Contracts.TerminalStates[order.state] or order.state == 'in_progress' or order.state == 'pending_apply' then return { ok = false, error = 'order_not_assignable' } end
  local context, contextErr = requireMechanic(source, order.workshop_code)
  if not context then return { ok = false, error = contextErr } end
  if order.assigned_mechanic_citizenid and order.assigned_mechanic_citizenid ~= context.identity.citizenid then return { ok = false, error = 'order_assigned' } end
  local updated, err, replayed = Repository.Assign(order, context.identity.citizenid, intent.requestKey, Contracts.Fingerprint('acceptOrder', order.public_id, intent.revision), intent.revision)
  if not updated then return { ok = false, error = err } end
  notifyOrder(updated)
  return responseOrder(updated, { replayed = replayed == true })
end

function Service.DiagnoseOrder(source, raw)
  local intent, intentErr = Contracts.ValidateIntent('diagnoseOrder', raw)
  if not intent then return { ok = false, error = intentErr } end
  local order = Repository.GetOrder(intent.orderId)
  if not order then return { ok = false, error = 'order_not_found' } end
  local context, contextErr = requireMechanic(source, order.workshop_code)
  if not context then return { ok = false, error = contextErr } end
  if order.assigned_mechanic_citizenid ~= context.identity.citizenid then return { ok = false, error = 'not_assigned_mechanic' } end
  local vehicle, vehicleErr = validateOrderVehicle(order, context)
  if not vehicle then return { ok = false, error = vehicleErr } end
  local diagnostic = { engine = math.floor(vehicle.engine), body = math.floor(vehicle.body), dirt = vehicle.dirt, capturedAt = os.time() }
  local quote = Contracts.CalculateQuote(diagnostic, MZMechanicConfig.Services)
  if quote.available ~= true then return { ok = false, error = quote.reason } end
  local diagnosed, diagnoseErr = transition(order, 'diagnosed', intent, { citizenid = context.identity.citizenid, role = 'mechanic' }, 'diagnosed', {
    diagnostic = diagnostic,
    application = { netId = vehicle.netId, status = 'not_started' }
  }, diagnostic, Contracts.OperationKey('diag', intent.requestKey))
  if not diagnosed then return { ok = false, error = diagnoseErr } end
  local quoted, quoteErr, replayed = transition(diagnosed, 'quoted', { revision = diagnosed.revision, requestKey = intent.requestKey }, { citizenid = context.identity.citizenid, role = 'mechanic' }, 'quoted', { quote = quote }, quote, Contracts.OperationKey('quote', intent.requestKey))
  if not quoted then return { ok = false, error = quoteErr } end
  notifyOrder(quoted)
  return responseOrder(quoted, { replayed = replayed == true })
end

function Service.AcceptQuote(source, raw)
  local intent, intentErr = Contracts.ValidateIntent('acceptQuote', raw)
  if not intent then return { ok = false, error = intentErr } end
  local order = Repository.GetOrder(intent.orderId)
  if not order then return { ok = false, error = 'order_not_found' } end
  local context, contextErr = resolveContext(source, order.workshop_code)
  if not context then return { ok = false, error = contextErr } end
  if context.identity.citizenid ~= order.customer_citizenid then return { ok = false, error = 'not_order_customer' } end
  local vehicle, vehicleErr = validateOrderVehicle(order, context)
  if not vehicle then return { ok = false, error = vehicleErr } end
  local access, accessErr = Adapters.CanAccessVehicle(source, vehicle.plate)
  if access ~= true then return { ok = false, error = accessErr or 'vehicle_access_denied' } end
  local updated, err, replayed = transition(order, 'accepted', intent, { citizenid = context.identity.citizenid, role = 'customer' }, 'accepted', nil, { quoteTotal = order.quote.total, vehicleId = vehicle.id })
  if not updated then return { ok = false, error = err } end
  notifyOrder(updated)
  return responseOrder(updated, { replayed = replayed == true })
end

local function finishAfterFailure(order, mechanicIdentity, reason, applied)
  local customerSource = Adapters.GetSourceByCitizenId(order.customer_citizenid)
  local payment = order.payment or {}
  if applied ~= true and customerSource and tonumber(payment.amount) and payment.amount > 0 then
    local refundKey = Contracts.OperationKey('mech_refund', order.public_id)
    local refunded, receipt = Adapters.Refund(customerSource, payment.amount, refundKey, order.public_id)
    if refunded then
      local failed = transition(order, 'apply_failed', { revision = order.revision, requestKey = refundKey }, { citizenid = mechanicIdentity.citizenid, role = 'mechanic' }, 'failed', {
        payment = { status = 'refunded', amount = payment.amount, receipt = payment.receipt, refundReceipt = receipt },
        failureCode = reason,
        releaseLock = true
      }, { reason = reason, refunded = true }, refundKey)
      return failed, reason
    end
  end
  local reconcileKey = Contracts.OperationKey('mech_reconcile', order.public_id)
  local pending = transition(order, 'reconciliation_required', { revision = order.revision, requestKey = reconcileKey }, { citizenid = mechanicIdentity.citizenid, role = 'mechanic' }, 'pending_reconciliation', {
    failureCode = reason,
    application = { status = applied and 'applied_unpersisted' or 'apply_failed', reason = reason }
  }, { reason = reason, applied = applied == true }, reconcileKey)
  return pending, reason
end

function Service.ExecuteOrder(source, raw)
  local intent, intentErr = Contracts.ValidateIntent('executeOrder', raw)
  if not intent then return { ok = false, error = intentErr } end
  local order = Repository.GetOrder(intent.orderId)
  if not order then return { ok = false, error = 'order_not_found' } end
  local context, contextErr = requireMechanic(source, order.workshop_code)
  if not context then return { ok = false, error = contextErr } end
  if order.assigned_mechanic_citizenid ~= context.identity.citizenid then return { ok = false, error = 'not_assigned_mechanic' } end
  if order.state ~= 'accepted' then return { ok = false, error = 'quote_not_accepted' } end
  local customerSource = Adapters.GetSourceByCitizenId(order.customer_citizenid)
  if not customerSource then return { ok = false, error = 'customer_offline' } end
  local vehicle, vehicleErr = validateOrderVehicle(order, context)
  if not vehicle then return { ok = false, error = vehicleErr } end
  local customerContext = resolveContext(customerSource, order.workshop_code)
  if not customerContext or customerContext.identity.citizenid ~= order.customer_citizenid then return { ok = false, error = 'customer_not_present' } end
  local customerVehicle = validateOrderVehicle(order, customerContext)
  if not customerVehicle then return { ok = false, error = 'customer_not_present' } end
  local amount = math.floor(tonumber(order.quote and order.quote.total) or 0)
  if amount <= 0 then return { ok = false, error = 'invalid_server_quote' } end
  local paymentKey = Contracts.OperationKey('mech_pay', order.public_id)
  local claimed, claimErr = transition(order, 'execution_claimed', intent, { citizenid = context.identity.citizenid, role = 'mechanic' }, 'in_progress', {
    payment = { status = 'pending', amount = amount, operationKey = paymentKey }
  }, { amount = amount }, Contracts.OperationKey('start', intent.requestKey))
  if not claimed then return { ok = false, error = claimErr } end
  local paid, receipt = Adapters.Debit(customerSource, amount, paymentKey, order.public_id)
  if not paid then
    local uncertain = receipt == 'payment_receipt_unavailable'
    local failureKey = Contracts.OperationKey(uncertain and 'pay_unknown' or 'pay_failed', order.public_id)
    local failed = transition(claimed, uncertain and 'payment_unknown' or 'payment_declined', { revision = claimed.revision, requestKey = failureKey }, { citizenid = context.identity.citizenid, role = 'mechanic' }, uncertain and 'pending_reconciliation' or 'failed', {
      payment = { status = uncertain and 'unknown' or 'declined', amount = amount, operationKey = paymentKey },
      failureCode = tostring(receipt or 'payment_failed'),
      releaseLock = not uncertain
    }, { reason = receipt }, failureKey)
    notifyOrder(failed or claimed)
    return { ok = false, error = uncertain and 'pending_reconciliation' or tostring(receipt or 'payment_failed'), order = publicOrder(failed or claimed) }
  end
  local paidOrder, paymentStateErr = transition(claimed, 'payment_confirmed', { revision = claimed.revision, requestKey = intent.requestKey }, { citizenid = context.identity.citizenid, role = 'mechanic' }, 'in_progress', {
    payment = { status = 'paid', amount = amount, operationKey = paymentKey, receipt = receipt }
  }, { amount = amount }, Contracts.OperationKey('paid', intent.requestKey))
  if not paidOrder then
    local current = Repository.GetOrder(order.public_id) or claimed
    local failed = finishAfterFailure(current, context.identity, paymentStateErr or 'payment_state_failed', false)
    notifyOrder(failed or current)
    return { ok = false, error = paymentStateErr or 'payment_state_failed', order = publicOrder(failed or current) }
  end
  local applyToken = Contracts.OperationKey('apply_token', ('%s_%x_%x'):format(order.public_id, os.time(), math.random(0, 0xffffff)))
  local pending, pendingErr = transition(paidOrder, 'apply_requested', { revision = paidOrder.revision, requestKey = intent.requestKey }, { citizenid = context.identity.citizenid, role = 'mechanic' }, 'pending_apply', {
    application = {
      status = 'pending', token = applyToken, netId = vehicle.netId, requestedAt = os.time(),
      kind = paidOrder.application and paidOrder.application.kind,
      props = paidOrder.application and paidOrder.application.props,
      itemCount = paidOrder.application and paidOrder.application.itemCount
    }
  }, { netId = vehicle.netId }, Contracts.OperationKey('apply', intent.requestKey))
  if not pending then
    local current = Repository.GetOrder(order.public_id) or paidOrder
    local failed = finishAfterFailure(current, context.identity, pendingErr or 'apply_request_failed', false)
    notifyOrder(failed or current)
    return { ok = false, error = pendingErr or 'apply_request_failed', order = publicOrder(failed or current) }
  end
  TriggerClientEvent('mz_mechanic:client:applyService', source, {
    orderId = pending.public_id,
    token = applyToken,
    netId = vehicle.netId,
    plate = vehicle.plate,
    services = pending.quote.services
  })
  notifyOrder(pending)
  return responseOrder(pending, { pending = true })
end

function Service.ConfirmApply(source, raw)
  local intent, intentErr = Contracts.ValidateIntent('confirmApply', raw)
  if not intent then return { ok = false, error = intentErr } end
  local order = Repository.GetOrder(intent.orderId)
  if not order then return { ok = false, error = 'order_not_found' } end
  local context, contextErr = requireMechanic(source, order.workshop_code)
  if not context then return { ok = false, error = contextErr } end
  if order.state ~= 'pending_apply' or order.assigned_mechanic_citizenid ~= context.identity.citizenid then return { ok = false, error = 'apply_not_authorized' } end
  if tostring(order.application.token or '') ~= intent.token or tonumber(order.application.netId) ~= intent.netId then return { ok = false, error = 'invalid_apply_token' } end
  local vehicle, vehicleErr = Adapters.ResolveVehicle(intent.netId)
  if not vehicle or vehicle.id ~= order.vehicle_id or vehicle.plate ~= order.vehicle_plate then
    local failed = finishAfterFailure(order, context.identity, vehicleErr or 'vehicle_identity_mismatch', false)
    return { ok = false, error = vehicleErr or 'vehicle_identity_mismatch', order = publicOrder(failed) }
  end
  local isCustomization = order.application and order.application.kind == 'customization'
  local applied = intent.applied == true
  if vehicle.bucket ~= GetPlayerRoutingBucket(source)
      or distance(context.coords, vehicle.coords) > MZMechanicConfig.Order.InteractionDistance
      or not bayForVehicle(context.workshop, vehicle.coords) then
    local pending = finishAfterFailure(order, context.identity, 'apply_context_changed', applied)
    notifyOrder(pending or order)
    return { ok = false, error = applied and 'pending_reconciliation' or 'vehicle_not_in_bay', order = publicOrder(pending or order) }
  end
  if not applied then
    local failed = finishAfterFailure(order, context.identity, 'apply_not_confirmed', false)
    notifyOrder(failed)
    return { ok = false, error = 'apply_not_confirmed', order = publicOrder(failed) }
  end
  local customerSource = Adapters.GetSourceByCitizenId(order.customer_citizenid)
  if not customerSource then
    local pending = finishAfterFailure(order, context.identity, 'customer_offline_after_apply', true)
    notifyOrder(pending)
    return { ok = false, error = 'pending_reconciliation', order = publicOrder(pending) }
  end
  local persisted, persistErr
  if isCustomization then
    if type(order.application.props) ~= 'table' then
      local pending = finishAfterFailure(order, context.identity, 'customization_props_missing', true)
      notifyOrder(pending)
      return { ok = false, error = 'pending_reconciliation', order = publicOrder(pending) }
    end
    persisted, persistErr = Adapters.PersistVehicleProps(customerSource, vehicle, order.application.props)
  else
    vehicle.engine, vehicle.body = 1000.0, 1000.0
    persisted, persistErr = Adapters.PersistVehicleRepair(customerSource, vehicle)
  end
  if persisted ~= true then
    local pending = finishAfterFailure(order, context.identity, persistErr or 'vehicle_persistence_failed', true)
    notifyOrder(pending)
    return { ok = false, error = 'pending_reconciliation', order = publicOrder(pending) }
  end
  local completeKey = Contracts.OperationKey('complete', order.public_id)
  local completed, completeErr = transition(order, 'completed', { revision = order.revision, requestKey = completeKey }, { citizenid = context.identity.citizenid, role = 'mechanic' }, 'completed', {
    application = {
      status = 'persisted', netId = vehicle.netId,
      kind = isCustomization and 'customization' or 'repair',
      itemCount = order.application and order.application.itemCount,
      engine = vehicle.engine, body = vehicle.body, completedAt = os.time()
    },
    releaseLock = true
  }, { vehicleId = vehicle.id }, completeKey)
  if not completed then return { ok = false, error = completeErr } end
  audit('order.completed', source, context.identity, completed, 'completed')
  notifyOrder(completed)
  return responseOrder(completed)
end

function Service.CancelOrder(source, raw)
  local intent, intentErr = Contracts.ValidateIntent('cancelOrder', raw)
  if not intent then return { ok = false, error = intentErr } end
  local order = Repository.GetOrder(intent.orderId)
  if not order then return { ok = false, error = 'order_not_found' } end
  if order.state == 'in_progress' or order.state == 'pending_apply' or order.state == 'pending_reconciliation' or Contracts.TerminalStates[order.state] then
    return { ok = false, error = 'order_not_cancellable' }
  end
  local identity, identityErr = Adapters.ResolveIdentity(source)
  if not identity then return { ok = false, error = identityErr } end
  local role = identity.citizenid == order.customer_citizenid and 'customer' or nil
  if role then
    local context, contextErr = resolveContext(source, order.workshop_code)
    if not context then return { ok = false, error = contextErr } end
  else
    local context = requireMechanic(source, order.workshop_code)
    if not context or (order.assigned_mechanic_citizenid and order.assigned_mechanic_citizenid ~= identity.citizenid) then return { ok = false, error = 'not_authorized' } end
    role = 'mechanic'
  end
  local cancelled, err, replayed = transition(order, 'cancelled', intent, { citizenid = identity.citizenid, role = role }, 'cancelled', {
    cancelReason = intent.reason,
    releaseLock = true
  }, { reason = intent.reason })
  if not cancelled then return { ok = false, error = err } end
  notifyOrder(cancelled)
  return responseOrder(cancelled, { replayed = replayed == true })
end

local function instantId()
  return ('mzi_%x_%x_%04x'):format(os.time(), GetGameTimer() % 0xffffff, math.random(0, 0xffff))
end

local function publicInstant(service)
  return {
    id = service.id,
    workshopCode = service.workshopCode,
    bayCode = service.bayCode,
    vehicle = { id = service.vehicleId, plate = service.plate },
    customerCitizenId = service.customerCitizenId,
    assignedMechanicCitizenId = service.mechanicCitizenId,
    state = service.status == 'quoted' and 'quoted' or service.status,
    revision = 1,
    diagnostic = service.diagnostic,
    quote = service.quote
  }
end

local function auditInstant(action, source, service, result, reason)
  Adapters.Log(action, {
    actor = { type = 'player', id = tostring(source), source = source },
    target = { type = 'mechanic_service', id = service and service.id or 'unknown' },
    context = {
      workshop_code = service and service.workshopCode,
      vehicle_id = service and service.vehicleId,
      vehicle_plate = service and service.plate
    },
    after = { result = result },
    meta = { reason = reason }
  })
end

local function instantCustomer(vehicle)
  local persisted = vehicle.persisted or {}
  if tostring(persisted.owner_type or '') ~= 'player' then return nil, nil, 'customer_not_player_owner' end
  local citizenid = tostring(persisted.owner_id or '')
  if citizenid == '' then return nil, nil, 'customer_unavailable' end
  local resolvedSource = Adapters.GetSourceByCitizenId(citizenid)
  local source = tonumber(resolvedSource)
  if not source or source <= 0 then return nil, nil, 'customer_offline' end
  return source, citizenid
end

local function validateInstantVehicle(context, netId, expected)
  local vehicle, vehicleErr = Adapters.ResolveVehicle(netId)
  if not vehicle then return nil, vehicleErr end
  if expected and (vehicle.id ~= expected.vehicleId or vehicle.plate ~= expected.plate) then
    return nil, 'vehicle_identity_mismatch'
  end
  if vehicle.bucket ~= GetPlayerRoutingBucket(context.source) then return nil, 'routing_bucket_mismatch' end
  if distance(context.coords, vehicle.coords) > MZMechanicConfig.Order.InteractionDistance then return nil, 'too_far_from_vehicle' end
  local bay = bayForVehicle(context.workshop, vehicle.coords)
  if not bay then return nil, 'vehicle_not_in_bay' end
  if (tonumber(vehicle.speed) or 0) > 0.1 then return nil, 'vehicle_not_stopped' end
  if vehicle.state ~= 'out' then return nil, 'vehicle_not_out' end
  return vehicle, bay
end

local function newInstantService(context, vehicle, bay, kind, requestKey)
  local now = GetGameTimer()
  for id, current in pairs(InstantServices) do
    if now > current.expiresAt then
      InstantServices[id] = nil
    elseif current.vehicleId == vehicle.id then
      if current.status == 'preview' and current.mechanicSource == context.source then
        InstantServices[id] = nil
      else
        return nil, 'service_in_progress'
      end
    end
  end
  local customerSource, customerCitizenId, customerErr = instantCustomer(vehicle)
  if not customerSource then return nil, customerErr end
  local service = {
    id = instantId(),
    kind = kind,
    status = 'preview',
    requestKey = requestKey,
    workshopCode = context.workshop.code,
    bayCode = bay.code,
    vehicleId = vehicle.id,
    netId = vehicle.netId,
    plate = vehicle.plate,
    mechanicSource = context.source,
    mechanicCitizenId = context.identity.citizenid,
    customerSource = customerSource,
    customerCitizenId = customerCitizenId,
    expiresAt = GetGameTimer() + 120000
  }
  InstantServices[service.id] = service
  return service
end

local function quoteInstant(service)
  service.status = 'quoted'
  service.expiresAt = GetGameTimer() + 120000
  local payload = publicInstant(service)
  TriggerClientEvent('mz_mechanic:client:quoteDecisionRequested', service.customerSource, payload)
  auditInstant('service.quoted', service.mechanicSource, service, 'quoted')
  return { ok = true, order = payload }
end

function Service.BeginCustomization(source, raw)
  if MZMechanicConfig.Customization.Enabled ~= true then return { ok = false, error = 'customization_disabled' } end
  local intent, intentErr = Contracts.ValidateIntent('beginCustomization', raw)
  if not intent then return { ok = false, error = intentErr } end
  local context, contextErr = requireMechanic(source)
  if not context then return { ok = false, error = contextErr } end
  local vehicle, bayOrErr = validateInstantVehicle(context, intent.netId)
  if not vehicle then return { ok = false, error = bayOrErr } end
  local service, serviceErr = newInstantService(context, vehicle, bayOrErr, 'customization')
  if not service then return { ok = false, error = serviceErr } end
  local token = ('preview_%08x_%08x_%08x'):format(os.time() % 0xffffffff, GetGameTimer() % 0xffffffff, math.random(0, 0xffffff))
  local ttlSeconds = math.max(15, math.min(180, tonumber(MZMechanicConfig.Customization.PreviewTtlSeconds) or 90))
  service.expiresAt = GetGameTimer() + ttlSeconds * 1000
  PreviewPermits[source] = { token = token, orderId = service.id, netId = vehicle.netId, expiresAt = service.expiresAt }
  return {
    ok = true,
    token = token,
    orderId = service.id,
    revision = 1,
    netId = vehicle.netId,
    ttlSeconds = ttlSeconds,
    catalog = customizationCatalog()
  }
end

function Service.QuoteCustomization(source, raw)
  local intent, intentErr = Contracts.ValidateIntent('quoteCustomization', raw)
  if not intent then return { ok = false, error = intentErr } end
  local permit = PreviewPermits[source]
  local service = InstantServices[intent.orderId]
  if not permit or permit.token ~= intent.token or permit.orderId ~= intent.orderId or not service then
    return { ok = false, error = 'preview_not_authorized' }
  end
  if GetGameTimer() > permit.expiresAt or GetGameTimer() > service.expiresAt then
    PreviewPermits[source], InstantServices[intent.orderId] = nil, nil
    return { ok = false, error = 'preview_expired' }
  end
  if service.status ~= 'preview' or service.mechanicSource ~= source then return { ok = false, error = 'preview_not_authorized' } end
  local context, contextErr = requireMechanic(source, service.workshopCode)
  if not context then return { ok = false, error = contextErr } end
  local vehicle, vehicleErr = validateInstantVehicle(context, service.netId, service)
  if not vehicle then return { ok = false, error = vehicleErr } end
  local quote, finalProps, quoteErr = buildCustomizationQuote(vehicle, intent.items)
  if not quote then return { ok = false, error = quoteErr } end
  service.quote = quote
  service.props = finalProps
  service.diagnostic = { engine = math.floor(vehicle.engine), body = math.floor(vehicle.body), dirt = vehicle.dirt, capturedAt = os.time() }
  PreviewPermits[source] = nil
  return quoteInstant(service)
end

function Service.RequestRepair(source, raw)
  local intent, intentErr = Contracts.ValidateIntent('requestRepair', raw)
  if not intent then return { ok = false, error = intentErr } end
  local context, contextErr = requireMechanic(source)
  if not context then return { ok = false, error = contextErr } end
  local vehicle, bayOrErr = validateInstantVehicle(context, intent.netId)
  if not vehicle then return { ok = false, error = bayOrErr } end
  local diagnostic = { engine = math.floor(vehicle.engine), body = math.floor(vehicle.body), dirt = vehicle.dirt, capturedAt = os.time() }
  local quote = Contracts.CalculateQuote(diagnostic, MZMechanicConfig.Services)
  if quote.available ~= true then return { ok = false, error = quote.reason } end
  local service, serviceErr = newInstantService(context, vehicle, bayOrErr, 'repair', intent.requestKey)
  if not service then return { ok = false, error = serviceErr } end
  service.diagnostic, service.quote = diagnostic, quote
  return quoteInstant(service)
end

function Service.AcceptQuote(source, raw)
  local intent, intentErr = Contracts.ValidateIntent('acceptQuote', raw)
  if not intent then return { ok = false, error = intentErr } end
  local service = InstantServices[intent.orderId]
  if not service or service.status ~= 'quoted' or GetGameTimer() > service.expiresAt then return { ok = false, error = 'service_expired' } end
  local customer, customerErr = resolveContext(source, service.workshopCode)
  if not customer then return { ok = false, error = customerErr } end
  if customer.identity.citizenid ~= service.customerCitizenId then return { ok = false, error = 'not_order_customer' } end
  local customerVehicle, vehicleErr = validateInstantVehicle(customer, service.netId, service)
  if not customerVehicle then return { ok = false, error = vehicleErr } end
  local access, accessErr = Adapters.CanAccessVehicle(source, customerVehicle.plate)
  if access ~= true then return { ok = false, error = accessErr or 'vehicle_access_denied' } end
  local mechanic, mechanicErr = requireMechanic(service.mechanicSource, service.workshopCode)
  if not mechanic then return { ok = false, error = mechanicErr or 'mechanic_unavailable' } end
  local mechanicVehicle, mechanicVehicleErr = validateInstantVehicle(mechanic, service.netId, service)
  if not mechanicVehicle then return { ok = false, error = mechanicVehicleErr } end
  local amount = math.floor(tonumber(service.quote and service.quote.total) or 0)
  if amount <= 0 then return { ok = false, error = 'invalid_server_quote' } end
  service.status = 'applying'
  service.paymentAmount = amount
  service.applyToken = Contracts.OperationKey('apply_token', ('%s_%x'):format(service.id, math.random(0, 0xffffff)))
  service.expiresAt = GetGameTimer() + 60000
  TriggerClientEvent('mz_mechanic:client:applyService', service.mechanicSource, {
    orderId = service.id,
    token = service.applyToken,
    netId = service.netId,
    plate = service.plate,
    services = service.quote.services
  })
  auditInstant('service.accepted', source, service, 'authorized')
  return { ok = true, pending = true, order = publicInstant(service) }
end

local function refundInstant(service, reason)
  local resolvedSource = Adapters.GetSourceByCitizenId(service.customerCitizenId)
  local customerSource = tonumber(resolvedSource)
  if not customerSource then return false, 'customer_offline' end
  local refunded, receipt = Adapters.Refund(
    customerSource,
    service.paymentAmount,
    Contracts.OperationKey('instant_refund', service.id),
    service.id
  )
  auditInstant('service.refund', customerSource, service, refunded and 'refunded' or 'refund_failed', reason)
  return refunded, receipt
end

function Service.ConfirmApply(source, raw)
  local intent, intentErr = Contracts.ValidateIntent('confirmApply', raw)
  if not intent then return { ok = false, error = intentErr } end
  local service = InstantServices[intent.orderId]
  if not service or service.status ~= 'applying' or service.mechanicSource ~= source then return { ok = false, error = 'apply_not_authorized' } end
  if service.applyToken ~= intent.token or service.netId ~= intent.netId then return { ok = false, error = 'invalid_apply_token' } end
  local context, contextErr = requireMechanic(source, service.workshopCode)
  if not context then return { ok = false, error = contextErr } end
  local vehicle, vehicleErr = validateInstantVehicle(context, intent.netId, service)
  if not vehicle then
    InstantServices[service.id] = nil
    return { ok = false, error = vehicleErr, rollback = true }
  end
  if intent.applied ~= true then
    InstantServices[service.id] = nil
    return { ok = false, error = 'apply_not_confirmed', rollback = true }
  end
  local resolvedSource = Adapters.GetSourceByCitizenId(service.customerCitizenId)
  local customerSource = tonumber(resolvedSource)
  if not customerSource then
    InstantServices[service.id] = nil
    return { ok = false, error = 'customer_offline', rollback = true }
  end
  service.status = 'charging'
  local paymentKey = Contracts.OperationKey('instant_pay', service.id)
  local paid, receipt = Adapters.Debit(customerSource, service.paymentAmount, paymentKey, service.id)
  if not paid then
    if receipt == 'payment_receipt_unavailable' then
      service.status = 'payment_uncertain'
    else
      InstantServices[service.id] = nil
    end
    auditInstant('service.payment_failed', customerSource, service, service.status, tostring(receipt))
    return { ok = false, error = tostring(receipt or 'payment_failed'), rollback = true }
  end
  service.paymentReceipt = receipt
  local persisted, persistErr
  if service.kind == 'customization' then
    persisted, persistErr = Adapters.PersistVehicleProps(customerSource, vehicle, service.props)
  else
    vehicle.engine, vehicle.body = 1000.0, 1000.0
    persisted, persistErr = Adapters.PersistVehicleRepair(customerSource, vehicle)
  end
  if persisted ~= true then
    local refunded, refundErr = refundInstant(service, persistErr or 'vehicle_persistence_failed')
    if refunded then InstantServices[service.id] = nil else service.status = 'payment_uncertain' end
    return { ok = false, error = tostring(persistErr or refundErr or 'vehicle_persistence_failed'), rollback = true }
  end
  auditInstant('service.completed', source, service, 'completed')
  InstantServices[service.id] = nil
  return { ok = true, completed = true }
end

function Service.CancelOrder(source, raw)
  local intent, intentErr = Contracts.ValidateIntent('cancelOrder', raw)
  if not intent then return { ok = false, error = intentErr } end
  local service = InstantServices[intent.orderId]
  if not service or service.status ~= 'quoted' then return { ok = false, error = 'service_not_cancellable' } end
  local identity, identityErr = Adapters.ResolveIdentity(source)
  if not identity then return { ok = false, error = identityErr } end
  if identity.citizenid ~= service.customerCitizenId and source ~= service.mechanicSource then return { ok = false, error = 'not_authorized' } end
  auditInstant('service.rejected', source, service, 'rejected', intent.reason)
  InstantServices[service.id] = nil
  return { ok = true, cancelled = true }
end

function Service.BindStandalone(actorSource, citizenid, workshopCode, role, active)
  local standalone = MZMechanicConfig.Authorization.Standalone or {}
  if standalone.Enabled ~= true then return false, 'standalone_disabled' end
  local authorized = actorSource == 0 or Adapters.HasStaffPermission(actorSource, 'staff.orgs.manage') or IsPlayerAceAllowed(actorSource, standalone.AdminAce)
  if not authorized then return false, 'not_authorized' end
  citizenid = tostring(citizenid or ''):gsub('^%s+', ''):gsub('%s+$', '')
  role = tostring(role or 'mechanic'):sub(1, 32)
  if #citizenid < 2 or #citizenid > 32 or not workshopByCode(workshopCode) then return false, 'invalid_binding' end
  local actor = actorSource == 0 and 'console' or (Adapters.ResolveIdentity(actorSource) or {}).citizenid
  if active then Repository.SetStandaloneBinding(citizenid, workshopCode, role, actor) else Repository.RemoveStandaloneBinding(citizenid, workshopCode, actor) end
  Adapters.Log('standalone_binding_changed', { actor = { type = actorSource == 0 and 'console' or 'player', id = actor }, target = { type = 'player', id = citizenid }, context = { workshop_code = workshopCode }, after = { active = active == true, role = role } })
  return true
end

function Service.HandlePlayerDrop(source)
  PreviewPermits[source] = nil
  for code in pairs(MZMechanicConfig.Workshops or {}) do
    StandaloneDuty[('%s:%s'):format(source, code)] = nil
  end
  local citizenid = KnownIdentities[source]
  if not citizenid then
    local identity = Adapters.ResolveIdentity(source)
    citizenid = identity and identity.citizenid
  end
  KnownIdentities[source] = nil
  for id, service in pairs(InstantServices) do
    if service.mechanicSource == source and service.status ~= 'charging' and service.status ~= 'payment_uncertain' then
      InstantServices[id] = nil
    elseif service.customerSource == source and (service.status == 'quoted' or service.status == 'applying') then
      InstantServices[id] = nil
    end
  end
end

