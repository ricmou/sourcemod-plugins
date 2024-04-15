#define PLUGIN_NAME           "Course Respawn Reborn"
#define PLUGIN_AUTHOR         "Someone"
#define PLUGIN_DESCRIPTION    ""
#define PLUGIN_VERSION        "1.01"
#define PLUGIN_URL            ""

#define MAXLENGTH_MESSAGE 256

#include <sourcemod>
#include <cstrike>
#include <sdktools>
#include <dhooks>
#include <AFKManager>
#undef REQUIRE_PLUGIN
#include <ctimer>

#pragma semicolon 1

enum struct EntityInfo
{
	int iEnt;
	int type;//1 - StartDisabled trigger_hurt; 2 - Enabled trigger_teleport; 3 - func_breakable; 4 - StartEnabled trigger_hurt;
	
	void resetValues()
	{
		this.iEnt = -1;
		this.type = -1;
	}
}

enum struct EntityHookInfo
{
	int hook;
	int iEnt;
	
	void resetValues()
	{
		this.hook = -1;
		this.iEnt = -1;
	}
}

//STATIC VALUES
static float DOWN_ANGLE[] = {90.0, 0.0, 0.0};

//EntityWatch
ArrayList g_EntityWatch;

//AcceptInput DHooks Handle
Handle g_acceptInput;

//CVAR HANDLES
ConVar g_hCvarTimeToRespawn;
ConVar g_hCvarEnable;
ConVar g_hCvarVerbose;

//Values
float cvarTimeToRespawn;
bool g_bAllowRespawn = false;
bool cvarEnable;
bool cvarVerbose = false;
bool g_bTimerEnabled = false;

public Plugin:myinfo =
{
	name = PLUGIN_NAME,
	author = PLUGIN_AUTHOR,
	description = PLUGIN_DESCRIPTION,
	version = PLUGIN_VERSION,
	url = PLUGIN_URL
};

public void OnPluginStart()
{
	LoadTranslations("courserespawn.phrases");
	
	//CONVAR
	CreateConVar("sm_cr_version", PLUGIN_VERSION, PLUGIN_NAME, FCVAR_NOTIFY|FCVAR_DONTRECORD);
	g_hCvarTimeToRespawn = CreateConVar("sm_cr_respawntime", "2.0", "Time to respawn the player", FCVAR_DONTRECORD);
	g_hCvarEnable = CreateConVar("sm_cr_enable", "0", "State of the plugin activity", FCVAR_DONTRECORD|FCVAR_NOTIFY);
	g_hCvarVerbose = CreateConVar("sm_cr_verbose", "0", "Enables debug mode. DO NOT ENABLE THIS UNLESS YOU KNOW WHAT YOU'RE DOING", FCVAR_DONTRECORD, true, 0.0, true, 1.0);
	
	//Hooks
	g_hCvarTimeToRespawn.AddChangeHook(CvarTimeToRespawnChanged);
	g_hCvarEnable.AddChangeHook(CvarEnableChanged);
	g_hCvarVerbose.AddChangeHook(CvarVerboseChanged);
	HookEvent("round_start", Event_RoundStart, EventHookMode_PostNoCopy);
	HookEvent("player_death", Event_PlayerDeath);
	
	//Commands
	RegConsoleCmd("sm_r", Command_Restart, "Respawns the player at will if spawning is enabled");
	RegConsoleCmd("sm_restart", Command_Restart, "Respawns the player at will if spawning is enabled");
	
	g_EntityWatch = new ArrayList(2);
	
	//GAMEDATA
	Handle temp = LoadGameConfigFile("courserespawnreborn.games");
	
	if(temp == INVALID_HANDLE)
	{
		SetFailState("Gamedata file ctimer.games.txt missing/broken.");
	}

	int offset = GameConfGetOffset(temp, "AcceptInput");
	
	if(offset == -1)
	{
		SetFailState("Failed to get AcceptInput offset");
	}

	delete temp;

	g_acceptInput = DHookCreate(offset, HookType_Entity, ReturnType_Bool, ThisPointer_CBaseEntity, AcceptInput);
	DHookAddParam(g_acceptInput, HookParamType_CharPtr);
	DHookAddParam(g_acceptInput, HookParamType_CBaseEntity);
	DHookAddParam(g_acceptInput, HookParamType_CBaseEntity);
	DHookAddParam(g_acceptInput, HookParamType_Object, 20, DHookPass_ByVal|DHookPass_ODTOR|DHookPass_OCTOR|DHookPass_OASSIGNOP); //varaint_t is a union of 12 (float[3]) plus two int type params 12 + 8 = 20
	DHookAddParam(g_acceptInput, HookParamType_Int);
}

public void OnMapStart()
{
	g_bAllowRespawn = false;
}

public void OnConfigsExecuted()
{
	///DEFAUL VALUES FOR CONVAR GLOBALS
	cvarTimeToRespawn = g_hCvarTimeToRespawn.FloatValue;
	cvarEnable = g_hCvarEnable.BoolValue;
	cvarVerbose = g_hCvarVerbose.BoolValue;
}

public void OnLibraryAdded(const char[] name)
{	
	if (StrEqual("ctimer", name))
		g_bTimerEnabled = true;
}

public void OnLibraryRemoved(const char[] name)
{
	if (StrEqual("ctimer", name))
		g_bTimerEnabled = false;
}

public void OnAllPluginsLoaded()
{
	if (LibraryExists("ctimer"))
		g_bTimerEnabled = true;
}

///CONVAR CHANGE
public void CvarTimeToRespawnChanged(ConVar cvar, char[] oldValue, char[] newValue)
{
	float fnewValue = StringToFloat(newValue);
	if (fnewValue < 0.1)
	{
		cvar.SetFloat(0.1);
		cvarTimeToRespawn = 0.1;
	}
	else
	{
		cvarTimeToRespawn = fnewValue;
	}
}

public void CvarEnableChanged(ConVar cvar, char[] oldValue, char[] newValue)
{
	int fnewValue = StringToInt(newValue);
	if (fnewValue >= 1)
	{
		cvar.SetBool(true);
		cvarEnable = true;
		g_bAllowRespawn = false;
	}
	else
	{
		cvar.SetBool(false);
		cvarEnable = false;
	}
}

public void CvarVerboseChanged(ConVar cvar, char[] oldValue, char[] newValue)
{
	int fnewValue = StringToInt(newValue);
	if (fnewValue >= 1)
	{
		cvar.SetBool(true);
		cvarVerbose = true;
	}
	else
	{
		cvar.SetBool(false);
		cvarVerbose = false;
	}
}

///EVENT CALLBACKS
public Action Command_Restart(int client, int args)
{
	if (!cvarEnable)
	{
		return Plugin_Continue;
	}

	if (!g_bAllowRespawn || !IsPlayerAlive(client) || (GetClientTeam(client) <= 1))
	{
		return Plugin_Handled;
	}
	
	if (g_bTimerEnabled)
		CTimer_Stop(client, true);
	
	Respawn(client);
	
	return Plugin_Handled;
}

public Action CS_OnTerminateRound(float &delay, CSRoundEndReason &reason)
{
	if (cvarEnable && reason == CSRoundEnd_Draw && g_bAllowRespawn)
	{
		return Plugin_Handled;
	}
	return Plugin_Continue;
}

public void Event_PlayerDeath(Handle event,char[] name,bool dontBroadcast)
{
	
	if (!cvarEnable)
	{
		return;
	}

	if (!g_bAllowRespawn)
	{
		return;
	}
	
	int victim_userid = GetEventInt(event, "userid");
	int victim = GetClientOfUserId(victim_userid);
	
	CreateTimer(cvarTimeToRespawn, RespawnClient, victim_userid);
	int timeInt = RoundFloat(cvarTimeToRespawn);
	CoursePrintToChat(victim, false, "%T", "Respawn", LANG_SERVER, timeInt);
}

public void Event_RoundStart(Handle event,char[] name,bool dontBroadcast)
{
	if (!cvarEnable)
	{
		return;
	}
	
	g_bAllowRespawn = true;
	
	//UNHOOK LAST ROUND ENTITIES
	UnhookLastRound();
	
	if (cvarVerbose)
		PrintToChatAll("[SM] Finding Spawnpoint");
	
	int spawnpoint = GetSpawnPoint();
	
	if (spawnpoint == -1) //No spawnpoint was found. Weird but not impossible.
		return;
	
	
	//Get Entity Position
	float pos[3];
	GetEntPropVector(spawnpoint, Prop_Send, "m_vecOrigin", pos);
	pos[2]+=40.0;
	
	if (cvarVerbose)
		PrintToChatAll("[SM] Finding Floor from %.2f, %.2f, %.2f", pos[0], pos[1], pos[2]);
		
	//Find floor
	TR_TraceRayFilter(pos, DOWN_ANGLE, MASK_SOLID, RayType_Infinite, TraceEntityFilter_FilterEntity);
	
	if (!TR_DidHit())//Again, weird, but theoretically not impossible.
	{	
		return;
	}
	
	//Now get the end position
	float floorPos[3];
	TR_GetEndPosition(floorPos);
	
	ArrayList entList = new ArrayList(2);
	
	
	if (cvarVerbose)
		PrintToChatAll("[SM] Get Entities");
		
	//Get all entities between the spawnpoint and the floor
	TR_EnumerateEntities(pos, floorPos, PARTITION_NON_STATIC_EDICTS, RayType_EndPoint, OnEntityHit, entList);
	
	if (entList.Length < 1)//No entities, possibly fall back to the legacy method?
	{
		if (cvarVerbose)
			PrintToChatAll("[SM] No Entities");
		return;
	}	
	//Looping done, take care of the data
	if (cvarVerbose)
		PrintToChatAll("[SM] Found %i entities!", entList.Length);
	
	for (int i = 0; i < entList.Length; i++)
	{
		EntityInfo temp;
		entList.GetArray(i, temp);
		if (cvarVerbose)
			PrintToChatAll("Ent: %i Type: %i", temp.iEnt, temp.type);
	}
	
	if (cvarVerbose)
		PrintToChatAll("[SM] Detecting SpawnKill");
	DetectSpawnkill(entList);
}

public bool OnEntityHit(int entity, ArrayList arrayValidEntities)
{
	//(Thanks mg_dr_minis_course_v5), does the entity have m_vecOrigin?
	if(!HasEntProp(entity, Prop_Send, "m_vecOrigin"))
		return true;//Doesn't, we'll move from it
	
	//Get entity classname and origin
	char classname[64];
	GetEntityClassname( entity, classname, sizeof( classname ) );
	float pos[3];
	GetEntPropVector(entity, Prop_Send, "m_vecOrigin", pos);
	
	//Run a Ray to double check if it really hits it
	TR_ClipCurrentRayToEntity(MASK_SOLID, entity);
	
	//Self Check
	if(TR_GetEntityIndex(INVALID_HANDLE) != entity)
		return true; //Maintain Execution
	
	//Filtering Block
	
	//trigger_hurt
	if( StrContains( classname, "trigger_hurt" ) > -1 )
	{
		//Found a trigger hurt, but does it start disabled?
		if (GetEntProp(entity, Prop_Data, "m_bDisabled", 1) == 1)
		{
			//Yes, so this goes to type 1;
			EntityInfo info;
			info.iEnt = entity;
			info.type = 1;
			arrayValidEntities.PushArray(info, sizeof info);
			return true;
		}
		else if (GetEntProp(entity, Prop_Data, "m_bDisabled", 1) == 0)
		{
			//No, so it falls into type 4;
			EntityInfo info;
			info.iEnt = entity;
			info.type = 4;
			arrayValidEntities.PushArray(info, sizeof info);
			return true;
		}
	}
	//trigger_teleport
	if( StrContains( classname, "trigger_teleport" ) > -1 )
	{
		//Found a trigger hurt, but does it start *enabled*?
		if (GetEntProp(entity, Prop_Data, "m_bDisabled", 1) == 0)
		{
			//Yes, goes into type 2;
			EntityInfo info;
			info.iEnt = entity;
			info.type = 2;
			arrayValidEntities.PushArray(info, sizeof info);
			return true;
		}
	}
	//func_breakable
	if( StrContains( classname, "func_breakable" ) > -1 )
	{
		//Edge case, just add to the pile as type 3
		EntityInfo info;
		info.iEnt = entity;
		info.type = 3;
		arrayValidEntities.PushArray(info, sizeof info);
		return true;
	}
	
	
	//Continue Iterating through all entites
	return true;
}

public bool TraceEntityFilter_FilterEntity(int entity, int contentsMask)
{
	return entity <= 0;
}

public int GetSpawnPoint()
{
	int spawnpoint = FindEntityByClassname(-1, "info_player_terrorist");
	if (spawnpoint == -1)
	{
		//Try CT
		spawnpoint = FindEntityByClassname(-1, "info_player_counterterrorist");
		if (spawnpoint == -1)
		{
			return -1;
		}
	}
	return spawnpoint;
}

public void DetectSpawnkill(ArrayList entList)
{
	ArrayList tempEntityInfo = new ArrayList(2);
	
	//Case 2 - Teleport Trigger that is enabled??
	
	int tempCount = FindEntitiesOfType(entList, tempEntityInfo, 2);
	bool hasTriggerTeleportHurt = false;
	
	//More than one teleport? Hmm...
	if(tempCount == 1)
	{
		if (HandleTriggerTeleport(tempEntityInfo))
		{
			//Signal that you are using at least this method.
			hasTriggerTeleportHurt = true;
			//Found a trigger_hurt after the teleport, good.
			if (cvarVerbose)
				PrintToChatAll("[SM] Method 2");
			HookEntities(tempEntityInfo);
		}
		
	}
	
	tempEntityInfo.Clear();
	
	//Case 1 - Simple Disabled Damage Trigger
	tempCount = FindEntitiesOfType(entList, tempEntityInfo, 1);
	
	if(tempCount > 0)
	{
		if (cvarVerbose)
			PrintToChatAll("[SM] Method 1");
		HookEntities(tempEntityInfo);
		return;
	}
	
	//In case method 1 doesn't have anything, but 2 did, stop execution here
	if(hasTriggerTeleportHurt)
	{
		if (cvarVerbose)
			PrintToChatAll("[SM] Method 2 execution stop");
		return;
	}
	
	tempEntityInfo.Clear();
	
	//Case 3 - func_breakable with a trigger_hurt below?
	
	tempCount = FindEntitiesOfType(entList, tempEntityInfo, 3);
	
	if(tempCount == 1)
	{
		
		//Store the func_breakable, we'll get back to it if needed
		EntityInfo filteredFuncBreakable;
		tempEntityInfo.GetArray(0, filteredFuncBreakable);
		
		tempEntityInfo.Clear();
		
		//Now find enabled trigger_hurt
		tempCount = FindEntitiesOfType(entList, tempEntityInfo, 4);
		
		if (tempCount == 1)
		{
			//Take it out of the array
			EntityInfo filteredTriggerHurt;
			tempEntityInfo.GetArray(0, filteredTriggerHurt);
			
			//Now get the positions of both
			float funcBreakablePos[3];
			float triggerHurtPos[3];
			GetEntPropVector(filteredFuncBreakable.iEnt, Prop_Send, "m_vecOrigin", funcBreakablePos);
			GetEntPropVector(filteredTriggerHurt.iEnt, Prop_Send, "m_vecOrigin", triggerHurtPos);
			
			if (funcBreakablePos[2] > triggerHurtPos[2])
			{
				tempEntityInfo.Clear();
				tempEntityInfo.PushArray(filteredFuncBreakable);
				if (cvarVerbose)
					PrintToChatAll("[SM] Method 3");
				HookEntities(tempEntityInfo);
				return;
			}
		}
		
	}

	if (cvarVerbose)
		PrintToChatAll("[SM] Failed to Achieve any method");
	
	//Couldn't find anything, maybe fall back to the casual method?
}

public int FindEntitiesOfType(ArrayList arrayValidEntities, ArrayList arrayFilteredEntities, int type)
{
	int count = 0;
	for (int i = 0; i < arrayValidEntities.Length; i++)
	{
		EntityInfo info;
		arrayValidEntities.GetArray(i, info);
		
		if (info.type == type)
		{
			arrayFilteredEntities.PushArray(info, sizeof info);
			count++;
		}
		
	}
	return count;
}

public bool HandleTriggerTeleport(ArrayList arrayFilteredEntities)
{
	char target[64];
	EntityInfo info;
	arrayFilteredEntities.GetArray(0, info);
	GetEntPropString(info.iEnt, Prop_Data, "m_target", target, sizeof target);
	
	int destEnt = -1;
	bool found = false;
	while (!found && (destEnt = FindEntityByClassname(destEnt, "info_teleport_destination")) != -1)
	{
		char entName[64];
		GetEntPropString(destEnt, Prop_Data, "m_iName", entName, sizeof entName);
		
		if (StrEqual(entName, target))
		{
			found = true;
		}
	}
	
	if(!found)//Targetname doesn't exist?
		return false;
	
    //Otherwise, we're repeating the process above
	
    //Get Entity Position
	float pos[3];
	GetEntPropVector(destEnt, Prop_Send, "m_vecOrigin", pos);
	pos[2]+=40.0;
	
	//Find floor
	TR_TraceRayFilter(pos, DOWN_ANGLE, MASK_SOLID, RayType_Infinite, TraceEntityFilter_FilterEntity);
	
	if (!TR_DidHit())//Again, weird, but theoretically not impossible.
	{
		return false;
	}
	
	//Now get the end position
	float floorPos[3];
	TR_GetEndPosition(floorPos);
	
	arrayFilteredEntities.Clear();
	
	//Get all entities between the spawnpoint and the floor
	TR_EnumerateEntities(pos, floorPos, PARTITION_NON_STATIC_EDICTS, RayType_EndPoint, OnEntityTargetHit, arrayFilteredEntities);
	
	//There is some trigger_hurt
	if (arrayFilteredEntities.Length > 0)
		return true;
	
	
	return false;
}


public bool OnEntityTargetHit(int entity, ArrayList arrayFilteredEntities)
{
	//Get entity classname and origin
	char classname[64];
	GetEntityClassname( entity, classname, sizeof( classname ) );

	//Weird edge case: Entity has no vector, disregard
	if (!HasEntProp(entity, Prop_Send, "m_vecOrigin"))
		return true;

	float pos[3];
	GetEntPropVector(entity, Prop_Send, "m_vecOrigin", pos);
	
	//Run a Ray to double check if it really hits it
	TR_ClipCurrentRayToEntity(MASK_SOLID, entity);
	
	//Self Check
	if(TR_GetEntityIndex(INVALID_HANDLE) != entity)
	return true; //Maintain Execution
	
	//Filtering Block
	
	//trigger_hurt
	if(StrContains(classname, "trigger_hurt") > -1 )
	{
		//Found a trigger hurt, but does it start disabled?
		if (GetEntProp(entity, Prop_Data, "m_bDisabled", 1) == 1)
		{
			//Yes, so this goes to type 1;
			EntityInfo info;
			info.iEnt = entity;
			info.type = 1;
			arrayFilteredEntities.PushArray(info, sizeof info);
			return true;
		}
	}
	
	//Continue Iterating through all entites
	return true;
}

public MRESReturn AcceptInput(int entity, Handle hReturn, Handle hParams)
{
	if (!cvarEnable || !g_bAllowRespawn)
	{
		return MRES_Ignored;
	}
	
	// Get args and classname
	static char command[128];
	DHookGetParamString(hParams, 1, command, sizeof(command));
	char classname[64];
	GetEntityClassname( entity, classname, sizeof( classname ) );
	
	if (cvarVerbose)
		PrintToChatAll("Ent: %i, CMD: %s, CN: %s", entity, command, classname);	
			
	if (StrEqual(command, "Enable", false) && !StrEqual(classname, "func_breakable", false))
	{
		if (cvarVerbose)
			PrintToChatAll("[SM] [WATCH] Entity %i was enabled!", entity);
		g_bAllowRespawn = false;
		CheckIsAlive();//Edge case, if all players are currently dead, restart round immediately
		CoursePrintToChat(0, true, "%T", "SpawnProtOn", LANG_SERVER);
	}
			
	else if (StrEqual(command, "Break", false) && StrEqual(classname, "func_breakable", false))
	{
		if (cvarVerbose)
			PrintToChatAll("[SM] [WATCH] Entity %i was Broken!", entity);
		g_bAllowRespawn = false;
		CheckIsAlive();//Edge case, if all players are currently dead, restart round immediately
		CoursePrintToChat(0, true, "%T", "SpawnProtOn", LANG_SERVER);
	}
	
	return MRES_Ignored;
	
}

public void HookEntities(ArrayList arrayEntList)
{
	for (int i = 0; i < arrayEntList.Length; i++)
	{
		EntityInfo temp;
		arrayEntList.GetArray(i, temp);
		
		if (HookAlreadyExists(temp.iEnt))
			return;
		
		int hook = DHookEntity(g_acceptInput, false, temp.iEnt);
		
		if (hook != -1)
		{
			if (cvarVerbose)
				PrintToChatAll("[SM] Hooking entity %i; HookID: %i", temp.iEnt, hook);
			EntityHookInfo ehi;
			ehi.hook = hook;
			ehi.iEnt = temp.iEnt;
			
			g_EntityWatch.PushArray(ehi);
		}
	}
}

public void UnhookLastRound()
{
	for (int i = 0; i < g_EntityWatch.Length; i++)
	{
		EntityHookInfo ehi;
		g_EntityWatch.GetArray(i, ehi);
		DHookRemoveHookID(ehi.hook);
	}
	
	g_EntityWatch.Clear();
	
}

public bool HookAlreadyExists(int entity)
{
	for (int i = 0; i < g_EntityWatch.Length; i++)
	{
		EntityHookInfo ehi;
		g_EntityWatch.GetArray(i, ehi);
		if (entity == ehi.iEnt)
		{
			if (cvarVerbose)
				PrintToChatAll("[SM] Entity %i already hooked!", entity);
			return true;
		}
	}
	return false;
	
}

public void CoursePrintToChat(int client, bool toall, char[] sText, any:...)
{
	int[] targets = new int[MaxClients];
	int numTargets;
	if (toall)
	{
		for (int i = 1; i <= MaxClients; i++)
		{
			if (IsClientInGame(i))
			{
				targets[numTargets] = i;
				numTargets++;
			}
		}
	}
	else
	{
		targets[0] = client;
		numTargets = 1;
	}
	
	char finalmessage[MAXLENGTH_MESSAGE], cBuffer[MAXLENGTH_MESSAGE];
	strcopy(cBuffer, sizeof(cBuffer), sText);
	VFormat(finalmessage, MAXLENGTH_MESSAGE, cBuffer, 4);
	Format(cBuffer, MAXLENGTH_MESSAGE, "%T", "Tag", LANG_SERVER);
	CFormat(finalmessage, MAXLENGTH_MESSAGE, "%s%s", cBuffer, finalmessage);
	
	SayText2(targets, numTargets, client, finalmessage);
	
}

//forums.alliedmods.net/showpost.php?p=1709517&postcount=35?p=1709517&postcount=35
public void CFormat(char[] buffer, int maxlength, char[] sText, any:...)
{
	char cBuffer[MAXLENGTH_MESSAGE];
	
	strcopy(cBuffer, sizeof(cBuffer), sText);
	VFormat(buffer, maxlength, cBuffer, 4);
	
	ReplaceString(buffer, maxlength, "{default}", "\x01", false);
	
	int iStart, iEnd, iTotal;
	char sHex[9], sCodeBefore[12], sCodeAfter[10];
	
	while ((iStart = StrContains(buffer[(iTotal)], "{#")) != -1) 
	{
	    if ((iEnd = StrContains(buffer[iTotal+iStart+2], "}")) != -1) 
	    {
	        if (iEnd == 6 || iEnd == 8) 
	        {
	            strcopy(sHex, iEnd+1, buffer[iTotal+iStart+2]);
	            Format(sCodeBefore, sizeof(sCodeBefore), "{#%s}", sHex);
	            Format(sCodeAfter, sizeof(sCodeAfter), (iEnd == 6 ? "\x07%s" : "\x08%s"), sHex);
	            ReplaceString(buffer, maxlength, sCodeBefore, sCodeAfter);
	            iTotal += iStart + iEnd + 1;
	        }
	        else {
	            iTotal += iStart + iEnd + 3;
	        }
	    }
	    else {
	        break;
	    }
	}
}

public void SayText2(int[] targets, int numTargets, int author, char[] szMessage)
{
	Handle hBuffer = StartMessage("SayText2", targets, numTargets, USERMSG_RELIABLE|USERMSG_BLOCKHOOKS);
	
	if(GetFeatureStatus(FeatureType_Native, "GetUserMessageType") == FeatureStatus_Available && GetUserMessageType() == UM_Protobuf) 
	{
		PbSetInt(hBuffer, "ent_idx", author);
		PbSetBool(hBuffer, "chat", true);
		PbSetString(hBuffer, "msg_name", szMessage);
		PbAddString(hBuffer, "params", "");
		PbAddString(hBuffer, "params", "");
		PbAddString(hBuffer, "params", "");
		PbAddString(hBuffer, "params", "");
	}
	else
	{
		BfWriteByte(hBuffer, author);
		BfWriteByte(hBuffer, true);
		BfWriteString(hBuffer, szMessage);
	}
	
	EndMessage();
}

///TIMER CALLBACK
public Action RespawnClient(Handle timer, any:userid)
{
	if (cvarEnable)
	{
		if (g_bAllowRespawn)
		{
			int client = GetClientOfUserId(userid);
			if (client && IsClientInGame(client) && (GetClientTeam(client) > 1) && !IsPlayerAlive(client))
			{
				Respawn(client);
			}
		}
	}
}

public void Respawn(int client)
{
	CS_RespawnPlayer(client);
}

public void CheckIsAlive()
{
	bool everyoneDead = true;
	bool someoneIngame = false;
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientConnected(i) && IsClientInGame(i) && (GetClientIdleTime(i) == 0))
		{
			someoneIngame = true;
			if(IsPlayerAlive(i))
				everyoneDead = false;
			
		}
	}
	
	if(everyoneDead && someoneIngame)
	{
		char delay[10];
		FindConVar("mp_round_restart_delay").GetString(delay, sizeof delay);
		CS_TerminateRound(StringToFloat(delay), CSRoundEnd_Draw, true);
	}
	
}