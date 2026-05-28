#include <amxmodx>
#include <sqlx>
#include <json>
#include <player_prefs>

const MAX_QUERY_LENGTH = 4096;

new const CONFIG_FILE[] = "addons/amxmodx/configs/player_prefs_mysql.json";

enum _: PlayerQuery {
  playerQuery_playerIndex,
  playerQuery_userid,
  playerQuery_databaseId,
  playerQuery_key[MAX_KEY_LENGTH],
  playerQuery_value[MAX_VALUE_LENGTH]
};

new g_szSqlHost[64];
new g_szSqlUser[32];
new g_szSqlPass[128];
new g_szSqlDatabase[32];

new Handle: g_hSqlTuple;
new g_szQuery[MAX_QUERY_LENGTH];

public plugin_init()
{
  register_plugin("Player Prefs — MySQL Provider", "1.0.0", "ufame");
}

public pp_provider_connect()
{
  ReadCredentials();
  Connect();
}

public pp_provider_load_keys()
{
  formatex(g_szQuery, charsmax(g_szQuery),
    "SELECT `key`, `default_value` \
    FROM `pp_keys`;"
  );

  SQL_ThreadQuery(g_hSqlTuple, "OnLoadKeysResult", g_szQuery);
}

public pp_provider_load_player(const playerIndex, const authId[])
{
  formatex(g_szQuery, charsmax(g_szQuery),
    "SELECT `id` \
    FROM `pp_players` \
    WHERE `authid` = '%s';",
    authId
  );

  new queryData[PlayerQuery];
  queryData[playerQuery_playerIndex] = playerIndex;
  queryData[playerQuery_userid] = get_user_userid(playerIndex);

  SQL_ThreadQuery(g_hSqlTuple, "OnLoadPlayerResult", g_szQuery, queryData, sizeof queryData);
}

public pp_provider_save_pref(const playerIndex, const authId[], const key[], const value[])
{
  formatex(g_szQuery, charsmax(g_szQuery),
    "INSERT IGNORE INTO `pp_keys` (`key`, `default_value`) VALUES ('%s', ''); \
    INSERT INTO `pp_preferences` (`player_id`, `key_id`, `value`) \
      SELECT pl.`id`, k.`id`, '%s' \
      FROM `pp_players` pl \
      JOIN `pp_keys` k ON k.`key` = '%s' \
      WHERE pl.`authid` = '%s' \
    ON DUPLICATE KEY UPDATE `value` = VALUES(`value`);",
    key,
    value,
    key,
    authId
  );

  new queryData[PlayerQuery];
  queryData[playerQuery_playerIndex] = playerIndex;
  queryData[playerQuery_userid] = get_user_userid(playerIndex);

  SQL_ThreadQuery(g_hSqlTuple, "OnSavePrefResult", g_szQuery, queryData, sizeof queryData);
}

public pp_provider_register_key(const key[], const defaultValue[])
{
  formatex(g_szQuery, charsmax(g_szQuery),
    "INSERT INTO `pp_keys` (`key`, `default_value`) VALUES ('%s', '%s') \
    ON DUPLICATE KEY UPDATE `default_value` = VALUES(`default_value`);",
    key, defaultValue
  );

  SQL_ThreadQuery(g_hSqlTuple, "OnRegisterKeyResult", g_szQuery);
}

public OnLoadKeysResult(failState, Handle: query, errorMessage[], errorCode, data[], dataSize, Float: queueTime)
{
  if (failState != TQUERY_SUCCESS)
  {
    LogQueryError(query, errorMessage, errorCode, queueTime);
    return;
  }

  new key[MAX_KEY_LENGTH];
  new defaultValue[MAX_VALUE_LENGTH];

  while (SQL_MoreResults(query))
  {
    SQL_ReadResult(query, SQL_FieldNameToNum(query, "key"), key, charsmax(key));
    SQL_ReadResult(query, SQL_FieldNameToNum(query, "default_value"), defaultValue, charsmax(defaultValue));

    pp_provider_key_loaded(key, defaultValue);

    SQL_NextRow(query);
  }

  pp_provider_keys_done();

  log_amx("[PP MySQL] Keys loaded.");
}

public OnLoadPlayerResult(failState, Handle: query, errorMessage[], errorCode, data[], dataSize, Float: queueTime)
{
  if (failState != TQUERY_SUCCESS)
  {
    LogQueryError(query, errorMessage, errorCode, queueTime);
    return;
  }

  new playerIndex = data[playerQuery_playerIndex];
  new userid = data[playerQuery_userid];

  if (!IsSessionValid(playerIndex, userid))
    return;

  if (!SQL_NumResults(query))
  {
    InsertPlayer(playerIndex, userid, data, dataSize);
    return;
  }

  data[playerQuery_databaseId] = SQL_ReadResult(query, SQL_FieldNameToNum(query, "id"));

  QueryPlayerPrefs(data, dataSize);
}

public OnInsertPlayerResult(failState, Handle: query, errorMessage[], errorCode, data[], dataSize, Float: queueTime)
{
  if (failState != TQUERY_SUCCESS)
  {
    LogQueryError(query, errorMessage, errorCode, queueTime);
    return;
  }

  new playerIndex = data[playerQuery_playerIndex];
  new userid = data[playerQuery_userid];

  if (!IsSessionValid(playerIndex, userid))
    return;

  pp_provider_player_done(playerIndex);
}

public OnLoadPrefsResult(failState, Handle: query, errorMessage[], errorCode, data[], dataSize, Float: queueTime)
{
  if (failState != TQUERY_SUCCESS)
  {
    LogQueryError(query, errorMessage, errorCode, queueTime);
    return;
  }

  new playerIndex = data[playerQuery_playerIndex];
  new userid = data[playerQuery_userid];

  if (!IsSessionValid(playerIndex, userid))
    return;

  new key[MAX_KEY_LENGTH];
  new value[MAX_VALUE_LENGTH];

  while (SQL_MoreResults(query))
  {
    SQL_ReadResult(query, SQL_FieldNameToNum(query, "key"), key, charsmax(key));
    SQL_ReadResult(query, SQL_FieldNameToNum(query, "value"), value, charsmax(value));

    pp_provider_pref_loaded(playerIndex, key, value);

    SQL_NextRow(query);
  }

  pp_provider_player_done(playerIndex);
}

public OnSavePrefResult(failState, Handle: query, errorMessage[], errorCode, data[], dataSize, Float: queueTime)
{
  if (failState != TQUERY_SUCCESS)
    LogQueryError(query, errorMessage, errorCode, queueTime);
}

public OnRegisterKeyResult(failState, Handle: query, errorMessage[], errorCode, data[], dataSize, Float: queueTime)
{
  if (failState != TQUERY_SUCCESS)
    LogQueryError(query, errorMessage, errorCode, queueTime);
}

InsertPlayer(playerIndex, userid, queryData[], dataSize)
{
  new authId[MAX_AUTHID_LENGTH];
  get_user_authid(playerIndex, authId, charsmax(authId));

  formatex(g_szQuery, charsmax(g_szQuery),
    "INSERT INTO `pp_players` (`authid`) VALUES ('%s');",
    authId
  );

  queryData[playerQuery_playerIndex] = playerIndex;
  queryData[playerQuery_userid] = userid;

  SQL_ThreadQuery(g_hSqlTuple, "OnInsertPlayerResult", g_szQuery, queryData, dataSize);
}

QueryPlayerPrefs(queryData[], dataSize)
{
  formatex(g_szQuery, charsmax(g_szQuery),
    "SELECT k.`key`, pr.`value` \
    FROM `pp_preferences` pr \
    JOIN `pp_keys` k ON k.`id` = pr.`key_id` \
    WHERE pr.`player_id` = %d;",
    queryData[playerQuery_databaseId]
  );

  SQL_ThreadQuery(g_hSqlTuple, "OnLoadPrefsResult", g_szQuery, queryData, dataSize);
}

bool: IsSessionValid(const playerIndex, const userid)
{
  return is_user_connected(playerIndex) && get_user_userid(playerIndex) == userid;
}

LogQueryError(Handle: query, const errorMessage[], errorCode, Float: queueTime)
{
  SQL_GetQueryString(query, g_szQuery, charsmax(g_szQuery));

  log_amx("[PP MySQL] Error [%d]: %s", errorCode, errorMessage);
  log_amx("[PP MySQL] Queue time: %.4f сек", queueTime);
  log_amx("[PP MySQL] Query: %s", g_szQuery);
}

ReadCredentials() {
  if (!file_exists(CONFIG_FILE))
  {
    abort(AMX_ERR_GENERAL, "[PP MySQL] Config file no found: %s", CONFIG_FILE);
    return;
  }

  new JSON: config = json_parse(CONFIG_FILE, .is_file = true);

  if (config == Invalid_JSON || !json_is_object(config))
  {
    if (config != Invalid_JSON)
      json_free(config);

    abort(AMX_ERR_GENERAL, "[PP MySQL] JSON read error: %s", CONFIG_FILE);
    return;
  }

  json_object_get_string(config, "host", g_szSqlHost,     charsmax(g_szSqlHost));
  json_object_get_string(config, "user", g_szSqlUser,     charsmax(g_szSqlUser));
  json_object_get_string(config, "pass", g_szSqlPass,     charsmax(g_szSqlPass));
  json_object_get_string(config, "db",   g_szSqlDatabase, charsmax(g_szSqlDatabase));

  json_free(config);
}

Connect()
{
  SQL_SetAffinity("mysql");

  g_hSqlTuple = SQL_MakeDbTuple(g_szSqlHost, g_szSqlUser, g_szSqlPass, g_szSqlDatabase);

  new errorMessage[512];
  new errorCode;
  new Handle: connection = SQL_Connect(g_hSqlTuple, errorCode, errorMessage, charsmax(errorMessage));

  if (connection == Empty_Handle)
  {
    SQL_FreeHandle(g_hSqlTuple);
    g_hSqlTuple = Empty_Handle;

    log_amx("[PP MySQL] Connection error [%d]: %s", errorCode, errorMessage);
    pp_provider_ready(false);

    return;
  }

  SQL_FreeHandle(connection);

  log_amx("[PP MySQL] Connection successfull.");

  CreateSchema();
}

CreateSchema()
{
  formatex(g_szQuery, charsmax(g_szQuery),
    "CREATE TABLE IF NOT EXISTS `pp_keys` ( \
      `id` INT UNSIGNED NOT NULL AUTO_INCREMENT, \
      `key` VARCHAR(64)  NOT NULL, \
      `default_value` VARCHAR(256) NOT NULL DEFAULT '', \
      PRIMARY KEY (`id`), \
      UNIQUE KEY `uq_key` (`key`) \
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4; \
    CREATE TABLE IF NOT EXISTS `pp_players` ( \
      `id` INT UNSIGNED NOT NULL AUTO_INCREMENT, \
      `authid` VARCHAR(32)  NOT NULL, \
      PRIMARY KEY (`id`), \
      UNIQUE KEY `uq_authid` (`authid`) \
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4; \
    CREATE TABLE IF NOT EXISTS `pp_preferences` ( \
      `player_id` INT UNSIGNED NOT NULL, \
      `key_id` INT UNSIGNED NOT NULL, \
      `value` VARCHAR(256) NOT NULL DEFAULT '', \
      PRIMARY KEY (`player_id`, `key_id`), \
      CONSTRAINT `fk_pref_player` FOREIGN KEY (`player_id`) REFERENCES `pp_players` (`id`) ON DELETE CASCADE, \
      CONSTRAINT `fk_pref_key` FOREIGN KEY (`key_id`) REFERENCES `pp_keys` (`id`) ON DELETE CASCADE \
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;"
  );

  SQL_ThreadQuery(g_hSqlTuple, "OnCreateSchemaResult", g_szQuery);
}

public OnCreateSchemaResult(failState, Handle: query, errorMessage[], errorCode, data[], dataSize, Float: queueTime)
{
  if (failState != TQUERY_SUCCESS)
  {
    LogQueryError(query, errorMessage, errorCode, queueTime);
    pp_provider_ready(false);
    return;
  }

  pp_provider_ready(true);
}