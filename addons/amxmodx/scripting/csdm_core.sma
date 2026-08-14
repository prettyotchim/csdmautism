#include <amxmodx>
#include <amxmisc>
#include <fakemeta>
#include <hamsandwich>
#include <engine>
#include <fun>
#include <cstrike>

#define PLUGIN "CSDM Core"
#define VERSION "1.0"
#define AUTHOR "AI"

// --- Конфигурация ---
#define RESPAWN_DELAY 2.0        // Задержка перед воскрешением (секунды)
#define PROTECTION_TIME 3.0      // Время защиты при респавне (секунды)
#define MAX_SPAWNS 128           // Максимальное количество кастомных спавнов

// --- Глобальные переменные ---
new Float:g_fSpawns[MAX_SPAWNS][3];
new Float:g_fSpawnAngles[MAX_SPAWNS][3];
new g_iSpawnCount = 0;
new bool:g_bProtected[33];
new bool:g_bHasCustomSpawns = false;

#define MAX_MAPS 32
new g_szVoteMaps[MAX_MAPS][32];
new g_iVoteMapsCount = 0;
new bool:g_bMapChanging = false;

#define MAX_KILLS 5
#define NUM_SERIES 3
new g_KillCount[33];
new g_PlayerSeries[33];

new g_pCvarFFA;
new g_pCvarVisualSpawns;
new g_pCvarDamageIndicator;
new g_pCvarDmgSize;
new g_pCvarDmgScatter;
new g_pCvarDmgOpaque;
new g_msgScoreInfo;
new g_pCvarHeadshotSound;
new g_pCvarKillVolume;
new g_pCvarBotDifficulty;

new g_iFakeTeam[33];
#define OFFSET_TEAM 114
#define EXTRA_OFFSET 5

new g_pCvarCustomModels;

new g_pCvarDeagleBuff;
#define m_flAccuracy 62
#define OFFSET_LINUX_WEAPONS 4

new g_msgScreenFade;

// Выбор оружия
new g_iPrimarySelected[33];
new g_iSecondarySelected[33];
new bool:g_bAutoEquip[33];
new bool:g_bHasWeaponsSelected[33];

// Оружия для меню
new const g_szPrimaryNames[][] = { "M4A1", "AK-47", "AWP", "Scout", "FAMAS", "MP5" };
new const g_szPrimaryEnts[][] = { "weapon_m4a1", "weapon_ak47", "weapon_awp", "weapon_scout", "weapon_famas", "weapon_mp5navy" };

new const g_szSecondaryNames[][] = { "Desert Eagle", "USP", "Glock 18" };
new const g_szSecondaryEnts[][] = { "weapon_deagle", "weapon_usp", "weapon_glock18" };

new const g_iMaxClip[31] = {
    0, 13, 0, 10, 1, 7, 1, 30, 30, 1, 30, 20, 25, 30, 35, 25, 12, 20, 10, 30, 100, 8, 30, 30, 20, 2, 7, 30, 30, 0, 50
};


public plugin_precache() {
    new sound_path[64];
    for(new s = 1; s <= NUM_SERIES; s++) {
        for(new k = 1; k <= MAX_KILLS; k++) {
            formatex(sound_path, charsmax(sound_path), "valorant/%d/kill%d.wav", s, k);
            precache_sound(sound_path);
        }
    }
    precache_sound("valorant/headshot.wav");
    
    // Precache custom player models
    precache_model("models/player/asuka/asuka.mdl");
}

public plugin_init() {
    register_plugin(PLUGIN, VERSION, AUTHOR);
    
    copy(g_szVoteMaps[g_iVoteMapsCount++], 31, "de_dust2");
    copy(g_szVoteMaps[g_iVoteMapsCount++], 31, "de_mirage");
    copy(g_szVoteMaps[g_iVoteMapsCount++], 31, "de_inferno");
    copy(g_szVoteMaps[g_iVoteMapsCount++], 31, "de_ancient_csgo");
    copy(g_szVoteMaps[g_iVoteMapsCount++], 31, "cs_mansion");
    copy(g_szVoteMaps[g_iVoteMapsCount++], 31, "de_westwood");
    
    // Хуки событий
    RegisterHam(Ham_Killed, "player", "OnPlayerKilled_Pre", 0);
    RegisterHam(Ham_Killed, "player", "OnPlayerKilled_Post", 1);
    RegisterHam(Ham_Spawn, "player", "OnPlayerSpawn_Post", 1);
    
    RegisterHam(Ham_TakeDamage, "player", "OnPlayerTakeDamage_Pre", 0);
    RegisterHam(Ham_TakeDamage, "player", "OnPlayerTakeDamage_Post", 1);
    
    RegisterHam(Ham_TraceAttack, "player", "OnPlayerTraceAttack_Pre", 0);
    RegisterHam(Ham_TraceAttack, "player", "OnPlayerTraceAttack_Post", 1);
    
    register_event("DeathMsg", "Event_DeathMsg", "a");
    
    g_pCvarFFA = register_cvar("csdm_ffa", "0");
    g_pCvarVisualSpawns = register_cvar("csdm_visual_spawns", "1");
    g_pCvarDamageIndicator = register_cvar("csdm_damage_indicator", "1");
    g_pCvarDmgSize = register_cvar("amx_dmg_size", "1");
    g_pCvarDmgScatter = register_cvar("amx_dmg_scatter", "1");
    g_pCvarDmgOpaque = register_cvar("amx_dmg_opaque", "1");
    g_pCvarHeadshotSound = register_cvar("csdm_hs_sound", "1");
    g_pCvarKillVolume = register_cvar("csdm_kill_volume", "100");
    g_pCvarBotDifficulty = register_cvar("csdm_bot_difficulty", "4");
    g_pCvarCustomModels = register_cvar("csdm_custom_models", "1");
    g_pCvarDeagleBuff = register_cvar("csdm_deagle_buff", "1");
    RegisterHam(Ham_Weapon_PrimaryAttack, "weapon_deagle", "OnDeaglePrimaryAttack_Pre", 0);
    RegisterHam(Ham_Weapon_PrimaryAttack, "weapon_deagle", "OnDeaglePrimaryAttack_Post", 1);
    
    register_clcmd("amx_csdm_dmg_set_scatter", "cmd_csdm_set_scatter");
    register_clcmd("amx_csdm_set_volume", "cmd_csdm_set_volume");
    register_clcmd("amx_csdm_add_map", "cmd_add_map");
    
    g_msgScoreInfo = get_user_msgid("ScoreInfo");
    g_msgScreenFade = get_user_msgid("ScreenFade");
    
    // Хук для снятия защиты при стрельбе
    register_forward(FM_CmdStart, "Fwd_CmdStart");
    
    // Хук для моментального удаления выброшенного оружия
    register_forward(FM_SetModel, "Fwd_SetModel_Pre", 0);
    
    // Событие для бесконечных патронов (в запасе)
    register_event("CurWeapon", "Event_CurWeapon", "be", "1=1");
    
    // Меню оружия
    register_clcmd("say /guns", "Cmd_Guns");
    register_clcmd("say_team /guns", "Cmd_Guns");
    register_clcmd("guns", "Cmd_Guns");
    
    // Фикс для бесконечной смены команды (Only 1 team change is allowed)
    register_clcmd("chooseteam", "Cmd_TeamChange");
    register_clcmd("jointeam", "Cmd_TeamChange");
    register_clcmd("joinclass", "Cmd_JoinClass");
    register_clcmd("menuselect", "Cmd_JoinClass");

    // Удаление целей карты для бесконечного раунда
    set_task(1.0, "Task_CleanMap");
    
    // Проверка времени до конца карты для голосования
    set_task(1.0, "Task_CheckTimeleft", 999, _, _, "b");
}

public plugin_cfg() {
    // Загрузка сохраненных настроек
    new szCfgDir[64], szFile[128];
    get_localinfo("amxx_configsdir", szCfgDir, charsmax(szCfgDir));
    formatex(szFile, charsmax(szFile), "%s/csdm/settings.cfg", szCfgDir);
    
    if (file_exists(szFile)) {
        server_cmd("exec %s", szFile);
        server_exec();
    }
    
    // Настраиваем сервер для CSDM
    server_cmd("mp_roundtime 9");
    server_cmd("mp_timelimit 10");
    server_cmd("mp_freezetime 0");
    server_cmd("mp_buytime 0");
    server_cmd("yb_csdm_mode %d", get_pcvar_num(g_pCvarFFA) ? 2 : 1);
    server_cmd("yb_difficulty %d", get_pcvar_num(g_pCvarBotDifficulty));
    
    // Загрузка кастомных спавнов
    LoadCustomSpawns();
}

// ----------------------------------------------------
// МОДУЛЬ: Подготовка карты (Map Cleanup)
// ----------------------------------------------------
public Task_CleanMap() {
    new ent = -1;
    new const szRemoveEntities[][] = {
        "func_bomb_target", "info_bomb_target", "hostage_entity",
        "func_hostage_rescue", "info_hostage_rescue", "info_vip_start",
        "func_vip_safetyzone", "func_escapezone", "func_buyzone",
        "armoury_entity"
    };
    
    for (new i = 0; i < sizeof(szRemoveEntities); i++) {
        ent = -1;
        while ((ent = engfunc(EngFunc_FindEntityByString, ent, "classname", szRemoveEntities[i])) > 0) {
            engfunc(EngFunc_RemoveEntity, ent);
        }
    }
}

// ----------------------------------------------------
// МОДУЛЬ: Удаление выброшенного оружия
// ----------------------------------------------------
public Fwd_SetModel_Pre(ent, const model[]) {
    if (!pev_valid(ent)) return FMRES_IGNORED;
    
    new classname[32];
    pev(ent, pev_classname, classname, charsmax(classname));
    
    // Моментально удаляем weaponbox (выброшенное оружие) или щит
    if (equal(classname, "weaponbox") || equal(classname, "weapon_shield")) {
        // Убедимся, что это не C4, хотя мы удалили bomb_target
        if (containi(model, "w_backpack") == -1) {
            engfunc(EngFunc_RemoveEntity, ent);
            return FMRES_SUPERCEDE;
        }
    }
    return FMRES_IGNORED;
}

// ----------------------------------------------------
// МОДУЛЬ: Респавн (Respawn)
// ----------------------------------------------------
public client_putinserver(id) {
    g_bAutoEquip[id] = false;
    g_bHasWeaponsSelected[id] = false;
    g_iPrimarySelected[id] = 0;
    g_iSecondarySelected[id] = 0;
    g_iFakeTeam[id] = 0;
    g_KillCount[id] = 0;
}

public client_disconnected(id) {
    g_KillCount[id] = 0;
}

public OnPlayerKilled_Pre(victim, attacker, shouldgib) {
    if (g_iFakeTeam[victim]) {
        set_pdata_int(victim, OFFSET_TEAM, g_iFakeTeam[victim], EXTRA_OFFSET);
        g_iFakeTeam[victim] = 0;
    }
}

public OnPlayerKilled_Post(victim, attacker, shouldgib) {
    if (is_user_connected(victim)) {
        // Запускаем таймер респавна
        set_task(RESPAWN_DELAY, "Task_Respawn", victim);
    }
    
    if (get_pcvar_num(g_pCvarFFA) && is_user_connected(attacker) && victim != attacker) {
        if (cs_get_user_team(victim) == cs_get_user_team(attacker)) {
            set_user_frags(attacker, get_user_frags(attacker) + 2);
            
            message_begin(MSG_ALL, g_msgScoreInfo);
            write_byte(attacker);
            write_short(get_user_frags(attacker));
            write_short(cs_get_user_deaths(attacker));
            write_short(0);
            write_short(get_user_team(attacker));
            message_end();
        }
    }
}

public Task_Respawn(id) {
    if (is_user_connected(id) && !is_user_alive(id)) {
        new CsTeams:team = cs_get_user_team(id);
        if (team == CS_TEAM_T || team == CS_TEAM_CT) {
            ExecuteHamB(Ham_CS_RoundRespawn, id);
        }
    }
}

public OnPlayerSpawn_Post(id) {
    if (!is_user_alive(id)) return;
    
    // Pick series for valorant kill sound (cycle sequentially)
    g_PlayerSeries[id]++;
    if (g_PlayerSeries[id] > NUM_SERIES) {
        g_PlayerSeries[id] = 1;
    }
    
    // 1. Телепортация на кастомный спавн
    DoCustomSpawn(id);
    
    // 2. Защита при спавне
    GiveProtection(id);
    
    // 3. Выдача оружия
    strip_user_weapons(id);
    give_item(id, "weapon_knife");
    give_item(id, "item_assaultsuit"); // Броня и шлем
    
    // 4. Кастомные модели
    if (get_pcvar_num(g_pCvarCustomModels) && !is_user_bot(id)) {
        cs_set_user_model(id, "asuka");
    } else {
        cs_reset_user_model(id);
    }
    
    // Логика выдачи оружия
    if (is_user_bot(id)) {
        // Ботам выдаем случайное оружие без снайперок (AWP=2, Scout=3)
        new pIdx;
        do {
            pIdx = random_num(0, sizeof(g_szPrimaryEnts) - 1);
        } while (pIdx == 2 || pIdx == 3);
        
        g_iPrimarySelected[id] = pIdx;
        g_iSecondarySelected[id] = random_num(0, sizeof(g_szSecondaryEnts) - 1);
        EquipPlayer(id);
    } else if (g_bAutoEquip[id]) {
        EquipPlayer(id);
    } else if (g_bHasWeaponsSelected[id]) {
        ShowEquipMenu(id);
    } else {
        ShowPrimaryMenu(id);
    }
}

// Событие обновления оружия у игрока (стрельба, смена оружия)
public Event_CurWeapon(id) {
    if (!is_user_alive(id)) return;
    
    new weapon = read_data(2);
    // Игнорируем гранаты, нож и бомбу
    if (weapon != CSW_KNIFE && weapon != CSW_HEGRENADE && weapon != CSW_FLASHBANG && weapon != CSW_SMOKEGRENADE && weapon != CSW_C4) {
        // Устанавливаем 200 патронов в запас (этого хватит для бесконечной перезарядки)
        cs_set_user_bpammo(id, weapon, 200);
    }
}

// ----------------------------------------------------
// МОДУЛЬ: Защита при спавне (Spawn Protection)
// ----------------------------------------------------
public GiveProtection(id) {
    g_bProtected[id] = true;
    set_pev(id, pev_takedamage, DAMAGE_NO);
    
    // Свечение взависимости от команды
    new CsTeams:team = cs_get_user_team(id);
    if (team == CS_TEAM_CT) {
        set_user_rendering(id, kRenderFxGlowShell, 0, 0, 255, kRenderNormal, 20); // Синий
    } else {
        set_user_rendering(id, kRenderFxGlowShell, 255, 0, 0, kRenderNormal, 20); // Красный
    }
    
    remove_task(id + 100);
    set_task(PROTECTION_TIME, "Task_RemoveProtection", id + 100);
}

public Task_RemoveProtection(taskid) {
    new id = taskid - 100;
    RemoveProtection(id);
}

public RemoveProtection(id) {
    if (is_user_connected(id) && g_bProtected[id]) {
        g_bProtected[id] = false;
        set_pev(id, pev_takedamage, DAMAGE_AIM);
        set_user_rendering(id, kRenderFxNone, 0, 0, 0, kRenderNormal, 0); // Снимаем свечение
    }
}

public OnPlayerTakeDamage_Pre(victim, inflictor, attacker, Float:damage, damagebits) {
    // Если жертва под защитой, блокируем урон
    if (g_bProtected[victim]) {
        return HAM_SUPERCEDE;
    }
    
    if (get_pcvar_num(g_pCvarFFA)) {
        if (is_user_connected(attacker) && victim != attacker) {
            if (cs_get_user_team(victim) == cs_get_user_team(attacker)) {
                g_iFakeTeam[victim] = get_pdata_int(victim, OFFSET_TEAM, EXTRA_OFFSET);
                new fake_team = (g_iFakeTeam[victim] == 1) ? 2 : 1;
                set_pdata_int(victim, OFFSET_TEAM, fake_team, EXTRA_OFFSET);
            }
        }
    } else {
        if (is_user_connected(attacker) && victim != attacker) {
            if (cs_get_user_team(victim) == cs_get_user_team(attacker)) {
                return HAM_SUPERCEDE;
            }
        }
    }
    return HAM_IGNORED;
}

public OnPlayerTakeDamage_Post(victim, inflictor, attacker, Float:damage, damagebits) {
    if (g_iFakeTeam[victim]) {
        set_pdata_int(victim, OFFSET_TEAM, g_iFakeTeam[victim], EXTRA_OFFSET);
        g_iFakeTeam[victim] = 0;
    }
    
    if (get_pcvar_num(g_pCvarDamageIndicator)) {
        // Урон теперь отрисовывается внутри custom_fog.sma
        // через хук Ham_TakeDamage и чтение квара csdm_damage_indicator,
        // чтобы не конфликтовать с HUD-фреймами от WH.
    }
}

public OnPlayerTraceAttack_Pre(victim, attacker, Float:damage, Float:direction[3], tracehandle, damagebits) {
    if (get_pcvar_num(g_pCvarFFA)) {
        if (is_user_connected(attacker) && victim != attacker) {
            if (cs_get_user_team(victim) == cs_get_user_team(attacker)) {
                g_iFakeTeam[victim] = get_pdata_int(victim, OFFSET_TEAM, EXTRA_OFFSET);
                new fake_team = (g_iFakeTeam[victim] == 1) ? 2 : 1;
                set_pdata_int(victim, OFFSET_TEAM, fake_team, EXTRA_OFFSET);
            }
        }
    } else {
        if (is_user_connected(attacker) && victim != attacker) {
            if (cs_get_user_team(victim) == cs_get_user_team(attacker)) {
                return HAM_SUPERCEDE;
            }
        }
    }
    return HAM_IGNORED;
}

public OnPlayerTraceAttack_Post(victim, attacker, Float:damage, Float:direction[3], tracehandle, damagebits) {
    if (g_iFakeTeam[victim]) {
        set_pdata_int(victim, OFFSET_TEAM, g_iFakeTeam[victim], EXTRA_OFFSET);
        g_iFakeTeam[victim] = 0;
    }
}

public Fwd_CmdStart(id, uc_handle, seed) {
    if (!is_user_alive(id) || !g_bProtected[id]) return FMRES_IGNORED;
    
    new button = get_uc(uc_handle, UC_Buttons);
    if (button & IN_ATTACK || button & IN_ATTACK2) {
        // Снимаем защиту, если игрок начал стрелять
        RemoveProtection(id);
    }
    
    return FMRES_IGNORED;
}

// ----------------------------------------------------
// МОДУЛЬ: Смена команды
// ----------------------------------------------------
public Cmd_TeamChange(id) {
    if (is_user_connected(id)) {
        // Очищаем бит, который запрещает менять команду более 1 раза (offset 125, bit 8)
        set_pdata_int(id, 125, get_pdata_int(id, 125, EXTRA_OFFSET) & ~(1<<8), EXTRA_OFFSET);
        if (!is_user_alive(id)) {
            set_task(0.5, "Task_Respawn", id);
        }
    }
    return PLUGIN_CONTINUE;
}

public Cmd_JoinClass(id) {
    if (is_user_connected(id) && !is_user_alive(id)) {
        // Запускаем респавн с небольшой задержкой, чтобы движок успел перевести игрока в команду
        set_task(0.5, "Task_Respawn", id);
    }
    return PLUGIN_CONTINUE;
}

// ----------------------------------------------------
// МОДУЛЬ: Меню Оружия (Weapon System)
// ----------------------------------------------------
public Cmd_Guns(id) {
    if (is_user_alive(id)) {
        g_bAutoEquip[id] = false;
        if (g_bHasWeaponsSelected[id]) {
            ShowEquipMenu(id);
        } else {
            ShowPrimaryMenu(id);
        }
    }
    return PLUGIN_HANDLED;
}

public ShowEquipMenu(id) {
    new menu = menu_create("\yCSDM: Экипировка", "EquipMenu_Handler");
    
    menu_additem(menu, "Предыдущий выбор", "1");
    menu_additem(menu, "Больше не спрашивать \d(Авто)\w", "2");
    menu_additem(menu, "Новый выбор оружия", "3");
    
    menu_additem(menu, "\rНастройки сервера", "4");
    
    menu_setprop(menu, MPROP_EXIT, MEXIT_ALL);
    menu_display(id, menu, 0);
}

public EquipMenu_Handler(id, menu, item) {
    if (item == MENU_EXIT || !is_user_alive(id)) {
        menu_destroy(menu);
        return PLUGIN_HANDLED;
    }
    
    new data[6], iName[64];
    new access, callback;
    menu_item_getinfo(menu, item, access, data, charsmax(data), iName, charsmax(iName), callback);
    new key = str_to_num(data);
    
    if (key == 1) {
        EquipPlayer(id);
    } else if (key == 2) {
        g_bAutoEquip[id] = true;
        EquipPlayer(id);
        client_print(id, print_chat, "[CSDM] Авто-экипировка включена. Напишите /guns для изменения.");
    } else if (key == 3) {
        ShowPrimaryMenu(id);
    } else if (key == 4) {
        ShowSettingsMenu(id);
    }
    
    menu_destroy(menu);
    return PLUGIN_HANDLED;
}

public ShowPrimaryMenu(id) {
    new menu = menu_create("\yCSDM: Основное оружие", "PrimaryMenu_Handler");
    
    for (new i = 0; i < sizeof(g_szPrimaryNames); i++) {
        new num[4]; num_to_str(i, num, charsmax(num));
        menu_additem(menu, g_szPrimaryNames[i], num);
    }
    
    menu_setprop(menu, MPROP_EXIT, MEXIT_ALL);
    menu_display(id, menu, 0);
}

public PrimaryMenu_Handler(id, menu, item) {
    if (item == MENU_EXIT || !is_user_alive(id)) {
        menu_destroy(menu);
        return PLUGIN_HANDLED;
    }
    
    new data[6], iName[64];
    new access, callback;
    menu_item_getinfo(menu, item, access, data, charsmax(data), iName, charsmax(iName), callback);
    new key = str_to_num(data);
    
    g_iPrimarySelected[id] = key;
    menu_destroy(menu);
    
    // Переход ко вторичному оружию
    ShowSecondaryMenu(id);
    
    return PLUGIN_HANDLED;
}

public ShowSettingsMenu(id) {
    new menu = menu_create("\yCSDM Server Settings", "SettingsMenu_Handler");
    
    if (get_pcvar_num(g_pCvarFFA)) {
        menu_additem(menu, "Mode: \rFree For All", "1");
    } else {
        menu_additem(menu, "Mode: \yTeam Deathmatch", "1");
    }
    
    if (get_pcvar_num(g_pCvarVisualSpawns)) {
        menu_additem(menu, "Visual Spawns: \yON", "2");
    } else {
        menu_additem(menu, "Visual Spawns: \rOFF", "2");
    }
    
    menu_additem(menu, "Damage Counter Settings", "3");
    
    menu_additem(menu, "Kill Sounds Settings", "4");
    
    new szItem[64];
    new diffStr[16];
    new diff = get_pcvar_num(g_pCvarBotDifficulty);
    switch(diff) {
        case 0: diffStr = "Noob";
        case 1: diffStr = "Easy";
        case 2: diffStr = "Normal";
        case 3: diffStr = "Hard";
        case 4: diffStr = "Expert";
        default: diffStr = "Unknown";
    }
    formatex(szItem, charsmax(szItem), "Bot Difficulty: \y%s", diffStr);
    menu_additem(menu, szItem, "5");
    
    if (get_pcvar_num(g_pCvarCustomModels)) {
        menu_additem(menu, "Custom Player Models: \yON", "6");
    } else {
        menu_additem(menu, "Custom Player Models: \rOFF", "6");
    }
    
    if (get_pcvar_num(g_pCvarDeagleBuff)) {
        menu_additem(menu, "Deagle Buff: \yON", "7");
    } else {
        menu_additem(menu, "Deagle Buff: \rOFF", "7");
    }
    
    menu_additem(menu, "Change Map \y(Now)", "8");
    
    menu_setprop(menu, MPROP_EXIT, MEXIT_ALL);
    menu_display(id, menu, 0);
}

public SettingsMenu_Handler(id, menu, item) {
    if (item == MENU_EXIT) {
        menu_destroy(menu);
        if (g_bHasWeaponsSelected[id]) {
            ShowEquipMenu(id);
        } else {
            ShowPrimaryMenu(id);
        }
        return PLUGIN_HANDLED;
    }
    
    new data[6], iName[64];
    new access, callback;
    menu_item_getinfo(menu, item, access, data, charsmax(data), iName, charsmax(iName), callback);
    new key = str_to_num(data);
    
    if (key == 1) {
        new bFFA = !get_pcvar_num(g_pCvarFFA);
        set_pcvar_num(g_pCvarFFA, bFFA);
        server_cmd("yb_csdm_mode %d", bFFA ? 2 : 1);
        client_print(0, print_chat, "[CSDM] Mode changed to %s!", bFFA ? "Free For All" : "Team Deathmatch");
    } else if (key == 2) {
        set_pcvar_num(g_pCvarVisualSpawns, !get_pcvar_num(g_pCvarVisualSpawns));
        client_print(id, print_chat, "[CSDM] Visual Spawn Points are now %s.", get_pcvar_num(g_pCvarVisualSpawns) ? "ON" : "OFF");
    } else if (key == 3) {
        menu_destroy(menu);
        ShowDamageSettingsMenu(id);
        return PLUGIN_HANDLED;
    } else if (key == 4) {
        menu_destroy(menu);
        ShowSoundSettingsMenu(id);
        return PLUGIN_HANDLED;
    } else if (key == 5) {
        new diff = get_pcvar_num(g_pCvarBotDifficulty) + 1;
        if (diff > 4) diff = 0;
        set_pcvar_num(g_pCvarBotDifficulty, diff);
        server_cmd("yb_difficulty %d", diff);
    } else if (key == 6) {
        new bModels = !get_pcvar_num(g_pCvarCustomModels);
        set_pcvar_num(g_pCvarCustomModels, bModels);
        
        // Apply immediately
        for (new i = 1; i <= get_maxplayers(); i++) {
            if (is_user_alive(i)) {
                if (bModels && !is_user_bot(i)) {
                    cs_set_user_model(i, "asuka");
                } else {
                    cs_reset_user_model(i);
                }
            }
        }
    } else if (key == 7) {
        set_pcvar_num(g_pCvarDeagleBuff, !get_pcvar_num(g_pCvarDeagleBuff));
    } else if (key == 8) {
        menu_destroy(menu);
        ShowAdminMapMenu(id);
        return PLUGIN_HANDLED;
    }
    
    SaveSettings();
    
    menu_destroy(menu);
    ShowSettingsMenu(id);
    return PLUGIN_HANDLED;
}

public ShowDamageSettingsMenu(id) {
    new menu = menu_create("\yCSDM Damage Settings", "DamageSettingsMenu_Handler");
    
    if (get_pcvar_num(g_pCvarDamageIndicator)) {
        menu_additem(menu, "Damage Indicator: \yON", "1");
    } else {
        menu_additem(menu, "Damage Indicator: \rOFF", "1");
    }
    
    new szItem[64];
    formatex(szItem, charsmax(szItem), "Size: \y%s", get_pcvar_num(g_pCvarDmgSize) ? "Large" : "Small");
    menu_additem(menu, szItem, "2");
    
    formatex(szItem, charsmax(szItem), "Opaque: \y%s", get_pcvar_num(g_pCvarDmgOpaque) ? "ON" : "OFF");
    menu_additem(menu, szItem, "3");
    
    formatex(szItem, charsmax(szItem), "Set Scatter: \y%d", get_pcvar_num(g_pCvarDmgScatter));
    menu_additem(menu, szItem, "4");
    
    menu_additem(menu, "\dBack to Server Settings", "5");
    
    menu_setprop(menu, MPROP_EXIT, MEXIT_ALL);
    menu_display(id, menu, 0);
}

public DamageSettingsMenu_Handler(id, menu, item) {
    if (item == MENU_EXIT) {
        menu_destroy(menu);
        return PLUGIN_HANDLED;
    }
    
    new data[6], iName[64];
    new access, callback;
    menu_item_getinfo(menu, item, access, data, charsmax(data), iName, charsmax(iName), callback);
    new key = str_to_num(data);
    
    if (key == 1) {
        set_pcvar_num(g_pCvarDamageIndicator, !get_pcvar_num(g_pCvarDamageIndicator));
        SaveSettings();
    } else if (key == 2) {
        set_pcvar_num(g_pCvarDmgSize, !get_pcvar_num(g_pCvarDmgSize));
        SaveSettings();
    } else if (key == 3) {
        set_pcvar_num(g_pCvarDmgOpaque, !get_pcvar_num(g_pCvarDmgOpaque));
        SaveSettings();
    } else if (key == 4) {
        client_cmd(id, "messagemode amx_csdm_dmg_set_scatter");
        menu_destroy(menu);
        return PLUGIN_HANDLED;
    } else if (key == 5) {
        menu_destroy(menu);
        ShowSettingsMenu(id);
        return PLUGIN_HANDLED;
    }
    
    menu_destroy(menu);
    ShowDamageSettingsMenu(id);
    return PLUGIN_HANDLED;
}

public cmd_csdm_set_scatter(id) {
    new arg[32]; read_args(arg, charsmax(arg)); remove_quotes(arg); trim(arg);
    if (strlen(arg) > 0) {
        new scatter = str_to_num(arg);
        if (scatter < 0) scatter = 0;
        if (scatter > 50) scatter = 50;
        set_pcvar_num(g_pCvarDmgScatter, scatter);
        SaveSettings();
    }
    ShowDamageSettingsMenu(id);
    return PLUGIN_HANDLED;
}

public ShowSoundSettingsMenu(id) {
    new menu = menu_create("\yCSDM Kill Sounds Settings", "SoundSettingsMenu_Handler");
    
    if (get_pcvar_num(g_pCvarHeadshotSound)) {
        menu_additem(menu, "Headshot Sound: \yON", "1");
    } else {
        menu_additem(menu, "Headshot Sound: \rOFF", "1");
    }
    
    new szItem[64];
    formatex(szItem, charsmax(szItem), "Sounds Volume: \y%d%%", get_pcvar_num(g_pCvarKillVolume));
    menu_additem(menu, szItem, "2");
    
    menu_additem(menu, "\dBack to Server Settings", "3");
    
    menu_setprop(menu, MPROP_EXIT, MEXIT_ALL);
    menu_display(id, menu, 0);
}

public SoundSettingsMenu_Handler(id, menu, item) {
    if (item == MENU_EXIT) {
        menu_destroy(menu);
        return PLUGIN_HANDLED;
    }
    
    new data[6], iName[64];
    new access, callback;
    menu_item_getinfo(menu, item, access, data, charsmax(data), iName, charsmax(iName), callback);
    new key = str_to_num(data);
    
    if (key == 1) {
        set_pcvar_num(g_pCvarHeadshotSound, !get_pcvar_num(g_pCvarHeadshotSound));
        SaveSettings();
    } else if (key == 2) {
        client_cmd(id, "messagemode amx_csdm_set_volume");
        menu_destroy(menu);
        return PLUGIN_HANDLED;
    } else if (key == 3) {
        menu_destroy(menu);
        ShowSettingsMenu(id);
        return PLUGIN_HANDLED;
    }
    
    menu_destroy(menu);
    ShowSoundSettingsMenu(id);
    return PLUGIN_HANDLED;
}

public cmd_csdm_set_volume(id) {
    new arg[32]; read_args(arg, charsmax(arg)); remove_quotes(arg); trim(arg);
    if (strlen(arg) > 0) {
        new vol = str_to_num(arg);
        if (vol < 0) vol = 0;
        if (vol > 100) vol = 100;
        set_pcvar_num(g_pCvarKillVolume, vol);
        SaveSettings();
    }
    ShowSoundSettingsMenu(id);
    return PLUGIN_HANDLED;
}

public SaveSettings() {
    new szCfgDir[64], szFile[128];
    get_localinfo("amxx_configsdir", szCfgDir, charsmax(szCfgDir));
    formatex(szFile, charsmax(szFile), "%s/csdm/settings.cfg", szCfgDir);
    
    new file = fopen(szFile, "wt");
    if (file) {
        fprintf(file, "csdm_ffa %d^n", get_pcvar_num(g_pCvarFFA));
        fprintf(file, "csdm_visual_spawns %d^n", get_pcvar_num(g_pCvarVisualSpawns));
        fprintf(file, "csdm_damage_indicator %d^n", get_pcvar_num(g_pCvarDamageIndicator));
        fprintf(file, "csdm_hs_sound %d^n", get_pcvar_num(g_pCvarHeadshotSound));
        fprintf(file, "csdm_kill_volume %d^n", get_pcvar_num(g_pCvarKillVolume));
        fprintf(file, "csdm_bot_difficulty %d^n", get_pcvar_num(g_pCvarBotDifficulty));
        fprintf(file, "csdm_custom_models %d^n", get_pcvar_num(g_pCvarCustomModels));
        fprintf(file, "csdm_deagle_buff %d^n", get_pcvar_num(g_pCvarDeagleBuff));
        
        fprintf(file, "amx_dmg_size %d^n", get_pcvar_num(g_pCvarDmgSize));
        fprintf(file, "amx_dmg_opaque %d^n", get_pcvar_num(g_pCvarDmgOpaque));
        fprintf(file, "amx_dmg_scatter %d^n", get_pcvar_num(g_pCvarDmgScatter));
        
        fclose(file);
    }
}

public ShowSecondaryMenu(id) {
    new menu = menu_create("\yCSDM: Вторичное оружие", "SecondaryMenu_Handler");
    
    for (new i = 0; i < sizeof(g_szSecondaryNames); i++) {
        new num[4]; num_to_str(i, num, charsmax(num));
        menu_additem(menu, g_szSecondaryNames[i], num);
    }
    
    menu_setprop(menu, MPROP_EXIT, MEXIT_ALL);
    menu_display(id, menu, 0);
}

public SecondaryMenu_Handler(id, menu, item) {
    if (item == MENU_EXIT || !is_user_alive(id)) {
        menu_destroy(menu);
        return PLUGIN_HANDLED;
    }
    
    new data[6], iName[64];
    new access, callback;
    menu_item_getinfo(menu, item, access, data, charsmax(data), iName, charsmax(iName), callback);
    
    g_iSecondarySelected[id] = str_to_num(data);
    g_bHasWeaponsSelected[id] = true;
    menu_destroy(menu);
    
    // Выдаем оружие после того, как все выбрано
    EquipPlayer(id);
    
    return PLUGIN_HANDLED;
}

public EquipPlayer(id) {
    if (!is_user_alive(id)) return;
    
    new pIdx = g_iPrimarySelected[id];
    new sIdx = g_iSecondarySelected[id];
    
    // Даем основное
    give_item(id, g_szPrimaryEnts[pIdx]);
    // Даем пистолет
    give_item(id, g_szSecondaryEnts[sIdx]);
    
    // Выдача патронов (90 primary, 100 secondary) - стандарт для CSDM
    new wpnid = get_weaponid(g_szPrimaryEnts[pIdx]);
    if (wpnid) cs_set_user_bpammo(id, wpnid, 90);
    
    wpnid = get_weaponid(g_szSecondaryEnts[sIdx]);
    if (wpnid) cs_set_user_bpammo(id, wpnid, 100);
}


// ----------------------------------------------------
// МОДУЛЬ: Кастомные Спавны (Custom Spawns)
// ----------------------------------------------------
public LoadCustomSpawns() {
    new szMapName[32], szCfgDir[64], szFile[128];
    get_mapname(szMapName, charsmax(szMapName));
    get_localinfo("amxx_configsdir", szCfgDir, charsmax(szCfgDir));
    
    formatex(szFile, charsmax(szFile), "%s/csdm/spawns/%s.spawns.cfg", szCfgDir, szMapName);
    
    g_iSpawnCount = 0;
    g_bHasCustomSpawns = false;
    
    if (!file_exists(szFile)) {
        server_print("[CSDM] Spawn file not found: %s", szFile);
        return;
    }
    
    new file = fopen(szFile, "rt");
    if (!file) return;
    
    new szLine[128], szX[16], szY[16], szZ[16], szAngX[16], szAngY[16], szAngZ[16];
    
    while (!feof(file) && g_iSpawnCount < MAX_SPAWNS) {
        fgets(file, szLine, charsmax(szLine));
        trim(szLine);
        
        // Пропускаем пустые строки и комментарии
        if (szLine[0] == 0 || szLine[0] == ';' || szLine[0] == '#') continue;
        
        // Ожидаемый формат: X Y Z AngX AngY AngZ
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
    
    if (g_iSpawnCount > 0) {
        g_bHasCustomSpawns = true;
        server_print("[CSDM] Loaded %d custom spawns for map %s", g_iSpawnCount, szMapName);
    }
}

public DoCustomSpawn(id) {
    if (!g_bHasCustomSpawns || g_iSpawnCount <= 0) return; // Используем дефолтные точки
    
    new bestIndex = random_num(0, g_iSpawnCount - 1);
    new maxAttempts = 10;
    new bFFA = get_pcvar_num(g_pCvarFFA);
    new CsTeams:idTeam = cs_get_user_team(id);
    
    for (new attempt = 0; attempt < maxAttempts; attempt++) {
        new randIndex = random_num(0, g_iSpawnCount - 1);
        new bool:bGood = true;
        
        for (new i = 1; i <= get_maxplayers(); i++) {
            if (!is_user_alive(i) || i == id)
                continue;
                
            if (!bFFA && cs_get_user_team(i) == idTeam)
                continue;
                
            new Float:fPlrOrigin[3];
            pev(i, pev_origin, fPlrOrigin);
            
            if (get_distance_f(g_fSpawns[randIndex], fPlrOrigin) < 600.0) {
                bGood = false;
                break;
            }
        }
        
        if (bGood) {
            bestIndex = randIndex;
            break;
        }
    }
    
    engfunc(EngFunc_SetOrigin, id, g_fSpawns[bestIndex]);
    set_pev(id, pev_angles, g_fSpawnAngles[bestIndex]);
    set_pev(id, pev_fixangle, 1);
}

// ----------------------------------------------------
// МОДУЛЬ: Отрисовка Звуков Убийств (Valorant Kill Sounds)
// ----------------------------------------------------
public Event_DeathMsg() {
    new killer = read_data(1);
    new victim = read_data(2);
    new headshot = read_data(3);
    
    if(is_user_connected(victim)) {
        g_KillCount[victim] = 0;
    }
    
    if(!is_user_connected(killer) || killer == victim) {
        return PLUGIN_CONTINUE;
    }
    
    if(!is_user_bot(killer)) {
        new hp = get_user_health(killer);
        set_user_health(killer, min(hp + 30, 100));
        
        new weapons[32], num;
        get_user_weapons(killer, weapons, num);
        
        for(new i = 0; i < num; i++) {
            new wpn_id = weapons[i];
            if(wpn_id == CSW_KNIFE || wpn_id == CSW_HEGRENADE || wpn_id == CSW_FLASHBANG || wpn_id == CSW_SMOKEGRENADE || wpn_id == CSW_C4) {
                continue;
            }
            
            new wpn_name[32];
            get_weaponname(wpn_id, wpn_name, charsmax(wpn_name));
            new wpn_ent = fm_find_ent_by_owner(-1, wpn_name, killer);
            
            if(wpn_ent > 0) {
                new clip = cs_get_weapon_ammo(wpn_ent);
                new max_clip = g_iMaxClip[wpn_id];
                new add_ammo = 0;
                
                if(wpn_id == CSW_P228 || wpn_id == CSW_ELITE || wpn_id == CSW_FIVESEVEN || wpn_id == CSW_USP || wpn_id == CSW_GLOCK18 || wpn_id == CSW_DEAGLE) {
                    add_ammo = max_clip - clip;
                } else if(wpn_id == CSW_AWP || wpn_id == CSW_SCOUT || wpn_id == CSW_G3SG1 || wpn_id == CSW_SG550) {
                    add_ammo = 3;
                } else {
                    add_ammo = 10;
                }
                
                new new_clip = clip + add_ammo;
                if(new_clip > max_clip) {
                    new_clip = max_clip;
                }
                
                cs_set_weapon_ammo(wpn_ent, new_clip);
            }
        }
    }
    
    if(g_PlayerSeries[killer] == 0) {
        g_PlayerSeries[killer] = 1;
    }
    
    g_KillCount[killer]++;
    
    new kill_number = g_KillCount[killer];
    if(kill_number > MAX_KILLS) {
        kill_number = MAX_KILLS;
    }
    
    new sound_path[64];
    formatex(sound_path, charsmax(sound_path), "valorant/%d/kill%d.wav", g_PlayerSeries[killer], kill_number);
    
    new Float:vol = float(get_pcvar_num(g_pCvarKillVolume)) / 100.0;
    emit_sound(killer, CHAN_AUTO, sound_path, vol, ATTN_NORM, 0, PITCH_NORM);
    
    if(headshot && get_pcvar_num(g_pCvarHeadshotSound)) {
        emit_sound(killer, CHAN_STATIC, "valorant/headshot.wav", vol, ATTN_NORM, 0, PITCH_NORM);
    }
    
    if (!is_user_bot(killer)) {
        message_begin(MSG_ONE_UNRELIABLE, g_msgScreenFade, _, killer);
        write_short(1<<11);  // ~0.5 секунды
        write_short(0);      // Без задержки (hold time)
        write_short(0x0000); // Эффект затухания (Fade In)
        if (headshot) {
            write_byte(255); // R (Золотисто-оранжевый)
            write_byte(170); // G
            write_byte(50);  // B
            write_byte(40);  // Alpha (ненавязчиво)
        } else {
            write_byte(150); // R (Голубоватый)
            write_byte(200); // G
            write_byte(255); // B
            write_byte(30);  // Alpha (чуть слабее)
        }
        message_end();
    }
    
    return PLUGIN_CONTINUE;
}

stock fm_find_ent_by_owner(index, const classname[], owner, jghgtype = 0) {
    new strtype[11] = "classname", ent = index;
    switch (jghgtype) {
        case 1: strtype = "target";
        case 2: strtype = "targetname";
    }
    while ((ent = engfunc(EngFunc_FindEntityByString, ent, strtype, classname)) && pev(ent, pev_owner) != owner) {}
    return ent;
}

public OnDeaglePrimaryAttack_Pre(weapon) {
    if (!get_pcvar_num(g_pCvarDeagleBuff)) return HAM_IGNORED;
    if (!pev_valid(weapon)) return HAM_IGNORED;
    
    new id = pev(weapon, pev_owner);
    if (!is_user_alive(id)) return HAM_IGNORED;
    
    new Float:velocity[3];
    pev(id, pev_velocity, velocity);
    new Float:speed = vector_length(velocity);
    
    if (speed < 120.0) {
        set_pdata_float(weapon, m_flAccuracy, 0.95, OFFSET_LINUX_WEAPONS);
    }
    
    return HAM_IGNORED;
}

public OnDeaglePrimaryAttack_Post(weapon) {
    if (!get_pcvar_num(g_pCvarDeagleBuff)) return;
    if (!pev_valid(weapon)) return;
    
    new id = pev(weapon, pev_owner);
    if (!is_user_alive(id)) return;
    
    new Float:velocity[3];
    pev(id, pev_velocity, velocity);
    new Float:speed = vector_length(velocity);
    
    if (speed < 120.0) {
        new Float:punch[3];
        pev(id, pev_punchangle, punch);
        punch[0] *= 0.3;
        punch[1] *= 0.3;
        punch[2] *= 0.3;
        set_pev(id, pev_punchangle, punch);
    }
}

// ----------------------------------------------------
// МОДУЛЬ: Голосование за Карту (Map Voting)
// ----------------------------------------------------
public Task_CheckTimeleft() {
    if (get_cvar_num("mp_timelimit") > 0) {
        new timeleft = get_timeleft();
        
        if (timeleft <= 0 && !g_bMapChanging) {
            g_bMapChanging = true;
            
            new currentMap[32], nextMap[32];
            get_mapname(currentMap, charsmax(currentMap));
            
            new nextIndex = 0;
            for (new i = 0; i < g_iVoteMapsCount; i++) {
                if (equal(currentMap, g_szVoteMaps[i])) {
                    nextIndex = (i + 1) % g_iVoteMapsCount;
                    break;
                }
            }
            
            copy(nextMap, charsmax(nextMap), g_szVoteMaps[nextIndex]);
            client_print(0, print_chat, "[CSDM] Время вышло! Следующая карта: %s", nextMap);
            server_cmd("changelevel %s", nextMap);
        }
    }
}

public ShowAdminMapMenu(id) {
    new menu = menu_create("\yCSDM: Сменить карту", "AdminMapMenu_Handler");
    for (new i = 0; i < g_iVoteMapsCount; i++) {
        new numStr[4];
        num_to_str(i + 1, numStr, charsmax(numStr));
        menu_additem(menu, g_szVoteMaps[i], numStr);
    }
    
    menu_additem(menu, "\y[Добавить карту]", "add_map");
    
    menu_setprop(menu, MPROP_EXIT, MEXIT_ALL);
    menu_display(id, menu, 0);
}

public AdminMapMenu_Handler(id, menu, item) {
    if (item == MENU_EXIT) {
        menu_destroy(menu);
        ShowSettingsMenu(id);
        return PLUGIN_HANDLED;
    }
    
    new data[16], iName[64], access, callback;
    menu_item_getinfo(menu, item, access, data, charsmax(data), iName, charsmax(iName), callback);
    
    if (equal(data, "add_map")) {
        client_cmd(id, "messagemode amx_csdm_add_map");
        menu_destroy(menu);
        return PLUGIN_HANDLED;
    }
    
    new key = str_to_num(data) - 1;
    if (key >= 0 && key < g_iVoteMapsCount) {
        client_print(0, print_chat, "[CSDM] Карта сменена на %s", g_szVoteMaps[key]);
        server_cmd("changelevel %s", g_szVoteMaps[key]);
    }
    
    menu_destroy(menu);
    return PLUGIN_HANDLED;
}

public cmd_add_map(id) {
    new arg[32]; 
    read_args(arg, charsmax(arg)); 
    remove_quotes(arg); 
    trim(arg);
    
    if (strlen(arg) > 0) {
        if (g_iVoteMapsCount < MAX_MAPS) {
            copy(g_szVoteMaps[g_iVoteMapsCount], 31, arg);
            g_iVoteMapsCount++;
            client_print(id, print_chat, "[CSDM] Карта %s добавлена в очередь.", arg);
        } else {
            client_print(id, print_chat, "[CSDM] Очередь карт переполнена!");
        }
    }
    ShowAdminMapMenu(id);
    return PLUGIN_HANDLED;
}
