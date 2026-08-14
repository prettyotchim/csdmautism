#include <amxmodx>

#define PLUGIN "Valorant Kill Sounds (3 Series)"
#define VERSION "1.2"
#define AUTHOR "Antigravity"

#define MAX_KILLS 5 // Пользователь загрузил по 5 звуков в каждой серии
#define NUM_SERIES 3 // Количество разных серий (папки 1, 2, 3)

new g_KillCount[33]
new g_PlayerSeries[33]

public plugin_init() {
    register_plugin(PLUGIN, VERSION, AUTHOR)
    
    register_event("DeathMsg", "Event_DeathMsg", "a")
    register_event("ResetHUD", "Event_ResetHUD", "be")
    register_logevent("Event_RoundStart", 2, "1=Round_Start")
}

public client_disconnected(id) {
    g_KillCount[id] = 0
}

public Event_ResetHUD(id) {
    if(is_user_alive(id)) {
        // При возрождении выбираем рандомную серию от 1 до 3
        g_PlayerSeries[id] = random_num(1, NUM_SERIES)
    }
}

public Event_RoundStart() {
    // Сбрасываем счетчики всем в начале обычного раунда
    for(new i = 1; i <= 32; i++) {
        g_KillCount[i] = 0
    }
}

public plugin_precache() {
    new sound_path[64]
    
    // Предкэшируем все 15 звуков (3 серии по 5 звуков)
    for(new s = 1; s <= NUM_SERIES; s++) {
        for(new k = 1; k <= MAX_KILLS; k++) {
            formatex(sound_path, charsmax(sound_path), "valorant/%d/kill%d.wav", s, k)
            precache_sound(sound_path)
        }
    }
    
    // Если у вас остался файл headshot.wav в папке valorant, раскомментируйте строку ниже
    // precache_sound("valorant/headshot.wav")
}

public Event_DeathMsg() {
    new killer = read_data(1)
    new victim = read_data(2)
    // new headshot = read_data(3)
    
    // Сбрасываем серию убийств того, кто умер
    if(is_user_connected(victim)) {
        g_KillCount[victim] = 0
    }
    
    if(!is_user_connected(killer) || killer == victim) {
        return PLUGIN_CONTINUE
    }
    
    // Если почему-то серия не выбралась (например, при первом заходе до спавна), выбираем ее
    if(g_PlayerSeries[killer] == 0) {
        g_PlayerSeries[killer] = random_num(1, NUM_SERIES)
    }
    
    // Увеличиваем серию убийств
    g_KillCount[killer]++
    
    // Определяем текущий килл
    new kill_number = g_KillCount[killer]
    if(kill_number > MAX_KILLS) {
        kill_number = MAX_KILLS // Если больше 5, играем 5-й звук
    }
    
    // Формируем путь к звуку на основе выбранной серии игрока
    new sound_path[64]
    formatex(sound_path, charsmax(sound_path), "valorant/%d/kill%d.wav", g_PlayerSeries[killer], kill_number)
    
    // Воспроизводим звук
    client_cmd(killer, "spk %s", sound_path)
    
    // Если нужен хедшот, раскомментируйте:
    /*
    if(headshot) {
        client_cmd(killer, "spk valorant/headshot.wav")
    }
    */
    
    return PLUGIN_CONTINUE
}
