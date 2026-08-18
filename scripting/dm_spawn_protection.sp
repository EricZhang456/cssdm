/**
 * dm_spawn_protection.sp
 * Adds spawn protection to CS:S DM.
 * This file is part of CS:S DM, Copyright (C) 2005-2007 AlliedModders LLC
 * by David "BAILOPAN" Anderson, http://www.bailopan.net/cssdm/
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License
 * as published by the Free Software Foundation; either version 2
 * of the License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.
 *
 * Version: $Id$
 */

#pragma semicolon 1
#include <sourcemod>
#include <sdktools>
#include <cssdm>

#define K_RENDER_NORMAL			0
#define K_RENDER_TRANS_COLOR	1

/* Plugin stuff */
ConVar g_ProtVar;
ConVar g_TColorVar;
ConVar g_CTColorVar;
ConVar g_ProtTimeVar;
int g_NormColor[4] = {255, 255, 255, 255};
int g_TColor[4] = {255, 0, 0, 128};
int g_CTColor[4] = {0, 0, 255, 128};
int g_HealthOffset;
int g_RenderModeOffset;
int g_RenderClrOffset;

/* Player stuff */
Handle g_PlayerTimers[MAXPLAYERS+1];
int g_PlayerHealth[MAXPLAYERS+1];

/** PUBLIC INFO */
public Plugin myinfo =
{
	name = "CS:S DM Spawn Protection",
	author = "AlliedModders LLC",
	description = "Spawn protection for CS:S DM",
	version = CSSDM_VERSION,
	url = "http://www.bailopan.net/cssdm/"
};

public void OnPluginStart()
{
	g_ProtVar = CreateConVar("cssdm_spawn_protection", "1", "Sets whether spawn protection is enabled");
	g_CTColorVar = CreateConVar("cssdm_prot_ctcolor", "0 0 255 128", "Sets the spawn color of CTs");
	g_TColorVar = CreateConVar("cssdm_prot_tcolor", "255 0 0 128", "Sets the spawn color of Ts");
	g_ProtTimeVar = CreateConVar("cssdm_prot_time", "2", "Sets time in seconds players are protected for");

	g_CTColorVar.AddChangeHook(OnColorChange);
	g_TColorVar.AddChangeHook(OnColorChange);

	g_HealthOffset = FindSendPropInfo("CCSPlayer", "m_iHealth");
	g_RenderModeOffset = FindSendPropInfo("CCSPlayer", "m_nRenderMode");
	g_RenderClrOffset = FindSendPropInfo("CCSPlayer", "m_clrRender");
}

public void OnColorChange(ConVar convar, const char[] oldValue, const char[] newValue)
{
	char colors[4][12];
	int clr[4];
	int num_strings = ExplodeString(newValue, " ", colors, 4, 12);

	for (int i=0; i<num_strings; i++)
	{
		clr[i] = StringToInt(colors[i]);
	}

	if (convar == g_CTColorVar)
	{
		g_CTColor = clr;
	} else if (convar == g_TColorVar) {
		g_TColor = clr;
	}
}

public void OnClientDisconnect(int client)
{
	if (g_PlayerTimers[client] != INVALID_HANDLE)
	{
		delete g_PlayerTimers[client];
		g_PlayerTimers[client] = INVALID_HANDLE;
	}
}

public Action DM_OnClientDeath(int client)
{
	if (g_PlayerTimers[client] != INVALID_HANDLE)
	{
		delete g_PlayerTimers[client];
		g_PlayerTimers[client] = INVALID_HANDLE;
	}

	return Plugin_Continue;
}

public Action StopProtection(Handle timer, int client)
{
	g_PlayerTimers[client] = INVALID_HANDLE;

	SetEntData(client, g_HealthOffset, g_PlayerHealth[client]);
	UTIL_Render(client, g_NormColor);

	return Plugin_Stop;
}

public void DM_OnClientPostSpawned(int client)
{
	if (!g_ProtVar.BoolValue
		|| !IsClientInGame(client)
		|| g_PlayerTimers[client] != INVALID_HANDLE)
	{
		return;
	}

	g_PlayerTimers[client] = CreateTimer(g_ProtTimeVar.FloatValue, StopProtection, client);

	/* Start protection */
	g_PlayerHealth[client] = GetEntData(client, g_HealthOffset);
	SetEntData(client, g_HealthOffset, 1012);	/* This overflows to show "500" */

	int team = GetClientTeam(client);
	if (team == CSSDM_TEAM_T)
	{
		UTIL_Render(client, g_TColor);
	} else if (team == CSSDM_TEAM_CT) {
		UTIL_Render(client, g_CTColor);
	}
}

void UTIL_Render(int client, const int color[4])
{
	int mode = (color[3] == 255) ? K_RENDER_NORMAL : K_RENDER_TRANS_COLOR;

	SetEntData(client, g_RenderModeOffset, mode, 1);
	SetEntDataArray(client, g_RenderClrOffset, color, 4, 1);
	ChangeEdictState(client);
}
