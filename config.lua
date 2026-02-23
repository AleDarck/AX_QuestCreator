-- ============================================================
--  AX_QuestCreator | config.lua
--  Configuración global del sistema de misiones
-- ============================================================

Config = {}

-- ─── GENERAL ────────────────────────────────────────────────
Config.Locale         = 'es'           -- Idioma de notificaciones
Config.DebugMode      = false          -- true = logs en consola
Config.AdminCommand   = 'questcreator' -- Comando para abrir el Creator Panel (solo admins)

-- ─── NOTIFICACIONES ─────────────────────────────────────────
-- 'ox_lib' | 'esx' | 'custom'
Config.NotifyType = 'esx'

-- ─── BLIPS ──────────────────────────────────────────────────
Config.Blips = {
    ELIMINATE = { sprite = 309, color = 1,  scale = 0.8, label = 'Misión: Eliminar'  },
    COLLECT   = { sprite = 326, color = 2,  scale = 0.8, label = 'Misión: Recolectar' },
    DEFEND    = { sprite = 280, color = 3,  scale = 0.8, label = 'Misión: Defender'  },
    REPAIR    = { sprite = 446, color = 5,  scale = 0.8, label = 'Misión: Reparar'   },
}

-- ─── ZONAS ──────────────────────────────────────────────────
Config.ZoneColor         = { r = 255, g = 50,  b = 50,  a = 80  }  -- Color del círculo de misión
Config.ZoneColorDefend   = { r = 50,  g = 255, b = 100, a = 80  }  -- Color zona DEFEND
Config.ZoneColorRepair   = { r = 50,  g = 150, b = 255, a = 80  }  -- Color zona REPAIR
Config.MarkerType        = 1     -- Tipo de marcador en suelo
Config.MarkerScale       = 2.0   -- Tamaño del marcador
Config.InteractDistance  = 2.5   -- Distancia para interactuar con puntos REPAIR

-- ─── PROGRESBAR ─────────────────────────────────────────────
Config.RepairTime   = 10000  -- ms base para reparar un punto (override por objective_data)
Config.UseProgressBar = true -- Usa ox_lib progressbar

-- ─── DIFICULTAD → MULTIPLICADOR DE RECOMPENSA ───────────────
Config.DifficultyMultiplier = {
    easy    = 1.0,
    medium  = 1.5,
    hard    = 2.0,
    extreme = 3.0
}

-- ─── COLORES DE DIFICULTAD (para UI) ────────────────────────
Config.DifficultyColors = {
    easy    = '#4CAF50',
    medium  = '#FF9800',
    hard    = '#F44336',
    extreme = '#9C27B0'
}

Config.DifficultyLabels = {
    easy    = 'FÁCIL',
    medium  = 'MEDIA',
    hard    = 'DIFÍCIL',
    extreme = 'EXTREMA'
}

-- ─── TIPOS DE MISIÓN (para UI) ──────────────────────────────
Config.QuestTypeLabels = {
    ELIMINATE = '💀 ELIMINAR',
    COLLECT   = '📦 RECOLECTAR',
    DEFEND    = '🪓 DEFENDER',
    REPAIR    = '🔧 REPARAR'
}

-- ─── INTEGRACIÓN CON AX_FactionMenu ─────────────────────────
-- Evento que FactionMenu debe escuchar para actualizar la UI en tiempo real
Config.FactionMenuUpdateEvent = 'AX_FactionMenu:UpdateQuestList'

-- ─── PERMISOS ADMIN ─────────────────────────────────────────
Config.AdminAcePerm = 'command'  -- todos los que pueden usar comandos

-- ─── LÍMITES ────────────────────────────────────────────────
Config.MaxActiveQuestsPerFaction = 3   -- Máximo de misiones activas simultáneas por facción
Config.MaxRewardItems            = 5   -- Máximo de ítems de recompensa configurables


--[[ ─── EXPORTS ────────────────────────────────────────────────

-- Misiones disponibles
local quests = exports['AX_QuestCreator']:GetAvailableQuests(factionId)

-- Misiones activas (recuadro de misiones en curso)
local active = exports['AX_QuestCreator']:GetActiveQuestInstances(factionId)

-- Para aceptar una misión desde FactionMenu
TriggerServerEvent('AX_QuestCreator:AcceptQuest', questId)

]]