MZMechanicRepository = MZMechanicRepository or {}

local Repository = MZMechanicRepository

local function decode(value, fallback)
  if type(value) == 'table' then return value end
  local ok, result = pcall(json.decode, tostring(value or ''))
  return ok and type(result) == 'table' and result or (fallback or {})
end

local function encode(value)
  return json.encode(type(value) == 'table' and value or {})
end

local function normalize(row)
  if type(row) ~= 'table' then return nil end
  row.id = tonumber(row.id)
  row.vehicle_id = tonumber(row.vehicle_id)
  row.lock_vehicle_id = tonumber(row.lock_vehicle_id)
  row.revision = tonumber(row.revision) or 1
  row.diagnostic = decode(row.diagnostic_json)
  row.quote = decode(row.quote_json)
  row.payment = decode(row.payment_json)
  row.application = decode(row.application_json)
  row.diagnostic_json, row.quote_json, row.payment_json, row.application_json = nil, nil, nil, nil
  return row
end

function Repository.CheckReady()
  for _, tableName in ipairs({ 'mz_mechanic_orders', 'mz_mechanic_order_events', 'mz_mechanic_operations', 'mz_mechanic_staff' }) do
    local ok = pcall(function() MySQL.scalar.await(('SELECT 1 FROM %s LIMIT 1'):format(tableName)) end)
    if not ok then return false, 'schema_not_installed:' .. tableName end
  end
  return true
end

function Repository.GetOrder(publicId)
  return normalize(MySQL.single.await('SELECT * FROM mz_mechanic_orders WHERE public_id = ? LIMIT 1', { publicId }))
end

function Repository.GetOperation(orderId, operationKey)
  local row = MySQL.single.await([[
    SELECT request_fingerprint, result_json FROM mz_mechanic_operations
    WHERE order_id = ? AND operation_key = ? LIMIT 1
  ]], { orderId, operationKey })
  if not row then return nil end
  row.result = decode(row.result_json)
  row.result_json = nil
  return row
end

function Repository.GetActiveByVehicle(vehicleId)
  return normalize(MySQL.single.await([[
    SELECT * FROM mz_mechanic_orders WHERE lock_vehicle_id = ? LIMIT 1
  ]], { vehicleId }))
end

function Repository.CountActiveForCustomer(citizenid)
  return tonumber(MySQL.scalar.await([[
    SELECT COUNT(*) FROM mz_mechanic_orders
    WHERE customer_citizenid = ? AND state NOT IN ('completed', 'cancelled', 'failed')
  ]], { citizenid })) or 0
end

function Repository.CreateOrder(data)
  local existing = MySQL.single.await([[
    SELECT * FROM mz_mechanic_orders
    WHERE customer_citizenid = ? AND create_key = ? LIMIT 1
  ]], { data.customerCitizenId, data.requestKey })
  if existing then
    existing = normalize(existing)
    if existing.vehicle_id ~= data.vehicleId or existing.workshop_code ~= data.workshopCode then
      return nil, 'idempotency_conflict'
    end
    return existing, nil, true
  end

  if Repository.CountActiveForCustomer(data.customerCitizenId) >= (tonumber(data.maxOpenOrders) or 1) then
    return nil, 'customer_order_limit'
  end
  if Repository.GetActiveByVehicle(data.vehicleId) then return nil, 'vehicle_locked' end
  local ok, insertId = pcall(function()
    return MySQL.insert.await([[
      INSERT INTO mz_mechanic_orders (
        public_id, workshop_code, bay_code, vehicle_id, lock_vehicle_id, vehicle_plate,
        customer_citizenid, state, revision, create_key, application_json, expires_at, lock_expires_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, 'created', 1, ?, ?,
        DATE_ADD(UTC_TIMESTAMP(), INTERVAL ? SECOND), DATE_ADD(UTC_TIMESTAMP(), INTERVAL ? SECOND))
    ]], {
      data.publicId, data.workshopCode, data.bayCode, data.vehicleId, data.vehicleId,
      data.vehiclePlate, data.customerCitizenId, data.requestKey, encode({
        netId = data.netId,
        status = 'not_started'
      }), data.ttlSeconds, data.lockTtlSeconds
    })
  end)
  if not ok or not insertId then
    if Repository.GetActiveByVehicle(data.vehicleId) then return nil, 'vehicle_locked' end
    return nil, 'database_error'
  end
  local order = Repository.GetOrder(data.publicId)
  Repository.AppendEvent(order.id, 'created', data.customerCitizenId, 'customer', { requestKey = data.requestKey })
  return order
end

function Repository.AppendEvent(orderId, eventType, actorId, actorRole, payload, operationKey)
  return MySQL.insert.await([[
    INSERT INTO mz_mechanic_order_events
      (order_id, event_type, actor_id, actor_role, operation_key, payload_json)
    VALUES (?, ?, ?, ?, ?, ?)
  ]], { orderId, eventType, actorId, actorRole, operationKey, encode(payload) })
end

function Repository.Transition(order, args)
  local prior = Repository.GetOperation(order.id, args.operationKey)
  if prior then
    if prior.request_fingerprint ~= args.fingerprint then return nil, 'idempotency_conflict' end
    return Repository.GetOrder(order.public_id), nil, true
  end
  if order.last_operation_key == args.operationKey then
    if order.last_operation_fingerprint ~= args.fingerprint then return nil, 'idempotency_conflict' end
    return Repository.GetOrder(order.public_id), nil, true
  end

  local sets = {
    'state = ?', 'revision = revision + 1', 'last_operation_key = ?',
    'last_operation_fingerprint = ?', 'updated_at = UTC_TIMESTAMP()'
  }
  local params = { args.toState, args.operationKey, args.fingerprint }
  local patch = args.patch or {}
  local jsonFields = {
    diagnostic = 'diagnostic_json', quote = 'quote_json', payment = 'payment_json', application = 'application_json'
  }
  for key, column in pairs(jsonFields) do
    if patch[key] ~= nil then sets[#sets + 1] = column .. ' = ?'; params[#params + 1] = encode(patch[key]) end
  end
  if patch.assignedMechanicCitizenId then
    sets[#sets + 1] = 'assigned_mechanic_citizenid = ?'
    params[#params + 1] = patch.assignedMechanicCitizenId
  elseif patch.clearAssigned == true then
    sets[#sets + 1] = 'assigned_mechanic_citizenid = NULL'
  end
  if patch.cancelReason then sets[#sets + 1] = 'cancel_reason = ?'; params[#params + 1] = patch.cancelReason end
  if patch.failureCode then sets[#sets + 1] = 'failure_code = ?'; params[#params + 1] = patch.failureCode end
  if patch.releaseLock == true then sets[#sets + 1] = 'lock_vehicle_id = NULL'; sets[#sets + 1] = 'lock_expires_at = NULL' end
  if args.toState == 'completed' then sets[#sets + 1] = 'completed_at = UTC_TIMESTAMP()' end

  params[#params + 1] = order.id
  params[#params + 1] = args.expectedVersion
  params[#params + 1] = args.fromState
  local affected = MySQL.update.await(([[
    UPDATE mz_mechanic_orders SET %s WHERE id = ? AND revision = ? AND state = ?
  ]]):format(table.concat(sets, ', ')), params)
  if tonumber(affected) ~= 1 then
    prior = Repository.GetOperation(order.id, args.operationKey)
    if prior and prior.request_fingerprint == args.fingerprint then
      return Repository.GetOrder(order.public_id), nil, true
    end
    local current = Repository.GetOrder(order.public_id)
    if current and current.last_operation_key == args.operationKey then
      if current.last_operation_fingerprint ~= args.fingerprint then return nil, 'idempotency_conflict' end
      return current, nil, true
    end
    return nil, 'order_conflict'
  end

  local updated = Repository.GetOrder(order.public_id)
  local result = { orderId = updated.public_id, state = updated.state, revision = updated.revision }
  local operationOk = pcall(function()
    MySQL.insert.await([[
      INSERT INTO mz_mechanic_operations
        (order_id, operation_key, request_fingerprint, result_json)
      VALUES (?, ?, ?, ?)
    ]], { order.id, args.operationKey, args.fingerprint, encode(result) })
  end)
  if not operationOk then
    print(('[mz_mechanic] operation journal delayed order=%s key=%s'):format(order.public_id, args.operationKey))
  end
  local eventOk = pcall(Repository.AppendEvent, order.id, args.eventType or args.toState, args.actorId, args.actorRole, args.eventPayload or result, args.operationKey)
  if not eventOk then print(('[mz_mechanic] event journal delayed order=%s key=%s'):format(order.public_id, args.operationKey)) end
  return updated
end

function Repository.Assign(order, mechanicCitizenId, operationKey, fingerprint, expectedVersion)
  return Repository.Transition(order, {
    fromState = order.state,
    toState = order.state,
    expectedVersion = expectedVersion,
    operationKey = operationKey,
    fingerprint = fingerprint,
    actorId = mechanicCitizenId,
    actorRole = 'mechanic',
    eventType = 'assigned',
    patch = { assignedMechanicCitizenId = mechanicCitizenId }
  })
end

function Repository.ListForCustomer(citizenid)
  local rows = MySQL.query.await([[
    SELECT * FROM mz_mechanic_orders WHERE customer_citizenid = ?
    ORDER BY id DESC LIMIT 30
  ]], { citizenid }) or {}
  for index, row in ipairs(rows) do rows[index] = normalize(row) end
  return rows
end

function Repository.ListForWorkshop(workshopCode)
  local rows = MySQL.query.await([[
    SELECT * FROM mz_mechanic_orders WHERE workshop_code = ?
      AND state NOT IN ('completed', 'cancelled', 'failed')
    ORDER BY id ASC LIMIT 50
  ]], { workshopCode }) or {}
  for index, row in ipairs(rows) do rows[index] = normalize(row) end
  return rows
end

function Repository.GetStandaloneBinding(citizenid, workshopCode)
  return MySQL.single.await([[
    SELECT citizenid, workshop_code, role FROM mz_mechanic_staff
    WHERE citizenid = ? AND workshop_code = ? AND active = 1 LIMIT 1
  ]], { citizenid, workshopCode })
end

function Repository.SetStandaloneBinding(citizenid, workshopCode, role, grantedBy)
  return MySQL.update.await([[
    INSERT INTO mz_mechanic_staff (citizenid, workshop_code, role, active, granted_by)
    VALUES (?, ?, ?, 1, ?)
    ON DUPLICATE KEY UPDATE role = VALUES(role), active = 1, granted_by = VALUES(granted_by), updated_at = UTC_TIMESTAMP()
  ]], { citizenid, workshopCode, role, grantedBy })
end

function Repository.RemoveStandaloneBinding(citizenid, workshopCode, grantedBy)
  return MySQL.update.await([[
    UPDATE mz_mechanic_staff SET active = 0, granted_by = ?, updated_at = UTC_TIMESTAMP()
    WHERE citizenid = ? AND workshop_code = ?
  ]], { grantedBy, citizenid, workshopCode })
end

function Repository.ReleaseExpired()
  MySQL.update.await([[
    UPDATE mz_mechanic_orders SET state = 'pending_reconciliation', failure_code = 'expired_after_payment_started',
      updated_at = UTC_TIMESTAMP(), revision = revision + 1
    WHERE state IN ('in_progress', 'pending_apply') AND expires_at < UTC_TIMESTAMP()
  ]])
  return MySQL.update.await([[
    UPDATE mz_mechanic_orders SET state = 'failed', failure_code = 'expired',
      lock_vehicle_id = NULL, lock_expires_at = NULL, updated_at = UTC_TIMESTAMP(), revision = revision + 1
    WHERE state IN ('created', 'diagnosed', 'quoted', 'accepted')
      AND expires_at < UTC_TIMESTAMP()
  ]])
end

function Repository.HandlePlayerDrop(citizenid)
  MySQL.update.await([[
    UPDATE mz_mechanic_orders SET assigned_mechanic_citizenid = NULL,
      updated_at = UTC_TIMESTAMP(), revision = revision + 1
    WHERE assigned_mechanic_citizenid = ? AND state IN ('created', 'diagnosed', 'quoted', 'accepted')
  ]], { citizenid })
  MySQL.update.await([[
    UPDATE mz_mechanic_orders SET state = 'pending_reconciliation', failure_code = 'mechanic_disconnected',
      updated_at = UTC_TIMESTAMP(), revision = revision + 1
    WHERE assigned_mechanic_citizenid = ? AND state IN ('in_progress', 'pending_apply')
  ]], { citizenid })
end

function Repository.MarkInterruptedRuntime()
  return MySQL.update.await([[
    UPDATE mz_mechanic_orders SET state = 'pending_reconciliation', failure_code = 'runtime_interrupted',
      updated_at = UTC_TIMESTAMP(), revision = revision + 1
    WHERE state IN ('in_progress', 'pending_apply')
  ]])
end

