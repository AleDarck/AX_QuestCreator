-- ============================================================
--  AX_QuestCreator | server.lua
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
    TriggerClientEvent('AX_QuestCreator:Notify', source, msg, ntype or 'inform')
end

local function NotifyFaction(factionId, msg, ntype)
    local players = ESX.GetPlayers()
    for _, playerId in ipairs(players) do
        local xPlayer = ESX.GetPlayerFromId(playerId)
        if xPlayer and xPlayer.getJob().name == factionId then
            Notify(playerId, msg, ntype or 'inform')
        end
    end
end

local function BroadcastFactionUpdate(factionId)
    local players = ESX.GetPlayers()
    for _, playerId in ipairs(players) do
        local xPlayer = ESX.GetPlayerFromId(playerId)
        if xPlayer and xPlayer.getJob().name == factionId then
            TriggerClientEvent(Config.FactionMenuUpdateEvent, playerId)
        end
    end
end

-- ─── EXPORTS para AX_FactionMenu ────────────────────────────

local function FormatCooldown(secondsRemaining)
    if secondsRemaining <= 0 then return nil end
    local h = math.floor(secondsRemaining / 3600)
    local m = math.floor((secondsRemaining % 3600) / 60)
    if h > 0 then
        return h .. 'H ' .. m .. 'M'
    else
        return m .. 'M'
    end
end

exports('GetAvailableQuests', function(factionId)
    local quests = MySQL.query.await(
        [[SELECT q.*,
            (SELECT COUNT(*) FROM ax_quest_instances qi
             WHERE qi.quest_id = q.id AND qi.faction_id = ? AND qi.status = 'active') AS is_active_for_faction
          FROM ax_quests q
          WHERE q.is_active = 1 AND (q.faction_id IS NULL OR q.faction_id = ?)
          ORDER BY q.difficulty, q.name]],
        { factionId, factionId }
    )

    for _, q in ipairs(quests) do
        if type(q.objective_data) == 'string' then q.objective_data = json.decode(q.objective_data) end
        if type(q.rewards)        == 'string' then q.rewards        = json.decode(q.rewards)        end

        q.cooldown_remaining      = 0
        q.cooldown_remaining_text = nil

        if q.cooldown_minutes and q.cooldown_minutes > 0 then
            local cooldown = MySQL.single.await(
                'SELECT UNIX_TIMESTAMP(last_completed) AS last_completed_unix FROM ax_quest_cooldowns WHERE faction_id = ? AND quest_id = ?',
                { factionId, q.id }
            )
            if cooldown and cooldown.last_completed_unix then
                local secondsSince    = os.time() - math.floor(cooldown.last_completed_unix)
                local cooldownSeconds = q.cooldown_minutes * 60
                if secondsSince < cooldownSeconds then
                    local remaining = cooldownSeconds - secondsSince
                    local mins      = math.floor(remaining / 60)
                    local hours     = math.floor(mins / 60)
                    local remMins   = mins % 60
                    q.cooldown_remaining = mins
                    if hours > 0 then
                        q.cooldown_remaining_text = hours .. 'H ' .. remMins .. 'M'
                    else
                        q.cooldown_remaining_text = mins .. 'M'
                    end
                end
            end
        end
    end

    return quests
end)

exports('GetActiveQuestInstances', function(factionId)
    local instances = MySQL.query.await(
        [[SELECT qi.*, q.name, q.description, q.type, q.difficulty, q.objective_data, q.rewards
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
    local source  = source
    local xPlayer = ESX.GetPlayerFromId(source)
    if not xPlayer then return end

    local factionId = xPlayer.getJob().name
    if factionId == 'unemployed' then
        Notify(source, 'Debes pertenecer a una facción para aceptar misiones.', 'error')
        return
    end

    local activeCount = MySQL.scalar.await(
        'SELECT COUNT(*) FROM ax_quest_instances WHERE faction_id = ? AND status = "active"',
        { factionId }
    )
    if activeCount >= 1 then
        Notify(source, 'Tu facción ya tiene una misión activa. Complétala primero.', 'error')
        return
    end

    local quest = MySQL.single.await('SELECT * FROM ax_quests WHERE id = ? AND is_active = 1', { questId })
    if not quest then
        Notify(source, 'Misión no encontrada o inactiva.', 'error')
        return
    end

    if quest.faction_id and quest.faction_id ~= factionId then
        Notify(source, 'Esta misión es exclusiva de otra facción.', 'error')
        return
    end

    -- Verificar cooldown
    if quest.cooldown_minutes and quest.cooldown_minutes > 0 then
        local cooldown = MySQL.single.await(
            'SELECT last_completed FROM ax_quest_cooldowns WHERE faction_id = ? AND quest_id = ?',
            { factionId, questId }
        )
        if cooldown and cooldown.last_completed ~= nil then
            local lastCompletedUnix = nil
            if type(cooldown.last_completed) == 'number' then
                lastCompletedUnix = math.floor(cooldown.last_completed / 1000)
            elseif type(cooldown.last_completed) == 'string' then
                local ts = MySQL.scalar.await("SELECT UNIX_TIMESTAMP(?)", { cooldown.last_completed })
                if ts then lastCompletedUnix = math.floor(ts) end
            end
            if lastCompletedUnix ~= nil then
                local secondsSince = os.time() - lastCompletedUnix
                local hoursSince   = secondsSince / 3600
                if hoursSince < quest.cooldown_minutes then
                    local remaining        = quest.cooldown_minutes - hoursSince
                    local remainingHours   = math.floor(remaining)
                    local remainingMinutes = math.floor((remaining - remainingHours) * 60)
                    local remainingText    = remainingHours > 0
                        and remainingHours .. 'h ' .. remainingMinutes .. 'min'
                        or remainingMinutes .. ' minutos'
                    Notify(source, 'Esta misión está en cooldown. Disponible en ' .. remainingText .. '.', 'error')
                    return
                end
            end
        end
    end

    local objectiveData = json.decode(quest.objective_data)
    local rewardData    = json.decode(quest.rewards)

    local initialProgress = {}
    if quest.type == 'DELIVERY' then
        initialProgress.delivered = {}
        for _, item in ipairs(objectiveData.items) do
            initialProgress.delivered[item.name] = 0
        end
    elseif quest.type == 'TERRITORY' then
        initialProgress.kills    = 0
        initialProgress.required = objectiveData.kills_required
    end

    local instanceId = MySQL.insert.await(
        [[INSERT INTO ax_quest_instances (quest_id, faction_id, accepted_by, status, progress)
          VALUES (?, ?, ?, 'active', ?)]],
        { questId, factionId, xPlayer.identifier, json.encode(initialProgress) }
    )

    Log('Misión ' .. quest.name .. ' aceptada por ' .. factionId .. ' (instance: ' .. instanceId .. ')')
    NotifyFaction(factionId, '¡Misión aceptada: ' .. quest.name .. '!', 'success')

    -- Enviar StartQuest a todos los miembros online de la facción
    local players = ESX.GetPlayers()
    for _, playerId in ipairs(players) do
        local xP = ESX.GetPlayerFromId(playerId)
        if xP and xP.getJob().name == factionId then
            TriggerClientEvent('AX_QuestCreator:StartQuest', playerId, {
                instanceId    = instanceId,
                questId       = questId,
                name          = quest.name,
                description   = quest.description,
                type          = quest.type,
                difficulty    = quest.difficulty,
                objectiveData = objectiveData,
                rewards       = rewardData,
                progress      = initialProgress,
                factionId     = factionId,
            })
        end
    end

    BroadcastFactionUpdate(factionId)
end)

-- ─── ENTREGA DE ITEMS (DELIVERY) ────────────────────────────

RegisterNetEvent('AX_QuestCreator:DeliverItems', function(instanceId)
    local source  = source
    local xPlayer = ESX.GetPlayerFromId(source)
    if not xPlayer then return end

    local instance = MySQL.single.await(
        [[SELECT qi.*, q.type, q.name, q.objective_data, q.rewards, q.difficulty
          FROM ax_quest_instances qi JOIN ax_quests q ON q.id = qi.quest_id
          WHERE qi.id = ? AND qi.status = 'active']],
        { instanceId }
    )
    if not instance then return end
    if xPlayer.getJob().name ~= instance.faction_id then return end
    if instance.type ~= 'DELIVERY' then return end

    local objectiveData = json.decode(instance.objective_data)
    local progress      = json.decode(instance.progress)
    local rewardData    = json.decode(instance.rewards)

    local anyDelivered = false

    for _, required in ipairs(objectiveData.items) do
        local alreadyDelivered = progress.delivered[required.name] or 0
        local stillNeeded      = required.amount - alreadyDelivered

        if stillNeeded > 0 then
            local playerHas = exports.ox_inventory:GetItemCount(source, required.name)
            if playerHas > 0 then
                local toDeliver = math.min(playerHas, stillNeeded)
                local removed   = exports.ox_inventory:RemoveItem(source, required.name, toDeliver)
                if removed then
                    progress.delivered[required.name] = alreadyDelivered + toDeliver
                    anyDelivered = true
                    Notify(source,
                        string.format('Entregado: %s x%d (%d/%d)',
                            required.label or required.name,
                            toDeliver,
                            progress.delivered[required.name],
                            required.amount
                        ), 'success'
                    )
                end
            end
        end
    end

    if not anyDelivered then
        Notify(source, 'No tienes ningún item requerido para esta misión.', 'error')
        return
    end

    MySQL.update.await(
        'UPDATE ax_quest_instances SET progress = ? WHERE id = ?',
        { json.encode(progress), instanceId }
    )

    -- Notificar progreso solo a miembros de la facción (NO usar -1)
    local players = ESX.GetPlayers()
    for _, playerId in ipairs(players) do
        local xP = ESX.GetPlayerFromId(playerId)
        if xP and xP.getJob().name == instance.faction_id then
            TriggerClientEvent('AX_QuestCreator:ProgressUpdated', playerId, instanceId, progress)
        end
    end

    BroadcastFactionUpdate(instance.faction_id)

    -- Verificar si completó
    local completed = true
    for _, required in ipairs(objectiveData.items) do
        if (progress.delivered[required.name] or 0) < required.amount then
            completed = false
            break
        end
    end

    if completed then
        CompleteQuest(instanceId, instance, rewardData, source)
    end
end)

-- ─── KILLS TERRITORY ────────────────────────────────────────

RegisterNetEvent('AX_QuestCreator:UpdateKills', function(instanceId, killsToAdd)
    local source  = source
    local xPlayer = ESX.GetPlayerFromId(source)
    if not xPlayer then return end

    if not killsToAdd or killsToAdd <= 0 then return end

    local instance = MySQL.single.await(
        [[SELECT qi.*, q.type, q.name, q.objective_data, q.rewards, q.difficulty
          FROM ax_quest_instances qi JOIN ax_quests q ON q.id = qi.quest_id
          WHERE qi.id = ? AND qi.status = 'active']],
        { instanceId }
    )
    if not instance then return end
    if xPlayer.getJob().name ~= instance.faction_id then return end
    if instance.type ~= 'TERRITORY' then return end

    local objectiveData = json.decode(instance.objective_data)
    local progress      = json.decode(instance.progress)
    local rewardData    = json.decode(instance.rewards)

    progress.kills    = math.min((progress.kills or 0) + killsToAdd, objectiveData.kills_required)
    progress.required = objectiveData.kills_required

    MySQL.update.await(
        'UPDATE ax_quest_instances SET progress = ? WHERE id = ?',
        { json.encode(progress), instanceId }
    )

    -- Notificar progreso solo a miembros de la facción (NO usar -1)
    local players = ESX.GetPlayers()
    for _, playerId in ipairs(players) do
        local xP = ESX.GetPlayerFromId(playerId)
        if xP and xP.getJob().name == instance.faction_id then
            TriggerClientEvent('AX_QuestCreator:ProgressUpdated', playerId, instanceId, progress)
        end
    end

    BroadcastFactionUpdate(instance.faction_id)

    if progress.kills >= objectiveData.kills_required then
        CompleteQuest(instanceId, instance, rewardData, source)
    end
end)

-- ─── COMPLETAR MISIÓN ────────────────────────────────────────

function CompleteQuest(instanceId, instance, rewardData, rewardSource)
    MySQL.update.await(
        'UPDATE ax_quest_instances SET status = "completed", completed_at = NOW() WHERE id = ?',
        { instanceId }
    )

    MySQL.update.await(
        [[INSERT INTO ax_quest_cooldowns (faction_id, quest_id, last_completed)
          VALUES (?, ?, NOW())
          ON DUPLICATE KEY UPDATE last_completed = NOW()]],
        { instance.faction_id, instance.quest_id }
    )

    -- Dinero al jugador que completó
    local xP = ESX.GetPlayerFromId(rewardSource)
    if xP then
        if rewardData.money and rewardData.money > 0 then
            xP.addMoney(rewardData.money)
        end
        if rewardData.items and #rewardData.items > 0 then
            for _, item in ipairs(rewardData.items) do
                if item.name and item.name ~= '' then
                    exports.ox_inventory:AddItem(rewardSource, item.name, item.amount or 1)
                end
            end
        end
    end

    -- XP a la facción
    local xp = rewardData.xp or 0
    if xp > 0 then
        exports['AX_FactionMenu']:addFactionXP(instance.faction_id, xp)
    end

    -- Notificar a todos de la facción pero solo el que completó recibe recompensa
    local rewardText = ''
    if rewardData.money and rewardData.money > 0 then
        rewardText = ' | +$' .. rewardData.money
    end
    if xp > 0 then
        rewardText = rewardText .. ' | +' .. xp .. ' XP'
    end

    local players = ESX.GetPlayers()
    for _, playerId in ipairs(players) do
        local xMember = ESX.GetPlayerFromId(playerId)
        if xMember and xMember.getJob().name == instance.faction_id then
            if playerId == rewardSource then
                -- Al que completó: notificación con recompensa y evento completo
                TriggerClientEvent('AX_QuestCreator:QuestCompleted', playerId, instanceId, instance.name, rewardData)
            else
                -- Al resto: solo notificación informativa sin recompensa
                TriggerClientEvent('AX_QuestCreator:Notify', playerId,
                    '✓ Misión completada: ' .. instance.name .. ' (facción +' .. xp .. ' XP)', 'success')
            end
        end
    end

    BroadcastFactionUpdate(instance.faction_id)
    Log('Misión ' .. instance.name .. ' completada por ' .. instance.faction_id)
end

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

    local players = ESX.GetPlayers()
    for _, playerId in ipairs(players) do
        local xP = ESX.GetPlayerFromId(playerId)
        if xP and xP.getJob().name == instance.faction_id then
            TriggerClientEvent('AX_QuestCreator:QuestAbandoned', playerId, instanceId)
        end
    end

    NotifyFaction(instance.faction_id, 'La misión ha sido abandonada.', 'error')
    BroadcastFactionUpdate(instance.faction_id)
end)

-- ─── CREATOR PANEL CRUD ─────────────────────────────────────

local function GetOxItems()
    -- ox_inventory expone todos los items registrados
    local items = exports.ox_inventory:Items()
    local result = {}
    for name, data in pairs(items) do
        table.insert(result, {
            name  = name,
            label = data.label or name,
        })
    end
    table.sort(result, function(a, b) return a.label < b.label end)
    return result
end

RegisterNetEvent('AX_QuestCreator:OpenCreator', function()
    local source = source
    if not IsAdmin(source) then Notify(source, 'Sin permisos.', 'error'); return end
    local quests = MySQL.query.await('SELECT * FROM ax_quests ORDER BY created_at DESC', {})
    for _, q in ipairs(quests) do
        if type(q.objective_data) == 'string' then q.objective_data = json.decode(q.objective_data) end
        if type(q.rewards) == 'string' then q.rewards = json.decode(q.rewards) end
    end
    local items = GetOxItems()
    TriggerClientEvent('AX_QuestCreator:OpenCreatorNUI', source, quests, items)
end)

RegisterNetEvent('AX_QuestCreator:CreateQuest', function(data)
    local source = source
    if not IsAdmin(source) then return end
    local xPlayer = ESX.GetPlayerFromId(source)
    if not xPlayer then return end
    if not data.name or data.name == '' then Notify(source, 'El nombre es requerido.', 'error'); return end

    local questId = MySQL.insert.await(
        [[INSERT INTO ax_quests (name, description, type, difficulty, faction_id, objective_data, rewards, cooldown_minutes, is_active, created_by)
          VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)]],
        {
            data.name, data.description or '', data.type, data.difficulty or 'easy',
            data.faction_id ~= '' and data.faction_id or nil,
            json.encode(data.objective_data),
            json.encode(data.rewards or { money = 0, items = {}, xp = 0 }),
            tonumber(data.cooldown_minutes) or 0,
            data.is_active and 1 or 0,
            xPlayer.identifier
        }
    )
    Notify(source, 'Misión "' .. data.name .. '" creada.', 'success')
    TriggerClientEvent('AX_QuestCreator:QuestCreated', source, questId)
end)

RegisterNetEvent('AX_QuestCreator:UpdateQuest', function(questId, data)
    local source = source
    if not IsAdmin(source) then return end
    MySQL.update.await(
        [[UPDATE ax_quests SET name=?, description=?, type=?, difficulty=?, faction_id=?,
          objective_data=?, rewards=?, cooldown_minutes=?, is_active=? WHERE id=?]],
        {
            data.name, data.description, data.type, data.difficulty,
            data.faction_id ~= '' and data.faction_id or nil,
            json.encode(data.objective_data),
            json.encode(data.rewards or { money = 0, items = {}, xp = 0 }),
            tonumber(data.cooldown_minutes) or 0,
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

RegisterNetEvent('AX_QuestCreator:GetFactions', function()
    local source = source
    if not IsAdmin(source) then return end
    local jobs = MySQL.query.await('SELECT name, label FROM jobs ORDER BY label', {})
    TriggerClientEvent('AX_QuestCreator:FactionsList', source, jobs)
end)

RegisterCommand(Config.AdminCommand, function(source, args, rawCommand)
    if source == 0 then return end
    if not IsAdmin(source) then Notify(source, 'Sin permisos.', 'error'); return end
    local quests = MySQL.query.await('SELECT * FROM ax_quests ORDER BY created_at DESC', {})
    for _, q in ipairs(quests) do
        if type(q.objective_data) == 'string' then q.objective_data = json.decode(q.objective_data) end
        if type(q.rewards) == 'string' then q.rewards = json.decode(q.rewards) end
    end
    local items = GetOxItems()
    TriggerClientEvent('AX_QuestCreator:OpenCreatorNUI', source, quests, items)
end, true)