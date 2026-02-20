
AddCSLuaFile()

DEFINE_BASECLASS( "base_tanktracktool" )

ENT.Type      = "anim"
ENT.Spawnable = true
ENT.AdminOnly = false
ENT.Category  = "Tank Track Tool"
ENT.PrintName = "Point Beam"

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

    function ENT:netvar_nme( data )
        return data
    end

    function ENT:netvar_wireInputs()
        return { "Disable", "Entity1 [ENTITY]", "Entity2 [ENTITY]", "Offset1 [VECTOR]", "Offset2 [VECTOR]" }
    end

    local function isnan( v ) return v.x ~= v.x or v.y ~= v.y or v.z ~= v.z end
    local function clamp( v ) return Vector( math.Clamp( v.x, -16384, 16384 ), math.Clamp( v.y, -16384, 16384 ), math.Clamp( v.z, -16384, 16384 ) ) end

    local inputs = {}
    inputs.Disable = function( self, ply, value )
        self:SetNW2Bool( "netwire_Disable", tobool( value ) )
    end
    inputs.Entity1 = function( self, ply, value )
        if ply and not tanktracktool.netvar.canLink( value, ply ) then value = nil end
        self:SetNW2Entity( "netwire_Entity1", value )
    end
    inputs.Entity2 = function( self, ply, value )
        if ply and not tanktracktool.netvar.canLink( value, ply ) then value = nil end
        self:SetNW2Entity( "netwire_Entity2", value )
    end
    inputs.Offset1 = function( self, ply, value )
        if not isvector( value ) or isnan( value ) then value = nil else value = clamp( value ) end
        self:SetNW2Vector( "netwire_Offset1", value )
    end
    inputs.Offset2 = function( self, ply, value )
        if not isvector( value ) or isnan( value ) then value = nil else value = clamp( value ) end
        self:SetNW2Vector( "netwire_Offset2", clamp( value ) )
    end

    function ENT:TriggerInput( name, value )
        if inputs[name] then inputs[name]( self, WireLib and WireLib.GetOwner( self ), value ) end
    end
end


--[[
    netvar setup
]]
local netvar = tanktracktool.netvar.new()

local default = {
    pointCount = 7,
    pointSpread = 4,
    pointStutter = 0.15,
    pointDelay = 0,
    pointSag = 0,

    sourceEnable = 1,
    sourceColor1 = "255 255 255 255",
    sourceColor2 = "255 0 0 255",
    sourceSize1 = 24,
    sourceSize2 = 64,

    pointEnable = 1,
    pointColor1 = "255 255 255 255",
    pointColor2 = "38 0 255 255",
    pointSize1 = 8,
    pointSize2 = 24,

    beamEnable = 1,
    beamColor1 = "255 255 255 255",
    beamColor2 = "242 0 255 255",
    beamSize1 = 16,
    beamSize2 = 48,

    particleEnable = 1,
    particleColor = "242 0 255 255",
    particleSize1 = 2,
    particleSize2 = 0,
}

function ENT:netvar_setup()
    return netvar, default
end

netvar:category( "Setup" )
netvar:var( "pointCount", "Int", { min = 2, max = 20, def = 5, title = "point count" } )
netvar:var( "pointSpread", "Float", { min = 0, max = 64, def = 1, title = "randomize point spread" } )
netvar:var( "pointStutter", "Float", { min = 0, max = 1, def = 0, title = "randomize point missfire" } )
netvar:var( "pointMulti", "Int", { min = 1, max = 4, def = 1, title = "beam count" } )
netvar:var( "pointDelay", "Float", { min = 0, max = 1, def = 0, title = "beam velocity delay" } )
netvar:var( "pointSag", "Float", { min = 0, max = 1, def = 0, title = "beam sag percent" } )
netvar:var( "pointTrace", "Bool", { def = 0, title = "enable beam intersection" } )

netvar:category( "source" )
netvar:var( "sourceEnable", "Bool", { def = 1, title = "enabled" } )
netvar:var( "sourceSize1", "Float", { min = 1, max = 64, def = 12, title = "inner size" } )
netvar:var( "sourceColor1", "Color", { def = "", title = "inner color" } )
netvar:var( "sourceSize2", "Float", { min = 1, max = 64, def = 12, title = "outer size" } )
netvar:var( "sourceColor2", "Color", { def = "", title = "outer color" } )

netvar:category( "Point" )
netvar:var( "pointEnable", "Bool", { def = 1, title = "enabled" } )
netvar:var( "pointSize1", "Float", { min = 1, max = 64, def = 12, title = "inner size" } )
netvar:var( "pointColor1", "Color", { def = "", title = "inner color" } )
netvar:var( "pointSize2", "Float", { min = 1, max = 64, def = 12, title = "outer size" } )
netvar:var( "pointColor2", "Color", { def = "", title = "outer color" } )

netvar:category( "Beam" )
netvar:var( "beamEnable", "Bool", { def = 1, title = "enabled" } )
netvar:var( "beamSize1", "Float", { min = 0, max = 64, def = 12, title = "inner size" } )
netvar:var( "beamColor1", "Color", { def = "", title = "inner color" } )
netvar:var( "beamSize2", "Float", { min = 0, max = 64, def = 12, title = "outer size" } )
netvar:var( "beamColor2", "Color", { def = "", title = "outer color" } )
netvar:var( "beamMaterial", "Combo", { def = "tripmine_laser", title = "material" } )

local edit = netvar:get( "beamMaterial" ).data
edit.values = {
    ["tripmine_laser"] = 1,
    ["trails/electric"] = 2,
    ["trails/physbeam"] = 3,
    ["trails/plasma"] = 4,
    ["cable/cable2"] = 5,
    ["tanktracktool/cable_white"] = 6,
    ["tanktracktool/cable_chain"] = 7,
}
if CLIENT then
    edit.images = {
        ["tripmine_laser"] = "tripmine_laser",
        ["trails/electric"] = "trails/electric",
        ["trails/physbeam"] = "trails/physbeam",
        ["trails/plasma"] = "trails/plasma",
        ["cable/cable2"] = "cable/cable2",
        ["tanktracktool/cable_white"] = "tanktracktool/cable_white",
        ["tanktracktool/cable_chain"] = "tanktracktool/cable_chain",
    }
end

netvar:category( "particle" )
netvar:var( "particleEnable", "Bool", { def = 1, title = "enabled" } )
netvar:var( "particleSize1", "Float", { min = 0, max = 64, def = 12, title = "start size" } )
netvar:var( "particleSize2", "Float", { min = 0, max = 64, def = 12, title = "end size" } )
netvar:var( "particleColor", "Color", { def = "", title = "color" } )
netvar:var( "particleMaterial", "Combo", { def = "effects/spark", title = "material" } )

local edit = netvar:get( "particleMaterial" ).data
edit.values = {
    ["effects/spark"] = 1,
}
if CLIENT then
    edit.images = {
        ["effects/spark"] = "effects/spark",
    }
end


--[[
    CLIENT
]]
if SERVER then return end

local math, util, string, table, render =
      math, util, string, table, render

local next, pairs, FrameTime, Entity, IsValid, EyePos, EyeVector, Vector, Angle, Matrix, WorldToLocal, LocalToWorld, Lerp, LerpVector =
      next, pairs, FrameTime, Entity, IsValid, EyePos, EyeVector, Vector, Angle, Matrix, WorldToLocal, LocalToWorld, Lerp, LerpVector

local pi = math.pi

local cv_ds = CreateClientConVar( "tanktracktool_pointbeam_disable", "0", true, false, "disable rendering" )
tanktracktool.disable_pointbeam = cv_ds:GetBool()

cvars.AddChangeCallback( "tanktracktool_pointbeam_disable", function( convar_name, value_old, value_new )
    tanktracktool.disable_pointbeam = tobool( value_new )
end )


--[[
    editor callbacks
]]
netvar:get( "sourceEnable" ).data.hook = function( inner, val )
    local editor = inner.m_Editor
    local enabled = tobool( val )

    editor.Variables.sourceSize1:SetEnabled( enabled )
    editor.Variables.sourceSize2:SetEnabled( enabled )
    editor.Variables.sourceColor1:SetEnabled( enabled )
    editor.Variables.sourceColor2:SetEnabled( enabled )
end
netvar:get( "pointEnable" ).data.hook = function( inner, val )
    local editor = inner.m_Editor
    local enabled = tobool( val )

    editor.Variables.pointSize1:SetEnabled( enabled )
    editor.Variables.pointSize2:SetEnabled( enabled )
    editor.Variables.pointColor1:SetEnabled( enabled )
    editor.Variables.pointColor2:SetEnabled( enabled )
end
netvar:get( "beamEnable" ).data.hook = function( inner, val )
    local editor = inner.m_Editor
    local enabled = tobool( val )

    editor.Variables.beamSize1:SetEnabled( enabled )
    editor.Variables.beamSize2:SetEnabled( enabled )
    editor.Variables.beamColor1:SetEnabled( enabled )
    editor.Variables.beamColor2:SetEnabled( enabled )
    editor.Variables.beamMaterial:SetEnabled( enabled )
end
netvar:get( "particleEnable" ).data.hook = function( inner, val )
    local editor = inner.m_Editor
    local enabled = tobool( val )

    editor.Variables.particleSize1:SetEnabled( enabled )
    editor.Variables.particleSize2:SetEnabled( enabled )
    editor.Variables.particleColor:SetEnabled( enabled )
    editor.Variables.particleMaterial:SetEnabled( enabled )
end


--[[
    netvar hooks
]]
local hooks = {}

hooks.editor_open = function( self, editor )
    for k, cat in pairs( editor.Categories ) do
        cat:SetExpanded( true )
    end
end

hooks.netvar_set = function( self ) self.tanktracktool_reset = true end
hooks.netvar_syncLink = function( self ) self.tanktracktool_reset = true end
hooks.netvar_syncData = function( self ) self.tanktracktool_reset = true end

function ENT:netvar_callback( id, ... )
    if hooks[id] then hooks[id]( self, ... ) end
end


--[[
]]
local mode = tanktracktool.render.mode()

function mode:onInit( controller )
    self:override( controller, true )

    local data = self:getData( controller )

    data.vars = controller:netvar_getValues()

    data.pointCount = math.abs( data.vars.pointCount or 10 )
    data.pointMulti = math.Clamp( data.vars.pointMulti or 1, 1, 4 )
    data.pointTrace = tobool( data.vars.pointTrace )

    local randomDisable = tonumber( data.vars.pointStutter )
    if randomDisable > 0 and randomDisable < 1 then
        data.randomDisable = 100 - randomDisable * 100
    else
        data.randomDisable = nil
    end

    data.pointDelay = tonumber( data.vars.pointDelay )
    if data.pointDelay > 0 then
        data.pointVelocity = Vector()
        data.pointDelay = data.pointDelay
    else
        data.pointDelay = nil
    end

    data.pointSpread = tonumber( data.vars.pointSpread )
    if data.pointSpread == 0 then
        data.pointSpread = nil
    end

    data.pointSag = tonumber( data.vars.pointSag )
    if data.pointSag == 0 then
        data.pointSag = nil
    end

    data.pointEnable = tobool( data.vars.pointEnable )
    if data.pointEnable then
        data.pointSize1 = math.abs( data.vars.pointSize1 or 16 )
        data.pointSize2 = math.abs( data.vars.pointSize2 or 16 )
        data.pointColor1 = string.ToColor( data.vars.pointColor1 or "" )
        data.pointColor2 = string.ToColor( data.vars.pointColor2 or "" )
        data.pointMaterial = Material( "sprites/gmdm_pickups/light" )
    end

    data.beamEnable = tobool( data.vars.beamEnable )
    if data.beamEnable then
        data.beamSize1 = math.abs( data.vars.beamSize1 or 16 )
        data.beamSize2 = math.abs( data.vars.beamSize2 or 16 )
        data.beamColor1 = string.ToColor( data.vars.beamColor1 or "" )
        data.beamColor2 = string.ToColor( data.vars.beamColor2 or "" )
        data.beamMaterial = Material( data.vars.beamMaterial )
    end

    data.sourceEnable = tobool( data.vars.sourceEnable )
    if data.sourceEnable then
        data.sourceSize1 = math.abs( data.vars.sourceSize1 or 16 )
        data.sourceSize2 = math.abs( data.vars.sourceSize2 or 16 )
        data.sourceColor1 = string.ToColor( data.vars.sourceColor1 or "" )
        data.sourceColor2 = string.ToColor( data.vars.sourceColor2 or "" )
        data.sourceMaterial = Material( "sprites/gmdm_pickups/light" )
    end

    data.particleEnable = tobool( data.vars.particleEnable )
    if data.particleEnable then
        data.particleSize1 = math.abs( data.vars.particleSize1 or 16 )
        data.particleSize2 = math.abs( data.vars.particleSize2 or 16 )
        data.particleColor = string.ToColor( data.vars.particleColor or "" )
        data.particleMaterial = data.vars.particleMaterial or "effects/spark"
    end

    data.beams = {}
end

local emitter = ParticleEmitter( Vector() )
local gravity = Vector()

local function CreateBeam( controller, ent1, ent2, pos1, pos2, data, fx )
    local beam = {
        ent0 = controller,
        ent1 = ent1,
        ent2 = ent2,
        pos1 = pos1,
        pos2 = pos2,
        data = data,
        points = {},
    }

    local min_length
    if data.pointSag then
        min_length = -pos1:Distance( pos2 ) * data.pointSag * 0.5
    end

    for i = 1, data.pointCount do
        local t = ( i - 1 ) / ( data.pointCount - 1 )
        local r = math.sin( t * pi )

        local pos = LerpVector( t, pos1, pos2 )

        if data.pointSpread then
            pos:Add( VectorRand( -r * data.pointSpread, r * data.pointSpread ) )
        end

        if data.pointDelay then
            pos:Add( data.velocity * r )
        end

        if min_length then
            gravity.z = min_length * r
            pos:Add( gravity )
        end

        beam.points[i] = pos
    end

    if fx then
        fx:SetOrigin( pos2 )
        fx:SetNormal( pos1 - pos2 )

        util.Effect( "AR2Impact", fx )
    end

    if data.particleEnable and emitter and math.random( 0, 100 ) > 50 then
        local index = math.random( 1, data.pointCount )
        local particle = emitter:Add( data.particleMaterial, beam.points[index] )

        if particle then
            particle:SetDieTime( 0.5 )
            particle:SetStartAlpha( 255 )
            particle:SetEndAlpha( 0 )
            particle:SetStartSize( math.Rand( data.particleSize1 * 0.5, data.particleSize1 ) )
            particle:SetEndSize( data.particleSize2 )
            particle:SetColor( data.particleColor.r, data.particleColor.g, data.particleColor.b )

            gravity.z = -( 25 + 250 * math.sin( ( index / data.pointCount ) * pi ) )

            particle:SetGravity( gravity )
        end
    end

    return beam
end

local function GetEntity( self, netkey, netlink )
    if netkey then netkey = self:GetNW2Entity( netkey ) end
    if IsValid( netkey ) then return netkey else
        return IsValid( netlink ) and netlink or self
    end
end

function mode:onThink( controller )
    local data = self:getData( controller )

    if data.randomDisable and math.random( 0, 100 ) > data.randomDisable or controller:GetNW2Bool( "netwire_Disable" ) then
        data.beams = {}
        return
    end

    if not controller.netvar.entities then
        local t = {}
        for k, v in pairs( controller.netvar.entindex ) do
            t[k] = IsValid( Entity( v ) ) and Entity( v ) or nil
        end
        controller.netvar.entities = t
    end

    -- local plus = controller:GetNW2Bool( "netwire_Disable" ) and 1 or -1
    -- data.frac = math.Clamp( ( data.frac or 0 ) + FrameTime() * plus, 0, 1 )

    -- if data.frac == 0 then
    --     data.beams = {}
    --     return
    -- end

    local ent1 = GetEntity( controller, "netwire_Entity1", controller.netvar.entities.Entity1 )
    local ent2 = GetEntity( controller, "netwire_Entity2", controller.netvar.entities.Entity2 )
    local pos1 = ent1:LocalToWorld( controller:GetNW2Vector( "netwire_Offset1" ), Vector() )
    local pos2 = ent2:LocalToWorld( controller:GetNW2Vector( "netwire_Offset2" ), Vector() )

    --local dir = pos2 - pos1
    --local len = dir:Length()

    --pos2 = pos1 + dir:GetNormalized() * len * data.frac

    if data.pointDelay then
        data.velocity = LerpVector( data.pointDelay, data.velocity or Vector(), ( ent1:GetVelocity() + ent2:GetVelocity() ) * -0.01 )
    end

    local beams = {}
    data.split = nil

    if data.pointTrace then
        local hit1 = util.TraceLine( { start = pos1, endpos = pos2, filter = { controller, ent1, ent2 } } )
        local hit2 = util.TraceLine( { start = pos2, endpos = pos1, filter = { controller, ent1, ent2 } } )

        local multi = data.pointMulti

        if IsValid( hit1.Entity ) then
            local fx = EffectData()

            if hit1.Entity:IsPlayer() then
                for i = 1, multi do beams[#beams + 1] = CreateBeam( controller, ent1, ent2, pos1, hit1.HitPos, data, fx ) end
            else
                for i = 1, multi do beams[#beams + 1] = CreateBeam( controller, ent1, ent2, pos1, hit1.Entity:NearestPoint( pos1 ), data, fx ) end
            end

            data.split = true
        end

        if IsValid( hit2.Entity ) then
            local fx = EffectData()

            if hit2.Entity:IsPlayer() then
                for i = 1, multi do beams[#beams + 1] = CreateBeam( controller, ent1, ent2, pos2, hit2.HitPos, data, fx ) end
            else
                for i = 1, multi do beams[#beams + 1] = CreateBeam( controller, ent1, ent2, pos2, hit2.Entity:NearestPoint( pos2 ), data, fx ) end
            end

            data.split = true
        end

        if not data.split then
            for i = 1, multi do beams[#beams + 1] = CreateBeam( controller, ent1, ent2, pos1, pos2, data ) end
        end
    else
        for i = 1, data.pointMulti do beams[#beams + 1] = CreateBeam( controller, ent1, ent2, pos1, pos2, data ) end
    end

    data.beams = beams
end

function mode:onDraw( controller, eyepos, eyedir, empty )
    local data = self:getData( controller )
    local beams = data.beams

    for k = 1, #beams do
        local beam = beams[k]
        local beamData = beam.data
        local beamPoints = beam.points
        local beamPointsCount = #beamPoints

        if beamData.sourceEnable then
            render.SetMaterial( beamData.sourceMaterial )

            render.DrawSprite( beamPoints[1], beamData.sourceSize1, beamData.sourceSize1, beamData.sourceColor1 )
            render.DrawSprite( beamPoints[1], beamData.sourceSize2, beamData.sourceSize2, beamData.sourceColor2 )

            if not beam.split then
                render.DrawSprite( beamPoints[beamPointsCount], beamData.sourceSize1, beamData.sourceSize1, beamData.sourceColor1 )
                render.DrawSprite( beamPoints[beamPointsCount], beamData.sourceSize2, beamData.sourceSize2, beamData.sourceColor2 )
            end
        end

        if beamData.pointEnable then
            render.SetMaterial( beamData.pointMaterial )

            for j = 1, beamPointsCount do
                render.DrawSprite( beamPoints[j], beamData.pointSize1, beamData.pointSize1, beamData.pointColor1 )
                render.DrawSprite( beamPoints[j], beamData.pointSize2, beamData.pointSize2, beamData.pointColor2 )
            end
        end

        if beamData.beamEnable then
            render.SetMaterial( beamData.beamMaterial )

            local v1 = beamPoints[1]
            local v2 = beamPoints[2]

            local s1 = beamData.beamSize1 > 0 and beamData.beamSize1
            local s2 = beamData.beamSize2 > 0 and beamData.beamSize2

            for j = 1, beamPointsCount - 1 do
                if s1 then render.DrawBeam( v1, v2, s1, 0, 1, beamData.beamColor1 ) end
                if s2 then render.DrawBeam( v1, v2, s2, 0, 1, beamData.beamColor2 ) end

                v1 = beamPoints[j + 1]
                v2 = beamPoints[j + 2]
            end
        end
    end
end

function ENT:Think()
    if tanktracktool.disable_pointbeam then
        self.tanktracktool_reset = true
        mode:override( self, false )
        return
    end

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
