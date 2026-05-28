--- Library to interact with the Tank Track Tool entities
-- @name tanktracktool
-- @class library
-- @libtbl tanktracktool_library
local WireLib = WireLib
local CheckLuaType = SF.CheckLuaType
local clampPos = WireLib.clampPos
local canEdit = tanktracktool.netvar.canEdit
local setVar = tanktracktool.netvar.setVar

SF.RegisterLibrary("tanktracktool")
local validClasses = {
    sent_tanktracks_auto = true,
    sent_tanktracks_legacy = true,
    sent_point_beam = true,
    sent_suspension_shock = true,
    sent_suspension_spring = true
}

return function(instance)
    local ents_metatable, ents_methods, ewrap, eunwrap = instance.Types.Entity, instance.Types.Entity.Methods, instance.Types.Entity.Wrap, instance.Types.Entity.Unwrap
    local _, _, vunwrap = instance.Types.Vector.Methods, instance.Types.Vector.Wrap, instance.Types.Vector.Unwrap
    local _, _, aunwrap = instance.Types.Angle.Methods, instance.Types.Angle.Wrap, instance.Types.Angle.Unwrap
    local CheckType = instance.CheckType
    local tanktracktool_library = instance.Libraries.tanktracktool
    local instance_plr = instance.player

    local function makeEntity(self, class, keep, pos, ang, model)
        if not gamemode.Call("PlayerSpawnSENT", instance_plr, class) then return NULL end
        local ent = ents.Create(class)
        if not IsValid(ent) then return NULL end
        if not util.IsValidModel(model) then model = "models/hunter/plates/plate.mdl" end
        ent:SetModel(model)
        ent:SetPos(clampPos(vunwrap(pos)))
        ent:SetAngles(aunwrap(ang))
        ent:Spawn()
        ent:Activate()
        local phys = ent:GetPhysicsObject()
        if IsValid(phys) then
            phys:EnableMotion(false)
            phys:Wake()
        end

        if not keep then
            self.data.tanktracks[ent] = true
            ent:CallOnRemove("tanktracktool_sf_onremove", function(e) self.data.spawnedProps[e] = nil end)
            ent.DoNotDuplicate = true
        else
            undo.Create(class)
            undo.SetPlayer(self.player)
            undo.AddEntity(ent)
            undo.Finish()
        end

        self.player:AddCleanup("sents", ent)
        self.player:AddCount(class, ent)
        return ewrap(ent)
    end

    local function canRunFunction()
        local ply = instance_plr
        if not ply.tanktracktool_sf_cooldown then
            ply.tanktracktool_sf_cooldown = CurTime() + 1
            ply.tanktracktool_sf_cooldown_count = 0
            return true
        end

        ply.tanktracktool_sf_cooldown_count = ply.tanktracktool_sf_cooldown_count + 1
        if ply.tanktracktool_sf_cooldown_count > 5 then
            if ply.tanktracktool_sf_cooldown > CurTime() then return false end
            ply.tanktracktool_sf_cooldown = CurTime() + 1
            ply.tanktracktool_sf_cooldown_count = 0
        end
        return true
    end

    --- Checks the cooldown whenever a value can be used
    function tanktracktool_library.canUseValue()
        return canRunFunction() and 1 or 0
    end

    --- Copies the track values from one entity to another
    -- @param Entity ent The entity from which to copy the values from
    function ents_methods:tanktracktoolCopyValues(ent)
        CheckType(self, ents_metatable)
        local selfEnt = eunwrap(self)
        local entEnt = eunwrap(ent)

        if not canRunFunction() then return end
        if not isOwner(instance, selfEnt) or not isOwner(instance, entEnt) then SF.Throw("You do not own this entity!", 1) end
        if not canEdit(selfEnt, instance_plr) or not canEdit(entEnt, instance_plr) then SF.Throw("You cannot edit this entity!", 1) end

        if selfEnt:GetClass() ~= entEnt:GetClass() then SF.Throw("Entities must be the same class!", 1) end
        selfEnt:netvar_copy(instance_plr, entEnt)
    end

    --- Resets the entity internal track values
    function ents_methods:tanktracktoolResetValues()
        CheckType(self, ents_metatable)
        local selfEnt = eunwrap(self)

        if not canRunFunction() then return end
        if not isOwner(instance, selfEnt) then SF.Throw("You do not own this entity!", 1) end
        if not canEdit(selfEnt, instance_plr) then SF.Throw("You cannot edit this entity!", 1) end

        local entindex = selfEnt.netvar.entindex
        local entities = selfEnt.netvar.entities
        selfEnt:netvar_install()
        selfEnt.netvar.entindex = entindex
        selfEnt.netvar.entities = entities
    end

    --- Create an entity with given class by request
    -- @param number num Keep
    -- @param string class The Class of the entity to create
    -- @param string model The Model of the entity to create
    -- @param Vector pos The Position of the created entity
    -- @param Angle ang The Angle of the created entity
    function tanktracktool_library.create(keep, class, model, pos, ang)
        class = string.lower(class)
        if not validClasses[class] then return end

        model = string.lower(model)

        return makeEntity(instance, class, keep ~= 0, pos, ang, model)
    end

    --- Updates the values under the specified index
    -- @param string key The key to set
    -- @param table args The values to set the key to
    function ents_methods:tanktracktoolSetValue(key, args)
        CheckType(self, ents_metatable)
        local ent = eunwrap(self)

        CheckLuaType(key, TYPE_STRING)

        if not canRunFunction() then return end
        if not isOwner(instance, ent) then SF.Throw("You do not own this entity!", 1) end
        if not canEdit(ent, instance_plr) then SF.Throw("You cannot edit this entity!", 1) end
        if not ent.netvar.variables:get(key) then SF.Throw(string.format("Variable '%s' doesn't exist on entity!", key), 1) end

        local count = #args
        if count == 0 then SF.Throw("You must provide a value!", 1) end
        if count == 1 then
            local value = unpack(args)
            setVar(ent, key, nil, value, true)
            return
        end

        if count == 2 then
            local index, value = unpack(args)
            if not isnumber(index) then SF.Throw("You must provide an index!", 1) end
            setVar(ent, key, index, value, true)
            return
        end
    end

    -------------------------------------------------------------------------------
    local quicklink = {}
    quicklink.doubleLink = {
        get = function() return {"Entity1 (entity)", "Entity2 (entity)"} end,
        set = function(ent, tbl)
            local Ent1 = eunwrap(tbl.Entity1)
            local Ent2 = eunwrap(tbl.Entity2)
            if not Ent1 or not isentity(Ent1) then
                SF.Throw("Links table must contain an entity with key 'Entity1'!", nil)
                return
            end

            if not Ent2 or not isentity(Ent2) then
                SF.Throw("Links table must contain an entity with key 'Entity2'!", nil)
                return
            end

            return ent:netvar_setLinks({
                Entity1 = Ent1,
                Entity2 = Ent2
            }, instance_plr)
        end
    }

    quicklink.sent_tanktracks_legacy = {
        get = function() return {"Chassis (entity)", "Wheel (table)", "Roller (table)"} end,
        set = function(ent, tbl)
            local VChassis = eunwrap(tbl.Chassis)
            if not VChassis or not isentity(VChassis) then
                SF.Throw("Links table must contain an entity with key 'Chassis'!", nil)
                return
            end

            if not tbl.Wheel or type(tbl.Wheel) ~= "table" then
                SF.Throw("Links table must contain an table with key 'Wheel'!", nil)
                return
            end

            if not tbl.Roller or type(tbl.Roller) ~= "table" then
                SF.Throw("Links table must contain an table with key 'Roller'!", nil)
                return
            end

            local t = {
                Chassis = VChassis,
                Wheel = {},
                Roller = {}
            }

            for k, v in SortedPairs(tbl.Wheel) do
                local vUnwrapped = eunwrap(v)
                if not isentity(vUnwrapped) then
                    SF.Throw("'Wheel' table must contain entities only!", nil)
                    return
                else
                    table.insert(t.Wheel, vUnwrapped)
                end
            end

            for k, v in SortedPairs(tbl.Roller) do
                local vUnwrapped = eunwrap(v)
                if not isentity(vUnwrapped) then
                    SF.Throw("'Roller' table must contain entities only!", nil)
                    return
                else
                    table.insert(t.Roller, vUnwrapped)
                end
            end

            return ent:netvar_setLinks(t, instance_plr)
        end
    }

    quicklink.sent_point_beam = quicklink.doubleLink
    quicklink.sent_suspension_shock = quicklink.doubleLink
    quicklink.sent_suspension_spring = quicklink.doubleLink
    -------------------------------------------------------------------------------
    --- Updates the entity links from the table passed
    -- Get the needed keys using tanktracktoolGetLinkNames()
    -- links table for shocks example:
    -- { ["Entity1"] = ent, ["Entity2"] = ent }
    -- @param table tbl The table with the links
    function ents_methods:tanktracktoolSetLinks(tbl)
        CheckType(self, ents_metatable)
        local ent = eunwrap(self)

        if not canRunFunction() then return end
        if not isOwner(instance, ent) then SF.Throw("You do not own this entity!", 1) end
        if not canEdit(ent, instance_plr) or not ent.netvar_setLinks then SF.Throw("You cannot link this entity!", 1) end

        local class = ent:GetClass()
        if not quicklink[class] then SF.Throw("You cannot link this entity!", 1) end
        quicklink[class].set(ent, tbl)
    end

    --- Returns a table containing the link names
    -- @return table The returned table
    function ents_methods:tanktracktoolGetLinkNames()
        CheckType(self, ents_metatable)
        local ent = eunwrap(self)

        if not canRunFunction() then return end
        if not ent.netvar_setLinks then SF.Throw("You cannot link this entity!", 1) end

        local class = ent:GetClass()
        if not quicklink[class] then SF.Throw("You cannot link this entity!", 1) end
        return quicklink[class].get(ent)
    end
end