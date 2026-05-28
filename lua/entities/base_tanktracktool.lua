
--[[
    base entity
]]
AddCSLuaFile()

DEFINE_BASECLASS( "base_anim" )

ENT.Type      = "anim"
ENT.Spawnable = false
ENT.AdminOnly = true
ENT.Category  = "Tank Track Tool"

local tanktracktool = tanktracktool

function ENT:Initialize()
    self:netvar_install()

    self:SetMoveType( MOVETYPE_VPHYSICS )
    self:SetSolid( SOLID_VPHYSICS )

    if SERVER then
        self:PhysicsInit( SOLID_VPHYSICS )

        if WireLib then
            local inputs = self:netvar_wireInputs()
            if inputs then self.Inputs = WireLib.CreateInputs( self, inputs ) end
        end
    end
end

function ENT:Think()
    self:netvar_transmit()
end

if SERVER then
    function ENT:UpdateTransmitState() return TRANSMIT_ALWAYS end

    local function getmodel( ply, class )
        local a = ply:GetInfo( "tanktracktool_spawn_model" )
        if a and util.IsValidModel( a ) then return a end

        local b = scripted_ents.GetMember( class, "tanktracktool_model" )
        if b and util.IsValidModel( b ) then return b end

        return "models/hunter/plates/plate.mdl"
    end

    function ENT:SpawnFunction( ply, tr, class )
        if not tr.Hit then return end

        local ent = ents.Create( class )
        ent:SetModel( getmodel( ply, class ) )

        local z = ent.tanktracktool_spawnHeight
        if not isnumber( z ) then
            local min, max = ent:GetModelBounds()
            z = ( max.z - min.z ) * 0.5
        end

        local ang
        if math.abs( tr.HitNormal.x ) < 0.001 and math.abs( tr.HitNormal.y ) < 0.001 then
            ang = Vector( 0, 0, tr.HitNormal.z ):Angle()
        else
            ang = tr.HitNormal:Angle()
        end
        ang.p = ang.p + 90

        ent:SetAngles( ang )
        ent:SetPos( tr.HitPos + ang:Up() * z )
        ent:Spawn()
        ent:Activate()

        return ent
    end

    --[[
        wiremod and duplicator support
    ]]
    function ENT:OnRemove()
        if WireLib then WireLib.Remove( self ) end
    end

    function ENT:OnRestore()
        if WireLib then WireLib.Restored( self )  end
    end

    function ENT:PreEntityCopy()
        duplicator.ClearEntityModifier( self, "tanktracktool" )

        local DupeInfo = tanktracktool.netvar.getDupe( self )
        if DupeInfo then
            duplicator.StoreEntityModifier( self, "tanktracktool", DupeInfo )
        end

        duplicator.ClearEntityModifier( self, "WireDupeInfo" )

        if WireLib then
            local DupeInfo = WireLib.BuildDupeInfo( self )
            duplicator.StoreEntityModifier( self, "WireDupeInfo", DupeInfo )
        end
    end

    function ENT:PostEntityCopy()
    end

    function ENT:OnEntityCopyTableFinish( dupedata )
        dupedata.OverlayData = nil
        dupedata.lastWireOverlayUpdate = nil
        dupedata.WireDebugName = nil
    end

    local function EntityLookup( createdEntities )
        return function( id, default )
            if id == nil then return default end
            if id == 0 then return game.GetWorld() end
            local ent = createdEntities[id]
            if IsValid( ent ) then return ent else return default end
        end
    end

    function ENT:OnDuplicated( entTable )
        self.DuplicationInProgress = true
    end

    function ENT:PostEntityPaste( ply, ent, createdEntities )
        local entmods = ent.EntityMods

        if entmods then
            local enttbl = EntityLookup( createdEntities )

            tanktracktool.netvar.applyDupe( ply, ent, entmods, enttbl )

            if WireLib and entmods.WireDupeInfo then
                WireLib.ApplyDupeInfo( ply, ent, entmods.WireDupeInfo, enttbl )
            end
        end

        self.DuplicationInProgress = nil
    end

else

    function ENT:Draw()
        self:DrawModel()
    end

end


--[[
    netvar methods
]]
function ENT:netvar_setup()
    return tanktracktool.netvar.new()
end

function ENT:netvar_install( restore )
    local install, default = self:netvar_setup()
    tanktracktool.netvar.install( self, install, default, restore )
end

function ENT:netvar_copy( ply, ent )
    tanktracktool.netvar.copy( self, ent, ply )
end

function ENT:netvar_set( name, index, newval, forceUpdate )
    return tanktracktool.netvar.setVar( self, name, index, newval, forceUpdate )
end

function ENT:netvar_get( name, index )
    return tanktracktool.netvar.getVar( self, name, index )
end

function ENT:netvar_getValues()
    return self.netvar.values
end

function ENT:netvar_callback( id, ... )
end

function ENT:netvar_wireInputs()
end


--[[
    networking
]]
if SERVER then

    --[[
        satisfy full update requests
    ]]
    function ENT:netvar_transmit()
        if self.netvar_syncData then
            tanktracktool.netvar.transmitData( self, self.netvar_syncData )
            self.netvar_syncData = nil
        end

        if self.netvar_syncLink then
            tanktracktool.netvar.transmitLink( self, self.netvar_syncLink )
            self.netvar_syncLink = nil
        end
    end

else

    --[[
        send full update request
    ]]
    function ENT:netvar_transmit()
        if not self.netvar_syncData then
            tanktracktool.netvar.transmitData( self )
            self.netvar_syncData = true
        end

        if not self.netvar_syncLink then
            tanktracktool.netvar.transmitLink( self )
            self.netvar_syncLink = true
        end
    end


    --[[
        send specific edit
    ]]
    function ENT:netvar_edit( name, index, newval )
        local name, index, newval, diff = self:netvar_set( name, index, newval )
        if not name or not diff then
            return false
        end

        tanktracktool.netvar.transmitEdit( self, name, index, newval )

        return true
    end

end
