if MSF.campfireBlockInstalled then return end

if not SCampfireGlobalObject then
    require "Camping/SCampfireGlobalObject"
end
if not SCampfireSystem then
    require "Camping/SCampfireSystem"
end
if not SCampfireGlobalObject then return end

MSF.campfireBlockInstalled = true
MSF.CAMPFIRE_BLOCKER_NAME = "MSF_CampfireBlocker"

local function isCampfireBlocker(object)
    if not object then return false end
    local okName, name = pcall(function() return object:getName() end)
    if okName and name == MSF.CAMPFIRE_BLOCKER_NAME then return true end
    local okData, modData = pcall(function() return object:getModData() end)
    return okData and modData and modData.MSF_CampfireBlocker == true
end

function MSF.getCampfireBlocker(square)
    if not square then return nil end
    local ok, objects = pcall(function() return square:getSpecialObjects() end)
    if not ok or not objects then return nil end
    for i = 1, objects:size() do
        local object = objects:get(i - 1)
        if isCampfireBlocker(object) then return object end
    end
    return nil
end

local function configureBlocker(blocker)
    blocker:setName(MSF.CAMPFIRE_BLOCKER_NAME)
    blocker:setSpriteFromName("invisible_01_0")
    blocker:setBlockAllTheSquare(true)
    blocker:setCanPassThrough(false)
    blocker:setIsThumpable(true)
    blocker:setIsDismantable(false)
    blocker:setCanBarricade(false)
    blocker:setIsHoppable(false)
    blocker:setThumpDmg(0)
    blocker:setMaxHealth(1000000)
    blocker:setHealth(1000000)
    blocker:setDoRender(false)
    local modData = blocker:getModData()
    if modData then modData.MSF_CampfireBlocker = true end
end

local function invalidateSquare(square)
    if not square then return end
    pcall(function() square:RecalcProperties() end)
    pcall(function() square:InvalidateSpecialObjectPaths() end)
    pcall(function() square:RecalcAllWithNeighbours(true) end)
end

local function addBlocker(square)
    local blocker = MSF.getCampfireBlocker(square)
    if blocker then
        configureBlocker(blocker)
        return blocker
    end
    local cell = getCell()
    if not cell or not square then return nil end
    blocker = IsoThumpable.new(cell, square, "invisible_01_0", false, {})
    configureBlocker(blocker)
    square:AddSpecialObject(blocker)
    local okChunk, chunk = pcall(function() return square:getChunk() end)
    if okChunk and chunk then
        pcall(function() blocker:transmitCompleteItemToClients() end)
    end
    invalidateSquare(square)
    return blocker
end

local function removeBlocker(square)
    local blocker = MSF.getCampfireBlocker(square)
    if not blocker then return end
    local okChunk, chunk = pcall(function() return square:getChunk() end)
    if okChunk and chunk then
        pcall(function() square:transmitRemoveItemFromSquareOnClients(blocker) end)
    end
    pcall(function() square:RemoveTileObject(blocker, true) end)
    pcall(function() blocker:removeFromSquare() end)
    pcall(function() blocker:setSquare(nil) end)
    invalidateSquare(square)
end

function MSF.updateCampfireBlocker(luaObject)
    if not luaObject then return end
    local square = luaObject:getSquare()
    if not square then return end
    if luaObject.isLit then
        addBlocker(square)
    else
        removeBlocker(square)
    end
end

local originalChangeFireLvl = SCampfireGlobalObject.changeFireLvl
MSF._originalCampfireChangeFireLvl = originalChangeFireLvl
function SCampfireGlobalObject:changeFireLvl()
    originalChangeFireLvl(self)
    MSF.updateCampfireBlocker(self)
end

local originalRemoveIsoObject = SCampfireGlobalObject.removeIsoObject
MSF._originalCampfireRemoveIsoObject = originalRemoveIsoObject
function SCampfireGlobalObject:removeIsoObject()
    local square = self:getSquare()
    if square then removeBlocker(square) end
    return originalRemoveIsoObject(self)
end

function MSF.uninstallCampfireBlock()
    SCampfireGlobalObject.changeFireLvl = MSF._originalCampfireChangeFireLvl
    SCampfireGlobalObject.removeIsoObject = MSF._originalCampfireRemoveIsoObject
    MSF.campfireBlockInstalled = false
end
