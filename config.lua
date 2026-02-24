-- ============================================================
--  AX_QuestCreator | config.lua
-- ============================================================

Config = {}

-- ─── GENERAL ────────────────────────────────────────────────
Config.DebugMode    = false
Config.AdminCommand = 'questcreator'

-- ─── NOTIFICACIONES ─────────────────────────────────────────
Config.NotifyType = 'esx'   -- 'esx' | 'ox_lib'

-- ─── NPC RECEPTOR DE ENTREGAS ───────────────────────────────
-- Este NPC es a quien se le entregan los items de misiones DELIVERY
Config.DeliveryNPC = {
    model  = 's_m_m_marine_01',          -- Modelo del ped
    coords = { x = -538.5024, y = 5365.7383, z = 70.5403, heading = 22.5142 },
    label  = 'Sargento Reyes',           -- Nombre que aparece en la interacción
}

-- ─── DISTANCIA DE INTERACCIÓN CON NPC ───────────────────────
Config.InteractDistance = 3.0

-- ─── BLIPS ──────────────────────────────────────────────────
Config.Blips = {
    DELIVERY  = { sprite = 478, color = 5,  scale = 0.8 },
    TERRITORY = { sprite = 309, color = 1,  scale = 0.8 },
}

-- ─── COLORES DE ZONA ────────────────────────────────────────
Config.ZoneColor = { r = 255, g = 50,  b = 50  }   -- TERRITORY
Config.DeliveryNPCColor = { r = 50, g = 150, b = 255 }

-- ─── MULTIPLICADOR POR DIFICULTAD ───────────────────────────
Config.DifficultyMultiplier = {
    easy    = 1.0,
    medium  = 1.5,
    hard    = 2.0,
    extreme = 3.0,
}

-- ─── XP POR DIFICULTAD (base, se multiplica) ────────────────
Config.DifficultyXP = {
    easy    = 100,
    medium  = 250,
    hard    = 500,
    extreme = 1000,
}

-- ─── PERMISOS ────────────────────────────────────────────────
Config.AdminAcePerm = 'command'

-- ─── INTEGRACIÓN AX_FactionMenu ─────────────────────────────
Config.FactionMenuUpdateEvent = 'AX_FactionMenu:UpdateQuestList'

