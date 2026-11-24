local fieldDuty = false
local repairVehicle, tuningKey = 0, nil
local repairPoint, tuningPoint = 'mz_mechanic:repair', 'mz_mechanic:tuning'

function MZMechanicClient.HasFieldDuty() return fieldDuty end

local function removePoint(id)
  if GetResourceState('mz_interact') == 'started' then
    pcall(function() exports['mz_interact']:RemovePoint(id) end)
  end
end

local function hoodCoords(vehicle)
  local bone = GetEntityBoneIndexByName(vehicle, 'bonnet')
  if bone and bone ~= -1 then return GetWorldPositionOfEntityBone(vehicle, bone) end
  return GetOffsetFromEntityInWorldCoords(vehicle, 0.0, 1.6, 0.5)
end

RegisterNetEvent('mz_mechanic:client:interactRepair', function(vehicle)
  vehicle = tonumber(vehicle) or 0
  if not fieldDuty or vehicle == 0 or MZMechanicClient.IsOpen() or IsPedInAnyVehicle(PlayerPedId(), false)
    or MZMechanicClient.GetVehicleNetId(vehicle) <= 0 or GetEntitySpeed(vehicle) > 0.1 then return end
  if #(GetEntityCoords(PlayerPedId()) - hoodCoords(vehicle)) > 2.1 then return end
  MZMechanicClient.RequestRepair(vehicle)
end)

RegisterNetEvent('mz_mechanic:client:interactTuning', function(workshopCode, bayCode)
  local workshop = MZMechanicConfig.Workshops[tostring(workshopCode or '')]
  if not workshop or not workshop.tuning or workshop.tuning.enabled ~= true then return end
  for _, bay in ipairs(workshop.bays or {}) do
    if bay.code == bayCode then
      local coords = vec3(bay.coords.x, bay.coords.y, bay.coords.z)
      if #(GetEntityCoords(PlayerPedId()) - coords) <= (tonumber(workshop.tuning.marker and workshop.tuning.marker.interactDistance) or 2.4) + 0.35 then
        MZMechanicClient.OpenTuningBay(bay)
      end
      return
    end
  end
end)

CreateThread(function()
  while true do
    local ped = PlayerPedId()
    if not IsPedInAnyVehicle(ped, false) and (MZMechanicClient.FindNearbyVehicle(8.0) or 0) ~= 0 then
      local ok, result = pcall(lib.callback.await, 'mz_mechanic:server:fieldRepairStatus', false, {})
      fieldDuty = ok and type(result) == 'table' and result.ok == true and result.available == true
    else
      fieldDuty = false
    end
    Wait(3000)
  end
end)

CreateThread(function()
  while true do
    if GetResourceState('mz_interact') == 'started' then
      local ped = PlayerPedId()
      local coords = GetEntityCoords(ped)
      local vehicle = 0
      if fieldDuty and not MZMechanicClient.IsOpen() and not IsPedInAnyVehicle(ped, false) then
        vehicle = MZMechanicClient.FindNearbyVehicle(5.0) or 0
        if vehicle ~= 0 and (MZMechanicClient.GetVehicleNetId(vehicle) <= 0 or GetEntitySpeed(vehicle) > 0.1) then vehicle = 0 end
      end
      if vehicle ~= repairVehicle then
        if repairVehicle ~= 0 then removePoint(repairPoint); repairVehicle = 0 end
        if vehicle ~= 0 then
          local ok, added = pcall(function() return exports['mz_interact']:AddPoint({
            id = repairPoint, coords = hoodCoords(vehicle),
            follow = { entity = vehicle, bone = 'bonnet', offset = vec3(0.0, 1.6, 0.5) },
            drawDistance = 4.0, interactDistance = 1.75, marker = false,
            text = { enabled = true, ui = true, discovery = true, keyLabel = 'E', label = 'Solicitar reparo' },
            event = { type = 'client', name = 'mz_mechanic:client:interactRepair', args = { vehicle } }
          }) end)
          if ok and added == true then repairVehicle = vehicle end
        end
      end

      local nearest, nearestCode, nearestDistance
      if not MZMechanicClient.IsOpen() then
        for code, workshop in pairs(MZMechanicConfig.Workshops or {}) do
          if workshop.tuning and workshop.tuning.enabled == true then
            for _, bay in ipairs(workshop.bays or {}) do
              local position = vec3(bay.coords.x, bay.coords.y, bay.coords.z)
              local distance = #(coords - position)
              if distance <= 4.0 and (not nearestDistance or distance < nearestDistance) then
                nearest, nearestCode, nearestDistance = bay, code, distance
              end
            end
          end
        end
      end
      local key = nearest and (nearestCode .. ':' .. tostring(nearest.code)) or nil
      if key ~= tuningKey then
        if tuningKey then removePoint(tuningPoint); tuningKey = nil end
        if nearest then
          local ok, added = pcall(function() return exports['mz_interact']:AddPoint({
            id = tuningPoint, coords = nearest.coords, drawDistance = 4.0,
            interactDistance = tonumber(MZMechanicConfig.Workshops[nearestCode].tuning.marker and MZMechanicConfig.Workshops[nearestCode].tuning.marker.interactDistance) or 2.4,
            marker = false, text = { enabled = true, ui = true, discovery = true, keyLabel = 'E', label = 'Abrir tuning' },
            event = { type = 'client', name = 'mz_mechanic:client:interactTuning', args = { nearestCode, nearest.code } }
          }) end)
          if ok and added == true then tuningKey = key end
        end
      end
    else
      repairVehicle, tuningKey = 0, nil
    end
    Wait(500)
  end
end)

AddEventHandler('onClientResourceStop', function(resource)
  if resource == 'mz_interact' then repairVehicle, tuningKey = 0, nil
  elseif resource == GetCurrentResourceName() then removePoint(repairPoint); removePoint(tuningPoint) end
end)
