#include <amxmodx>
#include <sqlx>
#include <player_prefs>

#pragma reqlib sqlite
#if !defined AMXMODX_NOAUTOLOAD
    #pragma loadlib sqlite
#endif

const MAX_QUERY_LENGTH = 4096;

new const DB_NAME[] = "player_prefs";

enum _: PlayerQuery {
    playerQuery_playerIndex,
    playerQuery_userid,
    playerQuery_databaseId,
    playerQuery_key[MAX_KEY_LENGTH],
    playerQuery_value[MAX_VALUE_LENGTH]
};

new Handle: g_hSqlTuple;
new g_szQuery[MAX_QUERY_LENGTH];

public plugin_init()
{
    register_plugin("Player Prefs — SQLite Provider", "1.0.0", "Nordic Warrior");
}

public pp_provider_connect()
{
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
    new safeKey[MAX_KEY_LENGTH * 2], safeValue[MAX_VALUE_LENGTH * 2];
    QuoteString(key, safeKey, charsmax(safeKey));
    QuoteString(value, safeValue, charsmax(safeValue));

    formatex(g_szQuery, charsmax(g_szQuery),
        "INSERT OR IGNORE INTO `pp_keys` (`key`, `default_value`) VALUES ('%s', '');",
        safeKey
    );

    SQL_ThreadQuery(g_hSqlTuple, "OnSaveKeyResult", g_szQuery);

    formatex(g_szQuery, charsmax(g_szQuery),
        "INSERT INTO `pp_preferences` (`player_id`, `key_id`, `value`) \
        SELECT pl.`id`, k.`id`, '%s' \
        FROM `pp_players` pl \
        JOIN `pp_keys` k ON k.`key` = '%s' \
        WHERE pl.`authid` = '%s' \
        ON CONFLICT(`player_id`, `key_id`) DO UPDATE SET `value` = excluded.`value`;",
        safeValue,
        safeKey,
        authId
    );

    new queryData[PlayerQuery];
    queryData[playerQuery_playerIndex] = playerIndex;
    queryData[playerQuery_userid] = get_user_userid(playerIndex);

    SQL_ThreadQuery(g_hSqlTuple, "OnSavePrefResult", g_szQuery, queryData, sizeof queryData);
}

public pp_provider_register_key(const key[], const defaultValue[])
{
    new safeKey[MAX_KEY_LENGTH * 2], safeDefault[MAX_VALUE_LENGTH * 2];
    QuoteString(key, safeKey, charsmax(safeKey));
    QuoteString(defaultValue, safeDefault, charsmax(safeDefault));

    formatex(g_szQuery, charsmax(g_szQuery),
        "INSERT INTO `pp_keys` (`key`, `default_value`) VALUES ('%s', '%s') \
        ON CONFLICT(`key`) DO UPDATE SET `default_value` = excluded.`default_value`;",
        safeKey, safeDefault
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

    log_amx("[PP SQLite] Keys loaded.");
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

public OnSaveKeyResult(failState, Handle: query, errorMessage[], errorCode, data[], dataSize, Float: queueTime)
{
    if (failState != TQUERY_SUCCESS)
        LogQueryError(query, errorMessage, errorCode, queueTime);
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
        "INSERT OR IGNORE INTO `pp_players` (`authid`) VALUES ('%s');",
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

// Keys and values come from plugins as is: a quote in a string value would break the statement.
QuoteString(const source[], dest[], const destLen)
{
    if (SQL_QuoteString(Empty_Handle, dest, destLen, source) == -1)
        copy(dest, destLen, "");
}

bool: IsSessionValid(const playerIndex, const userid)
{
    return is_user_connected(playerIndex) && get_user_userid(playerIndex) == userid;
}

LogQueryError(Handle: query, const errorMessage[], errorCode, Float: queueTime)
{
    SQL_GetQueryString(query, g_szQuery, charsmax(g_szQuery));

    log_amx("[PP SQLite] Error [%d]: %s", errorCode, errorMessage);
    log_amx("[PP SQLite] Queue time: %.4f sec", queueTime);
    log_amx("[PP SQLite] Query: %s", g_szQuery);
}

Connect()
{
    if (!SQL_SetAffinity("sqlite"))
    {
        log_amx("[PP SQLite] Failed to set SQL affinity to 'sqlite'.");
        pp_provider_ready(false);
        return;
    }

    g_hSqlTuple = SQL_MakeDbTuple("", "", "", DB_NAME);

    new errorMessage[512];
    new errorCode;
    new Handle: connection = SQL_Connect(g_hSqlTuple, errorCode, errorMessage, charsmax(errorMessage));

    if (connection == Empty_Handle)
    {
        SQL_FreeHandle(g_hSqlTuple);
        g_hSqlTuple = Empty_Handle;

        log_amx("[PP SQLite] Connection error [%d]: %s", errorCode, errorMessage);
        pp_provider_ready(false);

        return;
    }

    SQL_FreeHandle(connection);

    log_amx("[PP SQLite] Connection successful.");

    CreateSchema();
}

CreateSchema()
{
    formatex(g_szQuery, charsmax(g_szQuery),
        "CREATE TABLE IF NOT EXISTS `pp_keys` ( \
            `id` INTEGER PRIMARY KEY AUTOINCREMENT, \
            `key` VARCHAR(64) NOT NULL, \
            `default_value` VARCHAR(256) NOT NULL DEFAULT '', \
            UNIQUE (`key`) \
        );"
    );

    SQL_ThreadQuery(g_hSqlTuple, "OnCreateKeysResult", g_szQuery);
}

public OnCreateKeysResult(failState, Handle: query, errorMessage[], errorCode, data[], dataSize, Float: queueTime)
{
    if (failState != TQUERY_SUCCESS)
    {
        LogQueryError(query, errorMessage, errorCode, queueTime);
        pp_provider_ready(false);
        return;
    }

    formatex(g_szQuery, charsmax(g_szQuery),
        "CREATE TABLE IF NOT EXISTS `pp_players` ( \
            `id` INTEGER PRIMARY KEY AUTOINCREMENT, \
            `authid` VARCHAR(32) NOT NULL, \
            UNIQUE (`authid`) \
        );"
    );

    SQL_ThreadQuery(g_hSqlTuple, "OnCreatePlayersResult", g_szQuery);
}

public OnCreatePlayersResult(failState, Handle: query, errorMessage[], errorCode, data[], dataSize, Float: queueTime)
{
    if (failState != TQUERY_SUCCESS)
    {
        LogQueryError(query, errorMessage, errorCode, queueTime);
        pp_provider_ready(false);
        return;
    }

    formatex(g_szQuery, charsmax(g_szQuery),
        "CREATE TABLE IF NOT EXISTS `pp_preferences` ( \
            `player_id` INTEGER NOT NULL, \
            `key_id` INTEGER NOT NULL, \
            `value` VARCHAR(256) NOT NULL DEFAULT '', \
            PRIMARY KEY (`player_id`, `key_id`), \
            FOREIGN KEY (`player_id`) REFERENCES `pp_players` (`id`) ON DELETE CASCADE, \
            FOREIGN KEY (`key_id`) REFERENCES `pp_keys` (`id`) ON DELETE CASCADE \
        );"
    );

    SQL_ThreadQuery(g_hSqlTuple, "OnCreatePrefsResult", g_szQuery);
}

public OnCreatePrefsResult(failState, Handle: query, errorMessage[], errorCode, data[], dataSize, Float: queueTime)
{
    if (failState != TQUERY_SUCCESS)
    {
        LogQueryError(query, errorMessage, errorCode, queueTime);
        pp_provider_ready(false);
        return;
    }

    EnableForeignKeys();
}

EnableForeignKeys()
{
    formatex(g_szQuery, charsmax(g_szQuery), "PRAGMA foreign_keys = ON;");

    SQL_ThreadQuery(g_hSqlTuple, "OnPragmaResult", g_szQuery);
}

public OnPragmaResult(failState, Handle: query, errorMessage[], errorCode, data[], dataSize, Float: queueTime)
{
    if (failState != TQUERY_SUCCESS)
    {
        LogQueryError(query, errorMessage, errorCode, queueTime);
        pp_provider_ready(false);
        return;
    }

    pp_provider_ready(true);
}
