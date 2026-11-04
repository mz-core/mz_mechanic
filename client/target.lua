local repairLabel = 'Solicitar reparo'
local blips = {}

local function validVehicle(entity)
  return MZMechanicClient.GetVehicleNetId(entity) > 0
end

local function inTuningBay(entity)
  if not validVehicle(entity) then return false end
  return MZMechanicClient.GetTuningBay(entity) ~= nil and GetEntitySpeed(entity) <= 0.1
end

local function registerTarget()
  if GetResourceState('mz_target') ~= 'started' then return end
  exports['mz_target']:AddGlobalVehicle({
    distance = 3.0,
    options = {
      {
        label = repairLabel,
        icon = 'wrench',
        distance = 3.0,
        canInteract = inTuningBay,
        action = function(entity) MZMechanicClient.RequestRepair(entity) end
      }
    }
  })
end

local function removeTarget()
  if GetResourceState('mz_target') == 'started' then
    exports['mz_target']:RemoveGlobalVehicle({ repairLabel })
  end
end

local function displayTuningHelp()
  BeginTextCommandDisplayHelp('STRING')
  AddTextComponentSubstringPlayerName('[E] Abrir tuning')
  EndTextCommandDisplayHelp(0, false, true, -1)
end

local function markerLoop()
  while true do
    local sleep = 750
    if not MZMechanicClient.IsOpen() then
      local playerCoords = GetEntityCoords(PlayerPedId())
      for _, workshop in pairs(MZMechanicConfig.Workshops or {}) do
        local tuning = workshop.tuning
        local marker = tuning and tuning.marker or {}
        if tuning and tuning.enabled == true then
          for _, bay in ipairs(workshop.bays or {}) do
            local dx, dy, dz = playerCoords.x - bay.coords.x, playerCoords.y - bay.coords.y, playerCoords.z - bay.coords.z
            local bayDistance = math.sqrt(dx * dx + dy * dy + dz * dz)
            if bayDistance <= (tonumber(marker.drawDistance) or 24.0) then
              sleep = 0
              DrawMarker(1, bay.coords.x, bay.coords.y, bay.coords.z - 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
                2.4, 2.4, 0.25, 33, 212, 233, 155, false, false, 2, false, nil, nil, false)
              if bayDistance <= (tonumber(marker.interactDistance) or 2.4) then
                displayTuningHelp()
                if IsControlJustReleased(0, 38) then MZMechanicClient.OpenTuningBay(bay) end
              end
            end
          end
        end
      end
    end
    Wait(sleep)
  end
end

local function createBlips()
  for _, workshop in pairs(MZMechanicConfig.Workshops or {}) do
    local tuning = workshop.tuning
    if tuning and tuning.enabled == true and tuning.blip then
      local blip = AddBlipForCoord(workshop.coords.x, workshop.coords.y, workshop.coords.z)
      SetBlipSprite(blip, tonumber(tuning.blip.sprite) or 446)
      SetBlipColour(blip, tonumber(tuning.blip.color) or 3)
      SetBlipScale(blip, tonumber(tuning.blip.scale) or 0.75)
      SetBlipAsShortRange(blip, true)
      BeginTextCommandSetBlipName('STRING')
      AddTextComponentString(('MZ Automotive · %s'):format(workshop.label))
      EndTextCommandSetBlipName(blip)
      blips[#blips + 1] = blip
    end
  end
end

local function removeBlips()
  for _, blip in ipairs(blips) do
    if DoesBlipExist(blip) then RemoveBlip(blip) end
  end
  blips = {}
end

CreateThread(function()
  Wait(0)
  registerTarget()
  createBlips()
end)

CreateThread(markerLoop)

AddEventHandler('onClientResourceStart', function(resourceName)
  if resourceName == 'mz_target' then registerTarget() end
end)

AddEventHandler('onClientResourceStop', function(resourceName)
  if resourceName == GetCurrentResourceName() then
    removeTarget()
    removeBlips()
  end
end)

