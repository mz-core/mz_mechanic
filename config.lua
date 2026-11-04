MZMechanicConfig = {
  Enabled = true,
  Debug = true,    -- habilitar temporariamente apenas durante homologacao P0
  Authorization = {
    Mode = 'auto', -- org first; standalone only when explicitly enabled below
    OrgPermission = 'mechanic.repair.basic',
    RequireOrgDuty = true,
    Standalone = {
      Enabled = false,
      AdminAce = 'group.mz_owner'
    }
  },
  Order = {
    TtlSeconds = 30 * 60,
    LockTtlSeconds = 20 * 60,
    InteractionDistance = 8.0,
    ApplyTimeoutSeconds = 90,
    MaxOpenOrdersPerCustomer = 1
  },
  Payment = {
    Enabled = true,
    Account = 'bank'
  },
  Services = {
    full_repair = {
      label = 'Reparo estrutural completo',
      enabled = true,
      basePrice = 450,
      pricePerDamagePoint = 2,
      maxPrice = 2450
    },
    cleaning = {
      label = 'Limpeza técnica',
      enabled = false,
      unavailableReason = 'mz_vehicles não persiste sujeira nesta Wave'
    }
  },
  Customization = {
    Enabled = true,
    PreviewTtlSeconds = 90,
    MaxItems = 64,
    Items = {
      spoilers = { label = 'Aerofólio', category = 'body', field = 'modSpoilers', slot = 0, kind = 'indexed', maxIndex = 99, basePrice = 350, stepPrice = 120 },
      front_bumper = { label = 'Para-choque dianteiro', category = 'body', field = 'modFrontBumper', slot = 1, kind = 'indexed', maxIndex = 99, basePrice = 420, stepPrice = 130 },
      rear_bumper = { label = 'Para-choque traseiro', category = 'body', field = 'modRearBumper', slot = 2, kind = 'indexed', maxIndex = 99, basePrice = 420, stepPrice = 130 },
      side_skirt = { label = 'Saias laterais', category = 'body', field = 'modSideSkirt', slot = 3, kind = 'indexed', maxIndex = 99, basePrice = 360, stepPrice = 110 },
      exhaust = { label = 'Escapamento', category = 'body', field = 'modExhaust', slot = 4, kind = 'indexed', maxIndex = 99, basePrice = 300, stepPrice = 95 },
      frame = { label = 'Chassi', category = 'body', field = 'modFrame', slot = 5, kind = 'indexed', maxIndex = 99, basePrice = 380, stepPrice = 115 },
      grille = { label = 'Grade', category = 'body', field = 'modGrille', slot = 6, kind = 'indexed', maxIndex = 99, basePrice = 280, stepPrice = 90 },
      hood = { label = 'Capô', category = 'body', field = 'modHood', slot = 7, kind = 'indexed', maxIndex = 99, basePrice = 450, stepPrice = 140 },
      left_fender = { label = 'Para-lama esquerdo', category = 'body', field = 'modFender', slot = 8, kind = 'indexed', maxIndex = 99, basePrice = 320, stepPrice = 100 },
      right_fender = { label = 'Para-lama direito', category = 'body', field = 'modRightFender', slot = 9, kind = 'indexed', maxIndex = 99, basePrice = 320, stepPrice = 100 },
      roof = { label = 'Teto', category = 'body', field = 'modRoof', slot = 10, kind = 'indexed', maxIndex = 99, basePrice = 400, stepPrice = 125 },
      engine = { label = 'Motor', category = 'performance', field = 'modEngine', slot = 11, kind = 'indexed', maxIndex = 10, basePrice = 1200, stepPrice = 650 },
      brakes = { label = 'Freios', category = 'performance', field = 'modBrakes', slot = 12, kind = 'indexed', maxIndex = 10, basePrice = 700, stepPrice = 400 },
      transmission = { label = 'Transmissão', category = 'performance', field = 'modTransmission', slot = 13, kind = 'indexed', maxIndex = 10, basePrice = 900, stepPrice = 500 },
      horns = { label = 'Buzina', category = 'extras', field = 'modHorns', slot = 14, kind = 'indexed', maxIndex = 99, basePrice = 180, stepPrice = 45 },
      suspension = { label = 'Suspensão', category = 'performance', field = 'modSuspension', slot = 15, kind = 'indexed', maxIndex = 10, basePrice = 500, stepPrice = 250 },
      armor = { label = 'Blindagem', category = 'performance', field = 'modArmor', slot = 16, kind = 'indexed', maxIndex = 10, basePrice = 1300, stepPrice = 800 },
      kit_17 = { label = 'Kit especial 17', category = 'extras', field = 'modKit17', slot = 17, kind = 'indexed', maxIndex = 99, basePrice = 400, stepPrice = 130 },
      turbo = { label = 'Turbo', category = 'performance', field = 'modTurbo', slot = 18, kind = 'toggle', fixedPrice = 2800 },
      kit_19 = { label = 'Kit especial 19', category = 'extras', field = 'modKit19', slot = 19, kind = 'indexed', maxIndex = 99, basePrice = 400, stepPrice = 130 },
      tyre_smoke = { label = 'Fumaça dos pneus', category = 'wheels', field = 'modSmokeEnabled', slot = 20, kind = 'toggle', fixedPrice = 650 },
      kit_21 = { label = 'Kit especial 21', category = 'extras', field = 'modKit21', slot = 21, kind = 'indexed', maxIndex = 99, basePrice = 400, stepPrice = 130 },
      xenon = { label = 'Faróis xenon', category = 'lighting', field = 'modXenon', slot = 22, kind = 'toggle', fixedPrice = 900 },
      wheel_type = { label = 'Categoria das rodas', category = 'wheels', field = 'wheels', kind = 'range', minIndex = 0, maxIndex = 12, optionLabel = 'Categoria %02d', fixedPrice = 450 },
      front_wheels = { label = 'Rodas dianteiras', category = 'wheels', field = 'modFrontWheels', slot = 23, kind = 'indexed', maxIndex = 99, basePrice = 500, stepPrice = 80 },
      rear_wheels = { label = 'Rodas traseiras', category = 'wheels', field = 'modBackWheels', slot = 24, kind = 'indexed', maxIndex = 99, basePrice = 500, stepPrice = 80 },
      custom_tyres_front = { label = 'Pneus customizados dianteiros', category = 'wheels', field = 'modCustomTiresF', kind = 'toggle', requiresSlot = 23, fixedPrice = 350 },
      custom_tyres_rear = { label = 'Pneus customizados traseiros', category = 'wheels', field = 'modCustomTiresR', kind = 'toggle', requiresSlot = 24, fixedPrice = 350 },
      bulletproof_tyres = { label = 'Pneus à prova de balas', category = 'wheels', field = 'bulletProofTyres', kind = 'toggle', fixedPrice = 1600 },
      drift_tyres = { label = 'Pneus de drift', category = 'wheels', field = 'driftTyres', kind = 'toggle', fixedPrice = 1100 },
      plate_holder = { label = 'Suporte de placa', category = 'body', field = 'modPlateHolder', slot = 25, kind = 'indexed', maxIndex = 99, basePrice = 180, stepPrice = 55 },
      vanity_plate = { label = 'Placa decorativa', category = 'body', field = 'modVanityPlate', slot = 26, kind = 'indexed', maxIndex = 99, basePrice = 220, stepPrice = 65 },
      trim_a = { label = 'Acabamento interno A', category = 'interior', field = 'modTrimA', slot = 27, kind = 'indexed', maxIndex = 99, basePrice = 320, stepPrice = 85 },
      ornaments = { label = 'Ornamentos', category = 'interior', field = 'modOrnaments', slot = 28, kind = 'indexed', maxIndex = 99, basePrice = 180, stepPrice = 55 },
      dashboard = { label = 'Painel', category = 'interior', field = 'modDashboard', slot = 29, kind = 'indexed', maxIndex = 99, basePrice = 350, stepPrice = 90 },
      dials = { label = 'Mostradores', category = 'interior', field = 'modDial', slot = 30, kind = 'indexed', maxIndex = 99, basePrice = 220, stepPrice = 65 },
      door_speakers = { label = 'Alto-falantes das portas', category = 'interior', field = 'modDoorSpeaker', slot = 31, kind = 'indexed', maxIndex = 99, basePrice = 260, stepPrice = 70 },
      seats = { label = 'Bancos', category = 'interior', field = 'modSeats', slot = 32, kind = 'indexed', maxIndex = 99, basePrice = 420, stepPrice = 110 },
      steering_wheel = { label = 'Volante', category = 'interior', field = 'modSteeringWheel', slot = 33, kind = 'indexed', maxIndex = 99, basePrice = 300, stepPrice = 80 },
      shifter = { label = 'Alavanca de câmbio', category = 'interior', field = 'modShifterLeavers', slot = 34, kind = 'indexed', maxIndex = 99, basePrice = 220, stepPrice = 65 },
      plaque = { label = 'Plaqueta interna', category = 'interior', field = 'modAPlate', slot = 35, kind = 'indexed', maxIndex = 99, basePrice = 180, stepPrice = 55 },
      speakers = { label = 'Sistema de som', category = 'interior', field = 'modSpeakers', slot = 36, kind = 'indexed', maxIndex = 99, basePrice = 350, stepPrice = 95 },
      trunk = { label = 'Porta-malas', category = 'interior', field = 'modTrunk', slot = 37, kind = 'indexed', maxIndex = 99, basePrice = 340, stepPrice = 90 },
      hydraulics = { label = 'Hidráulica', category = 'performance', field = 'modHydrolic', slot = 38, kind = 'indexed', maxIndex = 99, basePrice = 900, stepPrice = 240 },
      engine_block = { label = 'Bloco do motor', category = 'body', field = 'modEngineBlock', slot = 39, kind = 'indexed', maxIndex = 99, basePrice = 380, stepPrice = 105 },
      air_filter = { label = 'Filtro de ar', category = 'body', field = 'modAirFilter', slot = 40, kind = 'indexed', maxIndex = 99, basePrice = 300, stepPrice = 85 },
      struts = { label = 'Barras estruturais', category = 'body', field = 'modStruts', slot = 41, kind = 'indexed', maxIndex = 99, basePrice = 330, stepPrice = 90 },
      arch_cover = { label = 'Cobertura dos arcos', category = 'body', field = 'modArchCover', slot = 42, kind = 'indexed', maxIndex = 99, basePrice = 300, stepPrice = 85 },
      aerials = { label = 'Antenas', category = 'body', field = 'modAerials', slot = 43, kind = 'indexed', maxIndex = 99, basePrice = 180, stepPrice = 55 },
      trim_b = { label = 'Acabamento externo', category = 'body', field = 'modTrimB', slot = 44, kind = 'indexed', maxIndex = 99, basePrice = 320, stepPrice = 90 },
      tank = { label = 'Tanque', category = 'body', field = 'modTank', slot = 45, kind = 'indexed', maxIndex = 99, basePrice = 340, stepPrice = 95 },
      windows = { label = 'Janelas', category = 'body', field = 'modWindows', slot = 46, kind = 'indexed', maxIndex = 99, basePrice = 300, stepPrice = 85 },
      kit_47 = { label = 'Kit especial 47', category = 'extras', field = 'modKit47', slot = 47, kind = 'indexed', maxIndex = 99, basePrice = 400, stepPrice = 130 },
      livery = { label = 'Livery', category = 'paint', field = 'modLivery', slot = 48, kind = 'indexed', counter = 'livery', maxIndex = 99, basePrice = 650, stepPrice = 150 },
      kit_49 = { label = 'Kit especial 49', category = 'extras', field = 'modKit49', slot = 49, kind = 'indexed', maxIndex = 99, basePrice = 400, stepPrice = 130 },
      roof_livery = { label = 'Livery do teto', category = 'paint', field = 'liveryRoof', kind = 'indexed', counter = 'roof_livery', maxIndex = 99, basePrice = 450, stepPrice = 120 },
      primary_color = { label = 'Pintura primária GTA', category = 'paint', field = 'color1', group = 'paint_primary', kind = 'range', minIndex = 0, maxIndex = 160, optionLabel = 'Cor %03d', fixedPrice = 700 },
      primary_custom = { label = 'Pintura primária personalizada', category = 'paint', field = 'color1', group = 'paint_primary', kind = 'rgb', fixedPrice = 950 },
      secondary_color = { label = 'Pintura secundária GTA', category = 'paint', field = 'color2', group = 'paint_secondary', kind = 'range', minIndex = 0, maxIndex = 160, optionLabel = 'Cor %03d', fixedPrice = 600 },
      secondary_custom = { label = 'Pintura secundária personalizada', category = 'paint', field = 'color2', group = 'paint_secondary', kind = 'rgb', fixedPrice = 850 },
      pearlescent = { label = 'Perolado', category = 'paint', field = 'pearlescentColor', kind = 'range', minIndex = 0, maxIndex = 160, optionLabel = 'Cor %03d', fixedPrice = 500 },
      wheel_color = { label = 'Cor das rodas', category = 'paint', field = 'wheelColor', kind = 'range', minIndex = 0, maxIndex = 160, optionLabel = 'Cor %03d', fixedPrice = 400 },
      dashboard_color = { label = 'Cor do painel', category = 'interior', field = 'dashboardColor', kind = 'range', minIndex = 0, maxIndex = 160, optionLabel = 'Cor %03d', fixedPrice = 350 },
      interior_color = { label = 'Cor do interior', category = 'interior', field = 'interiorColor', kind = 'range', minIndex = 0, maxIndex = 160, optionLabel = 'Cor %03d', fixedPrice = 450 },
      window_tint = { label = 'Película dos vidros', category = 'paint', field = 'windowTint', kind = 'range', minIndex = -1, maxIndex = 6, originalLabel = 'Sem película', optionLabel = 'Película %02d', fixedPrice = 300 },
      plate_style = { label = 'Estilo da placa', category = 'extras', field = 'plateIndex', kind = 'range', minIndex = 0, maxIndex = 5, optionLabel = 'Estilo %02d', fixedPrice = 180 },
      xenon_color = { label = 'Cor xenon GTA', category = 'lighting', field = 'xenonColor', group = 'xenon_color', kind = 'range', minIndex = -1, maxIndex = 12, originalLabel = 'Branco original', optionLabel = 'Tom %02d', fixedPrice = 450 },
      xenon_custom = { label = 'Cor xenon personalizada', category = 'lighting', field = 'xenonColor', group = 'xenon_color', kind = 'rgb', fixedPrice = 650 },
      neon_left = { label = 'Neon esquerdo', category = 'lighting', field = 'neonEnabled', key = 1, kind = 'toggle', fixedPrice = 250 },
      neon_right = { label = 'Neon direito', category = 'lighting', field = 'neonEnabled', key = 2, kind = 'toggle', fixedPrice = 250 },
      neon_front = { label = 'Neon dianteiro', category = 'lighting', field = 'neonEnabled', key = 3, kind = 'toggle', fixedPrice = 250 },
      neon_rear = { label = 'Neon traseiro', category = 'lighting', field = 'neonEnabled', key = 4, kind = 'toggle', fixedPrice = 250 },
      neon_color = { label = 'Cor do neon', category = 'lighting', field = 'neonColor', kind = 'rgb', fixedPrice = 600 },
      tyre_smoke_color = { label = 'Cor da fumaça', category = 'wheels', field = 'tyreSmokeColor', kind = 'rgb', fixedPrice = 450 }
    }
  },
  Workshops = {
    bennys = {
      label = "Benny's Motorworks",
      orgCode = 'mechanic',
      coords = { x = -211.55, y = -1324.55, z = 30.89 },
      radius = 45.0,
      tuning = {
        enabled = true,
        blip = { sprite = 446, color = 3, scale = 0.75 },
        marker = { drawDistance = 24.0, interactDistance = 2.4 }
      },
      bays = {
        { code = 'bay_1', label = 'Elevador 01', coords = { x = -211.67, y = -1324.81, z = 30.26 }, radius = 3.6 },
        { code = 'bay_2', label = 'Elevador 02', coords = { x = -196.35, y = -1324.20, z = 30.89 }, radius = 3.6 }
      }
    }
  }
}

for extraId = 0, 20 do
  MZMechanicConfig.Customization.Items[('extra_%02d'):format(extraId)] = {
    label = ('Extra %02d'):format(extraId),
    category = 'extras',
    field = 'extras',
    key = tostring(extraId),
    extraId = extraId,
    kind = 'toggle',
    fixedPrice = 220
  }
end
