require "ISUI/ISContextMenu"
require "ISUI/ISWorldObjectContextMenu"
require "TimedActions/ISWashClothing"
require "TimedActions/ISInventoryTransferUtil"
require "MSF_WorldMenuHook"

if MSF.washMenuInstalled then return end
MSF.washMenuInstalled = true

local function addBagInventories(container, list)
    if not container then return end
    local ok, bags = pcall(function()
        return container:getAllEvalRecurse(function(item)
            return instanceof(item, "InventoryContainer")
        end, ArrayList.new())
    end)
    if not ok or not bags then return end
    for i = 1, bags:size() do
        local bag = bags:get(i - 1)
        local inventory = bag:getInventory()
        if inventory then
            table.insert(list, inventory)
        end
    end
end

local function gatherContainers(playerObj)
    local playerInv = playerObj:getInventory()
    local scanContainers = { playerInv }
    addBagInventories(playerInv, scanContainers)

    local wornItems = playerObj:getWornItems()
    if wornItems then
        for i = 0, wornItems:size() - 1 do
            local ok, item = pcall(function() return wornItems:getItemByIndex(i) end)
            if ok and item and instanceof(item, "InventoryContainer") then
                local inventory = item:getInventory()
                if inventory then
                    table.insert(scanContainers, inventory)
                    addBagInventories(inventory, scanContainers)
                end
            end
        end
    end
    return scanContainers
end

local function collectCandidates(playerObj)
    local scanContainers = gatherContainers(playerObj)
    local items = MSF.collectWashableItems(scanContainers)
    local seen = {}
    for _, item in ipairs(items) do
        seen[item:getID()] = true
    end

    local wornItems = playerObj:getWornItems()
    if wornItems then
        for i = 0, wornItems:size() - 1 do
            local ok, item = pcall(function() return wornItems:getItemByIndex(i) end)
            if ok and item and not seen[item:getID()] and MSF.isWashableItem(item) then
                seen[item:getID()] = true
                table.insert(items, item)
            end
        end
    end

    return items, scanContainers
end

local function collectSoaps(scanContainers)
    local soaps = ArrayList.new()
    local seen = {}
    for _, container in ipairs(scanContainers) do
        local ok, list = pcall(function() return container:getSoapList(nil, true) end)
        if ok and list then
            for i = 0, list:size() - 1 do
                local soap = list:get(i)
                local id = soap:getID()
                if not seen[id] then
                    seen[id] = true
                    soaps:add(soap)
                end
            end
        end
    end
    return soaps
end

local function requiredWater(items)
    local total = 0
    for _, item in ipairs(items) do
        total = total + ISWashClothing.GetRequiredWater(item)
    end
    return total
end

local function waterAvailable(sink)
    local ok, amount = pcall(function() return sink:getFluidAmount() end)
    if ok and amount then return amount end
    return 0
end

local function washAmounts(item)
    local bloodAmount = 0
    local dirtAmount = 0
    if instanceof(item, "Clothing") or instanceof(item, "InventoryContainer") then
        local coveredParts = BloodClothingType.getCoveredParts(item:getBloodClothingType())
        if coveredParts then
            for j = 0, coveredParts:size() - 1 do
                local part = coveredParts:get(j)
                bloodAmount = bloodAmount + item:getBlood(part)
            end
        end
        if item:getDirtiness() > 0 then
            dirtAmount = dirtAmount + item:getDirtiness()
        end
    else
        bloodAmount = bloodAmount + item:getBloodLevel()
    end
    return bloodAmount, dirtAmount
end

local function snapshotItemIds(inventory, fullType)
    local ids = {}
    local items = inventory:getItems()
    for i = 0, items:size() - 1 do
        local item = items:get(i)
        if item:getFullType() == fullType then
            ids[item:getID()] = true
        end
    end
    return ids
end

local function findNewItem(inventory, fullType, oldIds)
    local items = inventory:getItems()
    for i = 0, items:size() - 1 do
        local item = items:get(i)
        if item:getFullType() == fullType and not oldIds[item:getID()] then
            return item
        end
    end
    return nil
end

local function queueWashBatch(playerObj, sink, items, soaps)
    local playerInv = playerObj:getInventory()
    local soapRemaining = ISWashClothing.GetSoapRemaining(soaps)

    for _, item in ipairs(items) do
        local container = item:getContainer()
        local outsideInventory = container ~= playerInv
        local cleaningResult = item:getItemAfterCleaning()
        local missingContainer = outsideInventory and (cleaningResult ~= nil or isClient()) and container == nil
        if not missingContainer then
            -- The MP authority uses vanilla isValid, which requires the item
            -- in the main inventory. Client-only action flags are not sent.
            local mustTransfer = outsideInventory and (cleaningResult ~= nil or isClient())
            if mustTransfer then
                ISTimedActionQueue.add(ISInventoryTransferUtil.newInventoryTransferAction(playerObj, item, container, playerInv))
            end

            local bloodAmount, dirtAmount = washAmounts(item)
            local noSoap = true
            local soapNeeded = ISWashClothing.GetRequiredSoap(item)
            if soapRemaining > 0 then
                noSoap = false
                soapRemaining = soapRemaining - math.min(soapRemaining, soapNeeded)
            end

            local action = ISWashClothing:new(playerObj, sink, item, bloodAmount, dirtAmount, noSoap)
            action.soaps = soaps
            if outsideInventory and not mustTransfer then
                action.msfWashInPlace = true
            end
            if mustTransfer then
                action.msfReturnContainer = container
                if cleaningResult ~= nil then action.msfReturnType = tostring(cleaningResult) end
            end
            ISTimedActionQueue.add(action)
            if mustTransfer and cleaningResult == nil and container then
                ISTimedActionQueue.add(ISInventoryTransferUtil.newInventoryTransferAction(playerObj, item, playerInv, container))
            end
        end
    end
end

function MSF.onWashItem(playerObj, playerNum, sink, item)
    if not playerObj or not sink or not item then return end
    if playerObj:isDead() or playerObj:isDriving() then return end
    if not MSF.isWashableItem(item) then return end
    if waterAvailable(sink) < ISWashClothing.GetRequiredWater(item) then return end
    if not luautils.walkAdjObject(playerObj, sink, true, true) then return end
    local soaps = collectSoaps(gatherContainers(playerObj))
    queueWashBatch(playerObj, sink, { item }, soaps)
end

function MSF.onWashAllCarried(playerObj, playerNum, sink)
    if not playerObj or not sink then return end
    if playerObj:isDead() or playerObj:isDriving() then return end

    local items, scanContainers = collectCandidates(playerObj)
    if #items == 0 then return end
    if waterAvailable(sink) < requiredWater(items) then return end

    local soaps = collectSoaps(scanContainers)
    if not luautils.walkAdjObject(playerObj, sink, true, true) then return end
    queueWashBatch(playerObj, sink, items, soaps)
end

local function findSinkSubMenu(context, sink)
    local name = nil
    -- getMoveableDisplayName is a local in ISWorldObjectContextMenu, not a global.
    local resolver = ISWorldObjectContextMenu and ISWorldObjectContextMenu.getMoveableDisplayName
    if resolver then
        local okName, moveableName = pcall(function() return resolver(sink) end)
        if okName and moveableName ~= nil then name = tostring(moveableName) end
    end
    if not name and instanceof(sink, "IsoWorldInventoryObject") then
        local okFluid, fluidName = pcall(function() return sink:getFluidUiName() end)
        if okFluid and fluidName ~= nil then name = tostring(fluidName) end
    end
    if not name then name = getText("ContextMenu_NaturalWaterSource") end
    local option = context:getOptionFromName(name)
    if option and option.subOption then
        return context:getSubMenu(option.subOption)
    end
    return nil
end

local function findAnyWashSubMenu(context)
    local washRoot = context:getOptionFromName(getText("ContextMenu_Wash"))
    if washRoot and washRoot.subOption then
        local existing = context:getSubMenu(washRoot.subOption)
        if existing then return existing end
    end
    if context.options then
        for _, option in ipairs(context.options) do
            if option.subOption then
                local parentMenu = context:getSubMenu(option.subOption)
                if parentMenu then
                    local wash = parentMenu:getOptionFromName(getText("ContextMenu_Wash"))
                    if wash and wash.subOption then
                        local washMenu = parentMenu:getSubMenu(wash.subOption)
                        if washMenu then return washMenu end
                    end
                end
            end
        end
    end
    return nil
end

local function getWashMenu(context, sink)
    local sinkMenu = findSinkSubMenu(context, sink)
    if sinkMenu then
        local wash = sinkMenu:getOptionFromName(getText("ContextMenu_Wash"))
        if wash and wash.subOption then
            local existing = sinkMenu:getSubMenu(wash.subOption)
            if existing then return existing end
        end
        local washRoot = sinkMenu:addOption(getText("ContextMenu_Wash"), nil, nil)
        local subMenu = ISContextMenu:getNew(sinkMenu)
        sinkMenu:addSubMenu(washRoot, subMenu)
        return subMenu
    end

    local existing = findAnyWashSubMenu(context)
    if existing then return existing end

    local washRoot = context:addOption(getText("ContextMenu_Wash"), nil, nil)
    local subMenu = ISContextMenu:getNew(context)
    context:addSubMenu(washRoot, subMenu)
    return subMenu
end

local function washDiagnostic(status, sourceKind, count, worldobjects, fetch)
    local okTime, now = pcall(function() return getTimestampMs() end)
    now = okTime and now or 0
    MSF._washDiagnosticLast = MSF._washDiagnosticLast or {}
    local key = status .. ":" .. tostring(sourceKind)
    local last = MSF._washDiagnosticLast[key]
    if last and now - last < 10000 then return end
    MSF._washDiagnosticLast[key] = now
    local function size(list)
        local n = 0
        for _ in pairs(list or {}) do n = n + 1 end
        return n
    end
    print("MSF|WASH|status=" .. status .. "|source=" .. tostring(sourceKind)
        .. "|items=" .. tostring(count) .. "|clicked=" .. size(worldobjects)
        .. "|storeWater=" .. size(fetch.storeWater) .. "|fluidcontainer=" .. size(fetch.fluidcontainer))
end

local function addWashItemOption(menu, playerObj, playerNum, sink, item)
    local required = ISWashClothing.GetRequiredWater(item)
    local option = menu:addOption(getText("ContextMenu_WashClothing", item:getName()), playerObj, MSF.onWashItem, playerNum, sink, item)
    local tooltip = ISWorldObjectContextMenu.addToolTip()
    tooltip.description = getText("ContextMenu_MSF_WashItem_tt", item:getName(), required)
    if waterAvailable(sink) < required then
        option.notAvailable = true
        tooltip.description = tooltip.description .. " <LINE> " .. getText("ContextMenu_MSF_WashNotEnoughWater", required, luautils.round(waterAvailable(sink), 2))
    end
    if playerObj:isDriving() then
        option.notAvailable = true
    end
    option.toolTip = tooltip
end

local function addWashOption(menu, playerObj, playerNum, sink, items, soaps)
    if #items == 0 then return end
    local waterRequired = requiredWater(items)
    local available = waterAvailable(sink)
    local option = menu:addOption(getText("ContextMenu_MSF_WashAllCarried", #items), playerObj, MSF.onWashAllCarried, playerNum, sink)
    local tooltip = ISWorldObjectContextMenu.addToolTip()
    tooltip.description = getText("ContextMenu_MSF_WashAllCarried_tt", #items, waterRequired)
    if available < waterRequired then
        option.notAvailable = true
        tooltip.description = tooltip.description .. " <LINE> " .. getText("ContextMenu_MSF_WashNotEnoughWater", waterRequired, luautils.round(available, 2))
    end
    if playerObj:isDriving() then
        option.notAvailable = true
    end
    if ISWashClothing.GetSoapRemaining(soaps) <= 0 then
        tooltip.description = tooltip.description .. " <LINE> " .. getText("ContextMenu_MSF_WashNoSoap")
    end
    option.toolTip = tooltip
end

local function onFillWorldObjectContextMenu(playerNum, context, worldobjects, test)
    if test then return end
    local playerObj = getSpecificPlayer(playerNum)
    if not playerObj then return end

    local fetch = ISWorldObjectContextMenu.fetchVars or {}
    local sink, sourceKind = MSF.findWashWaterSource(playerObj, worldobjects, fetch)
    if not sink then
        washDiagnostic("no_water_source", nil, 0, worldobjects, fetch)
        return
    end

    local allItems, scanContainers = collectCandidates(playerObj)
    if #allItems == 0 then
        washDiagnostic("no_washable_items", sourceKind, 0, worldobjects, fetch)
        return
    end

    local soaps = collectSoaps(scanContainers)
    local menu = getWashMenu(context, sink)
    local playerInv = playerObj:getInventory()

    for _, item in ipairs(allItems) do
        if item:getContainer() ~= playerInv then
            addWashItemOption(menu, playerObj, playerNum, sink, item)
        end
    end

    addWashOption(menu, playerObj, playerNum, sink, allItems, soaps)
    washDiagnostic("option_added", sourceKind, #allItems, worldobjects, fetch)
end

local originalWashIsValid = ISWashClothing.isValid
MSF._originalWashIsValid = originalWashIsValid
function ISWashClothing:isValid()
    if self.msfWashInPlace then
        if not self.item or not self.sink then return false end
        return waterAvailable(self.sink) >= ISWashClothing.GetRequiredWater(self.item)
    end
    return originalWashIsValid(self)
end

local originalWashComplete = ISWashClothing.complete
MSF._originalWashComplete = originalWashComplete
local originalWashStart = ISWashClothing.start
MSF._originalWashStart = originalWashStart
function ISWashClothing:start()
    -- In MP complete runs on the authority, while perform runs here after its
    -- acknowledgement. Capture the pre-replacement IDs on the client as well.
    if isClient() and self.msfReturnContainer and self.msfReturnType then
        self.msfReturnOldIds = snapshotItemIds(self.character:getInventory(), self.msfReturnType)
    end
    return originalWashStart(self)
end
function ISWashClothing:complete()
    if self.msfReturnContainer and self.msfReturnType and self.character then
        self.msfReturnOldIds = snapshotItemIds(self.character:getInventory(), self.msfReturnType)
    end
    local result = originalWashComplete(self)
    self.msfCompleted = true
    return result
end

local originalWashPerform = ISWashClothing.perform
MSF._originalWashPerform = originalWashPerform
function ISWashClothing:perform()
    local character = self.character
    local returnContainer = self.msfReturnContainer
    local returnType = self.msfReturnType
    local oldIds = self.msfReturnOldIds
    originalWashPerform(self)
    if character and returnContainer and returnType and oldIds then
        local playerInv = character:getInventory()
        local newItem = findNewItem(playerInv, returnType, oldIds)
        if newItem then
            pcall(function()
                ISTimedActionQueue.add(ISInventoryTransferUtil.newInventoryTransferAction(character, newItem, playerInv, returnContainer))
            end)
        end
    end
end

local originalWashStop = ISWashClothing.stop
MSF._originalWashStop = originalWashStop
function ISWashClothing:stop()
    local character = self.character
    local returnContainer = self.msfReturnContainer
    local item = self.item
    local alreadyCleaned = self.msfCompleted
    local pendingReturn = returnContainer and item
    local currentContainer = item and item:getContainer() or nil
    local result = originalWashStop(self)
    if not alreadyCleaned and pendingReturn and character and not character:isDead()
        and currentContainer and currentContainer ~= returnContainer then
        pcall(function()
            ISTimedActionQueue.add(ISInventoryTransferUtil.newInventoryTransferAction(character, item, currentContainer, returnContainer))
        end)
    end
    return result
end

-- Native world-menu handlers can return before OnFillWorldObjectContextMenu.
-- Inject after the original builder so the batch option can be added beside the
-- native Wash submenu while retaining the original safehouse permission gate.
Events.OnFillWorldObjectContextMenu.Remove(onFillWorldObjectContextMenu)
local washPostFillRegistered = MSF.registerWorldMenuPostFill("wash", onFillWorldObjectContextMenu)
print("MSF|WASH|installed|version=0.9.10|postfill=" .. tostring(washPostFillRegistered))
if not washPostFillRegistered then
    Events.OnFillWorldObjectContextMenu.Add(onFillWorldObjectContextMenu)
end

function MSF.uninstallWashMenu()
    Events.OnFillWorldObjectContextMenu.Remove(onFillWorldObjectContextMenu)
    MSF.unregisterWorldMenuPostFill("wash")
    if MSF._originalWashIsValid then
        ISWashClothing.isValid = MSF._originalWashIsValid
    end
    if MSF._originalWashComplete then
        ISWashClothing.complete = MSF._originalWashComplete
    end
    if MSF._originalWashStart then
        ISWashClothing.start = MSF._originalWashStart
    end
    if MSF._originalWashPerform then
        ISWashClothing.perform = MSF._originalWashPerform
    end
    if MSF._originalWashStop then
        ISWashClothing.stop = MSF._originalWashStop
    end
    MSF.washMenuInstalled = false
end
