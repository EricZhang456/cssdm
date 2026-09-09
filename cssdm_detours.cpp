/**
 * vim: set ts=4 :
 * ===============================================================
 * CS:S DM, Copyright (C) 2004-2007 AlliedModders LLC.
 * By David "BAILOPAN" Anderson
 * All rights reserved.
 * ===============================================================
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or (at
 * your option) any later version.
 *
 * This program is distributed in the hope that it will be useful, but
 * WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; see the file COPYING; if not, write to the
 * Free Software Foundation, Inc., 51 Franklin St, Fifth Floor, Boston,
 * MA 02110-1301 USA
 *
 * Version: $Id$
 */

#include "cssdm_headers.h"
#include "cssdm_detours.h"
#include "cssdm_utils.h"
#include "cssdm_events.h"
#include <sm_platform.h>
#include "CDetour/detours.h"

CDetour *drpwpns_callback = NULL;

DETOUR_DECL_MEMBER2(DetourDrpWpns, void, bool, unknown1, bool, unknown2)
{
	OnClientDropWeapons(reinterpret_cast<CBaseEntity *>(this));
	DETOUR_MEMBER_CALL(DetourDrpWpns)(unknown1, unknown2);
}

void InitDropWeaponsDetour()
{
	drpwpns_callback = DETOUR_CREATE_MEMBER(DetourDrpWpns, "DropWeapons");
	if(drpwpns_callback)
	{
		drpwpns_callback->EnableDetour();
	}
}

void DM_InitDetours()
{
	CDetourManager::Init(g_pSM->GetScriptingEngine(), g_pDmConf);
	InitDropWeaponsDetour();
}

void DM_ShutdownDetours()
{
	if (drpwpns_callback)
	{
		drpwpns_callback->Destroy();
		drpwpns_callback = NULL;
	}
}
