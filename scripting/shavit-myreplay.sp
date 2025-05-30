#include <sourcemod>
#include <shavit/core>
#include <shavit/wr>
#include <shavit/replay-file>
#include <shavit/replay-playback>
#include <shavit/replay-recorder>
#include <myreplay>
#include <clientprefs>

#pragma newdecls required
#pragma semicolon 1

Handle gH_Forwards_OnPersonalReplaySaved = null;
Handle gH_Forwards_OnPersonalReplayDeleted = null;

StringMap gSM_Replays;

Menu gM_ReplayMenu[MAXPLAYERS + 1];

char gS_Map[PLATFORM_MAX_PATH];
char gS_PreviousMap[PLATFORM_MAX_PATH];
char gS_SQLPrefix[32];

Database gH_ShavitDB;

bool gB_Late;
bool gB_Debug;
bool gB_Connected;
bool gB_ReplayPlayback;
bool gB_ReplayRecorder;
bool gB_ShowMenu[MAXPLAYERS + 1] = {true, ... };
bool gB_AutoSave[MAXPLAYERS + 1];
bool gB_AutoWatch[MAXPLAYERS + 1];
bool gB_MenuDelayed[MAXPLAYERS + 1];

float gF_MenuDelayTime = 1.75;

int gI_NumReplays;

frame_cache_t gA_FrameCache[MAXPLAYERS + 1];

stylestrings_t gS_StyleStrings[STYLE_LIMIT];

Cookie gC_ShowMenuCookie = null;
Cookie gC_AutoSaveCookie = null;
Cookie gC_AutoWatchCookie = null;

public Plugin myinfo =
{
    name        = "shavit - Personal Replays",
    author      = "BoomShot",
    description = "Allows a user to watch their replay after finishing the map.",
    version     = "1.0.4",
    url         = "https://github.com/BoomShotKapow/shavit-myreplay"
};

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
    CreateNative("Shavit_GetPersonalReplay", Native_GetPersonalReplay);

    RegPluginLibrary("shavit-myreplay");

    gB_Late = late;

    return APLRes_Success;
}

public void OnPluginStart()
{
    gH_Forwards_OnPersonalReplaySaved = new GlobalForward("Shavit_OnPersonalReplaySaved", ET_Ignore, Param_Cell, Param_Cell, Param_Cell, Param_String);
    gH_Forwards_OnPersonalReplayDeleted = new GlobalForward("Shavit_OnPersonalReplayDeleted", ET_Ignore, Param_Cell);

    gC_ShowMenuCookie = new Cookie("sm_myreplay_showmenu", "Toggles the display of the menu.", CookieAccess_Protected);
    gC_AutoSaveCookie = new Cookie("sm_myreplay_autosave", "Toggles the auto saving of personal replays.", CookieAccess_Protected);
    gC_AutoWatchCookie = new Cookie("sm_myreplay_autowatch", "Toggles the auto watching of personal replays.", CookieAccess_Protected);

    RegConsoleCmd("sm_rewatch", Command_Rewatch, "Rewatch your personal replay");
    RegConsoleCmd("sm_watch", Command_Watch, "Watch another user's personal replay");
    RegConsoleCmd("sm_deletepr", Command_DeleteReplay, "Delete your personal replay");
    RegConsoleCmd("sm_preview", Command_Preview, "Preview your unfinished replay");
    RegConsoleCmd("sm_myreplay", Command_MyReplay, "Toggles the display of the personal replay menu.");

    RegAdminCmd("sm_reload_replays", Command_ReloadReplays, ADMFLAG_RCON, "Reloads the replays in the folder");
    RegAdminCmd("sm_myreplay_debug", Command_Debug, ADMFLAG_ROOT);

    gSM_Replays = new StringMap();

    gB_ReplayRecorder = LibraryExists("shavit-replay-recorder");
    gB_ReplayPlayback = LibraryExists("shavit-replay-playback");

    if(gB_Late)
    {
        Shavit_OnDatabaseLoaded();
        Shavit_OnStyleConfigLoaded(Shavit_GetStyleCount());

        for(int client = 1; client <= MaxClients; client++)
        {
            if(IsClientInGame(client))
            {
                OnClientPutInServer(client);
            }
        }
    }
}

public void OnAllPluginsLoaded()
{
    gB_ReplayRecorder = LibraryExists("shavit-replay-recorder");
    gB_ReplayPlayback = LibraryExists("shavit-replay-playback");

    if(!gB_ReplayRecorder)
    {
        SetFailState("shavit-replay-recorder is required for this plugin!");
    }
    else if(!gB_ReplayPlayback)
    {
        SetFailState("shavit-replay-playback is required for this plugin!");
    }
}

public void OnLibraryAdded(const char[] name)
{
    if(StrEqual(name, "shavit-replay-recorder"))
    {
        gB_ReplayRecorder = true;
    }
    else if(StrEqual(name, "shavit-replay-playback"))
    {
        gB_ReplayPlayback = true;
    }
}

public void OnLibraryRemoved(const char[] name)
{
    if(StrEqual(name, "shavit-replay-recorder"))
    {
        gB_ReplayRecorder = false;
    }
    else if(StrEqual(name, "shavit-replay-playback"))
    {
        gB_ReplayPlayback = false;
    }
}

public void OnMapInit(const char[] mapName)
{
    strcopy(gS_Map, sizeof(gS_Map), mapName);
    LowercaseString(gS_Map);
}

public void OnMapStart()
{
    GetLowercaseMapName(gS_Map);

    if(!gB_Connected || gH_ShavitDB == null)
    {
        return;
    }

    if(!StrEqual(gS_Map, gS_PreviousMap, false))
    {
        GetReplayList();
    }
}

public void OnMapEnd()
{
    strcopy(gS_PreviousMap, sizeof(gS_PreviousMap), gS_Map);
}

public void OnClientPutInServer(int client)
{
    if(IsFakeClient(client))
    {
        return;
    }

    gB_ShowMenu[client] = true;
    gB_AutoSave[client] = false;
    gB_AutoWatch[client] = false;
    gB_MenuDelayed[client] = false;

    if(AreClientCookiesCached(client))
    {
        OnClientCookiesCached(client);
    }
}

public void OnClientCookiesCached(int client)
{
    char cookie[4];

    gC_ShowMenuCookie.Get(client, cookie, sizeof(cookie));
    gB_ShowMenu[client] = (strlen(cookie) > 0) ? view_as<bool>(StringToInt(cookie)) : true;

    gC_AutoSaveCookie.Get(client, cookie, sizeof(cookie));
    gB_AutoSave[client] = (strlen(cookie) > 0) ? view_as<bool>(StringToInt(cookie)) : false;

    gC_AutoWatchCookie.Get(client, cookie, sizeof(cookie));
    gB_AutoWatch[client] = (strlen(cookie) > 0) ? view_as<bool>(StringToInt(cookie)) : false;
}

public void OnClientDisconnect(int client)
{
    if(IsFakeClient(client))
    {
        return;
    }

    gB_ShowMenu[client] = true;

    PersonalReplay replay;
    GetPersonalReplay(replay, client);

    char tempPath[PLATFORM_MAX_PATH];
    replay.GetPath(tempPath, sizeof(tempPath), true);

    if(DeleteFile(tempPath))
    {
        PrintDebug("OnClientDisconnect: %N || Deleting: [%s]", client, tempPath);
    }

    if(gM_ReplayMenu[client] != null)
    {
        delete gM_ReplayMenu[client];
    }
}

public void Shavit_OnDatabaseLoaded()
{
    GetTimerSQLPrefix(gS_SQLPrefix, sizeof(gS_SQLPrefix));
    gH_ShavitDB = Shavit_GetDatabase();

    gB_Connected = true;

    if(!gB_Late)
    {
        OnMapStart();
    }
}

public void Shavit_OnStyleConfigLoaded(int styles)
{
    for(int i = 0; i < styles; i++)
    {
        Shavit_GetStyleStringsStruct(i, gS_StyleStrings[i]);
    }
}

public Action Shavit_OnFinishPre(int client, timer_snapshot_t snapshot)
{
    //Prevent menu from displaying when it's a new WR or if using autosave
    if(!gB_ShowMenu[client] || Shavit_GetRankForTime(snapshot.bsStyle, snapshot.fCurrentTime, snapshot.iTimerTrack) == 1 || gB_AutoSave[client])
    {
        return Plugin_Continue;
    }

    //Totally not ripped from Shavit's: https://github.com/shavitush/bhoptimer/blob/870c62a8c94a93537e72e8f0ccbfeb4dd5810d42/addons/sourcemod/scripting/shavit-mapchooser.sp#L725-L758
    gB_MenuDelayed[client] = (IsClientInGame(client) && !IsFakeClient(client) && GetClientMenu(client) != MenuSource_None);

    if(gB_MenuDelayed[client])
    {
        Shavit_PrintToChat(client, "You had a menu open. Waiting %.2fs before accepting input", gF_MenuDelayTime);
    }

    CreateTimer(gF_MenuDelayTime + 0.1, Timer_MenuDelay, 0, TIMER_FLAG_NO_MAPCHANGE);

    gM_ReplayMenu[client] = new Menu(PersonalReplay_MenuHandler, MenuAction_DrawItem);
    gM_ReplayMenu[client].SetTitle("Personal Replay\nDo you want to view your run?");
    gM_ReplayMenu[client].AddItem("", "", ITEMDRAW_SPACER);
    gM_ReplayMenu[client].AddItem("yes", "Yes (Loading...)", ITEMDRAW_DISABLED);
    gM_ReplayMenu[client].AddItem("no", "No");
    gM_ReplayMenu[client].AddItem("save", "Save for later.");
    gM_ReplayMenu[client].AddItem("", "", ITEMDRAW_SPACER);
    gM_ReplayMenu[client].AddItem("stop", "Stop asking, please.");
    gM_ReplayMenu[client].Display(client, 20);

    return Plugin_Continue;
}

public Action Timer_MenuDelay(Handle timer, any data)
{
    for(int client = 1; client <= MaxClients; client++)
    {
        if(gB_MenuDelayed[client])
        {
            gB_MenuDelayed[client] = false;

            if(IsClientInGame(client))
            {
                gM_ReplayMenu[client].Display(client, 20);
            }
        }
    }

    return Plugin_Stop;
}

public Action Shavit_ShouldSaveReplayCopy(int client, int style, float time, int jumps, int strafes, float sync, int track, float oldtime, float perfs, float avgvel, float maxvel, int timestamp, bool isbestreplay, bool istoolong)
{
    if(!gB_ReplayRecorder || isbestreplay || istoolong || !gB_ShowMenu[client])
    {
        if(!gB_ShowMenu[client])
        {
            PrintDebug("Shavit_ShouldSaveReplayCopy: %N || Menu is disabled", client);
        }

        return Plugin_Continue;
    }

    return Plugin_Changed;
}

public void Shavit_OnReplaySaved(int client, int style, float time, int jumps, int strafes, float sync, int track, float oldtime, float perfs, float avgvel, float maxvel, int timestamp, bool isbestreplay, bool istoolong, bool iscopy, const char[] replaypath, ArrayList frames, int preframes, int postframes, const char[] name)
{
    PersonalReplay replay;
    GetPersonalReplay(replay, client);

    char path[PLATFORM_MAX_PATH];
    replay.GetPath(path, sizeof(path));

    replay_header_t header;

    PrintDebug("Shavit_OnReplaySaved: %N || time: %f || isbestreplay: %b || iscopy: %b", client, time, isbestreplay, iscopy);

    if(!gB_ReplayRecorder || istoolong || (!isbestreplay && !iscopy) || !gB_ShowMenu[client])
    {
        return;
    }
    else if(isbestreplay)
    {
        //Set the player's personal replay to their best replay if they don't have one
        //Or auto save the better replay
        if(!replay.GetHeader(header) || (gB_AutoSave[client] && header.fTime > time && header.iStyle == style && header.iTrack == track))
        {
            PrintDebug("Copying file: [%s] to [%s]", replaypath, path);

            if(CopyReplayFile(replaypath, path))
            {
                SavePersonalReplay(client);

                if(gB_AutoWatch[client])
                {
                    StartPersonalReplay(client, replay.sAuth);
                }
            }
        }

        return;
    }

    if(gB_AutoSave[client])
    {
        if(!replay.GetHeader(header) || (header.fTime > time && header.iStyle == style && header.iTrack == track))
        {
            PrintDebug("Renaming file: [%s] to [%s]", replaypath, path);

            //Rename file to permanent
            if(RenameFile(path, replaypath))
            {
                SavePersonalReplay(client);

                if(gB_AutoWatch[client])
                {
                    StartPersonalReplay(client, replay.sAuth);
                }
            }
        }
        else
        {
            if(DeleteFile(replaypath))
            {
                PrintDebug("Deleting worse replay: [%s]", replaypath);
            }
        }
    }
    else
    {
        char tempPath[PLATFORM_MAX_PATH];
        replay.GetPath(tempPath, sizeof(tempPath), true);

        PrintDebug("Renaming file: [%s] to [%s]", replaypath, tempPath);

        //Rename file to temp so that we can reference it later
        RenameFile(tempPath, replaypath);

        if(gM_ReplayMenu[client] != null)
        {
            gM_ReplayMenu[client].RemoveItem(1);
            gM_ReplayMenu[client].InsertItem(1, "yes", "Yes");
            gM_ReplayMenu[client].Display(client, 20);
        }
    }
}

bool CopyReplayFile(const char[] from, const char[] to)
{
    File original = OpenFile(from, "rb");

    if(original == null)
    {
        LogError("[MyReplay] Failed to read replay file: [%s]!", from);
        return false;
    }

    File copy = OpenFile(to, "wb+");

    if(copy == null)
    {
        delete original;

        LogError("[MyReplay] Failed to write replay file: [%s]!", to);
        return false;
    }

    if(!original.Seek(0, SEEK_SET))
    {
        return false;
    }

    int buffer[256];

    while(!original.EndOfFile())
    {
        int read = original.Read(buffer, sizeof(buffer), 4);

        copy.Write(buffer, read, 4);
    }

    delete original;
    delete copy;

    return true;
}

void SavePersonalReplay(int client)
{
    PersonalReplay replay;
    GetPersonalReplay(replay, client);

    replay_header_t header;
    replay.GetHeader(header);

    if(!gSM_Replays.ContainsKey(replay.sAuth))
    {
        gI_NumReplays++;
    }

    gSM_Replays.SetArray(replay.sAuth, replay, sizeof(replay));

    char path[PLATFORM_MAX_PATH];
    replay.GetPath(path, sizeof(path));

    Call_StartForward(gH_Forwards_OnPersonalReplaySaved);
    Call_PushCell(client);
    Call_PushCell(header.iStyle);
    Call_PushCell(header.iTrack);
    Call_PushString(path);
    Call_Finish();

    Shavit_PrintToChat(client, "Your personal replay has been saved!");
}

public int PersonalReplay_MenuHandler(Menu menu, MenuAction action, int param1, int param2)
{
    switch(action)
    {
        case MenuAction_Select:
        {
            PersonalReplay replay;
            GetPersonalReplay(replay, param1);

            char replayPath[PLATFORM_MAX_PATH];
            replay.GetPath(replayPath, sizeof(replayPath));

            char tempPath[PLATFORM_MAX_PATH];
            replay.GetPath(tempPath, sizeof(tempPath), true);

            char info[16];
            if(menu.GetItem(param2, info, sizeof(info)))
            {
                if(StrEqual(info, "yes") || StrEqual(info, "save"))
                {
                    //Change temporary file name to permanent
                    if(RenameFile(replayPath, tempPath))
                    {
                        char option[8];
                        option = StrEqual(info, "yes") ? "Yes" : "Save";

                        PrintDebug("[%s] Renaming file: [%s] to [%s]", option, tempPath, replayPath);

                        SavePersonalReplay(param1);

                        if(StrEqual(info, "yes"))
                        {
                            StartPersonalReplay(param1, replay.sAuth);
                        }
                    }
                }
                else if(StrEqual(info, "no") || StrEqual(info, "stop"))
                {
                    char option[8];
                    option = StrEqual(info, "no") ? "No" : "Stop";

                    if(StrEqual(info, "stop"))
                    {
                        gB_ShowMenu[param1] = false;
                    }

                    if(DeleteFile(tempPath))
                    {
                        PrintDebug("[%s]: Deleting file: [%s]", option, tempPath);
                    }
                }
            }

            //Re-display the client's menu if they're on seg/TAS
            if(Shavit_GetStyleSettingBool(Shavit_GetBhopStyle(param1), "segments"))
            {
                FakeClientCommand(param1, "sm_cp");
            }
        }

        case MenuAction_DrawItem:
        {
            char info[16];
            char display[32];

            if(menu.GetItem(param2, info, sizeof(info), _, display, sizeof(display)))
            {
                if(StrEqual(info, ""))
                {
                    return ITEMDRAW_SPACER;
                }
                else if(gB_MenuDelayed[param1])
                {
                    return ITEMDRAW_DISABLED;
                }
                else if(StrEqual(info, "yes"))
                {
                    if(StrEqual(display, "Yes (Loading...)"))
                    {
                        return ITEMDRAW_DISABLED;
                    }
                }
            }
        }

        case MenuAction_Cancel:
        {
            if(param2 == MenuCancel_Timeout || param2 == MenuCancel_Exit)
            {
                PersonalReplay replay;
                GetPersonalReplay(replay, param1);

                char tempPath[PLATFORM_MAX_PATH];
                replay.GetPath(tempPath, sizeof(tempPath), true);

                PrintDebug("MenuAction_Cancel: Deleting file: [%s]", tempPath);
                DeleteFile(tempPath);
            }
        }
    }

    return 0;
}

bool GetPersonalReplay(PersonalReplay replay, int client = 0, const char[] auth = "")
{
    PersonalReplay emptyReplay;
    replay = emptyReplay;

    if(client == 0 && auth[0] == '\0')
    {
        return false;
    }

    char sAuth[64];

    if(client != 0)
    {
        if(!GetClientAccountID(client, sAuth, sizeof(sAuth)))
        {
            return false;
        }
    }
    else if(auth[0] != '\0')
    {
        strcopy(sAuth, sizeof(sAuth), auth);
    }

    replay.Reset(client, StringToInt(sAuth));

    return gSM_Replays.GetArray(sAuth, replay, sizeof(replay));
}

void StartPersonalReplay(int client, const char[] sAuth)
{
    PersonalReplay replay;
    GetPersonalReplay(replay, _, sAuth);

    replay_header_t header;
    replay.GetHeader(header);

    if(header.iSteamID == 0)
    {
        Shavit_PrintToChat(client, "Personal replay doesn't exist!");
        return;
    }

    char replayPath[PLATFORM_MAX_PATH];
    replay.GetPath(replayPath, sizeof(replayPath));

    LoadReplayCache(gA_FrameCache[client], header.iStyle, header.iTrack, replayPath, gS_Map);

    strcopy(gA_FrameCache[client].sReplayName, MAX_NAME_LENGTH, replay.username);

    //Use fake client command with observer-mode-switch-lag-fix plugin to prevent lag while spectating
    FakeClientCommand(client, "sm_spec");

    int bot = Shavit_StartReplayFromFrameCache(header.iStyle, header.iTrack, -1.0, client, -1, Replay_Dynamic, true, gA_FrameCache[client]);

    if(bot == 0)
    {
        Shavit_PrintToChat(client, "Replay bot is unavailable! Try again when it's available.");
        return;
    }
}

public Action Command_Rewatch(int client, int args)
{
    if(!IsValidClient(client))
    {
        return Plugin_Handled;
    }

    char sAuth[64];
    if(!GetClientAccountID(client, sAuth, sizeof(sAuth)))
    {
        return Plugin_Handled;
    }

    StartPersonalReplay(client, sAuth);

    return Plugin_Handled;
}

public Action Command_Watch(int client, int args)
{
    if(!IsValidClient(client))
    {
        return Plugin_Handled;
    }
    else if(args > 0)
    {
        char sAuth[64];
        GetCmdArg(1, sAuth, sizeof(sAuth));

        StartPersonalReplay(client, sAuth);

        return Plugin_Handled;
    }

    StringMapSnapshot snapshot = gSM_Replays.Snapshot();

    PrintDebug("Snapshot: %d || numReplays: %d", snapshot.Length, gI_NumReplays);

    if(snapshot.Length == gI_NumReplays && snapshot.Length > 0)
    {
        Menu menu = new Menu(ReplayList_MenuHandler);
        menu.SetTitle("Personal Replays List");

        for(int i = 0; i < snapshot.Length; i++)
        {
            char sAuth[64];
            snapshot.GetKey(i, sAuth, sizeof(sAuth));

            PersonalReplay replay;
            gSM_Replays.GetArray(sAuth, replay, sizeof(replay));

            replay_header_t header;
            if(!replay.GetHeader(header))
            {
                continue;
            }

            char time[16];
            FormatSeconds(header.fTime, time, sizeof(time));

            int track = header.iTrack;
            char sTrack[4];

            if(track != Track_Main)
            {
                sTrack[0] = 'B';
                if(track > Track_Bonus)
                {
                    sTrack[1] = '0' + track;
                }
            }
            else
            {
                sTrack[0] = 'M';
            }

            char display[128];
            FormatEx(display, sizeof(display), "[%s/%s] %s - %s @ %s", gS_StyleStrings[header.iStyle].sShortName, sTrack, gS_Map, replay.username, time);

            menu.AddItem(sAuth, display);
        }

        menu.Display(client, MENU_TIME_FOREVER);
    }
    else
    {
        Shavit_PrintToChat(client, "There are no personal replays!");
    }

    delete snapshot;

    return Plugin_Handled;
}

public Action Command_DeleteReplay(int client, int args)
{
    if(!IsValidClient(client))
    {
        return Plugin_Handled;
    }

    if(!DeletePersonalReplay(client))
    {
        PrintDebug("Deleting personal replay failed.");
    }

    return Plugin_Handled;
}

bool DeletePersonalReplay(int client)
{
    PersonalReplay replay;
    GetPersonalReplay(replay, client);

    replay_header_t header;
    if(!replay.GetHeader(header))
    {
        Shavit_PrintToChat(client, "Your personal replay doesn't exist!");
        return false;
    }
    else if(replay.auth != header.iSteamID)
    {
        LogError("[MyReplay] Deleting personal replay failed.");
        return false;
    }

    char replayPath[PLATFORM_MAX_PATH];
    replay.GetPath(replayPath, sizeof(replayPath));

    if(DeleteFile(replayPath))
    {
        PrintDebug("Deleted: [%s]", replayPath);
    }

    if(gSM_Replays.Remove(replay.sAuth))
    {
        gI_NumReplays--;
    }

    Call_StartForward(gH_Forwards_OnPersonalReplayDeleted);
    Call_PushCell(client);
    Call_Finish();

    Shavit_PrintToChat(client, "Your personal replay has been deleted!");

    return true;
}

void GetReplayList()
{
    char replayFolder[PLATFORM_MAX_PATH];
    Shavit_GetReplayFolderPath(replayFolder, sizeof(replayFolder));

    char personalReplayFolder[PLATFORM_MAX_PATH];
    FormatEx(personalReplayFolder, sizeof(personalReplayFolder), "%s/copy", replayFolder);

    gI_NumReplays = 0;
    gSM_Replays.Clear();

    DirectoryListing personalReplayDir = OpenDirectory(personalReplayFolder);

    PrintDebug("GetReplayList: [%s]", personalReplayFolder);

    char curFile[PLATFORM_MAX_PATH];
    while(personalReplayDir.GetNext(curFile, sizeof(curFile)))
    {
        int length = strlen(curFile);

        //This will filter most maps, but not fuzzy matches
        if(StrContains(curFile, gS_Map) == -1 || (curFile[length - 4] == 't' && curFile[length - 3] == 'e' && curFile[length - 2] == 'm' && curFile[length - 1] == 'p'))
        {
            continue;
        }

        char replayFile[PLATFORM_MAX_PATH];
        FormatEx(replayFile, sizeof(replayFile), "%s/%s", personalReplayFolder, curFile);

        replay_header_t header;
        File file = ReadReplayHeader(replayFile, header);

        if(file != null)
        {
            delete file;
        }
        else
        {
            continue;
        }

        if(!StrEqual(gS_Map, header.sMap, false))
        {
            continue;
        }

        char sQuery[192];
        FormatEx(sQuery, sizeof(sQuery), "SELECT auth, name FROM %susers WHERE auth = %d;", gS_SQLPrefix, header.iSteamID);

        PrintDebug("Executing SQL: [%s]", sQuery);
        QueryLog(gH_ShavitDB, SQL_GetUserNameFromHeader_Callback, sQuery);
    }

    delete personalReplayDir;
}

public void SQL_GetUserNameFromHeader_Callback(Database db, DBResultSet results, const char[] error, any data)
{
    if(results == null)
    {
        LogError("[MyReplay] Get username from replay failed. Reason: %s", error);
        return;
    }

    if(results.FetchRow())
    {
        char sAuth[64];
        IntToString(results.FetchInt(0), sAuth, sizeof(sAuth));

        PersonalReplay replay;
        GetPersonalReplay(replay, _, sAuth);

        results.FetchString(1, replay.username, MAX_NAME_LENGTH);

        if(!gSM_Replays.ContainsKey(replay.sAuth))
        {
            gI_NumReplays++;
        }

        gSM_Replays.SetArray(replay.sAuth, replay, sizeof(replay));

        PrintDebug("[%s]'s PersonalReplay (%d)", replay.username, replay.auth);
    }

    delete results;
}

public int ReplayList_MenuHandler(Menu menu, MenuAction action, int param1, int param2)
{
    switch(action)
    {
        case MenuAction_Select:
        {
            char sAuth[64];
            if(menu.GetItem(param2, sAuth, sizeof(sAuth)))
            {
                StartPersonalReplay(param1, sAuth);
            }
        }

        case MenuAction_End:
        {
            delete menu;
        }
    }

    return 0;
}

public Action Shavit_OnCheckpointMenuMade(int client, bool segmented, Menu menu)
{
    if(segmented)
    {
        menu.AddItem("preview", "Preview");
    }

    return Plugin_Continue;
}

public Action Shavit_OnCheckpointMenuSelect(int client, int param2, char[] info, int maxlength, int currentCheckpoint, int maxCPs, int owner)
{
    if(StrEqual(info, "preview"))
    {
        Preview(client);
    }

    return Plugin_Continue;
}

public Action Command_Preview(int client, int args)
{
    if(!IsValidClient(client) || IsFakeClient(client))
    {
        return Plugin_Handled;
    }

    Preview(client);

    return Plugin_Handled;
}

void Preview(int client)
{
    frame_cache_t frames;

    if(!GetClientFrameCache(client, frames))
    {
        Shavit_PrintToChat(client, "Failed to get current frame cache!");
        return;
    }

    int bot = Shavit_StartReplayFromFrameCache(Shavit_GetBhopStyle(client), Shavit_GetClientTrack(client), -1.0, client, -1, Replay_Dynamic, true, frames);

    if(bot == 0)
    {
        Shavit_PrintToChat(client, "Failed to start preview!");
    }
}

bool GetClientFrameCache(int client, frame_cache_t frames)
{
    ArrayList aFrames = Shavit_GetReplayData(client);
    frames.aFrames = view_as<ArrayList>(CloneHandle(aFrames));

    frames.fTime = Shavit_GetClientTime(client);
    frames.bNewFormat = true;
    frames.iPreFrames = Shavit_GetPlayerPreFrames(client);
    frames.iPostFrames = 0;
    frames.iFrameCount = aFrames.Length - frames.iPreFrames;
    frames.fTickrate = (1.0 / GetTickInterval());
    frames.iSteamID = GetSteamAccountID(client);
    frames.iReplayVersion = REPLAY_FORMAT_SUBVERSION;

    char name[MAX_NAME_LENGTH];
    FormatEx(name, sizeof(name), "[Preview] %N", client);

    strcopy(frames.sReplayName, MAX_NAME_LENGTH, name);

    return true;
}

public Action Command_ReloadReplays(int client, int args)
{
    GetReplayList();

    return Plugin_Handled;
}

public Action Command_MyReplay(int client, int args)
{
    if(!IsValidClient(client))
    {
        return Plugin_Handled;
    }

    if(!CreateMyReplayMenu(client))
    {
        LogError("[MyReplay] Failed to create menu!");
    }

    return Plugin_Handled;
}

bool CreateMyReplayMenu(int client)
{
    Menu menu = new Menu(MyReplay_MenuHandler);
    menu.SetTitle("MyReplay Settings:\n");

    menu.AddItem("enabled", gB_ShowMenu[client] ? "[X] Enabled" : "[ ] Enabled");
    menu.AddItem("-1", "", ITEMDRAW_SPACER);

    menu.AddItem("watch", "Watch Replay");
    menu.AddItem("delete", "Delete Replay");
    menu.AddItem("-1", "", ITEMDRAW_SPACER);

    menu.AddItem("autosave", gB_AutoSave[client] ? "[X] Auto Save" : "[ ] Auto Save");
    menu.AddItem("autowatch", gB_AutoWatch[client] ? "[X] Auto Watch" : "[ ] Auto Watch", (gB_AutoSave[client] ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED));

    return menu.Display(client, MENU_TIME_FOREVER);
}

public int MyReplay_MenuHandler(Menu menu, MenuAction action, int param1, int param2)
{
    switch(action)
    {
        case MenuAction_Select:
        {
            char info[64];
            menu.GetItem(param2, info, sizeof(info));

            if(StrEqual(info, "enabled"))
            {
                gB_ShowMenu[param1] = !gB_ShowMenu[param1];
                gC_ShowMenuCookie.Set(param1, gB_ShowMenu[param1] ? "1" : "0");
            }
            else if(StrEqual(info, "watch"))
            {
                char sAuth[64];
                if(GetClientAccountID(param1, sAuth, sizeof(sAuth)))
                {
                    StartPersonalReplay(param1, sAuth);
                }
            }
            else if(StrEqual(info, "delete"))
            {
                Menu subMenu = new Menu(DeleteConfirm_MenuHandler);
                subMenu.SetTitle("Delete personal replay?\n");
                subMenu.ExitBackButton = true;

                for(int i = 1; i <= GetRandomInt(1, 4); i++)
                {
                    subMenu.AddItem("-1", "NO!");
                }

                subMenu.AddItem("1", "YES! DELETE PERSONAL REPLAY!");

                for(int i = 1; i <= GetRandomInt(1, 3); i++)
                {
                    subMenu.AddItem("-1", "NO!");
                }

                subMenu.Display(param1, 300);
            }
            else if(StrEqual(info, "autosave"))
            {
                gB_AutoSave[param1] = !gB_AutoSave[param1];
                gC_AutoSaveCookie.Set(param1, gB_AutoSave[param1] ? "1" : "0");
            }
            else if(StrEqual(info, "autowatch"))
            {
                gB_AutoWatch[param1] = !gB_AutoWatch[param1];
                gC_AutoWatchCookie.Set(param1, gB_AutoWatch[param1] ? "1" : "0");
            }

            if(!StrEqual(info, "delete"))
            {
                CreateMyReplayMenu(param1);
            }
        }

        case MenuAction_Cancel:
        {
            if(param2 == MenuCancel_ExitBack)
            {
                delete menu;
            }
        }
    }

    return 0;
}

public int DeleteConfirm_MenuHandler(Menu menu, MenuAction action, int param1, int param2)
{
    switch(action)
    {
        case MenuAction_Select:
        {
            char info[64];
            menu.GetItem(param2, info, sizeof(info));

            int choice = StringToInt(info);

            if(choice != -1)
            {
                if(!DeletePersonalReplay(param1))
                {
                    PrintDebug("Deleting personal replay failed.");
                }
            }

            CreateMyReplayMenu(param1);
        }

        case MenuAction_Cancel:
        {
            if(param2 == MenuCancel_ExitBack)
            {
                CreateMyReplayMenu(param1);
                delete menu;
            }
        }
    }

    return 0;
}

public Action Command_Debug(int client, int args)
{
    gB_Debug = !gB_Debug;
    ReplyToCommand(client, "Debug Mode: %s", gB_Debug ? "Enabled" : "Disabled");

    return Plugin_Handled;
}

stock void PrintDebug(const char[] message, any ...)
{
    if(!gB_Debug)
    {
        return;
    }

    char buffer[255];
    VFormat(buffer, sizeof(buffer), message, 2);

    if(strlen(buffer) >= 255)
    {
        PrintToServer(buffer);
    }

    for(int client = 1; client <= MaxClients; client++)
    {
        if(IsClientConnected(client) && CheckCommandAccess(client, "sm_myreplay_debug", ADMFLAG_ROOT))
        {
            if(strlen(buffer) >= 255)
            {
                PrintToConsole(client, buffer);
            }
            else
            {
                PrintToChat(client, buffer);
            }
        }
    }
}

public int Native_GetPersonalReplay(Handle handler, int numParams)
{
    if(GetNativeCell(3) != sizeof(PersonalReplay))
    {
        return ThrowNativeError(200, "PersonalReplay does not match latest(got %i expected %i). Please update your includes and recompile your plugins",
            GetNativeCell(3), sizeof(PersonalReplay));
    }

    PersonalReplay replay;
    GetPersonalReplay(replay, GetNativeCell(1));

    return SetNativeArray(2, replay, sizeof(replay));
}