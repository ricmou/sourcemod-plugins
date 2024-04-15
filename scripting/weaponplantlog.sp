#pragma semicolon 1

#define PLUGIN_AUTHOR "Someone"
#define PLUGIN_VERSION "beta 5"

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>

enum DropInfo
{
	weaponbool,
	userid,
	Float:timestamp,
	String:plantername[64]
}

#pragma newdecls required

bool bLateLoad;

int g_iEntIdx[2048][DropInfo];
int g_iDelay;
int g_iFreezeTime;
int g_iRoundTime;

float g_fRoundStartTime;

ConVar g_cFreezeTime;
ConVar g_cRoundTime;
ConVar g_cDelay;

public Plugin myinfo = 
{
	name = "Weapon Plant Log",
	author = PLUGIN_AUTHOR,
	description = "uh, no one reads this",
	version = PLUGIN_VERSION,
	url = "www.videogames.com"
};

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	bLateLoad = late;
	return APLRes_Success;
}

public void OnPluginStart()
{
	HookEvent("round_start", Event_RoundStart, EventHookMode_PostNoCopy);
	
	g_cFreezeTime = FindConVar("mp_freezetime");
	g_cRoundTime = FindConVar("mp_roundtime");
	
	g_cDelay = CreateConVar("sm_gunplant_delay", "5", "Number of seconds before considering the weapon to not be planted.");
	
	if (bLateLoad)
	{
		for (int i = 1; i <= MaxClients; i++) {
			if (IsClientConnected(i) && IsClientInGame(i)) {
				OnClientPutInServer(i);
			}
		}
	}
	
	if (g_cDelay != null)
		g_cDelay.AddChangeHook(OnConVarChanged);
	
	if (g_cFreezeTime != null)
		g_cFreezeTime.AddChangeHook(OnConVarChanged);
	
	if (g_cRoundTime != null)
		g_cRoundTime.AddChangeHook(OnConVarChanged);
}

public void OnConfigsExecuted()
{
	g_iFreezeTime = GetConVarInt(g_cFreezeTime);
	g_iRoundTime = GetConVarInt(g_cRoundTime);
	g_iDelay = GetConVarInt(g_cDelay);
}

public void OnClientPutInServer(int client)
{
	SDKHook(client, SDKHook_WeaponDropPost, Hook_WeaponDropPost);
	SDKHook(client, SDKHook_WeaponEquipPost, Hook_WeaponEquipPost);
}



public void OnConVarChanged(ConVar convar, char[] oldValue, char[] newValue)
{
	g_iFreezeTime = GetConVarInt(g_cFreezeTime);
	g_iRoundTime = GetConVarInt(g_cRoundTime);
	g_iDelay = GetConVarInt(g_cDelay);
}

//Events

public void Event_RoundStart(Handle event, char[] name, bool dontBroadcast)
{
	g_fRoundStartTime = GetGameTime();
}

public void OnEntityDestroyed(int index)
{
	if (index > MaxClients && index < 2048)
	{
		if (g_iEntIdx[index][weaponbool] == 1)
			g_iEntIdx[index][weaponbool] = 0;
	}
}

//SDKHooks

public void Hook_WeaponDropPost(int client, int index)
{
	if (client && IsClientInGame(client) && IsClientConnected(client) && IsPlayerAlive(client) && GetClientTeam(client) == 3)
	{
		if (IsValidEdict(index))
		{
			if (g_iEntIdx[index][weaponbool] == 0)
			{
				g_iEntIdx[index][weaponbool] = 1;
				g_iEntIdx[index][userid] = GetClientUserId(client);
				g_iEntIdx[index][timestamp] = GetGameTime();
				char buffer[64];
				GetClientName(client, buffer, sizeof(buffer));
				Format(g_iEntIdx[index][plantername], 64, buffer);
			}
		}
	}
}
				
public void Hook_WeaponEquipPost(int client, int index)
{
	if (IsValidEdict(index))
	{
		switch (GetClientTeam(client))
		{
			case 2:
			{
				char weapon_name[64];
				GetEdictClassname(index, weapon_name, sizeof(weapon_name));
				if (StrContains(weapon_name, "weapon_", false) != -1)
				{
					if (StrEqual(weapon_name, "weapon_hegrenade") || StrEqual(weapon_name, "weapon_flashbang") || StrEqual(weapon_name, "weapon_smokegrenade") || StrEqual(weapon_name, "weapon_knife"))
						return;
					else
					{
						int dropperindex = GetClientOfUserId(g_iEntIdx[index][userid]);
						if (g_iEntIdx[index][weaponbool] == 1 && 
						(g_iEntIdx[index][timestamp] - g_fRoundStartTime) > 0 && 
						(g_iEntIdx[index][timestamp] + g_iDelay) > GetGameTime())
						{
							g_iEntIdx[index][weaponbool] = 0;
							if ((dropperindex && IsPlayerAlive(dropperindex)) || !dropperindex)
								LogPlant(client, dropperindex, weapon_name, g_iEntIdx[index][plantername]);
								
						}
					}
				}
			}
			case 3:
			{
				g_iEntIdx[index][weaponbool] = 0;
			}
		}
	}
}

//Logging

public void LogPlant(int client, int planter, char[] weapon_name,  char[] pname)
{
	char RoundTime[16];
	CalculateRoundTime(RoundTime, sizeof(RoundTime));
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientConnected(i) && IsClientInGame(i))
		{
			if (GetUserFlagBits(i) & ADMFLAG_GENERIC || GetUserFlagBits(i) & ADMFLAG_ROOT)
			{
				if (planter)
				PrintToConsole(i, "[Gunplant Log] %s is suspected of gunplanting a %s for %N. Roundtime: %s.", pname, weapon_name, client, RoundTime);
				
				else
				PrintToConsole(i, "[Gunplant Log] %s (left the game) is suspected of gunplanting a %s for %N. Roundtime: %s.", pname, weapon_name, client, RoundTime);
			}
		}
	}
	LogMessage("%s is suspected of gunplanting a %s on %N. Roundtime: %s.", pname, weapon_name, client, RoundTime);
}
			
void CalculateRoundTime(char[] buffer, int maxlen)
{
	int t = (RoundToFloor(GetGameTime() - g_fRoundStartTime) - g_iFreezeTime + 60);
	int m;
	
	if (t >= 60)
	{
		m = RoundToFloor(t / 60.0);
		t = t % 60;
	}
	
	t = 60 - t;
	m = g_iRoundTime - m;
	
	if (t % 60 == 0)
		m++;
	
	if (m < 0)
	{
		m = 0;
		t = 0;
	}
	Format(buffer, maxlen, "%i:%02i", m, t % 60);
}