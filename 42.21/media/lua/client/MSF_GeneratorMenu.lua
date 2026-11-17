require "ISUI/ISInventoryPaneContextMenu"
require "ISUI/ISWorldObjectContextMenu"
require "TimedActions/ISInventoryTransferAction"
require "TimedActions/ISInventoryTransferUtil"
require "TimedActions/ISEquipWeaponAction"
require "TimedActions/ISAddFuel"
require "TimedActions/ISUnequipAction"
require "MSF_WorldMenuHook"

if MSF.generatorMenuInstalled then return end
MSF.generatorMenuInstalled = true

local FUEL_SEARCH_RADIUS = 2

local originalGetNotFullFloorSquare = ISInventoryTransferAction.getNotFullFloorSquare
MSF._originalFuelGetNotFullFloorSquare = originalGetNotFullFloorSquare
function ISInventoryTransferAction:getNotFullFloorSquare(item)
    local square = self.msfDropSquare
    if square and self.destContainer and self.destContainer:getType() == "floor" then
        local ok, canDrop = pcall(function()
            return self:canDropOnFloor(square) and self:floorHasRoomFor(square, item)
        end)
        if ok and canDrop then return square end
    end
    if originalGetNotFullFloorSquare then
        return originalGetNotFullFloorSquare(self, item)
    end
    return nil
end

local function addCandidate(list, seen, item, source, square, worldObject)
    if not item or not MSF.isFuelContainer(item, worldObject) then return end
    local okId, id = pcall(function() return item:getID() end)
    if not okId or id == nil or seen[id] then return end
    seen[id] = true
    table.insert(list, {
        item = item,
        source = source,
        amount = MSF.getFuelAmount(item, worldObject),
        fluidHost = MSF.getFluidContainerHost(item, worldObject),
        square = square,
        worldObject = worldObject,
    })
end

local function collectGroundFuelCandidates(playerObj)
    local result = {}
    local seen = {}
    local playerSquare = playerObj:getCurrentSquare()
    if not playerSquare then return result end
    local cell = getCell()
    local z = playerSquare:getZ()
    for dy = -FUEL_SEARCH_RADIUS, FUEL_SEARCH_RADIUS do
        for dx = -FUEL_SEARCH_RADIUS, FUEL_SEARCH_RADIUS do
            local square = cell:getGridSquare(playerSquare:getX() + dx, playerSquare:getY() + dy, z)
            if square then
                local worldObjects = square:getWorldObjects()
                if worldObjects then
                    for i = 0, worldObjects:size() - 1 do
                        local worldObject = worldObjects:get(i)
                        local item = worldObject and worldObject:getItem()
                        if item and MSF.isFuelContainer(item, worldObject) then
                            local okSource, source = pcall(function() return item:getContainer() end)
                            addCandidate(result, seen, item, okSource and source or nil, square, worldObject)
                        end
                    end
                end

                local objects = square:getObjects()
                if objects then
                    for i = 0, objects:size() - 1 do
                        local object = objects:get(i)
                        if object and instanceof(object, "IsoWorldInventoryObject") then
                            local item = object:getItem()
                            if item and MSF.isFuelContainer(item, object) then
                                local okSource, source = pcall(function() return item:getContainer() end)
                                addCandidate(result, seen, item, okSource and source or nil, square, object)
                            end
                        end
                    end
                end
            end
        end
    end
    return result
end

local function addContainerCandidates(result, seen, container, playerObj)
    if not container then return end
    local candidates = MSF.collectFuelCandidatesFromContainers({ container })
    for _, candidate in ipairs(candidates) do
        local okId, id = pcall(function() return candidate.item:getID() end)
        if okId and id ~= nil and not seen[id] then
            seen[id] = true
            table.insert(result, candidate)
        end
    end
end

local function addWorldObjectCandidates(result, seen, object, playerObj)
    if not object then return end

    if instanceof(object, "IsoWorldInventoryObject") then
        local item = object:getItem()
        if item then
            if MSF.isFuelContainer(item, object) then
                local okSource, source = pcall(function() return item:getContainer() end)
                addCandidate(result, seen, item, okSource and source or nil, object:getSquare(), object)
            end
            if instanceof(item, "InventoryContainer") then
                local okInventory, inventory = pcall(function() return item:getInventory() end)
                if okInventory and inventory then
                    addContainerCandidates(result, seen, inventory, playerObj)
                end
            end
        end
    end

    if instanceof(object, "BaseVehicle") then
        local okParts, partCount = pcall(function() return object:getPartCount() end)
        if okParts and partCount then
            for index = 0, partCount - 1 do
                local okAccess, canAccess = pcall(function() return object:canAccessContainer(index, playerObj) end)
                if not okAccess or canAccess then
                    local okPart, part = pcall(function() return object:getPartByIndex(index) end)
                    if okPart and part then
                        local okContainer, container = pcall(function() return part:getItemContainer() end)
                        if okContainer and container then
                            addContainerCandidates(result, seen, container, playerObj)
                        end
                    end
                end
            end
        end
        return
    end

    local locked = false
    if instanceof(object, "IsoThumpable") then
        local okLocked, value = pcall(function() return object:isLockedToCharacter(playerObj) end)
        locked = okLocked and value == true
    end
    if locked then return end

    local okContainer, container = pcall(function() return object:getContainer() end)
    if okContainer and container then
        addContainerCandidates(result, seen, container, playerObj)
    end

    local okCount, count = pcall(function() return object:getContainerCount() end)
    if okCount and count then
        for index = 0, count - 1 do
            local okIndexed, indexed = pcall(function() return object:getContainerByIndex(index) end)
            if okIndexed and indexed then
                addContainerCandidates(result, seen, indexed, playerObj)
            end
        end
    end
end

local function collectNearbyFuelCandidates(playerObj)
    local result = collectGroundFuelCandidates(playerObj)
    local seen = {}
    for _, candidate in ipairs(result) do
        local okId, id = pcall(function() return candidate.item:getID() end)
        if okId and id ~= nil then seen[id] = true end
    end

    local playerInv = playerObj:getInventory()
    addContainerCandidates(result, seen, playerInv, playerObj)
    local containers = ISInventoryPaneContextMenu.getContainers(playerObj) or ArrayList.new()
    for i = 1, containers:size() do
        addContainerCandidates(result, seen, containers:get(i - 1), playerObj)
    end

    local playerSquare = playerObj:getCurrentSquare()
    if playerSquare then
        local cell = getCell()
        local z = playerSquare:getZ()
        for dy = -FUEL_SEARCH_RADIUS, FUEL_SEARCH_RADIUS do
            for dx = -FUEL_SEARCH_RADIUS, FUEL_SEARCH_RADIUS do
                local square = cell:getGridSquare(playerSquare:getX() + dx, playerSquare:getY() + dy, z)
                if square then
                    local objects = square:getObjects()
                    if objects then
                        for i = 0, objects:size() - 1 do
                            addWorldObjectCandidates(result, seen, objects:get(i), playerObj)
                        end
                    end
                end
            end
        end
    end
    return result
end

local function fuelDebugLine(item, sourceLabel, seen, worldObject)
    if not item then return nil end
    local okId, id = pcall(function() return item:getID() end)
    if okId and id ~= nil then
        if seen[id] then return nil end
        seen[id] = true
    end
    local okType, fullType = pcall(function() return item:getFullType() end)
    local okName, name = pcall(function() return item:getName() end)
    local line = string.format("%s|%s|name=%s", sourceLabel, tostring(fullType or "?"), tostring(name or "?"))
    local okItemFluid, itemFluid = pcall(function() return item:getFluidContainer() end)
    local okWorldFluid, worldFluid = pcall(function() return worldObject and worldObject:getFluidContainer() or nil end)
    local host = MSF.getFluidContainerHost(item, worldObject)
    local hostLabel = "none"
    if okItemFluid and itemFluid then
        hostLabel = "item"
    elseif okWorldFluid and worldFluid then
        hostLabel = "world"
    elseif host then
        hostLabel = "linked"
    end
    if not host then
        return line .. "|host=none"
    end
    local okAmount, amount = pcall(function() return host:getAmount() end)
    local okTag, hasTag = pcall(function() return item:hasTag(ItemTag.PETROL) end)
    local okWater, hasWater = pcall(function() return host:contains(Fluid.Water) end)
    local okFuel, isFuel = pcall(function() return MSF.isFuelContainer(item, worldObject) end)
    local fluidName = "?"
    local okPrimary, primary = pcall(function() return host:getPrimaryFluid() end)
    if okPrimary and primary then
        local okName, nameValue = pcall(function() return primary:getFluidTypeString() end)
        if okName and nameValue then fluidName = tostring(nameValue) end
    end
    local okContainer, container = pcall(function() return item:getContainer() end)
    local containerType = "nil"
    if okContainer and container then
        local okTypeName, typeName = pcall(function() return container:getType() end)
        if okTypeName and typeName then containerType = tostring(typeName) end
    end
    local okWorld, worldItem = pcall(function() return item:getWorldItem() end)
    return line .. string.format(
        "|host=%s|amount=%s|fluid=%s|petrolTag=%s|water=%s|isFuel=%s|container=%s|worldItem=%s",
        hostLabel, tostring(okAmount and amount or nil), fluidName, tostring(okTag and hasTag or nil),
        tostring(okWater and hasWater or nil), tostring(okFuel and isFuel or nil),
        containerType, tostring(okWorld and worldItem ~= nil or false))
end

local function debugFuelScan(playerObj)
    local now = getTimestampMs()
    if MSF._lastFuelDebug and now - MSF._lastFuelDebug < 10000 then return end
    MSF._lastFuelDebug = now

    local lines = {}
    local function add(line)
        if #lines < 100 then table.insert(lines, "MSF|FUELDEBUG|" .. line) end
    end

    local playerSquare = playerObj:getCurrentSquare()
    if not playerSquare then
        add("no_player_square")
    else
        add(string.format("square=%d,%d,%d", playerSquare:getX(), playerSquare:getY(), playerSquare:getZ()))
    end
    local seen = {}
    local cell = getCell()
    if playerSquare and cell then
        local z = playerSquare:getZ()
        for dy = -FUEL_SEARCH_RADIUS, FUEL_SEARCH_RADIUS do
            for dx = -FUEL_SEARCH_RADIUS, FUEL_SEARCH_RADIUS do
                local square = cell:getGridSquare(playerSquare:getX() + dx, playerSquare:getY() + dy, z)
                if square then
                    local worldObjects = square:getWorldObjects()
                    if worldObjects then
                        for i = 0, worldObjects:size() - 1 do
                            local worldObject = worldObjects:get(i)
                            local line = fuelDebugLine(worldObject and worldObject:getItem(), "WORLD", seen, worldObject)
                            if line then add(line) end
                        end
                    end
                    local objects = square:getObjects()
                    if objects then
                        for i = 0, objects:size() - 1 do
                            local object = objects:get(i)
                            if object then
                                if instanceof(object, "IsoWorldInventoryObject") then
                                    local line = fuelDebugLine(object:getItem(), "WORLD2", seen, object)
                                    if line then add(line) end
                                end
                                local okCount, count = pcall(function() return object:getContainerCount() end)
                                if okCount and count then
                                    for index = 0, count - 1 do
                                        local okContainer, container = pcall(function() return object:getContainerByIndex(index) end)
                                        if okContainer and container then
                                            local okItems, items = pcall(function()
                                                return container:getAllEvalRecurse(function(item) return item:getFluidContainer() ~= nil end, ArrayList.new())
                                            end)
                                            if okItems and items then
                                                for itemIndex = 1, items:size() do
                                                    local line = fuelDebugLine(items:get(itemIndex - 1), "OBJECT", seen)
                                                    if line then add(line) end
                                                end
                                            end
                                        end
                                    end
                                end
                                if instanceof(object, "BaseVehicle") then
                                    local okParts, partCount = pcall(function() return object:getPartCount() end)
                                    if okParts and partCount then
                                        for index = 0, partCount - 1 do
                                            local okAccess, canAccess = pcall(function() return object:canAccessContainer(index, playerObj) end)
                                            if not okAccess or canAccess then
                                                local okPart, part = pcall(function() return object:getPartByIndex(index) end)
                                                if okPart and part then
                                                    local okContainer, container = pcall(function() return part:getItemContainer() end)
                                                    if okContainer and container then
                                                        local okItems, items = pcall(function()
                                                            return container:getAllEvalRecurse(function(item) return item:getFluidContainer() ~= nil end, ArrayList.new())
                                                        end)
                                                        if okItems and items then
                                                            for itemIndex = 1, items:size() do
                                                                local line = fuelDebugLine(items:get(itemIndex - 1), "VEHICLE", seen)
                                                                if line then add(line) end
                                                            end
                                                        end
                                                    end
                                                end
                                            end
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    local playerInv = playerObj:getInventory()
    local okPlayerItems, playerItems = pcall(function()
        return playerInv:getAllEvalRecurse(function(item) return item:getFluidContainer() ~= nil end, ArrayList.new())
    end)
    if okPlayerItems and playerItems then
        for i = 1, playerItems:size() do
            local line = fuelDebugLine(playerItems:get(i - 1), "PLAYER", seen)
            if line then add(line) end
        end
    end
    local containers = ISInventoryPaneContextMenu.getContainers(playerObj) or ArrayList.new()
    for i = 1, containers:size() do
        local container = containers:get(i - 1)
        if container then
            local okItems, items = pcall(function()
                return container:getAllEvalRecurse(function(item) return item:getFluidContainer() ~= nil end, ArrayList.new())
            end)
            if okItems and items then
                for itemIndex = 1, items:size() do
                    local line = fuelDebugLine(items:get(itemIndex - 1), "CONTAINER", seen)
                    if line then add(line) end
                end
            end
        end
    end

    if #lines == 0 then add("no_debug_items") end
    for _, line in ipairs(lines) do print(line) end
end

local function findGenerator(worldobjects)
    for _, object in ipairs(worldobjects or {}) do
        if object and instanceof(object, "IsoGenerator") then
            return object
        end
    end
    return nil
end

local function findGeneratorMenu(context)
    local root = context:getOptionFromName(getText("ContextMenu_Generator"))
    if root and root.subOption then
        return context:getSubMenu(root.subOption)
    end
    return nil
end

local function isGeneratorReachable(playerObj, generator)
    local square = generator:getSquare()
    if not square then return false end
    local ok, tile = pcall(function() return AdjacentFreeTileFinder.Find(square, playerObj) end)
    return ok and tile ~= nil
end

local function makeFloorSource(item, worldObject)
    if worldObject then
        local okWorld, current = pcall(function() return item:getWorldItem() end)
        if okWorld and current == nil then
            pcall(function() item:setWorldItem(worldObject) end)
        end
    end
    local floor = ItemContainer.new("floor", nil, nil)
    local ok = pcall(function() floor:AddItem(item) end)
    if ok then return floor end
    return nil
end

MSF_AddFuel = ISAddFuel:derive("MSF_AddFuel")

function MSF_AddFuel:new(character, generator, petrol, fluidHost)
    local o = ISBaseTimedAction.new(self, character)
    o.petrol = petrol
    o.fluidCont = fluidHost or petrol:getFluidContainer()
    o.generator = generator
    o.maxTime = o:getDuration()
    return o
end

local function queueReturn(playerObj, candidate, playerInv)
    local source = candidate.source
    if source and source ~= playerInv then
        local action = ISInventoryTransferUtil.newInventoryTransferAction(playerObj, candidate.item, playerInv, source)
        if candidate.square then
            action.msfDropSquare = candidate.square
        end
        ISTimedActionQueue.add(action)
    end
end

function MSF.onAddFuelGeneratorNearby(playerObj, playerNum, generator)
    if not playerObj or not generator then return end
    if playerObj:isDead() or playerObj:getVehicle() then return end
    if generator:isActivated() then return end
    if generator:getFuel() >= generator:getMaxFuel() - 0.0001 then return end

    local candidates = collectNearbyFuelCandidates(playerObj)
    local plan = MSF.buildFuelPlan(generator:getFuel(), generator:getMaxFuel(), candidates)
    if #plan == 0 then return end
    if not generator:getSquare() or not luautils.walkAdj(playerObj, generator:getSquare()) then return end

    local playerInv = playerObj:getInventory()
    for _, candidate in ipairs(plan) do
        -- Ground items have no ItemContainer in B42; make a temporary floor source for pickup/return.
        if not candidate.source and candidate.square then
            candidate.source = makeFloorSource(candidate.item, candidate.worldObject)
        end
        if not candidate.fluidHost then
            candidate.fluidHost = MSF.getFluidContainerHost(candidate.item, candidate.worldObject)
        end
        if candidate.fluidHost and candidate.source then
            if candidate.source ~= playerInv then
                ISTimedActionQueue.add(ISInventoryTransferUtil.newInventoryTransferAction(playerObj, candidate.item, candidate.source, playerInv))
            end
            ISTimedActionQueue.add(ISEquipWeaponAction:new(playerObj, candidate.item, 50, true, false))
            ISTimedActionQueue.add(MSF_AddFuel:new(playerObj, generator, candidate.item, candidate.fluidHost))
            ISTimedActionQueue.add(ISUnequipAction:new(playerObj, candidate.item, 50))
            queueReturn(playerObj, candidate, playerInv)
        end
    end
end

local function onFillWorldObjectContextMenu(playerNum, context, worldobjects, test)
    if test then return end
    local playerObj = getSpecificPlayer(playerNum)
    if not playerObj or playerObj:isDead() or playerObj:getVehicle() then return end

    local generator = findGenerator(worldobjects)
    if not generator then return end
    local menu = findGeneratorMenu(context)
    if not menu then return end

    local candidates = collectNearbyFuelCandidates(playerObj)
    if #candidates == 0 then
        pcall(function() debugFuelScan(playerObj) end)
    end
    local label = getText("ContextMenu_MSF_GeneratorAddFuelNearby")
    local option = menu:insertOptionAfter(
        getText("ContextMenu_GeneratorAddFuel"),
        label,
        playerObj,
        MSF.onAddFuelGeneratorNearby,
        playerNum,
        generator
    )

    local tooltip = ISWorldObjectContextMenu.addToolTip()
    if generator:isActivated() then
        option.notAvailable = true
        tooltip.description = getText("ContextMenu_MSF_GeneratorAddFuelNearby_Activated")
    elseif generator:getFuel() >= generator:getMaxFuel() - 0.0001 then
        option.notAvailable = true
        tooltip.description = getText("ContextMenu_MSF_GeneratorAddFuelNearby_Full")
    elseif #candidates == 0 then
        option.notAvailable = true
        tooltip.description = getText("ContextMenu_MSF_GeneratorAddFuelNearby_NoFuel")
    elseif not isGeneratorReachable(playerObj, generator) then
        option.notAvailable = true
        tooltip.description = getText("ContextMenu_MSF_GeneratorAddFuelNearby_Unreachable")
    else
        tooltip.description = getText("ContextMenu_MSF_GeneratorAddFuelNearby_tt", #candidates)
    end
    option.toolTip = tooltip
end

-- Native world-menu handlers can short-circuit before OnFillWorldObjectContextMenu.
-- Add the option after the native menu exists; the shared hook keeps the original
-- safehouse permission gate.
Events.OnFillWorldObjectContextMenu.Remove(onFillWorldObjectContextMenu)
local generatorPostFillRegistered = MSF.registerWorldMenuPostFill("generator", onFillWorldObjectContextMenu)
if not generatorPostFillRegistered then
    Events.OnFillWorldObjectContextMenu.Add(onFillWorldObjectContextMenu)
end

function MSF.uninstallGeneratorMenu()
    Events.OnFillWorldObjectContextMenu.Remove(onFillWorldObjectContextMenu)
    MSF.unregisterWorldMenuPostFill("generator")
    if MSF._originalFuelGetNotFullFloorSquare then
        ISInventoryTransferAction.getNotFullFloorSquare = MSF._originalFuelGetNotFullFloorSquare
    end
    MSF.generatorMenuInstalled = false
end
