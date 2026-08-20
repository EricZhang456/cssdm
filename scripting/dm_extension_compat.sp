#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <cstrike>
#include <cssdm>

//Engine Version/Native stuff
EngineVersion iEngine = Engine_Unknown;
//new bool:bGiveAmmoNative = false; //Enable when we compile against 1.6

//Forwards
GlobalForward hOnStartup;
GlobalForward hOnShutdown;
GlobalForward hOnClientSpawned;
GlobalForward hOnClientSpawnedPost;
GlobalForward hOnClientDeath;
GlobalForward hOnSetSpawnMethod;

//CVars
ConVar hVersion;
ConVar hRagdollTime;
ConVar hRespawnWait;
ConVar hAllowC4;
ConVar hEnabled;
ConVar hFFAEnabled;
ConVar hSpawnMethod;
ConVar hRemoveDrops;

//Cvar values
bool bAllowC4;

//Bools
bool bIsRunning = false;
bool bFFAEnabled = false;
bool bConfigRan = false;
bool bInRoundRestart = false;
bool bAllowFFA = false;

//Weapon Info
int iMaxWeapons;
char szWeaponNames[CSSDM_MAX_WEAPONS][64];
char szClassnames[CSSDM_MAX_WEAPONS][64];
StringMap hWeaponIDTrie;
DmWeaponType iWeaponType[CSSDM_MAX_WEAPONS];

//Timers
Handle hRespawnTimers[MAXPLAYERS+1];

//Gameconf
GameData hGameConf;

//Bomb entity
int iBombEnt = -1;

//FFA Stuff
enum OperatingSystem
{
	OperatingSystem_Windows = 0,
	OperatingSystem_Linux,
	OperatingSystem_Mac
};

OperatingSystem iOS;

enum PatchType
{
	Patch_TakeDamage1 = 0,
	Patch_TakeDamage2,
	Patch_LagComp,
	Patch_CalcDom,
	Patch_IPointsForKills,
	Patch_Max
};

enum BytesType
{
	Bytes_Patch = 0,
	Bytes_Original,
	Bytes_Max
};

#define MAX_BYTES 10
int BytePatchesArray[Patch_Max][Bytes_Max][MAX_BYTES];
Address PatchAddressArray[Patch_Max];
int PatchOffsetsArray[Patch_Max];

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	iEngine = GetEngineVersion();

	if(iEngine != Engine_CSGO && iEngine != Engine_CSS)
	{
		strcopy(error, err_max, "This plugin is only supported on CS");
		return APLRes_Failure;
	}

	hGameConf = new GameData("cssdm.games");
	if(hGameConf == INVALID_HANDLE)
	{
		strcopy(error, err_max, "Failed to load game config cssdm.games.txt");
		return APLRes_Failure;
	}

	//Prepare FFA stuff
	int offset = hGameConf.GetOffset("g_pGameRules");

	if(offset == 1)
	{
		iOS = OperatingSystem_Linux;
	}
	else
	{
		iOS = OperatingSystem_Windows;
	}

	CreateNative("DM_GetSpawnMethod", DMN_GetSpawnMethod);
	CreateNative("DM_GetWeaponID", DMN_GetWeaponID);
	CreateNative("DM_GetWeaponType", DMN_GetWeaponType);
	CreateNative("DM_StripBotItems", DMN_StripBotItems);
	CreateNative("DM_GetWeaponClassname", DMN_GetWeaponClassname);
	CreateNative("DM_GetClientWeapon", DMN_GetClientWeapon);
	CreateNative("DM_DropWeapon", DMN_DropWeapon);
	CreateNative("DM_GetWeaponName", DMN_GetWeaponName);
	CreateNative("DM_IsRunning", DMN_IsRunning);
	CreateNative("DM_GetSpawnWaitTime", DMN_GetSpawnWaitTime);
	CreateNative("DM_RespawnClient", DMN_RespawnClient);
	CreateNative("DM_IsClientAlive", DMN_IsClientAlive);
	CreateNative("DM_GiveClientAmmo", DMN_GiveAmmo);

	//New natives for 3.0
	CreateNative("DM_IsFFAEnabled", DMN_IsFFAEnabled);

	hWeaponIDTrie = new StringMap();
	if(FileExists("cfg/cssdm/cssdm.weapons.txt"))
	{
		if(!ParseWeaponConfig("cfg/cssdm/cssdm.weapons.txt"))
		{
			strcopy(error, err_max, "Failed to parse weapon config cfg/cssdm/cssdm.weapons.txt");
			return APLRes_Failure;
		}
	}
	RegPluginLibrary("dm_extension_compat");
	return APLRes_Success;
}

public void OnPluginStart()
{
	hOnStartup = CreateGlobalForward("DM_OnStartup", ET_Ignore);
	hOnShutdown = CreateGlobalForward("DM_OnShutdown", ET_Ignore);
	hOnClientSpawned = CreateGlobalForward("DM_OnClientSpawned", ET_Ignore, Param_Cell);
	hOnClientSpawnedPost = CreateGlobalForward("DM_OnClientPostSpawned", ET_Ignore, Param_Cell);
	hOnClientDeath = CreateGlobalForward("DM_OnClientDeath", ET_Ignore, Param_Cell);
	hOnSetSpawnMethod = CreateGlobalForward("DM_OnSetSpawnMethod", ET_Ignore, Param_String);

	hVersion = CreateConVar("cssdm_version", CSSDM_VERSION, "CS:S DM Version", FCVAR_REPLICATED|FCVAR_NOTIFY|FCVAR_DONTRECORD);
	hRagdollTime = CreateConVar("cssdm_ragdoll_time", "2", "Sets ragdoll stay time", _, true, 0.0, true, 20.0);
	hRespawnWait = CreateConVar("cssdm_respawn_wait", "0.75", "Sets respawn wait time");
	hAllowC4 = CreateConVar("cssdm_allow_c4", "0", "Sets whether C4 is allowed");
	hEnabled = CreateConVar("cssdm_enabled", "1", "Sets whether CS:S DM is enabled", FCVAR_REPLICATED|FCVAR_NOTIFY);
	hFFAEnabled = CreateConVar("cssdm_ffa_enabled", "0", "Sets whether Free-For-All mode is enabled", FCVAR_REPLICATED|FCVAR_NOTIFY);
	hSpawnMethod = CreateConVar("cssdm_spawn_method", "preset", "Sets how and where players are spawned");
	hRemoveDrops = CreateConVar("cssdm_remove_drops", "1", "Sets whether dropped items are removed");

	hEnabled.AddChangeHook(ChangeStatus);
	hFFAEnabled.AddChangeHook(ChangeFFAStatus);
	hSpawnMethod.AddChangeHook(ChangeSpawnStatus);
	hAllowC4.AddChangeHook(ChangeAllowC4);

	bAllowC4 = hAllowC4.BoolValue;

	bAllowFFA = PrepareFFA();

	if(!bAllowFFA)
	{
		LogError("Free-For-All will not work, Failed to get patch bytes");
	}

	AutoExecConfig(true, "cssdm", "cssdm");
	//bGiveAmmoNative = (GetFeatureStatus(FeatureType_Native, "GivePlayerAmmo") == FeatureStatus_Available)
}

public void OnClientPutInServer(int client)
{
	if(!bIsRunning)
		return;

	if(!bAllowC4)
	{
		SDKHook(client, SDKHook_WeaponCanUse, Hook_CanUse);
	}

	hRespawnTimers[client] = INVALID_HANDLE;
}

public void OnClientDisconnect(int client)
{
	KillRespawnTimer(client);
}

public void OnConfigsExecuted()
{
	iBombEnt = -1;
	bInRoundRestart = false;
	if(ParseConfigs())
	{
		if(GetConVarBool(hEnabled) && Enable())
		{
			Call_StartForward(hOnStartup);
			Call_Finish();
		}
		if(GetConVarBool(hFFAEnabled))
		{
			EnableFFA();
		}
	}
}

public void OnMapEnd()
{
	if(bConfigRan)
	{
		bConfigRan = false;
		if(bIsRunning)
		{
			Disable();
			Call_StartForward(hOnShutdown);
			Call_Finish();
		}
		if(bFFAEnabled)
		{
			DisableFFA();
		}
	}
}

public void OnEntityCreated(int entity, const char[] classname)
{
	if(StrEqual(classname, "weapon_c4"))
	{
		iBombEnt = entity;
	}
	else if(bIsRunning && (StrEqual(classname, "item_defuser") || StrEqual(classname, "item_cutters")))//CS:GO has both items, only hook if we are running
	{
		SDKHook(entity, SDKHook_SpawnPost, Hook_SpawnPost);
	}
}

public void OnEntityDestroyed(int entity)
{
	if(entity == iBombEnt)
	{
		iBombEnt = -1;
	}
}

public void OnPluginEnd()
{
	//Unpatch if we patched.
	DisableFFA();
}
public Action CS_OnCSWeaponDrop(int client, int weaponIndex, bool donated)
{
	if(hRemoveDrops.BoolValue)
	{
		AcceptEntityInput(weaponIndex, "Kill");
	}
	return Plugin_Continue;
}

public void ChangeAllowC4(ConVar convar, const char[] oldValue, const char[] newValue)
{
	bool bNewVal = hAllowC4.BoolValue;
	if(!bAllowC4 && bNewVal)
	{
		for(new i = 1; i <= MaxClients; i++)
		{
			if(IsClientInGame(i))
			{
				SDKUnhook(i, SDKHook_WeaponCanUse, Hook_CanUse);
			}
		}
	}
	else if(bAllowC4 && !bNewVal)
	{
		for(new i = 1; i <= MaxClients; i++)
		{
			if(IsClientInGame(i))
			{
				SDKHook(i, SDKHook_WeaponCanUse, Hook_CanUse);
			}
		}
	}
	bAllowC4 = bNewVal;
}

public void ChangeStatus(ConVar convar, const char[] oldValue, const char[] newValue)
{
	if(hEnabled.BoolValue)
	{
		Enable();
	}
	else
	{
		Disable();
	}
}

public void ChangeFFAStatus(ConVar convar, const char[] oldValue, const char[] newValue)
{
	if(hFFAEnabled.BoolValue)
	{
		EnableFFA();
	}
	else
	{
		DisableFFA();
	}
}

public void ChangeSpawnStatus(ConVar convar, const char[] oldValue, const char[] newValue)
{
	if(!StrEqual(oldValue, newValue))
	{
		Call_StartForward(hOnSetSpawnMethod);
		Call_PushString(newValue);
		Call_Finish();
	}
}

//Natives
public void DMN_GetSpawnMethod(Handle hPlugin, int iNumParams)
{
	char szSpawnMethod[32];
	hSpawnMethod.GetString(szSpawnMethod, sizeof(szSpawnMethod));
	SetNativeString(1, szSpawnMethod, GetNativeCell(2));
}

public int DMN_GetWeaponID(Handle hPlugin, int iNumParams)
{
	char weaponName[64];
	int id;
	GetNativeString(1, weaponName, sizeof(weaponName));
	if(hWeaponIDTrie.GetValue(weaponName, id))
	{
		return id;
	}
	return -1;
}

public DmWeaponType DMN_GetWeaponType(Handle:hPlugin, iNumParams)
{
	int id = GetNativeCell(1);
	if(id < 0 || id >= iMaxWeapons)
	{
		return ThrowNativeError(SP_ERROR_NATIVE, "Invalid CS:S DM weapon id (%d)", id);
	}
	return iWeaponType[id];
}

public void DMN_StripBotItems(Handle hPlugin, int iNumParams)
{
	static int iMyWeaponsMax = 0;

	if(!iMyWeaponsMax)
	{
		if(iEngine == Engine_CSGO)
		{
			iMyWeaponsMax = 64;
		}
		else
		{
			iMyWeaponsMax = 32;
		}
	}

	int client = GetNativeCell(1);

	if(client <= 0 || client > MaxClients)
	{
		return ThrowNativeError(SP_ERROR_NATIVE, "Invalid client index %d", client);
	}
	if(!IsClientInGame(client))
	{
		return ThrowNativeError(SP_ERROR_NATIVE, "Client %d is not in game", client);
	}
	if(!IsFakeClient(client))
	{
		return ThrowNativeError(SP_ERROR_NATIVE, "Client %d is not a bot", client);
	}

	int weapon;
	for(int x = 0; x < iMyWeaponsMax; x++)
	{
		weapon = GetEntPropEnt(client, Prop_Send, "m_hMyWeapons", x);
		if(weapon && IsValidEdict(weapon))
		{
			DM_DropWeaponRemove(client, weapon);
		}
	}
	SetEntProp(client, Prop_Send, "m_bHasDefuser", 0);
	SetEntProp(client, Prop_Send, "m_ArmorValue", 0);
	SetEntProp(client, Prop_Send, "m_bHasHelmet", 0);
}

public void DMN_GetWeaponClassname(Handle hPlugin, int iNumParams)
{
	int id = GetNativeCell(1);
	if(id < 0 || id >= iMaxWeapons)
	{
		return ThrowNativeError(SP_ERROR_NATIVE, "Invalid CS:S DM weapon id (%d)", id);
	}
	SetNativeString(2, szClassnames[id], GetNativeCell(3));
}

public int DMN_GetClientWeapon(Handle hPlugin, int iNumParams)
{
	return GetPlayerWeaponSlot(GetNativeCell(1), GetNativeCell(2));
}

public void DMN_DropWeapon(Handle hPlugin, int iNumParams)
{
	int weapon = GetNativeCell(2);
	int client = GetNativeCell(1);

	DM_DropWeaponRemove(client, weapon);
}

public void DMN_GetWeaponName(Handle hPlugin, int iNumParams)
{
	int id = GetNativeCell(1);
	if(id < 0 || id >= iMaxWeapons)
	{
		return ThrowNativeError(SP_ERROR_NATIVE, "Invalid CS:S DM weapon id (%d)", id);
	}
	SetNativeString(2, szWeaponNames[id], GetNativeCell(3));
}

public bool DMN_IsRunning(Handle hPlugin, int iNumParams)
{
	return bIsRunning;
}

public float DMN_GetSpawnWaitTime(Handle hPlugin, int iNumParams)
{
	return hRespawnWait.FloatValue;
}

public void DMN_RespawnClient(Handle hPlugin, int iNumParams)
{
	CS_RespawnPlayer(GetNativeCell(1));
}

public bool DMN_IsClientAlive(Handle hPlugin, int iNumParams)
{
	return IsPlayerAlive(GetNativeCell(1));
}

public int DMN_GiveAmmo(Handle hPlugin, int iNumParams)
{
	Handle hGiveAmmo = INVALID_HANDLE;
	StartPrepSDKCall(SDKCall_Entity);
	PrepSDKCall_SetFromConf(hGameConf, SDKConf_Virtual, "GiveAmmo");
	PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain);
	PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain);
	PrepSDKCall_AddParameter(SDKType_Bool, SDKPass_Plain);
	PrepSDKCall_SetReturnInfo(SDKType_PlainOldData, SDKPass_Plain);

	hGiveAmmo = EndPrepSDKCall();

	if(!hGiveAmmo)
	{
		ThrowNativeError(SP_ERROR_NATIVE, "Failed to create GiveAmmo SDKCall");
		return 0;
	}

	int res = SDKCall(hGiveAmmo, GetNativeCell(1), GetNativeCell(3), GetNativeCell(2), GetNativeCell(4)? true : false);

	delete hGiveAmmo;

	return res;
}

public bool DMN_IsFFAEnabled(Handle hPlugin, int iNumParams)
{
	return bFFAEnabled;
}

//Hook callbacks
public Action Hook_CanUse(int client, int weapon)
{
	if(iBombEnt == -1 || weapon != iBombEnt || bAllowC4)
	{
		return Plugin_Continue;
	}

	//Dont ever allow the bomb!
	return Plugin_Handled;
}

public void Hook_SpawnPost(int entity)
{
	//Kill defusers
	AcceptEntityInput(entity, "Kill");
}

public Action OnJoinClass(int client, const char[] command, int args)
{
	//Respawn him next frame if he hasnt already
	if(client && IsClientInGame(client))
	{
		hRespawnTimers[client] = CreateTimer(0.1, TimeRespawnPlayer, GetClientSerial(client));
	}
	return Plugin_Continue;
}

public Action Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
	if(!bIsRunning)
		return Plugin_Continue;

	int ragdoolTime = hRagdollTime.IntValue;
	int client = GetClientOfUserId(event.GetInt("userid"));

	if(client && IsClientInGame(client))
	{
		SetEntProp(client, Prop_Send, "m_bHasDefuser", 0);

		Call_StartForward(hOnClientDeath);
		Call_PushCell(client);

		Action res = Plugin_Continue;
		Call_Finish(res);

		if(ragdollTime <= 20 && ragdollTime >= 0)
		{
			int ragdoll = GetEntPropEnt(client, Prop_Send, "m_hRagdoll");

			if(ragdoll && IsValidEntity(ragdoll))
			{
				if(ragdollTime == 0)
				{
					AcceptEntityInput(ragdoll, "Kill");
				}
				else
				{
					int ref = EntIndexToEntRef(ragdoll);
					if(ref != INVALID_ENT_REFERENCE)
					{
						CreateTimer(float(ragdoolTime), TimeRagdollRemove, ref, TIMER_FLAG_NO_MAPCHANGE);
					}
				}
			}
		}

		if(res == Plugin_Continue)
		{
			hRespawnTimers[client] = CreateTimer(hRespawnWait.FloatValue, TimeRespawnPlayer, GetClientSerial(client));
		}
	}

	return Plugin_Continue;
}

public Action Event_PlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));

	if(client <= 0 || client > MaxClients || !IsClientInGame(client) || GetClientTeam(client) <= CS_TEAM_SPECTATOR)
	{
		return Plugin_Continue;
	}

	Call_StartForward(hOnClientSpawned);
	Call_PushCell(client);
	Call_Finish();
	Call_StartForward(hOnClientSpawnedPost);
	Call_PushCell(client);
	Call_Finish();

	return Plugin_Continue;
}

public Action Event_RoundStart(Event event, const char[] name, bool dontBroadcast)
{
	bInRoundRestart = false;

	return Plugin_Continue;
}

public Action Event_RoundEnd(Event event, const char[] name, bool dontBroadcast)
{
	bInRoundRestart = true;

	for(int i = 1; i <= MaxClients; i++)
	{
		KillRespawnTimer(i);
	}

	return Plugin_Continue;
}

//Timer callbacks
public Action TimeRespawnPlayer(Handle timer, int serial)
{
	int client = GetClientFromSerial(serial);

	if(client && IsClientInGame(client))
	{
		if(bIsRunning && !bInRoundRestart)
		{
			CS_RespawnPlayer(client);
		}
		if (hRespawnTimers[client])
		{
			delete hRespawnTimers[client];
		}
		hRespawnTimers[client] = INVALID_HANDLE;
	}
	return Plugin_Continue;
}

public Action TimeRagdollRemove(Handle timer, int ref)
{
	int index = EntRefToEntIndex(ref);
	if(bIsRunning && index != INVALID_ENT_REFERENCE)
	{
		AcceptEntityInput(index, "Kill");
	}
	return Plugin_Continue;
}

//Private functions

// is this even necessary?
void GetCurrentMapEx(char map[], int size)
{
	GetCurrentMap(map, size);

	int index = -1;
	int mapLen = strlen(map);
	for(int i = 0; i < mapLen; i++)
	{
		if(StrContains(map[i], "/") != -1 || StrContains(map[i], "\\") != -1)
		{
			if(i != strlen(map) - 1)
				index = i;
		}
		else
		{
			break;
		}
	}
	strcopy(map, size, map[index+1]);
}

bool ParseWeaponConfig(const char[] szWeaponCfg)
{
	static char game[32] = "";

	if(strlen(game) <= 1)
	{
		GetGameFolderName(game, sizeof(game));
	}

	KeyValues kv = new KeyValues("Weapons");

	if(!kv.ImportFromFile(szWeaponCfg))
	{
		delete kv;
		return false;
	}

	if(!kv.JumpToKey(game))
	{
		delete kv;
		return false;
	}

	if(!kv.GotoFirstSubKey())
	{
		delete kv;
		return false;
	}

	char name[64];
	char type[32];

	iMaxWeapons = 0;

	do
	{
		kv.GetSectionName(name, sizeof(name));
		StringToLower(name);
		hWeaponIDTrie.SetValue(name, iMaxWeapons);
		Format(szClassnames[iMaxWeapons], sizeof(szClassnames[]), "weapon_%s", name);
		kv.GetString("name", szWeaponNames[iMaxWeapons], sizeof(szWeaponNames[]), name);
		kv.GetString("type", type, sizeof(type), "");

		iWeaponType[iMaxWeapons] = DmWeapon_Invalid;

		if(StrEqual("primary", type))
		{
			iWeaponType[iMaxWeapons] = DmWeapon_Primary;
		}
		else if(StrEqual("secondary", type))
		{
			iWeaponType[iMaxWeapons] = DmWeapon_Secondary;
		}
		else if(StrEqual("grenade", type))
		{
			iWeaponType[iMaxWeapons] = DmWeapon_Grenade;
		}
		else if(StrEqual("c4", type))
		{
			iWeaponType[iMaxWeapons] = DmWeapon_C4;
		}

		if(iWeaponType[iMaxWeapons] != DmWeapon_Invalid)
		{
			iMaxWeapons++;
		}
		else
		{
			szClassnames[iMaxWeapons] = "";
			szWeaponNames[iMaxWeapons] = ""
			hWeaponIDTrie.Remove(name);
		}

	} while (KvGotoNextKey(kv));

	delete kv;
	return true;
}

bool ParseConfigs()
{
	if(bConfigRan)
		return true;

	//Execute the map sepcific file if it exists
	char buffer[PLATFORM_MAX_PATH];
	char map[64];

	GetCurrentMapEx(map, sizeof(map));

	Format(buffer, sizeof(buffer), "exec cssdm/maps/%s.cssdm.cfg", map);
	ServerCommand(buffer);

	bConfigRan = true;
	return true;
}

void HookEvents()
{
	HookEvent("player_death", Event_PlayerDeath);
	HookEvent("player_spawn", Event_PlayerSpawn);
	HookEvent("round_start", Event_RoundStart, EventHookMode_PostNoCopy);
	HookEvent("round_end", Event_RoundEnd, EventHookMode_PostNoCopy);
	AddCommandListener(OnJoinClass, "joinclass");

	if(!bAllowC4)
	{
		for(int i = 1; i <= MaxClients; i++)
		{
			if(IsClientInGame(i))
			{
				SDKHook(i, SDKHook_WeaponCanUse, Hook_CanUse);
			}
		}
	}
}

void UnhookEvents()
{
	UnhookEvent("player_death", Event_PlayerDeath);
	UnhookEvent("player_spawn", Event_PlayerSpawn);
	UnhookEvent("round_start", Event_RoundStart);
	UnhookEvent("round_end", Event_RoundEnd);
	RemoveCommandListener(OnJoinClass, "joinclass");

	if(!bAllowC4)
	{
		for(int i = 1; i <= MaxClients; i++)
		{
			if(IsClientInGame(i))
			{
				SDKUnhook(i, SDKHook_WeaponCanUse, Hook_CanUse);
			}
		}
	}
}

bool Enable()
{
	//Dont return true more than once since we only want the forward called once
	if(bIsRunning || !bConfigRan)
	{
		return false;
	}

	HookEvents();
	bIsRunning = true;
	return true;
}
void Disable()
{
	if(!bIsRunning)
	{
		return;
	}

	//Clear Timers
	for(int i = 1; i <= MaxClients; i++)
	{
		KillRespawnTimer(i);
	}

	UnhookEvents();
	bIsRunning = false;
}

void EnableFFA()
{
	if(!bAllowFFA || !bIsRunning || bFFAEnabled)
		return;

	for(int i = 0; i < view_as<int>(Patch_Max); i++)
	{
		if(!CheckIfShouldPatch(LoadFromAddress(PatchAddressArray[i]+view_as<Address>(PatchOffsetsArray[i]), NumberType_Int8)))
		{
			LogError("Failed to enable FFA. Failed to find valid byte to patch for PatchType (%i)", i);
			return;
		}
	}

	int byte = 0;

	for(int i = 0; i < view_as<int>(Patch_Max); i++)
	{
		byte = 0;

		if(iEngine == Engine_CSS && i == view_as<int>(Patch_TakeDamage2))
			continue;

		while(BytePatchesArray[i][Bytes_Patch][byte] != -1)
		{
			if(BytePatchesArray[i][Bytes_Original][byte] == -1)//Save the bytes if its our first time
			{
				BytePatchesArray[i][Bytes_Original][byte] = LoadFromAddress(PatchAddressArray[i]+view_as<Address>(byte+PatchOffsetsArray[i]), NumberType_Int8);
			}
			StoreToAddress(PatchAddressArray[i]+view_as<Address>(byte+PatchOffsetsArray[i]), BytePatchesArray[i][Bytes_Patch][byte], NumberType_Int8);
			byte++;
		}
	}

	bFFAEnabled = true;
}

void DisableFFA()
{
	if(!bFFAEnabled)
		return;

	int byte = 0;

	for(new i = 0; i < view_as<int>(Patch_Max); i++)
	{
		byte = 0;

		if(iEngine == Engine_CSS && i == view_as<int>(Patch_TakeDamage2))
			continue;

		while(BytePatchesArray[i][Bytes_Original][byte] != -1)
		{
			StoreToAddress(PatchAddressArray[i]+view_as<Address>(byte+PatchOffsetsArray[i]), BytePatchesArray[i][Bytes_Original][byte], NumberType_Int8);
			byte++;
		}
	}

	bFFAEnabled = false;
}

bool PrepareFFA()
{
	for(int i = 0; i < MAX_BYTES; i++)
	{
		for(int x = 0; x < view_as<int>(Patch_Max); x++)
		{
			for(int j = 0; j < view_as<int>(Bytes_Max); j++)
			{
				BytePatchesArray[x][j][i] = -1;
			}
		}
	}

	char szKey[32];
	char szTakeDmg1[32];
	char szTakeDmg2[32];
	char szCalcDom[32];
	char szLagComp[32];
	char szIPoints[32];
	char szOS[10];

	if(iOS == OperatingSystem_Linux)
	{
		strcopy(szOS, sizeof(szOS), "Linux");
	}
	else if(iOS == OperatingSystem_Mac)
	{
		strcopy(szOS, sizeof(szOS), "Mac");
	}
	else
	{
		strcopy(szOS, sizeof(szOS), "Windows");
	}


	Format(szTakeDmg1, sizeof(szTakeDmg1), "TakeDmgPatch1_%s", szOS);
	Format(szTakeDmg2, sizeof(szTakeDmg2), "TakeDmgPatch2_%s", szOS);
	Format(szCalcDom, sizeof(szCalcDom), "CalcDomRevPatch_%s", szOS);
	Format(szLagComp, sizeof(szLagComp), "LagCompPatch_%s", szOS);
	Format(szIPoints, sizeof(szIPoints), "IPointsForKillPatch_%s", szOS);

	if(!hGameConf.GetKeyValue(szTakeDmg1, szKey, sizeof(szKey)) || !GetBytes(szKey, BytePatchesArray[Patch_TakeDamage1][Bytes_Patch]))
	{
		LogError("Failed to get %s", szTakeDmg1);
		return false;
	}

	if (iEngine == Engine_CSGO)
	{
		if(!hGameConf.GetKeyValue(szTakeDmg2, szKey, sizeof(szKey)) || !GetBytes(szKey, BytePatchesArray[Patch_TakeDamage2][Bytes_Patch]))
		{
			LogError("Failed to get %s", szTakeDmg2);
			return false;
		}
	}

	if(!hGameConf.GetKeyValue(szCalcDom, szKey, sizeof(szKey)) || !GetBytes(szKey, BytePatchesArray[Patch_CalcDom][Bytes_Patch]))
	{
		LogError("Failed to get %s", szCalcDom);
		return false;
	}

	if(!hGameConf.GetKeyValue(szLagComp, szKey, sizeof(szKey)) || !GetBytes(szKey, BytePatchesArray[Patch_LagComp][Bytes_Patch]))
	{
		LogError("Failed to get %s", szLagComp);
		return false;
	}

	if(!hGameConf.GetKeyValue(szIPoints, szKey, sizeof(szKey)) || !GetBytes(szKey, BytePatchesArray[Patch_IPointsForKills][Bytes_Patch]))
	{
		LogError("Failed to get %s", szIPoints);
		return false;
	}

	if(!(PatchAddressArray[Patch_TakeDamage1] = PatchAddressArray[Patch_TakeDamage2] = hGameConf.GetAddress("TakeDamage_Addr")))
	{
		LogError("Failed to locate TakeDamage Address");
		return false;
	}
	if(!(PatchAddressArray[Patch_CalcDom] = hGameConf.GetAddress("CalcDominationAndRevenge_Addr")))
	{
		LogError("Failed to locate CalcDominationAndRevenge Address");
		return false;
	}
	if(!(PatchAddressArray[Patch_LagComp] = hGameConf.GetAddress("WantsLagComp_Addr")))
	{
		LogError("Failed to locate WantsLagComp Address");
		return false;
	}
	if(!(PatchAddressArray[Patch_IPointsForKills] = hGameConf.GetAddress("IPointsForKill_Addr")))
	{
		LogError("Failed to locate IPointsForKill Address");
		return false;
	}

	if((PatchOffsetsArray[Patch_TakeDamage1] = hGameConf.GetOffset("TakeDmgPatch1")) == -1)
	{
		LogError("Failed to locate TakeDmgPatch1 patch offset");
		return false;
	}
	if((PatchOffsetsArray[Patch_TakeDamage2] = hGameConf.GetOffset("TakeDmgPatch2")) == -1)
	{
		LogError("Failed to locate TakeDmgPatch2 patch offset");
		return false;
	}
	if((PatchOffsetsArray[Patch_LagComp] = hGameConf.GetOffset("LagCompPatch")) == -1)
	{
		LogError("Failed to locate WantsLagComp patch offset");
		return false;
	}
	if((PatchOffsetsArray[Patch_CalcDom] = hGameConf.GetOffset("CalcDomRevPatch")) == -1)
	{
		LogError("Failed to locate CalcDominationAndRevenge patch offset");
		return false;
	}
	if((PatchOffsetsArray[Patch_IPointsForKills] = hGameConf.GetOffset("IPointsForKillPatch")) == -1)
	{
		LogError("Failed to locate IPointsForKill patch offset");
		return false;
	}

	return true;
}

bool GetBytes(const char[] szBytes, int iBytes)
{
	int max = strlen(szBytes)/4;

	if(max > MAX_BYTES || max < 1)
		return false;

	int x = 0;
	for(int i = 0; i < max; i++)
	{
		if(strncmp(szBytes[i*4], "\\x90", 4) == 0)
		{
			iBytes[x] = 0x90;
		}
		else if(strncmp(szBytes[i*4], "\\xEB", 4) == 0)
		{
			iBytes[x] = 0xEB;
		}
		else if(strncmp(szBytes[i*4], "\\xE9", 4) == 0)
		{
			iBytes[x] = 0xE9;
		}
		else
		{
			return false;
		}
		x++;
	}

	return true;
}

bool CheckIfShouldPatch(int iByte)
{
	if(iByte == 0x74 || iByte == 0x75 || iByte == 0x0F)
		return true;

	return false;
}
void DM_DropWeaponRemove(int client, int weapon)
{
	CS_DropWeapon(client, weapon, true);
	AcceptEntityInput(weapon, "Kill");
}

void KillRespawnTimer(int client)
{
	if(hRespawnTimers[client])
	{
		KillTimer(hRespawnTimers[client]);
		hRespawnTimers[client] = INVALID_HANDLE;
	}
}

void StringToLower(char buffer[])
{
	int bufferLen = sizeof(buffer);
	for(int i = 0; i < bufferLen; i++)
	{
		buffer[i] = CharToLower(buffer[i]);
	}
}
