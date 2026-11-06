
local math_abs, math_cos, math_sin, math_pi = math.abs, math.cos, math.sin, math.pi

local probe = {}

local function intersect( tri, ox, oy, oz, dx, dy, dz )
    local a, b, c = tri[1], tri[2], tri[3]
    local e1x, e1y, e1z = b.x - a.x, b.y - a.y, b.z - a.z
    local e2x, e2y, e2z = c.x - a.x, c.y - a.y, c.z - a.z

    local px, py, pz = dy * e2z - dz * e2y, dz * e2x - dx * e2z, dx * e2y - dy * e2x
    local det = e1x * px + e1y * py + e1z * pz
    if math_abs( det ) < 1e-12 then return end

    local inv = 1 / det
    local sx, sy, sz = ox - a.x, oy - a.y, oz - a.z
    local u = ( sx * px + sy * py + sz * pz ) * inv
    if u < -1e-7 or u > 1 + 1e-7 then return end

    local qx, qy, qz = sy * e1z - sz * e1y, sz * e1x - sx * e1z, sx * e1y - sy * e1x
    local v = ( dx * qx + dy * qy + dz * qz ) * inv
    if v < -1e-7 or u + v > 1 + 1e-7 then return end

    local t = ( e2x * qx + e2y * qy + e2z * qz ) * inv
    if t < 1e-6 then return end

    return t, u, v
end

function probe.slab( frame, y )
    frame.slabs = frame.slabs or {}
    if frame.slabs[y] then return frame.slabs[y] end

    local tris = {}
    for _, tri in ipairs( frame.tris ) do
        local a, b, c = tri[1].y, tri[2].y, tri[3].y
        if math.min( a, b, c ) <= y + 1e-4 and math.max( a, b, c ) >= y - 1e-4 then tris[#tris + 1] = tri end
    end

    frame.slabs[y] = { tris = tris }
    return frame.slabs[y]
end

local function bounds( tri )
    if tri.minx then return tri end
    local a, b, c = tri[1], tri[2], tri[3]
    tri.minx, tri.maxx = math.min( a.x, b.x, c.x ), math.max( a.x, b.x, c.x )
    tri.minz, tri.maxz = math.min( a.z, b.z, c.z ), math.max( a.z, b.z, c.z )
    return tri
end

function probe.column( frame, x, y )
    local slab = probe.slab( frame, y )
    if not slab.grid then
        local grid = {}
        for _, tri in ipairs( slab.tris ) do
            bounds( tri )
            for cell = math.floor( tri.minx / 2 ), math.floor( tri.maxx / 2 ) do
                grid[cell] = grid[cell] or {}
                table.insert( grid[cell], tri )
            end
        end
        slab.grid = grid
    end
    return slab.grid[math.floor( x / 2 )] or {}
end

function probe.near( frame, origin, dist )
    local tris = {}
    for _, tri in ipairs( probe.slab( frame, origin.y ).tris ) do
        bounds( tri )
        if tri.minx <= origin.x + dist and tri.maxx >= origin.x - dist and tri.minz <= origin.z + dist and tri.maxz >= origin.z - dist then
            tris[#tris + 1] = tri
        end
    end
    return { tris = tris }
end

function probe.cast( frame, origin, dir, maxdist )
    dir = dir:GetNormalized()
    local ox, oy, oz = origin.x, origin.y, origin.z
    local dx, dy, dz = dir.x, dir.y, dir.z

    local hits = {}
    local tris
    if dx == 0 and dy == 0 then
        tris = probe.column( frame, ox, oy )
    elseif dy == 0 then
        tris = probe.slab( frame, oy ).tris
    else
        tris = frame.tris
    end
    for i = 1, #tris do
        local tri = tris[i]
        local t, u, v = intersect( tri, ox, oy, oz, dx, dy, dz )
        if t and ( not maxdist or t <= maxdist ) then
            local w = 1 - u - v
            local a, b, c = tri[1], tri[2], tri[3]
            hits[#hits + 1] = {
                t = t,
                pos = Vector( ox + dx * t, oy + dy * t, oz + dz * t ),
                u = w * a.u + u * b.u + v * c.u,
                v = w * a.v + u * b.v + v * c.v,
                tri = tri,
            }
        end
    end

    table.sort( hits, function( a, b ) return a.t < b.t end )

    local merged = {}
    for i = 1, #hits do
        local last = merged[#merged]
        if not last or hits[i].t - last.t > 1e-3 then merged[#merged + 1] = hits[i] end
    end

    return merged
end

function probe.first( frame, origin, dir, maxdist )
    return probe.cast( frame, origin, dir, maxdist )[1]
end

function probe.clearance( frame, center, yoffset, maxdist, steps )
    steps = steps or 72
    local origin = Vector( center.x, center.y + ( yoffset or 0 ), center.z )
    if maxdist then frame = probe.near( frame, origin, maxdist ) end
    local best
    for i = 0, steps - 1 do
        local a = ( i / steps ) * math_pi * 2
        local hit = probe.first( frame, origin, Vector( math_cos( a ), 0, math_sin( a ) ), maxdist )
        if hit and ( not best or hit.t < best ) then best = hit.t end
    end
    return best
end

function probe.extents( frame, filter )
    local mins, maxs
    for _, tri in ipairs( frame.tris ) do
        for k = 1, 3 do
            local p = tri[k]
            if not filter or filter( p ) then
                if not mins then
                    mins, maxs = Vector( p.x, p.y, p.z ), Vector( p.x, p.y, p.z )
                else
                    mins.x, mins.y, mins.z = math.min( mins.x, p.x ), math.min( mins.y, p.y ), math.min( mins.z, p.z )
                    maxs.x, maxs.y, maxs.z = math.max( maxs.x, p.x ), math.max( maxs.y, p.y ), math.max( maxs.z, p.z )
                end
            end
        end
    end
    return mins, maxs
end

function probe.wrap( d )
    return ( d + 0.5 ) % 1 - 0.5
end

-- texture coordinates per unit of surface between two rays, signed along a -> b
function probe.density( frame, a, b, dir )
    local ha, hb = probe.first( frame, a, dir ), probe.first( frame, b, dir )
    if not ha or not hb then return end
    return probe.wrap( hb.v - ha.v ) / ha.pos:Distance( hb.pos ), ha, hb
end

-- the top or bottom surface height of the track at x, found by casting a vertical ray
function probe.height( frame, x, y, fromAbove )
    local hit = fromAbove and probe.first( frame, Vector( x, y, 1000 ), Vector( 0, 0, -1 ) ) or probe.first( frame, Vector( x, y, -1000 ), Vector( 0, 0, 1 ) )
    return hit and hit.pos.z, hit
end

return probe
