#include <amxmodx>
#include <time>
#include <nvault>
#include <json>
#include <player_prefs>

new const CONFIG_FILE[] = "addons/amxmodx/configs/player_prefs_nvault.json";

new g_szVaultName[MAX_NAME_LENGTH];
new g_iPruneDays;
new g_nvHandle = INVALID_HANDLE;
new Array: g_aKeys = Invalid_Array;

public plugin_init()
{
  register_plugin("Player Prefs — nVault Provider", "1.0.0", "Psycrow");
}

public plugin_end()
{
  if (g_nvHandle != INVALID_HANDLE)
  {
    nvault_close(g_nvHandle);
    g_nvHandle = INVALID_HANDLE;
  }
}

public pp_provider_connect()
{
  if (!ReadConfig())
  {
    pp_provider_ready(false);
    return;
  }

  log_amx("[PP nVault] Config loaded. nVault name: %s", g_szVaultName);

  g_nvHandle = nvault_open(g_szVaultName);
  if (g_nvHandle == INVALID_HANDLE)
  {
    log_amx("[PP nVault] Error opening nVault: %s", g_szVaultName);
    pp_provider_ready(false);
    return;
  }

  if (g_iPruneDays > 0)
    nvault_prune(g_nvHandle, 0, get_systime() - (g_iPruneDays * SECONDS_IN_DAY));

  g_aKeys = ArrayCreate(MAX_KEY_LENGTH);

  pp_provider_ready(true);
}

public pp_provider_load_keys()
{
  pp_provider_keys_done();
}

public pp_provider_load_player(const playerIndex, const authId[])
{
  new keysNum = ArraySize(g_aKeys);
  new nvKey[MAX_KEY_LENGTH + MAX_AUTHID_LENGTH];
  new key[MAX_KEY_LENGTH], value[MAX_VALUE_LENGTH];

  for (new i; i < keysNum; i++)
  {
    ArrayGetString(g_aKeys, i, key, charsmax(key));
    FormatKey(nvKey, charsmax(nvKey), authId, key);

    if (nvault_get(g_nvHandle, nvKey, value, charsmax(value)))
    {
      nvault_touch(g_nvHandle, nvKey);
      pp_provider_pref_loaded(playerIndex, key, value);
    }
  }

  pp_provider_player_done(playerIndex);
}

public pp_provider_save_pref(const playerIndex, const authId[], const key[], const value[])
{
  new nvKey[MAX_KEY_LENGTH + MAX_AUTHID_LENGTH];
  FormatKey(nvKey, charsmax(nvKey), authId, key);

  nvault_set(g_nvHandle, nvKey, value);
}

public pp_provider_register_key(const key[], const defaultValue[])
{
  ArrayPushString(g_aKeys, key);
}

FormatKey(output[], len, const authId[], const key[])
{
  return formatex(output, len, "%s%s", authId, key);
}

bool: ReadConfig()
{
  if (!file_exists(CONFIG_FILE))
  {
    log_error(AMX_ERR_NATIVE, "[PP nVault] Config file not found: %s", CONFIG_FILE);
    return false;
  }

  new JSON: hConfig = json_parse(CONFIG_FILE, .is_file = true);

  if (hConfig == Invalid_JSON || !json_is_object(hConfig))
  {
    if (hConfig != Invalid_JSON) json_free(hConfig);
    log_amx("[PP nVault] JSON error in config file: %s", CONFIG_FILE);
    return false;
  }

  json_object_get_string(hConfig, "name", g_szVaultName, charsmax(g_szVaultName));
  g_iPruneDays = json_object_get_number(hConfig, "prune_days");

  json_free(hConfig);

  if (g_szVaultName[0] == EOS)
  {
    log_amx("[PP nVault] Configuration is incomplete: name is required");
    return false;
  }

  return true;
}
