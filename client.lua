-- ============================================================
--  AX_QuestCreator | client/client.lua
--  Lógica de cliente: zonas, marcadores, progreso, interacciones
-- ============================================================

local ESX = exports['es_extended']:getSharedObject()

-- ─── ESTADO LOCAL ───────────────────────────────────────────

local activeQuests   = {}   -- { [instanceId] = questData }
local questBlips     = {}   -- { [instanceId] = blipHandle }
local questZones     = {}   -- { [instanceId] = zoneData }
local questThreads   = {}   -- { [instanceId] = threadRunning }
local repairProgress = {}   -- { [instanceId] = { [pointIdx] = bool } }

local nuiOpen = false

-- ─── UTILIDADES ─────────────────────────────────────────────

local function DrawMarker3D(x, y, z, r, g, b, a, scale)
    scale = scale or Config.MarkerScale
    DrawMarker(Config.MarkerType, x, y, z - 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
        scale, scale, 1.0, r, g, b, a, false, true, 2, false, nil, nil, false)
end

local function DrawZoneCircle(zone, color)
    local pts = 36
    for i = 0, pts - 1 do
        local angle1 = math.rad(i * (360 / pts))
        local angle2 = math.rad((i + 1) * (360 / pts))
        DrawLine(
            zone.x + math.cos(angle1) * zone.radius, zone.y + math.sin(angle1) * zone.radius, zone.z,
            zone.x + math.cos(angle2) * zone.radius, zone.y + math.sin(angle2) * zone.radius, zone.z,
            color.r, color.g, color.b, 220
        )
    end
end

local function IsInZone(zone)
    local px, py, pz = table.unpack(GetEntityCoords(PlayerPedId()))
    return #(vector3(px, py, pz) - vector3(zone.x, zone.y, zone.z)) <= zone.radius
end

local function CreateQuestBlip(instanceId, zone, questType, questName)
    local blip = AddBlipForCoord(zone.x, zone.y, zone.z)
    local cfg  = Config.Blips[questType]
    SetBlipSprite(blip, cfg.sprite)
    SetBlipColour(blip, cfg.color)
    SetBlipScale(blip, cfg.scale)
    SetBlipAsShortRange(blip, false)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentString(questName)
    EndTextCommandSetBlipName(blip)
    questBlips[instanceId] = blip
end

local function RemoveQuestBlip(instanceId)
    if questBlips[instanceId] then
        RemoveBlip(questBlips[instanceId])
        questBlips[instanceId] = nil
    end
end

local function Notify(msg, ntype)
    if Config.NotifyType == 'ox_lib' then
        lib.notify({ title = 'Misión', description = msg, type = ntype or 'inform' })
    else
        ESX.ShowNotification(msg)
    end
end

-- ─── HUD DE PROGRESO EN PANTALLA ────────────────────────────

local function DrawQuestHUD()
    local y = 0.15
    for instanceId, quest in pairs(activeQuests) do
        local progress = quest.progress
        if not progress then goto continue end

        local pct   = 0
        local label = ''
        local current = 0
        local required = progress.required or 1

        if quest.type == 'ELIMINATE' then
            current = progress.kills or 0
            pct     = current / required * 100
            label   = quest.name .. '  ' .. current .. '/' .. required .. ' eliminados'
        elseif quest.type == 'COLLECT' then
            current = progress.collected or 0
            pct     = current / required * 100
            label   = quest.name .. '  ' .. current .. '/' .. required .. ' recolectados'
        elseif quest.type == 'DEFEND' then
            current = progress.elapsed_seconds or 0
            pct     = current / required * 100
            label   = quest.name .. '  ' .. current .. 's/' .. required .. 's'
        elseif quest.type == 'REPAIR' then
            current = progress.repaired or 0
            pct     = current / required * 100
            label   = quest.name .. '  ' .. current .. '/' .. required .. ' reparados'
        end

        pct = math.min(pct, 100)

        -- Fondo total
        DrawRect(0.85, y, 0.28, 0.038, 10, 10, 10, 200)
        -- Barra de progreso
        if pct > 0 then
            local barWidth = (pct / 100) * 0.28
            DrawRect(0.71 + barWidth / 2, y, barWidth, 0.038, 192, 57, 43, 180)
        end
        -- Borde
        DrawRect(0.71, y - 0.019, 0.001, 0.038, 192, 57, 43, 255)
        DrawRect(0.99, y - 0.019, 0.001, 0.038, 192, 57, 43, 255)

        -- Texto
        SetTextFont(4)
        SetTextScale(0.28, 0.28)
        SetTextColour(255, 255, 255, 255)
        SetTextOutline()
        SetTextEntry('STRING')
        AddTextComponentString(label)
        DrawText(0.725, y - 0.013)

        y = y + 0.055

        ::continue::
    end
end

-- ─── LÓGICA ELIMINATE ───────────────────────────────────────

local function StartEliminateThread(instanceId, quest)
    if questThreads[instanceId] then return end
    questThreads[instanceId] = true

    CreateThread(function()
        local zone = quest.objectiveData.zone

        while activeQuests[instanceId] do
            Wait(0)

            -- Dibujar zona
            DrawZoneCircle(zone, Config.ZoneColor)
            DrawMarker3D(zone.x, zone.y, zone.z, 255, 50, 50, 100)

            if not IsInZone(zone) then Wait(500) end
        end

        questThreads[instanceId] = nil
    end)

    -- Thread de detección de kills en zona
    CreateThread(function()
        while activeQuests[instanceId] do
            Wait(500)

            if not IsInZone(quest.objectiveData.zone) then goto continue end

            -- Iterar peds cercanos para detectar muertes
            local ped  = PlayerPedId()
            local peds = GetGamePool('CPed')

            for _, entity in ipairs(peds) do
                if entity ~= ped and not IsPedAPlayer(entity) then
                    if IsEntityDead(entity) and not Entity(entity).state.ax_counted then
                        local ex, ey, ez  = table.unpack(GetEntityCoords(entity))
                        local zone = quest.objectiveData.zone
                        if #(vector3(ex, ey, ez) - vector3(zone.x, zone.y, zone.z)) <= zone.radius then
                            -- Marcar como contado para no contar dos veces
                            Entity(entity).state:set('ax_counted', true, false)

                            local progress = activeQuests[instanceId] and activeQuests[instanceId].progress
                            if progress then
                                progress.kills = (progress.kills or 0) + 1
                                TriggerServerEvent('AX_QuestCreator:UpdateProgress', instanceId, progress)
                            end
                        end
                    end
                end
            end

            ::continue::
        end
    end)
end

-- ─── LÓGICA COLLECT ─────────────────────────────────────────

local function StartCollectThread(instanceId, quest)
    if questThreads[instanceId] then return end
    questThreads[instanceId] = true

    CreateThread(function()
        local zone = quest.objectiveData.zone

        while activeQuests[instanceId] do
            Wait(0)
            DrawZoneCircle(zone, Config.ZoneColor)
            DrawMarker3D(zone.x, zone.y, zone.z, 255, 150, 50, 100)
            if not IsInZone(zone) then Wait(500) end
        end
        questThreads[instanceId] = nil
    end)
end

-- El servidor llama a este evento cuando ox_inventory detecta que se recogió el ítem
-- (se debe agregar un hook en ox_inventory o triggerear desde el contexto de recogida)
RegisterNetEvent('AX_QuestCreator:ItemCollected', function(instanceId, amount)
    if not activeQuests[instanceId] then return end
    local progress = activeQuests[instanceId].progress
    progress.collected = (progress.collected or 0) + (amount or 1)
    TriggerServerEvent('AX_QuestCreator:UpdateProgress', instanceId, progress)
    Notify(string.format('Ítem recogido: %d/%d', progress.collected, progress.required), 'inform')
end)

-- ─── LÓGICA DEFEND ──────────────────────────────────────────

local function StartDefendThread(instanceId, quest)
    if questThreads[instanceId] then return end
    questThreads[instanceId] = true

    CreateThread(function()
        local zone    = quest.objectiveData.zone
        local minPl   = quest.objectiveData.min_players_inside or 1
        local lastSend = GetGameTimer()

        while activeQuests[instanceId] do
            Wait(0)
            DrawZoneCircle(zone, Config.ZoneColorDefend)
            DrawMarker3D(zone.x, zone.y, zone.z, 50, 255, 100, 100)

            -- Contar jugadores de la facción en zona
            local count   = 0
            local players = GetActivePlayers()
            for _, playerId in ipairs(players) do
                local ped = GetPlayerPed(playerId)
                local px, py, pz = table.unpack(GetEntityCoords(ped))
                if #(vector3(px, py, pz) - vector3(zone.x, zone.y, zone.z)) <= zone.radius then
                    count = count + 1
                end
            end

            -- Avanzar timer solo si hay suficientes jugadores
            if count >= minPl then
                local now = GetGameTimer()
                if now - lastSend >= 1000 then
                    local progress = activeQuests[instanceId] and activeQuests[instanceId].progress
                    if progress then
                        progress.elapsed_seconds = (progress.elapsed_seconds or 0) + 1
                        TriggerServerEvent('AX_QuestCreator:UpdateProgress', instanceId, progress)
                    end
                    lastSend = now
                end
            else
                -- Mostrar aviso si el jugador actual está en zona pero sin suficientes
                if IsInZone(zone) and count < minPl then
                    -- Mostrar UI hint (se dibuja junto al HUD)
                end
            end

            Wait(500)
        end
        questThreads[instanceId] = nil
    end)
end

-- ─── LÓGICA REPAIR ──────────────────────────────────────────

local function StartRepairThread(instanceId, quest)
    if questThreads[instanceId] then return end
    questThreads[instanceId] = true

    repairProgress[instanceId] = repairProgress[instanceId] or {}

    CreateThread(function()
        local points     = quest.objectiveData.points
        local interactMs = quest.objectiveData.interact_time or Config.RepairTime
        local repairing  = false

        while activeQuests[instanceId] do
            Wait(0)

            for i, point in ipairs(points) do
                if not repairProgress[instanceId] then break end

                local done = repairProgress[instanceId][i]
                local col  = done and { r = 50, g = 255, b = 50 } or Config.ZoneColorRepair

                DrawMarker3D(point.x, point.y, point.z, col.r, col.g, col.b, 200, 1.0)
                DrawZoneCircle({ x = point.x, y = point.y, z = point.z, radius = 3.0 }, col)

                if not done and not repairing then
                    local px, py, pz = table.unpack(GetEntityCoords(PlayerPedId()))
                    local dist = #(vector3(px, py, pz) - vector3(point.x, point.y, point.z))

                    if dist <= Config.InteractDistance then
                        ESX.ShowHelpNotification('[E] Reparar: ' .. (point.label or 'Punto ' .. i))

                        if IsControlJustReleased(0, 38) then
                            repairing = true

                            -- Minijuego en thread separado, resultado via flag
                            local miniResult = nil  -- nil=pendiente, true=pasó, false=falló

                            CreateThread(function()
                                local passed = false
                                while not passed do
                                    local success = exports['devhub_minigames']:startMinigame("minigame_7", "medium")
                                    if success then
                                        passed = true
                                    else
                                        Notify('Minijuego fallido, intenta de nuevo.', 'error')
                                        Wait(1000)
                                    end
                                end
                                miniResult = true
                            end)

                            -- Esperar resultado del minijuego bloqueando este thread
                            while miniResult == nil do Wait(100) end

                            -- Progressbar con callback — usamos flag para bloquear
                            local pbDone = false
                            local pbCancelled = false

                            exports['AX_ProgressBar']:Progress({
                                duration = interactMs,
                                label    = 'Reparando: ' .. (point.label or 'Punto ' .. i),
                                useWhileDead = false,
                                canCancel    = true,
                                controlDisables = {
                                    disableMovement    = true,
                                    disableCarMovement = true,
                                    disableMouse       = false,
                                    disableCombat      = true,
                                },
                                animation = {
                                    animDict = "missheistdockssetup1clipboard@base",
                                    anim     = "base",
                                    flags    = 49,
                                },
}, function(cancelled)
    print('[DEBUG] progressbar callback - cancelled: ' .. tostring(cancelled))
    pbCancelled = cancelled
    pbDone = true
end)

                            -- Esperar que termine el progressbar
                            while not pbDone do Wait(100) end
print('[DEBUG] progressbar terminó - cancelled: ' .. tostring(pbCancelled))
print('[DEBUG] repairing antes de limpiar: ' .. tostring(repairing))

                            if not pbCancelled then
                                if repairProgress[instanceId] then
                                    repairProgress[instanceId][i] = true
                                end

                                local currentQuest = activeQuests[instanceId]
                                if currentQuest and currentQuest.progress then
                                    local progress = currentQuest.progress
                                    progress.points = {}
                                    for j = 1, #points do
                                        progress.points[j] = repairProgress[instanceId] and repairProgress[instanceId][j] or false
                                    end

                                    local repaired = 0
                                    for _, v in ipairs(progress.points) do
                                        if v then repaired = repaired + 1 end
                                    end
                                    progress.repaired = repaired
                                    progress.required = #points

                                    TriggerServerEvent('AX_QuestCreator:UpdateProgress', instanceId, progress)
                                    Notify((point.label or 'Punto ' .. i) .. ' reparado.', 'success')
                                end
                            else
                                Notify('Reparación cancelada.', 'error')
                            end

                            repairing = false
                        end
                    end
                end
            end
        end
        questThreads[instanceId] = nil
    end)
end

-- ─── INICIAR MISIÓN ─────────────────────────────────────────

RegisterNetEvent('AX_QuestCreator:StartQuest', function(questData)
        print('[DEBUG] StartQuest recibido:')
    print(json.encode(questData))
    local instanceId = questData.instanceId
    activeQuests[instanceId] = questData

    -- Inicializar repairProgress si aplica
    if questData.type == 'REPAIR' then
        repairProgress[instanceId] = {}
        if questData.progress and questData.progress.points then
            for i, v in ipairs(questData.progress.points) do
                repairProgress[instanceId][i] = v
            end
        end
    end

    -- Determinar zona principal para el blip
    local zone = questData.objectiveData.zone or
                 (questData.objectiveData.points and questData.objectiveData.points[1])

    if zone then
        CreateQuestBlip(instanceId, zone, questData.type, questData.name)
    end

    -- Iniciar thread según tipo
    if questData.type == 'ELIMINATE' then
        StartEliminateThread(instanceId, questData)
    elseif questData.type == 'COLLECT' then
        StartCollectThread(instanceId, questData)
    elseif questData.type == 'DEFEND' then
        StartDefendThread(instanceId, questData)
    elseif questData.type == 'REPAIR' then
        StartRepairThread(instanceId, questData)
    end

    Notify('Misión iniciada: ' .. questData.name, 'success')
end)

-- ─── EVENTOS DE FIN DE MISIÓN ────────────────────────────────

RegisterNetEvent('AX_QuestCreator:QuestCompleted', function(instanceId, questName, rewards, multiplier)
    activeQuests[instanceId] = nil
    repairProgress[instanceId] = nil
    RemoveQuestBlip(instanceId)

    local rewardText = ''
    if rewards.money and rewards.money > 0 then
        rewardText = rewardText .. '$' .. math.floor(rewards.money * multiplier)
    end
    if rewards.items and #rewards.items > 0 then
        for _, item in ipairs(rewards.items) do
            rewardText = rewardText .. ' + ' .. item.name .. 'x' .. math.floor((item.amount or 1) * multiplier)
        end
    end

    Notify('✓ Misión completada: ' .. questName .. ' | Recompensa: ' .. rewardText, 'success')
end)

RegisterNetEvent('AX_QuestCreator:QuestFailed', function(instanceId, reason)
    activeQuests[instanceId] = nil
    repairProgress[instanceId] = nil
    RemoveQuestBlip(instanceId)
    Notify('✗ Misión fallida: ' .. (reason or 'Sin motivo'), 'error')
end)

RegisterNetEvent('AX_QuestCreator:QuestAbandoned', function(instanceId)
    activeQuests[instanceId] = nil
    repairProgress[instanceId] = nil
    RemoveQuestBlip(instanceId)
    Notify('Misión abandonada.', 'error')
end)

RegisterNetEvent('AX_QuestCreator:ProgressUpdated', function(instanceId, progress)
    if activeQuests[instanceId] then
        activeQuests[instanceId].progress = progress
    end
end)

-- ─── HUD THREAD ─────────────────────────────────────────────

CreateThread(function()
    while true do
        Wait(0)
        if next(activeQuests) then
            DrawQuestHUD()
        end
    end
end)

-- ─── NUI: CREATOR PANEL ──────────────────────────────────────

RegisterNetEvent('AX_QuestCreator:OpenCreatorNUI', function(quests)
    SetNuiFocus(true, true)
    nuiOpen = true
    SendNUIMessage({
        action = 'openCreator',
        quests = quests
    })
end)

RegisterNetEvent('AX_QuestCreator:FactionsList', function(factions)
    SendNUIMessage({
        action   = 'factionsList',
        factions = factions
    })
end)

RegisterNetEvent('AX_QuestCreator:QuestCreated', function(questId)
    SendNUIMessage({ action = 'questCreated', id = questId })
    TriggerServerEvent('AX_QuestCreator:OpenCreator') -- Recargar lista
end)

RegisterNetEvent('AX_QuestCreator:QuestUpdated', function(questId)
    SendNUIMessage({ action = 'questUpdated', id = questId })
    TriggerServerEvent('AX_QuestCreator:OpenCreator')
end)

RegisterNetEvent('AX_QuestCreator:QuestDeleted', function(questId)
    SendNUIMessage({ action = 'questDeleted', id = questId })
    TriggerServerEvent('AX_QuestCreator:OpenCreator')
end)

-- ─── NUI CALLBACKS ──────────────────────────────────────────

RegisterNUICallback('closeCreator', function(data, cb)
    SetNuiFocus(false, false)
    nuiOpen = false
    cb('ok')
end)

RegisterNUICallback('createQuest', function(data, cb)
    TriggerServerEvent('AX_QuestCreator:CreateQuest', data)
    cb('ok')
end)

RegisterNUICallback('updateQuest', function(data, cb)
    TriggerServerEvent('AX_QuestCreator:UpdateQuest', data.id, data)
    cb('ok')
end)

RegisterNUICallback('deleteQuest', function(data, cb)
    TriggerServerEvent('AX_QuestCreator:DeleteQuest', data.id)
    cb('ok')
end)

RegisterNUICallback('toggleQuest', function(data, cb)
    TriggerServerEvent('AX_QuestCreator:ToggleQuest', data.id, data.state)
    cb('ok')
end)

RegisterNUICallback('getFactions', function(data, cb)
    TriggerServerEvent('AX_QuestCreator:GetFactions')
    cb('ok')
end)

-- Cerrar con ESC
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

-- ─── NOTIFY ─────────────────────────────────────────────────

RegisterNetEvent('AX_QuestCreator:Notify', function(msg, ntype)
    Notify(msg, ntype)
end)
