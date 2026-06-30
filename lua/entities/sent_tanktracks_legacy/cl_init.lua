
include( "shared.lua" )

local tanktracktool =  tanktracktool

local math, util, string, table, render =
      math, util, string, table, render

local next, pairs, FrameTime, Entity, IsValid, EyePos, EyeVector, Vector, Angle, Matrix, WorldToLocal, LocalToWorld, Lerp, LerpVector =
      next, pairs, FrameTime, Entity, IsValid, EyePos, EyeVector, Vector, Angle, Matrix, WorldToLocal, LocalToWorld, Lerp, LerpVector

local pi = math.pi


--[[
    tool_link setup
]]
local function tool_filter_wheels( controller, ent, key, enttbl, feedback )
    if not isentity( ent ) or not IsValid( ent ) or ent:IsPlayer() or ent:IsVehicle() or ent:IsNPC() or ent:IsWorld() then
        if feedback then chat.AddText( Color( 255, 0, 0 ), "Invalid entity" ) end
        return false
    end
    if ent == enttbl.Chassis then
        if feedback then chat.AddText( tanktracktool.multitool.ui.colors.text_plain, "This entity is the ", tanktracktool.multitool.ui.colors.text_class, "Chassis" ) end
        return false
    end
    if key == "Wheel" and enttbl.Roller and enttbl.Roller[ent] then
        if feedback then chat.AddText( tanktracktool.multitool.ui.colors.text_plain, "This entity is already a ", tanktracktool.multitool.ui.colors.text_class, "Roller" ) end
        return false
    end
    if key == "Roller" and enttbl.Wheel and enttbl.Wheel[ent] then
        if feedback then chat.AddText( tanktracktool.multitool.ui.colors.text_plain, "This entity is already a ", tanktracktool.multitool.ui.colors.text_class, "Wheel" ) end
        return false
    end

    local e
    if enttbl.Roller and next( enttbl.Roller ) then
        e = next( enttbl.Roller )
    end
    if enttbl.Wheel and next( enttbl.Wheel ) then
        e = next( enttbl.Wheel )
    end

    if e then
        local m = enttbl.Chassis:GetWorldTransformMatrix()
        if tobool( controller.netvar.values.systemRotate ) then
            m:Rotate( Angle( 0, -90, 0 ) )
        end

        local pos, dir = m:GetTranslation(), m:GetRight()
        local d1 = dir:Dot( ( ent:GetPos() - pos ):GetNormalized() ) > 0
        local d2 = dir:Dot( ( e:GetPos() - pos ):GetNormalized() ) > 0

        if d1 ~= d2 then
            if feedback then
                chat.AddText(
                    tanktracktool.multitool.ui.colors.text_plain, "All ",
                    tanktracktool.multitool.ui.colors.text_class, "Wheels ",
                    tanktracktool.multitool.ui.colors.text_plain, "and ",
                    tanktracktool.multitool.ui.colors.text_class, "Rollers ",
                    tanktracktool.multitool.ui.colors.text_plain, "must be on the same side of the ",
                    tanktracktool.multitool.ui.colors.text_class, "Chassis"
                )
            end
            return false
        end
    end

    return true
end

tanktracktool.netvar.addToolLink( ENT, "Chassis", nil, nil )
tanktracktool.netvar.addToolLinks( ENT, "Wheel", tool_filter_wheels, nil, "Roller", tool_filter_wheels, nil )


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
    mode
]]
local function real_radius( ent )
    if ent:GetHitBoxBounds( 0, 0 ) then
        local min, max = ent:GetHitBoxBounds( 0, 0 )
        local bounds = ( max - min ) * 0.5
        return math.max( bounds.x, bounds.y, bounds.z )
    end
    return ent:GetModelRadius() or 12
end

local function GetAngularVelocity( ent, pos, ang )
    local dir = WorldToLocal( ent:GetForward() + pos, ang, pos, ang )
    local ang = math.deg( math.atan2( dir.z, dir.x ) )

    ent.m_DeltaAngle = ent.m_DeltaAngle or 0
    local ang_vel = ( ang - ent.m_DeltaAngle + 180 ) % 360 - 180
    ent.m_DeltaAngle = ang

    return ang_vel --/ FrameTime()
end

local mode = tanktracktool.render.mode()

function mode:onInit( controller )
    local values = controller.netvar.values

    controller.autotracks_matrixRotate = tobool( values.systemRotate ) and Angle( 0, -90, 0 )
    controller.autotracks_matrix = controller.autotracks_chassis:GetWorldTransformMatrix()
    if controller.autotracks_matrixRotate then
        controller.autotracks_matrix:Rotate( controller.autotracks_matrixRotate )
    end

    local pos = controller.autotracks_matrix:GetTranslation()
    local ang = controller.autotracks_matrix:GetAngles()

    local parts = self:getParts( controller )

    for i = 1, #controller.autotracks_wheels do
        local wheel = controller.autotracks_wheels[i]

        table.insert( parts, {
            index = i,
            {
                entity = wheel,
                radius = real_radius( wheel ),
                [1] = WorldToLocal( wheel:GetPos(), wheel:GetAngles(), pos, ang ),
            }
        } )
    end

    local rollercount = 0
    for i = 1, #parts do
        local node_this = parts[i][1]
        local node_next = parts[i == #parts and 1 or i + 1][1]

        local offset = math.Clamp( rollercount > 0 and values.rollerRadius or values.wheelRadius, -node_this.radius * 2, node_this.radius * 2 )
        node_this.radius = node_this.radius + offset -- values.trackHeight * 0.25

        local dir_next = node_next[1] - node_this[1]
        if dir_next.x >= 0 then
            rollercount = rollercount + 1
        end
    end

    controller.autotracks_trackvalues = {
        trackColor = values.trackColor,
        trackMaterial = values.trackMaterial,
        trackWidth = values.trackWidth,
        trackHeight = values.trackHeight,
        trackGuideY = values.trackGuideY,
        trackGuideZ = values.trackGuideZ,
        trackGrouser = values.trackGrouser,
        trackTension = values.trackTension,
        trackRes = values.trackRes,
        trackFlip = values.trackFlip,
    }

    controller.autotracks_rollercount = rollercount
    controller.autotracks_trackoffset = parts[1][1][1].y + ( controller.autotracks_trackvalues.trackFlip ~= 0 and -1 or 1 ) * values.trackOffsetY
    controller.autotracks_sprocket = math.Clamp( values.wheelSprocket, 1, #parts )
    controller.autotracks_scrollRateMod = math.Clamp( values.scrollMod, 0.01, 2 )
    controller.autotracks_le_lastpos = controller.autotracks_le_lastpos or Vector()
    controller.autotracks_le_lastvel = controller.autotracks_le_lastvel or 1
    controller.autotracks_le_lastrot = controller.autotracks_le_lastrot or 1

    tanktracktool.autotracks.setup( controller )
    tanktracktool.autotracks.think( controller )
    self:override( controller, true )
end


function mode:onThink( controller, eyepos, eyedir )
    controller.autotracks_data_ready = nil

    if not IsValid( controller.autotracks_chassis ) then
        controller.tanktracktool_reset = true
        return
    end

    if controller.autotracks_chassis:IsDormant() then
        return
    end

    for i = 1, #controller.autotracks_wheels do
        if not IsValid( controller.autotracks_wheels[i] ) then
            controller.tanktracktool_reset = true
            print( "invalid wheell " )
            return
        end
    end

    local parts = self:getParts( controller )

    controller.autotracks_matrix = controller.autotracks_chassis:GetWorldTransformMatrix()
    if controller.autotracks_matrixRotate then
        controller.autotracks_matrix:Rotate( controller.autotracks_matrixRotate )
    end

    local pos, ang = controller.autotracks_matrix:GetTranslation(), controller.autotracks_matrix:GetAngles()

    local dir = pos - eyepos
    if dir:Dot( eyedir ) / dir:Length() < -0.75 then return end

    local sprocket = controller.autotracks_sprocket
    local scrollMod = controller.autotracks_scrollRateMod

    for i = 1, #parts do
        local wheel = parts[i][1]
        local ent = wheel.entity

        wheel[1] = WorldToLocal( ent:GetPos(), ent:GetAngles(), pos, ang )
        wheel[1].y = controller.autotracks_trackoffset

        if i == sprocket then
            local rot_le = GetAngularVelocity( ent, pos, ang )
            controller.autotracks_le_lastvel = rot_le / ( math.pi * ( 1.5 * scrollMod ) ) -- no idea if this is correct nor why it works
        end
    end

    tanktracktool.autotracks.think( controller )
end


function mode:onDraw( controller, eyepos, eyedir, emptyCSENT, flashlightMODE )
    local pos, ang = controller.autotracks_matrix:GetTranslation(), controller.autotracks_matrix:GetAngles()

    if controller.autotracks_data_ready and emptyCSENT then
        local matrix = controller.autotracks_matrix
        local pos, ang = matrix:GetTranslation(), matrix:GetAngles()

        render.SetBlend( 0 )
        emptyCSENT:SetPos( pos )
        emptyCSENT:SetAngles( ang )
        emptyCSENT:SetupBones()
        emptyCSENT:DrawModel()
        render.SetBlend( 1 )

        tanktracktool.autotracks.render( controller, matrix )
    end
end

function ENT:Think()
    if tanktracktool.disable_autotracks then
        self.netvar_syncData = nil
        self.netvar_syncLink = nil
        self.tanktracktool_reset = true

        mode:override( self, false )

        return
    end

    self.BaseClass.Think( self )

    if self:IsDormant() then
        return
    end

    if self.tanktracktool_reset then
        if not self.netvar.entities then
            local e = {}
            for k, v in pairs( self.netvar.entindex ) do
                if IsValid( Entity( v ) ) then
                    e[k] = Entity( v )
                else
                    return
                end
            end

            self.netvar.entities = e

            return
        end

        self.autotracks_chassis = self.netvar.entities[1]
        if not IsValid( self.autotracks_chassis ) then return end

        self.autotracks_wheels = {}
        for k, v in SortedPairs( self.netvar.entities ) do
            if k ~= 1 and IsValid( v ) then table.insert( self.autotracks_wheels, v ) end
        end

        if #self.autotracks_wheels == 0 then return end

        mode:init( self )
        self.tanktracktool_reset = nil

        return
    end

    mode:think( self )
end

function ENT:Draw()
    self:DrawModel()
end
