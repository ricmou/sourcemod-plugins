#define PLUGIN_NAME           "Elysium"
#define PLUGIN_AUTHOR         "Someone"
#define PLUGIN_DESCRIPTION    "Extends"
#define PLUGIN_VERSION        "1.0"
#define PLUGIN_URL            ""
#define TIER_COUNT			  3
#define MAXLENGTH_MESSAGE     256
#define DEFAULT_AFK			  600

#include <sourcemod>
#include <sdktools>
#include <cstrike>
#include <mapchooser>
#include <AFKManager>

#pragma semicolon 1

enum struct VoteTier{
	
	float percentage;
	int amount;
	
	void resetData(){
		this.percentage = 0.0;
		this.amount = 0;
		}
}

enum struct TimeEndNotification{
	bool minAlert;
	bool halfMinAlert;
	bool tenSecAlert;
	bool endAlert;
	
	void resetData(){
		this.minAlert = false;
		this.halfMinAlert = false;
		this.tenSecAlert = false;
		this.endAlert = false;
	}
}

ConVar g_cTier1Percentage = null;
ConVar g_cTier2Percentage = null;
ConVar g_cTier3Percentage = null;
ConVar g_cTier1Count = null;
ConVar g_cTier2Count = null;
ConVar g_cTier3Count = null;

ConVar g_cAllowExtendBeforeVote = null;
ConVar g_cExtendPeriod = null;
ConVar g_cMinNumPlayers = null;
ConVar g_cTimeToEndEnable = null;

ConVar g_cAfkMoveTime = null;

VoteTier g_voteTiers[TIER_COUNT];
TimeEndNotification g_endNotifications;

bool g_bAllowExtendBeforeVote = false;
int g_iExtendPeriod = 0;
int g_iMinNumPlayers = 0;
int g_iTimeToEndEnable = 0;

int g_iAfkMoveTime = DEFAULT_AFK;

/*--*/
bool g_bEnabled = false;
bool g_bVoted[MAXPLAYERS] = false;
int g_iExtendCount = 0;
int g_iMaxExtensions = 0;
int g_iRequiredVotes = 0;
int g_iCurrentVotes = 0;
Handle g_hTimer = null;

bool g_bGameOver = false;
Address g_pGameOver;

public Plugin:myinfo =
{
	name = PLUGIN_NAME,
	author = PLUGIN_AUTHOR,
	description = PLUGIN_DESCRIPTION,
	version = PLUGIN_VERSION,
	url = PLUGIN_URL
};

public OnPluginStart()
{
	LoadTranslations("elysium.phrases");
	
	RegConsoleCmd("sm_ve", Command_VoteExtend, "Votes to extend a map");
	RegAdminCmd("sm_eldebug", Command_GetRnd, ADMFLAG_RCON);
	RegAdminCmd("sm_elcalc", Command_ForceCalc, ADMFLAG_RCON);
	
	g_cAllowExtendBeforeVote = CreateConVar("extend_allow_before_vote", "0", "Wether or not to allow the extend voting to occur before the next map is decided", _, true, 0.0, true, 1.0);
	g_cExtendPeriod = CreateConVar("extend_period", "10", "Number of minutes a extend provides", _, true, 1.0);
	g_cMinNumPlayers = CreateConVar("extend_min_num_players", "5", "Number of players required (inclusive) until the percentage values kick in (Values below this will be considered 100%)",  _, true, 1.0);
	g_cTimeToEndEnable = CreateConVar("extend_time_to_end", "5", "Time, in minutes, until the extend function is enabled", _, true, 0.0);
	
	g_cAllowExtendBeforeVote.AddChangeHook(CvarChanged);
	g_cExtendPeriod.AddChangeHook(CvarChanged);
	g_cMinNumPlayers.AddChangeHook(CvarChanged);
	g_cTimeToEndEnable.AddChangeHook(CvarChanged);
	
	//This is awful, but I honestly cannot be bothered doing KV atm.
	
	g_cTier1Percentage = CreateConVar("extend_t1_percent", "0.80", "Percentage of players required for a extend on the first phase", _, true, 0.0, true, 1.0);
	g_cTier2Percentage = CreateConVar("extend_t2_percent", "0.85", "Percentage of players required for a extend on the second phase", _, true, 0.0, true, 1.0);
	g_cTier3Percentage = CreateConVar("extend_t3_percent", "0.90", "Percentage of players required for a extend on the third phase", _, true, 0.0, true, 1.0);
	g_cTier1Count = CreateConVar("extend_t1_amount", "2", "Amount of extends allowed on the first phase", _, true, 1.0);
	g_cTier2Count = CreateConVar("extend_t2_amount", "2", "Amount of extends allowed on the second phase", _, true, 1.0);
	g_cTier3Count = CreateConVar("extend_t3_amount", "0", "Amount of extends allowed on the third phase", _, true, 0.0);
	
	g_cAfkMoveTime = FindConVar("sm_afk_move_time");
	
	g_cTier1Percentage.AddChangeHook(CvarChanged);
	g_cTier2Percentage.AddChangeHook(CvarChanged);
	g_cTier3Percentage.AddChangeHook(CvarChanged);
	g_cTier1Count.AddChangeHook(CvarChanged);
	g_cTier2Count.AddChangeHook(CvarChanged);
	g_cTier3Count.AddChangeHook(CvarChanged);
	
	if (g_cAfkMoveTime != null)
		g_cAfkMoveTime.AddChangeHook(CvarChanged);
	
	g_hTimer = CreateTimer(1.0, TimeCheck, INVALID_HANDLE, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
	
	Handle hGameConf = LoadGameConfigFile("elysium.games");
	if(hGameConf == INVALID_HANDLE)
	{
		g_bGameOver = false;
		LogError("Couldn't load Extend.games game config! GameOver cancel disabled.");
		return;
	}

	if(!(g_pGameOver = GameConfGetAddress(hGameConf, "GameOver")))
	{
		g_bGameOver = false;
		delete hGameConf;
		LogError("Couldn't get GameOver address from game config! GameOver cancel disabled.");
		return;
	}

	g_bGameOver = true;
	delete hGameConf;
	
	AutoExecConfig(true, "elysium");
	
}

public void OnMapStart()
{
	g_hTimer = null;
	if (g_hTimer == null)
		g_hTimer = CreateTimer(1.0, TimeCheck, INVALID_HANDLE, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
		
	doToggleProcedure(false);
	g_iExtendCount = 0;
	g_iMaxExtensions = 0;
	g_iRequiredVotes = 0;
	g_iCurrentVotes = 0;
}

public void OnMapTimeLeftChanged()
{
	int time;
	GetMapTimeLimit(time);
	
	GameRules_SetProp("m_iRoundTime", time*60);
}


public void OnClientConnected(int client)
{
	if(g_bEnabled)
	{
		g_bVoted[client] = false;
		calculateRequired();
		CheckForExtend();
	}
}

public void OnClientDisconnect(int client)
{
	if (g_bEnabled)
	{
		if(g_bVoted[client] == true)
		{
			g_iCurrentVotes--;
			g_bVoted[client] = false;
		}
		calculateRequired();
		CheckForExtend();
	}
}

public void OnConfigsExecuted()
{
	updateConfigValues();
}

public void CvarChanged(ConVar cvar, char[] oldValue, char[] newValue)
{
	updateConfigValues();
}

public void updateConfigValues()
{
	g_bAllowExtendBeforeVote = g_cAllowExtendBeforeVote.BoolValue;
	g_iExtendPeriod = g_cExtendPeriod.IntValue;
	g_iMinNumPlayers = g_cMinNumPlayers.IntValue;
	g_iTimeToEndEnable = g_cTimeToEndEnable.IntValue * 60;
	
	if (g_cAfkMoveTime != null)
		g_iAfkMoveTime = g_cAfkMoveTime.IntValue;
	else
		g_iAfkMoveTime = DEFAULT_AFK;
	
	g_iMaxExtensions = 0;
	
	g_voteTiers[0].resetData();
	g_voteTiers[0].amount = g_cTier1Count.IntValue;
	g_voteTiers[0].percentage = g_cTier1Percentage.FloatValue;
	
	if (g_voteTiers[0].amount != 0)
	{
		g_iMaxExtensions += g_voteTiers[0].amount;
	}
	else
	{
		g_iMaxExtensions = -1;
	}

	g_voteTiers[1].resetData();
	g_voteTiers[1].amount = g_cTier2Count.IntValue;
	g_voteTiers[1].percentage = g_cTier2Percentage.FloatValue;
	
	if (g_voteTiers[1].amount != 0 && g_iMaxExtensions != -1)
	{
		g_iMaxExtensions += g_voteTiers[1].amount;
	}
	else
	{
		g_iMaxExtensions = -1;
	}
	
	g_voteTiers[2].resetData();
	g_voteTiers[2].amount = g_cTier3Count.IntValue;
	g_voteTiers[2].percentage = g_cTier3Percentage.FloatValue;
	
	if (g_voteTiers[2].amount != 0 && g_iMaxExtensions != -1)
	{
		g_iMaxExtensions += g_voteTiers[2].amount;
	}
	else
	{
		g_iMaxExtensions = -1;
	}	
}

public Action Command_VoteExtend(int client, int args)
{
	if(!g_bEnabled)
	{
		CoursePrintToChat(client, false, "%T", "NoVote", LANG_SERVER);
		return Plugin_Handled;
	}
	
	bool toAll = false;
	
	if(!g_bVoted[client])
	{
		g_bVoted[client] = true;
		toAll = true;
		g_iCurrentVotes++;
	}
	
	calculateRequired();
	
	char name[MAX_NAME_LENGTH];
	GetClientName(client, name, MAX_NAME_LENGTH);
	
	CoursePrintToChat(client, toAll, "%T", "YouVoted", LANG_SERVER, name, g_iCurrentVotes, g_iRequiredVotes);
	
	//PrintToChatAll("%N voted to extend. (%d/%d)", client, g_iCurrentVotes, g_iRequiredVotes);
	
	CheckForExtend();
	
	return Plugin_Handled;
}

public Action TimeCheck(Handle timer)
{
	//Get time left
	int timeLeft;
	GetMapTimeLeft(timeLeft);
	
	if (!g_bEnabled && //Currently disabled
	(g_bAllowExtendBeforeVote || HasEndOfMapVoteFinished()) && //End of map vote been done
	(g_iMaxExtensions == -1 || (g_iMaxExtensions > g_iExtendCount)) && //Not going over the maximum number of extensions?
	timeLeft <= g_iTimeToEndEnable) //Timeleft lower than the extend_time_to_end
	{
		doToggleProcedure(true);
	}
	
	if (g_bEnabled)
	{
		if (timeLeft > g_iTimeToEndEnable)
			doToggleProcedure(false);
		else
		{
			checkForAFK();
		}
			
	}
	
	if (timeLeft == -1)
		return Plugin_Continue;
	
	if (timeLeft > 60 && g_endNotifications.minAlert == true)
		g_endNotifications.resetData();
		
	if (timeLeft <= 60 && g_endNotifications.minAlert == false)
	{
		g_endNotifications.minAlert = true;
		CoursePrintToChat(0, true, "%T", "60Sec", LANG_SERVER);
	}
	
	if (timeLeft <= 30 && g_endNotifications.halfMinAlert == false)
	{
		g_endNotifications.halfMinAlert = true;
		CoursePrintToChat(0, true, "%T", "30Sec", LANG_SERVER);
	}
	
	if (timeLeft <= 10 && g_endNotifications.tenSecAlert == false)
	{
		g_endNotifications.tenSecAlert = true;
		CoursePrintToChat(0, true, "%T", "10Sec", LANG_SERVER);
	}
	
	if (timeLeft <= -2 && g_endNotifications.endAlert == false)
	{
		g_endNotifications.endAlert = true;
		char nextmap[64];
		GetNextMap(nextmap, sizeof nextmap);
		CS_TerminateRound(5.0, CSRoundEnd_Draw, true);
		CoursePrintToChat(0, true, "%T", "MapEnd", LANG_SERVER, nextmap);
	}
	
	return Plugin_Continue;
}

public void checkForAFK()
{
	bool changed = false;
	for (int i = 1; i <= MaxClients; i++)
	{
		//If no vote recorded, dont bother
		if(!g_bVoted[i])
			continue;
			
		//If it passes this check, its still valid
		if(IsClientConnected(i) && IsClientInGame(i) && !IsFakeClient(i) && (GetClientIdleTime(i) <= g_iAfkMoveTime))
			continue;
		
		//If not, likely went afk, removing the vote.
		g_bVoted[i] = false;
		changed = true;
		g_iCurrentVotes--;
	}
	
	if (changed)
	{
		calculateRequired();
		CheckForExtend();
	}
}

public void doToggleProcedure(bool state)
{
	//Bring vote count to 0
	g_iCurrentVotes = 0;
	
	//Reset everyones state
	for (int i = 1; i <= MaxClients; i++)
	{
		g_bVoted[i] = false;
	}
	
	g_bEnabled = state;
	
	//If enabling, recalculate
	if (state)
	{
		calculateRequired();
		CoursePrintToChat(0, true, "%T", "YouCanVote", LANG_SERVER);
	}
}

public Action Command_GetRnd(int client, int args)
{
	int time = GameRules_GetProp("m_iRoundTime", time);
	PrintToChat(client, "m_iRoundTime: %d", time);
	GetMapTimeLeft(time);
	int time2;
	GetMapTimeLimit(time2);
	PrintToChat(client, "GetMapTimeLeft: %d; GetMapTimeLimit: %d", time, time2);
	PrintToChat(client, "g_bEnabled: %s; g_iExtendCount: %d; g_iMaxExtensions: %d, g_iRequiredVotes: %d; g_iCurrentVotes: %d", g_bEnabled ? "true" : "false", g_iExtendCount, g_iMaxExtensions, g_iRequiredVotes, g_iCurrentVotes);
	PrintToChat(client, "1minAlert: %s; 30SecAlert: %s; 10SecAlert: %s; EndAlert: %s", g_endNotifications.minAlert ? "true" : "false", g_endNotifications.halfMinAlert ? "true" : "false", g_endNotifications.tenSecAlert ? "true" : "false", g_endNotifications.endAlert ? "true" : "false");
	return Plugin_Handled;
}

public Action Command_ForceCalc(int client, int args)
{
	calculateRequired();
}

public void calculateRequired()
{
	// This is what controls most checks, time, has the vote gone through, etcetra. If any of those are not enabled, theres little to no point to calculate.
	if (!g_bEnabled)
		return;
	
	int tier = whichTier();
	
	//This should never happen, but still.
	if (tier == -1)
	{
		g_bEnabled = false;
		return;
	}
	
	int playerCount = getValidPlayers();
	
	if(playerCount == 0)
	{
		//No one's on the server, disregard.
		return;
	}
	
	if (playerCount <= g_iMinNumPlayers)
	{
		//It's 100%, not worth doing a divison by 1.
		g_iRequiredVotes = playerCount;
		return;
	}
	
	g_iRequiredVotes = RoundToNearest(playerCount * g_voteTiers[tier].percentage);
	
}

public int whichTier()
{
	int cumulative = 0;
	
	for (int i = 0; i < TIER_COUNT; i++)
	{
		cumulative += g_voteTiers[i].amount;
		
		if (cumulative - g_iExtendCount > 0 || g_voteTiers[i].amount == 0)
		{
			return i;
		}
	}
	
	return -1;
}

public int getValidPlayers()
{
	int count = 0;
	for (int i = 1; i <= MaxClients; i++)
	{
		//PrintToChatAll("MAX: %d ;GetClientIdleTime(%d) = %d", g_iAfkMoveTime, i, GetClientIdleTime(i));
		if (IsClientConnected(i) && IsClientInGame(i) && !IsFakeClient(i) && (GetClientIdleTime(i) <= g_iAfkMoveTime))
		{
			count++;
		}
	}
	
	return count;
}

public void CheckForExtend()
{
	
	//This should never reach this code if g_bEnabled is false, but...
	if(!g_bEnabled)
		return;
	
	//Again, should be unreachable, but check if theres extends left.
	if(g_iMaxExtensions != -1 && g_iMaxExtensions <= g_iExtendCount)
		return;
	
	//If theres no players on the server...
	if(getValidPlayers() == 0)
		return;

	//Has the count reached?
	if(g_iRequiredVotes <= g_iCurrentVotes)
	{
		//Final Check
		int count = 0;
		for (int i = 1; i <= MaxClients; i++)
		{
			//PrintToChatAll("MAX: %d ;GetClientIdleTime(%d) = %d", g_iAfkMoveTime, i, GetClientIdleTime(i));
			if (IsClientConnected(i) && IsClientInGame(i) && !IsFakeClient(i) && (GetClientIdleTime(i) <= g_iAfkMoveTime) && g_bVoted[i])
			{
				count++;
			}
		}
		
		//Count went out of sync?
		if(count < g_iCurrentVotes)
		{
			//It did, snap to the current
			g_iCurrentVotes = count;
			
		}
		
		//Everything is fine? Extend.
		ExtendMapTimeLimit(g_iExtendPeriod*60);
		g_iExtendCount++;
		CancelGameOver();
		CoursePrintToChat(0, true, "%T", "VoteSuccess", LANG_SERVER, g_iExtendPeriod);
		doToggleProcedure(false);
		
	}
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

//From BotoXs extend plugin
void CancelGameOver()
{
	if (!g_bGameOver)
		return;

	StoreToAddress(g_pGameOver, 0, NumberType_Int8);

	for (int client = 1; client <= MaxClients; client++)
	{
		if (IsClientInGame(client))
		{
			if (IsClientObserver(client))
				SetEntityMoveType(client, MOVETYPE_NOCLIP);
			else
				SetEntityMoveType(client, MOVETYPE_WALK);
		}
	}
}