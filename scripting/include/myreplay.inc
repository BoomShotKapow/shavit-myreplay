#if defined _shavit_myreplay_included
 #endinput
#endif
#define _shavit_myreplay_included

#include <shavit/steamid-stocks>
#include <shavit/replay-stocks.sp>

stock bool GetClientAccountID(int client, char[] buffer, int length)
{
    char steamID[64];
    if(!GetClientAuthId(client, AuthId_Steam2, steamID, sizeof(steamID)))
    {
        return false;
    }

    int auth = SteamIDToAccountID(steamID);

    if(auth == 0)
    {
        return false;
    }

    IntToString(auth, buffer, length);

    return true;
}

enum struct PersonalReplay
{
    int auth;
    char sAuth[64];
    char username[MAX_NAME_LENGTH];

    void GetPath(char[] path, int length, bool temp = false)
    {
        char replayFolder[PLATFORM_MAX_PATH];
        Shavit_GetReplayFolderPath(replayFolder, sizeof(replayFolder));

        char mapName[PLATFORM_MAX_PATH];
        GetCurrentMap(mapName, sizeof(mapName));
        GetMapDisplayName(mapName, mapName, sizeof(mapName));
        LowercaseString(mapName);

        FormatEx(path, length, "%s/copy/%d_%s.replay", replayFolder, this.auth, mapName);

        if(temp)
        {
            StrCat(path, length, ".temp");
        }
    }

    bool GetHeader(replay_header_t header)
    {
        char replayPath[PLATFORM_MAX_PATH];
        this.GetPath(replayPath, sizeof(replayPath));

        File file = ReadReplayHeader(replayPath, header);

        if(file == null)
        {
            return false;
        }

        delete file;

        return true;
    }

    void Reset(int client = 0, int auth = 0)
    {
        if(client == 0 && auth != 0)
        {
            this.auth = auth;
            IntToString(this.auth, this.sAuth, sizeof(this.sAuth));

            return;
        }

        if(GetClientAccountID(client, this.sAuth, sizeof(this.sAuth)))
        {
            this.auth = StringToInt(this.sAuth);
            GetClientName(client, this.username, sizeof(this.username));
        }
    }
}

/**
 * Called when a personal replay has been saved.
 *
 * @param client                    Client index of the player who saved a personal replay.
 * @param style                     Style the personal replay was done on.
 * @param track                     The track that the personal replay was saved on.
 * @param path                      Path to the location of the saved personal replay file.
 *
 * @noreturn
 */
forward void Shavit_OnPersonalReplaySaved(int client, int style, int track, const char[] path);

/**
 * Called when a personal replay has been deleted.
 *
 * @param client                    Client index of the player who deleted their personal replay.
 *
 * @noreturn
 */
forward void Shavit_OnPersonalReplayDeleted(int client);

/**
 * Retrieves the personal replay data for the specified client.
 *
 * @param client                    Client index.
 * @param replay                    Buffer to store personal replay data in sizeof(PersonalReplay)
 * @param size                      Size of the personal replay buffer, e.g sizeof(PersonalReplay)
 *
 * @noreturn
 */
native int Shavit_GetPersonalReplay(int client, any[] replay, int size = sizeof(PersonalReplay));

public SharedPlugin __pl_shavit_myreplay =
{
    name = "shavit-myreplay",
    file = "shavit-myreplay.smx",
#if defined REQUIRE_PLUGIN
    required = 1
#else
    required = 0
#endif
};

#if !defined REQUIRE_PLUGIN
public void __pl_shavit_myreplay_SetNTVOptional()
{
	MarkNativeAsOptional("Shavit_GetPersonalReplay");
}
#endif