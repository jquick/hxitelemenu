require 'common';

addon.name    = 'hxitelemenu';
addon.version = '1.0.0';
addon.author  = 'jquick';
addon.desc    = 'Quick teleport menu for conquest outpost NPCs.';

local imgui = require('imgui');

local regions = {
    { key = 'Aragoneu',          label = 'Aragoneu (Meriphataud Mtns)' },
    { key = 'Derfland',          label = 'Derfland (Pashhow Marshlands)' },
    { key = 'Elshimo Lowlands',  label = 'Elshimo Low. (Yuhtunga Jungle)' },
    { key = 'Elshimo Uplands',   label = 'Elshimo Up. (Yhoator Jungle)' },
    { key = 'Fauregandi',        label = 'Fauregandi (Beaucedine Glacier)' },
    { key = 'Gustaberg',         label = 'Gustaberg (N. Gustaberg)' },
    { key = 'Kolshushu',         label = 'Kolshushu (Buburimu Peninsula)' },
    { key = 'Kuzotz',            label = 'Kuzotz (Eastern Altepa Desert)' },
    { key = "Li'Telor",          label = "Li'Telor (The Sanctuary of Zi'Tah)" },
    { key = 'Norvallen',         label = 'Norvallen (Jugner Forest)' },
    { key = 'Qufim',             label = 'Qufim (Qufim Island)' },
    { key = 'Ronfaure',          label = 'Ronfaure (W. Ronfaure)' },
    { key = 'Sarutabaruta',      label = 'Sarutabaruta (W. Sarutabaruta)' },
    { key = 'Tavnazia',          label = 'Tavnazia (Lufaise Meadows)' },
    { key = 'Valdeaunia',        label = 'Valdeaunia (Xarcabard)' },
    { key = 'Vollbow',           label = 'Vollbow (Cape Teriggan)' },
    { key = 'Zulkheim',          label = 'Zulkheim (Valkurm Dunes)' },
};

local function btn_colors(r, g, b)
    return {
        { r, g, b, 0.9 },
        { r + 0.1, g + 0.1, b + 0.1, 1.0 },
        { r - 0.08, g - 0.05, b - 0.07, 1.0 },
    };
end

local nation_colors = {
    Ronfaure     = btn_colors(0.7, 0.2, 0.2),
    Gustaberg    = btn_colors(0.2, 0.4, 0.8),
    Sarutabaruta = btn_colors(0.2, 0.6, 0.3),
};
local default_color = btn_colors(0.3, 0.15, 0.35);
local cancel_color  = btn_colors(0.4, 0.2, 0.2);
local spinner = { '|', '/', '-', '\\' };

local show_menu = { false };
local menu_question = '';
local first_page_msg = '';
local need_cancel = false;
local target_region = nil;
local navigating = false;
local nav_label = '';
local debug_mode = false;

local function get_player_name()
    local entity = GetPlayerEntity();
    if entity then return entity.Name; end
    return '';
end

local function send_menu_response(question, answer)
    local name = get_player_name();
    local msg = string.format('GMTELL(%s): Question(%s): Result (%s)', name, question, answer);

    local mode_bytes = string.char(0x03, 0x00);
    local recipient = '_CUSTOM_MENU\0\0\0';
    local payload = mode_bytes .. recipient .. msg;

    local total = 4 + #payload;
    local pad = (4 - (total % 4)) % 4;
    payload = payload .. string.rep('\0', pad);
    total = total + pad;

    local size_field = total / 4;
    local header_word = bit.bor(0xB6, bit.lshift(size_field, 9));
    local header = struct.pack('Hxx', header_word);
    local pkt = (header .. payload):totable();

    if debug_mode then
        print(string.format('[hxitelemenu] Sending: %s', msg));
    end

    AshitaCore:GetPacketManager():AddOutgoingPacket(0xB6, pkt);
end

local function close_menu()
    show_menu[1] = false;
    need_cancel = false;
    navigating = false;
    target_region = nil;
    nav_label = '';
end

ashita.events.register('packet_in', 'hxitelemenu_pin', function(e)
    if e.id ~= 0x0017 then return; end

    local pkt_name = e.data:sub(0x08 + 1, 0x08 + 15):match('^[^\0]+') or '';
    if pkt_name ~= '_CUSTOM_MENU' then return; end

    local msg = e.data:sub(0x17 + 1):match('^[^\0]+') or '';

    if debug_mode then
        print(string.format('[hxitelemenu] [IN MENU] %s', msg));
    end

    if msg:find('Which region would you like to teleport') then
        menu_question = msg:match('^"([^"]+)"') or '';

        if target_region then
            if msg:find('"' .. target_region .. '"', 1, true) then
                send_menu_response(menu_question, target_region);
                close_menu();
            elseif msg:find('"Next Page"', 1, true) then
                send_menu_response(menu_question, 'Next Page');
            else
                send_menu_response(menu_question, 'Canceled.');
                close_menu();
                print('[hxitelemenu] Region not found - is this outpost unlocked?');
            end
            e.blocked = true;
            return;
        end

        first_page_msg = msg;
        show_menu[1] = true;
        need_cancel = true;
        e.blocked = true;
        return;
    end
end);

ashita.events.register('d3d_present', 'hxitelemenu_render', function()
    if not show_menu[1] then
        if need_cancel then
            send_menu_response(menu_question, 'Canceled.');
            close_menu();
        end
        return;
    end

    imgui.SetNextWindowSizeConstraints({ 340, 0 }, { 340, 9999 });
    imgui.PushStyleVar(ImGuiStyleVar_FrameRounding, 4.0);
    imgui.PushStyleVar(ImGuiStyleVar_ItemSpacing, { 6, 4 });
    imgui.PushStyleVar(ImGuiStyleVar_ButtonTextAlign, { 0.0, 0.5 });
    if imgui.Begin('Outpost Teleport', show_menu, ImGuiWindowFlags_AlwaysAutoResize) then
        if navigating then
            local idx = math.floor(os.clock() * 8) % #spinner + 1;
            imgui.Text(string.format('  %s  Teleporting to %s...', spinner[idx], nav_label));
        else
            imgui.Text('Select destination:');
        end
        imgui.Separator();
        imgui.Spacing();

        if navigating then imgui.BeginDisabled(); end

        for _, r in ipairs(regions) do
            local c = nation_colors[r.key] or default_color;
            imgui.PushStyleColor(ImGuiCol_Button, c[1]);
            imgui.PushStyleColor(ImGuiCol_ButtonHovered, c[2]);
            imgui.PushStyleColor(ImGuiCol_ButtonActive, c[3]);
            if imgui.Button(r.label, { -1, 0 }) then
                need_cancel = false;
                navigating = true;
                nav_label = r.label;
                if first_page_msg:find('"' .. r.key .. '"', 1, true) then
                    send_menu_response(menu_question, r.key);
                    close_menu();
                else
                    target_region = r.key;
                    send_menu_response(menu_question, 'Next Page');
                end
            end
            imgui.PopStyleColor(3);
        end

        imgui.Spacing();
        imgui.Separator();
        imgui.PushStyleColor(ImGuiCol_Button, cancel_color[1]);
        imgui.PushStyleColor(ImGuiCol_ButtonHovered, cancel_color[2]);
        imgui.PushStyleColor(ImGuiCol_ButtonActive, cancel_color[3]);
        if imgui.Button('Cancel', { -1, 0 }) then
            close_menu();
        end
        imgui.PopStyleColor(3);

        if navigating then imgui.EndDisabled(); end
    end
    imgui.PopStyleVar(3);
    imgui.End();
end);

ashita.events.register('command', 'hxitelemenu_cmd', function(e)
    local args = e.command:args();
    if (#args == 0 or not args[1]:any('/hxitelemenu')) then return; end
    e.blocked = true;

    if (#args >= 2 and args[2]:any('debug')) then
        debug_mode = not debug_mode;
        print(string.format('[hxitelemenu] Debug: %s', debug_mode and 'ON' or 'OFF'));
        return;
    end

    print('[hxitelemenu] Commands:');
    print('  /hxitelemenu debug - Toggle debug logging');
end);

ashita.events.register('load', 'hxitelemenu_load', function()
    print('[hxitelemenu] Loaded. Talk to a teleport NPC to see the quick menu.');
end);

ashita.events.register('unload', 'hxitelemenu_unload', function()
    if need_cancel and menu_question ~= '' then
        send_menu_response(menu_question, 'Canceled.');
    end
    close_menu();
    print('[hxitelemenu] Unloaded.');
end);