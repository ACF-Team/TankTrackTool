
local fixtures = include( "tests/tanktracktool/helpers/fixtures.lua" )
local probe = include( "tests/tanktracktool/helpers/probe.lua" )

local function pair( opts )
    local b1, a1 = fixtures.load( { skinned = false } )
    local b2, a2 = fixtures.load()
    return fixtures.track( b1, a1, opts ), fixtures.track( b2, a2, opts )
end

local function each( tracks, fn )
    for _, track in ipairs( tracks ) do fn( track ) end
end

-- how much of the old renderer's output the new one reproduces, sampled with rays over the whole track
local function likeness( legacy, skinned )
    local a, b = legacy:frame(), skinned:frame()
    local width, height = legacy.values.trackWidth, legacy.values.trackHeight
    local total, shape, texture, worst = 0, 0, 0, 0

    local function compare( fa, fb, origin, dir, maxdist )
        local ha, hb = probe.first( fa, origin, dir, maxdist ), probe.first( fb, origin, dir, maxdist )
        if not ha and not hb then return end
        total = total + 1
        if not ha or not hb then return end

        local d = math.abs( ha.t - hb.t )
        worst = math.max( worst, d )
        if d <= 0.15 then shape = shape + 1 end
        if math.abs( probe.wrap( ha.v - hb.v ) ) <= 0.01 and math.abs( ha.u - hb.u ) <= 0.02 then texture = texture + 1 end
    end

    local function runs( y )
        for x = -110, 110, 4 do
            compare( a, b, Vector( x, y, 1000 ), Vector( 0, 0, -1 ) )
            compare( a, b, Vector( x, y, -1000 ), Vector( 0, 0, 1 ) )
        end
    end

    local function around( origin, reach )
        local na, nb = probe.near( a, origin, reach ), probe.near( b, origin, reach )
        for k = 0, 23 do
            local r = ( k / 24 ) * math.pi * 2
            compare( na, nb, origin, Vector( math.cos( r ), 0, math.sin( r ) ), reach )
        end
    end

    for _, side in ipairs( legacy:sides() ) do
        local y = legacy:wheel( 1, side ).y
        for _, offset in ipairs( { 0.3, -0.3, 0.42, -0.42 } ) do
            runs( y + offset * width )
        end

        for i = 1, legacy:count() do
            local center, radius = legacy:wheel( i, side )
            around( center + Vector( 0, 0.3 * width, 0 ), radius + height + 2 )
            around( center - Vector( 0, 0.3 * width, 0 ), radius + height + 2 )
        end
    end

    return shape / total, texture / total, worst
end

local configs = {
    { name = "default" },
    { name = "slack", values = { trackTension = 0 } },
    { name = "no rollers", layout = "norollers" },
    { name = "three rollers", layout = "rollers3" },
    { name = "grousers", values = { trackGrouser = 0.5 } },
    { name = "guide offset", values = { trackGuideY = 0.5, trackGuideZ = 2 } },
    { name = "big track", values = { trackWidth = 40, trackHeight = 6, trackRes = 5 } },
    { name = "flipped", values = { trackFlip = 1 } },
    { name = "suspension", move = { [3] = Vector( 0, 0, 6 ), [5] = Vector( 0, 0, -3 ) } },
    { name = "driving", speed = { 5, -3 } },
}

local function longLayout()
    local wheels = {}
    for i, w in ipairs( fixtures.layouts.default ) do
        wheels[i] = { w[1] * 6, w[2], w[3] }
    end
    return wheels
end

return {
    groupName = "tanktracktool.autotracks skinned",

    beforeEach = function( state )
        state.backend, state.autotracks = fixtures.load()
        state.track = function( opts ) return fixtures.track( state.backend, state.autotracks, opts ) end
    end,

    cases = {
        {
            name = "Looks like the old renderer",
            func = function( state )
                local fails = {}
                for _, config in ipairs( configs ) do
                    local legacy, skinned = pair( config )
                    each( { legacy, skinned }, function( track )
                        track:build()
                        for i, offset in pairs( config.move or {} ) do track:moveWheel( i, offset ) end
                        if config.speed then
                            track:setVelocity( config.speed[1], config.speed[2] )
                            for _ = 1, 3 do track:think() end
                        end
                        track:think()
                    end )

                    local shape, texture, worst = likeness( legacy, skinned )
                    if shape < 0.95 or texture < 0.95 or worst > 1 then
                        fails[#fails + 1] = string.format( "%s: shape %.1f%%, texture %.1f%%, worst %.2f units", config.name, shape * 100, texture * 100, worst )
                    end
                end
                expect( table.concat( fails, "\n" ) ).to.equal( "" )
            end
        },

        {
            name = "Doesn't build anything while driving",
            func = function( state )
                local track = state.track():build()
                track:frame()
                state.backend:resetStats()

                for i = 1, 10 do
                    track:moveWheel( 2 + i % 5, Vector( 0, 0, i % 2 == 0 and 3 or -3 ) )
                    track:setVelocity( i, -i )
                    track:think()
                    track:frame()
                end

                local stats = state.backend.stats
                expect( stats.meshes ).to.equal( 0 )
                expect( stats.begins ).to.equal( 0 )
                expect( stats.vertices ).to.equal( 0 )
                expect( stats.draws ).to.beGreaterThan( 0 )
                expect( stats.skinned_draws ).to.equal( stats.draws )
            end
        },

        {
            name = "Doesn't keep growing in memory while driving",
            func = function( state )
                local track = state.track():build()

                local function drive( frames )
                    for i = 1, frames do
                        track:moveWheel( 4, Vector( 0, 0, i % 2 == 0 and 0.5 or -0.5 ) )
                        track:think()
                    end
                end

                drive( 50 )
                collectgarbage( "collect" )
                collectgarbage( "collect" )
                local before = collectgarbage( "count" )

                drive( 2000 )
                collectgarbage( "collect" )
                collectgarbage( "collect" )

                expect( collectgarbage( "count" ) - before ).to.beLessThan( 64 )
            end
        },

        {
            name = "Rebuilds once after an edit and frees the old meshes",
            func = function( state )
                local track = state.track():build()
                local made = state.backend.stats.meshes
                state.backend:resetStats()

                track:setup()
                track:think()

                expect( state.backend.stats.destroyed ).to.equal( made )
                expect( state.backend.stats.meshes ).to.beGreaterThan( 0 )

                state.backend:resetStats()
                track:think()
                expect( state.backend.stats.meshes ).to.equal( 0 )
            end
        },

        {
            name = "Rebuilds when the detail setting changes",
            func = function( state )
                local track = state.track():build()
                state.backend:resetStats()

                state.backend:setConVar( "tanktracktool_autotracks_detail_max", 12 )
                track:think()
                expect( state.backend.stats.meshes ).to.beGreaterThan( 0 )

                state.backend:resetStats()
                track:think()
                expect( state.backend.stats.meshes ).to.equal( 0 )
            end
        },

        {
            name = "Splits long tracks to stay within the bone limit",
            func = function( state )
                local track = state.track( { wheels = longLayout() } ):build()
                local frame = track:frame()

                expect( #frame.draws ).to.beGreaterThan( 4 )
                expect( track:contactFailures( frame, 0.5 ) ).to.equal( "" )
            end
        },

        {
            name = "Can be switched off for the old renderer",
            func = function( state )
                local track = state.track():build()
                expect( track:frame().draws[1].skinned ).to.beTrue()

                state.backend:setConVar( "tanktracktool_autotracks_skinned", 0 )
                track:think()
                local frame = track:frame()
                expect( frame.draws[1].skinned ).to.beFalse()
                expect( track:contactFailures( frame, 0.5 ) ).to.equal( "" )

                state.backend:setConVar( "tanktracktool_autotracks_skinned", 1 )
                track:think()
                frame = track:frame()
                expect( frame.draws[1].skinned ).to.beTrue()
                expect( track:contactFailures( frame, 0.5 ) ).to.equal( "" )
            end
        },

        {
            name = "Uses the old renderer when the game can't skin meshes",
            func = function()
                local backend, autotracks = fixtures.load( { unsupported = true } )
                local track = fixtures.track( backend, autotracks ):build()
                local frame = track:frame()

                expect( #frame.draws ).to.beGreaterThan( 0 )
                expect( frame.draws[1].skinned ).to.beFalse()
                expect( backend.stats.meshes ).to.equal( 0 )
            end
        },
    }
}
