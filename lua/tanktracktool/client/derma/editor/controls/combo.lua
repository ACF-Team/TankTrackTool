
local PANEL = {}

function PANEL:Init()
end

local ImagePanel

local function OpenImagePanel( menu, comboBox, editData )
    if IsValid( ImagePanel ) then
        ImagePanel:Remove()
        ImagePanel = nil
    end
    if not editData.images then
        return
    end

    ImagePanel = vgui.Create( "DImage" )

    local x, y = menu:GetPos()
    local w, h = menu:GetSize()

    local ih = math.max( w, math.min( h, menu:GetMaxHeight() ) )
    if ih > h then y = y - ( ih - h ) end

    ImagePanel:SetDrawOnTop( true )
    ImagePanel:SetPos( x - w - 1, y )
    ImagePanel:SetSize( w, ih )

    ImagePanel.Think = function( self )
        if not IsValid( menu ) then
            ImagePanel:Remove()
            ImagePanel = nil
        end
    end

    ImagePanel.Paint = function( self, w, h )
        surface.SetDrawColor( 0, 0, 0, 255 )
        surface.DrawRect( 0, 0, w, h )
        DImage.Paint( self, w, h )
        surface.SetDrawColor( 255, 0, 0, 255 )
        surface.DrawOutlinedRect( 0, 0, w, h )
        surface.DrawLine( 0, 0, w, h )
    end

    ImagePanel.menu = menu
    ImagePanel.editData = editData
    ImagePanel.SetImage = function( self, image )
        image = isstring( editData.images ) and string.format( editData.images, image ) or istable( editData.images ) and editData.images[image] or nil
        DImage.SetImage( self, image )
    end

    ImagePanel:SetImage( comboBox:GetText() )

    return ImagePanel
end

local function SetImage( image )
    if not IsValid( ImagePanel ) then
        ImagePanel = nil
        return
    end

    if not ImagePanel.editData or not IsValid( ImagePanel.menu ) then
        ImagePanel:Remove()
        ImagePanel = nil
        return
    end

    ImagePanel:SetImage( image )
end

local function OnCursorEntered( self )
    SetImage( self:GetText() )

    if self.ParentMenu then
        self.ParentMenu:OpenSubMenu( self, self.SubMenu )
        return
    end

    self:GetParent():OpenSubMenu( self, self.SubMenu )
end

function PANEL:SetupMenu( comboBox, editData )
    local hasIcons, pattern, icon = editData.icons

    -- icons can be a string pattern or a table
    if isstring( hasIcons ) then pattern = true elseif not istable( hasIcons ) then hasIcons = nil end

    -- default to editor theme
    local bICon, bSkin
    if not hasIcons then
        bIcon = "icon16/bullet_white.png"
        bSkin = self:GetEditorSkin().colorHeader
    end

    local sorter = editData.sort or SortedPairs
    if editData.sort then
        comboBox:SetSortItems( false )
    end

    for id, thing in sorter( editData.values or {} ) do
        if hasIcons then
            if pattern then icon = string.format( hasIcons, id ) else icon = hasIcons[ id ] end
        end

        comboBox:AddChoice( id, thing, id == editData.select, icon or bIcon or nil )
        comboBox:AddSpacer()
    end

    local height = self:GetRow().m_Editor.frame:GetTall() * 0.5

    comboBox.OnMenuOpened = function( _, menu )
        menu:SetMaxHeight( height )
        menu.VBar:SetWide( 9 )
        menu.VBar:SetHideButtons( true )

        local mx, my = comboBox:LocalToScreen( 0, 0 )
        local mw, mh = menu:GetSize()
        local mh = math.min( mh, height )

        local sx, sy = self:GetRow().m_Editor.frame:LocalToScreen( 0, 0 )
        local sw, sh = self:GetRow().m_Editor.frame:GetSize()

        local miny = sy
        local maxy = sy + sh

        if ( my + mh ) > ( sy + sh ) then
            local diff = ( my + mh ) - ( sy + sh )
            my = my - diff
        end

        menu:SetPos( mx, my )

        OpenImagePanel( menu, comboBox, editData )

        for i = 1, menu:ChildCount() do
            local k = menu:GetChild( i )
            if k.SetFont and k.GetText then
                if bSkin and k.m_Image then k.m_Image:SetImageColor( bSkin ) end
                k.OnCursorEntered = OnCursorEntered
            end
        end
    end
end

function PANEL:Setup( editData )
    editData = editData or {}

    self:Clear()

    local combo = vgui.Create( "DComboBox", self )
    combo:Dock( FILL )
    combo:DockMargin( 0, 0, 0, 0 )
    combo:SetValue( editData.text or "Select..." )

    self:SetupMenu( combo, editData )

    self.IsEditing = function( self )
        return combo:IsMenuOpen()
    end

    self.SetValue = function( self, val )
        for id, data in pairs( combo.Data ) do
            if data == editData.values[val] then
                combo:SetText( val )
                break
            end
        end
        self:Callback( editData, val )
    end

    combo.OnSelect = function( _, id, val, data )
        if val == "Cancel..." then return end
        self:ValueChanged( val, true )
    end

    combo.Paint = function( combo, w, h )
        if self:IsEditing() or self:GetRow():IsHovered() or self:GetIsDragging() or self:GetRow():IsChildHovered() then
            DComboBox.Paint( combo, w, h )
        end
    end

    self:GetRow().AddChoice = function( _, value, data, select )
        combo:AddChoice( value, data, select )
    end

    self:GetRow().SetSelected = function( _, id )
        combo:ChooseOptionID( id )
    end

    self.IsEnabled = function( _ )
        return combo:IsEnabled()
    end

    self.SetEnabled = function( _, b )
        combo:SetEnabled( b )
    end
end

vgui.Register( "tanktracktoolEditor_Combo", PANEL, "tanktracktoolEditor_Generic" )

