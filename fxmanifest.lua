fx_version 'cerulean'
game 'gta5'
lua54 'yes'
author 'AX Development'
description 'AX_QuestCreator - Sistema de Misiones para Facciones'
version '1.0.0'

shared_scripts {
    '@ox_lib/init.lua',
    'config.lua'
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server.lua'
}

client_scripts {
    'client.lua'
}

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/style.css',
    'html/script.js'
}

dependencies {
    'es_extended',
    'oxmysql',
    'ox_inventory',
    'ox_lib'
}