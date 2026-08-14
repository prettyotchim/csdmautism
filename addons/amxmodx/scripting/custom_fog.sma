#include <amxmodx>
#include <amxmisc>
#include <hamsandwich>
#include <fakemeta>
#include <nvault>

#define PLUGIN  "Custom Weather Plugin"
#define VERSION "1.2"
#define AUTHOR  "AI"

// Increase stack size to avoid overflow during deep recursion in PrecacheDirectory
#pragma dynamic 32768

// ============================================================
// GLOBAL (server-wide) — only Snow/Rain and Skybox
// Engine limitation: these cannot be made per-player in GoldSrc
// ============================================================
new g_msgFog;
new g_msgSetFOV;

// Snow & Rain
new cvar_snow_enable;
new cvar_rain_enable;
new cvar_snow_intensity;
new g_iSnowEnt = 0;
new g_iRainEnt = 0;

// Skybox (sv_skyname is server-wide)
new cvar_skybox_enable;
new cvar_skybox_name;
new g_szDefaultSky[32];

// Sprite handles
new g_spriteLaser;
new g_spriteTracer;

// Storage
new g_hVault;
new Trie:g_trieSounds;

// ============================================================
// PER-PLAYER settings arrays  [index 0 unused; 1-32 = players]
// Each player has their own independent copy of every setting.
// ============================================================

// --- Fog ---
new g_iFogEnable[33];
new g_iFogR[33], g_iFogG[33], g_iFogB[33];
new g_iFogDensity[33];
new g_iFogRGBEnable[33];
new Float:g_fFogRGBSpeed[33];
new g_iFogRGBState[33];
new Float:g_fFogCurR[33], Float:g_fFogCurG[33], Float:g_fFogCurB[33];

// --- Tracer ---
new g_iTracerEnable[33];
new g_iTracerR[33], g_iTracerG[33], g_iTracerB[33];
new bool:g_bFiring[33];

// --- FOV ---
new g_iFOVEnable[33];
new g_iFOVValue[33];

// --- Bunnyhop ---
new g_iBhopEnable[33];

// --- Wallhack / ESP ---
new g_iWHEnable[33];
new g_iWHBeams[33];
new g_iWHBeamsR[33], g_iWHBeamsG[33], g_iWHBeamsB[33];
new g_iWHBeamsWidth[33];
new g_iWHBeamsRGBEnable[33];
new Float:g_fWHBeamsRGBSpeed[33];
new g_iWHBeamsRGBState[33];
new Float:g_fWHCurR[33], Float:g_fWHCurG[33], Float:g_fWHCurB[33];
new g_iWHTeammates[33];
new g_iWHHighlightHumans[33];
new g_iWHFill[33];
new g_iWHMarkers[33];

#define MAX_WH_CHANNELS 16
#define HUD_CHAR_W      0.01

// --- Damage indicator ---
new g_iDmgEnable[33];
new g_iDmgSize[33];
new g_iDmgScatter[33];
new g_iDmgOpaque[33];
new Float:g_fDamageEndTime[33];
new g_iDamageAmount[33];
new Float:g_fDamageX[33];
new Float:g_fDamageY[33];
new g_iDamageR[33], g_iDamageG[33], g_iDamageB[33];

// --- Weapon Skins (always were per-player) ---
new g_szSkinKnife[33][64];
new g_szSkinM4A1[33][64];
new g_szSkinAK47[33][64];
new bool:g_bAutoDeploySkins[33];
new bool:g_bAutoKillSkins[33];
new bool:g_bSkipDeployCycle[33][32];

new g_szAvailableSkinsKnife[32][64];
new g_iSkinsCountKnife = 0;
new g_szAvailableSkinsM4A1[32][64];
new g_iSkinsCountM4A1 = 0;
new g_szAvailableSkinsAK47[32][64];
new g_iSkinsCountAK47 = 0;

// ============================================================
// plugin_init
// ============================================================
public plugin_init() {
    register_plugin(PLUGIN, VERSION, AUTHOR);

    // Global cvars (snow/rain and skybox)
    cvar_snow_enable    = register_cvar("amx_snow_enable",    "0");
    cvar_rain_enable    = register_cvar("amx_rain_enable",    "0");
    cvar_snow_intensity = register_cvar("amx_snow_intensity", "3");
    cvar_skybox_enable  = register_cvar("amx_skybox_enable",  "0");
    cvar_skybox_name    = register_cvar("amx_skybox_name",    "custom_sky");

    // Weapon attack hooks (for tracers and firing state)
    new const WEAPONS_FIREARMS[][] = {
        "weapon_p228", "weapon_scout", "weapon_xm1014", "weapon_mac10",
        "weapon_aug", "weapon_elite", "weapon_fiveseven", "weapon_ump45", "weapon_sg550",
        "weapon_galil", "weapon_famas", "weapon_usp", "weapon_glock18", "weapon_awp",
        "weapon_mp5navy", "weapon_m249", "weapon_m3", "weapon_m4a1", "weapon_tmp",
        "weapon_g3sg1", "weapon_deagle", "weapon_sg552", "weapon_ak47", "weapon_p90"
    };
    for (new i = 0; i < sizeof(WEAPONS_FIREARMS); i++) {
        RegisterHam(Ham_Weapon_PrimaryAttack, WEAPONS_FIREARMS[i], "fw_PrimaryAttack_Pre",  0);
        RegisterHam(Ham_Weapon_PrimaryAttack, WEAPONS_FIREARMS[i], "fw_PrimaryAttack_Post", 1);
    }
    RegisterHam(Ham_Item_PostFrame, "weapon_glock18", "fw_ItemPostFrame_Pre",  0);
    RegisterHam(Ham_Item_PostFrame, "weapon_glock18", "fw_ItemPostFrame_Post", 1);
    RegisterHam(Ham_Item_PostFrame, "weapon_famas",   "fw_ItemPostFrame_Pre",  0);
    RegisterHam(Ham_Item_PostFrame, "weapon_famas",   "fw_ItemPostFrame_Post", 1);

    register_forward(FM_TraceLine,      "fw_TraceLine_Post",     1);
    register_forward(FM_AddToFullPack,  "fw_AddToFullPack_Post", 1);
    register_forward(FM_PlayerPreThink, "fw_PlayerPreThink");
    register_forward(FM_EmitSound,      "fw_EmitSound");

    // Menu commands
    register_clcmd("amx_fog_menu",    "cmd_fog_menu",    0, "- shows fog settings menu");
    register_clcmd("amx_snow_menu",   "cmd_snow_menu",   0, "- shows snow settings menu");
    register_clcmd("amx_tracer_menu", "cmd_tracer_menu", 0, "- shows tracer settings menu");
    register_clcmd("amx_fov_menu",    "cmd_fov_menu",    0, "- shows fov settings menu");
    register_clcmd("amx_bhop_menu",   "cmd_bhop_menu",   0, "- shows bhop settings menu");
    register_clcmd("amx_wh_menu",     "cmd_wh_menu",     0, "- shows wh settings menu");
    register_clcmd("amx_dmg_menu",    "cmd_dmg_menu",    0, "- shows damage settings menu");
    register_clcmd("amx_skybox_menu", "cmd_skybox_menu", 0, "- shows skybox settings menu");
    register_clcmd("amx_skins_menu",  "cmd_skins_menu",  0, "- shows weapon skins menu");
    register_clcmd("amx_custom_menu", "cmd_main_menu",   0, "- shows main custom settings menu");

    // Messagemode input handlers
    register_clcmd("amx_fog_set_color",          "cmd_set_color");
    register_clcmd("amx_fog_set_density",        "cmd_set_density");
    register_clcmd("amx_fog_set_rgb_speed",      "cmd_set_rgb_speed");
    register_clcmd("amx_snow_set_intensity",     "cmd_snow_set_intensity");
    register_clcmd("amx_tracer_set_color",       "cmd_tracer_set_color");
    register_clcmd("amx_fov_set_value",          "cmd_fov_set_value");
    register_clcmd("amx_wh_beams_set_color",     "cmd_wh_beams_set_color");
    register_clcmd("amx_wh_beams_set_width",     "cmd_wh_beams_set_width");
    register_clcmd("amx_wh_beams_set_rgb_speed", "cmd_wh_beams_set_rgb_speed");
    register_clcmd("amx_dmg_set_scatter",        "cmd_dmg_set_scatter");

    g_msgFog    = get_user_msgid("Fog");
    g_msgSetFOV = get_user_msgid("SetFOV");
    register_message(g_msgSetFOV, "Message_SetFOV");

    RegisterHam(Ham_Spawn,       "player",       "OnPlayerSpawn_Post",    1);
    RegisterHam(Ham_Item_Deploy, "weapon_knife", "fw_ItemDeploy_Post",    1);
    RegisterHam(Ham_Item_Deploy, "weapon_m4a1",  "fw_ItemDeploy_Post",    1);
    RegisterHam(Ham_Item_Deploy, "weapon_ak47",  "fw_ItemDeploy_Post",    1);
    RegisterHam(Ham_TakeDamage,  "player",       "OnPlayerTakeDamage_Post", 1);
    RegisterHam(Ham_Killed,      "player",       "OnPlayerKilled_Post",   1);

    // Single combined RGB task — loops internally over all non-bot players
    set_task(0.1, "Task_RGBUpdate", .flags="b");
}

// ============================================================
// plugin_end
// ============================================================
public plugin_end() {
    if (g_hVault != INVALID_HANDLE) nvault_close(g_hVault);
    if (g_trieSounds != Invalid_Trie) TrieDestroy(g_trieSounds);
}

// ============================================================
// plugin_precache
// ============================================================
public plugin_precache() {
    g_trieSounds = TrieCreate();
    g_hVault = nvault_open("custom_settings");

    new weather_type = 1;
    if (g_hVault != INVALID_HANDLE) {
        weather_type = nvault_get(g_hVault, "GLOBAL_weather_type");
        if (weather_type == 0) weather_type = 1;
    }

    // In GoldSrc weather must be created before map start.
    // Cannot create both simultaneously — rain always takes priority.
    if (weather_type == 2) {
        g_iRainEnt = engfunc(EngFunc_CreateNamedEntity, engfunc(EngFunc_AllocString, "env_rain"));
        if (pev_valid(g_iRainEnt))
            engfunc(EngFunc_SetSize, g_iRainEnt, Float:{-8192.0,-8192.0,-8192.0}, Float:{8192.0,8192.0,8192.0});
    } else {
        g_iSnowEnt = engfunc(EngFunc_CreateNamedEntity, engfunc(EngFunc_AllocString, "env_snow"));
        if (pev_valid(g_iSnowEnt))
            engfunc(EngFunc_SetSize, g_iSnowEnt, Float:{-8192.0,-8192.0,-8192.0}, Float:{8192.0,8192.0,8192.0});
    }

    g_spriteLaser  = precache_model("sprites/laserbeam.spr");
    g_spriteTracer = precache_model("sprites/custom_tracer.spr");

    PrecacheSkins("knife");
    PrecacheSkins("m4a1");
    PrecacheSkins("ak47");
}

stock PrecacheSkins(const szWeaponType[]) {
    new szBaseDir[128];
    formatex(szBaseDir, charsmax(szBaseDir), "models/custom_skins/%s", szWeaponType);

    new dir = open_dir(szBaseDir, "", 0);
    if (!dir) return;

    new filename[64], szPath[256];
    while (next_file(dir, filename, charsmax(filename))) {
        if (filename[0] == '.') continue;
        formatex(szPath, charsmax(szPath), "%s/%s", szBaseDir, filename);
        if (dir_exists(szPath)) {
            new szModelPath[256];
            formatex(szModelPath, charsmax(szModelPath), "%s/v_%s.mdl", szPath, szWeaponType);
            new bHasBase = file_exists(szModelPath);
            
            new szVariantDir[256];
            formatex(szVariantDir, charsmax(szVariantDir), "%s/variant", szPath);
            new bHasVariant = dir_exists(szVariantDir);

            if (bHasBase) {
                precache_model(szModelPath);
                
                if      (equal(szWeaponType, "knife") && g_iSkinsCountKnife < 32) copy(g_szAvailableSkinsKnife[g_iSkinsCountKnife++], 63, filename);
                else if (equal(szWeaponType, "m4a1")  && g_iSkinsCountM4A1  < 32) copy(g_szAvailableSkinsM4A1[g_iSkinsCountM4A1++],   63, filename);
                else if (equal(szWeaponType, "ak47")  && g_iSkinsCountAK47  < 32) copy(g_szAvailableSkinsAK47[g_iSkinsCountAK47++],   63, filename);
            }

            new szSoundDir[256];
            formatex(szSoundDir, charsmax(szSoundDir), "%s/sound", szPath);
            if (dir_exists(szSoundDir)) PrecacheDirectory(szSoundDir, "");

            if (bHasVariant) {
                new vdir = open_dir(szVariantDir, "", 0);
                if (vdir) {
                    new vfile[64];
                    while (next_file(vdir, vfile, charsmax(vfile))) {
                        if (vfile[0] == '.') continue;
                        new szVModelPath[256];
                        formatex(szVModelPath, charsmax(szVModelPath), "%s/%s/v_%s.mdl", szVariantDir, vfile, szWeaponType);
                        if (file_exists(szVModelPath)) {
                            precache_model(szVModelPath);
                            
                            new szVarName[64];
                            formatex(szVarName, charsmax(szVarName), "%s/variant/%s", filename, vfile);
                            if      (equal(szWeaponType, "knife") && g_iSkinsCountKnife < 32) copy(g_szAvailableSkinsKnife[g_iSkinsCountKnife++], 63, szVarName);
                            else if (equal(szWeaponType, "m4a1")  && g_iSkinsCountM4A1  < 32) copy(g_szAvailableSkinsM4A1[g_iSkinsCountM4A1++],   63, szVarName);
                            else if (equal(szWeaponType, "ak47")  && g_iSkinsCountAK47  < 32) copy(g_szAvailableSkinsAK47[g_iSkinsCountAK47++],   63, szVarName);
                        }
                    }
                    close_dir(vdir);
                }
            }
        }
    }
    close_dir(dir);
}

stock PrecacheDirectory(const szBaseDir[], const szRelativePath[]) {
    new szFullPath[256];
    if (strlen(szRelativePath) > 0)
        formatex(szFullPath, charsmax(szFullPath), "%s/%s", szBaseDir, szRelativePath);
    else
        copy(szFullPath, charsmax(szFullPath), szBaseDir);

    new dir = open_dir(szFullPath, "", 0);
    if (!dir) return;

    new filename[128], szPath[256], szRel[256];
    while (next_file(dir, filename, charsmax(filename))) {
        if (filename[0] == '.') continue;
        formatex(szPath, charsmax(szPath), "%s/%s", szFullPath, filename);
        if (strlen(szRelativePath) > 0)
            formatex(szRel, charsmax(szRel), "%s/%s", szRelativePath, filename);
        else
            copy(szRel, charsmax(szRel), filename);

        if (dir_exists(szPath)) {
            PrecacheDirectory(szBaseDir, szRel);
        } else {
            new len = strlen(filename);
            if (len > 4 && equali(filename[len-4], ".wav")) {
                precache_generic(szPath);
                TrieSetCell(g_trieSounds, szPath, 1);
            }
        }
    }
    close_dir(dir);
}

// ============================================================
// plugin_cfg
// ============================================================
public plugin_cfg() {
    set_task(1.0, "UpdateSnow");
    get_cvar_string("sv_skyname", g_szDefaultSky, charsmax(g_szDefaultSky));
    if (get_pcvar_num(cvar_skybox_enable)) {
        new szSky[32];
        get_pcvar_string(cvar_skybox_name, szSky, charsmax(szSky));
        if (strlen(szSky) > 0) {
            new szFullSky[64];
            formatex(szFullSky, charsmax(szFullSky), "custom_skies/%s", szSky);
            set_cvar_string("sv_skyname", szFullSky);
        }
    }
}

// ============================================================
// Per-player default values
// ============================================================
stock SetPlayerDefaults(id) {
    // Fog
    g_iFogEnable[id]    = 1;
    g_iFogR[id]         = 128;
    g_iFogG[id]         = 128;
    g_iFogB[id]         = 128;
    g_iFogDensity[id]   = 1;
    g_iFogRGBEnable[id] = 0;
    g_fFogRGBSpeed[id]  = 5.0;
    g_iFogRGBState[id]  = 0;
    g_fFogCurR[id]      = 255.0;
    g_fFogCurG[id]      = 0.0;
    g_fFogCurB[id]      = 0.0;

    // Tracer
    g_iTracerEnable[id] = 0;
    g_iTracerR[id]      = 0;
    g_iTracerG[id]      = 255;
    g_iTracerB[id]      = 0;

    // FOV
    g_iFOVEnable[id] = 0;
    g_iFOVValue[id]  = 110;

    // Bhop
    g_iBhopEnable[id] = 0;

    // Wallhack
    g_iWHEnable[id]          = 0;
    g_iWHBeams[id]           = 1;
    g_iWHBeamsR[id]          = 255;
    g_iWHBeamsG[id]          = 255;
    g_iWHBeamsB[id]          = 255;
    g_iWHBeamsWidth[id]      = 3;
    g_iWHBeamsRGBEnable[id]  = 0;
    g_fWHBeamsRGBSpeed[id]   = 5.0;
    g_iWHBeamsRGBState[id]   = 0;
    g_fWHCurR[id]            = 255.0;
    g_fWHCurG[id]            = 0.0;
    g_fWHCurB[id]            = 0.0;
    g_iWHTeammates[id]       = 0;
    g_iWHHighlightHumans[id] = 0;
    g_iWHFill[id]            = 0;
    g_iWHMarkers[id]         = 0;

    // Damage
    g_iDmgEnable[id]     = 1;
    g_iDmgSize[id]       = 1;
    g_iDmgScatter[id]    = 1;
    g_iDmgOpaque[id]     = 1;
    g_fDamageEndTime[id] = 0.0;
    g_iDamageAmount[id]  = 0;
}

// ============================================================
// client_putinserver
// ============================================================
public client_putinserver(id) {
    // Reset skins
    g_szSkinKnife[id][0]   = 0;
    g_szSkinM4A1[id][0]    = 0;
    g_szSkinAK47[id][0]    = 0;
    g_bAutoDeploySkins[id] = false;
    g_bAutoKillSkins[id]   = false;

    // Apply defaults first (works for bots too)
    SetPlayerDefaults(id);

    // BOT OPTIMIZATION: bots get defaults only — no vault I/O, no cl_weather
    if (is_user_bot(id)) return;

    if (g_hVault != INVALID_HANDLE) {
        new szAuthID[32], szKey[64];
        get_user_authid(id, szAuthID, charsmax(szAuthID));

        // Load skins
        formatex(szKey, charsmax(szKey), "%s_skin_knife", szAuthID);
        nvault_get(g_hVault, szKey, g_szSkinKnife[id], 63);
        formatex(szKey, charsmax(szKey), "%s_skin_m4a1", szAuthID);
        nvault_get(g_hVault, szKey, g_szSkinM4A1[id], 63);
        formatex(szKey, charsmax(szKey), "%s_skin_ak47", szAuthID);
        nvault_get(g_hVault, szKey, g_szSkinAK47[id], 63);

        formatex(szKey, charsmax(szKey), "%s_skin_autodep", szAuthID);
        g_bAutoDeploySkins[id] = nvault_get(g_hVault, szKey) ? true : false;
        formatex(szKey, charsmax(szKey), "%s_skin_autokill", szAuthID);
        g_bAutoKillSkins[id] = nvault_get(g_hVault, szKey) ? true : false;

        // Auto-load all personal settings from vault
        LoadSettingsForPlayer(id);
    }

    // Global weather — send to this human player
    if (get_pcvar_num(cvar_snow_enable) || get_pcvar_num(cvar_rain_enable)) {
        new intensity = clamp(get_pcvar_num(cvar_snow_intensity), 1, 3);
        client_cmd(id, "cl_weather 0; cl_weather %d", intensity);
    } else {
        client_cmd(id, "cl_weather 0");
    }
}

// ============================================================
// OnPlayerSpawn_Post
// ============================================================
public OnPlayerSpawn_Post(id) {
    if (!is_user_alive(id))  return;
    if (is_user_bot(id))     return; // BOT OPTIMIZATION

    ApplyFogToPlayer(id);

    if (g_iFOVEnable[id]) {
        new custom_fov = clamp(g_iFOVValue[id], 10, 150);
        client_cmd(id, "default_fov %d", custom_fov);
        message_begin(MSG_ONE, g_msgSetFOV, _, id);
        write_byte(custom_fov);
        message_end();
    }
}

// ============================================================
// Skins: GetNextSkin / OnPlayerKilled_Post / fw_ItemDeploy_Post
// ============================================================
stock GetNextSkin(const szWeaponType[], const szCurrentSkin[], szNextSkin[], maxlen) {
    new count = 0, index = 0;
    if      (equal(szWeaponType, "knife")) count = g_iSkinsCountKnife;
    else if (equal(szWeaponType, "m4a1"))  count = g_iSkinsCountM4A1;
    else if (equal(szWeaponType, "ak47"))  count = g_iSkinsCountAK47;

    for (new i = 0; i < count; i++) {
        new szAvailable[64];
        if      (equal(szWeaponType, "knife")) copy(szAvailable, 63, g_szAvailableSkinsKnife[i]);
        else if (equal(szWeaponType, "m4a1"))  copy(szAvailable, 63, g_szAvailableSkinsM4A1[i]);
        else if (equal(szWeaponType, "ak47"))  copy(szAvailable, 63, g_szAvailableSkinsAK47[i]);
        if (equal(szAvailable, szCurrentSkin)) { index = i + 1; break; }
    }

    new nextIndex = (index + 1) % (count + 1);
    if (nextIndex == 0) {
        szNextSkin[0] = 0;
    } else {
        if      (equal(szWeaponType, "knife")) copy(szNextSkin, maxlen, g_szAvailableSkinsKnife[nextIndex - 1]);
        else if (equal(szWeaponType, "m4a1"))  copy(szNextSkin, maxlen, g_szAvailableSkinsM4A1[nextIndex - 1]);
        else if (equal(szWeaponType, "ak47"))  copy(szNextSkin, maxlen, g_szAvailableSkinsAK47[nextIndex - 1]);
    }
}

public OnPlayerKilled_Post(victim, attacker, shouldgib) {
    if (attacker < 1 || attacker > 32 || !is_user_connected(attacker)) return HAM_IGNORED;
    if (victim == attacker) return HAM_IGNORED;

    if (g_bAutoKillSkins[attacker]) {
        new iWeapon = get_user_weapon(attacker);
        new szNextSkin[64];
        if (iWeapon == CSW_KNIFE) {
            GetNextSkin("knife", g_szSkinKnife[attacker], szNextSkin, 63);
            copy(g_szSkinKnife[attacker], 63, szNextSkin);
            g_bSkipDeployCycle[attacker][CSW_KNIFE] = true;
        } else if (iWeapon == CSW_M4A1) {
            GetNextSkin("m4a1", g_szSkinM4A1[attacker], szNextSkin, 63);
            copy(g_szSkinM4A1[attacker], 63, szNextSkin);
            g_bSkipDeployCycle[attacker][CSW_M4A1] = true;
        } else if (iWeapon == CSW_AK47) {
            GetNextSkin("ak47", g_szSkinAK47[attacker], szNextSkin, 63);
            copy(g_szSkinAK47[attacker], 63, szNextSkin);
            g_bSkipDeployCycle[attacker][CSW_AK47] = true;
        }
    }
    return HAM_IGNORED;
}

public fw_ItemDeploy_Post(ent) {
    if (!pev_valid(ent)) return HAM_IGNORED;
    new id = get_pdata_cbase(ent, 41, 4);
    if (id < 1 || id > 32 || !is_user_alive(id)) return HAM_IGNORED;

    new iId = get_pdata_int(ent, 43, 4);
    new szPath[128];
    szPath[0] = 0;

    if (g_bAutoDeploySkins[id]) {
        if (g_bSkipDeployCycle[id][iId]) {
            g_bSkipDeployCycle[id][iId] = false;
        } else {
            new szNextSkin[64];
            if      (iId == CSW_KNIFE) { GetNextSkin("knife", g_szSkinKnife[id], szNextSkin, 63); copy(g_szSkinKnife[id], 63, szNextSkin); }
            else if (iId == CSW_M4A1)  { GetNextSkin("m4a1",  g_szSkinM4A1[id],  szNextSkin, 63); copy(g_szSkinM4A1[id],  63, szNextSkin); }
            else if (iId == CSW_AK47)  { GetNextSkin("ak47",  g_szSkinAK47[id],  szNextSkin, 63); copy(g_szSkinAK47[id],  63, szNextSkin); }
        }
    } else {
        g_bSkipDeployCycle[id][iId] = false;
    }

    if      (iId == CSW_KNIFE) { if (strlen(g_szSkinKnife[id]) > 0) formatex(szPath, charsmax(szPath), "models/custom_skins/knife/%s/v_knife.mdl", g_szSkinKnife[id]); else formatex(szPath, charsmax(szPath), "models/v_knife.mdl"); }
    else if (iId == CSW_M4A1)  { if (strlen(g_szSkinM4A1[id])  > 0) formatex(szPath, charsmax(szPath), "models/custom_skins/m4a1/%s/v_m4a1.mdl",   g_szSkinM4A1[id]);  else formatex(szPath, charsmax(szPath), "models/v_m4a1.mdl"); }
    else if (iId == CSW_AK47)  { if (strlen(g_szSkinAK47[id])  > 0) formatex(szPath, charsmax(szPath), "models/custom_skins/ak47/%s/v_ak47.mdl",   g_szSkinAK47[id]);  else formatex(szPath, charsmax(szPath), "models/v_ak47.mdl"); }

    if (strlen(szPath) > 0) set_pev(id, pev_viewmodel2, szPath);
    return HAM_IGNORED;
}

// ============================================================
// Custom weapon sounds
// ============================================================
public fw_EmitSound(id, channel, const sample[], Float:volume, Float:attn, flags, pitch) {
    if (id < 1 || id > 32 || !is_user_connected(id)) return FMRES_IGNORED;
    if (containi(sample, "weapons/") != 0) return FMRES_IGNORED;

    new iWeapon = get_user_weapon(id);
    new szSkin[64], szWeaponType[16];

    if      (iWeapon == CSW_KNIFE && strlen(g_szSkinKnife[id]) > 0) { copy(szSkin, charsmax(szSkin), g_szSkinKnife[id]); copy(szWeaponType, charsmax(szWeaponType), "knife"); }
    else if (iWeapon == CSW_M4A1  && strlen(g_szSkinM4A1[id])  > 0) { copy(szSkin, charsmax(szSkin), g_szSkinM4A1[id]);  copy(szWeaponType, charsmax(szWeaponType), "m4a1"); }
    else if (iWeapon == CSW_AK47  && strlen(g_szSkinAK47[id])  > 0) { copy(szSkin, charsmax(szSkin), g_szSkinAK47[id]);  copy(szWeaponType, charsmax(szWeaponType), "ak47"); }

    if (strlen(szSkin) > 0) {
        new szCheckPath[256];
        formatex(szCheckPath, charsmax(szCheckPath), "models/custom_skins/%s/%s/sound/%s", szWeaponType, szSkin, sample);
        
        if (!TrieKeyExists(g_trieSounds, szCheckPath)) {
            new delim = strfind(szSkin, "/variant/");
            if (delim != -1) {
                new szBaseSkin[64];
                copy(szBaseSkin, delim, szSkin);
                formatex(szCheckPath, charsmax(szCheckPath), "models/custom_skins/%s/%s/sound/%s", szWeaponType, szBaseSkin, sample);
            }
        }

        if (TrieKeyExists(g_trieSounds, szCheckPath)) {
            new szEmitPath[256];
            formatex(szEmitPath, charsmax(szEmitPath), "../%s", szCheckPath);
            emit_sound(id, channel, szEmitPath, volume, attn, flags, pitch);
            return FMRES_SUPERCEDE;
        }
    }
    return FMRES_IGNORED;
}

// ============================================================
// Damage indicator
// ============================================================
public OnPlayerTakeDamage_Post(victim, inflictor, attacker, Float:damage, damagebits) {
    if (attacker < 1 || attacker > 32 || !is_user_connected(attacker)) return HAM_IGNORED;
    if (victim == attacker) return HAM_IGNORED;
    if (is_user_bot(attacker)) return HAM_IGNORED; // BOT OPTIMIZATION — bots don't see HUD damage
    if (!g_iDmgEnable[attacker]) return HAM_IGNORED;

    new iDamage = floatround(damage);
    if (iDamage <= 0) return HAM_IGNORED;

    g_iDamageAmount[attacker] = iDamage;

    new Float:scatter = float(g_iDmgScatter[attacker]) / 100.0;
    new Float:fX = random_float(0.50 - scatter, 0.50 + scatter);
    new Float:fY = random_float(0.50 - scatter, 0.50 + scatter);

    if (fX > 0.50 - scatter/2 && fX < 0.50 + scatter/2) fX += (fX > 0.50 ? scatter/2 : -scatter/2);
    if (fY > 0.50 - scatter/2 && fY < 0.50 + scatter/2) fY += (fY > 0.50 ? scatter/2 : -scatter/2);

    if      (iDamage >= 80) { g_iDamageR[attacker] = 255; g_iDamageG[attacker] = 0;   g_iDamageB[attacker] = 0; }
    else if (iDamage >= 30) { g_iDamageR[attacker] = 255; g_iDamageG[attacker] = 140; g_iDamageB[attacker] = 0; }
    else                    { g_iDamageR[attacker] = 255; g_iDamageG[attacker] = 215; g_iDamageB[attacker] = 0; }

    new effect = g_iDmgOpaque[attacker] ? 0 : 1;

    if (g_iDmgSize[attacker] == 1) {
        // Large (Reliable DHUD)
        send_dhud_reliable(attacker, g_iDamageR[attacker], g_iDamageG[attacker], g_iDamageB[attacker], fX, fY, effect, 0.1, 1.0, 0.1, 0.2, "%d", iDamage);
    } else {
        // Small (HUD — rendered inside WH loop)
        g_fDamageX[attacker]      = fX;
        g_fDamageY[attacker]      = fY;
        g_fDamageEndTime[attacker] = get_gametime() + 1.0;
    }

    return HAM_IGNORED;
}

stock send_dhud_reliable(id, r, g, b, Float:x, Float:y, effect, Float:fxtime, Float:holdtime, Float:fadeintime, Float:fadeouttime, const message[], any:...) {
    new buffer[128];
    vformat(buffer, charsmax(buffer), message, 13);

    message_begin(MSG_ONE, 51, _, id); // SVC_DIRECTOR = 51
    write_byte(strlen(buffer) + 31);
    write_byte(6); // DRC_CMD_MESSAGE
    write_byte(effect);
    write_long((r & 0xFF) | ((g & 0xFF) << 8) | ((b & 0xFF) << 16));
    write_long(_:x);
    write_long(_:y);
    write_long(_:fadeintime);
    write_long(_:fadeouttime);
    write_long(_:holdtime);
    write_long(_:fxtime);
    write_string(buffer);
    message_end();
}

// ============================================================
// Fog — per-player apply
// ============================================================
public ApplyFogToPlayer(id) {
    if (is_user_bot(id)) return; // BOT OPTIMIZATION — bots don't render Fog HUD

    if (!g_iFogEnable[id]) {
        message_begin(MSG_ONE, g_msgFog, _, id);
        for (new i = 0; i < 7; i++) write_byte(0);
        message_end();
        return;
    }

    new r, g, b;
    if (g_iFogRGBEnable[id]) {
        r = floatround(g_fFogCurR[id]);
        g = floatround(g_fFogCurG[id]);
        b = floatround(g_fFogCurB[id]);
    } else {
        r = g_iFogR[id];
        g = g_iFogG[id];
        b = g_iFogB[id];
    }

    new Float:fDensity = float(g_iFogDensity[id]) * 0.001;
    new iDensity = _:fDensity;

    message_begin(MSG_ONE, g_msgFog, _, id);
    write_byte(clamp(r, 0, 255));
    write_byte(clamp(g, 0, 255));
    write_byte(clamp(b, 0, 255));
    write_byte((iDensity)       & 0xFF);
    write_byte((iDensity >> 8)  & 0xFF);
    write_byte((iDensity >> 16) & 0xFF);
    write_byte((iDensity >> 24) & 0xFF);
    message_end();
}

// ============================================================
// Combined RGB update task — handles Fog RGB and WH RGB
// for all non-bot players in a single 0.1-second tick.
// ============================================================
public Task_RGBUpdate() {
    new iMaxPlayers = get_maxplayers();
    for (new id = 1; id <= iMaxPlayers; id++) {
        if (!is_user_alive(id) || is_user_bot(id)) continue;

        // --- Fog RGB ---
        if (g_iFogEnable[id] && g_iFogRGBEnable[id]) {
            new Float:fSpeed = g_fFogRGBSpeed[id];
            switch (g_iFogRGBState[id]) {
                case 0: { g_fFogCurG[id] += fSpeed; if (g_fFogCurG[id] >= 255.0) { g_fFogCurG[id] = 255.0; g_iFogRGBState[id] = 1; } }
                case 1: { g_fFogCurR[id] -= fSpeed; if (g_fFogCurR[id] <= 0.0)   { g_fFogCurR[id] = 0.0;   g_iFogRGBState[id] = 2; } }
                case 2: { g_fFogCurB[id] += fSpeed; if (g_fFogCurB[id] >= 255.0) { g_fFogCurB[id] = 255.0; g_iFogRGBState[id] = 3; } }
                case 3: { g_fFogCurG[id] -= fSpeed; if (g_fFogCurG[id] <= 0.0)   { g_fFogCurG[id] = 0.0;   g_iFogRGBState[id] = 4; } }
                case 4: { g_fFogCurR[id] += fSpeed; if (g_fFogCurR[id] >= 255.0) { g_fFogCurR[id] = 255.0; g_iFogRGBState[id] = 5; } }
                case 5: { g_fFogCurB[id] -= fSpeed; if (g_fFogCurB[id] <= 0.0)   { g_fFogCurB[id] = 0.0;   g_iFogRGBState[id] = 0; } }
            }
            ApplyFogToPlayer(id);
        }

        // --- WH Beams RGB (tracks state for potential future use) ---
        if (g_iWHEnable[id] && g_iWHBeamsRGBEnable[id]) {
            new Float:whSpeed = g_fWHBeamsRGBSpeed[id];
            switch (g_iWHBeamsRGBState[id]) {
                case 0: { g_fWHCurG[id] += whSpeed; if (g_fWHCurG[id] >= 255.0) { g_fWHCurG[id] = 255.0; g_iWHBeamsRGBState[id] = 1; } }
                case 1: { g_fWHCurR[id] -= whSpeed; if (g_fWHCurR[id] <= 0.0)   { g_fWHCurR[id] = 0.0;   g_iWHBeamsRGBState[id] = 2; } }
                case 2: { g_fWHCurB[id] += whSpeed; if (g_fWHCurB[id] >= 255.0) { g_fWHCurB[id] = 255.0; g_iWHBeamsRGBState[id] = 3; } }
                case 3: { g_fWHCurG[id] -= whSpeed; if (g_fWHCurG[id] <= 0.0)   { g_fWHCurG[id] = 0.0;   g_iWHBeamsRGBState[id] = 4; } }
                case 4: { g_fWHCurR[id] += whSpeed; if (g_fWHCurR[id] >= 255.0) { g_fWHCurR[id] = 255.0; g_iWHBeamsRGBState[id] = 5; } }
                case 5: { g_fWHCurB[id] -= whSpeed; if (g_fWHCurB[id] <= 0.0)   { g_fWHCurB[id] = 0.0;   g_iWHBeamsRGBState[id] = 0; } }
            }
        }
    }
}

// ============================================================
// Snow / Rain (global)
// ============================================================
public UpdateSnow() {
    new enable_snow = get_pcvar_num(cvar_snow_enable);
    new enable_rain = get_pcvar_num(cvar_rain_enable);

    // Mutual exclusion
    if (enable_snow && enable_rain) {
        enable_rain = 0;
        set_pcvar_num(cvar_rain_enable, 0);
    }

    if (pev_valid(g_iSnowEnt)) {
        if (enable_snow) set_pev(g_iSnowEnt, pev_effects, pev(g_iSnowEnt, pev_effects) & ~EF_NODRAW);
        else             set_pev(g_iSnowEnt, pev_effects, pev(g_iSnowEnt, pev_effects) |  EF_NODRAW);
    }
    if (pev_valid(g_iRainEnt)) {
        if (enable_rain) set_pev(g_iRainEnt, pev_effects, pev(g_iRainEnt, pev_effects) & ~EF_NODRAW);
        else             set_pev(g_iRainEnt, pev_effects, pev(g_iRainEnt, pev_effects) |  EF_NODRAW);
    }

    // Send only to non-bot players
    new iMaxPlayers = get_maxplayers();
    for (new id = 1; id <= iMaxPlayers; id++) {
        if (!is_user_connected(id) || is_user_bot(id)) continue;
        if (enable_snow || enable_rain) {
            new intensity = clamp(get_pcvar_num(cvar_snow_intensity), 1, 3);
            client_cmd(id, "cl_weather 0; cl_weather %d", intensity);
        } else {
            client_cmd(id, "cl_weather 0");
        }
    }
}

// ============================================================
// Main menu
// ============================================================
public cmd_main_menu(id) { show_main_menu(id); return PLUGIN_HANDLED; }

public show_main_menu(id) {
    new menu = menu_create("\yMain Settings Menu (Page 1/2)", "menu_handler_main");
    menu_additem(menu, "Fog Settings",       "1");
    menu_additem(menu, "Snow & Rain Settings","2");
    menu_additem(menu, "Tracer Settings",    "3");
    menu_additem(menu, "FOV Settings",       "4");
    menu_additem(menu, "Bunnyhop Settings",  "5");
    menu_additem(menu, "Wallhack Settings",  "6");
    menu_additem(menu, "Next Page \y->",     "7");
    menu_additem(menu, "\rSave Current Settings", "8");
    menu_additem(menu, "\yLoad Last Settings",     "9");
    menu_setprop(menu, MPROP_PERPAGE, 0);
    menu_setprop(menu, MPROP_EXIT, MEXIT_ALL);
    menu_display(id, menu, 0);
}

public menu_handler_main(id, menu, item) {
    if (item == MENU_EXIT) { menu_destroy(menu); return PLUGIN_HANDLED; }
    new data[6], iName[64], access, callback;
    menu_item_getinfo(menu, item, access, data, charsmax(data), iName, charsmax(iName), callback);
    switch (str_to_num(data)) {
        case 1: show_fog_menu(id);
        case 2: show_snow_menu(id);
        case 3: show_tracer_menu(id);
        case 4: show_fov_menu(id);
        case 5: show_bhop_menu(id);
        case 6: show_wh_menu(id);
        case 7: show_main_menu2(id);
        case 8: { SaveSettings(id); show_main_menu(id); }
        case 9: { LoadSettings(id); show_main_menu(id); }
    }
    menu_destroy(menu);
    return PLUGIN_HANDLED;
}

public show_main_menu2(id) {
    new menu = menu_create("\yMain Settings Menu (Page 2/2)", "menu_handler_main2");
    menu_additem(menu, "Damage Counter Settings", "1");
    menu_additem(menu, "Skybox Settings",         "2");
    menu_additem(menu, "Weapon Skins Settings",   "3");
    menu_addblank(menu, 1);
    menu_addblank(menu, 1);
    menu_addblank(menu, 1);
    menu_additem(menu, "<- \yPrevious Page",      "7");
    menu_additem(menu, "\rSave Current Settings", "8");
    menu_additem(menu, "\yLoad Last Settings",    "9");
    menu_setprop(menu, MPROP_PERPAGE, 0);
    menu_setprop(menu, MPROP_EXIT, MEXIT_ALL);
    menu_display(id, menu, 0);
}

public menu_handler_main2(id, menu, item) {
    if (item == MENU_EXIT) { menu_destroy(menu); return PLUGIN_HANDLED; }
    new data[6], iName[64], access, callback;
    menu_item_getinfo(menu, item, access, data, charsmax(data), iName, charsmax(iName), callback);
    switch (str_to_num(data)) {
        case 1: show_dmg_menu(id);
        case 2: show_skybox_menu(id);
        case 3: show_skins_menu(id);
        case 7: show_main_menu(id);
        case 8: { SaveSettings(id); show_main_menu2(id); }
        case 9: { LoadSettings(id); show_main_menu2(id); }
    }
    menu_destroy(menu);
    return PLUGIN_HANDLED;
}

// ============================================================
// Skybox menu (global setting)
// ============================================================
public cmd_skybox_menu(id) { show_skybox_menu(id); return PLUGIN_HANDLED; }

public show_skybox_menu(id) {
    new menu = menu_create("\ySkybox Settings Menu \r[GLOBAL]", "menu_handler_skybox");
    new szItem[128], szSky[32];
    formatex(szItem, charsmax(szItem), "Toggle Custom Skybox: \w[%s]", get_pcvar_num(cvar_skybox_enable) ? "ON" : "OFF");
    menu_additem(menu, szItem, "1");
    get_pcvar_string(cvar_skybox_name, szSky, charsmax(szSky));
    if (strlen(szSky) == 0) formatex(szSky, charsmax(szSky), "None");
    formatex(szItem, charsmax(szItem), "Select Skybox: \y[%s]", szSky);
    menu_additem(menu, szItem, "2");
    menu_additem(menu, "Back to Main Menu", "3");
    menu_setprop(menu, MPROP_EXIT, MEXIT_ALL);
    menu_display(id, menu, 0);
}

public menu_handler_skybox(id, menu, item) {
    if (item == MENU_EXIT) { menu_destroy(menu); return PLUGIN_HANDLED; }
    new data[6], iName[64], access, callback;
    menu_item_getinfo(menu, item, access, data, charsmax(data), iName, charsmax(iName), callback);
    switch (str_to_num(data)) {
        case 1: {
            set_pcvar_num(cvar_skybox_enable, !get_pcvar_num(cvar_skybox_enable));
            if (get_pcvar_num(cvar_skybox_enable)) {
                new szSky[32];
                get_pcvar_string(cvar_skybox_name, szSky, charsmax(szSky));
                if (strlen(szSky) > 0) { new szFullSky[64]; formatex(szFullSky, charsmax(szFullSky), "custom_skies/%s", szSky); set_cvar_string("sv_skyname", szFullSky); }
            } else {
                set_cvar_string("sv_skyname", g_szDefaultSky);
            }
            client_print(id, print_chat, "[SKYBOX] Change will apply on next map load.");
            show_skybox_menu(id);
        }
        case 2: show_skybox_list_menu(id);
        case 3: show_main_menu2(id);
    }
    menu_destroy(menu);
    return PLUGIN_HANDLED;
}

public show_skybox_list_menu(id) {
    new menu = menu_create("\ySelect Skybox", "menu_handler_skybox_list");
    new dir = open_dir("gfx/env/custom_skies", "", 0);
    if (dir) {
        new filename[64], len;
        while (next_file(dir, filename, charsmax(filename))) {
            if (filename[0] == '.') continue;
            len = strlen(filename);
            if (len > 6 && equali(filename[len-6], "up.tga")) {
                new basename[32];
                copy(basename, charsmax(basename), filename);
                basename[len-6] = 0;
                menu_additem(menu, basename, basename);
            }
        }
        close_dir(dir);
    } else {
        menu_additem(menu, "\dNo custom skies found", "");
    }
    menu_setprop(menu, MPROP_EXIT, MEXIT_ALL);
    menu_display(id, menu, 0);
}

public menu_handler_skybox_list(id, menu, item) {
    if (item == MENU_EXIT) { menu_destroy(menu); show_skybox_menu(id); return PLUGIN_HANDLED; }
    new data[64], iName[64], access, callback;
    menu_item_getinfo(menu, item, access, data, charsmax(data), iName, charsmax(iName), callback);
    if (strlen(data) > 0) {
        set_pcvar_string(cvar_skybox_name, data);
        set_pcvar_num(cvar_skybox_enable, 1);
        new szFullSky[64];
        formatex(szFullSky, charsmax(szFullSky), "custom_skies/%s", data);
        set_cvar_string("sv_skyname", szFullSky);
        client_print(id, print_chat, "[SKYBOX] Set to '%s'. Applies on next map load.", data);
    }
    menu_destroy(menu);
    show_skybox_menu(id);
    return PLUGIN_HANDLED;
}

// ============================================================
// Skins menu (already per-player)
// ============================================================
public cmd_skins_menu(id) { show_skins_menu(id); return PLUGIN_HANDLED; }

public show_skins_menu(id) {
    new menu = menu_create("\yWeapon Skins Menu", "menu_handler_skins");
    new szItem[128];
    formatex(szItem, charsmax(szItem), "Knife Skin: \y[%s]", strlen(g_szSkinKnife[id]) > 0 ? g_szSkinKnife[id] : "Default"); menu_additem(menu, szItem, "1");
    formatex(szItem, charsmax(szItem), "M4A1 Skin: \y[%s]",  strlen(g_szSkinM4A1[id])  > 0 ? g_szSkinM4A1[id]  : "Default"); menu_additem(menu, szItem, "2");
    formatex(szItem, charsmax(szItem), "AK-47 Skin: \y[%s]", strlen(g_szSkinAK47[id])  > 0 ? g_szSkinAK47[id]  : "Default"); menu_additem(menu, szItem, "3");
    formatex(szItem, charsmax(szItem), "Next Skin on Deploy: \y[%s]", g_bAutoDeploySkins[id] ? "ON" : "OFF"); menu_additem(menu, szItem, "4");
    formatex(szItem, charsmax(szItem), "Next Skin on Kill: \y[%s]",   g_bAutoKillSkins[id]   ? "ON" : "OFF"); menu_additem(menu, szItem, "5");
    menu_additem(menu, "Back to Main Menu", "6");
    menu_setprop(menu, MPROP_EXIT, MEXIT_ALL);
    menu_display(id, menu, 0);
}

public menu_handler_skins(id, menu, item) {
    if (item == MENU_EXIT) { menu_destroy(menu); return PLUGIN_HANDLED; }
    new data[6], iName[64], access, callback;
    menu_item_getinfo(menu, item, access, data, charsmax(data), iName, charsmax(iName), callback);
    switch (str_to_num(data)) {
        case 1: show_skins_list_menu(id, "knife");
        case 2: show_skins_list_menu(id, "m4a1");
        case 3: show_skins_list_menu(id, "ak47");
        case 4: {
            g_bAutoDeploySkins[id] = !g_bAutoDeploySkins[id];
            if (g_hVault != INVALID_HANDLE) {
                new szAuthID[32], szKey[64];
                get_user_authid(id, szAuthID, charsmax(szAuthID));
                formatex(szKey, charsmax(szKey), "%s_skin_autodep", szAuthID);
                nvault_set(g_hVault, szKey, g_bAutoDeploySkins[id] ? "1" : "0");
            }
            show_skins_menu(id);
        }
        case 5: {
            g_bAutoKillSkins[id] = !g_bAutoKillSkins[id];
            if (g_hVault != INVALID_HANDLE) {
                new szAuthID[32], szKey[64];
                get_user_authid(id, szAuthID, charsmax(szAuthID));
                formatex(szKey, charsmax(szKey), "%s_skin_autokill", szAuthID);
                nvault_set(g_hVault, szKey, g_bAutoKillSkins[id] ? "1" : "0");
            }
            show_skins_menu(id);
        }
        case 6: show_main_menu2(id);
    }
    menu_destroy(menu);
    return PLUGIN_HANDLED;
}

public show_skins_list_menu(id, const szWeaponType[]) {
    new szTitle[128], szBaseDir[128];
    formatex(szTitle, charsmax(szTitle), "\ySelect Skin (%s)", szWeaponType);
    new menu = menu_create(szTitle, "menu_handler_skins_list");
    formatex(szBaseDir, charsmax(szBaseDir), "models/custom_skins/%s", szWeaponType);
    menu_additem(menu, "Default (Turn Off)", szWeaponType);
    new dir = open_dir(szBaseDir, "", 0);
    if (dir) {
        new filename[64], szPath[256];
        while (next_file(dir, filename, charsmax(filename))) {
            if (filename[0] == '.') continue;
            formatex(szPath, charsmax(szPath), "%s/%s", szBaseDir, filename);
            if (dir_exists(szPath)) {
                new info[64];
                formatex(info, charsmax(info), "%s:%s", szWeaponType, filename);
                menu_additem(menu, filename, info);
            }
        }
        close_dir(dir);
    }
    menu_setprop(menu, MPROP_EXIT, MEXIT_ALL);
    menu_display(id, menu, 0);
}

public menu_handler_skins_list(id, menu, item) {
    if (item == MENU_EXIT) { menu_destroy(menu); show_skins_menu(id); return PLUGIN_HANDLED; }
    new data[64], iName[64], access, callback;
    menu_item_getinfo(menu, item, access, data, charsmax(data), iName, charsmax(iName), callback);
    if (strlen(data) > 0) {
        new szWeaponType[16], szFilename[64];
        new delim = strfind(data, ":");
        if (delim != -1) {
            copy(szWeaponType, delim, data);
            copy(szFilename, charsmax(szFilename), data[delim+1]);
            
            new szVariantPath[256];
            formatex(szVariantPath, charsmax(szVariantPath), "models/custom_skins/%s/%s/variant", szWeaponType, szFilename);
            if (dir_exists(szVariantPath)) {
                menu_destroy(menu);
                show_skins_variants_menu(id, szWeaponType, szFilename);
                return PLUGIN_HANDLED;
            }

            if      (equal(szWeaponType, "knife")) copy(g_szSkinKnife[id], 63, szFilename);
            else if (equal(szWeaponType, "m4a1"))  copy(g_szSkinM4A1[id],  63, szFilename);
            else if (equal(szWeaponType, "ak47"))  copy(g_szSkinAK47[id],  63, szFilename);
            client_print(id, print_chat, "[SKINS] %s skin changed to %s. Re-deploy weapon to apply.", szWeaponType, szFilename);
        } else {
            copy(szWeaponType, charsmax(szWeaponType), data);
            if      (equal(szWeaponType, "knife")) g_szSkinKnife[id][0] = 0;
            else if (equal(szWeaponType, "m4a1"))  g_szSkinM4A1[id][0]  = 0;
            else if (equal(szWeaponType, "ak47"))  g_szSkinAK47[id][0]  = 0;
            client_print(id, print_chat, "[SKINS] %s skin reset to Default.", szWeaponType);
        }
        if (g_hVault != INVALID_HANDLE) {
            new szAuthID[32], szKey[64];
            get_user_authid(id, szAuthID, charsmax(szAuthID));
            if      (equal(szWeaponType, "knife")) { formatex(szKey, charsmax(szKey), "%s_skin_knife", szAuthID); nvault_set(g_hVault, szKey, g_szSkinKnife[id]); }
            else if (equal(szWeaponType, "m4a1"))  { formatex(szKey, charsmax(szKey), "%s_skin_m4a1",  szAuthID); nvault_set(g_hVault, szKey, g_szSkinM4A1[id]);  }
            else if (equal(szWeaponType, "ak47"))  { formatex(szKey, charsmax(szKey), "%s_skin_ak47",  szAuthID); nvault_set(g_hVault, szKey, g_szSkinAK47[id]);  }
        }
    }
    menu_destroy(menu);
    show_skins_menu(id);
    return PLUGIN_HANDLED;
}

public show_skins_variants_menu(id, const szWeaponType[], const szSkinName[]) {
    new szTitle[128], szBaseDir[128];
    formatex(szTitle, charsmax(szTitle), "\ySelect Variant (%s)", szSkinName);
    new menu = menu_create(szTitle, "menu_handler_skins_list");
    
    new info_default[64];
    formatex(info_default, charsmax(info_default), "%s:%s", szWeaponType, szSkinName);
    menu_additem(menu, "Default Color", info_default);

    formatex(szBaseDir, charsmax(szBaseDir), "models/custom_skins/%s/%s/variant", szWeaponType, szSkinName);
    new dir = open_dir(szBaseDir, "", 0);
    if (dir) {
        new filename[64], szPath[256];
        while (next_file(dir, filename, charsmax(filename))) {
            if (filename[0] == '.') continue;
            formatex(szPath, charsmax(szPath), "%s/%s", szBaseDir, filename);
            if (dir_exists(szPath)) {
                new info[64];
                formatex(info, charsmax(info), "%s:%s/variant/%s", szWeaponType, szSkinName, filename);
                menu_additem(menu, filename, info);
            }
        }
        close_dir(dir);
    }
    menu_setprop(menu, MPROP_EXIT, MEXIT_ALL);
    menu_display(id, menu, 0);
}

// ============================================================
// Fog menu (per-player)
// ============================================================
public cmd_fog_menu(id) { show_fog_menu(id); return PLUGIN_HANDLED; }

public show_fog_menu(id) {
    new menu = menu_create("\yFog Settings Menu", "menu_handler_fog");
    new szItem[128];
    formatex(szItem, charsmax(szItem), "Toggle Fog: \w[%s]",              g_iFogEnable[id]    ? "ON" : "OFF");    menu_additem(menu, szItem, "1");
    formatex(szItem, charsmax(szItem), "Set Color (R G B): \w[%d %d %d]", g_iFogR[id], g_iFogG[id], g_iFogB[id]); menu_additem(menu, szItem, "2");
    formatex(szItem, charsmax(szItem), "Set Density: \w[%d]",             g_iFogDensity[id]);                      menu_additem(menu, szItem, "3");
    formatex(szItem, charsmax(szItem), "Toggle RGB Auto-Color: \w[%s]",   g_iFogRGBEnable[id] ? "ON" : "OFF");    menu_additem(menu, szItem, "4");
    formatex(szItem, charsmax(szItem), "Set RGB Speed: \w[%.1f]",         g_fFogRGBSpeed[id]);                     menu_additem(menu, szItem, "5");
    menu_additem(menu, "Back to Main Menu", "6");
    menu_setprop(menu, MPROP_EXIT, MEXIT_ALL);
    menu_display(id, menu, 0);
}

public menu_handler_fog(id, menu, item) {
    if (item == MENU_EXIT) { menu_destroy(menu); return PLUGIN_HANDLED; }
    new data[6], iName[64], access, callback;
    menu_item_getinfo(menu, item, access, data, charsmax(data), iName, charsmax(iName), callback);
    switch (str_to_num(data)) {
        case 1: { g_iFogEnable[id] = !g_iFogEnable[id]; ApplyFogToPlayer(id); show_fog_menu(id); }
        case 2: { client_print(id, print_chat, "[FOG] Type R G B values in chat (e.g., '255 0 0')"); client_cmd(id, "messagemode amx_fog_set_color"); }
        case 3: { client_print(id, print_chat, "[FOG] Type density value in chat (1 to 99)");        client_cmd(id, "messagemode amx_fog_set_density"); }
        case 4: { g_iFogRGBEnable[id] = !g_iFogRGBEnable[id]; ApplyFogToPlayer(id); show_fog_menu(id); }
        case 5: { client_print(id, print_chat, "[FOG] Type RGB speed in chat (e.g., 5.0)");          client_cmd(id, "messagemode amx_fog_set_rgb_speed"); }
        case 6: show_main_menu(id);
    }
    menu_destroy(menu);
    return PLUGIN_HANDLED;
}

public cmd_set_color(id) {
    new arg[32]; read_args(arg, charsmax(arg)); remove_quotes(arg); trim(arg);
    if (strlen(arg) > 0) {
        new str_r[5], str_g[5], str_b[5];
        parse(arg, str_r, charsmax(str_r), str_g, charsmax(str_g), str_b, charsmax(str_b));
        g_iFogR[id] = clamp(str_to_num(str_r), 0, 255);
        g_iFogG[id] = clamp(str_to_num(str_g), 0, 255);
        g_iFogB[id] = clamp(str_to_num(str_b), 0, 255);
        ApplyFogToPlayer(id);
    }
    show_fog_menu(id);
    return PLUGIN_HANDLED;
}

public cmd_set_density(id) {
    new arg[32]; read_args(arg, charsmax(arg)); remove_quotes(arg); trim(arg);
    if (strlen(arg) > 0) {
        g_iFogDensity[id] = str_to_num(arg);
        ApplyFogToPlayer(id);
    }
    show_fog_menu(id);
    return PLUGIN_HANDLED;
}

public cmd_set_rgb_speed(id) {
    new arg[32]; read_args(arg, charsmax(arg)); remove_quotes(arg); trim(arg);
    if (strlen(arg) > 0) {
        new Float:speed = str_to_float(arg);
        if (speed <= 0.0) speed = 1.0;
        g_fFogRGBSpeed[id] = speed;
    }
    show_fog_menu(id);
    return PLUGIN_HANDLED;
}

// ============================================================
// Snow / Rain menu (global)
// ============================================================
public cmd_snow_menu(id) { show_snow_menu(id); return PLUGIN_HANDLED; }

public show_snow_menu(id) {
    new menu = menu_create("\ySnow & Rain Settings Menu \r[GLOBAL]", "menu_handler_snow");
    new szItem[128];
    formatex(szItem, charsmax(szItem), "Toggle Snow: \w[%s]",          get_pcvar_num(cvar_snow_enable) ? "ON" : "OFF"); menu_additem(menu, szItem, "1");
    formatex(szItem, charsmax(szItem), "Toggle Rain: \w[%s]",          get_pcvar_num(cvar_rain_enable) ? "ON" : "OFF"); menu_additem(menu, szItem, "2");
    formatex(szItem, charsmax(szItem), "Set Intensity (1-3): \w[%d]",  clamp(get_pcvar_num(cvar_snow_intensity), 1, 3)); menu_additem(menu, szItem, "3");
    menu_additem(menu, "Back to Main Menu", "4");
    menu_setprop(menu, MPROP_EXIT, MEXIT_ALL);
    menu_display(id, menu, 0);
}

public menu_handler_snow(id, menu, item) {
    if (item == MENU_EXIT) { menu_destroy(menu); return PLUGIN_HANDLED; }
    new data[6], iName[64], access, callback;
    menu_item_getinfo(menu, item, access, data, charsmax(data), iName, charsmax(iName), callback);
    switch (str_to_num(data)) {
        case 1: {
            new bState = !get_pcvar_num(cvar_snow_enable);
            set_pcvar_num(cvar_snow_enable, bState);
            if (bState) { set_pcvar_num(cvar_rain_enable, 0); if (g_hVault != INVALID_HANDLE) nvault_set(g_hVault, "GLOBAL_weather_type", "1"); client_print(id, print_chat, "[WEATHER] Snow ON. (Rain change takes effect on next map)"); }
            UpdateSnow(); show_snow_menu(id);
        }
        case 2: {
            new bState = !get_pcvar_num(cvar_rain_enable);
            set_pcvar_num(cvar_rain_enable, bState);
            if (bState) { set_pcvar_num(cvar_snow_enable, 0); if (g_hVault != INVALID_HANDLE) nvault_set(g_hVault, "GLOBAL_weather_type", "2"); client_print(id, print_chat, "[WEATHER] Rain ON. (Snow change takes effect on next map)"); }
            UpdateSnow(); show_snow_menu(id);
        }
        case 3: { client_print(id, print_chat, "[WEATHER] Type intensity value in chat (1, 2, or 3)"); client_cmd(id, "messagemode amx_snow_set_intensity"); }
        case 4: show_main_menu(id);
    }
    menu_destroy(menu);
    return PLUGIN_HANDLED;
}

public cmd_snow_set_intensity(id) {
    new arg[32]; read_args(arg, charsmax(arg)); remove_quotes(arg); trim(arg);
    if (strlen(arg) > 0) {
        set_pcvar_num(cvar_snow_intensity, clamp(str_to_num(arg), 1, 3));
        UpdateSnow();
    }
    show_snow_menu(id);
    return PLUGIN_HANDLED;
}

// ============================================================
// Tracer logic + menu (per-player settings, broadcast visual)
// ============================================================
public fw_PrimaryAttack_Pre(ent) {
    if (pev_valid(ent)) { new id = get_pdata_cbase(ent, 41, 4); if (id >= 1 && id <= 32) g_bFiring[id] = true; }
    return HAM_IGNORED;
}
public fw_PrimaryAttack_Post(ent) {
    if (pev_valid(ent)) { new id = get_pdata_cbase(ent, 41, 4); if (id >= 1 && id <= 32) g_bFiring[id] = false; }
    return HAM_IGNORED;
}
public fw_ItemPostFrame_Pre(ent) {
    if (pev_valid(ent)) { new id = get_pdata_cbase(ent, 41, 4); if (id >= 1 && id <= 32) g_bFiring[id] = true; }
    return HAM_IGNORED;
}
public fw_ItemPostFrame_Post(ent) {
    if (pev_valid(ent)) { new id = get_pdata_cbase(ent, 41, 4); if (id >= 1 && id <= 32) g_bFiring[id] = false; }
    return HAM_IGNORED;
}

public fw_TraceLine_Post(const Float:start[3], const Float:end[3], conditions, id, trace) {
    if (id >= 1 && id <= 32 && g_bFiring[id]) {
        if (is_user_bot(id)) return FMRES_IGNORED;       // Bots don't need tracers
        if (!g_iTracerEnable[id]) return FMRES_IGNORED;  // Per-player enable check

        new Float:origin[3];
        pev(id, pev_origin, origin);
        new Float:dx = origin[0] - start[0];
        new Float:dy = origin[1] - start[1];
        new Float:dz = origin[2] - start[2];
        if ((dx*dx + dy*dy + dz*dz) > 10000.0) return FMRES_IGNORED;

        new Float:vecEndPos[3];
        get_tr2(trace, TR_vecEndPos, vecEndPos);

        message_begin(MSG_BROADCAST, SVC_TEMPENTITY);
        write_byte(TE_BEAMENTPOINT);
        write_short(id | 0x1000);
        write_coord(floatround(vecEndPos[0]));
        write_coord(floatround(vecEndPos[1]));
        write_coord(floatround(vecEndPos[2]));
        write_short(g_spriteTracer);
        write_byte(0); write_byte(0); write_byte(2); write_byte(5); write_byte(0);
        write_byte(g_iTracerR[id]);  // Per-player color
        write_byte(g_iTracerG[id]);
        write_byte(g_iTracerB[id]);
        write_byte(200); write_byte(150);
        message_end();
    }
    return FMRES_IGNORED;
}

public cmd_tracer_menu(id) { show_tracer_menu(id); return PLUGIN_HANDLED; }

public show_tracer_menu(id) {
    new menu = menu_create("\yTracer Settings Menu", "menu_handler_tracer");
    new szItem[128];
    formatex(szItem, charsmax(szItem), "Toggle Tracers: \w[%s]",       g_iTracerEnable[id] ? "ON" : "OFF");              menu_additem(menu, szItem, "1");
    formatex(szItem, charsmax(szItem), "Set Color (R G B): \w[%d %d %d]", g_iTracerR[id], g_iTracerG[id], g_iTracerB[id]); menu_additem(menu, szItem, "2");
    menu_additem(menu, "Back to Main Menu", "3");
    menu_setprop(menu, MPROP_EXIT, MEXIT_ALL);
    menu_display(id, menu, 0);
}

public menu_handler_tracer(id, menu, item) {
    if (item == MENU_EXIT) { menu_destroy(menu); return PLUGIN_HANDLED; }
    new data[6], iName[64], access, callback;
    menu_item_getinfo(menu, item, access, data, charsmax(data), iName, charsmax(iName), callback);
    switch (str_to_num(data)) {
        case 1: { g_iTracerEnable[id] = !g_iTracerEnable[id]; show_tracer_menu(id); }
        case 2: { client_print(id, print_chat, "[TRACER] Type R G B values in chat (e.g., '0 255 0')"); client_cmd(id, "messagemode amx_tracer_set_color"); }
        case 3: show_main_menu(id);
    }
    menu_destroy(menu);
    return PLUGIN_HANDLED;
}

public cmd_tracer_set_color(id) {
    new arg[32]; read_args(arg, charsmax(arg)); remove_quotes(arg); trim(arg);
    if (strlen(arg) > 0) {
        new str_r[5], str_g[5], str_b[5];
        parse(arg, str_r, charsmax(str_r), str_g, charsmax(str_g), str_b, charsmax(str_b));
        g_iTracerR[id] = clamp(str_to_num(str_r), 0, 255);
        g_iTracerG[id] = clamp(str_to_num(str_g), 0, 255);
        g_iTracerB[id] = clamp(str_to_num(str_b), 0, 255);
    }
    show_tracer_menu(id);
    return PLUGIN_HANDLED;
}

// ============================================================
// FOV logic + menu (per-player)
// ============================================================
public Message_SetFOV(msg_id, msg_dest, id) {
    if (is_user_bot(id)) return PLUGIN_CONTINUE; // BOT OPTIMIZATION

    if (!g_iFOVEnable[id]) {
        client_cmd(id, "default_fov 90");
        return PLUGIN_CONTINUE;
    }

    new fov = get_msg_arg_int(1);
    if (fov == 90 || fov == 0) {
        new custom_fov = clamp(g_iFOVValue[id], 10, 150);
        set_msg_arg_int(1, ARG_BYTE, custom_fov);
        client_cmd(id, "default_fov %d", custom_fov);
    } else {
        client_cmd(id, "default_fov 90");
    }
    return PLUGIN_CONTINUE;
}

public cmd_fov_menu(id) { show_fov_menu(id); return PLUGIN_HANDLED; }

public show_fov_menu(id) {
    new menu = menu_create("\yFOV Settings Menu", "menu_handler_fov");
    new szItem[128];
    formatex(szItem, charsmax(szItem), "Toggle FOV: \w[%s]",       g_iFOVEnable[id] ? "ON" : "OFF");           menu_additem(menu, szItem, "1");
    formatex(szItem, charsmax(szItem), "Set FOV (10-150): \w[%d]", clamp(g_iFOVValue[id], 10, 150));           menu_additem(menu, szItem, "2");
    menu_additem(menu, "Back to Main Menu", "3");
    menu_setprop(menu, MPROP_EXIT, MEXIT_ALL);
    menu_display(id, menu, 0);
}

public menu_handler_fov(id, menu, item) {
    if (item == MENU_EXIT) { menu_destroy(menu); return PLUGIN_HANDLED; }
    new data[6], iName[64], access, callback;
    menu_item_getinfo(menu, item, access, data, charsmax(data), iName, charsmax(iName), callback);
    switch (str_to_num(data)) {
        case 1: {
            g_iFOVEnable[id] = !g_iFOVEnable[id];
            new custom_fov = g_iFOVEnable[id] ? clamp(g_iFOVValue[id], 10, 150) : 90;
            client_cmd(id, "default_fov %d", custom_fov);
            message_begin(MSG_ONE, g_msgSetFOV, _, id);
            write_byte(custom_fov);
            message_end();
            show_fov_menu(id);
        }
        case 2: { client_print(id, print_chat, "[FOV] Type FOV value in chat (10-150)"); client_cmd(id, "messagemode amx_fov_set_value"); }
        case 3: show_main_menu(id);
    }
    menu_destroy(menu);
    return PLUGIN_HANDLED;
}

public cmd_fov_set_value(id) {
    new arg[32]; read_args(arg, charsmax(arg)); remove_quotes(arg); trim(arg);
    if (strlen(arg) > 0) {
        g_iFOVValue[id] = clamp(str_to_num(arg), 10, 150);
        if (g_iFOVEnable[id]) {
            client_cmd(id, "default_fov %d", g_iFOVValue[id]);
            message_begin(MSG_ONE, g_msgSetFOV, _, id);
            write_byte(g_iFOVValue[id]);
            message_end();
        }
    }
    show_fov_menu(id);
    return PLUGIN_HANDLED;
}

// ============================================================
// Bunnyhop + WH PreThink  —  BOT OPTIMIZATION at the top
// ============================================================
public fw_PlayerPreThink(id) {
    if (!is_user_alive(id)) return FMRES_IGNORED;

    // BOT OPTIMIZATION: bots don't need any visual effects or bhop
    if (is_user_bot(id)) return FMRES_IGNORED;

    // Per-player WH ESP update
    if (g_iWHEnable[id]) Update_Player_WH(id);

    if (!g_iBhopEnable[id]) return FMRES_IGNORED;

    // Remove jump stamina/slowdown
    set_pev(id, pev_fuser2, 0.0);

    new button = pev(id, pev_button);
    if (button & IN_JUMP) {
        new flags      = pev(id, pev_flags);
        new waterlevel = pev(id, pev_waterlevel);
        new movetype   = pev(id, pev_movetype);

        if (waterlevel >= 2 || movetype == MOVETYPE_FLY || movetype == MOVETYPE_NOCLIP || (flags & FL_WATERJUMP))
            return FMRES_IGNORED;

        if (flags & FL_ONGROUND) {
            new Float:velocity[3];
            pev(id, pev_velocity, velocity);
            velocity[2] = 250.0;
            set_pev(id, pev_velocity, velocity);
            set_pev(id, pev_gaitsequence, 6);
        }
    }
    return FMRES_IGNORED;
}

// ============================================================
// Bhop menu
// ============================================================
public cmd_bhop_menu(id) { show_bhop_menu(id); return PLUGIN_HANDLED; }

public show_bhop_menu(id) {
    new menu = menu_create("\yBunnyhop Settings Menu", "menu_handler_bhop");
    new szItem[128];
    formatex(szItem, charsmax(szItem), "Toggle Bunnyhop: \w[%s]", g_iBhopEnable[id] ? "ON" : "OFF");
    menu_additem(menu, szItem, "1");
    menu_additem(menu, "Back to Main Menu", "2");
    menu_setprop(menu, MPROP_EXIT, MEXIT_ALL);
    menu_display(id, menu, 0);
}

public menu_handler_bhop(id, menu, item) {
    if (item == MENU_EXIT) { menu_destroy(menu); return PLUGIN_HANDLED; }
    new data[6], iName[64], access, callback;
    menu_item_getinfo(menu, item, access, data, charsmax(data), iName, charsmax(iName), callback);
    switch (str_to_num(data)) {
        case 1: { g_iBhopEnable[id] = !g_iBhopEnable[id]; show_bhop_menu(id); }
        case 2: show_main_menu(id);
    }
    menu_destroy(menu);
    return PLUGIN_HANDLED;
}

// ============================================================
// Wallhack / ESP logic
//
// 2D HUD ESP with scalable boxes.
// Читает настройки из массивов игрока (id).
// ============================================================
public Update_Player_WH(id) {
    // Already confirmed non-bot, alive, wh_enable in fw_PlayerPreThink
    new id_team = get_user_team(id);
    if (id_team != 1 && id_team != 2) return;

    new Float:fTime = get_gametime();
    new bool:bUpdateBeams = false;

    new bool:bShowingDamage = (g_iDmgEnable[id] && g_fDamageEndTime[id] > fTime);

    static Float:fLastBeamTime[33];

    if (g_iWHBeams[id] && fTime - fLastBeamTime[id] >= 0.03) {
        fLastBeamTime[id] = fTime;
        bUpdateBeams = true;

        message_begin(MSG_ONE_UNRELIABLE, SVC_TEMPENTITY, _, id);
        write_byte(TE_KILLBEAM);
        write_short(id);
        message_end();
    }

    new iMaxPlayers = get_maxplayers();

    new Float:fEye[3], Float:fViewOfs[3];
    pev(id, pev_origin, fEye);
    pev(id, pev_view_ofs, fViewOfs);
    fEye[0] += fViewOfs[0]; fEye[1] += fViewOfs[1]; fEye[2] += fViewOfs[2];

    new Float:fAng[3], Float:vF[3], Float:vR[3], Float:vU[3];
    pev(id, pev_v_angle, fAng);
    engfunc(EngFunc_AngleVectors, fAng, vF, vR, vU);

    new Float:fFov = 90.0;
    if (g_iFOVEnable[id]) fFov = float(clamp(g_iFOVValue[id], 10, 150));
    new Float:fTH = floattan(fFov * 0.5, degrees);

    new iTargets[33], Float:fDists[33], iNumTargets = 0;

    for (new target = 1; target <= iMaxPlayers; target++) {
        if (id == target || !is_user_alive(target)) continue;
        new target_team = get_user_team(target);
        if (!g_iWHTeammates[id] && id_team == target_team) continue;

        new Float:fO[3];
        pev(target, pev_origin, fO);
        new Float:fD[3];
        fD[0] = fO[0] - fEye[0]; fD[1] = fO[1] - fEye[1]; fD[2] = fO[2] - fEye[2];

        new Float:dF = fD[0]*vF[0] + fD[1]*vF[1] + fD[2]*vF[2];
        if (dF < 20.0) continue;

        iTargets[iNumTargets] = target;
        fDists[iNumTargets]   = fD[0]*fD[0] + fD[1]*fD[1] + fD[2]*fD[2];
        iNumTargets++;
    }

    // Sort by distance (closest first)
    for (new i = 0; i < iNumTargets - 1; i++) {
        for (new j = i + 1; j < iNumTargets; j++) {
            if (fDists[i] > fDists[j]) {
                new Float:tmpD = fDists[i]; fDists[i] = fDists[j]; fDists[j] = tmpD;
                new tmpT = iTargets[i];     iTargets[i] = iTargets[j]; iTargets[j] = tmpT;
            }
        }
    }

    new iCh = 1;

    for (new idx = 0; idx < iNumTargets; idx++) {
        new target      = iTargets[idx];
        new target_team = get_user_team(target);

        new Float:fO[3];
        pev(target, pev_origin, fO);

        new Float:fD[3];
        fD[0] = fO[0] - fEye[0]; fD[1] = fO[1] - fEye[1]; fD[2] = fO[2] - fEye[2];

        new Float:dF = fD[0]*vF[0] + fD[1]*vF[1] + fD[2]*vF[2];
        new Float:dR = fD[0]*vR[0] + fD[1]*vR[1] + fD[2]*vR[2];
        new Float:dU = fD[0]*vU[0] + fD[1]*vU[1] + fD[2]*vU[2];

        new Float:sCX = 0.5 + (dR / dF) / (2.0 * fTH);

        new Float:dF_head = dF + 36.0 * vF[2]; new Float:dU_head = dU + 36.0 * vU[2];
        new Float:dF_feet = dF - 36.0 * vF[2]; new Float:dU_feet = dU - 36.0 * vU[2];
        if (dF_head < 1.0) dF_head = 1.0;
        if (dF_feet < 1.0) dF_feet = 1.0;

        new Float:sHeadY = 0.5 - (dU_head / dF_head) / (2.0 * fTH * 0.75);
        new Float:sFeetY = 0.5 - (dU_feet / dF_feet) / (2.0 * fTH * 0.75);

        if (sCX < -0.15 || sCX > 1.15) continue;
        if (sHeadY > 1.1 && sFeetY > 1.1) continue;
        if (sHeadY < -0.1 && sFeetY < -0.1) continue;

        new Float:fHalfW = (16.0 / dF) / (2.0 * fTH);
        new Float:sLeftX = sCX - fHalfW;

        new iBarLen = floatround(fHalfW * 2.0 / HUD_CHAR_W);
        if (iBarLen < 6)  iBarLen = 6;
        if (iBarLen > 40) iBarLen = 40;

        if (sLeftX < 0.0)  sLeftX = 0.0;
        if (sLeftX > 0.95) sLeftX = 0.95;
        if (sHeadY < 0.0)  sHeadY = 0.0;
        if (sHeadY > 0.95) sHeadY = 0.95;
        if (sFeetY < 0.02) sFeetY = 0.02;
        if (sFeetY > 0.98) sFeetY = 0.98;

        new iR, iG, iB;
        if (target_team == 1) { iR = 255; iG = 50;  iB = 50; }
        else                   { iR = 50;  iG = 100; iB = 255; }

        new szBar[48], i;
        for (i = 0; i < iBarLen && i < 47; i++) szBar[i] = '=';
        szBar[i] = 0;

        if (bUpdateBeams) {
            new bR, bG, bB, iWidth;
            new Float:fDist   = floatsqroot(fDists[idx]);
            new Float:fMinDist = 300.0, Float:fMaxDist = 1200.0;
            new Float:fRatio  = (fDist - fMinDist) / (fMaxDist - fMinDist);
            if (fRatio > 1.0) fRatio = 1.0;
            if (fRatio < 0.0) fRatio = 0.0;

            // Use per-player highlight_humans setting
            if (g_iWHHighlightHumans[id] && !is_user_bot(target)) {
                bR = 255; bG = floatround(fRatio * 100.0); bB = 255;
                iWidth = 2 + floatround((1.0 - fRatio) * 6.0);
            } else {
                bR = floatround((1.0 - fRatio) * 255.0);
                bG = floatround(fRatio * 255.0);
                bB = 0;
                iWidth = 1 + floatround((1.0 - fRatio) * 4.0);
            }

            message_begin(MSG_ONE_UNRELIABLE, SVC_TEMPENTITY, _, id);
            write_byte(TE_BEAMENTPOINT);
            write_short(id);
            write_coord(floatround(fO[0])); write_coord(floatround(fO[1])); write_coord(floatround(fO[2]));
            write_short(g_spriteLaser);
            write_byte(0); write_byte(0); write_byte(2);
            write_byte(clamp(iWidth, 1, 8));
            write_byte(0);
            write_byte(bR); write_byte(bG); write_byte(bB);
            write_byte(150); write_byte(0);
            message_end();
        }

        if (iCh <= 3) {
            // Top bar (head)
            set_hudmessage(iR, iG, iB, sLeftX, sHeadY, 0, 0.0, 0.05, 0.0, 0.0, iCh);
            show_hudmessage(id, szBar);
            iCh++;

            // Bottom bar (feet)
            if (!bShowingDamage || iCh != 4) {
                set_hudmessage(iR, iG, iB, sLeftX, sFeetY, 0, 0.0, 0.05, 0.0, 0.0, iCh);
                show_hudmessage(id, szBar);
            }
            iCh++;
        }
    }

    // Small HUD damage display (channel 4)
    if (bShowingDamage && g_iDmgSize[id] == 0) {
        new szDmg[16];
        num_to_str(g_iDamageAmount[id], szDmg, charsmax(szDmg));
        new effect = g_iDmgOpaque[id] ? 0 : 1;
        set_hudmessage(g_iDamageR[id], g_iDamageG[id], g_iDamageB[id], g_fDamageX[id], g_fDamageY[id], effect, 0.0, 0.05, 0.0, 0.0, 4);
        show_hudmessage(id, szDmg);
    }

    // Clear unused channels
    new max_ch = g_iWHMarkers[id];
    if (bShowingDamage && max_ch < 4) max_ch = 4;
    for (new ch = iCh; ch <= max_ch; ch++) {
        if (ch == 4 && bShowingDamage) continue;
        if (ch > 4) break;
        set_hudmessage(0, 0, 0, 0.0, 0.0, 0, 0.0, 0.01, 0.0, 0.0, ch);
        show_hudmessage(id, "");
    }
    g_iWHMarkers[id] = bShowingDamage ? max(iCh, 4) : iCh;
}

// ============================================================
// WH menu (per-player)
// ============================================================
public cmd_wh_menu(id) { show_wh_menu(id); return PLUGIN_HANDLED; }

public show_wh_menu(id) {
    new menu = menu_create("\yWallhack Settings Menu", "menu_handler_wh");
    new szItem[128];
    formatex(szItem, charsmax(szItem), "Toggle Wallhack: \w[%s]",       g_iWHEnable[id]          ? "ON" : "OFF"); menu_additem(menu, szItem, "1");
    formatex(szItem, charsmax(szItem), "Toggle Beams/Tracers: \w[%s]",  g_iWHBeams[id]           ? "ON" : "OFF"); menu_additem(menu, szItem, "2");
    formatex(szItem, charsmax(szItem), "Apply to Teammates: \w[%s]",    g_iWHTeammates[id]       ? "ON" : "OFF"); menu_additem(menu, szItem, "3");
    formatex(szItem, charsmax(szItem), "Highlight Humans: \w[%s]",      g_iWHHighlightHumans[id] ? "ON" : "OFF"); menu_additem(menu, szItem, "4");
    formatex(szItem, charsmax(szItem), "Toggle Fill (Glow): \w[%s]",    g_iWHFill[id]            ? "ON" : "OFF"); menu_additem(menu, szItem, "5");
    menu_additem(menu, "Back to Main Menu", "6");
    menu_setprop(menu, MPROP_EXIT, MEXIT_ALL);
    menu_display(id, menu, 0);
}

public menu_handler_wh(id, menu, item) {
    if (item == MENU_EXIT) { menu_destroy(menu); return PLUGIN_HANDLED; }
    new data[6], iName[64], access, callback;
    menu_item_getinfo(menu, item, access, data, charsmax(data), iName, charsmax(iName), callback);
    switch (str_to_num(data)) {
        case 1: { g_iWHEnable[id]          = !g_iWHEnable[id];          show_wh_menu(id); }
        case 2: { g_iWHBeams[id]           = !g_iWHBeams[id];           show_wh_menu(id); }
        case 3: { g_iWHTeammates[id]       = !g_iWHTeammates[id];       show_wh_menu(id); }
        case 4: { g_iWHHighlightHumans[id] = !g_iWHHighlightHumans[id]; show_wh_menu(id); }
        case 5: { g_iWHFill[id]            = !g_iWHFill[id];            show_wh_menu(id); }
        case 6: show_main_menu(id);
    }
    menu_destroy(menu);
    return PLUGIN_HANDLED;
}

public cmd_wh_beams_set_color(id) {
    new arg[32]; read_args(arg, charsmax(arg)); remove_quotes(arg); trim(arg);
    if (strlen(arg) > 0) {
        new str_r[5], str_g[5], str_b[5];
        parse(arg, str_r, charsmax(str_r), str_g, charsmax(str_g), str_b, charsmax(str_b));
        g_iWHBeamsR[id] = clamp(str_to_num(str_r), 0, 255);
        g_iWHBeamsG[id] = clamp(str_to_num(str_g), 0, 255);
        g_iWHBeamsB[id] = clamp(str_to_num(str_b), 0, 255);
    }
    show_wh_menu(id);
    return PLUGIN_HANDLED;
}

public cmd_wh_beams_set_width(id) {
    new arg[32]; read_args(arg, charsmax(arg)); remove_quotes(arg); trim(arg);
    if (strlen(arg) > 0) g_iWHBeamsWidth[id] = clamp(str_to_num(arg), 1, 5);
    show_wh_menu(id);
    return PLUGIN_HANDLED;
}

public cmd_wh_beams_set_rgb_speed(id) {
    new arg[32]; read_args(arg, charsmax(arg)); remove_quotes(arg); trim(arg);
    if (strlen(arg) > 0) {
        new Float:speed = str_to_float(arg);
        if (speed <= 0.0) speed = 1.0;
        g_fWHBeamsRGBSpeed[id] = speed;
    }
    show_wh_menu(id);
    return PLUGIN_HANDLED;
}

// ============================================================
// Damage menu (per-player)
// ============================================================
public cmd_dmg_menu(id) { show_dmg_menu(id); return PLUGIN_HANDLED; }

public show_dmg_menu(id) {
    new menu = menu_create("\yDamage Settings Menu", "menu_handler_dmg");
    new szItem[128];
    formatex(szItem, charsmax(szItem), "Toggle Damage Indicator: \w[%s]", g_iDmgEnable[id]  ? "ON" : "OFF");   menu_additem(menu, szItem, "1");
    formatex(szItem, charsmax(szItem), "Size: \w[%s]",                    g_iDmgSize[id]    ? "Large" : "Small"); menu_additem(menu, szItem, "2");
    formatex(szItem, charsmax(szItem), "Opaque/Solid: \w[%s]",            g_iDmgOpaque[id]  ? "ON" : "OFF");   menu_additem(menu, szItem, "3");
    formatex(szItem, charsmax(szItem), "Set Scatter Radius: \w[%d]",      g_iDmgScatter[id]);                    menu_additem(menu, szItem, "4");
    menu_additem(menu, "Back to Main Menu", "5");
    menu_setprop(menu, MPROP_EXIT, MEXIT_ALL);
    menu_display(id, menu, 0);
}

public menu_handler_dmg(id, menu, item) {
    if (item == MENU_EXIT) { menu_destroy(menu); return PLUGIN_HANDLED; }
    new data[6], iName[64], access, callback;
    menu_item_getinfo(menu, item, access, data, charsmax(data), iName, charsmax(iName), callback);
    switch (str_to_num(data)) {
        case 1: { g_iDmgEnable[id]  = !g_iDmgEnable[id];  show_dmg_menu(id); }
        case 2: { g_iDmgSize[id]    = !g_iDmgSize[id];    show_dmg_menu(id); }
        case 3: { g_iDmgOpaque[id]  = !g_iDmgOpaque[id];  show_dmg_menu(id); }
        case 4: { client_cmd(id, "messagemode amx_dmg_set_scatter"); }
        case 5: show_main_menu(id);
    }
    menu_destroy(menu);
    return PLUGIN_HANDLED;
}

public cmd_dmg_set_scatter(id) {
    new arg[32]; read_args(arg, charsmax(arg)); remove_quotes(arg); trim(arg);
    if (strlen(arg) > 0) g_iDmgScatter[id] = clamp(str_to_num(arg), 0, 50);
    show_dmg_menu(id);
    return PLUGIN_HANDLED;
}

// ============================================================
// nVault helpers: per-player save/load
// ============================================================
stock SavePlayerInt(const szAuth[], const szName[], val) {
    new szKey[64], szVal[16];
    formatex(szKey, charsmax(szKey), "%s_%s", szAuth, szName);
    num_to_str(val, szVal, charsmax(szVal));
    nvault_set(g_hVault, szKey, szVal);
}

stock SavePlayerFloat(const szAuth[], const szName[], Float:val) {
    new szKey[64], szVal[16];
    formatex(szKey, charsmax(szKey), "%s_%s", szAuth, szName);
    float_to_str(val, szVal, charsmax(szVal));
    nvault_set(g_hVault, szKey, szVal);
}

stock LoadPlayerInt(const szAuth[], const szName[], &val) {
    new szKey[64], szVal[16];
    formatex(szKey, charsmax(szKey), "%s_%s", szAuth, szName);
    if (nvault_get(g_hVault, szKey, szVal, charsmax(szVal)))
        val = str_to_num(szVal);
}

stock LoadPlayerFloat(const szAuth[], const szName[], &Float:val) {
    new szKey[64], szVal[16];
    formatex(szKey, charsmax(szKey), "%s_%s", szAuth, szName);
    if (nvault_get(g_hVault, szKey, szVal, charsmax(szVal)))
        val = str_to_float(szVal);
}

// ============================================================
// Save / Load settings (per-player)
// ============================================================
stock LoadSettingsForPlayer(id) {
    if (g_hVault == INVALID_HANDLE || is_user_bot(id)) return;
    new szAuth[32];
    get_user_authid(id, szAuth, charsmax(szAuth));

    LoadPlayerInt(szAuth,   "fog_enable",          g_iFogEnable[id]);
    LoadPlayerInt(szAuth,   "fog_r",               g_iFogR[id]);
    LoadPlayerInt(szAuth,   "fog_g",               g_iFogG[id]);
    LoadPlayerInt(szAuth,   "fog_b",               g_iFogB[id]);
    LoadPlayerInt(szAuth,   "fog_density",         g_iFogDensity[id]);
    LoadPlayerInt(szAuth,   "fog_rgb_enable",      g_iFogRGBEnable[id]);
    LoadPlayerFloat(szAuth, "fog_rgb_speed",       g_fFogRGBSpeed[id]);

    LoadPlayerInt(szAuth,   "tracer_enable",       g_iTracerEnable[id]);
    LoadPlayerInt(szAuth,   "tracer_r",            g_iTracerR[id]);
    LoadPlayerInt(szAuth,   "tracer_g",            g_iTracerG[id]);
    LoadPlayerInt(szAuth,   "tracer_b",            g_iTracerB[id]);

    LoadPlayerInt(szAuth,   "fov_enable",          g_iFOVEnable[id]);
    LoadPlayerInt(szAuth,   "fov_value",           g_iFOVValue[id]);

    LoadPlayerInt(szAuth,   "bhop_enable",         g_iBhopEnable[id]);

    LoadPlayerInt(szAuth,   "wh_enable",           g_iWHEnable[id]);
    LoadPlayerInt(szAuth,   "wh_beams",            g_iWHBeams[id]);
    LoadPlayerInt(szAuth,   "wh_beams_r",          g_iWHBeamsR[id]);
    LoadPlayerInt(szAuth,   "wh_beams_g",          g_iWHBeamsG[id]);
    LoadPlayerInt(szAuth,   "wh_beams_b",          g_iWHBeamsB[id]);
    LoadPlayerInt(szAuth,   "wh_beams_width",      g_iWHBeamsWidth[id]);
    LoadPlayerInt(szAuth,   "wh_beams_rgb_enable", g_iWHBeamsRGBEnable[id]);
    LoadPlayerFloat(szAuth, "wh_beams_rgb_speed",  g_fWHBeamsRGBSpeed[id]);
    LoadPlayerInt(szAuth,   "wh_teammates",        g_iWHTeammates[id]);
    LoadPlayerInt(szAuth,   "wh_highlight_humans", g_iWHHighlightHumans[id]);
    LoadPlayerInt(szAuth,   "wh_fill",             g_iWHFill[id]);

    LoadPlayerInt(szAuth,   "dmg_enable",          g_iDmgEnable[id]);
    LoadPlayerInt(szAuth,   "dmg_size",            g_iDmgSize[id]);
    LoadPlayerInt(szAuth,   "dmg_scatter",         g_iDmgScatter[id]);
    LoadPlayerInt(szAuth,   "dmg_opaque",          g_iDmgOpaque[id]);
}

public SaveSettings(id) {
    if (g_hVault == INVALID_HANDLE || is_user_bot(id)) return;
    new szAuth[32];
    get_user_authid(id, szAuth, charsmax(szAuth));

    SavePlayerInt(szAuth,   "fog_enable",          g_iFogEnable[id]);
    SavePlayerInt(szAuth,   "fog_r",               g_iFogR[id]);
    SavePlayerInt(szAuth,   "fog_g",               g_iFogG[id]);
    SavePlayerInt(szAuth,   "fog_b",               g_iFogB[id]);
    SavePlayerInt(szAuth,   "fog_density",         g_iFogDensity[id]);
    SavePlayerInt(szAuth,   "fog_rgb_enable",      g_iFogRGBEnable[id]);
    SavePlayerFloat(szAuth, "fog_rgb_speed",       g_fFogRGBSpeed[id]);

    SavePlayerInt(szAuth,   "tracer_enable",       g_iTracerEnable[id]);
    SavePlayerInt(szAuth,   "tracer_r",            g_iTracerR[id]);
    SavePlayerInt(szAuth,   "tracer_g",            g_iTracerG[id]);
    SavePlayerInt(szAuth,   "tracer_b",            g_iTracerB[id]);

    SavePlayerInt(szAuth,   "fov_enable",          g_iFOVEnable[id]);
    SavePlayerInt(szAuth,   "fov_value",           g_iFOVValue[id]);

    SavePlayerInt(szAuth,   "bhop_enable",         g_iBhopEnable[id]);

    SavePlayerInt(szAuth,   "wh_enable",           g_iWHEnable[id]);
    SavePlayerInt(szAuth,   "wh_beams",            g_iWHBeams[id]);
    SavePlayerInt(szAuth,   "wh_beams_r",          g_iWHBeamsR[id]);
    SavePlayerInt(szAuth,   "wh_beams_g",          g_iWHBeamsG[id]);
    SavePlayerInt(szAuth,   "wh_beams_b",          g_iWHBeamsB[id]);
    SavePlayerInt(szAuth,   "wh_beams_width",      g_iWHBeamsWidth[id]);
    SavePlayerInt(szAuth,   "wh_beams_rgb_enable", g_iWHBeamsRGBEnable[id]);
    SavePlayerFloat(szAuth, "wh_beams_rgb_speed",  g_fWHBeamsRGBSpeed[id]);
    SavePlayerInt(szAuth,   "wh_teammates",        g_iWHTeammates[id]);
    SavePlayerInt(szAuth,   "wh_highlight_humans", g_iWHHighlightHumans[id]);
    SavePlayerInt(szAuth,   "wh_fill",             g_iWHFill[id]);

    SavePlayerInt(szAuth,   "dmg_enable",          g_iDmgEnable[id]);
    SavePlayerInt(szAuth,   "dmg_size",            g_iDmgSize[id]);
    SavePlayerInt(szAuth,   "dmg_scatter",         g_iDmgScatter[id]);
    SavePlayerInt(szAuth,   "dmg_opaque",          g_iDmgOpaque[id]);

    client_print(id, print_chat, "[CustomMenu] All settings have been SAVED.");
}

public LoadSettings(id) {
    if (g_hVault == INVALID_HANDLE || is_user_bot(id)) return;
    LoadSettingsForPlayer(id);

    // Apply fog immediately
    ApplyFogToPlayer(id);

    // Apply FOV if enabled
    if (g_iFOVEnable[id]) {
        new custom_fov = clamp(g_iFOVValue[id], 10, 150);
        client_cmd(id, "default_fov %d", custom_fov);
        message_begin(MSG_ONE, g_msgSetFOV, _, id);
        write_byte(custom_fov);
        message_end();
    } else {
        client_cmd(id, "default_fov 90");
    }

    client_print(id, print_chat, "[CustomMenu] Last settings have been LOADED.");
}

// ============================================================
// fw_AddToFullPack_Post — WH glow fill (per-host settings)
// ============================================================
public fw_AddToFullPack_Post(es_handle, e, ent, host, hostflags, player, pSet) {
    if (!player) return FMRES_IGNORED;
    if (!is_user_alive(host)) return FMRES_IGNORED;
    if (is_user_bot(host)) return FMRES_IGNORED;    // BOT OPTIMIZATION
    if (ent == host) return FMRES_IGNORED;

    // Read host's per-player WH settings
    if (!g_iWHEnable[host] || !g_iWHFill[host]) return FMRES_IGNORED;

    if (ent < 1 || ent > 32 || !is_user_alive(ent)) return FMRES_IGNORED;

    new host_team = get_user_team(host);
    new ent_team  = get_user_team(ent);
    if (!g_iWHTeammates[host] && host_team == ent_team) return FMRES_IGNORED;

    set_es(es_handle, ES_RenderFx, 19); // kRenderFxGlowShell

    new color[3];
    if      (ent_team == 1) { color[0] = 255; color[1] = 50;  color[2] = 50; }
    else if (ent_team == 2) { color[0] = 50;  color[1] = 100; color[2] = 255; }
    else                    { color[0] = 255; color[1] = 255; color[2] = 255; }

    set_es(es_handle, ES_RenderColor, color);
    set_es(es_handle, ES_RenderAmt,   25);
    set_es(es_handle, ES_RenderMode,  0); // kRenderNormal

    return FMRES_IGNORED;
}
