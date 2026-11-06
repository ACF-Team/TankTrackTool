
local enums = {
    MATERIAL_POINTS = 0,
    MATERIAL_LINES = 1,
    MATERIAL_TRIANGLES = 2,
    MATERIAL_TRIANGLE_STRIP = 3,
    MATERIAL_LINE_STRIP = 4,
    MATERIAL_LINE_LOOP = 5,
    MATERIAL_POLYGON = 6,
    MATERIAL_QUADS = 7,
}

local function noop() end

local function parseVector( value )
    if isvector( value ) then return Vector( value ) end
    if isstring( value ) then
        local n = {}
        for s in string.gmatch( value, "[%-%d%.eE]+" ) do n[#n + 1] = tonumber( s ) or 0 end
        return Vector( n[1] or 0, n[2] or n[1] or 0, n[3] or n[1] or 0 )
    end
    if isnumber( value ) then return Vector( value, value, value ) end
    return Vector()
end

local function unpackMatrix( m )
    local t = m:ToTable()
    return {
        t[1][1], t[1][2], t[1][3], t[1][4],
        t[2][1], t[2][2], t[2][3], t[2][4],
        t[3][1], t[3][2], t[3][3], t[3][4],
    }
end

local identity = { 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0 }

local function mulMatrix( a, b )
    return {
        a[1] * b[1] + a[2] * b[5] + a[3] * b[9],  a[1] * b[2] + a[2] * b[6] + a[3] * b[10],  a[1] * b[3] + a[2] * b[7] + a[3] * b[11],  a[1] * b[4] + a[2] * b[8] + a[3] * b[12] + a[4],
        a[5] * b[1] + a[6] * b[5] + a[7] * b[9],  a[5] * b[2] + a[6] * b[6] + a[7] * b[10],  a[5] * b[3] + a[6] * b[7] + a[7] * b[11],  a[5] * b[4] + a[6] * b[8] + a[7] * b[12] + a[8],
        a[9] * b[1] + a[10] * b[5] + a[11] * b[9], a[9] * b[2] + a[10] * b[6] + a[11] * b[10], a[9] * b[3] + a[10] * b[7] + a[11] * b[11], a[9] * b[4] + a[10] * b[8] + a[11] * b[12] + a[12],
    }
end

local function transform( m, x, y, z )
    return m[1] * x + m[2] * y + m[3] * z + m[4],
           m[5] * x + m[6] * y + m[7] * z + m[8],
           m[9] * x + m[10] * y + m[11] * z + m[12]
end

local function rotate( m, x, y, z )
    return m[1] * x + m[2] * y + m[3] * z,
           m[5] * x + m[6] * y + m[7] * z,
           m[9] * x + m[10] * y + m[11] * z
end


--[[
    materials
]]
local material_meta = {}
material_meta.__index = material_meta

local function newMaterial( name, shader, params )
    local self = setmetatable( { name = name, shader = shader or "UnlitGeneric", params = {} }, material_meta )
    if params then
        for k, v in pairs( params ) do
            if k == "Proxies" then
                self.proxies = v
            else
                self.params[string.lower( k )] = v
            end
        end
    end
    return self
end

function material_meta:GetName() return self.name end
function material_meta:GetShader() return self.shader end
function material_meta:IsError() return false end
function material_meta:GetKeyValues() return self.params end
function material_meta:SetVector( k, v ) self.params[string.lower( k )] = Vector( v ) end
function material_meta:SetVector4D( k, x, y, z, w ) self.params[string.lower( k )] = { x, y, z, w } end
function material_meta:SetFloat( k, v ) self.params[string.lower( k )] = v end
function material_meta:SetInt( k, v ) self.params[string.lower( k )] = v end
function material_meta:SetString( k, v ) self.params[string.lower( k )] = v end
function material_meta:SetTexture( k, v ) self.params[string.lower( k )] = v end
function material_meta:SetMatrix( k, v ) self.params[string.lower( k )] = Matrix( v ) end
function material_meta:SetUndefined( k ) self.params[string.lower( k )] = nil end
function material_meta:Recompute() end
function material_meta:GetVector( k ) return parseVector( self.params[string.lower( k )] ) end
function material_meta:GetFloat( k ) return tonumber( self.params[string.lower( k )] ) end
function material_meta:GetInt( k ) return math.floor( tonumber( self.params[string.lower( k )] ) or 0 ) end
function material_meta:GetString( k ) local v = self.params[string.lower( k )] return v ~= nil and tostring( v ) or nil end
function material_meta:GetMatrix( k ) local v = self.params[string.lower( k )] return ismatrix( v ) and Matrix( v ) or Matrix() end

function material_meta:getParam( k )
    return self.params[string.lower( k )]
end

function material_meta:textureTransform()
    local proxy = self.proxies and self.proxies.TextureTransform
    if proxy then
        local center = proxy.centerVar and self:GetVector( proxy.centerVar ) or Vector( 0.5, 0.5, 0 )
        local scale = proxy.scaleVar and self.params[string.lower( proxy.scaleVar )] ~= nil and self:GetVector( proxy.scaleVar ) or Vector( 1, 1, 1 )
        local angle = proxy.rotateVar and self:GetFloat( proxy.rotateVar ) or 0
        local translate = proxy.translateVar and self:GetVector( proxy.translateVar ) or Vector()

        local c, s = math.cos( math.rad( angle ) ), math.sin( math.rad( angle ) )
        local cx, cy = center.x, center.y
        local sx, sy = scale.x, scale.y
        local tx, ty = translate.x, translate.y

        return function( u, v )
            local x, y = ( u - cx ) * sx, ( v - cy ) * sy
            return c * x - s * y + cx + tx, s * x + c * y + cy + ty
        end
    end

    local m = self.params["$basetexturetransform"]
    if ismatrix( m ) then
        m = unpackMatrix( m )
        return function( u, v )
            return m[1] * u + m[2] * v + m[4], m[5] * u + m[6] * v + m[8]
        end
    end

    return function( u, v ) return u, v end
end


--[[
    backend
]]
local fake = {}
local backend_meta = {}
backend_meta.__index = backend_meta

function fake.new()
    local self = setmetatable( {}, backend_meta )

    self.materials = {}
    self.convars = {}
    self.convar_callbacks = {}
    self.hooks = {}
    self.matrix_stack = { identity }
    self.material = nil
    self.building = nil
    self.drawing = nil

    self:resetStats()
    self:buildEnv()

    return self
end

function backend_meta:resetStats()
    self.stats = { meshes = 0, destroyed = 0, begins = 0, vertices = 0, draws = 0, skinned_draws = 0, overflows = 0 }
end

function backend_meta:modelMatrix()
    return self.matrix_stack[#self.matrix_stack]
end

function backend_meta:capture( fn )
    local frame = { tris = {}, draws = {} }
    local prev = self.drawing
    self.drawing = frame
    local ok, err = pcall( fn )
    self.drawing = prev
    if not ok then error( err, 0 ) end
    return frame
end

function backend_meta:emit( tris, bones, multiply )
    self.stats.draws = self.stats.draws + 1
    if bones then self.stats.skinned_draws = self.stats.skinned_draws + 1 end

    local frame = self.drawing
    if not frame then return end

    local material = self.material
    local uvtransform = material and material:textureTransform() or function( u, v ) return u, v end
    local draw = {
        material = material,
        color2 = material and material:getParam( "$color2" ) and material:GetVector( "$color2" ) or nil,
        skinned = bones ~= nil,
    }
    frame.draws[#frame.draws + 1] = draw

    local model = self:modelMatrix()
    local slots
    if bones then
        slots = {}
        for i = 1, 52 do
            local b = bones[i]
            if b then
                b = unpackMatrix( b )
                slots[i] = multiply and mulMatrix( model, b ) or b
            else
                slots[i] = multiply and model or identity
            end
        end
    end

    local function place( vert )
        local x, y, z = vert.pos.x, vert.pos.y, vert.pos.z
        local nx, ny, nz = vert.normal.x, vert.normal.y, vert.normal.z
        if not slots then
            local px, py, pz = transform( model, x, y, z )
            local qx, qy, qz = rotate( model, nx, ny, nz )
            return px, py, pz, qx, qy, qz
        end

        local px, py, pz, qx, qy, qz = 0, 0, 0, 0, 0, 0
        local rest = 1
        for s = 1, 2 do
            local b = vert.bones[s]
            if b.weight > 0 then
                local m = b.id == 0 and model or slots[b.id]
                local ax, ay, az = transform( m, x, y, z )
                local bx, by, bz = rotate( m, nx, ny, nz )
                px, py, pz = px + ax * b.weight, py + ay * b.weight, pz + az * b.weight
                qx, qy, qz = qx + bx * b.weight, qy + by * b.weight, qz + bz * b.weight
                rest = rest - b.weight
            end
        end
        if rest > 1e-6 then
            local ax, ay, az = transform( model, x, y, z )
            local bx, by, bz = rotate( model, nx, ny, nz )
            px, py, pz = px + ax * rest, py + ay * rest, pz + az * rest
            qx, qy, qz = qx + bx * rest, qy + by * rest, qz + bz * rest
        end
        return px, py, pz, qx, qy, qz
    end

    local out = frame.tris
    for i = 1, #tris do
        local tri = tris[i]
        local t = { draw = draw }
        for k = 1, 3 do
            local vert = tri[k]
            local px, py, pz, qx, qy, qz = place( vert )
            local u, v = uvtransform( vert.u, vert.v )
            t[k] = { x = px, y = py, z = pz, nx = qx, ny = qy, nz = qz, u = u, v = v, color = vert.color }
        end
        out[#out + 1] = t
    end
end

local function triangulate( prim, verts )
    local tris = {}
    if prim == enums.MATERIAL_TRIANGLES then
        for i = 1, #verts - 2, 3 do tris[#tris + 1] = { verts[i], verts[i + 1], verts[i + 2] } end
    elseif prim == enums.MATERIAL_QUADS then
        for i = 1, #verts - 3, 4 do
            tris[#tris + 1] = { verts[i], verts[i + 1], verts[i + 2] }
            tris[#tris + 1] = { verts[i], verts[i + 2], verts[i + 3] }
        end
    elseif prim == enums.MATERIAL_TRIANGLE_STRIP then
        for i = 1, #verts - 2 do
            if i % 2 == 1 then
                tris[#tris + 1] = { verts[i], verts[i + 1], verts[i + 2] }
            else
                tris[#tris + 1] = { verts[i + 1], verts[i], verts[i + 2] }
            end
        end
    elseif prim == enums.MATERIAL_POLYGON then
        for i = 2, #verts - 1 do tris[#tris + 1] = { verts[1], verts[i], verts[i + 1] } end
    end
    return tris
end

local primitive_size = {
    [enums.MATERIAL_TRIANGLES] = function( n ) return n * 3 end,
    [enums.MATERIAL_QUADS] = function( n ) return n * 4 end,
    [enums.MATERIAL_TRIANGLE_STRIP] = function( n ) return n + 2 end,
    [enums.MATERIAL_POLYGON] = function( n ) return n end,
}

local function newVertex()
    return {
        pos = Vector(), normal = Vector(), u = 0, v = 0, color = { 255, 255, 255, 255 },
        bones = { { id = 0, weight = 0 }, { id = 0, weight = 0 } },
    }
end

function backend_meta:buildEnv()
    local backend = self
    local stats = function() return backend.stats end

    --
    local imesh_meta = {}
    imesh_meta.__index = imesh_meta

    function imesh_meta:IsValid() return not self.destroyed end
    function imesh_meta:Destroy()
        if not self.destroyed then stats().destroyed = stats().destroyed + 1 end
        self.destroyed = true
    end
    function imesh_meta:Draw()
        if self.destroyed then error( "Tried to use a NULL IMesh!", 2 ) end
        if self.skinned then error( "Trying to render skinned mesh without skinning!", 2 ) end
        backend:emit( self.tris )
    end
    function imesh_meta:DrawSkinned( bones, multiply )
        if self.destroyed then error( "Tried to use a NULL IMesh!", 2 ) end
        if not self.skinned then return backend:emit( self.tris ) end
        if not istable( bones ) then error( "bad argument #1 to 'DrawSkinned' (table expected)", 2 ) end
        if bones[52] ~= nil then error( "Too many model transform matrices! (53 max)", 2 ) end
        backend:emit( self.tris, bones, multiply )
    end
    function imesh_meta:BuildFromTriangles( verts )
        local list = {}
        for i = 1, #verts do
            local v = verts[i]
            local vert = newVertex()
            vert.pos = Vector( v.pos )
            vert.normal = v.normal and Vector( v.normal ) or Vector()
            vert.u, vert.v = v.u or 0, v.v or 0
            list[i] = vert
        end
        self.tris = triangulate( enums.MATERIAL_TRIANGLES, list )
    end

    local function Mesh( mat, boneWeights )
        stats().meshes = stats().meshes + 1
        return setmetatable( { tris = {}, skinned = ( boneWeights or 0 ) > 0, material = mat }, imesh_meta )
    end

    --
    local mesh = {}

    function mesh.Begin( a, b, c )
        if backend.building then error( "mesh.Begin called while already building", 2 ) end
        stats().begins = stats().begins + 1
        local build = { verts = {}, cur = newVertex() }
        if getmetatable( a ) == imesh_meta then
            build.imesh, build.prim, build.count = a, b, c
        else
            build.prim, build.count = a, b
        end
        backend.building = build
    end
    function mesh.Position( x, y, z )
        local b = backend.building
        if not b then error( "mesh.Position called outside mesh.Begin", 2 ) end
        if isvector( x ) then b.cur.pos = Vector( x ) else b.cur.pos = Vector( x, y, z ) end
    end
    function mesh.Normal( x, y, z )
        local b = backend.building
        if isvector( x ) then b.cur.normal = Vector( x ) else b.cur.normal = Vector( x, y, z ) end
    end
    function mesh.TexCoord( stage, u, v )
        local b = backend.building
        if stage == 0 then b.cur.u, b.cur.v = u, v end
    end
    function mesh.Color( r, g, b2, a )
        backend.building.cur.color = { r, g, b2, a }
    end
    function mesh.BoneData( slot, id, weight )
        local b = backend.building
        if not b then error( "cannot call mesh.BoneData if no mesh was started using mesh.Begin", 2 ) end
        if slot ~= 0 and slot ~= 1 then error( "Invalid bone matrix index. Must be integer [0,1]", 2 ) end
        if id < 0 or id > 52 or id % 1 ~= 0 then error( "Invalid bone matrix bone. Must be integer [1,52]", 2 ) end
        if weight < 0 or weight > 1 then error( "Invalid bone matrix weight. Must be float [0,1]", 2 ) end
        b.cur.bones[slot + 1] = { id = id, weight = weight }
    end
    mesh.UserData = noop
    mesh.TangentS = noop
    mesh.TangentT = noop
    mesh.Specular = noop
    function mesh.AdvanceVertex()
        local b = backend.building
        if not b then error( "mesh.AdvanceVertex called outside mesh.Begin", 2 ) end
        stats().vertices = stats().vertices + 1
        local cur = b.cur
        b.verts[#b.verts + 1] = cur
        b.cur = {
            pos = Vector( cur.pos ), normal = Vector( cur.normal ), u = cur.u, v = cur.v, color = cur.color,
            bones = { { id = 0, weight = 0 }, { id = 0, weight = 0 } },
        }
    end
    function mesh.End()
        local b = backend.building
        if not b then error( "mesh.End called outside mesh.Begin", 2 ) end
        backend.building = nil

        local size = primitive_size[b.prim]
        if size and b.count and #b.verts > size( b.count ) then
            stats().overflows = stats().overflows + 1
        end

        local tris = triangulate( b.prim, b.verts )
        if b.imesh then
            b.imesh.tris = tris
        else
            backend:emit( tris )
        end
    end

    --
    local render = setmetatable( {}, { __index = function() return noop end } )

    function render.SetMaterial( mat ) backend.material = mat end
    function render.MaterialOverride( mat ) end
    function render.GetColorModulation() return 1, 1, 1 end
    function render.GetBlend() return 1 end

    local cam = setmetatable( {}, { __index = function() return noop end } )

    function cam.PushModelMatrix( m, multiply )
        local top = unpackMatrix( m )
        if multiply then top = mulMatrix( backend:modelMatrix(), top ) end
        backend.matrix_stack[#backend.matrix_stack + 1] = top
    end
    function cam.PopModelMatrix()
        if #backend.matrix_stack == 1 then error( "cam.PopModelMatrix called without a matching push", 2 ) end
        backend.matrix_stack[#backend.matrix_stack] = nil
    end
    function cam.GetModelMatrix()
        local m = backend:modelMatrix()
        return Matrix( {
            { m[1], m[2], m[3], m[4] },
            { m[5], m[6], m[7], m[8] },
            { m[9], m[10], m[11], m[12] },
            { 0, 0, 0, 1 },
        } )
    end

    --
    local convar_meta = {}
    convar_meta.__index = convar_meta

    function convar_meta:GetString() return tostring( self.value ) end
    function convar_meta:GetFloat() return tonumber( self.value ) or 0 end
    function convar_meta:GetInt() return math.floor( tonumber( self.value ) or 0 ) end
    function convar_meta:GetBool() return tobool( self.value ) end
    function convar_meta:GetDefault() return self.default end
    function convar_meta:GetName() return self.name end
    function convar_meta:SetString( v ) backend:setConVar( self.name, v ) end
    function convar_meta:SetInt( v ) backend:setConVar( self.name, v ) end
    function convar_meta:SetFloat( v ) backend:setConVar( self.name, v ) end
    function convar_meta:SetBool( v ) backend:setConVar( self.name, v and 1 or 0 ) end

    local function CreateClientConVar( name, default )
        if not backend.convars[name] then
            backend.convars[name] = setmetatable( { name = name, value = tostring( default ), default = tostring( default ) }, convar_meta )
        end
        return backend.convars[name]
    end

    local cvars = {
        AddChangeCallback = function( name, fn, id )
            backend.convar_callbacks[name] = backend.convar_callbacks[name] or {}
            backend.convar_callbacks[name][id or #backend.convar_callbacks[name] + 1] = fn
        end,
        RemoveChangeCallback = function( name, id )
            if backend.convar_callbacks[name] then backend.convar_callbacks[name][id] = nil end
        end,
        Number = function( name, default ) local c = backend.convars[name] return c and tonumber( c.value ) or default end,
        Bool = function( name, default ) local c = backend.convars[name] if c then return tobool( c.value ) end return default end,
        String = function( name, default ) local c = backend.convars[name] return c and c.value or default end,
    }

    local real_GetConVar = GetConVar
    local function GetConVar( name )
        return backend.convars[name] or real_GetConVar( name )
    end

    --
    local hook = {
        Add = function( event, id, fn ) backend.hooks[event] = backend.hooks[event] or {} backend.hooks[event][id] = fn end,
        Remove = function( event, id ) if backend.hooks[event] then backend.hooks[event][id] = nil end end,
        GetTable = function() return backend.hooks end,
        Run = function( event, ... ) return backend:runHook( event, ... ) end,
        Call = function( event, gm, ... ) return backend:runHook( event, ... ) end,
    }

    local function Material( name )
        if not backend.materials[name] then
            backend.materials[name] = newMaterial( name, "UnlitGeneric" )
        end
        return backend.materials[name]
    end

    local function CreateMaterial( name, shader, params )
        local mat = newMaterial( name, shader, params )
        backend.materials[name] = mat
        return mat
    end

    local env = {
        mesh = mesh,
        Mesh = Mesh,
        render = render,
        cam = cam,
        Material = Material,
        CreateMaterial = CreateMaterial,
        CreateClientConVar = CreateClientConVar,
        GetConVar = GetConVar,
        cvars = cvars,
        hook = hook,
        AddCSLuaFile = noop,
    }
    for k, v in pairs( enums ) do env[k] = v end

    self.imesh_meta = imesh_meta
    self.env = setmetatable( env, { __index = _G } )
end

function backend_meta:setConVar( name, value )
    local c = self.convars[name]
    if not c then return end
    local old = c.value
    c.value = tostring( value )
    for _, fn in pairs( self.convar_callbacks[name] or {} ) do
        fn( name, old, c.value )
    end
end

function backend_meta:runHook( event, ... )
    for _, fn in pairs( self.hooks[event] or {} ) do
        local a, b, c = fn( ... )
        if a ~= nil then return a, b, c end
    end
end

function backend_meta:include( path )
    local fn = CompileFile( path )
    if not isfunction( fn ) then error( "could not compile " .. path, 2 ) end
    setfenv( fn, self.env )
    return fn()
end

function backend_meta:loadTankTrackTool( paths )
    local env = self.env
    env.tanktracktool = {}
    env.include = function( path ) return self:include( path ) end
    for i = 1, #paths do self:include( paths[i] ) end
    return env.tanktracktool
end

return fake
