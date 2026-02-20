
AddCSLuaFile()

DEFINE_BASECLASS( "base_tanktracktool" )

ENT.Type      = "anim"
ENT.Spawnable = true
ENT.AdminOnly = false
ENT.Category  = "Tank Track Tool"
ENT.PrintName = "Suspension Shock"

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

netvar:category( "Shock Absorber" )

netvar:subcategory( "Setup" )
netvar:var( "shocktype", "Combo", { def = "coil_over", values = { coil_over = 1, spring = 2, covered = 3, none = 4 }, sort = SortedPairsByValue, title = "type" } )
netvar:var( "shockscale", "Float", { def = 1, min = 0, max = 50, title = "model scale" } )
netvar:var( "shocklencyl", "Float", { def = 12, min = 0, max = 1000, title = "cylinder length", help = "absolute units" } )
netvar:var( "shocklenret", "Float", { def = 0.75, min = 0, max = 1, title = "retainer offset", help = "% of cylinder length" } )
netvar:var( "shockcoilradius", "Float", { def = 0.25, min = 0, max = 1, title = "coil wire radius", help = "% of model scale" } )
netvar:var( "shockcoilcount", "Int", { def = 12, min = 1, max = 50, title = "coil turn count" } )
netvar:var( "shockoffset1", "Vector", { def = Vector(), min = Vector( -1000, -1000, -1000 ), max = Vector( 1000, 1000, 1000 ), title = "local offset (E1)" } )
netvar:var( "shockoffset2", "Vector", { def = Vector(), min = Vector( -1000, -1000, -1000 ), max = Vector( 1000, 1000, 1000 ), title = "local offset (E2)" } )

netvar:subcategory( "Colors" )
netvar:var( "shockrodcolor", "Color", { def = "", title = "piston" } )
netvar:var( "shocktopcolor", "Color", { def = "175 175 175 255", title = "top" } )
netvar:var( "shockbotcolor", "Color", { def = "30 30 30 255", title = "bottom" } )
netvar:var( "shockcylcolor", "Color", { def = "30 30 30 255", title = "cylinder" } )
netvar:var( "shockretcolor", "Color", { def = "175 175 175 255", title = "retainer" } )
netvar:var( "shockwirecolor", "Color", { def = "30 30 30 255", title = "coil/cover" } )

netvar:subcategory( "Materials" )
netvar:var( "shockrodmat", "String", { def = "phoenix_storms/fender_chrome", title = "piston" } )
netvar:var( "shocktopmat", "String", { def = "models/shiny", title = "top" } )
netvar:var( "shockbotmat", "String", { def = "models/shiny", title = "bottom" } )
netvar:var( "shockcylmat", "String", { def = "models/shiny", title = "cylinder" } )
netvar:var( "shockretmat", "String", { def = "models/shiny", title = "retainer" } )
netvar:var( "shockcovermat", "String", { def = "phoenix_storms/concrete0", title = "cover" } )


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
    editor callbacks
]]
do
    netvar:get( "shocktype" ).data.hook = function( inner, val )
        local editor = inner.m_Editor

        if val == "none" then
            editor.Variables.shocklenret:SetEnabled( false )
            editor.Variables.shockcoilradius:SetEnabled( false )
            editor.Variables.shockcoilcount:SetEnabled( false )
            editor.Variables.shockcovermat:SetEnabled( false )
            editor.Variables.shockretmat:SetEnabled( false )
            editor.Variables.shockbotmat:SetEnabled( false )
            editor.Variables.shockwirecolor:SetEnabled( false )
            editor.Variables.shockretcolor:SetEnabled( false )
            editor.Variables.shockbotcolor:SetEnabled( false )
            return
        end

        editor.Variables.shocklenret:SetEnabled( true )
        editor.Variables.shockretmat:SetEnabled( true )
        editor.Variables.shockbotmat:SetEnabled( true )
        editor.Variables.shockwirecolor:SetEnabled( true )
        editor.Variables.shockretcolor:SetEnabled( true )
        editor.Variables.shockbotcolor:SetEnabled( true )

        if val == "spring" or val == "coil_over" then
            editor.Variables.shockcoilradius:SetEnabled( true )
            editor.Variables.shockcoilcount:SetEnabled( true )
            editor.Variables.shockcovermat:SetEnabled( false )
            return
        end

        if val == "covered" then
            editor.Variables.shockcoilradius:SetEnabled( false )
            editor.Variables.shockcoilcount:SetEnabled( false )
            editor.Variables.shockcovermat:SetEnabled( true )
        end
    end
end


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

    local shock = tanktracktool.render.addshock( self, controller )
    data.shock = shock

    shock.info.type = values.shocktype
    shock.info.scale = values.shockscale
    shock.info.coilcount = values.shockcoilcount
    shock.info.wireradius = values.shockcoilradius
    shock.info.shocklencyl = values.shocklencyl
    shock.info.shocklenret = values.shocklenret
    shock.info.rodcolor = values.shockrodcolor
    shock.info.topcolor = values.shocktopcolor
    shock.info.botcolor = values.shockbotcolor
    shock.info.cylcolor = values.shockcylcolor
    shock.info.retcolor = values.shockretcolor
    shock.info.wirecolor = values.shockwirecolor

    shock.info.rodmat = values.shockrodmat
    shock.info.topmat = values.shocktopmat
    shock.info.botmat = values.shockbotmat
    shock.info.cylmat = values.shockcylmat
    shock.info.retmat = values.shockretmat
    shock.info.covermat = values.shockcovermat

    data.offset1 = Vector( values.shockoffset1 )
    data.offset2 = Vector( values.shockoffset2 )

    data.shock:init( true, false )
end

function mode:onThink( controller )
    local data = self:getData( controller )

    local e1, e2 = GetEntities( controller )
    if not e1 or not e2 then
        self:setnodraw( controller, true )
        return
    end

    self:setnodraw( controller, false )
    data.shock:setcontrolpoints( e2:LocalToWorld( data.offset2 ), e1:LocalToWorld( data.offset1 ) )
end

function mode:onDraw( controller, eyepos, eyedir, empty, flashlight )
    local data = self:getData( controller )

    data.shock:render()
    self:renderParts( controller, eyepos, eyedir, emptyCSENT, flashlightMODE )

    if flashlightMODE then
        render.PushFlashlightMode( true )
        self:renderParts( controller, eyepos, eyedir, emptyCSENT, flashlightMODE )
        render.PopFlashlightMode()
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
