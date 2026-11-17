require "ISUI/ISInventoryPaneContextMenu"
require "ISUI/ISInventoryPane"

if MSF.batchMenuInstalled then return end
MSF.batchMenuInstalled = true

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

local function collectValidTasks(playerObj, nearby, candidates, recipeForItem)
    local valid = {}
    for _, item in ipairs(candidates) do
        local recipe = recipeForItem(item)
        if recipe then
            local ok, canPerform = pcall(function()
                local logic = HandcraftLogic.new(playerObj, nil, nil)
                logic:setContainers(nearby)
                logic:setRecipeFromContextClick(recipe, item)
                return logic:canPerformCurrentRecipe()
            end)
            if ok and canPerform then
                table.insert(valid, { item = item, recipe = recipe })
            end
        end
    end
    return valid
end

local function runTasks(tasks, playerNum)
    for _, task in ipairs(tasks) do
        ISInventoryPaneContextMenu.OnNewCraft(task.item, task.recipe, playerNum, false)
    end
end

local function findRecipeMenu(context, recipe)
    local recipeName = getText(recipe:getTranslationName())
    if context:getOptionFromName(recipeName) then
        return context
    end
    if context.options then
        for _, option in ipairs(context.options) do
            if option.subOption then
                local subMenu = context:getSubMenu(option.subOption)
                if subMenu and subMenu:getOptionFromName(recipeName) then
                    return subMenu
                end
            end
        end
    end
    return nil
end

local function insertAfterRecipe(context, recipe, label, playerObj, playerNum, handler)
    local recipeName = getText(recipe:getTranslationName())
    local menu = findRecipeMenu(context, recipe)
    if menu then
        return menu:insertOptionAfter(recipeName, label, playerObj, handler, playerNum)
    end
    return context:addOption(label, playerObj, handler, playerNum)
end

local function addBatchTooltip(option, playerObj, validCount, candidateCount, tooltipKey, unavailableKey)
    local tooltip = ISInventoryPaneContextMenu.addToolTip()
    if playerObj:isDriving() then
        option.notAvailable = true
        tooltip.description = getText("ContextMenu_MSF_Batch_Driving")
    elseif validCount == 0 then
        option.notAvailable = true
        tooltip.description = getText(unavailableKey)
    else
        tooltip.description = getText(tooltipKey, validCount)
        if validCount < candidateCount then
            tooltip.description = tooltip.description .. " <LINE> " .. getText("ContextMenu_MSF_Batch_Skip")
        end
    end
    option.toolTip = tooltip
end

local function addRipSameTooltip(option, playerObj, validCount, candidateCount, itemName)
    local tooltip = ISInventoryPaneContextMenu.addToolTip()
    if playerObj:isDriving() then
        option.notAvailable = true
        tooltip.description = getText("ContextMenu_MSF_Batch_Driving")
    elseif validCount == 0 then
        option.notAvailable = true
        tooltip.description = getText("ContextMenu_MSF_RipSameClothing_Unavailable", itemName)
    else
        tooltip.description = getText("ContextMenu_MSF_RipSameClothing_tt", itemName, validCount)
        if validCount < candidateCount then
            tooltip.description = tooltip.description .. " <LINE> " .. getText("ContextMenu_MSF_Batch_Skip")
        end
    end
    option.toolTip = tooltip
end

function MSF.onCutAllBelts(playerObj, playerNum)
    if not playerObj or playerObj:isDead() or playerObj:isDriving() then return end
    local recipe = MSF.getCutUpBeltRecipe()
    if not recipe then return end
    local scanContainers, nearby = gatherContainers(playerObj)
    local candidates = MSF.collectBeltItems(scanContainers)
    local valid = collectValidTasks(playerObj, nearby, candidates, function() return recipe end)
    runTasks(valid, playerNum)
end

function MSF.onRipAllClothing(playerObj, playerNum)
    if not playerObj or playerObj:isDead() or playerObj:isDriving() then return end
    local ripRecipe = MSF.getRipClothingRecipe()
    local cutRecipe = MSF.getRipDenimClothingRecipe()
    if not ripRecipe and not cutRecipe then return end
    local scanContainers, nearby = gatherContainers(playerObj)
    local candidates = MSF.collectRipClothingItems(scanContainers)
    local valid = collectValidTasks(playerObj, nearby, candidates, function(item)
        local name = MSF.getClothingRipRecipeName(item)
        if name == "RipClothing" then return ripRecipe end
        if name == "RipDenimClothing" then return cutRecipe end
        return nil
    end)
    runTasks(valid, playerNum)
end

function MSF.onRipSameClothing(playerObj, playerNum, fullType)
    if not playerObj or playerObj:isDead() or playerObj:isDriving() then return end
    if not fullType then return end
    local ripRecipe = MSF.getRipClothingRecipe()
    local cutRecipe = MSF.getRipDenimClothingRecipe()
    if not ripRecipe and not cutRecipe then return end
    local scanContainers, nearby = gatherContainers(playerObj)
    local candidates = MSF.collectRipClothingItemsOfType(scanContainers, fullType)
    local valid = collectValidTasks(playerObj, nearby, candidates, function(item)
        local name = MSF.getClothingRipRecipeName(item)
        if name == "RipClothing" then return ripRecipe end
        if name == "RipDenimClothing" then return cutRecipe end
        return nil
    end)
    runTasks(valid, playerNum)
end

local function onFillInventoryObjectContextMenu(playerNum, context, items)
    local playerObj = getSpecificPlayer(playerNum)
    if not playerObj then return end

    local actualItems = ISInventoryPane.getActualItems(items)
    local clickedBelt = nil
    local clickedClothing = nil
    for _, item in ipairs(actualItems) do
        if not clickedBelt and MSF.isBeltScrapItem(item) then clickedBelt = item end
        if not clickedClothing and MSF.getClothingRipRecipeName(item) then clickedClothing = item end
    end
    if not clickedBelt and not clickedClothing then return end

    local scanContainers, nearby = gatherContainers(playerObj)

    if clickedBelt then
        local recipe = MSF.getCutUpBeltRecipe()
        if recipe then
            local candidates = MSF.collectBeltItems(scanContainers)
            if #candidates > 0 then
                local valid = collectValidTasks(playerObj, nearby, candidates, function() return recipe end)
                local count = #valid
                local labelCount = count > 0 and count or #candidates
                local label = getText("ContextMenu_MSF_CutAllBelts", labelCount)
                local option = insertAfterRecipe(context, recipe, label, playerObj, playerNum, MSF.onCutAllBelts)
                addBatchTooltip(option, playerObj, count, #candidates, "ContextMenu_MSF_CutAllBelts_tt", "ContextMenu_MSF_CutAllBelts_Unavailable")
            end
        end
    end

    if clickedClothing then
        local anchorRecipeName = MSF.getClothingRipRecipeName(clickedClothing)
        local anchorRecipe = anchorRecipeName and MSF.getCraftRecipe(anchorRecipeName)
        if anchorRecipe then
            local allCandidates = MSF.collectRipClothingItems(scanContainers)
            if #allCandidates > 0 then
                local ripRecipe = MSF.getRipClothingRecipe()
                local cutRecipe = MSF.getRipDenimClothingRecipe()
                local function recipeFor(item)
                    local name = MSF.getClothingRipRecipeName(item)
                    if name == "RipClothing" then return ripRecipe end
                    if name == "RipDenimClothing" then return cutRecipe end
                    return nil
                end

                local fullType = tostring(clickedClothing:getFullType())
                local itemName = clickedClothing:getName()
                local sameCandidates = MSF.collectRipClothingItemsOfType(scanContainers, fullType)
                local sameValid = {}
                if #sameCandidates > 0 then
                    sameValid = collectValidTasks(playerObj, nearby, sameCandidates, recipeFor)
                end
                local allValid = collectValidTasks(playerObj, nearby, allCandidates, recipeFor)

                local recipeName = getText(anchorRecipe:getTranslationName())
                local menu = findRecipeMenu(context, anchorRecipe) or context
                local anchor = recipeName

                if #sameCandidates > 0 then
                    local sameLabelCount = #sameValid > 0 and #sameValid or #sameCandidates
                    local sameLabel = getText("ContextMenu_MSF_RipSameClothing", itemName, sameLabelCount)
                    local sameOption = menu:insertOptionAfter(anchor, sameLabel, playerObj, MSF.onRipSameClothing, playerNum, fullType)
                    addRipSameTooltip(sameOption, playerObj, #sameValid, #sameCandidates, itemName)
                    anchor = sameLabel
                end

                local allCount = #allValid
                local allLabelCount = allCount > 0 and allCount or #allCandidates
                local allLabel = getText("ContextMenu_MSF_RipAllClothing", allLabelCount)
                local allOption = menu:insertOptionAfter(anchor, allLabel, playerObj, MSF.onRipAllClothing, playerNum)
                addBatchTooltip(allOption, playerObj, allCount, #allCandidates, "ContextMenu_MSF_RipAllClothing_tt", "ContextMenu_MSF_RipAllClothing_Unavailable")
            end
        end
    end
end

Events.OnFillInventoryObjectContextMenu.Add(onFillInventoryObjectContextMenu)

function MSF.uninstallBatchMenu()
    Events.OnFillInventoryObjectContextMenu.Remove(onFillInventoryObjectContextMenu)
    MSF.batchMenuInstalled = false
end
