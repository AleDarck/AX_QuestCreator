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

--[[

-- Misiones disponibles para una facción
local quests = exports['AX_QuestCreator']:GetAvailableQuests(factionId)
-- Devuelve:
-- quest.id, quest.name, quest.description
-- quest.type                  → 'DELIVERY' | 'TERRITORY'
-- quest.difficulty             → 'easy' | 'medium' | 'hard' | 'extreme'
-- quest.faction_id             → nil = todas
-- quest.objective_data         → tabla decodificada
-- quest.rewards                → { money, xp, items }
-- quest.is_active_for_faction  → número, si > 0 ya está activa
-- quest.cooldown_minutes       → minutos configurados
-- quest.cooldown_remaining     → segundos restantes (0 si disponible)
-- quest.cooldown_remaining_text → "1H 23M" | "45M" | nil si disponible

-- Misiones activas en curso de una facción
local active = exports['AX_QuestCreator']:GetActiveQuestInstances(factionId)
-- Devuelve:
-- instance.id, instance.quest_id
-- instance.name, instance.description
-- instance.type, instance.difficulty
-- instance.faction_id, instance.accepted_by
-- instance.objective_data  → tabla decodificada
-- instance.rewards         → tabla decodificada
-- instance.started_at
-- instance.progress:
--   DELIVERY:  { delivered = { ['item_name'] = cantidad, ... } }
--   TERRITORY: { kills = 34, required = 50 }



-- Aceptar una misión
TriggerServerEvent('AX_QuestCreator:AcceptQuest', questId)

-- Abandonar una misión activa
TriggerServerEvent('AX_QuestCreator:AbandonQuest', instanceId)


-- Se dispara cada vez que hay cambio de progreso,
-- misión aceptada, completada o abandonada
RegisterNetEvent('AX_FactionMenu:UpdateQuestList', function()
    -- Recargar listas llamando a los exports
end)



-- 1. Al abrir pestaña de misiones
local disponibles = exports['AX_QuestCreator']:GetAvailableQuests(factionId)
local activas     = exports['AX_QuestCreator']:GetActiveQuestInstances(factionId)

-- 2. Para cada misión disponible verificar si tiene cooldown
for _, quest in ipairs(disponibles) do
    if quest.cooldown_remaining > 0 then
        -- Mostrar quest.cooldown_remaining_text → "1H 23M"
    elseif quest.is_active_for_faction > 0 then
        -- Ya está activa, mostrar botón de ver progreso
    else
        -- Mostrar botón de aceptar
    end
end

-- 3. Para misiones activas mostrar progreso
for _, instance in ipairs(activas) do
    if instance.type == 'DELIVERY' then
        -- instance.progress.delivered['scrap'] / instance.objective_data.items[x].amount
    elseif instance.type == 'TERRITORY' then
        -- instance.progress.kills / instance.progress.required
    end
end

-- 4. Al aceptar desde el menú (cliente)
TriggerServerEvent('AX_QuestCreator:AcceptQuest', questId)

-- 5. Escuchar cambios en tiempo real
RegisterNetEvent('AX_FactionMenu:UpdateQuestList', function()
    -- volver a llamar los exports y refrescar UI
end)


]]