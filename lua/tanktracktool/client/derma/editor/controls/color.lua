
local PANEL = {}

local function ColorToString( col )
    return math.floor( col.r ) .. " " .. math.floor( col.g ) .. " " .. math.floor( col.b ) .. " " .. math.floor( col.a )
end

local function Luminance( col )
    return 0.2126 * col.r + 0.7152 * col.g + 0.0722 * col.b
end

local grid = Material( "gui/alpha_grid.png", "nocull" )
local gradient = Material( "vgui/gradient-l" )

local function Paint( self, w, h )
    local color = self:GetColor()

    if color.a < 255 then
        surface.SetDrawColor( 255, 255, 255, 255 )
        surface.SetMaterial( grid )

        local size = 192
        for i = 0, math.ceil( h / size ) do
            surface.DrawTexturedRect( 0, i * size, w, size )
        end

        surface.SetDrawColor( color )
        surface.SetMaterial( gradient )
        surface.DrawTexturedRect( 0, 0, w, h )
        surface.DrawTexturedRect( 0, 0, w, h )

        surface.SetDrawColor( 0, 0, 0, 200 )
        surface.DrawOutlinedRect( 0, 0, w, h )

        if IsValid( self.mixer ) then
            if Luminance( color ) < 180 then
                draw.SimpleTextOutlined( "Click to close!", "DermaDefault", w / 2, h / 2, color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 1, color_black )
            else
                draw.SimpleTextOutlined( "Click to close!", "DermaDefault", w / 2, h / 2, color_black, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 1, color_white)
            end
        end

        return true
    end

    surface.SetDrawColor( color )
    surface.DrawRect( 0, 0, w, h )

    surface.SetDrawColor( 0, 0, 0, 200 )
    surface.DrawOutlinedRect( 0, 0, w, h )

    if IsValid( self.mixer ) then
        if Luminance( color ) < 180 then
            draw.SimpleTextOutlined( "Click to close!", "DermaDefault", w / 2, h / 2, color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 1, color_black )
        else
            draw.SimpleTextOutlined( "Click to close!", "DermaDefault", w / 2, h / 2, color_black, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 1, color_white)
        end
    end

    return true
end

function PANEL:Setup( editData )
    self:Clear()

    local editor = self:Add( "DButton" )
    editor:Dock( FILL )
    editor:DockMargin( 0, 0, 0, 0 )
    editor:SetText( "" )

    local inner = Color( 255, 255, 255, 255 )
    local mixer

    editor.Paint = Paint
    editor.DoClick = function()
        if IsValid( mixer ) then
            editor.mixer = nil
            mixer:Remove()
            mixer = nil
            return
        end

        if IsValid( self.m_Editor.ColorMixer ) then
            self.m_Editor.ColorMixer:Remove()
        end

        self.m_Editor.ColorMixer = vgui.Create( "DColorMixer", self.m_Editor )
        mixer = self.m_Editor.ColorMixer
        editor.mixer = mixer

        mixer:SetAlphaBar( true )
        mixer:SetPalette( false )
        mixer:SetWangs( true )

        mixer.ValueChanged = function( color, newcol )
            inner = newcol
            editor:SetColor( newcol )
            self:ValueChanged( ColorToString( newcol ), true )
        end

        mixer.Paint = function( _, w, h )
            surface.SetDrawColor( inner )
            surface.DrawRect( 0, 0, w, h )
            return DColorMixer.Paint( _, w, h )
        end


        local col = inner
        mixer:SetColor( col )

        local sx, sy = self.m_Editor:GetChildPosition( self:GetRow() )
        mixer:SetPos( sx - mixer:GetWide() + self:GetRow():GetWide(), sy - self.m_Editor.VBar:GetOffset() + self:GetRow().Label:GetTall() )

        --local x, y = self.m_Editor:ScreenToLocal( gui.MouseX(), gui.MouseY() )
        --local cx, cy = self.m_Editor:GetChildPosition( editor )
        --mixer:SetPos( cx, cy )

        --local x, y = self.m_Editor:GetChildPosition( self:GetRow() )
        --mixer:SetPos( x - mixer:GetWide() + self:GetRow():GetWide(), y + self:GetRow().Label:GetTall() )
    end

    editor.DoRightClick = function()
        local menu = DermaMenu()
        menu:AddOption( "copy " .. self:GetRow():GetText(), function()
            self.m_Editor.ColorCopied = editor:GetColor()
        end ):SetImage( "icon16/page_copy.png" )

        if IsColor( self.m_Editor.ColorCopied ) then
            menu:AddOption( "paste color", function()
                inner = self.m_Editor.ColorCopied
                editor:SetColor( self.m_Editor.ColorCopied )
                self:ValueChanged( ColorToString( self.m_Editor.ColorCopied ), true )
            end ):SetImage( "icon16/page_paste.png" )
        end

        menu:AddOption( "cancel", function() end ):SetImage( "icon16/cancel.png" )

        local x, y = editor:LocalToScreen( 0, self:GetRow().Label:GetTall() )
        menu:Open( x, y )
    end

    self.IsEnabled = function( _ )
        return editor:IsEnabled()
    end

    self.SetEnabled = function( _, b )
        editor:SetEnabled( b )
    end

    self.IsEditing = function( _ )
        return IsValid( mixer )
    end

    self.SetValue = function( _, val )
        inner = string.ToColor( val )
        editor:SetColor( inner )
        self:Callback( editData, inner )
    end
end

vgui.Register( "tanktracktoolEditor_Color", PANEL, "tanktracktoolEditor_Generic" )
