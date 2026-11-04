local handle

local function nearWorkshop()
  local coords = GetEntityCoords(PlayerPedId())
  for _, workshop in pairs(MZMechanicConfig.Workshops or {}) do
    local target = vector3(workshop.coords.x, workshop.coords.y, workshop.coords.z)
    if #(coords - target) <= (tonumber(workshop.radius) or 30.0) then return true end
  end
  return false
end

local function registerRadial()
  if GetResourceState('mz_radialmenu') ~= 'started' then return end
  local ok, result = exports['mz_radialmenu']:RegisterOption({
    id = 'mechanic_panel',
    label = 'Oficina',
    icon = 'wrench',
    canOpen = function() return nearWorkshop() end,
    onSelect = function()
      MZMechanicClient.OpenNearby('atendimento')
      return true
    end
  })
  if ok then handle = result end
end

local function removeRadial()
  if handle and GetResourceState('mz_radialmenu') == 'started' then
    exports['mz_radialmenu']:RemoveOption(handle)
  end
  handle = nil
end

CreateThread(function()
  Wait(0)
  registerRadial()
end)

RegisterNetEvent('mz_radialmenu:client:ready', registerRadial)

AddEventHandler('onClientResourceStart', function(resourceName)
  if resourceName == 'mz_radialmenu' then registerRadial() end
end)

AddEventHandler('onClientResourceStop', function(resourceName)
  if resourceName == GetCurrentResourceName() then removeRadial() end
end)
