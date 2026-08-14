#include <amxmodx>
#include <amxmisc>
#include <fakemeta>
#include <engine>

#define PLUGIN "CSDM Spawn Editor"
#define VERSION "1.0"
#define AUTHOR "AI"

#define MAX_SPAWNS 128
new Float:g_fSpawns[MAX_SPAWNS][3];
new Float:g_fSpawnAngles[MAX_SPAWNS][3];
new g_iSpawnCount = 0;

new g_spriteLaser;

public plugin_init() {
    register_plugin(PLUGIN, VERSION, AUTHOR);
    
    register_clcmd("say /spawns", "Cmd_SpawnMenu", ADMIN_KICK, "- Opens CSDM Spawn Editor");
    register_clcmd("spawns", "Cmd_SpawnMenu", ADMIN_KICK, "- Opens CSDM Spawn Editor");
    
    // Подгружаем существующие спавны
    set_task(1.0, "LoadSpawns");
    
    // Рисуем лучи к спавнам каждую секунду, чтобы редактор их видел
    set_task(1.0, "DrawSpawns", 0, _, _, "b");
}

public plugin_precache() {
    g_spriteLaser = precache_model("sprites/laserbeam.spr");
}

public Cmd_SpawnMenu(id, level, cid) {
    if (!cmd_access(id, level, cid, 1)) return PLUGIN_HANDLED;
    
    ShowSpawnMenu(id);
    return PLUGIN_HANDLED;
}

public ShowSpawnMenu(id) {
    new menu = menu_create("\yCSDM Spawn Editor", "MenuHandler");
    new szItem[64];
    
    menu_additem(menu, "Add Spawn Here", "1");
    
    formatex(szItem, charsmax(szItem), "Delete Nearest Spawn \r(Total: %d)", g_iSpawnCount);
    menu_additem(menu, szItem, "2");
    
    menu_additem(menu, "Clear All Spawns", "3");
    
    menu_additem(menu, "\ySave Spawns to File", "4");
    
    menu_setprop(menu, MPROP_EXIT, MEXIT_ALL);
    menu_display(id, menu, 0);
}

public MenuHandler(id, menu, item) {
    if (item == MENU_EXIT) {
        menu_destroy(menu);
        return PLUGIN_HANDLED;
    }
    
    new data[6], iName[64], access, callback;
    menu_item_getinfo(menu, item, access, data, charsmax(data), iName, charsmax(iName), callback);
    new key = str_to_num(data);
    
    switch (key) {
        case 1: AddSpawn(id);
        case 2: DeleteNearestSpawn(id);
        case 3: {
            g_iSpawnCount = 0;
            client_print(id, print_chat, "[CSDM] All spawns cleared from memory.");
        }
        case 4: SaveSpawns(id);
    }
    
    menu_destroy(menu);
    if (key != 4) ShowSpawnMenu(id);
    
    return PLUGIN_HANDLED;
}

public AddSpawn(id) {
    if (g_iSpawnCount >= MAX_SPAWNS) {
        client_print(id, print_chat, "[CSDM] Spawn limit reached (%d).", MAX_SPAWNS);
        return;
    }
    
    new Float:origin[3], Float:angles[3];
    pev(id, pev_origin, origin);
    pev(id, pev_angles, angles);
    
    g_fSpawns[g_iSpawnCount][0] = origin[0];
    g_fSpawns[g_iSpawnCount][1] = origin[1];
    g_fSpawns[g_iSpawnCount][2] = origin[2];
    
    g_fSpawnAngles[g_iSpawnCount][0] = angles[0];
    g_fSpawnAngles[g_iSpawnCount][1] = angles[1];
    g_fSpawnAngles[g_iSpawnCount][2] = angles[2];
    
    g_iSpawnCount++;
    client_print(id, print_chat, "[CSDM] Spawn added! Total: %d", g_iSpawnCount);
}

public DeleteNearestSpawn(id) {
    if (g_iSpawnCount == 0) return;
    
    new Float:origin[3];
    pev(id, pev_origin, origin);
    
    new nearest_idx = -1;
    new Float:nearest_dist = 99999.0;
    
    for (new i = 0; i < g_iSpawnCount; i++) {
        new Float:dist = vector_distance(origin, g_fSpawns[i]);
        if (dist < nearest_dist) {
            nearest_dist = dist;
            nearest_idx = i;
        }
    }
    
    if (nearest_idx != -1 && nearest_dist < 150.0) {
        // Удаляем точку, сдвигая массив
        for (new i = nearest_idx; i < g_iSpawnCount - 1; i++) {
            g_fSpawns[i][0] = g_fSpawns[i+1][0];
            g_fSpawns[i][1] = g_fSpawns[i+1][1];
            g_fSpawns[i][2] = g_fSpawns[i+1][2];
            g_fSpawnAngles[i][0] = g_fSpawnAngles[i+1][0];
            g_fSpawnAngles[i][1] = g_fSpawnAngles[i+1][1];
            g_fSpawnAngles[i][2] = g_fSpawnAngles[i+1][2];
        }
        g_iSpawnCount--;
        client_print(id, print_chat, "[CSDM] Nearest spawn deleted.");
    } else {
        client_print(id, print_chat, "[CSDM] No spawn found nearby.");
    }
}

public SaveSpawns(id) {
    new szMapName[32], szCfgDir[64], szDir[128], szFile[128];
    get_mapname(szMapName, charsmax(szMapName));
    get_localinfo("amxx_configsdir", szCfgDir, charsmax(szCfgDir));
    
    formatex(szDir, charsmax(szDir), "%s/csdm", szCfgDir);
    if (!dir_exists(szDir)) mkdir(szDir);
    
    formatex(szDir, charsmax(szDir), "%s/csdm/spawns", szCfgDir);
    if (!dir_exists(szDir)) mkdir(szDir);
    
    formatex(szFile, charsmax(szFile), "%s/%s.spawns.cfg", szDir, szMapName);
    
    if (file_exists(szFile)) delete_file(szFile);
    
    if (g_iSpawnCount == 0) {
        client_print(id, print_chat, "[CSDM] Spawn file deleted (no spawns to save).");
        return;
    }
    
    new file = fopen(szFile, "wt");
    if (!file) {
        client_print(id, print_chat, "[CSDM] Error saving spawns!");
        return;
    }
    
    for (new i = 0; i < g_iSpawnCount; i++) {
        fprintf(file, "%.1f %.1f %.1f %.1f %.1f %.1f^n", 
            g_fSpawns[i][0], g_fSpawns[i][1], g_fSpawns[i][2],
            g_fSpawnAngles[i][0], g_fSpawnAngles[i][1], g_fSpawnAngles[i][2]);
    }
    
    fclose(file);
    client_print(id, print_chat, "[CSDM] Successfully saved %d spawns to %s.spawns.cfg", g_iSpawnCount, szMapName);
}

public LoadSpawns() {
    new szMapName[32], szCfgDir[64], szFile[128];
    get_mapname(szMapName, charsmax(szMapName));
    get_localinfo("amxx_configsdir", szCfgDir, charsmax(szCfgDir));
    
    formatex(szFile, charsmax(szFile), "%s/csdm/spawns/%s.spawns.cfg", szCfgDir, szMapName);
    
    g_iSpawnCount = 0;
    if (!file_exists(szFile)) return;
    
    new file = fopen(szFile, "rt");
    if (!file) return;
    
    new szLine[128], szX[16], szY[16], szZ[16], szAngX[16], szAngY[16], szAngZ[16];
    
    while (!feof(file) && g_iSpawnCount < MAX_SPAWNS) {
        fgets(file, szLine, charsmax(szLine));
        trim(szLine);
        
        if (szLine[0] == 0 || szLine[0] == ';' || szLine[0] == '#') continue;
        
        parse(szLine, szX, 15, szY, 15, szZ, 15, szAngX, 15, szAngY, 15, szAngZ, 15);
        
        g_fSpawns[g_iSpawnCount][0] = str_to_float(szX);
        g_fSpawns[g_iSpawnCount][1] = str_to_float(szY);
        g_fSpawns[g_iSpawnCount][2] = str_to_float(szZ);
        
        g_fSpawnAngles[g_iSpawnCount][0] = str_to_float(szAngX);
        g_fSpawnAngles[g_iSpawnCount][1] = str_to_float(szAngY);
        g_fSpawnAngles[g_iSpawnCount][2] = str_to_float(szAngZ);
        
        g_iSpawnCount++;
    }
    fclose(file);
}

public DrawSpawns() {
    if (g_iSpawnCount == 0) return;
    
    new pCvarVisualSpawns = get_cvar_pointer("csdm_visual_spawns");
    if (pCvarVisualSpawns && !get_pcvar_num(pCvarVisualSpawns)) {
        return;
    }
    
    // Рисуем лучи только для админов
    for (new id = 1; id <= get_maxplayers(); id++) {
        if (!is_user_connected(id) || !(get_user_flags(id) & ADMIN_KICK)) continue;
        
        // Показываем только если у админа открыто меню (опционально, но здесь показываем всегда для простоты)
        for (new i = 0; i < g_iSpawnCount; i++) {
            new vecStart[3], vecEnd[3];
            vecStart[0] = floatround(g_fSpawns[i][0]);
            vecStart[1] = floatround(g_fSpawns[i][1]);
            vecStart[2] = floatround(g_fSpawns[i][2]);
            
            vecEnd[0] = vecStart[0];
            vecEnd[1] = vecStart[1];
            vecEnd[2] = vecStart[2] + 40; // Линия вверх на 40 юнитов
            
            message_begin(MSG_ONE_UNRELIABLE, SVC_TEMPENTITY, _, id);
            write_byte(TE_BEAMPOINTS);
            write_coord(vecStart[0]);
            write_coord(vecStart[1]);
            write_coord(vecStart[2]);
            write_coord(vecEnd[0]);
            write_coord(vecEnd[1]);
            write_coord(vecEnd[2]);
            write_short(g_spriteLaser);
            write_byte(0); // starting frame
            write_byte(0); // frame rate
            write_byte(10); // life in 0.1s
            write_byte(10); // line width
            write_byte(0); // noise
            write_byte(0); // R
            write_byte(255); // G
            write_byte(0); // B
            write_byte(255); // brightness
            write_byte(0); // scroll speed
            message_end();
        }
    }
}
