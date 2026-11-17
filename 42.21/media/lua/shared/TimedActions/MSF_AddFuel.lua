require "TimedActions/ISAddFuel"

-- Network timed actions reconstruct this class on the authority from the
-- constructor's named fields. Keep both the class and fluidCont on both ends.
MSF_AddFuel = ISAddFuel:derive("MSF_AddFuel")

function MSF_AddFuel:new(character, generator, petrol, fluidCont)
    local o = ISBaseTimedAction.new(self, character)
    o.petrol = petrol
    o.fluidCont = fluidCont or petrol:getFluidContainer()
    o.generator = generator
    o.maxTime = o:getDuration()
    return o
end
