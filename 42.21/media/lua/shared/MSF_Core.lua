MSF = MSF or {}

MSF.MOD_ID = "MoreSensibleFeatures"
MSF.BIND_ID = "MSF_UnequipLight"
MSF.MASK_BIND_ID = "MSF_ToggleMask"
MSF.MASK_RETURN_BIND_ID = "MSF_ToggleMaskReturn"
MSF.BIND_SECTION = "[MoreSensibleFeatures]"

MSF.pending = MSF.pending or {}
MSF.originalContainers = MSF.originalContainers or {}

function MSF.isLightSource(item)
    if not item then return false end
    local ok, strength = pcall(function() return item:getLightStrength() end)
    return ok and strength ~= nil and strength > 0
end

function MSF.isEmitting(item)
    if not item then return false end
    local okEmit, canEmit = pcall(function() return item:canEmitLight() end)
    if not okEmit or not canEmit then return false end
    local okActive, canBeActivated = pcall(function() return item:canBeActivated() end)
    if okActive and canBeActivated then
        local okOn, activated = pcall(function() return item:isActivated() end)
        return okOn and activated == true
    end
    return true
end

function MSF.getEquippedLights(player)
    local result = {}
    if not player then return result end

    local secondary = player:getSecondaryHandItem()
    if MSF.isLightSource(secondary) then
        table.insert(result, { item = secondary, hand = "secondary" })
    end

    local primary = player:getPrimaryHandItem()
    if MSF.isLightSource(primary) and primary ~= secondary then
        table.insert(result, { item = primary, hand = "primary" })
    end

    return result
end

function MSF.getLitKind(item)
    if not item then return nil end
    local okType, fullType = pcall(function() return item:getFullType() end)
    if okType and fullType == "Base.CandleLit" then
        return "candle"
    end
    local okTag, hasTag = pcall(function() return item:hasTag(ItemTag.LIT_LANTERN) end)
    if okTag and hasTag then
        return "lantern"
    end
    return nil
end

function MSF.getExtinguishedType(item)
    if not item then return nil end
    local okType, fullType = pcall(function() return item:getFullType() end)
    if okType and fullType == "Base.CandleLit" then
        return "Base.Candle"
    end
    local okExt, extinguished = pcall(function() return item:getExtinguishedItem() end)
    if okExt and extinguished then
        local okFull, extType = pcall(function() return extinguished:getFullType() end)
        if okFull then return extType end
    end
    return nil
end

function MSF.rememberEquipSource(item, mainInventory)
    if not MSF.isLightSource(item) then return end
    local okId, id = pcall(function() return item:getID() end)
    if not okId or id == nil then return end
    local okContainer, container = pcall(function() return item:getContainer() end)
    if okContainer and container and container ~= mainInventory then
        MSF.originalContainers[id] = container
    else
        MSF.originalContainers[id] = nil
    end
end

function MSF.getOriginalContainer(item)
    if not item then return nil end
    local okId, id = pcall(function() return item:getID() end)
    if not okId or id == nil then return nil end
    return MSF.originalContainers[id]
end

function MSF.clearOriginalContainer(item)
    if not item then return end
    local okId, id = pcall(function() return item:getID() end)
    if okId and id ~= nil then
        MSF.originalContainers[id] = nil
    end
end

function MSF.isWristWatch(item)
    if not item then return false end
    local ok, result = pcall(function() return instanceof(item, "AlarmClockClothing") end)
    return ok and result == true
end

function MSF.isDigitalWristWatch(item)
    if not MSF.isWristWatch(item) then return false end
    local okDigital, digital = pcall(function() return item:isDigital() end)
    if okDigital and digital == true then return true end
    local okTag, hasTag = pcall(function() return item:hasTag(ItemTag.DIGITAL) end)
    return okTag and hasTag == true
end

function MSF.getDismantleWatchesRecipe()
    local manager = getScriptManager()
    if not manager then return nil end
    return manager:getCraftRecipe("DismantleElectronics") or manager:getCraftRecipe("Base.DismantleElectronics")
end

function MSF.collectEligibleItems(containers, predicate)
    local result = {}
    local seen = {}
    for _, container in ipairs(containers or {}) do
        if container then
            local ok, items = pcall(function()
                return container:getAllEvalRecurse(predicate, ArrayList.new())
            end)
            if ok and items then
                for i = 1, items:size() do
                    local item = items:get(i - 1)
                    local okId, id = pcall(function() return item:getID() end)
                    if okId and id ~= nil and not seen[id] then
                        seen[id] = true
                        table.insert(result, item)
                    end
                end
            end
        end
    end
    return result
end

function MSF.collectDigitalWristWatches(containers)
    return MSF.collectEligibleItems(containers, function(item)
        if not MSF.isDigitalWristWatch(item) then return false end
        local okWorn, worn = pcall(function() return item:isWorn() end)
        if not okWorn or worn then return false end
        local okFavorite, favorite = pcall(function() return item:isFavorite() end)
        return okFavorite and favorite == false
    end)
end

function MSF.itemHasTag(item, tag)
    if not item or not tag then return false end
    local ok, hasTag = pcall(function() return item:hasTag(tag) end)
    return ok and hasTag == true
end

function MSF.isBatchEligible(item)
    if not item then return false end
    local okWorn, worn = pcall(function() return item:isWorn() end)
    if not okWorn or worn then return false end
    local okEquipped, equipped = pcall(function() return item:isEquipped() end)
    if not okEquipped or equipped then return false end
    local okFavorite, favorite = pcall(function() return item:isFavorite() end)
    return okFavorite and favorite == false
end

function MSF.isBeltScrapItem(item)
    return MSF.itemHasTag(item, ItemTag.SCRAP_AS_BELT)
end

function MSF.isClothing(item)
    if not item then return false end
    local ok, result = pcall(function() return instanceof(item, "Clothing") end)
    return ok and result == true
end

local cottonRipTags = {}
local cutRipTags = {}
if ItemTag then
    for _, tag in ipairs({ ItemTag.RIP_CLOTHING_COTTON, ItemTag.RIP_CLOTHING_COTON, ItemTag.RIP_CLOTHIG_COTTON }) do
        if tag then table.insert(cottonRipTags, tag) end
    end
    for _, tag in ipairs({ ItemTag.RIP_CLOTHING_DENIM, ItemTag.RIP_CLOTHING_LEATHER }) do
        if tag then table.insert(cutRipTags, tag) end
    end
end

function MSF.getClothingRipRecipeName(item)
    if not MSF.isClothing(item) then return nil end
    for _, tag in ipairs(cottonRipTags) do
        if MSF.itemHasTag(item, tag) then return "RipClothing" end
    end
    for _, tag in ipairs(cutRipTags) do
        if MSF.itemHasTag(item, tag) then return "RipDenimClothing" end
    end
    return nil
end

function MSF.getCraftRecipe(name)
    local manager = getScriptManager()
    if not manager or not name then return nil end
    return manager:getCraftRecipe(name) or manager:getCraftRecipe("Base." .. name)
end

function MSF.getCutUpBeltRecipe()
    return MSF.getCraftRecipe("CutUpBelt")
end

function MSF.getRipClothingRecipe()
    return MSF.getCraftRecipe("RipClothing")
end

function MSF.getRipDenimClothingRecipe()
    return MSF.getCraftRecipe("RipDenimClothing")
end

function MSF.collectBeltItems(containers)
    return MSF.collectEligibleItems(containers, function(item)
        return MSF.isBeltScrapItem(item) and MSF.isBatchEligible(item)
    end)
end

function MSF.collectRipClothingItems(containers)
    return MSF.collectEligibleItems(containers, function(item)
        return MSF.getClothingRipRecipeName(item) ~= nil and MSF.isBatchEligible(item)
    end)
end

function MSF.collectRipClothingItemsOfType(containers, fullType)
    if not fullType then return {} end
    local wanted = tostring(fullType)
    return MSF.collectEligibleItems(containers, function(item)
        return item:getFullType() == wanted
            and MSF.getClothingRipRecipeName(item) ~= nil
            and MSF.isBatchEligible(item)
    end)
end

function MSF.isWashableItem(item)
    if not item then return false end
    local okHidden, hidden = pcall(function() return item:isHidden() end)
    if not okHidden or hidden then return false end
    if MSF.itemHasTag(item, ItemTag.BREAK_WHEN_WET) then return false end
    if MSF.itemHasTag(item, ItemTag.CAN_BE_WASHED) then
        local okDelta, delta = pcall(function() return item:getJobDelta() end)
        return okDelta and delta == 0
    end
    local okBlood, blood = pcall(function() return item:hasBlood() end)
    local okDirt, dirt = pcall(function() return item:hasDirt() end)
    if MSF.isClothing(item) then
        return (okBlood and blood == true) or (okDirt and dirt == true)
    end
    local okCategory, category = pcall(function() return item:getCategory() end)
    if okCategory and category == "Weapon" then
        return okBlood and blood == true
    end
    if okCategory and category == "Container" then
        return (okBlood and blood == true) or (okDirt and dirt == true)
    end
    return false
end

function MSF.collectWashableItems(containers)
    return MSF.collectEligibleItems(containers, MSF.isWashableItem)
end

-- The native menu also gathers sources while fetching objects on the clicked
-- square. Those sources are not necessarily present in the raw click list.
function MSF.findWashWaterSource(player, worldobjects, fetch)
    if not player then return nil end
    fetch = fetch or {}
    local lists = { { worldobjects, "clicked" }, { fetch.storeWater, "storeWater" },
        { fetch.fluidcontainer, "fluidcontainer" } }
    local okBuilding, building = pcall(function() return player:getBuilding() end)
    if not okBuilding then return nil end
    for _, entry in ipairs(lists) do
        for _, object in pairs(entry[1] or {}) do
            if object and object ~= fetch.clothingWasher and object ~= fetch.comboWasherDryer
                and object ~= fetch.clothingDryer then
                local okWater, hasWater = pcall(function() return object:hasWater() end)
                if okWater and hasWater then
                    local okSquare, square = pcall(function() return object:getSquare() end)
                    if okSquare and square then
                        local okSourceBuilding, sourceBuilding = pcall(function() return square:getBuilding() end)
                        if okSourceBuilding and sourceBuilding == building then return object, entry[2] end
                    end
                end
            end
        end
    end
    return nil
end

MSF.maskSources = MSF.maskSources or {}

function MSF.isProtectiveMaskItem(item)
    if not item then return false end
    local okClothing, isClothing = pcall(function() return instanceof(item, "Clothing") end)
    if not okClothing or not isClothing then return false end
    local okBroken, broken = pcall(function() return item:isBroken() end)
    if okBroken and broken then return false end
    local okLocation, location = pcall(function() return item:getBodyLocation() end)
    if not okLocation or location == nil then return false end
    local okDefense, defense = pcall(function() return item:getCorpseSicknessDefense() end)
    return okDefense and defense ~= nil and defense > 0
end

function MSF.isEffectiveFilterMask(item)
    if not MSF.isProtectiveMaskItem(item) then return false end
    local okFilter, hasFilter = pcall(function() return item:hasFilter() end)
    if not okFilter or hasFilter ~= true then return false end
    local okDelta, delta = pcall(function() return item:getUsedDelta() end)
    return okDelta and delta ~= nil and delta > 0
end

function MSF.getMaskFilterLife(item)
    local ok, delta = pcall(function() return item:getUsedDelta() end)
    if ok and delta ~= nil then return delta end
    return 0
end

function MSF.getMaskDefense(item)
    local ok, defense = pcall(function() return item:getCorpseSicknessDefense() end)
    if ok and defense ~= nil then return defense end
    return 0
end

function MSF.collectMaskCandidates(containers)
    return MSF.collectEligibleItems(containers, function(item)
        if not MSF.isProtectiveMaskItem(item) then return false end
        local okWorn, worn = pcall(function() return item:isWorn() end)
        return okWorn and worn ~= true
    end)
end

function MSF.getWornProtectiveMasks(player)
    local result = {}
    if not player then return result end
    local wornItems = player:getWornItems()
    if not wornItems then return result end
    for i = 0, wornItems:size() - 1 do
        local ok, item = pcall(function() return wornItems:getItemByIndex(i) end)
        if ok and MSF.isProtectiveMaskItem(item) then
            table.insert(result, item)
        end
    end
    return result
end

function MSF.chooseMask(onPersonCandidates, nearbyCandidates)
    local candidates = {}
    local seen = {}
    local function addCandidates(list, onPerson)
        for _, item in ipairs(list or {}) do
            if item and MSF.isProtectiveMaskItem(item) then
                local okId, id = pcall(function() return item:getID() end)
                if not okId then id = nil end
                if id == nil or not seen[id] then
                    if id ~= nil then seen[id] = true end
                    table.insert(candidates, { item = item, onPerson = onPerson })
                end
            end
        end
    end
    addCandidates(onPersonCandidates, true)
    addCandidates(nearbyCandidates, false)
    if #candidates == 0 then return nil end

    local favorites = {}
    for _, candidate in ipairs(candidates) do
        local okFavorite, favorite = pcall(function() return candidate.item:isFavorite() end)
        if okFavorite and favorite then table.insert(favorites, candidate) end
    end
    local pool = #favorites > 0 and favorites or candidates

    local filters = {}
    for _, candidate in ipairs(pool) do
        if MSF.isEffectiveFilterMask(candidate.item) then
            table.insert(filters, candidate)
        end
    end

    if #filters > 0 then
        local best = filters[1]
        for i = 2, #filters do
            local candidate = filters[i]
            local candidateLife = MSF.getMaskFilterLife(candidate.item)
            local bestLife = MSF.getMaskFilterLife(best.item)
            if candidateLife < bestLife - 0.0001 then
                best = candidate
            elseif math.abs(candidateLife - bestLife) <= 0.0001 then
                if candidate.onPerson and not best.onPerson then
                    best = candidate
                elseif candidate.onPerson == best.onPerson then
                    if MSF.getMaskDefense(candidate.item) > MSF.getMaskDefense(best.item) then
                        best = candidate
                    end
                end
            end
        end
        return best.item
    end

    local onPersonPool = {}
    for _, candidate in ipairs(pool) do
        if candidate.onPerson then table.insert(onPersonPool, candidate) end
    end
    local randomPool = #onPersonPool > 0 and onPersonPool or pool
    local index = 1
    if ZombRand then index = ZombRand(#randomPool) + 1 end
    return randomPool[index].item
end

function MSF.rememberMaskSource(item, mainInventory)
    if not item then return end
    local okId, id = pcall(function() return item:getID() end)
    if not okId or id == nil then return end
    local okContainer, container = pcall(function() return item:getContainer() end)
    if okContainer and container and container ~= mainInventory then
        MSF.maskSources[id] = container
    else
        MSF.maskSources[id] = nil
    end
end

function MSF.getMaskSource(item)
    if not item then return nil end
    local okId, id = pcall(function() return item:getID() end)
    if not okId or id == nil then return nil end
    return MSF.maskSources[id]
end

function MSF.clearMaskSource(item)
    if not item then return end
    local okId, id = pcall(function() return item:getID() end)
    if okId and id ~= nil then
        MSF.maskSources[id] = nil
    end
end

function MSF.getFluidContainerHost(item, worldObject)
    if not item then return nil end
    local ok, fluid = pcall(function() return item:getFluidContainer() end)
    if ok and fluid then return fluid end

    if worldObject then
        local okWorld, worldFluid = pcall(function() return worldObject:getFluidContainer() end)
        if okWorld and worldFluid then return worldFluid end
    end

    local okSelf, selfFluid = pcall(function() return item:getFluidContainerFromSelfOrWorldItem() end)
    if okSelf and selfFluid then return selfFluid end

    local okLink, worldItem = pcall(function() return item:getWorldItem() end)
    if okLink and worldItem then
        local okItemWorld, itemWorldFluid = pcall(function() return worldItem:getFluidContainer() end)
        if okItemWorld and itemWorldFluid then return itemWorldFluid end
    end
    return nil
end

function MSF.getFuelAmount(item, worldObject)
    local fluid = MSF.getFluidContainerHost(item, worldObject)
    if not fluid then return 0 end
    local okAmount, amount = pcall(function() return fluid:getAmount() end)
    if okAmount and amount ~= nil then return amount end
    return 0
end

function MSF.isFuelContainer(item, worldObject)
    if not item then return false end
    local fluid = MSF.getFluidContainerHost(item, worldObject)
    if not fluid then return false end
    local okAmount, amount = pcall(function() return fluid:getAmount() end)
    if not okAmount or amount == nil or amount <= 0.0001 then return false end

    local okWater, hasWater = pcall(function() return fluid:contains(Fluid.Water) end)
    if okWater and hasWater then return false end

    local okTag, hasPetrolTag = pcall(function() return item:hasTag(ItemTag.PETROL) end)
    if okTag and hasPetrolTag then return true end

    local okContains, contains = pcall(function() return fluid:contains(Fluid.Petrol) end)
    if okContains and contains == true then return true end

    local okPrimary, primary = pcall(function() return fluid:getPrimaryFluid() end)
    if okPrimary and primary then
        local okName, fluidName = pcall(function() return primary:getFluidTypeString() end)
        if okName and fluidName then
            local name = string.lower(tostring(fluidName))
            if string.find(name, "petrol", 1, true)
                or string.find(name, "gasoline", 1, true)
                or string.find(name, "fuel", 1, true) then
                return true
            end
        end
    end

    local okType, fullType = pcall(function() return item:getFullType() end)
    local okDisplay, displayName = pcall(function() return item:getDisplayName() end)
    local itemName = string.lower(tostring(fullType or "") .. " " .. tostring(displayName or ""))
    return string.find(itemName, "petrol", 1, true) ~= nil
        or string.find(itemName, "gasoline", 1, true) ~= nil
        or string.find(itemName, "jerry", 1, true) ~= nil
        or string.find(itemName, "gascan", 1, true) ~= nil
        or string.find(itemName, "gas_can", 1, true) ~= nil
        or string.find(itemName, "fuelcan", 1, true) ~= nil
        or string.find(itemName, "fuel_can", 1, true) ~= nil
        or string.find(itemName, "汽油", 1, true) ~= nil
        or string.find(itemName, "燃油", 1, true) ~= nil
end

function MSF.collectFuelCandidatesFromContainers(containers)
    local result = {}
    local seen = {}
    for _, container in ipairs(containers or {}) do
        if container then
            local ok, items = pcall(function()
                return container:getAllEvalRecurse(MSF.isFuelContainer, ArrayList.new())
            end)
            if ok and items then
                for i = 1, items:size() do
                    local item = items:get(i - 1)
                    local okId, id = pcall(function() return item:getID() end)
                    if okId and id ~= nil and not seen[id] then
                        seen[id] = true
                        local okSource, source = pcall(function() return item:getContainer() end)
                        table.insert(result, {
                            item = item,
                            source = (okSource and source) or container,
                            amount = MSF.getFuelAmount(item),
                        })
                    end
                end
            end
        end
    end
    return result
end

function MSF.sortFuelCandidates(candidates)
    table.sort(candidates, function(a, b)
        local amountA = a.amount or 0
        local amountB = b.amount or 0
        if math.abs(amountA - amountB) > 0.0001 then
            return amountA < amountB
        end
        local okA, idA = pcall(function() return a.item:getID() end)
        local okB, idB = pcall(function() return b.item:getID() end)
        return (okA and idA or 0) < (okB and idB or 0)
    end)
    return candidates
end

function MSF.buildFuelPlan(currentFuel, maxFuel, candidates)
    local plan = {}
    local needed = (maxFuel or 0) - (currentFuel or 0)
    if needed <= 0.0001 then return plan end

    local sorted = {}
    for _, candidate in ipairs(candidates or {}) do
        table.insert(sorted, candidate)
    end
    MSF.sortFuelCandidates(sorted)

    for _, candidate in ipairs(sorted) do
        if needed <= 0.0001 then break end
        local amount = candidate.amount or 0
        if amount > 0.0001 then
            table.insert(plan, candidate)
            needed = needed - math.min(amount, needed)
        end
    end
    return plan
end
