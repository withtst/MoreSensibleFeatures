require "ISUI/ISInventoryPaneContextMenu"
require "TimedActions/ISWearClothing"
require "TimedActions/ISUnequipAction"
require "TimedActions/ISInventoryTransferUtil"

if MSF.maskClientInstalled then return end
MSF.maskClientInstalled = true

local MASK_BIND_ID = MSF.MASK_BIND_ID
local MASK_RETURN_BIND_ID = MSF.MASK_RETURN_BIND_ID
local BIND_SECTION = MSF.BIND_SECTION

local function ensureKeyBindingTable()
    if type(keyBinding) ~= "table" then return end
    local hasSection = false
    local hasMask = false
    local hasMaskReturn = false

    for i = 1, #keyBinding do
        local entry = keyBinding[i]
        if entry.value == BIND_SECTION then hasSection = true end
        if entry.value == MASK_BIND_ID then hasMask = true end
        if entry.value == MASK_RETURN_BIND_ID then hasMaskReturn = true end
        if entry.value == "Display FPS" then
            if entry.key == Keyboard.KEY_K then
                MSF._maskFpsBindingEntry = entry
                MSF._maskFpsBindingOldKey = entry.key
                entry.key = 0
            end
        end
    end

    if not hasSection then
        table.insert(keyBinding, { value = BIND_SECTION })
    end
    if not hasMask then
        table.insert(keyBinding, { value = MASK_BIND_ID, key = Keyboard.KEY_K })
    end
    if not hasMaskReturn then
        table.insert(keyBinding, { value = MASK_RETURN_BIND_ID, key = Keyboard.KEY_K, ctrl = true })
    end

    local okFps, fpsKey = pcall(function() return getCore():getKey("Display FPS") end)
    MSF._maskFpsCoreOldKey = okFps and fpsKey or nil
    if okFps and fpsKey == Keyboard.KEY_K then
        pcall(function() getCore():addKeyBinding("Display FPS", 0, 0, false, false, false) end)
        MSF._maskFpsFreed = true
    end
end

local function ensureCoreBinding(id, ctrl)
    local ok, current = pcall(function() return getCore():getKey(id) end)
    if not ok or not current or current == 0 then
        getCore():addKeyBinding(id, Keyboard.KEY_K, 0, false, ctrl, false)
    end
end

ensureKeyBindingTable()
ensureCoreBinding(MASK_BIND_ID, false)
ensureCoreBinding(MASK_RETURN_BIND_ID, true)

function MSF.isMaskToggleEvent(key)
    if key == nil or key == 0 then return false end
    local ok, result = pcall(function() return getCore():isKey(MASK_BIND_ID, key) end)
    return ok and result == true
end

function MSF.isMaskReturnEvent(key)
    if key == nil or key == 0 then return false end
    local ok, result = pcall(function() return getCore():isKey(MASK_RETURN_BIND_ID, key) end)
    return ok and result == true
end

local function collectOnPersonMasks(player)
    local playerInv = player:getInventory()
    local containers = { playerInv }
    local wornItems = player:getWornItems()
    if wornItems then
        for i = 0, wornItems:size() - 1 do
            local ok, item = pcall(function() return wornItems:getItemByIndex(i) end)
            if ok and item and instanceof(item, "InventoryContainer") then
                local inventory = item:getInventory()
                if inventory then table.insert(containers, inventory) end
            end
        end
    end
    return MSF.collectMaskCandidates(containers)
end

local function collectNearbyMasks(player)
    local nearby = ISInventoryPaneContextMenu.getContainers(player) or ArrayList.new()
    local containers = {}
    for i = 1, nearby:size() do
        local container = nearby:get(i - 1)
        if container then table.insert(containers, container) end
    end
    return MSF.collectMaskCandidates(containers)
end

local function removeWornMasks(player, returnToSource)
    local worn = MSF.getWornProtectiveMasks(player)
    if #worn == 0 then return false end
    local playerInv = player:getInventory()
    for _, item in ipairs(worn) do
        local source = returnToSource and MSF.getMaskSource(item) or nil
        ISTimedActionQueue.add(ISUnequipAction:new(player, item, 50))
        if source and source ~= playerInv then
            ISTimedActionQueue.add(ISInventoryTransferUtil.newInventoryTransferAction(player, item, playerInv, source))
        end
        MSF.clearMaskSource(item)
    end
    return true
end

local function showNoMaskText(player)
    if HaloTextHelper and HaloTextHelper.addText then
        HaloTextHelper.addText(player, getText("MSF_Mask_NoMask"), "", 255, 255, 0)
    end
end

local function wearMask(player, target)
    MSF.rememberMaskSource(target, player:getInventory())
    ISInventoryPaneContextMenu.wearItem(target, player:getPlayerNum())
end

local function onKeyStartPressed(key)
    local isReturn = MSF.isMaskReturnEvent(key)
    local isToggle = MSF.isMaskToggleEvent(key)
    if not isReturn and not isToggle then return end

    local player = getSpecificPlayer(0)
    if not player or player:isDead() or isGamePaused() then return end

    if isReturn then
        removeWornMasks(player, true)
        return
    end

    if removeWornMasks(player, false) then return end

    local onPerson = collectOnPersonMasks(player)
    local nearby = collectNearbyMasks(player)
    local target = MSF.chooseMask(onPerson, nearby)
    if not target then
        showNoMaskText(player)
        return
    end
    wearMask(player, target)
end

Events.OnKeyStartPressed.Add(onKeyStartPressed)

local originalFpsKeyPressed = ISFPS and ISFPS.onKeyPressed
MSF._maskOriginalFpsKeyPressed = originalFpsKeyPressed
if originalFpsKeyPressed then
    local fpsWrapper = function(key)
        if key == Keyboard.KEY_K then return end
        return originalFpsKeyPressed(key)
    end
    pcall(function() Events.OnKeyPressed.Remove(originalFpsKeyPressed) end)
    Events.OnKeyPressed.Add(fpsWrapper)
    ISFPS.onKeyPressed = fpsWrapper
    MSF._maskFpsWrapper = fpsWrapper
end

function MSF.uninstallMaskClient()
    Events.OnKeyStartPressed.Remove(onKeyStartPressed)
    if MSF._maskFpsWrapper then
        Events.OnKeyPressed.Remove(MSF._maskFpsWrapper)
        MSF._maskFpsWrapper = nil
    end
    if MSF._maskOriginalFpsKeyPressed then
        ISFPS.onKeyPressed = MSF._maskOriginalFpsKeyPressed
        Events.OnKeyPressed.Add(MSF._maskOriginalFpsKeyPressed)
    end
    if MSF._maskFpsBindingEntry and MSF._maskFpsBindingOldKey then
        MSF._maskFpsBindingEntry.key = MSF._maskFpsBindingOldKey
    end
    if MSF._maskFpsFreed and MSF._maskFpsCoreOldKey then
        pcall(function()
            getCore():addKeyBinding("Display FPS", MSF._maskFpsCoreOldKey, 0, false, false, false)
        end)
    end
    if type(keyBinding) == "table" then
        for i = #keyBinding, 1, -1 do
            local value = keyBinding[i].value
            if value == MASK_BIND_ID or value == MASK_RETURN_BIND_ID then
                table.remove(keyBinding, i)
            end
        end
    end
    pcall(function() getCore():addKeyBinding(MASK_BIND_ID, 0, 0, false, false, false) end)
    pcall(function() getCore():addKeyBinding(MASK_RETURN_BIND_ID, 0, 0, false, false, false) end)
    MSF.maskClientInstalled = false
end
