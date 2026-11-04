MZMechanicAdapters = MZMechanicAdapters or {}

local Adapters = MZMechanicAdapters

local function started(resource)
  return type(GetResourceState) == 'function' and GetResourceState(resource) == 'started'
end

local function call(resource, exportName, ...)
  if not started(resource) then return nil, resource .. '_unavailable' end
  local args = table.pack(...)
  local result = table.pack(pcall(function()
    local resourceExports = exports[resource]
    local exportFn = resourceExports and resourceExports[exportName]
    if type(exportFn) ~= 'function' then error(('missing_export:%s:%s'):format(resource, exportName)) end
    return exportFn(resourceExports, table.unpack(args, 1, args.n))
  end))
  if result[1] ~= true then return nil, resource .. '_contract_failed' end
  return table.unpack(result, 2, result.n)
end

local function debugCoreIdentity(source, requestId, stage, value, err)
  if MZMechanicConfig.Debug ~= true then return end
  local valueType = type(value)
  local returnedSource = valueType == 'table' and tonumber(value.source) or nil
  local sourceMatch = returnedSource and returnedSource == tonumber(source) or nil
  print(('[mz_mechanic][core] request=%s source=%s stage=%s result_type=%s ok=%s error=%s source_match=%s'):format(
    tostring(requestId or 0), tostring(source), tostring(stage), valueType,
    tostring(valueType == 'table' and value.ok == true or value == true),
    tostring(err or (valueType == 'table' and value.error) or 'none'),
    sourceMatch == nil and 'n/a' or tostring(sourceMatch)
  ))
end

function Adapters.ResolveIdentity(source, requestId)
  local identity, err = call('mz_core', 'ResolvePlayerIdentity', source)
  debugCoreIdentity(source, requestId, 'resolve_identity', identity, err)
  if type(identity) ~= 'table' or identity.ok ~= true or not identity.citizenid then
    return nil, err or (identity and identity.error) or 'identity_unavailable'
  end
  local loaded, loadedErr = call('mz_core', 'IsPlayerLoaded', source)
  debugCoreIdentity(source, requestId, 'is_player_loaded', loaded, loadedErr)
  if loaded == nil then return nil, loadedErr or 'identity_unavailable' end
  if loaded ~= true or identity.active ~= true then return nil, 'session_not_ready' end
  return identity
end

function Adapters.GetSourceByCitizenId(citizenid)
  return call('mz_core', 'GetSourceByCitizenId', citizenid)
end

function Adapters.HasStaffPermission(source, permission)
  return call('mz_core', 'HasGlobalPermission', source, permission) == true
end

function Adapters.Log(action, payload)
  call('mz_core', 'CreateDetailedLog', 'mechanic', action, payload or {})
end

function Adapters.GetOrgMechanic(source, workshop)
  if not started('mz_org') then return nil, 'mz_org_unavailable' end
  local orgs, err = call('mz_org', 'GetPlayerOrgContext', source)
  if type(orgs) ~= 'table' then return nil, err or 'org_context_unavailable' end
  for _, org in ipairs(orgs) do
    if tostring(org.code or '') == tostring(workshop.orgCode or '') and org.active == true then
      local permission = tostring(MZMechanicConfig.Authorization.OrgPermission)
      local allowed = type(org.permissions) == 'table' and org.permissions[permission] == true
      return {
        linked = allowed,
        onDuty = org.duty == true,
        orgId = tonumber(org.orgId or org.org_id),
        orgCode = tostring(org.code),
        grade = org.grade,
        reason = allowed and nil or 'missing_permission'
      }
    end
  end
  return nil, 'not_org_mechanic'
end

function Adapters.SetOrgDuty(source, workshop, duty)
  return call('mz_org', 'SetSelfOrgDutyAtPoint', source, workshop.orgCode, duty)
end

function Adapters.GetPlayerCoords(source)
  local ok, ped = pcall(GetPlayerPed, source)
  if not ok or not ped or ped <= 0 then return nil, 'player_not_found' end
  local coordsOk, coords = pcall(GetEntityCoords, ped)
  if not coordsOk or not coords then return nil, 'position_unavailable' end
  return { x = tonumber(coords.x), y = tonumber(coords.y), z = tonumber(coords.z) }
end

function Adapters.ResolveVehicle(netId)
  netId = tonumber(netId) or 0
  if netId <= 0 then return nil, 'invalid_net_id' end
  local ok, entity = pcall(NetworkGetEntityFromNetworkId, netId)
  local exists = ok and entity and entity > 0 and DoesEntityExist(entity)
  exists = exists == true or exists == 1
  local entityType = exists and GetEntityType(entity) or 0
  if MZMechanicConfig.Debug == true then
    print(('[mz_mechanic][vehicle] stage=resolve net_id=%s entity_exists=%s entity_type=%s'):format(
      tostring(netId), tostring(exists), tostring(entityType)
    ))
  end
  if not exists or entityType ~= 2 then
    return nil, 'vehicle_not_found'
  end
  local plate = tostring(GetVehicleNumberPlateText(entity) or ''):upper():gsub('^%s+', ''):gsub('%s+$', '')
  if plate == '' then return nil, 'vehicle_plate_unavailable' end
  local vehicleOk, vehicleOrErr = call('mz_vehicles', 'GetVehicleByPlate', plate)
  if vehicleOk ~= true or type(vehicleOrErr) ~= 'table' then return nil, vehicleOrErr or 'vehicle_not_registered' end
  local coords = GetEntityCoords(entity)
  local function vehicleNumber(native, fallback)
    local nativeOk, value = pcall(native, entity)
    value, fallback = nativeOk and tonumber(value) or nil, tonumber(fallback)
    if value and (value ~= 0 or not fallback or fallback == 0) then return value end
    return fallback or value or 0
  end
  return {
    entity = entity,
    netId = netId,
    id = tonumber(vehicleOrErr.id),
    plate = tostring(vehicleOrErr.plate),
    model = tostring(vehicleOrErr.model),
    state = tostring(vehicleOrErr.state),
    bucket = type(GetEntityRoutingBucket) == 'function' and GetEntityRoutingBucket(entity) or 0,
    coords = { x = tonumber(coords.x), y = tonumber(coords.y), z = tonumber(coords.z) },
    engine = vehicleNumber(GetVehicleEngineHealth, vehicleOrErr.engine),
    body = vehicleNumber(GetVehicleBodyHealth, vehicleOrErr.body),
    speed = type(GetEntitySpeed) == 'function' and vehicleNumber(GetEntitySpeed, 0) or 0,
    dirt = type(GetVehicleDirtLevel) == 'function' and vehicleNumber(GetVehicleDirtLevel, 0) or 0,
    persisted = vehicleOrErr
  }
end

function Adapters.CanAccessVehicle(source, plate)
  return call('mz_vehicles', 'CanAccessVehicle', source, plate)
end

function Adapters.PersistVehicleRepair(customerSource, vehicle)
  return call('mz_vehicles', 'UpdateOutVehicleSnapshot', customerSource, vehicle.plate, {
    net_id = vehicle.netId,
    coords = vehicle.coords,
    engine_health = vehicle.engine,
    body_health = vehicle.body,
    destroyed = false
  }, {
    bypassRateLimit = true
  })
end

function Adapters.PersistVehicleProps(customerSource, vehicle, props)
  return call('mz_vehicles', 'UpdateOutVehicleSnapshot', customerSource, vehicle.plate, {
    net_id = vehicle.netId,
    coords = vehicle.coords,
    engine_health = vehicle.engine,
    body_health = vehicle.body,
    destroyed = false,
    props = props
  }, {
    bypassRateLimit = true
  })
end

function Adapters.Debit(source, amount, operationKey, orderId)
  if MZMechanicConfig.Payment.Enabled ~= true then return false, 'payments_disabled' end
  local ok, err = call('mz_economy', 'RemoveMoney', source, MZMechanicConfig.Payment.Account, amount, {
    idempotency_key = operationKey,
    category = 'vehicle_service',
    reason = 'mechanic_service_order',
    source_type = 'resource',
    external_ref = orderId,
    data = { channel = 'resource', order_id = orderId }
  })
  if ok ~= true then return false, err or 'payment_failed' end
  local receipt = call('mz_economy', 'GetOperationResult', source, operationKey, 'remove_money')
  if type(receipt) ~= 'table' or receipt.ok ~= true or receipt.found ~= true then
    return false, 'payment_receipt_unavailable'
  end
  return true, receipt
end

function Adapters.Refund(source, amount, operationKey, orderId)
  local ok, err = call('mz_economy', 'AddMoney', source, MZMechanicConfig.Payment.Account, amount, {
    idempotency_key = operationKey,
    category = 'vehicle_service_refund',
    reason = 'mechanic_service_refund',
    source_type = 'resource',
    external_ref = orderId,
    data = { channel = 'resource', order_id = orderId }
  })
  if ok ~= true then return false, err or 'refund_failed' end
  local receipt = call('mz_economy', 'GetOperationResult', source, operationKey, 'add_money')
  return type(receipt) == 'table' and receipt.ok == true, receipt
end

function Adapters.Capabilities()
  local vehiclesReady = call('mz_vehicles', 'IsVehicleDomainReady')
  local orgReady = started('mz_org') and call('mz_org', 'GetOrganizationReadiness') or nil
  local jobsReady = started('mz_jobs') and call('mz_jobs', 'GetJobsCapabilities') or nil
  return {
    economy = started('mz_economy'),
    vehicles = vehiclesReady == true,
    org = type(orgReady) == 'table' and orgReady.ready == true,
    jobsPlayable = type(jobsReady) == 'table' and jobsReady.playableJobs == true
  }
end

