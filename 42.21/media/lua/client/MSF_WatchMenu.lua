require "ISUI/ISInventoryPaneContextMenu"
require "ISUI/ISInventoryPane"

if MSF.watchMenuInstalled then return end
MSF.watchMenuInstalled = true

local function gatherContainers(playerObj)
    local scanContainers = { playerObj:getInventory() }
    local nearby = ISInventoryPaneContextMenu.getContainers(playerObj) or ArrayList.new()
    for i = 1, nearby:size() do
        local container = nearby:get(i - 1)
        if container then
            table.insert(scanContainers, container)
        end
    end
    return scanContainers, nearby
end

local function collectTargets(playerObj, recipe)
    local scanContainers, nearby = gatherContainers(playerObj)
    local candidates = MSF.collectDigitalWristWatches(scanContainers)
    local valid = {}
    for _, item in ipairs(candidates) do
        local ok, canPerform = pcall(function()
            local logic = HandcraftLogic.new(playerObj, nil, nil)
            logic:setContainers(nearby)
            logic:setRecipeFromContextClick(recipe, item)
            return logic:canPerformCurrentRecipe()
        end)
        if ok and canPerform then
            table.insert(valid, item)
        end
    end
    return candidates, valid
end

function MSF.onDismantleAllWatches(playerObj, playerNum, recipe)
    if not playerObj or not recipe then return end
    if playerObj:isDead() or playerObj:isDriving() then return end
    local _, valid = collectTargets(playerObj, recipe)
    for _, watch in ipairs(valid) do
        ISInventoryPaneContextMenu.OnNewCraft(watch, recipe, playerNum, false)
    end
end

local function addOptionAfterDismantle(context, recipe, label, playerObj, playerNum)
    local recipeName = getText(recipe:getTranslationName())
    if context:getOptionFromName(recipeName) then
        return context:insertOptionAfter(recipeName, label, playerObj, MSF.onDismantleAllWatches, playerNum, recipe)
    end
    if context.options then
        for _, option in ipairs(context.options) do
            if option.subOption then
                local subMenu = context:getSubMenu(option.subOption)
                if subMenu and subMenu:getOptionFromName(recipeName) then
                    return subMenu:insertOptionAfter(recipeName, label, playerObj, MSF.onDismantleAllWatches, playerNum, recipe)
                end
            end
        end
    end
    return context:addOption(label, playerObj, MSF.onDismantleAllWatches, playerNum, recipe)
end

local function onFillInventoryObjectContextMenu(playerNum, context, items)
    local playerObj = getSpecificPlayer(playerNum)
    if not playerObj then return end

    local actualItems = ISInventoryPane.getActualItems(items)
    local clickedWatch = nil
    for _, item in ipairs(actualItems) do
        if MSF.isWristWatch(item) then
            clickedWatch = item
            break
        end
    end
    if not clickedWatch then return end

    local recipe = MSF.getDismantleWatchesRecipe()
    if not recipe then return end

    local candidates, valid = collectTargets(playerObj, recipe)
    if #candidates == 0 then return end

    local count = #valid
    local labelCount = count > 0 and count or #candidates
    local label = getText("ContextMenu_MSF_DismantleAllWatches", labelCount)
    local option = addOptionAfterDismantle(context, recipe, label, playerObj, playerNum)

    local tooltip = ISInventoryPaneContextMenu.addToolTip()
    if playerObj:isDriving() then
        option.notAvailable = true
        tooltip.description = getText("ContextMenu_MSF_DismantleAllWatches_Driving")
    elseif count == 0 then
        option.notAvailable = true
        tooltip.description = getText("ContextMenu_MSF_DismantleAllWatches_Unavailable")
    else
        tooltip.description = getText("ContextMenu_MSF_DismantleAllWatches_tt", count)
        if count < #candidates then
            tooltip.description = tooltip.description .. " <LINE> " .. getText("ContextMenu_MSF_DismantleAllWatches_Skip")
        end
    end
    option.toolTip = tooltip
end

Events.OnFillInventoryObjectContextMenu.Add(onFillInventoryObjectContextMenu)

function MSF.uninstallWatchMenu()
    Events.OnFillInventoryObjectContextMenu.Remove(onFillInventoryObjectContextMenu)
    MSF.watchMenuInstalled = false
end
