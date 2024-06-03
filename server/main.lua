local KGCore = exports['kg-core']:GetCoreObject()

-- Functions

local function generateOID()
    local num = math.random(1, 10) .. math.random(111, 999)

    return 'OC' .. num
end

-- Callbacks

KGCore.Functions.CreateCallback('kg-occasions:server:getVehicles', function(_, cb)
    local result = MySQL.query.await('SELECT * FROM occasion_vehicles', {})
    if result[1] then
        cb(result)
    else
        cb(nil)
    end
end)

KGCore.Functions.CreateCallback('kg-occasions:server:checkVehicleOwner', function(source, cb, plate)
    local pData = KGCore.Functions.GetPlayer(source)
    MySQL.query('SELECT balance FROM player_vehicles WHERE plate = ? AND citizenid = ?', { plate, pData.PlayerData.citizenid }, function(result)
        if result[1] then
            cb(true, result[1].balance)
        else
            cb(false)
        end
    end)
end)

KGCore.Functions.CreateCallback('kg-occasions:server:getSellerInformation', function(_, cb, citizenid)
    MySQL.query('SELECT * FROM players WHERE citizenid = ?', { citizenid }, function(result)
        if result[1] then
            cb(result[1])
        else
            cb(nil)
        end
    end)
end)

KGCore.Functions.CreateCallback('kg-vehiclesales:server:CheckModelName', function(_, cb, plate)
    if plate then
        local ReturnData = MySQL.scalar.await('SELECT vehicle FROM player_vehicles WHERE plate = ?', { plate })
        cb(ReturnData)
    end
end)

-- Events

RegisterNetEvent('kg-occasions:server:ReturnVehicle', function(vehicleData)
    local src = source
    local Player = KGCore.Functions.GetPlayer(src)
    local result = MySQL.query.await('SELECT * FROM occasion_vehicles WHERE plate = ? AND occasionid = ?', { vehicleData['plate'], vehicleData['oid'] })
    if result[1] then
        if result[1].seller == Player.PlayerData.citizenid then
            MySQL.insert('INSERT INTO player_vehicles (license, citizenid, vehicle, hash, mods, plate, state) VALUES (?, ?, ?, ?, ?, ?, ?)', { Player.PlayerData.license, Player.PlayerData.citizenid, vehicleData['model'], joaat(vehicleData['model']), vehicleData['mods'], vehicleData['plate'], 0 })
            MySQL.query('DELETE FROM occasion_vehicles WHERE occasionid = ? AND plate = ?', { vehicleData['oid'], vehicleData['plate'] })
            TriggerClientEvent('kg-occasions:client:ReturnOwnedVehicle', src, result[1])
            TriggerClientEvent('kg-occasion:client:refreshVehicles', -1)
        else
            TriggerClientEvent('KGCore:Notify', src, Lang:t('error.not_your_vehicle'), 'error', 3500)
        end
    else
        TriggerClientEvent('KGCore:Notify', src, Lang:t('error.vehicle_does_not_exist'), 'error', 3500)
    end
end)

RegisterNetEvent('kg-occasions:server:sellVehicle', function(vehiclePrice, vehicleData)
    local src = source
    local Player = KGCore.Functions.GetPlayer(src)
    MySQL.query('DELETE FROM player_vehicles WHERE plate = ? AND vehicle = ?', { vehicleData.plate, vehicleData.model })
    MySQL.insert('INSERT INTO occasion_vehicles (seller, price, description, plate, model, mods, occasionid) VALUES (?, ?, ?, ?, ?, ?, ?)', { Player.PlayerData.citizenid, vehiclePrice, vehicleData.desc, vehicleData.plate, vehicleData.model, json.encode(vehicleData.mods), generateOID() })
    TriggerEvent('kg-log:server:CreateLog', 'vehicleshop', 'Vehicle for Sale', 'red', '**' .. GetPlayerName(src) .. '** has a ' .. vehicleData.model .. ' priced at ' .. vehiclePrice)
    TriggerClientEvent('kg-occasion:client:refreshVehicles', -1)
end)

RegisterNetEvent('kg-occasions:server:sellVehicleBack', function(vehData)
    local src = source
    local Player = KGCore.Functions.GetPlayer(src)
    local price = 0
    local plate = vehData.plate
    for _, v in pairs(KGCore.Shared.Vehicles) do
        if v['hash'] == vehData.model then
            price = tonumber(v['price'])
            break
        end
    end
    local payout = math.floor(tonumber(price * 0.5)) -- This will give you half of the cars value
    Player.Functions.AddMoney('bank', payout, 'sold vehicle back')
    TriggerClientEvent('KGCore:Notify', src, Lang:t('success.sold_car_for_price', { value = payout }), 'success', 5500)
    MySQL.query('DELETE FROM player_vehicles WHERE plate = ?', { plate })
end)

RegisterNetEvent('kg-occasions:server:buyVehicle', function(vehicleData)
    local src = source
    local Player = KGCore.Functions.GetPlayer(src)
    local result = MySQL.query.await('SELECT * FROM occasion_vehicles WHERE plate = ? AND occasionid = ?', { vehicleData['plate'], vehicleData['oid'] })
    if result[1] and next(result[1]) then
        if Player.PlayerData.money.bank >= result[1].price then
            local SellerCitizenId = result[1].seller
            local SellerData = KGCore.Functions.GetPlayerByCitizenId(SellerCitizenId)
            local NewPrice = math.ceil((result[1].price / 100) * 77)
            Player.Functions.RemoveMoney('bank', result[1].price, 'bought vehicle used lot')
            MySQL.insert(
                'INSERT INTO player_vehicles (license, citizenid, vehicle, hash, mods, plate, state) VALUES (?, ?, ?, ?, ?, ?, ?)', {
                    Player.PlayerData.license,
                    Player.PlayerData.citizenid, result[1]['model'],
                    GetHashKey(result[1]['model']),
                    result[1]['mods'],
                    result[1]['plate'],
                    0
                })
            if SellerData then
                SellerData.Functions.AddMoney('bank', NewPrice, 'sold vehicle used lot')
            else
                local BuyerData = MySQL.query.await('SELECT * FROM players WHERE citizenid = ?', { SellerCitizenId })
                if BuyerData[1] then
                    local BuyerMoney = json.decode(BuyerData[1].money)
                    BuyerMoney.bank = BuyerMoney.bank + NewPrice
                    MySQL.update('UPDATE players SET money = ? WHERE citizenid = ?', { json.encode(BuyerMoney), SellerCitizenId })
                end
            end
            TriggerEvent('kg-log:server:CreateLog', 'vehicleshop', 'bought', 'green', '**' .. GetPlayerName(src) .. '** has bought for ' .. result[1].price .. ' (' .. result[1].plate .. ') from **' .. SellerCitizenId .. '**')
            TriggerClientEvent('kg-occasions:client:BuyFinished', src, result[1])
            TriggerClientEvent('kg-occasion:client:refreshVehicles', -1)
            MySQL.query('DELETE FROM occasion_vehicles WHERE plate = ? AND occasionid = ?', { result[1].plate, result[1].occasionid })
            exports['kg-phone']:sendNewMailToOffline(SellerCitizenId, {
                sender = Lang:t('mail.sender'),
                subject = Lang:t('mail.subject'),
                message = Lang:t('mail.message', { value = NewPrice, value2 = KGCore.Shared.Vehicles[result[1].model].name })
            })
        else
            TriggerClientEvent('KGCore:Notify', src, Lang:t('error.not_enough_money'), 'error', 3500)
        end
    end
end)
