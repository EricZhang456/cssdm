/**
 * dm_bot_quotas.sp
 * Adds bot quota correction to CS:S DM.
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


#include <sourcemod>
#include <cssdm>

public Plugin myinfo =
{
	name = "CS:S DM Bot Quotas",
	author = "AlliedModders LLC",
	description = "Bot Quota Correction for CS:S DM",
	version = CSSDM_VERSION,
	url = "http://www.bailopan.net/cssdm/"
}

/* CS:S ConVars */
ConVar BotQuota;

/* Our ConVars */
ConVar BalanceAmt;

public void OnPluginStart()
{
	/* Find CS:S ConVars */
	BotQuota = FindConVar("bot_quota");

	/* Create our ConVars */
	BalanceAmt = CreateConVar("cssdm_bots_balance", "0", "Minimum number of players (bot_quota)");
	BalanceAmt.AddChangeHook(OnBalanceChange);
}

public void OnMapStart()
{
	BalanceBots(BalanceAmt.IntValue);
}

public void OnBalanceChange(ConVar convar, const char[] oldval, const char[] newval)
{
	BalanceBots(StringToInt(newval));
}

void BalanceBots(int quota)
{
	if (!quota)
	{
		return;
	}

	int humans, bots;

	/* Get the number of valid humans and bots */
	for (int i=1; i<=MaxClients; i++)
	{
		if (!IsClientInGame(i))
		{
			continue;
		}
		if (!IsFakeClient(i))
		{
			humans++;
		} else {
			bots++;
		}
	}

	/* Get the number of bots needed to fill quota */
	if (quota < humans)
	{
		quota = 0;
	} else {
		quota -= humans;
	}

	/* Now, set the new value */
	BotQuota.IntValue = quota;
}

public void OnClientPutInServer(int client)
{
	BalanceBots(BalanceAmt.IntValue);
}

public void OnClientDisconnect_Post(int client)
{
	BalanceBots(BalanceAmt.IntValue);
}
