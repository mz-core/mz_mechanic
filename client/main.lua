MZMechanicClient = MZMechanicClient or {}

local Client = MZMechanicClient
local opened = false
local currentNetId = 0
local contextRevision = 0
local customizationPreview
local activeView = 'atendimento'
local pendingQuotePrompt
local tuningCamera
local tuningHudSuppressed = false

local serviceErrors = {
  customer_not_player_owner = 'Este veículo não possui um proprietário jogador para aprovar o serviço.',
  customer_offline = 'O proprietário precisa estar online e presente na oficina.',
  service_in_progress = 'Este veículo já possui um atendimento em andamento.',
  vehicle_not_damaged = 'Este veículo não precisa de reparo estrutural.',
  payment_failed = 'A cobrança foi recusada.',
  payment_receipt_unavailable = 'A cobrança precisa de conferência no ledger.',
  apply_not_confirmed = 'A execução não foi concluída.'
}

local function serviceError(code)
  return serviceErrors[tostring(code or '')] or tostring(code or 'erro desconhecido')
end

local function notify(description, kind)
  local types = { inform = 'info', success = 'success', error = 'error', warning = 'warning' }
  exports['mz_lib']:notify({ title = 'Oficina', description = description, type = types[kind] or 'info' })
end

local function setTuningHudSuppressed(suppressed, force)
  suppressed = suppressed == true
  if not force and tuningHudSuppressed == suppressed then return end
  tuningHudSuppressed = suppressed
  TriggerEvent('mz_hud:client:setSuppressed', 'mz_mechanic', suppressed)
end

local function requestKey(prefix)
  return ('%s_%08x_%06x'):format(prefix, GetGameTimer() % 0xffffffff, math.random(0, 0xffffff))
end

local function server(callbackName, payload)
  local ok, result = pcall(lib.callback.await, callbackName, false, payload or {})
  if not ok then return { ok = false, error = 'server_unavailable' } end
  return type(result) == 'table' and result or { ok = false, error = 'invalid_server_response' }
end

local function debugLog(message)
  if MZMechanicConfig.Debug == true then
    print(('[mz_mechanic][nui] %s'):format(tostring(message)))
  end
end

local function distance(a, b)
  local dx, dy, dz = a.x - b.x, a.y - b.y, a.z - b.z
  return math.sqrt(dx * dx + dy * dy + dz * dz)
end

local function vehicleNetId(entity)
  if not entity or entity <= 0 or not DoesEntityExist(entity) or GetEntityType(entity) ~= 2
      or not NetworkGetEntityIsNetworked(entity) then return 0 end
  return tonumber(NetworkGetNetworkIdFromEntity(entity)) or 0
end

local function tuningBayForVehicle(entity)
  if vehicleNetId(entity) <= 0 then return nil end
  local coords = GetEntityCoords(entity)
  local nearest, nearestDistance, nearestWorkshop
  for workshopCode, workshop in pairs(MZMechanicConfig.Workshops or {}) do
    if workshop.tuning and workshop.tuning.enabled == true then
      for _, bay in ipairs(workshop.bays or {}) do
        local bayDistance = distance(coords, bay.coords)
        if not nearestDistance or bayDistance < nearestDistance then
          nearest, nearestDistance, nearestWorkshop = bay, bayDistance, workshopCode
        end
      end
    end
  end
  if nearest and nearestDistance <= (tonumber(nearest.radius) or 5.0) then
    return nearest, nearestDistance, nearestWorkshop
  end
  return nil, nearestDistance, nearestWorkshop
end

local function nearestVehicle(point, maxDistance, stoppedOnly)
  local nearest, nearestDistance
  for _, entity in ipairs(GetGamePool('CVehicle')) do
    if vehicleNetId(entity) > 0 and (not stoppedOnly or GetEntitySpeed(entity) <= 0.1) then
      local entityDistance = distance(GetEntityCoords(entity), point)
      if entityDistance <= maxDistance and (not nearestDistance or entityDistance < nearestDistance) then
        nearest, nearestDistance = entity, entityDistance
      end
    end
  end
  return nearest or 0, nearestDistance
end

local function debugClientSession(requestId)
  if MZMechanicConfig.Debug ~= true then return end
  local ok, session = pcall(function()
    return exports['mz_core']:GetPlayerSession()
  end)
  print(('[mz_mechanic][nui] context request=%s client_session export_ok=%s present=%s active=%s lifecycle=%s character=%s'):format(
    tostring(requestId),
    tostring(ok),
    tostring(type(session) == 'table'),
    tostring(type(session) == 'table' and session.isActive == true),
    tostring(type(session) == 'table' and session.lifecycle or 'nil'),
    tostring(type(session) == 'table' and session.activeCharacterId ~= nil)
  ))
end

local function clone(value)
  if type(value) ~= 'table' then return value end
  local copy = {}
  for key, item in pairs(value) do copy[key] = clone(item) end
  return copy
end

local function equal(a, b)
  if type(a) ~= type(b) then return false end
  if type(a) ~= 'table' then return a == b end
  for key, value in pairs(a) do if not equal(value, b[key]) then return false end end
  for key in pairs(b) do if a[key] == nil then return false end end
  return true
end

local function customizationProperty(props, definition)
  if type(props) ~= 'table' then return nil end
  if definition.key == nil then return props[definition.field] end
  return type(props[definition.field]) == 'table' and props[definition.field][definition.key] or nil
end

local function setCustomizationProperty(props, definition, value)
  if definition.key == nil then
    props[definition.field] = clone(value)
    return
  end
  if type(props[definition.field]) ~= 'table' then props[definition.field] = {} end
  props[definition.field][definition.key] = clone(value)
end

local function rgbValue(value)
  value = math.floor(tonumber(value) or -1)
  if value < 0 or value > 0xffffff then return nil end
  return {
    math.floor(value / 0x10000) % 0x100,
    math.floor(value / 0x100) % 0x100,
    value % 0x100
  }
end

local function rgbNumber(value)
  if type(value) ~= 'table' then return nil end
  local red, green, blue = tonumber(value[1]), tonumber(value[2]), tonumber(value[3])
  if not red or not green or not blue then return nil end
  return math.floor(red) * 0x10000 + math.floor(green) * 0x100 + math.floor(blue)
end

local function currentVehicle()
  local vehicle = currentNetId > 0 and NetworkGetEntityFromNetworkId(currentNetId) or 0
  return vehicle > 0 and DoesEntityExist(vehicle) and vehicle or 0
end

local function destroyTuningCamera()
  if not tuningCamera then return end
  if tuningCamera.mode == 'interior' then
    SetFollowVehicleCamViewMode(tuningCamera.previousViewMode)
  end
  RenderScriptCams(false, true, 250, true, true)
  DestroyCam(tuningCamera.handle, false)
  ClearFocus()
  tuningCamera = nil
end

local function updateTuningCamera()
  if not tuningCamera or not DoesEntityExist(tuningCamera.vehicle) then return destroyTuningCamera() end
  local camera, vehicle = tuningCamera.handle, tuningCamera.vehicle
  local center = GetOffsetFromEntityInWorldCoords(vehicle, 0.0, 0.0, 0.55)
  local radians = math.rad(tuningCamera.angle)
  SetCamCoord(camera,
    center.x + math.cos(radians) * tuningCamera.distance,
    center.y + math.sin(radians) * tuningCamera.distance,
    center.z + 1.0)
  PointCamAtEntity(camera, vehicle, 0.0, 0.0, 0.45, true)
  SetCamFov(camera, 45.0)
end

local function startTuningCamera(vehicle)
  destroyTuningCamera()
  tuningCamera = {
    handle = CreateCam('DEFAULT_SCRIPTED_CAMERA', true),
    vehicle = vehicle,
    angle = GetEntityHeading(vehicle) + 135.0,
    distance = 5.5,
    mode = 'general',
    previousViewMode = GetFollowVehicleCamViewMode()
  }
  SetFocusEntity(vehicle)
  updateTuningCamera()
  RenderScriptCams(true, true, 300, true, true)
end

local function controlTuningCamera(action)
  if not tuningCamera then return false end
  if action == 'interior' then
    if GetVehiclePedIsIn(PlayerPedId(), false) ~= tuningCamera.vehicle then
      notify('Entre no veículo para usar a visão interna.', 'warning')
      return false
    end
    tuningCamera.mode = 'interior'
    RenderScriptCams(false, true, 250, true, true)
    SetFollowVehicleCamViewMode(4)
    return true
  end
  local wasInterior = tuningCamera.mode == 'interior'
  if wasInterior then SetFollowVehicleCamViewMode(tuningCamera.previousViewMode) end
  tuningCamera.mode = 'general'
  if action == 'left' or action == 'right' then
    tuningCamera.angle = tuningCamera.angle + (action == 'left' and -15.0 or 15.0)
  elseif action == 'zoomIn' or action == 'zoomOut' then
    local delta = action == 'zoomIn' and -0.6 or 0.6
    tuningCamera.distance = math.max(2.2, math.min(8.0, tuningCamera.distance + delta))
  elseif action ~= 'general' then
    return false
  end
  updateTuningCamera()
  if wasInterior then RenderScriptCams(true, true, 250, true, true) end
  return true
end

local function vehicleProps(vehicle)
  local ok, props = pcall(function() return exports['mz_vehicles']:GetVehicleProperties(vehicle) end)
  return ok and type(props) == 'table' and props or nil
end

local function applyVehicleProps(vehicle, props)
  return pcall(function() exports['mz_vehicles']:SetVehicleProperties(vehicle, props) end)
end

local function rollbackCustomization(reason)
  local preview = customizationPreview
  customizationPreview = nil
  if not preview then return true end
  local vehicle = preview.netId > 0 and NetworkGetEntityFromNetworkId(preview.netId) or 0
  local restored = vehicle > 0 and DoesEntityExist(vehicle) and applyVehicleProps(vehicle, preview.originalProps) or false
  debugLog(('customization stage=rollback reason=%s restored=%s'):format(tostring(reason), tostring(restored == true)))
  return restored == true
end

local function customizationModCount(vehicle, item)
  if item.extraId ~= nil then return DoesExtraExist(vehicle, tonumber(item.extraId)) and 1 or 0 end
  if item.requiresSlot ~= nil then return math.max(0, tonumber(GetNumVehicleMods(vehicle, tonumber(item.requiresSlot))) or 0) end
  if item.counter == 'livery' then
    return math.max(
      math.max(0, tonumber(GetNumVehicleMods(vehicle, tonumber(item.slot) or 48)) or 0),
      math.max(0, tonumber(GetVehicleLiveryCount(vehicle)) or 0)
    )
  end
  if item.counter == 'roof_livery' then
    return type(GetVehicleRoofLiveryCount) == 'function' and math.max(0, tonumber(GetVehicleRoofLiveryCount(vehicle)) or 0) or 0
  end
  if item.slot ~= nil then return math.max(0, tonumber(GetNumVehicleMods(vehicle, tonumber(item.slot))) or 0) end
  return 1
end

local function optionLabel(item, value)
  if value == -1 and item.originalLabel then return item.originalLabel end
  if item.optionLabel then return tostring(item.optionLabel):format(value) end
  if item.category == 'performance' then return ('Nível %s'):format(value + 1) end
  return ('Opção %02d'):format(value + 1)
end

local function buildCustomizationCatalog(vehicle, catalog, originalProps)
  SetVehicleModKit(vehicle, 0)
  local supported = {}
  for _, item in ipairs(type(catalog) == 'table' and catalog or {}) do
    local count = customizationModCount(vehicle, item)
    local constrainedToggle = item.slot ~= nil or item.extraId ~= nil or item.requiresSlot ~= nil
    local available = item.kind == 'indexed' and count > 0
      or item.kind == 'toggle' and (not constrainedToggle or count > 0)
      or item.kind == 'range' or item.kind == 'rgb'
    if available then
      local options = {}
      if item.kind == 'toggle' then
        options = {
          { value = false, label = 'Desativado', price = math.floor((tonumber(item.fixedPrice) or 0) * 0.25) },
          { value = true, label = 'Ativado', price = math.floor(tonumber(item.fixedPrice) or 0) }
        }
      elseif item.kind == 'indexed' then
        local maxCount = math.min(count, (tonumber(item.maxIndex) or 99) + 1)
        if item.counter ~= 'livery' and item.counter ~= 'roof_livery' then
          options[1] = { value = -1, label = 'Original', price = math.floor(tonumber(item.basePrice) or 0) }
        end
        for index = 0, maxCount - 1 do
          options[#options + 1] = {
            value = index,
            label = optionLabel(item, index),
            price = math.floor((tonumber(item.basePrice) or 0) + (index + 1) * (tonumber(item.stepPrice) or 0))
          }
        end
      elseif item.kind == 'range' then
        for index = tonumber(item.minIndex) or -1, tonumber(item.maxIndex) or 99 do
          options[#options + 1] = {
            value = index,
            label = optionLabel(item, index),
            price = math.floor(tonumber(item.fixedPrice) or 0)
          }
        end
      end
      local applied = customizationProperty(originalProps, item)
      if item.kind == 'rgb' then applied = rgbNumber(applied) end
      supported[#supported + 1] = {
        code = item.code, label = item.label, category = item.category, field = item.field,
        slot = item.slot, kind = item.kind, key = item.key, extraId = item.extraId,
        requiresSlot = item.requiresSlot, counter = item.counter, group = item.group,
        minIndex = item.minIndex, maxIndex = item.maxIndex, fixedPrice = item.fixedPrice,
        applied = applied, options = options
      }
    end
  end
  return supported
end

local function configuredCustomizationCatalog(vehicle)
  local props = vehicleProps(vehicle)
  if not props then return {} end
  local definitions = {}
  for code, item in pairs(MZMechanicConfig.Customization and MZMechanicConfig.Customization.Items or {}) do
    local definition = clone(item)
    definition.code = code
    definitions[#definitions + 1] = definition
  end
  table.sort(definitions, function(a, b) return a.code < b.code end)
  return buildCustomizationCatalog(vehicle, definitions, props)
end

function Client.GetVehicleNetId(entity)
  return vehicleNetId(entity)
end

function Client.IsOpen()
  return opened
end

function Client.GetTuningBay(entity)
  return tuningBayForVehicle(entity)
end

function Client.FindNearbyVehicle(maxDistance)
  local ped = PlayerPedId()
  local coords = GetEntityCoords(ped)
  local current = GetVehiclePedIsIn(ped, false)
  if vehicleNetId(current) > 0 and distance(GetEntityCoords(current), coords) <= (tonumber(maxDistance) or MZMechanicConfig.Order.InteractionDistance) then
    return current
  end
  return nearestVehicle(coords, tonumber(maxDistance) or MZMechanicConfig.Order.InteractionDistance, false)
end

function Client.FindTuningVehicle(preferred)
  if vehicleNetId(preferred) > 0 then
    local bay, bayDistance, workshopCode = tuningBayForVehicle(preferred)
    debugLog(('vehicle source=tuning_target entity=%s net_id=%s workshop=%s bay=%s distance=%.2f stopped=%s'):format(
      tostring(preferred), tostring(vehicleNetId(preferred)), tostring(workshopCode or 'none'),
      tostring(bay and bay.code or 'none'), tonumber(bayDistance) or -1, tostring(GetEntitySpeed(preferred) <= 0.1)
    ))
    if bay and GetEntitySpeed(preferred) <= 0.1 then return preferred end
    return 0
  end
  local pedCoords = GetEntityCoords(PlayerPedId())
  local selected, selectedDistance
  for workshopCode, workshop in pairs(MZMechanicConfig.Workshops or {}) do
    if workshop.tuning and workshop.tuning.enabled == true
        and distance(pedCoords, workshop.coords) <= (tonumber(workshop.radius) or 30.0) then
      for _, bay in ipairs(workshop.bays or {}) do
        local vehicle, bayDistance = nearestVehicle(bay.coords, tonumber(bay.radius) or 5.0, true)
        debugLog(('vehicle source=tuning_bay workshop=%s bay=%s distance=%.2f net_id=%s'):format(
          tostring(workshopCode), tostring(bay.code), tonumber(bayDistance) or -1, tostring(vehicleNetId(vehicle))
        ))
        if vehicle > 0 and (not selectedDistance or bayDistance < selectedDistance) then
          selected, selectedDistance = vehicle, bayDistance
        end
      end
    end
  end
  return selected or 0
end

function Client.OpenTuningBay(bay)
  if opened or type(bay) ~= 'table' or type(bay.coords) ~= 'table' then return false end
  local vehicle = nearestVehicle(bay.coords, tonumber(bay.radius) or 5.0, true)
  if vehicle <= 0 then
    notify('Posicione e pare um veículo nesta vaga para abrir o tuning.', 'warning')
    return false
  end
  return Client.Open(vehicle, 'tuning')
end

local function requestContext(openAction)
  if not opened then return nil end
  contextRevision = contextRevision + 1
  local requestId = contextRevision
  SendNUIMessage({
    action = openAction and 'mz_mechanic:open' or 'mz_mechanic:contextLoading',
    netId = currentNetId,
    requestId = requestId,
    view = activeView
  })
  CreateThread(function()
    if not opened or requestId ~= contextRevision then return end
    debugClientSession(requestId)
    debugLog(('context request=%s stage=server_dispatch vehicle_request=%s'):format(
      tostring(requestId), tostring(currentNetId > 0)
    ))
    local result = server('mz_mechanic:server:getContext', { netId = currentNetId, requestId = requestId, view = activeView })
    if result.ok == true and activeView == 'tuning' then
      local vehicle = currentVehicle()
      if vehicle > 0 then result.tuningCatalog = configuredCustomizationCatalog(vehicle) end
    end
    if not result.ok then
      debugLog(('context request %s failed: %s'):format(requestId, tostring(result.error)))
    end
    if opened and requestId == contextRevision then
      debugLog(('context request=%s stage=nui_dispatch result_type=%s ok=%s error=%s'):format(
        tostring(requestId), type(result), tostring(result.ok == true), tostring(result.error or 'none')
      ))
      SendNUIMessage({ action = 'mz_mechanic:context', requestId = requestId, result = result })
    end
  end)
  return requestId
end

function Client.Open(vehicle, view)
  rollbackCustomization('open_changed')
  destroyTuningCamera()
  activeView = view == 'tuning' and 'tuning' or 'atendimento'
  local requested = tonumber(vehicle) or 0
  if activeView == 'tuning' and requested <= 0 then vehicle = Client.FindTuningVehicle() end
  currentNetId = vehicleNetId(vehicle)
  debugLog(('vehicle source=open view=%s entity=%s exists=%s type=%s networked=%s net_id=%s'):format(
    activeView, tostring(vehicle or 0), tostring(vehicle and vehicle > 0 and DoesEntityExist(vehicle) or false),
    tostring(vehicle and vehicle > 0 and DoesEntityExist(vehicle) and GetEntityType(vehicle) or 0),
    tostring(vehicle and vehicle > 0 and DoesEntityExist(vehicle) and NetworkGetEntityIsNetworked(vehicle) or false),
    tostring(currentNetId)
  ))
  if requested > 0 and currentNetId <= 0 then
    notify('O veículo selecionado não está mais disponível.', 'error')
    return false
  end
  opened = true
  setTuningHudSuppressed(activeView == 'tuning')
  if activeView == 'tuning' and currentNetId > 0 then startTuningCamera(vehicle) end
  SetNuiFocus(true, true)
  requestContext(true)
  return true
end

function Client.OpenNearby(view)
  return Client.Open(Client.FindNearbyVehicle(), view or 'atendimento')
end

function Client.Close()
  rollbackCustomization('close')
  destroyTuningCamera()
  setTuningHudSuppressed(false)
  if not opened then return end
  opened = false
  contextRevision = contextRevision + 1
  currentNetId = 0
  activeView = 'atendimento'
  SetNuiFocus(false, false)
  SendNUIMessage({ action = 'mz_mechanic:close' })
end

function Client.RefreshContext()
  if currentNetId <= 0 and activeView == 'atendimento' then
    currentNetId = vehicleNetId(Client.FindNearbyVehicle())
  end
  return requestContext(false)
end

local function registerCallback(nuiName, serverName, includeNetId)
  RegisterNUICallback(nuiName, function(payload, cb)
    payload = type(payload) == 'table' and payload or {}
    if includeNetId and payload.netId == nil then payload.netId = currentNetId end
    cb(server(serverName, payload))
  end)
end

registerCallback('mz_mechanic:getContext', 'mz_mechanic:server:getContext', true)
registerCallback('mz_mechanic:toggleDuty', 'mz_mechanic:server:toggleDuty')
registerCallback('mz_mechanic:acceptQuote', 'mz_mechanic:server:acceptQuote')
registerCallback('mz_mechanic:cancelOrder', 'mz_mechanic:server:cancelOrder')

RegisterNUICallback('mz_mechanic:beginCustomization', function(payload, cb)
  payload = type(payload) == 'table' and payload or {}
  rollbackCustomization('new_preview')
  local vehicle = currentVehicle()
  if vehicle == 0 then return cb({ ok = false, error = 'vehicle_not_found' }) end
  local result = server('mz_mechanic:server:beginCustomization', { netId = currentNetId })
  if result.ok ~= true then return cb(result) end
  if tonumber(result.netId) ~= currentNetId then return cb({ ok = false, error = 'vehicle_identity_mismatch' }) end
  local originalProps = vehicleProps(vehicle)
  if not originalProps then return cb({ ok = false, error = 'vehicle_props_unavailable' }) end
  local definitions = result.catalog
  local catalog = buildCustomizationCatalog(vehicle, definitions, originalProps)
  if #catalog == 0 then return cb({ ok = false, error = 'no_supported_customization' }) end
  customizationPreview = {
    token = result.token,
    orderId = result.orderId,
    netId = currentNetId,
    originalProps = originalProps,
    currentProps = clone(originalProps),
    definitions = definitions,
    catalog = catalog
  }
  local expectedToken = result.token
  SetTimeout((tonumber(result.ttlSeconds) or 90) * 1000, function()
    if customizationPreview and customizationPreview.token == expectedToken then
      rollbackCustomization('timeout')
      if opened then SendNUIMessage({ action = 'mz_mechanic:customizationExpired' }) end
    end
  end)
  result.catalog = catalog
  cb(result)
end)

RegisterNUICallback('mz_mechanic:previewCustomization', function(payload, cb)
  payload = type(payload) == 'table' and payload or {}
  local preview = customizationPreview
  if not preview or payload.token ~= preview.token or payload.orderId ~= preview.orderId then
    return cb({ ok = false, error = 'preview_not_authorized' })
  end
  local vehicle = currentVehicle()
  if vehicle == 0 or currentNetId ~= preview.netId then return cb({ ok = false, error = 'vehicle_identity_mismatch' }) end
  local definition
  for _, item in ipairs(preview.catalog) do if item.code == payload.code then definition = item break end end
  if not definition then return cb({ ok = false, error = 'customization_not_allowed' }) end
  local selectedValue, value = payload.value, payload.value
  if definition.kind == 'toggle' then
    if type(value) ~= 'boolean' then return cb({ ok = false, error = 'invalid_customization_value' }) end
  elseif definition.kind == 'indexed' then
    value = tonumber(value)
    local count = customizationModCount(vehicle, definition)
    if not value or value % 1 ~= 0 or value < -1 or value >= count then
      return cb({ ok = false, error = 'unsupported_customization_option' })
    end
    value = math.floor(value)
  elseif definition.kind == 'range' then
    value = tonumber(value)
    if not value or value % 1 ~= 0 or value < (tonumber(definition.minIndex) or -1)
        or value > (tonumber(definition.maxIndex) or 99) then
      return cb({ ok = false, error = 'unsupported_customization_option' })
    end
    value = math.floor(value)
  elseif definition.kind == 'rgb' then
    value = rgbValue(value)
    if not value then return cb({ ok = false, error = 'invalid_customization_value' }) end
  else
    return cb({ ok = false, error = 'invalid_customization_value' })
  end
  local previous = clone(customizationProperty(preview.currentProps, definition))
  setCustomizationProperty(preview.currentProps, definition, value)
  if not applyVehicleProps(vehicle, preview.currentProps) then
    setCustomizationProperty(preview.currentProps, definition, previous)
    return cb({ ok = false, error = 'preview_apply_failed' })
  end
  local appliedProps = vehicleProps(vehicle)
  if not appliedProps or not equal(customizationProperty(appliedProps, definition), value) then
    setCustomizationProperty(preview.currentProps, definition, previous)
    applyVehicleProps(vehicle, preview.currentProps)
    return cb({ ok = false, error = 'preview_not_confirmed' })
  end
  local refreshedCatalog
  if definition.field == 'wheels' then
    refreshedCatalog = buildCustomizationCatalog(vehicle, preview.definitions, preview.originalProps)
    preview.catalog = refreshedCatalog
  end
  cb({ ok = true, applied = selectedValue, catalog = refreshedCatalog })
end)

RegisterNUICallback('mz_mechanic:cancelCustomization', function(_, cb)
  cb({ ok = rollbackCustomization('cancel') })
end)

RegisterNUICallback('mz_mechanic:quoteCustomization', function(payload, cb)
  payload = type(payload) == 'table' and payload or {}
  local preview = customizationPreview
  if not preview or payload.token ~= preview.token or payload.orderId ~= preview.orderId then
    return cb({ ok = false, error = 'preview_not_authorized' })
  end
  rollbackCustomization('quote')
  cb(server('mz_mechanic:server:quoteCustomization', payload))
end)

function Client.RequestRepair(vehicle)
  local netId = vehicleNetId(vehicle)
  if netId <= 0 then
    notify('O veículo selecionado não está mais disponível.', 'error')
    return false
  end
  CreateThread(function()
    local result = server('mz_mechanic:server:requestRepair', {
      netId = netId,
      requestKey = requestKey('repair')
    })
    notify(
      result.ok and 'Orçamento de reparo enviado ao proprietário.' or ('Reparo não iniciado: ' .. serviceError(result.error)),
      result.ok and 'success' or 'error'
    )
  end)
  return true
end

RegisterNUICallback('mz_mechanic:retryContext', function(_, cb)
  local requestId = Client.RefreshContext()
  cb(requestId and { ok = true, requestId = requestId } or { ok = false, error = 'panel_closed' })
end)

RegisterNUICallback('mz_mechanic:camera', function(payload, cb)
  local action = type(payload) == 'table' and tostring(payload.action or '') or ''
  cb({ ok = opened and activeView == 'tuning' and controlTuningCamera(action) })
end)

RegisterNUICallback('mz_mechanic:close', function(_, cb)
  Client.Close()
  cb({ ok = true })
end)

RegisterNetEvent('mz_mechanic:client:open', function(netId)
  local vehicle = tonumber(netId) and NetworkGetEntityFromNetworkId(tonumber(netId)) or 0
  Client.Open(vehicle, 'atendimento')
end)

RegisterNetEvent('mz_mechanic:client:orderUpdated', function(order)
  if opened then
    SendNUIMessage({ action = 'mz_mechanic:orderUpdated', order = order })
  else
    notify(('Ordem %s atualizada: %s'):format(tostring(order and order.id or ''), tostring(order and order.state or '')), 'inform')
  end
end)

RegisterNetEvent('mz_mechanic:client:quoteDecisionRequested', function(order)
  if type(order) ~= 'table' or order.state ~= 'quoted' or pendingQuotePrompt == order.id then return end
  pendingQuotePrompt = order.id
  CreateThread(function()
    if opened then Client.Close() end
    local ok, accepted = pcall(function()
      return exports['mz_lib']:alertDialog({
        title = 'Aceitar orçamento?',
        description = ('Veículo %s · valor $ %d'):format(
          tostring(order.vehicle and order.vehicle.plate or 'sem placa'),
          math.floor(tonumber(order.quote and order.quote.total) or 0)
        ),
        keyboard = true,
        confirmLabel = 'Aceitar',
        cancelLabel = 'Recusar'
      })
    end)
    if not ok then
      notify('Não foi possível abrir a confirmação do orçamento.', 'error')
    elseif accepted ~= nil then
      local result
      if accepted == true then
        result = server('mz_mechanic:server:acceptQuote', {
          orderId = order.id,
          revision = order.revision,
          requestKey = requestKey('quote_accept')
        })
      else
        result = server('mz_mechanic:server:cancelOrder', {
          orderId = order.id,
          revision = order.revision,
          requestKey = requestKey('quote_reject'),
          reason = 'orçamento recusado pelo cliente'
        })
      end
      notify(
        result.ok and (accepted and 'Orçamento aceito.' or 'Orçamento recusado.') or ('Decisão não concluída: ' .. serviceError(result.error)),
        result.ok and (accepted and 'success' or 'warning') or 'error'
      )
    end
    pendingQuotePrompt = nil
  end)
end)

RegisterNetEvent('mz_core:client:characterSelectionRequired', function()
  Client.Close()
end)

RegisterNetEvent('mz_mechanic:client:applyService', function(payload)
  if type(payload) ~= 'table' then return end
  Client.Close()
  local netId = tonumber(payload.netId) or 0
  local vehicle = netId > 0 and NetworkGetEntityFromNetworkId(netId) or 0
  local applied = false
  local originalProps, originalEngine, originalBody
  if vehicle > 0 and DoesEntityExist(vehicle) then
    local plate = exports['mz_vehicles']:GetVehiclePlate(vehicle)
    plate = tostring(plate or ''):upper():gsub('^%s+', ''):gsub('%s+$', '')
    local expectedPlate = tostring(payload.plate or ''):upper():gsub('^%s+', ''):gsub('%s+$', '')
    if plate == expectedPlate then
      originalProps = vehicleProps(vehicle)
      originalEngine = GetVehicleEngineHealth(vehicle)
      originalBody = GetVehicleBodyHealth(vehicle)
      local nextProps = originalProps and clone(originalProps) or nil
      local customizationItems = {}
      local ped = PlayerPedId()
      TaskTurnPedToFaceEntity(ped, vehicle, 750)
      Wait(750)
      local animationOwned = false
      if type(GetResourceState) == 'function' and GetResourceState('mz_animations') == 'started' then
        local ok, played = pcall(function()
          return exports['mz_animations']:PlayByName('mecanico2', { silent = true })
        end)
        animationOwned = ok and played == true
      end
      if not animationOwned then TaskStartScenarioInPlace(ped, 'WORLD_HUMAN_VEHICLE_MECHANIC', 0, true) end
      local progressOk, completed = pcall(function()
        return exports['mz_lib']:progress({
          label = 'Executando serviço...',
          duration = 6500,
          canCancel = false,
          disable = { move = true, car = true, combat = true }
        })
      end)
      debugLog(('apply order=%s stage=progress export_ok=%s completed=%s'):format(
        tostring(payload.orderId), tostring(progressOk), tostring(progressOk and completed == true)
      ))
      if animationOwned then
        pcall(function() exports['mz_animations']:Stop('mechanic_service', false) end)
      else
        ClearPedTasks(ped)
      end
      if progressOk and completed == true then
        for _, service in ipairs(payload.services or {}) do
          if service.code == 'full_repair' then
            SetVehicleFixed(vehicle)
            SetVehicleEngineHealth(vehicle, 1000.0)
            SetVehicleBodyHealth(vehicle, 1000.0)
            SetVehicleUndriveable(vehicle, false)
            applied = true
          elseif type(service.customization) == 'table' and nextProps then
            setCustomizationProperty(nextProps, service.customization, service.customization.value)
            customizationItems[#customizationItems + 1] = service.customization
          end
        end
        if #customizationItems > 0 and applyVehicleProps(vehicle, nextProps) then
          local confirmed = vehicleProps(vehicle)
          applied = confirmed ~= nil
          for _, item in ipairs(customizationItems) do
            if not confirmed or not equal(customizationProperty(confirmed, item), item.value) then applied = false break end
          end
          if not applied and originalProps then applyVehicleProps(vehicle, originalProps) end
        end
      end
    end
  end
  local result = server('mz_mechanic:server:confirmApply', {
    orderId = payload.orderId,
    token = payload.token,
    netId = netId,
    applied = applied
  })
  debugLog(('apply order=%s stage=confirm applied=%s ok=%s error=%s'):format(
    tostring(payload.orderId), tostring(applied), tostring(result.ok == true), tostring(result.error or 'none')
  ))
  if result.ok ~= true and result.rollback == true and vehicle > 0 and DoesEntityExist(vehicle) then
    if originalProps then applyVehicleProps(vehicle, originalProps) end
    if originalEngine then SetVehicleEngineHealth(vehicle, originalEngine + 0.0) end
    if originalBody then SetVehicleBodyHealth(vehicle, originalBody + 0.0) end
  end
  notify(result.ok and 'Serviço aplicado e persistido.' or ('Serviço não concluído: ' .. serviceError(result.error)), result.ok and 'success' or 'error')
end)

RegisterCommand('mzmechanic', function()
  Client.OpenNearby('atendimento')
end, false)

RegisterKeyMapping('mzmechanic', 'Abrir painel da oficina', 'keyboard', 'F7')

AddEventHandler('onClientResourceStart', function(resourceName)
  if resourceName == 'mz_hud' and tuningHudSuppressed then setTuningHudSuppressed(true, true) end
end)

AddEventHandler('onClientResourceStop', function(resourceName)
  if resourceName == GetCurrentResourceName() then
    rollbackCustomization('resource_stop')
    destroyTuningCamera()
    setTuningHudSuppressed(false)
    opened = false
    contextRevision = contextRevision + 1
    SetNuiFocus(false, false)
    ClearPedTasks(PlayerPedId())
  end
end)

