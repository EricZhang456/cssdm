#include <sourcemod>
#include <cssdm>

Engine iEngine = Engine_Unknown;
public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	iEngine = GetEngineVersion();
	
	if(iEngine != Engine_CSGO && iEngine != Engine_CSS)
	{
		strcopy(error, err_max, "This plugin is only supported on CS");
		return APLRes_Failure;
	}
	return APLRes_Success;
}
public void OnPluginStart()
{
	if(iEngine == Engine_CSS) //Only care about CS:S for this
	{
		HookEvent("player_blind", Event_PlayerBlind, EventHookMode_Post);
	}
}
public Event_PlayerBlind(Event event, const char[] name, bool dontBroadcast)
{
	if(!DM_IsFFAEnabled())
		return;

	int userid = event.GetInt("userid");
	int client = GetClientOfUserId(userid);
	
	if(IsValidClient(client))
	{
		float fDuration = GetEntPropFloat(client, Prop_Send, "m_flFlashDuration");
		CreateTimer(fDuration, Timer_FlashEnd, userid, TIMER_FLAG_NO_MAPCHANGE);
	}
}
public Action Timer_FlashEnd(Handle timer, int userid)
{
	if(!DM_IsFFAEnabled())
		return;

	int client = GetClientOfUserId(userid);
	
	if(IsValidCLient(client))
	{
		HideRadar(client);
	}
		
	return Plugin_Stop;
}
public void DM_OnClientPostSpawned(int client)
{
	//DM checks everything already just hide it
	HideRadar(client);
}
//Private functions
void HideRadar(int client)
{
	if(!DM_IsFFAEnabled())
		return;

	if(iEngine == Engine_CSGO)
	{
		SetEntProp(client, Prop_Send, "m_iHideHUD", (1 << 12));
	}
	else
	{
		//Credit to GoD-Tony for his method of hiding radar in CS:S
		SetEntPropFloat(client, Prop_Send, "m_flFlashDuration", 3600.0);
		SetEntPropFloat(client, Prop_Send, "m_flFlashMaxAlpha", 0.5);
	}
}
bool IsValidClient(int client)
{
	if(client >= 1 && client <= MaxClients && IsClientInGame(client) && GetClientTeam(client) > 1)
		return true;

	return false;
}
