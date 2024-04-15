#include <sourcemod>
#include <scp>

public Plugin myinfo = 
{
	name = "Tags",
	author = "Someone",
	description = "Saves text & color",
	version = "3.1.0",
	url = ""
}

#define MAXTAGSIZE 20
#define VIPFLAG ADMFLAG_RESERVATION

Handle g_hDatabase = INVALID_HANDLE;
int g_iChatColor[MAXPLAYERS+1];
int g_iNameColor[MAXPLAYERS+1];

char g_colortags[][] = {"{white}", "{darkred}", "{teamcolor}", "{green}", "{lightgreen}", "{lime}", "{red}", "{gray}", "{yellow}", "{clearblue}", "{lightblue}", "{blue}", "{cleargray}", "{purple}", "{darkorange}", "{orange}"};
char g_colors[][] = {"\x01", "\x02", "\x03", "\x04", "\x05", "\x06", "\x07", "\x08", "\x09", "\x0A", "\x0B", "\x0C", "\x0D", "\x0E", "\x0F", "\x10"};
char g_colornames[][] = { "White/None", "Dark Red", "Teamcolor", "Green", "Light Green", "Lime", "Red", "Gray", "Yellow", "Clear Blue", "Light Blue", "Blue", "Clear Gray", "Purple", "Dark Orange", "Orange" };
char g_tags[MAXPLAYERS+1][MAXTAGSIZE];


public void OnPluginStart()
{
	LoadTranslations("common.phrases");
	SQL_TConnect(OnSQLConnect, "tags");
	
	RegAdminCmd("sm_chatcolor", Command_ColorsMenu, VIPFLAG, "Brings up the colors menu");
	RegAdminCmd("sm_chatcolors", Command_ColorsMenu, VIPFLAG, "Brings up the colors menu");
	RegAdminCmd("sm_colors", Command_ColorsMenu, VIPFLAG, "Brings up the colors menu");
	RegAdminCmd("sm_namecolors", Command_NameColorsMenu, VIPFLAG, "Set name color");
	RegAdminCmd("sm_namecolor", Command_NameColorsMenu, VIPFLAG, "Set name color");
	RegAdminCmd("sm_settag", Command_SetTag, VIPFLAG, "Set tag");
	RegAdminCmd("sm_colortags", Command_ColorTags, VIPFLAG, "Displays all available color tags");

	for (new i = 1; i < MAXPLAYERS+1; i++)
	{
		g_iChatColor[i] = 0;
		g_iNameColor[i] = 2;
	}
}

public void OnClientPostAdminCheck(int client)
{
	if (!IsFakeClient(client))
	{
		char query[512];
		char steamid[32];
		GetClientAuthId(client, AuthId_Steam2, steamid, sizeof(steamid));
		Format(query, sizeof(query), "SELECT * FROM csgo_tagsncolors WHERE steamid='%s';", steamid);
		
		Handle result = SQL_Query(g_hDatabase, query);
		if (result == INVALID_HANDLE)
		{
			SetFailState("[Tags] Lost connection to database. Reconnecting on map change.");
		}
		else
		{
			if (SQL_MoreRows(result))
			{
				if (SQL_FetchRow(result))
				{
					g_iChatColor[client] = SQL_FetchInt(result, 1);
					SQL_FetchString(result, 2, g_tags[client], MAXTAGSIZE);
					g_iNameColor[client] = SQL_FetchInt(result, 3);
				}
			}
			else
			{
				g_tags[client][0] = '\0';
				g_iChatColor[client] = 0;
				g_iNameColor[client] = 2;
			}
			CloseHandle(result);
		}
	}
}

public Action Command_SetTag(int client, int args)
{
	if (client == 0)
		return Plugin_Handled;
	
	if (!args)
	{
		ReplyToCommand(client, " \x06[Unloze] \x01Check console for output");
		PrintSetTagInfo(client);
		return Plugin_Handled;
	}
		
	char argument[128];
	bool isEmpty = false;
	GetCmdArgString(argument, sizeof(argument));
	
	if (StrContains(argument, "%s", false) > -1)
		ReplaceString(argument, sizeof(argument), "%s", "", false);
	
	if (StrEqual(argument, "none", false))
	{
		Format(argument, sizeof(argument), "");
		isEmpty = true
	}
		
	else
		CFormat(argument, sizeof(argument));
		
	Format(g_tags[client], MAXTAGSIZE, "%s", argument);

	char safetag[2 * MAXTAGSIZE + 1];
	char query[1024];
	char steamid[64];

	SQL_EscapeString(g_hDatabase, g_tags[client], safetag, 2 * strlen(g_tags[client]) + 1);
	GetClientAuthId(client, AuthId_Steam2, steamid, sizeof(steamid));

	Format(query, sizeof(query), "INSERT INTO csgo_tagsncolors (steamid, tag) VALUES('%s', '%s') ON DUPLICATE KEY UPDATE tag='%s';", steamid, safetag, safetag);
	SQL_Query(g_hDatabase, query);
	
	if (isEmpty)
		PrintToChat(client, " \x06[Unloze] \x01You removed your tag.");
	else
		PrintToChat(client, " \x06[Unloze] \x01Your tag was set to \"%s\x01\".", g_tags[client]);

	return Plugin_Handled;
}

public void CFormat(char[] tag, int maxlength)
{
		
	for (new i = 0; i < sizeof(g_colortags); i++)
	{
		/* If tag not found - skip */
		if (StrContains(tag, g_colortags[i], false) == -1)
			continue;
			
		else
			ReplaceString(tag, maxlength, g_colortags[i], g_colors[i], false);
	}
}

public void InvCFormat(char[] tag, int maxlength)
{
	for (new i = 0; i < sizeof(g_colors); i++)
	{
		/* If tag not found - skip */
		if (StrContains(tag, g_colors[i], false) == -1)
			continue;
			
		else
			ReplaceString(tag, maxlength, g_colors[i], g_colortags[i], false);
	}
}

void PrintSetTagInfo(int client)
{
	char currenttag[128];
	char colorbuffer[256];
	strcopy(currenttag, sizeof(currenttag), g_tags[client]);
	InvCFormat(currenttag, sizeof(currenttag));
	
	for (new i = 0; i < sizeof(g_colortags); i++)
	{
		Format(colorbuffer, sizeof(colorbuffer), "%s%s ", colorbuffer, g_colortags[i]);
	}
	
	PrintToConsole(client, "//////////////////////////////////////////////////////////////////////////");
	PrintToConsole(client, "Usage: sm_settag [arg]");
	PrintToConsole(client, "To disable the tag, type \"sm_settag none\"");
	PrintToConsole(client, " ");
	PrintToConsole(client, "Available colors: %s", colorbuffer);
	PrintToConsole(client, "Type sm_colortags to see these tags on chat");
	PrintToConsole(client, " ");
	PrintToConsole(client, "Your current tag is \"%s\"", currenttag);
	PrintToConsole(client, "//////////////////////////////////////////////////////////////////////////");
}

public Action Command_ColorTags(int client, int args)
{
	char buffer[256];
	for (new i = 0; i < sizeof(g_colors); i++)
	{
		Format(buffer, sizeof(buffer), "%s%s%s ", buffer, g_colors[i], g_colortags[i]);
	}
	PrintToChat(client, " %s", buffer);
}

public Action Command_ColorsMenu(int client, int args)
{
	if (client == 0)
		return Plugin_Handled;

	SubColorsMenu(client);
	return Plugin_Handled;
}

public Action Command_NameColorsMenu(int client, int args)
{
	if (client == 0)
		return Plugin_Handled;
	
	Menu menu = new Menu(NameColorsHandler);
	menu.SetTitle("Select a color:\n");
	for (new i = 0; i < sizeof(g_colornames); i++)
	{
		if (i == g_iNameColor[client])
		{
			char buffer[32];
			Format(buffer, sizeof(buffer), "%s (Current)", g_colornames[i]);
			menu.AddItem("", buffer, ITEMDRAW_DISABLED);
		}
		else
			menu.AddItem("", g_colornames[i]);
	}
	menu.ExitButton = true;
	menu.Display(client, MENU_TIME_FOREVER);
	return Plugin_Handled;
}

public int NameColorsHandler(Handle menu, MenuAction action, int param1, int param2)
{
	if (action == MenuAction_Select)
	{
		char info[32];
		bool found = GetMenuItem(menu, param2, info, sizeof(info));
		if (found == true)
		{
			g_iNameColor[param1] = param2;
			
			char query[512];
			char steamid[32];
			GetClientAuthId(param1, AuthId_Steam2, steamid, sizeof(steamid));
			Format(query, sizeof(query), "SELECT * FROM csgo_tagsncolors WHERE steamid='%s';", steamid);
			
			Handle result = SQL_Query(g_hDatabase, query);
			
			if (result == INVALID_HANDLE)
			{
				SetFailState("[Tags] Lost connection to database. Reconnecting on map change.");
			}
			else
			{
				if (SQL_MoreRows(result)) // if it fetches the row, they are a supporter, grab their data and load it
				{
					Format(query, sizeof(query), "UPDATE csgo_tagsncolors SET namecolor=%d WHERE steamid='%s';", g_iNameColor[param1], steamid);
					SQL_Query(g_hDatabase, query);
				}
				else // if not, add them
				{
					Format(query, sizeof(query), "INSERT INTO csgo_tagsncolors (steamid, namecolor) VALUES('%s', %d);", steamid, g_iNameColor[param1]);
					SQL_Query(g_hDatabase, query);
				}
				CloseHandle(result);
			}
			
			PrintToChat(param1, " \x06[Unloze] \x01Your name color was set to %s%s\x01.", g_colors[g_iNameColor[param1]], g_colornames[g_iNameColor[param1]]);
		}
	}
	else if (action == MenuAction_End)
	{
		delete menu;
	}
}

public void SubColorsMenu(int client)
{
	Menu menu = new Menu(SubColorsHandler);
	menu.SetTitle("Select a color:\n");
	for (new i = 0; i < sizeof(g_colornames); i++)
	{
		if (i == g_iChatColor[client])
		{
			char buffer[32];
			Format(buffer, sizeof(buffer), "%s (Current)", g_colornames[i]);
			menu.AddItem("", buffer, ITEMDRAW_DISABLED);
		}
		else
			menu.AddItem("", g_colornames[i]);
	}
	menu.ExitButton = true;
	menu.Display(client, MENU_TIME_FOREVER);
}

public int SubColorsHandler(Handle menu, MenuAction action, int param1, int param2)
{
	if (action == MenuAction_Select)
	{
		char info[32];
		bool found = GetMenuItem(menu, param2, info, sizeof(info));
		if (found == true)
		{
			g_iChatColor[param1] = param2;
			
			char query[512];
			char steamid[32];
			GetClientAuthId(param1, AuthId_Steam2, steamid, sizeof(steamid));
			Format(query, sizeof(query), "SELECT * FROM csgo_tagsncolors WHERE steamid='%s';", steamid);
			
			Handle result = SQL_Query(g_hDatabase, query);
			
			if (result == INVALID_HANDLE)
			{
				SetFailState("[Tags] Lost connection to database. Reconnecting on map change.");
			}
			else
			{
				if (SQL_MoreRows(result)) // if it fetches the row, they are a supporter, grab their data and load it
				{
					Format(query, sizeof(query), "UPDATE csgo_tagsncolors SET color=%d WHERE steamid='%s';", g_iChatColor[param1], steamid);
					SQL_Query(g_hDatabase, query);
				}
				else // if not, add them
				{
					Format(query, sizeof(query), "INSERT INTO csgo_tagsncolors (steamid, color) VALUES('%s', %d);", steamid, g_iChatColor[param1]);
					SQL_Query(g_hDatabase, query);
				}
				CloseHandle(result);
			}
			
			PrintToChat(param1, " \x06[Unloze] \x01Your chat color was set to %s%s\x01.", g_colors[g_iChatColor[param1]], g_colornames[g_iChatColor[param1]]);
		}
	}
	else if (action == MenuAction_End)
	{
		delete menu;
	}
}

public Action OnChatMessage(int &client, Handle recipients, char[] name, char[] message)
{
	if (!CheckCommandAccess(client, "sm_colors", VIPFLAG))
		return Plugin_Continue;
		
	char namecopy[MAX_NAME_LENGTH];
	Format(namecopy, MAX_NAME_LENGTH, "%s%s", g_colors[g_iNameColor[client]], name);
	
	if (strlen(g_tags[client]))
	{
		Format(namecopy, MAX_NAME_LENGTH, "%s%s", g_tags[client], namecopy);
	}
	
	strcopy(name, MAX_NAME_LENGTH, namecopy);

	if (g_iChatColor[client] >= 0)
	{
		char copy[MAXLENGTH_INPUT];
		copy = g_colors[g_iChatColor[client]];
		StrCat(copy, MAXLENGTH_INPUT, message);
		strcopy(message, MAXLENGTH_INPUT, copy);
	}
	
	return Plugin_Changed;
}

public void OnSQLConnect(Handle owner, Handle hndl, const char[] error, any:data)
{
	if(hndl == INVALID_HANDLE || strlen(error) > 0)
	{
		SetFailState("[Tags] Lost connection to database. Reconnecting on map change. Error: %s", error);
	}
	
	g_hDatabase = hndl;
	
	SQL_TQuery(g_hDatabase, SQL_DoNothing, "CREATE TABLE IF NOT EXISTS csgo_tagsncolors (steamid VARCHAR(32) PRIMARY KEY, color INTEGER DEFAULT '0', tag VARCHAR(32) DEFAULT '', namecolor INTEGER DEFAULT '2');");
	
	for (new i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i) && IsClientAuthorized(i))
		{
			OnClientPostAdminCheck(i);
		}
	}
}

public void SQL_DoNothing(Handle owner, Handle hndl, const char[] error, any:data)
{
	if (hndl == INVALID_HANDLE || strlen(error) > 0)
	{
		SetFailState("[Tags] Lost connection to database. Reconnecting on map change. Error: %s", error);
	}
}

