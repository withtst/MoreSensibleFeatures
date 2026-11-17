if MSF.worldMenuHookInitialized then return end
MSF.worldMenuHookInitialized = true
MSF.worldMenuPostFillCallbacks = MSF.worldMenuPostFillCallbacks or {}

local function installWorldMenuHook()
    if MSF._worldMenuHookWrapper then return true end
    if not ISWorldObjectContextMenu or type(ISWorldObjectContextMenu.createMenu) ~= "function" then
        return false
    end

    local original = ISWorldObjectContextMenu.createMenu
    local wrapper
    wrapper = function(playerNum, worldobjects, x, y, test)
        local result = original(playerNum, worldobjects, x, y, test)
        if test or not result then return result end

        -- Match the legacy event's safehouse permission gate.
        local fetch = ISWorldObjectContextMenu.fetchVars
        if not fetch or not fetch.safehouseAllowInteract then
            if not MSF._worldMenuPermissionLogged then
                print("MSF|WORLD_MENU|permission_gate")
                MSF._worldMenuPermissionLogged = true
            end
            return result
        end

        local context = nil
        if type(result) == "table" and result.options then
            context = result
        end
        if not context then
            local ok, activeContext = pcall(function() return getPlayerContextMenu(playerNum) end)
            if ok then context = activeContext end
        end
        if not context then
            if not MSF._worldMenuMissingContextLogged then
                print("MSF|WORLD_MENU|no_context")
                MSF._worldMenuMissingContextLogged = true
            end
            return result
        end

        local keys = {}
        for key in pairs(MSF.worldMenuPostFillCallbacks) do
            table.insert(keys, key)
        end
        table.sort(keys)
        for _, key in ipairs(keys) do
            local callback = MSF.worldMenuPostFillCallbacks[key]
            if callback then
                local ok, err = pcall(callback, playerNum, context, worldobjects, test)
                if not ok then
                    print("MSF|WORLD_MENU|callback=" .. tostring(key) .. "|error=" .. tostring(err))
                end
            end
        end
        return result
    end

    MSF._worldMenuOriginalCreateMenu = original
    MSF._worldMenuHookWrapper = wrapper
    ISWorldObjectContextMenu.createMenu = wrapper
    return true
end

function MSF.registerWorldMenuPostFill(key, callback)
    if type(key) ~= "string" or type(callback) ~= "function" then return false end
    MSF.worldMenuPostFillCallbacks[key] = callback
    return installWorldMenuHook()
end

function MSF.unregisterWorldMenuPostFill(key)
    MSF.worldMenuPostFillCallbacks[key] = nil
    for _ in pairs(MSF.worldMenuPostFillCallbacks) do return end

    if ISWorldObjectContextMenu
        and ISWorldObjectContextMenu.createMenu == MSF._worldMenuHookWrapper
        and MSF._worldMenuOriginalCreateMenu then
        ISWorldObjectContextMenu.createMenu = MSF._worldMenuOriginalCreateMenu
    end
    MSF._worldMenuOriginalCreateMenu = nil
    MSF._worldMenuHookWrapper = nil
end

function MSF.uninstallWorldMenuHook()
    if ISWorldObjectContextMenu
        and ISWorldObjectContextMenu.createMenu == MSF._worldMenuHookWrapper
        and MSF._worldMenuOriginalCreateMenu then
        ISWorldObjectContextMenu.createMenu = MSF._worldMenuOriginalCreateMenu
    end
    for key in pairs(MSF.worldMenuPostFillCallbacks) do
        MSF.worldMenuPostFillCallbacks[key] = nil
    end
    MSF._worldMenuOriginalCreateMenu = nil
    MSF._worldMenuHookWrapper = nil
end
