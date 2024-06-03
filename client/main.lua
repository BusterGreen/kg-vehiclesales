local KGCore = exports['kg-core']:GetCoreObject()
local Zone = nil
local TextShown = false
local AcitveZone = {}
local CurrentVehicle = {}
local SpawnZone = {}
local EntityZones = {}
local occasionVehicles = {}

-- Functions

local function spawnOccasionsVehicles(vehicles)
    if Zone then
        local oSlot = Config.Zones[Zone].VehicleSpots
        if not occasionVehicles[Zone] then occasionVehicles[Zone] = {} end
        if vehicles then
            for i = 1, #vehicles, 1 do
                local model = GetHashKey(vehicles[i].model)
                RequestModel(model)
                while not HasModelLoaded(model) do
                    Wait(0)
                end
                occasionVehicles[Zone][i] = {
                    car   = CreateVehicle(model, oSlot[i].x, oSlot[i].y, oSlot[i].z, false, false),
                    loc   = vector3(oSlot[i].x, oSlot[i].y, oSlot[i].z),
                    price = vehicles[i].price,
                    owner = vehicles[i].seller,
                    model = vehicles[i].model,
                    plate = vehicles[i].plate,
                    oid   = vehicles[i].occasionid,
                    desc  = vehicles[i].description,
                    mods  = vehicles[i].mods
                }

                KGCore.Functions.SetVehicleProperties(occasionVehicles[Zone][i].car, json.decode(occasionVehicles[Zone][i].mods))

                SetModelAsNoLongerNeeded(model)
                SetVehicleOnGroundProperly(occasionVehicles[Zone][i].car)
                SetEntityInvincible(occasionVehicles[Zone][i].car, true)
                SetEntityHeading(occasionVehicles[Zone][i].car, oSlot[i].w)
                SetVehicleDoorsLocked(occasionVehicles[Zone][i].car, 3)
                SetVehicleNumberPlateText(occasionVehicles[Zone][i].car, occasionVehicles[Zone][i].oid)
                FreezeEntityPosition(occasionVehicles[Zone][i].car, true)
                if Config.UseTarget then
                    if not EntityZones then EntityZones = {} end
                    EntityZones[i] = exports['kg-target']:AddTargetEntity(occasionVehicles[Zone][i].car, {
                        options = {
                            {
                                type = 'client',
                                event = 'kg-vehiclesales:client:OpenContract',
                                icon = 'fas fa-car',
                                label = Lang:t('menu.view_contract'),
                                Contract = i
                            }
                        },
                        distance = 2.0
                    })
                end
            end
        end
    end
end

local function despawnOccasionsVehicles()
    if not Zone then return end
    local oSlot = Config.Zones[Zone].VehicleSpots
    for i = 1, #oSlot, 1 do
        local loc = oSlot[i]
        local oldVehicle = GetClosestVehicle(loc.x, loc.y, loc.z, 1.3, 0, 70)

        if oldVehicle then
            KGCore.Functions.DeleteVehicle(oldVehicle)
        end

        if EntityZones[i] and Config.UseTarget then
            exports['kg-target']:RemoveZone(EntityZones[i])
        end
    end
    EntityZones = {}
end

local function openSellContract(bool)
    local pData = KGCore.Functions.GetPlayerData()

    SetNuiFocus(bool, bool)
    SendNUIMessage({
        action = 'sellVehicle',
        showTakeBackOption = false,
        bizName = Config.Zones[Zone].BusinessName,
        sellerData = {
            firstname = pData.charinfo.firstname,
            lastname = pData.charinfo.lastname,
            account = pData.charinfo.account,
            phone = pData.charinfo.phone
        },
        plate = KGCore.Functions.GetPlate(GetVehiclePedIsUsing(PlayerPedId()))
    })
end

local function openBuyContract(sellerData, vehicleData)
    local pData = KGCore.Functions.GetPlayerData()
    SetNuiFocus(true, true)
    SendNUIMessage({
        action = 'buyVehicle',
        showTakeBackOption = sellerData.charinfo.firstname == pData.charinfo.firstname and sellerData.charinfo.lastname == pData.charinfo.lastname,
        bizName = Config.Zones[Zone].BusinessName,
        sellerData = {
            firstname = sellerData.charinfo.firstname,
            lastname = sellerData.charinfo.lastname,
            account = sellerData.charinfo.account,
            phone = sellerData.charinfo.phone
        },
        vehicleData = {
            desc = vehicleData.desc,
            price = vehicleData.price
        },
        plate = vehicleData.plate
    })
end

local function sellVehicleWait(price)
    DoScreenFadeOut(250)
    Wait(250)
    KGCore.Functions.DeleteVehicle(GetVehiclePedIsIn(PlayerPedId()))
    Wait(1500)
    DoScreenFadeIn(250)
    KGCore.Functions.Notify(Lang:t('success.car_up_for_sale', { value = price }), 'success')
    PlaySound(-1, 'SELECT', 'HUD_FRONTEND_DEFAULT_SOUNDSET', 0, 0, 1)
end

local function SellData(data, model)
    KGCore.Functions.TriggerCallback('kg-vehiclesales:server:CheckModelName', function(DataReturning)
        local vehicleData = {}
        vehicleData.ent = GetVehiclePedIsUsing(PlayerPedId())
        vehicleData.model = DataReturning
        vehicleData.plate = model
        vehicleData.mods = KGCore.Functions.GetVehicleProperties(vehicleData.ent)
        vehicleData.desc = data.desc
        TriggerServerEvent('kg-occasions:server:sellVehicle', data.price, vehicleData)
        sellVehicleWait(data.price)
    end, model)
end

local listen = false
local function Listen4Control(spot) -- Uses this to listen for controls to open various menus.
    listen = true
    CreateThread(function()
        while listen do
            if IsControlJustReleased(0, 38) then -- E
                if spot then
                    local data = { Contract = spot }
                    TriggerEvent('kg-vehiclesales:client:OpenContract', data)
                else
                    if IsPedInAnyVehicle(PlayerPedId(), false) then
                        listen = false
                        TriggerEvent('kg-occasions:client:MainMenu')
                        --TriggerEvent('kg-vehiclesales:client:SellVehicle')
                    else
                        KGCore.Functions.Notify(Lang:t('error.not_in_veh'), 'error', 4500)
                    end
                end
            end
            Wait(0)
        end
    end)
end

---- ** Main Zone Functions ** ----

local function CreateZones()
    for k, v in pairs(Config.Zones) do
        local SellSpot = PolyZone:Create(v.PolyZone, {
            name = k,
            minZ = v.MinZ,
            maxZ = v.MaxZ,
            debugPoly = false
        })

        SellSpot:onPlayerInOut(function(isPointInside)
            if isPointInside and Zone ~= k then
                Zone = k
                KGCore.Functions.TriggerCallback('kg-occasions:server:getVehicles', function(vehicles)
                    despawnOccasionsVehicles()
                    spawnOccasionsVehicles(vehicles)
                end)
            else
                despawnOccasionsVehicles()
                Zone = nil
            end
        end)
        AcitveZone[k] = SellSpot
    end
end

local function DeleteZones()
    for k in pairs(AcitveZone) do
        AcitveZone[k]:destroy()
    end
    AcitveZone = {}
end

local function IsCarSpawned(Car)
    local bool = false

    if occasionVehicles then
        for k in pairs(occasionVehicles[Zone]) do
            if k == Car then
                bool = true
                break
            end
        end
    end
    return bool
end

-- NUI Callbacks

RegisterNUICallback('sellVehicle', function(data, cb)
    local plate = KGCore.Functions.GetPlate(GetVehiclePedIsUsing(PlayerPedId())) --Getting the plate and sending to the function
    SellData(data, plate)
    cb('ok')
end)

RegisterNUICallback('close', function(_, cb)
    SetNuiFocus(false, false)
    cb('ok')
end)

RegisterNUICallback('buyVehicle', function(_, cb)
    TriggerServerEvent('kg-occasions:server:buyVehicle', CurrentVehicle)
    cb('ok')
end)

RegisterNUICallback('takeVehicleBack', function(_, cb)
    TriggerServerEvent('kg-occasions:server:ReturnVehicle', CurrentVehicle)
    cb('ok')
end)

-- Events

RegisterNetEvent('kg-occasions:client:BuyFinished', function(vehdata)
    local vehmods = json.decode(vehdata.mods)

    DoScreenFadeOut(250)
    Wait(500)
    KGCore.Functions.TriggerCallback('KGCore:Server:SpawnVehicle', function(netId)
        local veh = NetToVeh(netId)
        SetVehicleNumberPlateText(veh, vehdata.plate)
        SetEntityHeading(veh, Config.Zones[Zone].BuyVehicle.w)
        TaskWarpPedIntoVehicle(PlayerPedId(), veh, -1)
        SetVehicleFuelLevel(veh, 100)
        KGCore.Functions.Notify(Lang:t('success.vehicle_bought'), 'success', 2500)
        TriggerEvent('vehiclekeys:client:SetOwner', vehdata.plate)
        SetVehicleEngineOn(veh, true, true)
        Wait(500)
        KGCore.Functions.SetVehicleProperties(veh, vehmods)
    end, vehdata.model, Config.Zones[Zone].BuyVehicle, true)
    Wait(500)
    DoScreenFadeIn(250)
    CurrentVehicle = {}
end)

RegisterNetEvent('kg-occasions:client:SellBackCar', function()
    local ped = PlayerPedId()
    if IsPedInAnyVehicle(ped, false) then
        local vehicleData = {}
        local vehicle = GetVehiclePedIsIn(ped, false)
        vehicleData.model = GetEntityModel(vehicle)
        vehicleData.plate = GetVehicleNumberPlateText(vehicle)
        KGCore.Functions.TriggerCallback('kg-occasions:server:checkVehicleOwner', function(owned, balance)
            if owned then
                if balance < 1 then
                    TriggerServerEvent('kg-occasions:server:sellVehicleBack', vehicleData)
                    KGCore.Functions.DeleteVehicle(vehicle)
                else
                    KGCore.Functions.Notify(Lang:t('error.finish_payments'), 'error', 3500)
                end
            else
                KGCore.Functions.Notify(Lang:t('error.not_your_vehicle'), 'error', 3500)
            end
        end, vehicleData.plate)
    else
        KGCore.Functions.Notify(Lang:t('error.not_in_veh'), 'error', 4500)
    end
end)

RegisterNetEvent('kg-occasions:client:ReturnOwnedVehicle', function(vehdata)
    local vehmods = json.decode(vehdata.mods)
    DoScreenFadeOut(250)
    Wait(500)
    KGCore.Functions.TriggerCallback('KGCore:Server:SpawnVehicle', function(netId)
        local veh = NetToVeh(netId)
        SetVehicleNumberPlateText(veh, vehdata.plate)
        SetEntityHeading(veh, Config.Zones[Zone].BuyVehicle.w)
        TaskWarpPedIntoVehicle(PlayerPedId(), veh, -1)
        SetVehicleFuelLevel(veh, 100)
        KGCore.Functions.Notify(Lang:t('info.vehicle_returned'))
        TriggerEvent('vehiclekeys:client:SetOwner', vehdata.plate)
        SetVehicleEngineOn(veh, true, true)
        Wait(500)
        KGCore.Functions.SetVehicleProperties(veh, vehmods)
    end, vehdata.model, Config.Zones[Zone].BuyVehicle, true)
    Wait(500)
    DoScreenFadeIn(250)
    CurrentVehicle = {}
end)

RegisterNetEvent('kg-occasion:client:refreshVehicles', function()
    if Zone then
        KGCore.Functions.TriggerCallback('kg-occasions:server:getVehicles', function(vehicles)
            despawnOccasionsVehicles()
            spawnOccasionsVehicles(vehicles)
        end)
    end
end)

RegisterNetEvent('kg-vehiclesales:client:SellVehicle', function()
    local VehiclePlate = KGCore.Functions.GetPlate(GetVehiclePedIsIn(PlayerPedId()))
    KGCore.Functions.TriggerCallback('kg-occasions:server:checkVehicleOwner', function(owned, balance)
        if owned then
            if balance < 1 then
                KGCore.Functions.TriggerCallback('kg-occasions:server:getVehicles', function(vehicles)
                    if vehicles == nil or #vehicles < #Config.Zones[Zone].VehicleSpots then
                        openSellContract(true)
                    else
                        KGCore.Functions.Notify(Lang:t('error.no_space_on_lot'), 'error', 3500)
                    end
                end)
            else
                KGCore.Functions.Notify(Lang:t('error.finish_payments'), 'error', 3500)
            end
        else
            KGCore.Functions.Notify(Lang:t('error.not_your_vehicle'), 'error', 3500)
        end
    end, VehiclePlate)
end)

RegisterNetEvent('kg-vehiclesales:client:OpenContract', function(data)
    CurrentVehicle = occasionVehicles[Zone][data.Contract]
    if CurrentVehicle then
        KGCore.Functions.TriggerCallback('kg-occasions:server:getSellerInformation', function(info)
            if info then
                info.charinfo = json.decode(info.charinfo)
            else
                info = {}
                info.charinfo = {
                    firstname = Lang:t('charinfo.firstname'),
                    lastname = Lang:t('charinfo.lastname'),
                    account = Lang:t('charinfo.account'),
                    phone = Lang:t('charinfo.phone')
                }
            end

            openBuyContract(info, CurrentVehicle)
        end, CurrentVehicle.owner)
    else
        KGCore.Functions.Notify(Lang:t('error.not_for_sale'), 'error', 7500)
    end
end)

RegisterNetEvent('kg-occasions:client:MainMenu', function()
    local MainMenu = {
        {
            isMenuHeader = true,
            header = Config.Zones[Zone].BusinessName
        },
        {
            header = Lang:t('menu.sell_vehicle'),
            txt = Lang:t('menu.sell_vehicle_help'),
            params = {
                event = 'kg-vehiclesales:client:SellVehicle',
            }
        },
        {
            header = Lang:t('menu.sell_back'),
            txt = Lang:t('menu.sell_back_help'),
            params = {
                event = 'kg-occasions:client:SellBackCar',
            }
        }
    }

    exports['kg-menu']:openMenu(MainMenu)
end)

-- Threads

CreateThread(function()
    for _, cars in pairs(Config.Zones) do
        local OccasionBlip = AddBlipForCoord(cars.SellVehicle.x, cars.SellVehicle.y, cars.SellVehicle.z)
        SetBlipSprite(OccasionBlip, 326)
        SetBlipDisplay(OccasionBlip, 4)
        SetBlipScale(OccasionBlip, 0.75)
        SetBlipAsShortRange(OccasionBlip, true)
        SetBlipColour(OccasionBlip, 3)
        BeginTextCommandSetBlipName('STRING')
        AddTextComponentSubstringPlayerName(Lang:t('info.used_vehicle_lot'))
        EndTextCommandSetBlipName(OccasionBlip)
    end
end)

CreateThread(function()
    for k, cars in pairs(Config.Zones) do
        SpawnZone[k] = CircleZone:Create(vector3(cars.SellVehicle.x, cars.SellVehicle.y, cars.SellVehicle.z), 3.0, {
            name = 'OCSell' .. k,
            debugPoly = false,
        })

        SpawnZone[k]:onPlayerInOut(function(isPointInside)
            if isPointInside and IsPedInAnyVehicle(PlayerPedId(), false) then
                exports['kg-core']:DrawText(Lang:t('menu.interaction'), 'left')
                TextShown = true
                Listen4Control()
            else
                listen = false
                if TextShown then
                    TextShown = false
                    exports['kg-core']:HideText()
                end
            end
        end)
        if not Config.UseTarget then
            for k2, v in pairs(Config.Zones[k].VehicleSpots) do
                local VehicleZones = BoxZone:Create(vector3(v.x, v.y, v.z), 4.3, 3.6, {
                    name = 'VehicleSpot' .. k .. k2,
                    debugPoly = false,
                    minZ = v.z - 2,
                    maxZ = v.z + 2,
                })

                VehicleZones:onPlayerInOut(function(isPointInside)
                    if isPointInside and IsCarSpawned(k2) then
                        exports['kg-core']:DrawText(Lang:t('menu.view_contract_int'), 'left')
                        TextShown = true
                        Listen4Control(k2)
                    else
                        listen = false
                        if TextShown then
                            TextShown = false
                            exports['kg-core']:HideText()
                        end
                    end
                end)
            end
        end
    end
end)

---- ** Mostly just to ensure you can restart resources live without issues, also improves the code slightly. ** ----

RegisterNetEvent('KGCore:Client:OnPlayerLoaded', function()
    CreateZones()
end)

RegisterNetEvent('KGCore:Client:OnPlayerUnload', function()
    DeleteZones()
end)

AddEventHandler('onResourceStart', function(resourceName)
    if GetCurrentResourceName() == resourceName then
        CreateZones()
    end
end)

AddEventHandler('onResourceStop', function(resourceName)
    if GetCurrentResourceName() == resourceName then
        DeleteZones()
        despawnOccasionsVehicles()
    end
end)