fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'mz_mechanic'
author 'Mazus / MZ Framework'
description 'Server-authoritative instant workshop, mechanic duty and vehicle service flow'
version '0.1.0'

shared_scripts {
  '@ox_lib/init.lua',
  'config.lua',
  'shared/contracts.lua'
}

client_scripts {
  'client/main.lua',
  'client/target.lua',
  'client/radialmenu.lua'
}

server_scripts {
  'server/adapters.lua',
  'server/service.lua',
  'server/main.lua'
}

ui_page 'web/dist/index.html'

files {
  'web/dist/index.html',
  'web/dist/assets/*'
}

dependencies {
  'ox_lib',
  'mz_lib',
  'mz_core',
  'mz_economy',
  'mz_org',
  'mz_vehicles'
}

