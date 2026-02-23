-- ============================================================
--  AX_QuestCreator | server/server.lua
--  Lógica de servidor: CRUD, progreso, recompensas, exports
-- ============================================================

local ESX = exports['es_extended']:getSharedObject()

-- ─── UTILIDADES ─────────────────────────────────────────────

local function Log(msg)
    if Config.DebugMode then
        print('^3[AX_QuestCreator]^7 ' .. tostring(msg))
    end
end

local function IsAdmin(source)
    return IsPlayerAceAllowed(source, Config.AdminAcePerm)
end

local function Notify(source, msg, ntype)
    ntype = ntype or 'inform'
    TriggerClientEvent('AX_QuestCreator:Notify', source, msg, ntype)
end

-- Notifica a todos los miembros online de una facción
local function NotifyFaction(factionId, msg, ntype)
    local players = ESX.GetPlayers()
    for _, playerId in ipairs(players) do
        local xPlayer = ESX.GetPlayerFromId(playerId)
        if xPlayer and xPlayer.getJob().name == factionId then
            Notify(playerId, msg, ntype or 'inform')
        end
    end
end

-- Dispara actualización en tiempo real al FactionMenu
local function BroadcastFactionUpdate(factionId)
    local players = ESX.GetPlayers()
    for _, playerId in ipairs(players) do
        local xPlayer = ESX.GetPlayerFromId(playerId)
        if xPlayer and xPlayer.getJob().name == factionId then
            TriggerClientEvent(Config.FactionMenuUpdateEvent, playerId)
        end
    end
end

-- ─── EXPORTS: FactionMenu los consume ───────────────────────

-- Retorna misiones disponibles para una facción (sin cooldown activo, activas)
exports('GetAvailableQuests', function(factionId)
    local quests = MySQL.query.await(
        [[SELECT q.*, 
            CASE WHEN cd.last_completed IS NOT NULL 
                 AND TIMESTAMPDIFF(MINUTE, cd.last_completed, NOW()) < q.cooldown_minutes
                 THEN CEIL(q.cooldown_minutes - TIMESTAMPDIFF(MINUTE, cd.last_completed, NOW()))
                 ELSE 0 END AS cooldown_remaining,
            (SELECT COUNT(*) FROM ax_quest_instances qi 
             WHERE qi.quest_id = q.id AND qi.faction_id = ? AND qi.status = 'active') AS is_active_for_faction
          FROM ax_quests q
          LEFT JOIN ax_quest_cooldowns cd ON cd.quest_id = q.id AND cd.faction_id = ?
          WHERE q.is_active = 1 AND (q.faction_id IS NULL OR q.faction_id = ?)
          ORDER BY q.difficulty, q.name]],
        { factionId, factionId, factionId }
    )

    -- Deserializar JSON
    for _, q in ipairs(quests) do
        if type(q.objective_data) == 'string' then
            q.objective_data = json.decode(q.objective_data)
        end
        if type(q.rewards) == 'string' then
            q.rewards = json.decode(q.rewards)
        end
    end

    return quests
end)

-- Retorna misiones activas (instancias) de una facción
exports('GetActiveQuestInstances', function(factionId)
    local instances = MySQL.query.await(
        [[SELECT qi.*, q.name, q.description, q.type, q.difficulty, q.objective_data, q.rewards, q.time_limit
          FROM ax_quest_instances qi
          JOIN ax_quests q ON q.id = qi.quest_id
          WHERE qi.faction_id = ? AND qi.status = 'active'
          ORDER BY qi.started_at DESC]],
        { factionId }
    )

    for _, i in ipairs(instances) do
        if type(i.objective_data) == 'string' then i.objective_data = json.decode(i.objective_data) end
        if type(i.rewards) == 'string' then i.rewards = json.decode(i.rewards) end
        if type(i.progress) == 'string' then i.progress = json.decode(i.progress) end
    end

    return instances
end)

-- ─── ACEPTAR MISIÓN ─────────────────────────────────────────

RegisterNetEvent('AX_QuestCreator:AcceptQuest', function(questId)
    local source   = source
    local xPlayer  = ESX.GetPlayerFromId(source)
    if not xPlayer then return end

    local factionId = xPlayer.getJob().name
    if factionId == 'unemployed' then
        Notify(source, 'Debes pertenecer a una facción para aceptar misiones.', 'error')
        return
    end

    -- Verificar límite de misiones activas
    local activeCount = MySQL.scalar.await(
        'SELECT COUNT(*) FROM ax_quest_instances WHERE faction_id = ? AND status = "active"',
        { factionId }
    )
    if activeCount >= Config.MaxActiveQuestsPerFaction then
        Notify(source, 'Tu facción ya tiene el máximo de misiones activas (' .. Config.MaxActiveQuestsPerFaction .. ').', 'error')
        return
    end

    -- Obtener datos de la misión
    local quest = MySQL.single.await('SELECT * FROM ax_quests WHERE id = ? AND is_active = 1', { questId })
    if not quest then
        Notify(source, 'Misión no encontrada o inactiva.', 'error')
        return
    end

    -- Verificar facción requerida
    if quest.faction_id and quest.faction_id ~= factionId then
        Notify(source, 'Esta misión es exclusiva de otra facción.', 'error')
        return
    end

    -- Verificar cooldown
    local cooldown = MySQL.single.await(
        'SELECT last_completed FROM ax_quest_cooldowns WHERE faction_id = ? AND quest_id = ?',
        { factionId, questId }
    )
    if cooldown then
        local minutesSince = MySQL.scalar.await(
            'SELECT TIMESTAMPDIFF(MINUTE, ?, NOW())', { cooldown.last_completed }
        )
        if minutesSince < quest.cooldown_minutes then
            local remaining = quest.cooldown_minutes - minutesSince
            Notify(source, 'Esta misión está en cooldown. Disponible en ' .. remaining .. ' minutos.', 'error')
            return
        end
    end

    -- Verificar si ya está activa para esta facción
    local alreadyActive = MySQL.scalar.await(
        'SELECT COUNT(*) FROM ax_quest_instances WHERE quest_id = ? AND faction_id = ? AND status = "active"',
        { questId, factionId }
    )
    if alreadyActive > 0 then
        Notify(source, 'Tu facción ya tiene esta misión activa.', 'error')
        return
    end

    -- Calcular expiración
    local objectiveData = json.decode(quest.objective_data)
    local rewardData    = json.decode(quest.rewards)

    local expiresAt = nil
    if quest.time_limit then
        expiresAt = os.date('%Y-%m-%d %H:%M:%S', os.time() + quest.time_limit)
    end

    print('[DEBUG] time_limit: ' .. tostring(quest.time_limit))
    print('[DEBUG] expiresAt calculado: ' .. tostring(expiresAt))
    print('[DEBUG] os.time(): ' .. tostring(os.time()))

    -- Progreso inicial según tipo
    local initialProgress = {}
    if quest.type == 'ELIMINATE' then
        initialProgress = { kills = 0, required = objectiveData.amount }
    elseif quest.type == 'COLLECT' then
        initialProgress = { collected = 0, required = objectiveData.amount }
    elseif quest.type == 'DEFEND' then
        initialProgress = { elapsed_seconds = 0, required = objectiveData.duration_seconds }
    elseif quest.type == 'REPAIR' then
        local total = #objectiveData.points
        initialProgress = { repaired = 0, required = total, points = {} }
        for i = 1, total do
            initialProgress.points[i] = false
        end
    end

    -- Insertar instancia
    local instanceId = MySQL.insert.await(
        [[INSERT INTO ax_quest_instances (quest_id, faction_id, accepted_by, status, progress, expires_at)
          VALUES (?, ?, ?, 'active', ?, ?)]],
        { questId, factionId, xPlayer.identifier, json.encode(initialProgress), expiresAt }
    )

    Log('Misión ' .. quest.name .. ' aceptada por facción ' .. factionId .. ' (instance: ' .. instanceId .. ')')

    -- Notificar a toda la facción
    NotifyFaction(factionId, '¡Misión aceptada: ' .. quest.name .. '!', 'success')

    -- Enviar datos al cliente que aceptó para iniciar lógica de zona
    TriggerClientEvent('AX_QuestCreator:StartQuest', source, {
        instanceId    = instanceId,
        questId       = questId,
        name          = quest.name,
        description   = quest.description,
        type          = quest.type,
        difficulty    = quest.difficulty,
        objectiveData = objectiveData,
        rewards       = rewardData,
        progress      = initialProgress,
        expiresAt     = expiresAt,
        factionId     = factionId
    })

    -- Actualizar UI del FactionMenu para toda la facción
    BroadcastFactionUpdate(factionId)
end)

-- ─── ACTUALIZAR PROGRESO ─────────────────────────────────────

RegisterNetEvent('AX_QuestCreator:UpdateProgress', function(instanceId, progressData)
    print('[DEBUG] UpdateProgress llamado - instanceId: ' .. tostring(instanceId))
    print('[DEBUG] progressData: ' .. json.encode(progressData))
    local source  = source
    local xPlayer = ESX.GetPlayerFromId(source)
    if not xPlayer then return end

    -- Verificar que la instancia existe y está activa
    local instance = MySQL.single.await(
        [[SELECT qi.*, q.type, q.name, q.objective_data, q.rewards, q.difficulty, q.faction_id as quest_faction
          FROM ax_quest_instances qi JOIN ax_quests q ON q.id = qi.quest_id
          WHERE qi.id = ? AND qi.status = 'active']],
        { instanceId }
    )
        print('[DEBUG] instance type: ' .. tostring(instance and instance.type or 'NIL'))
    print('[DEBUG] instance status: ' .. tostring(instance and instance.status or 'NIL'))
    print('[DEBUG] instance faction: ' .. tostring(instance and instance.faction_id or 'NIL'))
    print('[DEBUG] player job: ' .. tostring(xPlayer and xPlayer.getJob().name or 'NIL'))

    if not instance then return end

    -- Verificar que el jugador pertenece a la facción de la instancia
    if xPlayer.getJob().name ~= instance.faction_id then return end

    -- Verificar expiración
    if instance.expires_at then
        local expired = MySQL.scalar.await(
            'SELECT NOW() > ?', { instance.expires_at }
        )
        if expired == 1 then
            MySQL.update.await(
                'UPDATE ax_quest_instances SET status = "expired" WHERE id = ?',
                { instanceId }
            )
            NotifyFaction(instance.faction_id, 'La misión "' .. instance.name .. '" ha expirado.', 'error')
            TriggerClientEvent('AX_QuestCreator:QuestFailed', source, instanceId, 'Tiempo agotado')
            BroadcastFactionUpdate(instance.faction_id)
            return
        end
    end

    local objectiveData = json.decode(instance.objective_data)
    local rewardData    = json.decode(instance.rewards)
    local completed     = false

    -- Validar progreso según tipo
    if instance.type == 'ELIMINATE' then
        progressData.required = objectiveData.amount
        progressData.kills    = math.min(progressData.kills or 0, objectiveData.amount)
        completed = progressData.kills >= objectiveData.amount

    elseif instance.type == 'COLLECT' then
        progressData.required  = objectiveData.amount
        progressData.collected = math.min(progressData.collected or 0, objectiveData.amount)
        completed = progressData.collected >= objectiveData.amount

    elseif instance.type == 'DEFEND' then
        progressData.required        = objectiveData.duration_seconds
        progressData.elapsed_seconds = math.min(progressData.elapsed_seconds or 0, objectiveData.duration_seconds)
        completed = progressData.elapsed_seconds >= objectiveData.duration_seconds

elseif instance.type == 'REPAIR' then
    progressData.required = #objectiveData.points
    local repaired = 0
    for _, v in ipairs(progressData.points or {}) do
        if v then repaired = repaired + 1 end
    end
    progressData.repaired = repaired
    completed = repaired >= #objectiveData.points
    print('[DEBUG] REPAIR - repaired: ' .. repaired .. ' required: ' .. #objectiveData.points .. ' completed: ' .. tostring(completed))
end

    -- Guardar progreso
    MySQL.update.await(
        'UPDATE ax_quest_instances SET progress = ? WHERE id = ?',
        { json.encode(progressData), instanceId }
    )

    -- Notificar progreso en tiempo real al cliente
    TriggerClientEvent('AX_QuestCreator:ProgressUpdated', source, instanceId, progressData)
    BroadcastFactionUpdate(instance.faction_id)

    -- ─── COMPLETAR MISIÓN ───────────────────────────────────
if completed then
    print('[DEBUG] Entrando al bloque completed')
        MySQL.update.await(
            'UPDATE ax_quest_instances SET status = "completed", completed_at = NOW() WHERE id = ?',
            { instanceId }
        )

        -- Registrar cooldown
        MySQL.update.await(
            [[INSERT INTO ax_quest_cooldowns (faction_id, quest_id, last_completed) 
              VALUES (?, ?, NOW()) 
              ON DUPLICATE KEY UPDATE last_completed = NOW()]],
            { instance.faction_id, instance.quest_id }
        )

        -- Entregar recompensas a todos los miembros online de la facción
        local multiplier = Config.DifficultyMultiplier[instance.difficulty] or 1.0
        local players    = ESX.GetPlayers()

        for _, playerId in ipairs(players) do
            local xP = ESX.GetPlayerFromId(playerId)
            if xP and xP.getJob().name == instance.faction_id then

                -- Dinero
                if rewardData.money and rewardData.money > 0 then
                    local finalMoney = math.floor(rewardData.money * multiplier)
                    xP.addMoney(finalMoney)
                end

                -- Ítems via ox_inventory
                if rewardData.items then
                    for _, item in ipairs(rewardData.items) do
                        local finalAmount = math.max(1, math.floor((item.amount or 1) * multiplier))
                        exports.ox_inventory:AddItem(playerId, item.name, finalAmount)
                    end
                end

                TriggerClientEvent('AX_QuestCreator:QuestCompleted', playerId, instanceId, instance.name, rewardData, multiplier)
            end
        end

        Log('Misión ' .. instance.name .. ' completada por facción ' .. instance.faction_id)
        BroadcastFactionUpdate(instance.faction_id)
    end
end)

-- ─── ABANDONAR MISIÓN ────────────────────────────────────────

RegisterNetEvent('AX_QuestCreator:AbandonQuest', function(instanceId)
    local source  = source
    local xPlayer = ESX.GetPlayerFromId(source)
    if not xPlayer then return end

    local instance = MySQL.single.await(
        'SELECT * FROM ax_quest_instances WHERE id = ? AND status = "active"',
        { instanceId }
    )
    if not instance then return end
    if xPlayer.getJob().name ~= instance.faction_id then return end

    MySQL.update.await(
        'UPDATE ax_quest_instances SET status = "failed" WHERE id = ?',
        { instanceId }
    )

    NotifyFaction(instance.faction_id, 'La misión ha sido abandonada.', 'error')
    TriggerClientEvent('AX_QuestCreator:QuestAbandoned', source, instanceId)
    BroadcastFactionUpdate(instance.faction_id)
end)

-- ─── CREATOR PANEL: CRUD (Solo Admins) ──────────────────────

RegisterNetEvent('AX_QuestCreator:OpenCreator', function()
    local source = source
    if not IsAdmin(source) then
        Notify(source, 'No tienes permisos para acceder al Creator.', 'error')
        return
    end
    local quests = MySQL.query.await('SELECT * FROM ax_quests ORDER BY created_at DESC', {})
    for _, q in ipairs(quests) do
        if type(q.objective_data) == 'string' then q.objective_data = json.decode(q.objective_data) end
        if type(q.rewards) == 'string' then q.rewards = json.decode(q.rewards) end
    end
    TriggerClientEvent('AX_QuestCreator:OpenCreatorNUI', source, quests)
end)

RegisterNetEvent('AX_QuestCreator:CreateQuest', function(data)
    local source = source
    if not IsAdmin(source) then return end

    local xPlayer = ESX.GetPlayerFromId(source)
    if not xPlayer then return end

    -- Validaciones básicas
    if not data.name or data.name == '' then
        Notify(source, 'El nombre de la misión es requerido.', 'error')
        return
    end
    if not data.type or not data.objective_data then
        Notify(source, 'Tipo y datos del objetivo son requeridos.', 'error')
        return
    end

    local questId = MySQL.insert.await(
        [[INSERT INTO ax_quests 
          (name, description, type, difficulty, faction_id, min_players, max_players, 
           objective_data, rewards, time_limit, cooldown_minutes, is_active, created_by)
          VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)]],
        {
            data.name,
            data.description or '',
            data.type,
            data.difficulty or 'easy',
            data.faction_id ~= '' and data.faction_id or nil,
            tonumber(data.min_players) or 1,
            tonumber(data.max_players) or 10,
            json.encode(data.objective_data),
            json.encode(data.rewards or { money = 0, items = {} }),
            data.time_limit ~= '' and tonumber(data.time_limit) or nil,
            tonumber(data.cooldown_minutes) or 60,
            data.is_active and 1 or 0,
            xPlayer.identifier
        }
    )

    Log('Misión creada: ' .. data.name .. ' (id: ' .. questId .. ') por ' .. xPlayer.identifier)
    Notify(source, 'Misión "' .. data.name .. '" creada exitosamente.', 'success')
    TriggerClientEvent('AX_QuestCreator:QuestCreated', source, questId)
end)

RegisterNetEvent('AX_QuestCreator:UpdateQuest', function(questId, data)
    local source = source
    if not IsAdmin(source) then return end

    MySQL.update.await(
        [[UPDATE ax_quests SET 
          name = ?, description = ?, type = ?, difficulty = ?, faction_id = ?,
          min_players = ?, max_players = ?, objective_data = ?, rewards = ?,
          time_limit = ?, cooldown_minutes = ?, is_active = ?
          WHERE id = ?]],
        {
            data.name, data.description, data.type, data.difficulty,
            data.faction_id ~= '' and data.faction_id or nil,
            tonumber(data.min_players) or 1,
            tonumber(data.max_players) or 10,
            json.encode(data.objective_data),
            json.encode(data.rewards or { money = 0, items = {} }),
            data.time_limit ~= '' and tonumber(data.time_limit) or nil,
            tonumber(data.cooldown_minutes) or 60,
            data.is_active and 1 or 0,
            questId
        }
    )

    Notify(source, 'Misión actualizada.', 'success')
    TriggerClientEvent('AX_QuestCreator:QuestUpdated', source, questId)
end)

RegisterNetEvent('AX_QuestCreator:DeleteQuest', function(questId)
    local source = source
    if not IsAdmin(source) then return end

    MySQL.update.await('DELETE FROM ax_quests WHERE id = ?', { questId })
    Notify(source, 'Misión eliminada.', 'success')
    TriggerClientEvent('AX_QuestCreator:QuestDeleted', source, questId)
end)

RegisterNetEvent('AX_QuestCreator:ToggleQuest', function(questId, state)
    local source = source
    if not IsAdmin(source) then return end

    MySQL.update.await('UPDATE ax_quests SET is_active = ? WHERE id = ?', { state and 1 or 0, questId })
    Notify(source, 'Estado de misión actualizado.', 'success')
end)

-- Obtener lista de facciones para el creator (desplegable)
RegisterNetEvent('AX_QuestCreator:GetFactions', function()
    local source = source
    if not IsAdmin(source) then return end

    -- ESX jobs como facciones
    local jobs = MySQL.query.await('SELECT name, label FROM jobs ORDER BY label', {})
    TriggerClientEvent('AX_QuestCreator:FactionsList', source, jobs)
end)

-- ─── COMANDO ADMIN ──────────────────────────────────────────

RegisterCommand(Config.AdminCommand, function(source, args, rawCommand)
    if source == 0 then return end
    if not IsAdmin(source) then
        Notify(source, 'Sin permisos.', 'error')
        return
    end
    local quests = MySQL.query.await('SELECT * FROM ax_quests ORDER BY created_at DESC', {})
    for _, q in ipairs(quests) do
        if type(q.objective_data) == 'string' then q.objective_data = json.decode(q.objective_data) end
        if type(q.rewards) == 'string' then q.rewards = json.decode(q.rewards) end
    end
    TriggerClientEvent('AX_QuestCreator:OpenCreatorNUI', source, quests)
end, true)

-- ─── EXPIRACIÓN AUTOMÁTICA (tick cada 60s) ──────────────────

CreateThread(function()
    while true do
        Wait(60000)
        local expired = MySQL.query.await(
            [[SELECT qi.id, qi.faction_id, q.name 
              FROM ax_quest_instances qi JOIN ax_quests q ON q.id = qi.quest_id
              WHERE qi.status = 'active' AND qi.expires_at IS NOT NULL AND NOW() > qi.expires_at]],
            {}
        )
        print('[DEBUG] instancias expiradas encontradas: ' .. #expired)
        for _, inst in ipairs(expired) do
            print('[DEBUG] expirada id=' .. inst.id .. ' faction=' .. inst.faction_id)
            MySQL.update.await(
                'UPDATE ax_quest_instances SET status = "expired" WHERE id = ?',
                { inst.id }
            )
            NotifyFaction(inst.faction_id, 'La misión "' .. inst.name .. '" expiró por tiempo.', 'error')
            BroadcastFactionUpdate(inst.faction_id)
            Log('Instancia ' .. inst.id .. ' marcada como expirada.')
        end
    end
end)