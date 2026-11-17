require "ISUI/ISLightSourceRadialMenu"
require "TimedActions/ISEquipWeaponAction"
require "TimedActions/ISUnequipAction"
require "TimedActions/ISInventoryTransferUtil"
require "TimedActions/ISLitCandleExtinguish"
require "TimedActions/ISHurricaneLanternExtinguish"

if MSF.clientInstalled then return end
MSF.clientInstalled = true

local BIND_ID = MSF.BIND_ID
local BIND_SECTION = MSF.BIND_SECTION

local function ensureKeyBindingTable()
    if type(keyBinding) ~= "table" then return end
    local hasSection = false
    local hasBind = false
    for i = 1, #keyBinding do
        local value = keyBinding[i].value
        if value == BIND_SECTION then hasSection = true end
        if value == BIND_ID then hasBind = true end
    end
    if not hasSection then
        table.insert(keyBinding, { value = BIND_SECTION })
    end
    if not hasBind then
        table.insert(keyBinding, { value = BIND_ID, key = Keyboard.KEY_F, ctrl = true })
    end
end

local function ensureCoreBinding()
    local ok, current = pcall(function() return getCore():getKey(BIND_ID) end)
    if not ok or not current or current == 0 then
        getCore():addKeyBinding(BIND_ID, Keyboard.KEY_F, 0, false, true, false)
    end
end

ensureKeyBindingTable()
ensureCoreBinding()

local function ensureModOptions()
    if MSF.options then return end
    if not PZAPI or not PZAPI.ModOptions then return end
    local ok, options = pcall(function()
        local o = PZAPI.ModOptions:create(MSF.MOD_ID, "UI_MSF_ModName")
        o:addTitle("UI_MSF_OptionsTitle")
        o:addTickBox("autoReturn", "UI_MSF_AutoReturn", true, "UI_MSF_AutoReturn_tt")
        return o
    end)
    if ok then
        MSF.options = options
    end
end

ensureModOptions()

function MSF.isHotkeyEvent(key)
    if key == nil or key == 0 then return false end
    local ok, result = pcall(function() return getCore():isKey(BIND_ID, key) end)
    return ok and result == true
end

local function isAutoReturnEnabled()
    if MSF.options then
        local option = MSF.options:getOption("autoReturn")
        if option then
            local ok, value = pcall(function() return option:getValue() end)
            if ok then
                return value ~= false
            end
        end
    end
    return true
end

local function isContainerEligible(player, container)
    if not container or container == player:getInventory() then return false end
    local ok, result = pcall(function() return container:isInCharacterInventory(player) end)
    return ok and result == true
end

local function queueUnequipAndReturn(player, item, destContainer)
    if not item then return end
    ISTimedActionQueue.add(ISUnequipAction:new(player, item, 50))
    if destContainer and isContainerEligible(player, destContainer) then
        local src = item:getContainer() or player:getInventory()
        ISTimedActionQueue.add(ISInventoryTransferUtil.newInventoryTransferAction(player, item, src, destContainer))
    end
    MSF.clearOriginalContainer(item)
end

local function deactivateHeldLight(player, item)
    local okActivate, canBeActivated = pcall(function() return item:canBeActivated() end)
    if not okActivate or not canBeActivated then return end
    local okOn, activated = pcall(function() return item:isActivated() end)
    if okOn and activated then
        item:setActivated(false)
        syncItemActivated(player, item)
        item:playActivateDeactivateSound()
    end
end

local function queueExtinguish(player, target, destContainer)
    local item = target.item
    local kind = MSF.getLitKind(item)
    local expectedType = MSF.getExtinguishedType(item)
    if not kind or not expectedType then
        queueUnequipAndReturn(player, item, destContainer)
        return
    end

    if kind == "candle" then
        ISTimedActionQueue.add(ISLitCandleExtinguish:new(player, item))
    else
        ISTimedActionQueue.add(ISHurricaneLanternExtinguish:new(player, item))
    end

    local playerNum = player:getPlayerNum()
    MSF.pending[playerNum] = MSF.pending[playerNum] or {}
    table.insert(MSF.pending[playerNum], {
        hand = target.hand,
        originalId = item:getID(),
        expectedType = expectedType,
        destContainer = destContainer,
        expires = getTimestampMs() + 60000,
    })
    MSF.clearOriginalContainer(item)
end

local function onPlayerUpdate(player)
    if not player then return end
    local playerNum = player:getPlayerNum()
    local pending = MSF.pending[playerNum]
    if not pending or #pending == 0 then return end
    if player:isDead() then
        MSF.pending[playerNum] = nil
        return
    end

    local now = getTimestampMs()
    for i = #pending, 1, -1 do
        local record = pending[i]
        local handItem = nil
        if record.hand == "primary" then
            handItem = player:getPrimaryHandItem()
        else
            handItem = player:getSecondaryHandItem()
        end

        if handItem and handItem:getID() == record.originalId then
            if now >= record.expires then
                table.remove(pending, i)
            end
        elseif handItem and handItem:getFullType() == record.expectedType then
            table.remove(pending, i)
            queueUnequipAndReturn(player, handItem, record.destContainer)
        else
            table.remove(pending, i)
        end
    end

    if #pending == 0 then
        MSF.pending[playerNum] = nil
    end
end

local function onKeyStartPressed(key)
    if not MSF.isHotkeyEvent(key) then return end
    local player = getSpecificPlayer(0)
    if not player or player:isDead() or isGamePaused() then return end

    local targets = MSF.getEquippedLights(player)
    if #targets == 0 then return end

    local autoReturn = isAutoReturnEnabled()
    for _, target in ipairs(targets) do
        local item = target.item
        local destContainer = nil
        if autoReturn then
            destContainer = MSF.getOriginalContainer(item)
            if destContainer and not isContainerEligible(player, destContainer) then
                destContainer = nil
            end
        end

        if MSF.isEmitting(item) and not item:canBeActivated() then
            queueExtinguish(player, target, destContainer)
        else
            deactivateHeldLight(player, item)
            queueUnequipAndReturn(player, item, destContainer)
        end
    end
end

local function onGameStart()
    MSF.originalContainers = {}
    MSF.pending = {}
    if PZAPI and PZAPI.ModOptions then
        pcall(function() PZAPI.ModOptions:load() end)
    end
end

local originalCheckKey = ISLightSourceRadialMenu.checkKey
MSF._originalCheckKey = originalCheckKey
ISLightSourceRadialMenu.checkKey = function(key)
    if MSF.isHotkeyEvent(key) then return false end
    return originalCheckKey(key)
end

local originalEquipNew = ISEquipWeaponAction.new
MSF._originalEquipNew = originalEquipNew
function ISEquipWeaponAction:new(character, item, maxTimeInit, primary, twoHands, alwaysTurnOn)
    if character and item then
        MSF.rememberEquipSource(item, character:getInventory())
    end
    return originalEquipNew(self, character, item, maxTimeInit, primary, twoHands, alwaysTurnOn)
end

Events.OnKeyStartPressed.Add(onKeyStartPressed)
Events.OnPlayerUpdate.Add(onPlayerUpdate)
Events.OnGameStart.Add(onGameStart)

function MSF.uninstall()
    Events.OnKeyStartPressed.Remove(onKeyStartPressed)
    Events.OnPlayerUpdate.Remove(onPlayerUpdate)
    Events.OnGameStart.Remove(onGameStart)
    if MSF._originalCheckKey then
        ISLightSourceRadialMenu.checkKey = MSF._originalCheckKey
    end
    if MSF._originalEquipNew then
        ISEquipWeaponAction.new = MSF._originalEquipNew
    end
    MSF.clientInstalled = false
end
