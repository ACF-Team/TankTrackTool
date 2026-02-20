
AddCSLuaFile()

DEFINE_BASECLASS( "base_tanktracktool" )

ENT.Type      = "anim"
ENT.Spawnable = true
ENT.AdminOnly = false
ENT.Category  = "Tank Track Tool"
ENT.PrintName = "Suspension Spring"

local tanktracktool = tanktracktool


--[[
    wiremod & tool_link setup
]]
if CLIENT then
    tanktracktool.netvar.addToolLink( ENT, "Entity1", nil, nil )
    tanktracktool.netvar.addToolLink( ENT, "Entity2", nil, nil )
end

if SERVER then
    function ENT:netvar_setLinks( tbl, ply )
        if not istable( tbl ) then
            return tanktracktool.netvar.setLinks( self, {}, ply )
        end

        tbl = {
            Entity1 = isentity( tbl.Entity1 ) and tbl.Entity1 or nil,
            Entity2 = isentity( tbl.Entity2 ) and tbl.Entity2 or nil,
        }

        return tanktracktool.netvar.setLinks( self, tbl, ply )
    end
end


--[[
    netvar setup
]]
local netvar = tanktracktool.netvar.new()


function ENT:netvar_setup()
    return netvar
end

netvar:category( "Spring" )

netvar:subcategory( "Setup" )
netvar:var( "coilcount", "Int", { def = 12, min = 1, max = 50, title = "coil turn count" } )
netvar:var( "coilradius", "Float", { def = 12, min = 0, max = 1000, title = "coil turn radius" } )
netvar:var( "wireradius", "Float", { def = 0.25, min = 0, max = 1, title = "coil wire radius", help = "% of turn radius" } )
netvar:var( "offset1", "Vector", { def = Vector(), min = Vector( -1000, -1000, -1000 ), max = Vector( 1000, 1000, 1000 ), title = "local offset (E1)" } )
netvar:var( "offset2", "Vector", { def = Vector(), min = Vector( -1000, -1000, -1000 ), max = Vector( 1000, 1000, 1000 ), title = "local offset (E2)" } )

netvar:subcategory( "Colors" )
netvar:var( "wirecolor", "Color", { def = "255 125 0 255", title = "coil" } )


--[[
    CLIENT
]]
if SERVER then return end

local math, util, string, table, render =
      math, util, string, table, render

local next, pairs, FrameTime, Entity, IsValid, EyePos, EyeVector, Vector, Angle, Matrix, WorldToLocal, LocalToWorld, Lerp, LerpVector =
      next, pairs, FrameTime, Entity, IsValid, EyePos, EyeVector, Vector, Angle, Matrix, WorldToLocal, LocalToWorld, Lerp, LerpVector

local pi = math.pi


--[[
    netvar hooks
]]
local hooks = {}

hooks.editor_open = function( self, editor )
    for k, cat in pairs( editor.Categories ) do
        cat:ExpandRecurse( true )
    end
end

hooks.netvar_set = function( self ) self.tanktracktool_reset = true end
hooks.netvar_syncLink = function( self ) self.tanktracktool_reset = true end
hooks.netvar_syncData = function( self ) self.tanktracktool_reset = true end

function ENT:netvar_callback( id, ... )
    if hooks[id] then hooks[id]( self, ... ) end
end


local function GetEntities( self )
    if not self.netvar.entities and ( self.netvar.entindex.Entity1 and self.netvar.entindex.Entity2 ) then
        local e1 = Entity( self.netvar.entindex.Entity1 )
        local e2 = Entity( self.netvar.entindex.Entity2 )

        if IsValid( e1 ) and IsValid( e2 ) then
            self.netvar.entities = { Entity1 = e1, Entity2 = e2 }
        end
    end

    local e1 = self.netvar.entities and IsValid( self.netvar.entities.Entity1 ) and self.netvar.entities.Entity1 or nil
    local e2 = self.netvar.entities and IsValid( self.netvar.entities.Entity2 ) and self.netvar.entities.Entity2 or nil

    return e1, e2
end


--[[
]]
local mode = tanktracktool.render.mode()

function mode:onInit( controller )
    self:override( controller, true )

    local values = controller.netvar.values
    local data = self:getData( controller )

    data.coilcount = values.coilcount
    data.coilradius = values.coilradius
    data.wireradius = values.wireradius
    data.wirecolor = values.wirecolor
    data.offset1 = Vector( values.offset1 )
    data.offset2 = Vector( values.offset2 )

    if data.wireradius > 0 and data.coilradius > 0 and data.coilcount > 0 then
        data.helix = tanktracktool.render.createCoil()
        data.helix:setCoilCount( data.coilcount )
        data.helix:setRadius( data.coilradius )
        data.helix:setWireRadius( data.coilradius * data.wireradius )
        data.helix:setColor( data.wirecolor )
        data.helix:setDetail( 1 / 2 )
    end
end

function mode:onThink( controller )
    local data = self:getData( controller )

    local e1, e2 = GetEntities( controller )
    if not e1 or not e2 then
        self:setnodraw( controller, true )
        return
    end

    self:setnodraw( controller, false )
    if data.helix then
        data.helix:think( e2:LocalToWorld( data.offset2 ), e1:LocalToWorld( data.offset1 ) )
    end
end

function mode:onDraw( controller, eyepos, eyedir, empty, flashlight )
    local data = self:getData( controller )
    if data.helix then
        data.helix:draw()
    end
end

function ENT:Think()
    self.BaseClass.Think( self )

    if self.tanktracktool_reset then
        self.tanktracktool_reset = nil
        mode:init( self )
        return
    end

    mode:think( self )
end

function ENT:Draw()
    self:DrawModel()
end
