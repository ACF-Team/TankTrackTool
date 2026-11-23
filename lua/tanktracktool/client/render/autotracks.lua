
--
local math, mesh, render, cam, table, string =
      math, mesh, render, cam, table, string

local Vector, Matrix, Mesh, IsValid =
      Vector, Matrix, Mesh, IsValid

local table_insert = table.insert

local mesh_Begin, mesh_End, mesh_Position, mesh_TexCoord, mesh_Normal, mesh_Color, mesh_BoneData, mesh_AdvanceVertex =
      mesh.Begin, mesh.End, mesh.Position, mesh.TexCoord, mesh.Normal, mesh.Color, mesh.BoneData, mesh.AdvanceVertex

local render_SetMaterial, render_SetColorModulation =
      render.SetMaterial, render.SetColorModulation

local math_sqrt, math_sin, math_cos, math_atan2, math_floor, math_ceil, math_abs, math_max, math_min, math_Round, math_Clamp =
      math.sqrt, math.sin, math.cos, math.atan2, math.floor, math.ceil, math.abs, math.max, math.min, math.Round, math.Clamp

local math_rad = math.pi / 180
local math_deg = 180 / math.pi

local cv_md = CreateClientConVar( "tanktracktool_autotracks_detail_max", "8", true, false, "maximum track render quality", 4, 16 )

local tanktracktool = tanktracktool
tanktracktool.autotracks = tanktracktool.autotracks or {}

local autotracks = tanktracktool.autotracks

function autotracks.textureList()
    local ret = {}
    for k, v in SortedPairs( file.Find( string.format( "materials/%s/*.vtf", "tanktracktool/autotracks/" ), "GAME" ) ) do
        local name = string.StripExtension( string.GetFileFromFilename( v ) )
        ret[name] = k
    end
    return ret
end

local cv_ds = CreateClientConVar( "tanktracktool_autotracks_disable", "0", true, false, "disable rendering" )
tanktracktool.disable_autotracks = cv_ds:GetBool()

cvars.AddChangeCallback( "tanktracktool_autotracks_disable", function( convar_name, value_old, value_new )
    tanktracktool.disable_autotracks = tobool( value_new )
end )


--
local function grouser( y, z, side, yedge )
    local dir = Vector( 0, y * 0.5, 0 ) - Vector( 0, y * 0.375, z * 0.125 )
    dir:Normalize()
    dir = dir * ( yedge * y ) * side
    dir = dir + Vector( 0, y * 0.5, 0 )
    return dir
end

local trackverts_model = function( y, z, side, yguide, zguide, yedge )
    y = y * side

    local model = {
        -- edge
        Vector( 0, y * 0.5, 0 ),
        Vector( 0, -y * 0.5, 0 ),

        -- top mid
        Vector( 0, y * 0.375, z * 0.5 ),
        Vector( 0, -y * 0.375, z * 0.5 ),

        -- bot mid
        Vector( 0, y * 0.375, -z * 0.5 ),
        Vector( 0, -y * 0.375, -z * 0.5 ),

        -- guide
        Vector( 0, y * yguide * 0.375, z * 0.5 ),
        Vector( 0, y * yguide * 0.375, -z * zguide ),
     }

    if yedge ~= 0 then
        table.insert( model, grouser( y, z, side, yedge ) )
    end

    return model
end

local track_textures = {}
local function createTrackTexture( path )
    local folders = { "tanktracktool/autotracks/" }
    local diffuse

    for k, v in pairs( folders ) do
        local check = v .. path
        if track_textures[check] then
            return track_textures[check]
        end
        if file.Exists( string.format( "materials/%s.vtf", check ), "GAME" ) then
            path = check
            diffuse = string.format( "%s.vtf", check )
            break
        end
    end

    if not diffuse then
        diffuse = "hunter/myplastic"
    end

    local shader = {
        ["$basetexture"]         = diffuse,
        ["$alphatest"]           = "1",
        ["$nocull"]              = "1",
        ["$color2"]              = "[1 1 1]",
        ["$vertexcolor"]         = "1",
        ["$angle"]               = "0",
        ["$translate"]           = "[0.0 0.0 0.0]",
        ["$center"]              = "[0.0 0.0 0.0]",
        ["$newscale"]            = "[1.0 1.0 1.0]",
        ["Proxies"]              = {
            ["TextureTransform"] = {
                ["translateVar"] = "$translate",
                ["scaleVar"]     = "$newscale",
                ["rotateVar"]    = "$angle",
                ["centerVar"]    = "$center",
                ["resultVar"]    = "$basetexturetransform",
             },
         }
     }

    track_textures[path] = CreateMaterial( "ttctracks" .. path .. SysTime(), "VertexLitGeneric", shader )

    return track_textures[path]
end


--
local bones_per_mesh = 51

local function bisect( xs, ys, zs, index, droop )
    if index < 1 then return 0 end
    table_insert( xs, index + 1, ( xs[index] + xs[index + 1] ) * 0.5 )
    table_insert( ys, index + 1, ( ys[index] + ys[index + 1] ) * 0.5 )
    table_insert( zs, index + 1, ( zs[index] + zs[index + 1] ) * 0.5 - droop )
    return 1
end

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
        elseif atan2 < atan0 then -- raised wheels dont fold the track back on itself
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

    for k = #xs, count + 1, -1 do
        xs[k], ys[k], zs[k] = nil, nil, nil
    end

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

-- { model vertex a, u at a, model vertex b, u at b, normal }
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
    local spacing = math_Clamp( math_sqrt( 8 * math_max( radius, 0.5 ) * ( 0.8 / detail ) ), 0.25, 12 )

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


-- bones are local to the track, so they only need moving when a wheel moves relative to it
local function wheelsMoved( self, isdouble )
    local last = self.autotracks_skin_last
    local trackroots = self.tanktracktool_modeData.parts

    local moved = #last ~= isdouble * #trackroots * 3
    if not moved then
        local k = 0
        for i = 1, isdouble do
            for r = 1, #trackroots do
                local x, y, z = trackroots[r][1][i]:Unpack()
                if math_abs( last[k + 1] - x ) > 0.001 or math_abs( last[k + 2] - y ) > 0.001 or math_abs( last[k + 3] - z ) > 0.001 then
                    moved = true
                    break
                end
                k = k + 3
            end
            if moved then break end
        end
    end

    if moved then
        local k = 0
        for i = 1, isdouble do
            for r = 1, #trackroots do
                last[k + 1], last[k + 2], last[k + 3] = trackroots[r][1][i]:Unpack()
                k = k + 3
            end
        end
        for n = k + 1, #last do last[n] = nil end
    end

    return moved
end


--
function autotracks.setup( self )
    local values = self.autotracks_trackvalues

    local color = string.ToColor( values.trackColor )
    self.autotracks_data_color = Vector( color.r / 255, color.g / 255, color.b / 255 )

    self.autotracks_data_texture = createTrackTexture( values.trackMaterial )
    self.autotracks_data_textureres = values.trackRes * values.trackWidth
    self.autotracks_data_texturemap = 1 / self.autotracks_data_textureres

    self.autotracks_data_tension = 1 - values.trackTension

    local side = 1
    if values.trackFlip ~= nil then
        if values.trackFlip ~= 0 then side = -1 else side = 1 end
    end

    self.autotracks_data_model_le = trackverts_model( values.trackWidth, values.trackHeight, side, values.trackGuideY, values.trackGuideZ, values.trackGrouser )
    self.autotracks_data_model_ri = trackverts_model( values.trackWidth, values.trackHeight, -side, values.trackGuideY, values.trackGuideZ, values.trackGrouser )

    local trackHeight = values.trackHeight * 0.5
    for i = 1, #self.tanktracktool_modeData.parts do
        local part = self.tanktracktool_modeData.parts[i][1]

        local trackRadius = part.radius + trackHeight
        part.trackRadius = trackRadius
        part.trackHeight = trackRadius + trackHeight + 0.1
    end

    self.autotracks_data_ready = nil

    self.autotracks_skin_dirty = true
    self.autotracks_skin_paths = self.autotracks_skin_paths or {}
    self.autotracks_skin_last = {}
end


--
function autotracks.think( self )
    local isdouble = self.autotracks_isdouble and 2 or 1

    if isdouble == 2 then
        self.autotracks_ri_lastrot = self.autotracks_ri_lastrot - self.autotracks_ri_lastvel / self.autotracks_data_textureres
    end
    self.autotracks_le_lastrot = self.autotracks_le_lastrot - self.autotracks_le_lastvel / self.autotracks_data_textureres

    local detail = cv_md:GetInt()
    local skin = self.autotracks_skin

    if not wheelsMoved( self, isdouble ) and skin and not self.autotracks_skin_dirty and skin.detail == detail and #skin == isdouble then
        self.autotracks_data_ready = true
        return
    end

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
        for i = 1, isdouble do
            placeBones( skin[i], paths[i] )
        end
    end

    self.autotracks_data_ready = true
end


--
local scroll = Vector()
local scale = Vector( 1, 1, 1 )
local reset_scroll = Vector()
local reset_scale = Vector( 1, 1, 1 )

function autotracks.render( self, matrix )
    local skin = self.autotracks_skin
    if not skin or not self.autotracks_data_ready then return end

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
