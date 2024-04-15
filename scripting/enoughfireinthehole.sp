#pragma semicolon 1

#define PLUGIN_AUTHOR "no"
#define PLUGIN_VERSION "⌐■_■"

#include <sourcemod>
#include <sdktools>
#include <cstrike>

ConVar g_hCvarEnoughFireInTheHole = null;
bool g_bEnoughFireInTheHole = false;

public Plugin myinfo = 
{
	name = "ENOUGH Fire in the Hole!",
	author = PLUGIN_AUTHOR,
	description = "",
	version = PLUGIN_VERSION,
	url = ""
};

public void OnPluginStart()
{
	g_hCvarEnoughFireInTheHole = CreateConVar("enough_fire_in_the_hole", "0", "Enough FIRE IN TEH HOLE", FCVAR_NONE, true, 0.0, true, 1.0);
	
	if(g_hCvarEnoughFireInTheHole != null)
	{
		g_hCvarEnoughFireInTheHole.AddChangeHook(EnoughFireInTheHole);
	}
	
	
	
	//AddNormalSoundHook(NormalSoundHook);
	UserMsg umRadioText = GetUserMessageId("RadioText");
	if (umRadioText != INVALID_MESSAGE_ID)
	{
		HookUserMessage(umRadioText, OnRadioText, true);
	}
	umRadioText = GetUserMessageId("SendAudio");
	if (umRadioText != INVALID_MESSAGE_ID)
	{
		HookUserMessage(umRadioText, OnSendAudio, true);
	}
	
}

public void OnConfigsExecuted()
{
	g_bEnoughFireInTheHole = g_hCvarEnoughFireInTheHole.BoolValue;
}

public void EnoughFireInTheHole(ConVar convar, char[] oldValue, char[] newValue)
{
	g_bEnoughFireInTheHole = g_hCvarEnoughFireInTheHole.BoolValue;
}

public Action OnRadioText(UserMsg msg_id, BfRead msg, const int[] players, int playersNum, bool reliable, bool init)
{
	if (!g_bEnoughFireInTheHole)
		return Plugin_Continue;
		
	char buffer[256];
	msg.ReadString(buffer, sizeof(buffer));
	msg.ReadString(buffer, sizeof(buffer));
	msg.ReadString(buffer, sizeof(buffer));
	msg.ReadString(buffer, sizeof(buffer));

	if (StrContains(buffer, "Fire_in_the_hole", false) != -1)
		return Plugin_Handled;

	return Plugin_Continue;
}

public Action OnSendAudio(UserMsg msg_id, BfRead msg, const int[] players, int playersNum, bool reliable, bool init)
{
	if (!g_bEnoughFireInTheHole)
		return Plugin_Continue;
	
	char buffer[256];
	msg.ReadString(buffer, sizeof(buffer));
	if (StrEqual("Radio.FireInTheHole", buffer))
		return Plugin_Handled;
		
	return Plugin_Continue;
}