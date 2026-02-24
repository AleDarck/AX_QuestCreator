-- ============================================================
--  AX_QuestCreator | client.lua
-- ============================================================

local ESX = exports['es_extended']:getSharedObject()

-- ─── ESTADO ─────────────────────────────────────────────────

local activeQuests = {}
local questBlips   = {}
local questThreads = {}
local deliveryNPC  = nil
local nuiOpen      = false

-- ─── UTILIDADES ─────────────────────────────────────────────

local function Notify(msg, ntype)
    if Config.NotifyType == 'ox_lib' then
        lib.notify({ title = 'Misión', description = msg, type = ntype or 'inform' })
    else
        ESX.ShowNotification(msg)
    end
end

local function CreateQuestBlip(instanceId, x, y, z, questType, label)
    if questBlips[instanceId] then RemoveBlip(questBlips[instanceId]) end
    local blip = AddBlipForCoord(x, y, z)
    local cfg  = Config.Blips[questType]
    SetBlipSprite(blip, cfg.sprite)
    SetBlipColour(blip, cfg.color)
    SetBlipScale(blip, cfg.scale)
    SetBlipAsShortRange(blip, false)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentString(label)
    EndTextCommandSetBlipName(blip)
    questBlips[instanceId] = blip
end

local function RemoveQuestBlip(instanceId)
    if questBlips[instanceId] then
        RemoveBlip(questBlips[instanceId])
        questBlips[instanceId] = nil
    end
end

local function DrawZoneCircle(zone, color)
    local pts = 36
    for i = 0, pts - 1 do
        local a1 = math.rad(i * (360 / pts))
        local a2 = math.rad((i + 1) * (360 / pts))
        DrawLine(
            zone.x + math.cos(a1) * zone.radius, zone.y + math.sin(a1) * zone.radius, zone.z,
            zone.x + math.cos(a2) * zone.radius, zone.y + math.sin(a2) * zone.radius, zone.z,
            color.r, color.g, color.b, 200
        )
    end
end

local function IsInZone(zone)
    local coords = GetEntityCoords(PlayerPedId())
    return #(coords - vector3(zone.x, zone.y, zone.z)) <= zone.radius
end

-- ─── SPAWN NPC ───────────────────────────────────────────────

local function SpawnDeliveryNPC()
    if deliveryNPC and DoesEntityExist(deliveryNPC) then return end
    local cfg = Config.DeliveryNPC
    RequestModel(cfg.model)
    local timeout = 0
    while not HasModelLoaded(cfg.model) and timeout < 100 do
        Wait(100); timeout = timeout + 1
    end
    deliveryNPC = CreatePed(4, cfg.model, cfg.coords.x, cfg.coords.y, cfg.coords.z - 1.0, cfg.coords.heading, false, true)
    SetEntityInvincible(deliveryNPC, true)
    SetBlockingOfNonTemporaryEvents(deliveryNPC, true)
    FreezeEntityPosition(deliveryNPC, true)
    SetPedCanRagdoll(deliveryNPC, false)
    TaskStartScenarioInPlace(deliveryNPC, 'WORLD_HUMAN_STAND_IMPATIENT', 0, true)
    SetModelAsNoLongerNeeded(cfg.model)
end

-- ─── LÓGICA DELIVERY ─────────────────────────────────────────

local function StartDeliveryThread(instanceId, quest)
    if questThreads[instanceId] then return end
    questThreads[instanceId] = true

    local cfg = Config.DeliveryNPC
    CreateQuestBlip(instanceId, cfg.coords.x, cfg.coords.y, cfg.coords.z, 'DELIVERY', quest.name)

    CreateThread(function()
        while activeQuests[instanceId] do
            Wait(0)

            if not DoesEntityExist(deliveryNPC) then SpawnDeliveryNPC() end

            local playerCoords = GetEntityCoords(PlayerPedId())
            local npcCoords    = GetEntityCoords(deliveryNPC)
            local dist         = #(playerCoords - npcCoords)

            if dist <= Config.InteractDistance then
                ESX.ShowHelpNotification('[E] Hablar con ' .. Config.DeliveryNPC.label)

                if IsControlJustReleased(0, 38) then
                    -- Abrir modal NUI con progreso actual
                    local progress = activeQuests[instanceId] and activeQuests[instanceId].progress
                    local obj      = activeQuests[instanceId].objectiveData

                    SetNuiFocus(true, true)
                    nuiOpen = true
                    SendNUIMessage({
                        action       = 'openDelivery',
                        instanceId   = instanceId,
                        questName    = quest.name,
                        items        = obj.items,
                        delivered    = progress and progress.delivered or {},
                        npcLabel     = Config.DeliveryNPC.label,
                    })
                end
            end
        end

        questThreads[instanceId] = nil
    end)
end

-- ─── LÓGICA TERRITORY ────────────────────────────────────────

local function StartTerritoryThread(instanceId, quest)
    if questThreads[instanceId] then return end
    questThreads[instanceId] = true

    local zone = quest.objectiveData.zone
    CreateQuestBlip(instanceId, zone.x, zone.y, zone.z, 'TERRITORY', quest.name)

    -- Thread visual
    CreateThread(function()
        while activeQuests[instanceId] do
            Wait(0)
            DrawZoneCircle(zone, Config.ZoneColor)
            DrawMarker(1, zone.x, zone.y, zone.z - 1.0,
                0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
                zone.radius * 2, zone.radius * 2, 1.5,
                Config.ZoneColor.r, Config.ZoneColor.g, Config.ZoneColor.b, 25,
                false, true, 2, false, nil, nil, false
            )
            if not IsInZone(zone) then Wait(300) end
        end
    end)

    -- Thread de detección de kills
    CreateThread(function()
        -- Tabla local de entidades ya contadas en esta sesión
        local counted = {}

        while activeQuests[instanceId] do
            Wait(300)

            local playerPed = PlayerPedId()

            -- Solo detectar si el jugador está en la zona
            if not IsInZone(zone) then goto continue end

            local allPeds = GetGamePool('CPed')
            for _, entity in ipairs(allPeds) do
                -- Ignorar: el propio jugador, otros jugadores, ya contados, vivos
                if entity == playerPed then goto nextped end
                if IsPedAPlayer(entity) then goto nextped end
                if counted[entity] then goto nextped end
                if not IsEntityDead(entity) then goto nextped end

                -- Verificar que está dentro de la zona
                local eCoords = GetEntityCoords(entity)
                if #(eCoords - vector3(zone.x, zone.y, zone.z)) > zone.radius then goto nextped end

                -- Verificar que fue herido por alguien (para no contar muertes ajenas)
                -- GetPedSourceOfDeath devuelve la entidad que lo mató
                local killer = GetPedSourceOfDeath(entity)
                local killerIsPlayer = false

                -- Comprobar si el killer es algún jugador (de cualquier facción)
                -- Esto evita contar zombies que murieron solos o por otras causas
                local activePlayers = GetActivePlayers()
                for _, pid in ipairs(activePlayers) do
                    if GetPlayerPed(pid) == killer then
                        killerIsPlayer = true
                        break
                    end
                end

                if killerIsPlayer then
                    counted[entity] = true
                    TriggerServerEvent('AX_QuestCreator:UpdateKills', instanceId, 1)
                end

                ::nextped::
            end

            ::continue::
        end

        questThreads[instanceId] = nil
    end)
end

-- ─── INICIAR MISIÓN ──────────────────────────────────────────

RegisterNetEvent('AX_QuestCreator:StartQuest', function(questData)
    local instanceId = questData.instanceId
    activeQuests[instanceId] = questData

    if questData.type == 'DELIVERY' then
        SpawnDeliveryNPC()
        StartDeliveryThread(instanceId, questData)
    elseif questData.type == 'TERRITORY' then
        StartTerritoryThread(instanceId, questData)
    end

    Notify('Misión iniciada: ' .. questData.name, 'success')
end)

-- ─── PROGRESO ────────────────────────────────────────────────

RegisterNetEvent('AX_QuestCreator:ProgressUpdated', function(instanceId, progress)
    if activeQuests[instanceId] then
        activeQuests[instanceId].progress = progress
        -- Si el modal de delivery está abierto, actualizar progreso en tiempo real
        if activeQuests[instanceId].type == 'DELIVERY' then
            SendNUIMessage({
                action    = 'updateDeliveryProgress',
                items     = activeQuests[instanceId].objectiveData.items,
                delivered = progress.delivered,
            })
        end
    end
end)

-- ─── FIN DE MISIÓN ───────────────────────────────────────────

RegisterNetEvent('AX_QuestCreator:QuestCompleted', function(instanceId, questName, rewards)
    activeQuests[instanceId] = nil
    questThreads[instanceId] = nil
    RemoveQuestBlip(instanceId)

    local rewardText = ''
    if rewards.money and rewards.money > 0 then
        rewardText = ' | +$' .. rewards.money
    end
    if rewards.xp and rewards.xp > 0 then
        rewardText = rewardText .. ' | +' .. rewards.xp .. ' XP'
    end

    Notify('✓ Misión completada: ' .. questName .. rewardText, 'success')
end)

RegisterNetEvent('AX_QuestCreator:QuestAbandoned', function(instanceId)
    activeQuests[instanceId] = nil
    questThreads[instanceId] = nil
    RemoveQuestBlip(instanceId)
    Notify('Misión abandonada.', 'error')
end)

RegisterNetEvent('AX_QuestCreator:QuestFailed', function(instanceId, reason)
    activeQuests[instanceId] = nil
    questThreads[instanceId] = nil
    RemoveQuestBlip(instanceId)
    Notify('✗ Misión fallida: ' .. (reason or ''), 'error')
end)

-- ─── SPAWN NPC AL CARGAR ─────────────────────────────────────

CreateThread(function()
    while not ESX.IsPlayerLoaded() do Wait(1000) end
    Wait(2000)
    SpawnDeliveryNPC()
end)

-- ─── NUI CREATOR ─────────────────────────────────────────────

RegisterNetEvent('AX_QuestCreator:OpenCreatorNUI', function(quests, items)
    SetNuiFocus(true, true)
    nuiOpen = true
    SendNUIMessage({ action = 'openCreator', quests = quests, items = items or {} })
end)

RegisterNetEvent('AX_QuestCreator:FactionsList', function(factions)
    SendNUIMessage({ action = 'factionsList', factions = factions })
end)

RegisterNetEvent('AX_QuestCreator:QuestCreated', function(questId)
    SendNUIMessage({ action = 'questCreated', id = questId })
    TriggerServerEvent('AX_QuestCreator:OpenCreator')
end)

RegisterNetEvent('AX_QuestCreator:QuestUpdated', function(questId)
    SendNUIMessage({ action = 'questUpdated', id = questId })
    TriggerServerEvent('AX_QuestCreator:OpenCreator')
end)

RegisterNetEvent('AX_QuestCreator:QuestDeleted', function(questId)
    SendNUIMessage({ action = 'questDeleted', id = questId })
    TriggerServerEvent('AX_QuestCreator:OpenCreator')
end)

RegisterNUICallback('closeCreator', function(data, cb) SetNuiFocus(false, false); nuiOpen = false; cb('ok') end)
RegisterNUICallback('createQuest',  function(data, cb) TriggerServerEvent('AX_QuestCreator:CreateQuest', data); cb('ok') end)
RegisterNUICallback('updateQuest',  function(data, cb) TriggerServerEvent('AX_QuestCreator:UpdateQuest', data.id, data); cb('ok') end)
RegisterNUICallback('deleteQuest',  function(data, cb) TriggerServerEvent('AX_QuestCreator:DeleteQuest', data.id); cb('ok') end)
RegisterNUICallback('getFactions',  function(data, cb) TriggerServerEvent('AX_QuestCreator:GetFactions'); cb('ok') end)

RegisterNetEvent('AX_QuestCreator:Notify', function(msg, ntype) Notify(msg, ntype) end)

RegisterNUICallback('deliverItems', function(data, cb)
    SetNuiFocus(false, false)
    nuiOpen = false
    TriggerServerEvent('AX_QuestCreator:DeliverItems', data.instanceId)
    cb('ok')
end)

RegisterNUICallback('closeDelivery', function(data, cb)
    SetNuiFocus(false, false)
    nuiOpen = false
    cb('ok')
end)

RegisterNUICallback('getPlayerCoords', function(data, cb)
    local coords = GetEntityCoords(PlayerPedId())
    cb({ x = math.floor(coords.x * 10) / 10, y = math.floor(coords.y * 10) / 10, z = math.floor(coords.z * 10) / 10 })
end)

CreateThread(function()
    while true do
        Wait(0)
        if nuiOpen and IsControlJustReleased(0, 200) then
            SetNuiFocus(false, false)
            nuiOpen = false
            SendNUIMessage({ action = 'forceClose' })
        end
    end
end)