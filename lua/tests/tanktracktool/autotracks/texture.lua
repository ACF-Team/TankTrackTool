
local fixtures = include( "tests/tanktracktool/helpers/fixtures.lua" )
local probe = include( "tests/tanktracktool/helpers/probe.lua" )

local up, down = Vector( 0, 0, 1 ), Vector( 0, 0, -1 )

local function texmap( track )
    return 1 / ( track.values.trackRes * track.values.trackWidth )
end

local function bottomDensity( frame, track, side, x1, x2 )
    local y = track:wheel( 1, side ).y + 0.3 * track.values.trackWidth
    return probe.density( frame, Vector( x1, y, -1000 ), Vector( x2, y, -1000 ), up )
end

local function bottomV( frame, track, side, x )
    local y = track:wheel( 1, side ).y
    return probe.first( frame, Vector( x, y + 0.3 * track.values.trackWidth, -1000 ), up ).v
end

return {
    groupName = "tanktracktool.autotracks texture",

    beforeEach = function( state )
        state.backend, state.autotracks = fixtures.load()
        state.track = function( opts ) return fixtures.track( state.backend, state.autotracks, opts ) end
    end,

    cases = {
        {
            name = "Repeats once every resolution times width along the track",
            func = function( state )
                for _, values in ipairs( { {}, { trackRes = 5, trackWidth = 40 } } ) do
                    values.trackTension = 1

                    local track = state.track( { values = values } ):build()
                    local frame = track:frame()
                    local expected = texmap( track )

                    for _, side in ipairs( track:sides() ) do
                        local y = track:wheel( 1, side ).y + 0.3 * track.values.trackWidth

                        expect( bottomDensity( frame, track, side, 55, 45 ) ).to.aboutEqual( -expected, expected * 0.03 )
                        expect( probe.density( frame, Vector( -5, y, 1000 ), Vector( 5, y, 1000 ), down ) ).to.aboutEqual( -expected, expected * 0.03 )
                    end
                end
            end
        },

        {
            name = "Runs across the width mirrored on each side",
            func = function( state )
                for _, flip in ipairs( { 0, 1 } ) do
                    local track = state.track( { values = { trackFlip = flip } } ):build()
                    local frame = track:frame()
                    local offset = 0.3 * track.values.trackWidth

                    for _, side in ipairs( track:sides() ) do
                        local center = track:wheel( 4, side )
                        local outer = ( ( side == 1 ) == ( flip == 0 ) ) and offset or -offset

                        local a = probe.first( frame, Vector( center.x, center.y + outer, -1000 ), up )
                        local b = probe.first( frame, Vector( center.x, center.y - outer, -1000 ), up )

                        expect( a.u ).to.aboutEqual( 0.143 + 0.1 * 0.714, 0.01 )
                        expect( b.u ).to.aboutEqual( 0.857 - 0.1 * 0.714, 0.01 )
                    end
                end
            end
        },

        {
            name = "Scrolls each side by its own speed",
            func = function( state )
                local track = state.track():build()
                local expected = texmap( track )
                local left, right = bottomV( track:frame(), track, 1, 50 ), bottomV( track:frame(), track, 2, 50 )

                track:setVelocity( 6, 0 )
                track:think()

                local frame = track:frame()
                expect( probe.wrap( bottomV( frame, track, 1, 50 ) - left ) ).to.aboutEqual( -6 * expected, 0.005 )
                expect( probe.wrap( bottomV( frame, track, 2, 50 ) - right ) ).to.aboutEqual( 0, 0.005 )

                track:setVelocity( 0, -4 )
                track:think()
                track:think()

                frame = track:frame()
                expect( probe.wrap( bottomV( frame, track, 1, 50 ) - left ) ).to.aboutEqual( -6 * expected, 0.005 )
                expect( probe.wrap( bottomV( frame, track, 2, 50 ) - right ) ).to.aboutEqual( 8 * expected, 0.005 )
            end
        },

        {
            name = "Stays evenly spread when the suspension moves",
            func = function( state )
                for _, offset in ipairs( { 6, -4 } ) do
                    local track = state.track( { values = { trackTension = 1 } } ):build()
                    local expected = texmap( track )

                    track:moveWheel( 4, Vector( 0, 0, offset ) )
                    track:think()

                    local frame = track:frame()
                    for _, side in ipairs( track:sides() ) do
                        expect( bottomDensity( frame, track, side, 55, 45 ) ).to.aboutEqual( -expected, expected * 0.03 )
                        expect( bottomDensity( frame, track, side, 20, 14 ) ).to.aboutEqual( -expected, expected * 0.03 )
                        expect( bottomDensity( frame, track, side, -14, -20 ) ).to.aboutEqual( -expected, expected * 0.03 )
                    end
                end
            end
        },
    }
}
