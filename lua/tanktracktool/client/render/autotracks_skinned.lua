
--
local math, mesh, render, cam, table =
      math, mesh, render, cam, table

local Vector, Mesh, IsValid =
      Vector, Mesh, IsValid

local table_insert = table.insert

local mesh_Begin, mesh_End, mesh_Position, mesh_TexCoord, mesh_Normal, mesh_Color, mesh_BoneData, mesh_AdvanceVertex =
      mesh.Begin, mesh.End, mesh.Position, mesh.TexCoord, mesh.Normal, mesh.Color, mesh.BoneData, mesh.AdvanceVertex

local render_SetMaterial, render_SetColorModulation =
      render.SetMaterial, render.SetColorModulation

local math_sqrt, math_sin, math_cos, math_atan2, math_floor, math_ceil, math_abs, math_max, math_min, math_Round, math_Clamp =
      math.sqrt, math.sin, math.cos, math.atan2, math.floor, math.ceil, math.abs, math.max, math.min, math.Round, math.Clamp

local math_rad = math.pi / 180
local math_deg = 180 / math.pi

local tanktracktool = tanktracktool
local autotracks = tanktracktool.autotracks

local supported = mesh_BoneData ~= nil

local cv_md = GetConVar( "tanktracktool_autotracks_detail_max" )
local cv_sk = CreateClientConVar( "tanktracktool_autotracks_skinned", "1", true, false, "render tracks with skinned meshes instead of rebuilding them every frame" )

local legacy = autotracks.legacy or {}
autotracks.legacy = legacy

for _, k in ipairs( { "setup", "think", "render" } ) do
    if not ( autotracks.skinned and autotracks[k] == autotracks.skinned[k] ) then
        legacy[k] = autotracks[k]
    end
end

local skinned = {}
autotracks.skinned = skinned

local bones_per_mesh = 51


--
local function bisect( xs, ys, zs, index, droop )
    if index < 1 then return 0 end
    table_insert( xs, index + 1, ( xs[index] + xs[index + 1] ) * 0.5 )
    table_insert( ys, index + 1, ( ys[index] + ys[index + 1] ) * 0.5 )
    table_insert( zs, index + 1, ( zs[index] + zs[index + 1] ) * 0.5 - droop )
    return 1
end

-- same path as autotracks.think without the vector garbage, except raised wheels don't fold the track back on itself
local function buildPath( self, i, detail, path )
    local xs, ys, zs = path.x, path.y, path.z

    local trackroots = self.tanktracktool_modeData.parts
    local trackrootscount = #trackroots

    local tension = self.autotracks_data_tension
    local droop = tension * 3
    local detailrad = 1 / ( 45 / detail )

    local count = 0
    local switchdir = -1

    for rootid = 1, trackrootscount do
        local root0 = trackroots[rootid == 1 and trackrootscount or rootid - 1][1]
        local root1 = trackroots[rootid][1]
        local root2 = trackroots[rootid == trackrootscount and 1 or rootid + 1][1]

        local pos1, pos0, pos2 = root1[i], root0[i], root2[i]
        local px, py, pz = pos1.x, pos1.y, pos1.z
        local rad = root1.trackRadius

        local d0x, d0z = pos0.x - px, pos0.z - pz
        local d2x, d2z = pos2.x - px, pos2.z - pz

        local atan0, atan2
        if d2x < 0 then
            atan2 = math_atan2( -d2x, -d2z ) * math_deg
            atan0 = math_atan2( d0x, d0z ) * math_deg
        else
            atan2 = math_atan2( d2x, d2z ) * math_deg
            atan0 = math_atan2( -d0x, -d0z ) * math_deg
            rad = -rad
            switchdir = switchdir + 1
        end

        local steps = detail
        if ( d2x > 0 ) ~= ( d0x > 0 ) then
            steps = math_Round( math_abs( atan2 ) - math_abs( atan0 ) ) * detailrad
        elseif atan2 < atan0 then
            steps = 0
        end

        if steps > 0 then
            for k = 0, steps do
                local p = ( atan0 + ( atan2 - atan0 ) * ( k / steps ) ) * math_rad
                count = count + 1
                xs[count], ys[count], zs[count] = px + math_cos( p ) * rad, py, pz - math_sin( p ) * rad
            end
        else
            local p = ( atan0 + ( atan2 - atan0 ) * 0.5 ) * math_rad
            count = count + 1
            xs[count], ys[count], zs[count] = px + math_cos( p ) * rad, py, pz - math_sin( p ) * rad
        end

        if switchdir > 0 and tension > 0 then
            count = count + bisect( xs, ys, zs, count - math_floor( math_max( 0, steps ) ) - 1, droop )
        end
    end

    if switchdir > 0 then
        xs[count + 1], ys[count + 1], zs[count + 1] = xs[1], ys[1], zs[1]
        if tension > 0 then
            count = count + bisect( xs, ys, zs, count, droop )
        end
    else
        local x0, y0, z0 = xs[count], ys[count], zs[count]
        local dx, dy, dz = xs[1] - x0, ys[1] - y0, zs[1] - z0

        local splitcount = trackrootscount - 1
        local splitdroop = tension * ( trackrootscount - 2 ) * 2
        local splitcfold = 1 / splitcount
        local splitsteps = 180 * splitcfold

        for n = 1, splitcount - 1 do
            local f = n * splitcfold
            local root0 = trackroots[splitcount - n + 1][1]
            local nextz = z0 + dz * f - math_sin( splitsteps * n * math_rad ) * splitdroop
            local diffz = nextz - root0[i].z
            local radius = root0.trackRadius

            if diffz < radius then
                nextz = nextz + ( radius - diffz )
            end

            count = count + 1
            xs[count], ys[count], zs[count] = x0 + dx * f, y0 + dy * f, nextz
        end
    end

    path.count = count

    local lens = path.len
    local total = 0
    for k = 1, count do
        local j = k == count and 1 or k + 1
        local dx, dy, dz = xs[j] - xs[k], ys[j] - ys[k], zs[j] - zs[k]
        local len = math_sqrt( dx * dx + dy * dy + dz * dz )
        lens[k] = len
        total = total + len
    end

    path.total = total
end

-- spreads the bones evenly along the path so the texture never stretches
local function placeBones( side, path )
    local xs, ys, zs, lens = path.x, path.y, path.z, path.len
    local count = path.count
    local nodes = side.nodes
    local nx, ny, nz = side.x, side.y, side.z
    local step = path.total / nodes

    local k, acc = 1, 0
    for n = 0, nodes - 1 do
        local s = n * step
        while k < count and acc + lens[k] < s do
            acc = acc + lens[k]
            k = k + 1
        end

        local len = lens[k]
        local f = len > 0 and math_min( 1, ( s - acc ) / len ) or 0
        local j = k == count and 1 or k + 1

        nx[n] = xs[k] + ( xs[j] - xs[k] ) * f
        ny[n] = ys[k] + ( ys[j] - ys[k] ) * f
        nz[n] = zs[k] + ( zs[j] - zs[k] ) * f
    end

    local matrices = side.matrices
    for n = 0, nodes - 1 do
        local prev = n == 0 and nodes - 1 or n - 1
        local next = n == nodes - 1 and 0 or n + 1

        local dx, dz = nx[next] - nx[prev], nz[next] - nz[prev]
        local len = math_sqrt( dx * dx + dz * dz )

        if len > 0 then
            local c, s = dx / len, -dz / len
            matrices[n]:SetUnpacked(
                c, 0, s, nx[n],
                0, 1, 0, ny[n],
                -s, 0, c, nz[n],
                0, 0, 0, 1
            )
        end
    end
end


--
local normal_up = Vector( 0, 0, 1 )
local normal_dn = Vector( 0, 0, -1 )
local normal_ri = Vector( 0, -1, 0 )

-- { model vertex a, u at a, model vertex b, u at b, normal }, matching the quads autotracks.render draws
local trackquads = {
    { 3, 0.143, 1, 0, normal_up },
    { 2, 1, 4, 0.857, normal_up },
    { 4, 0.857, 3, 0.143, normal_up },
    { 1, 0, 5, 0.143, normal_dn },
    { 6, 0.857, 2, 1, normal_dn },
    { 5, 0.143, 6, 0.857, normal_dn },
    { 7, 0.143, 8, 0, normal_ri },
}
local grouserquad = { 1, 0.041, 9, 0, normal_up }

local function vertex( pos, bone, u, v, normal )
    mesh_Position( pos )
    mesh_Normal( normal )
    mesh_TexCoord( 0, u, v )
    mesh_Color( 255, 255, 255, 255 )
    mesh_BoneData( 0, bone, 1 )
    mesh_BoneData( 1, bone, 0 )
    mesh_AdvanceVertex()
end

local function buildMeshes( side, model, material, step, texmap )
    local quads = { unpack( trackquads ) }
    if #model == 9 then quads[#quads + 1] = grouserquad end

    local quadcount = #quads
    local nodes = side.nodes
    local segments = bones_per_mesh - 1

    for first = 0, nodes - 1, segments do
        local last = math_min( first + segments, nodes )

        local bones = {}
        for n = first, last do
            bones[#bones + 1] = side.matrices[n % nodes]
        end

        local imesh = Mesh( material, 2 )
        mesh_Begin( imesh, MATERIAL_TRIANGLES, ( last - first ) * quadcount * 2 )

        for n = first, last - 1 do
            local this, next = n - first + 1, n - first + 2
            local v0, v1 = -n * step * texmap, -( n + 1 ) * step * texmap

            for q = 1, quadcount do
                local quad = quads[q]
                local a, ua, b, ub, normal = model[quad[1]], quad[2], model[quad[3]], quad[4], quad[5]

                vertex( a, next, ua, v1, normal )
                vertex( a, this, ua, v0, normal )
                vertex( b, this, ub, v0, normal )

                vertex( a, next, ua, v1, normal )
                vertex( b, this, ub, v0, normal )
                vertex( b, next, ub, v1, normal )
            end
        end

        mesh_End()

        side.meshes[#side.meshes + 1] = imesh
        side.bones[#side.bones + 1] = bones
    end
end

local function destroy( self )
    local skin = self.autotracks_skin
    if not skin then return end

    for i = 1, #skin do
        local meshes = skin[i].meshes
        for m = 1, #meshes do
            meshes[m]:Destroy()
        end
    end

    self.autotracks_skin = nil
end

local function isBuilt( self, detail, paths )
    local skin = self.autotracks_skin
    if not skin or self.autotracks_skin_dirty or skin.detail ~= detail then return false end

    for i = 1, #skin do
        local side = skin[i]
        local first = side.meshes[1]
        if not first or not first:IsValid() then return false end

        local ratio = paths[i].total / side.total
        if ratio < 0.8 or ratio > 1.25 then return false end
    end

    return true
end

local function build( self, detail, paths )
    destroy( self )

    local skin = { detail = detail }

    local radius = math.huge
    local trackroots = self.tanktracktool_modeData.parts
    for i = 1, #trackroots do
        radius = math_min( radius, math_abs( trackroots[i][1].trackRadius ) )
    end

    -- keep the chords along the smallest wheel within a fraction of a unit of its curve
    local spacing = math_Clamp( math_sqrt( 8 * math_max( radius, 0.5 ) * ( 0.4 / detail ) ), 0.25, 12 )

    for i = 1, #paths do
        local path = paths[i]
        local nodes = math_Clamp( math_ceil( path.total / spacing ), 8, 2048 )

        local side = { nodes = nodes, total = path.total, x = {}, y = {}, z = {}, matrices = {}, meshes = {}, bones = {} }
        for n = 0, nodes - 1 do
            side.matrices[n] = Matrix()
        end

        placeBones( side, path )
        buildMeshes( side, i == 2 and self.autotracks_data_model_ri or self.autotracks_data_model_le, self.autotracks_data_texture, path.total / nodes, self.autotracks_data_texturemap )

        skin[i] = side
    end

    self.autotracks_skin = skin
    self.autotracks_skin_dirty = nil

    if self.CallOnRemove then
        self:CallOnRemove( "tanktracktool_autotracks_skin", function( ent )
            timer.Simple( 0, function()
                if IsValid( ent ) then ent.autotracks_skin_dirty = true return end
                destroy( ent )
            end )
        end )
    end
end


--
function skinned.setup( self )
    legacy.setup( self )
    self.autotracks_skin_dirty = true
    self.autotracks_skin_paths = self.autotracks_skin_paths or {}
end

function skinned.think( self )
    if not supported or not cv_sk:GetBool() then
        destroy( self )
        return legacy.think( self )
    end

    local isdouble = self.autotracks_isdouble and 2 or 1

    if isdouble == 2 then
        self.autotracks_ri_lastrot = self.autotracks_ri_lastrot - self.autotracks_ri_lastvel / self.autotracks_data_textureres
    end
    self.autotracks_le_lastrot = self.autotracks_le_lastrot - self.autotracks_le_lastvel / self.autotracks_data_textureres

    local detail = cv_md:GetInt()
    local paths = self.autotracks_skin_paths
    for i = 1, isdouble do
        local path = paths[i]
        if not path then
            path = { x = {}, y = {}, z = {}, len = {} }
            paths[i] = path
        end
        buildPath( self, i, detail, path )
    end
    for i = isdouble + 1, #paths do paths[i] = nil end

    if not isBuilt( self, detail, paths ) then
        build( self, detail, paths )
    else
        local skin = self.autotracks_skin
        for i = 1, isdouble do
            placeBones( skin[i], paths[i] )
        end
    end

    self.autotracks_data_ready = true
end

local scroll = Vector()
local scale = Vector( 1, 1, 1 )
local reset_scroll = Vector()
local reset_scale = Vector( 1, 1, 1 )

function skinned.render( self, matrix )
    local skin = self.autotracks_skin
    if not skin then return legacy.render( self, matrix ) end
    if not self.autotracks_data_ready then return end

    cam.PushModelMatrix( matrix or self:GetWorldTransformMatrix() )

    local texture = self.autotracks_data_texture
    if self.autotracks_data_color then
        texture:SetVector( "$color2", self.autotracks_data_color )
    end

    local paths = self.autotracks_skin_paths

    for i = 1, #skin do
        local side = skin[i]

        scroll.y = ( i == 2 and self.autotracks_ri_lastrot or self.autotracks_le_lastrot ) or 0
        scale.y = paths[i].total / side.total

        texture:SetVector( "$translate", scroll )
        texture:SetVector( "$newscale", scale )
        render_SetMaterial( texture )

        local meshes, bones = side.meshes, side.bones
        for m = 1, #meshes do
            meshes[m]:DrawSkinned( bones[m], true )
        end
    end

    texture:SetVector( "$translate", reset_scroll )
    texture:SetVector( "$newscale", reset_scale )

    render_SetColorModulation( 1, 1, 1 )
    cam.PopModelMatrix()
end

autotracks.setup = skinned.setup
autotracks.think = skinned.think
autotracks.render = skinned.render
