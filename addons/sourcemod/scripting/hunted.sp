/*
-----------------------------------------------------------------------------
THE HUNTED MOD - SOURCEMOD PLUGIN
-----------------------------------------------------------------------------
Code Written By msleeper (c) 2008
Visit http://www.msleeper.com/ for more info!
-----------------------------------------------------------------------------
This plugin was written with the intent of returning "Hunted" style gameplay
back into TF2. The "VIP Escort" game mode was removed likely for the same
reason that Robin Walker states in the TF2 commentary that the Commander
class was removed - The game can become frankly unenjoyable if the Blue
Bodyguard team is skilled but has a terrible Hunted, or vice versa. While
I do take Mr. Walker's noble advice into consideration, I know there are a
large number of players who are unhappy with our "replacement" Hunted game
mode, Payload. While Payload is very very fun, it's no Hunted!

Please visit http://www.msleeper.com/ for any questions, or for a live
server running the latest Hunted Mod visit http://www.f7lans.com/. As
always, the best place to get recent news and information regarding this
plugin as at the AlliedModders forums, http://forums.alliedmods.net/

Thank you and enjoy!
- msleeper
-----------------------------------------------------------------------------
Version History

-- 1.0.0 (7/2/08)
 . Initial release!

-- 1.1.0 (7/15/08)
 . Fixing "Victory/Loss" sound bug where the victory sound is not played sometimes.
 . Fixing "No Engineer" bug from instantly selecting a new Hunted instead of waiting 20 seconds.
 . Fixing Hunted self death respawn, so that the Hunted suiciding or falling from a great height will not cause everyone to respawn.
 . Fixing respawn when a new Hunted is selected, and removed respawn if the Hunted is switched.
 . Limiting Pyros on RED. This can either be a straight cap or a percentage of the team.

-- 1.1.1 (7/15/08)
 . Fixed stupid error in the Pyro limiter, and made it more strict.

-- 1.2.0 (7/29/08)
 . Fixed a few more exploits.
 . Fixed crashing bugs, debug errors, and optimized code overall.
 . Adding in some rotation methods. The Hunted will now automatically change at the beginning of a new round.
 . Changed all text messages for phrases/translation support.
 . Added German translation, thank you gH0sTy!
 . Added French translation, thank you Jérémie!
 . Added in a team balancer that favors Blue, so that the Bodyguards always have the extra man.

-- 1.2.1 (8/12/08)
 . Fixed a crashing bug when a new Hunted was chosen randomly.
 . Fixed a bug where no Hunted would be selected at end of round.
 . Fixed a crashing bug with the Team Balancer.
 . Made the Pyro limiter require a minimum number of players when used in "percent" mode.

-- 1.2.2 (7/20/15)
 . Fixed all the TFClassType problems

-----------------------------------------------------------------------------
*/

/*
 * Updated by El Diablo of War3Evo.info
 *
 * 21 Jul 2014
 *
 * Our community wanted this mod resurrected.
 *
 *
*/

#pragma semicolon 1

//ignore these comments below,
//its for another mod that I work on.
//#include <switchgamemode>
//#assert GGAMETYPE == 0

#include <sourcemod>
#include <sdktools>
#include <tf2_stocks>

//
// Global definitions
//

// Plugin version
#define PLUGIN_VERSION  "1.2.2"

/*
enum TFClassType
{
	TFClass_Unknown = 0,
	TFClass_Scout,
	TFClass_Sniper,
	TFClass_Soldier,
	TFClass_DemoMan,
	TFClass_Medic,
	TFClass_Heavy,
	TFClass_Pyro,
	TFClass_Spy,
	TFClass_Engineer
};
*/

// Class that is used as the Hunted, default is Engineer.
// To best replicate Hunted gameplay, do not use a class that is
// playable by either the Bodyguards or the Assassians.

#define HUNTED_CLASS    TFClass_Engineer // TF2_ENGINEER

// Assassin kill score amounts, unused right now as personal scoring is broken
// const AssassinKillHunted = 10;
// const AssassinKillHuntedAssist = 5;

// Other global variable inits
new CurrentHunted = -1;             // ClientID of the current Hunted
new PreviousHunted = -1;            // ClientID of the previous Hunted, used for anti-grief checks
new bool:IsPluginEnabled = true;
new bool:IsHuntedDead = false;
new bool:IsHuntedOnCap = false;
new bool:NewHuntedOnWarning = false;
new HuntedCapPoint = -1;

// CVars
new Handle:cvarEnabled;
new Handle:cvarPyroMode;
new Handle:cvarMaxPyros;

// Plugin Info
public Plugin:myinfo =
{
	name = "The Hunted Gameplay Mod",
	author = "msleeper",
	description = "The Hunted gameplay modification for TF2",
	version = PLUGIN_VERSION,
	url = "http://www.msleeper.com/"
};

// Main plugin init - here we go!
public OnPluginStart()
{
	CreateConVar("sm_hunted_version", PLUGIN_VERSION, "The Hunted Gameplay Mod Version", FCVAR_PLUGIN|FCVAR_SPONLY|FCVAR_REPLICATED|FCVAR_NOTIFY);

	cvarEnabled = CreateConVar("sm_hunted_enable", "1", "Enable/Disable the Hunted plugin", FCVAR_PLUGIN, true, 0.0, true, 1.0);
	cvarPyroMode = CreateConVar("sm_hunted_pyromode", "1", "Cap Pyros by amount (0) or percentage (1)", FCVAR_PLUGIN, true, 0.0, true, 1.0);
	cvarMaxPyros = CreateConVar("sm_hunted_maxpyros", "3", "Max Pyro count or percentage (3 = 30%)", FCVAR_PLUGIN, true, 0.0, true, 10.0);

	LoadTranslations("common.phrases");
	LoadTranslations("hunted.phrases");

	//PrecacheSound("misc/your_team_won.mp3", true);
	//PrecacheSound("misc/your_team_lost.mp3", true);

	HookEvent("controlpoint_starttouch", event_CPStartTouch);
	HookEvent("controlpoint_endtouch", event_CPEndTouch);
	HookEvent("teamplay_round_start", event_RoundStart);
	HookEvent("player_spawn", event_PlayerRespawn);
	HookEvent("player_changeclass", event_ChangeClass);
	HookEvent("player_death", event_PlayerDeath);
	// HookEvent("player_chargedeployed", event_PlayerDeployUber);

	HookConVarChange(cvarEnabled, CheckHuntedEnabled);

	RegConsoleCmd("equip", cmd_Equip);
	// RegConsoleCmd("say", cmd_VoteHunted);

	RegAdminCmd("sm_hunted_reset", cmd_ResetHunted, ADMFLAG_KICK, "Force all players to respawn");
	RegAdminCmd("sm_hunted_force", cmd_ForceHunted, ADMFLAG_KICK, "Select a random new Hunted, and force all players to respawn");
	RegAdminCmd("sm_hunted_set", cmd_SetPlayerHunted, ADMFLAG_KICK, "Select a new Hunted by name|ClientID");

	CreateTimer(10.0, timer_NoHuntedWarning, INVALID_HANDLE, TIMER_REPEAT);
	CreateTimer(0.1, timer_HuntedItemStrip, INVALID_HANDLE, TIMER_REPEAT);
}

/* The Hunted seemed to have a bug where it didn't reset the cart when someone
 * won a round.   I am not completely sure if it was suppose to be like
 * that or not.  So, I've added what I believe is a fix.
 *
 *
 * End's the current round, allows specifying the winning
 * team and more.
 * This function currently works in TF2 only (it uses the game_round_win entity).
 *
 * @param team			The winning Team, pass 0 for Sudden Death mode (no winning team)
 * @param forceMapReset If to force the map to reset during the force respawn after the round is over.
 * @param switchTeams	If to switch the teams when the game is going to be reset.
 * @return				True on success, false otherwise
 */
stock bool:Game_EndRound(team=0, bool:forceMapReset=false, bool:switchTeams=false)
{
	new game_round_win = FindEntityByClassname(-1, "game_round_win");

	if (game_round_win == -1) {
		game_round_win = CreateEntityByName("game_end");

		if (game_round_win == -1) {
			ThrowError("Unable to find or create entity \"game_round_win\"");
		}
	}

	DispatchKeyValue(game_round_win, "TeamNum"			, (team			? "true" : "false"));
	DispatchKeyValue(game_round_win, "force_map_reset"	, (forceMapReset? "true" : "false"));
	DispatchKeyValue(game_round_win, "switch_teams"		, (switchTeams	? "true" : "false"));

	return AcceptEntityInput(game_round_win, "RoundWin");
}


// Probably not necessary but better safe than sorry
public OnPluginEnd()
{
	CurrentHunted = -1;
	PreviousHunted = -1;
}

// When a new map is started and ended, the current and previous Hunted
// IDs are cleared out, so that the server does not get put into an
// endless loop or, more likely, disallow any Blue from going Hunted because
// the plugin thinks there already is one.
//
// Note in the MasterCheckPlayer function it allows a player to switch to
// the Hunted class if CurrentHunted = -1 or = 0, this is because for some
// unexplored reason the CurrentHunted gets changed to 0 during map change.
// This is probably due to the GetRandomHunted coming up with no response,
// and this may require further investigation in the future.

public OnMapStart()
{
	CurrentHunted = -1;
	PreviousHunted = -1;

	//PrecacheSound("misc/your_team_won.mp3", true);
	//PrecacheSound("misc/your_team_lost.mp3", true);
}

public OnMapEnd()
{
	CurrentHunted = -1;
	PreviousHunted = -1;
}

public CheckHuntedEnabled(Handle:convar, const String:oldValue[], const String:newValue[])
{
	if (StringToInt(newValue) == 1)
	{
		PrintToChatAll("[HUNTED] %T", "HuntedActivated", LANG_SERVER);
		GetRandomHunted();
		RespawnPlayers();
	}
	else
	{
		PrintToChatAll("[HUNTED] %T", "HuntedDeactivated", LANG_SERVER);
		CurrentHunted = -1;
		PreviousHunted = -1;
		RespawnPlayers();
	}
}

// ADMIN FUNCTION - Respawn all players
public Action:cmd_ResetHunted(client, args)
{
	RespawnPlayers();
	return Plugin_Handled;
}

// ADMIN FUNCTION - Force reset of all players, and choose a random Hunted
public Action:cmd_ForceHunted(client, args)
{
	GetRandomHunted();
	RespawnPlayers();

	PrintToChatAll("[HUNTED] %T", "NewHunted", LANG_SERVER);
	PrintToConsole(client, "[HUNTED] %t", "NewHunted");
	return Plugin_Handled;
}

// ADMIN FUNCTION - Force a given player to be the Hunted
public Action:cmd_SetPlayerHunted(client, args)
{
	new String:arg1[32];
	GetCmdArg(1, arg1, sizeof(arg1));

	new target = FindTarget(client, arg1);
	if (target == -1)
		return Plugin_Handled;

	PreviousHunted = CurrentHunted;
	CurrentHunted = target;
	ChangeClientTeam(CurrentHunted, 3);
	SetPlayerClass(CurrentHunted, HUNTED_CLASS);
	RespawnPlayers();

	new String:name[MAX_NAME_LENGTH];
	GetClientName(CurrentHunted, name, sizeof(name));

	PrintToChatAll("[HUNTED] %T", "PlayerNewHunted", LANG_SERVER, name);
	PrintToConsole(client, "[HUNTED] %t", "PlayerNewHunted", name);
	return Plugin_Handled;
}

// Hooks resupply and ammo pickup, so that the Hunted can be stripped.
public Action:cmd_Equip(client, args)
{
	if (!GetConVarInt(cvarEnabled) || !IsPluginEnabled)
		return;

	if (client == CurrentHunted)
		CreateTimer(0.5, timer_HuntedChangeWeapons);
}

// Remove all weapons and metal from the Hunted
public Action:timer_HuntedItemStrip(Handle:timer)
{
	if (!GetConVarInt(cvarEnabled) || !IsPluginEnabled)
		return;

	if (!IsPlayerHunted(CurrentHunted) || GetClientCount() == 0)
		return;

	for (new i = 0; i <= 5; i++)
	{
		if (i == 2)
			continue;

		TF2_RemoveWeaponSlot(CurrentHunted, i);
	}

	SetEntData(CurrentHunted, FindSendPropInfo("CTFPlayer", "m_iAmmo") + ((3)*4), 0);
}

// Forces the Hunted to change weapons, so they do not go into Civilian mode
public Action:timer_HuntedChangeWeapons(Handle:timer)
{
	if (!GetConVarInt(cvarEnabled) || !IsPluginEnabled)
		return;

	if (!IsPlayerHunted(CurrentHunted))
		return;

	ClientCommand(CurrentHunted, "slot2");
	ClientCommand(CurrentHunted, "slot3");
}

// Checks to see if the Hunted left the server, and if so it prompts
// for a new Hunted.

public OnClientDisconnect(client)
{
	if (CurrentHunted == client)
	{
		CurrentHunted = -1;
		NewHuntedOnWarning = false;
	}
}

// Randomly selects a new Hunted from the Blue team.
public GetRandomHunted()
{
	new maxplayers = GetMaxClients();

	decl Bodyguards[maxplayers];
	new team;
	new index = 0;

	if (GetClientCount() == 0 || GetTeamClientCount(3) < 2)
	{
		NewHuntedOnWarning = false;
		return;
	}

	for (new i = 1; i <= maxplayers; i++)
	{
		if (IsClientConnected(i) && IsClientInGame(i))
		{
			team = GetClientTeam(i);
			if (team == 3 && i != CurrentHunted)
			{
				Bodyguards[index] = i;
				index++;
			}
		}
	}

	new rand = GetRandomInt(0, index - 1);
	if (Bodyguards[rand] < 1 || !IsClientConnected(Bodyguards[rand]) || !IsClientInGame(Bodyguards[rand]))
	{
		NewHuntedOnWarning = false;
		return;
	}
	else
	{
		PreviousHunted = CurrentHunted;
		CurrentHunted = Bodyguards[rand];
		ChangeClientTeam(CurrentHunted, 3);
		SetPlayerClass(CurrentHunted, HUNTED_CLASS);
	}
}

// Timer that checks to see if there is currently no Hunted, and
// displays pop-up messages to the Blue team that someone needs
// to switch to the Hunted. After 20 seconds it picks one randomly.

public Action:timer_NoHuntedWarning(Handle:timer)
{
	if (!GetConVarInt(cvarEnabled) || !IsPluginEnabled)
		return;

	if (IsPlayerHunted(CurrentHunted))
		return;

	if (GetClientCount() == 0 || GetTeamClientCount(3) < 2)
		return;

	new String:Message[256];

	if (!NewHuntedOnWarning)
	{
		Format(Message, sizeof(Message), "%T", "NoHuntedWarning", LANG_SERVER);
		DisplayText(Message, "3");
		HuntedHintText(Message, 3);
		NewHuntedOnWarning = true;
	}
	else
	{
		GetRandomHunted();
		Format(Message, sizeof(Message), "%T", "NewHunted", LANG_SERVER);
		DisplayText(Message, "3");
		HuntedHintText(Message, 3);
		NewHuntedOnWarning = false;
	}
}

public Action:event_ChangeClass(Handle:event, const String:name[], bool:dontBroadcast)
{
	if (!GetConVarInt(cvarEnabled) || !IsPluginEnabled)
		return;

	new client = GetClientOfUserId(GetEventInt(event, "userid"));
	new TFClassType:class = TFClassType:GetEventInt(event, "class");

	if (client == CurrentHunted && class != HUNTED_CLASS)
	{
		PreviousHunted = CurrentHunted;
		CurrentHunted = -1;
		NewHuntedOnWarning = false;
	}

	if (client == CurrentHunted)
		CreateTimer(0.5, timer_HuntedChangeWeapons);
}

public Action:event_RoundStart(Handle:event, const String:name[], bool:dontBroadcast)
{
	if (!GetConVarInt(cvarEnabled) || !IsPluginEnabled)
		return;

	if (GetClientCount() == 0)
		return;

	GetRandomHunted();
	RespawnPlayers();

	new String:Message[256];
	Format(Message, sizeof(Message), "%T", "NewHunted", LANG_SERVER);
	DisplayText(Message, "3");
	HuntedHintText(Message, 3);
}

// Checks to see if the Hunted has died, and if so it announces the killer,
// sets everyone to respawn when the Hunted does, and gives the Assassins
// a team point. I am considering adding a psuedo-Humiliation mode here,
// but right now I don't want to have it.
//
// Removed player respawning if the killer is the Hunted or Worldspawn,
// IE suicide, falling from a ledge, etc. This prevents people from spamming
// "Hunted Change" to grief, and to fix the exploit of changing Hunteds right
// before setup ends, allowing Blue easier capping of the first point on multi
// stage maps like Dustbowl.

public Action:event_PlayerDeath(Handle:event, const String:name[], bool:dontBroadcast)
{
	if (!GetConVarInt(cvarEnabled) || !IsPluginEnabled)
		return;

	new client = GetClientOfUserId(GetEventInt(event, "userid"));
	new Killer = GetClientOfUserId(GetEventInt(event, "attacker"));
	new Assister = GetClientOfUserId(GetEventInt(event, "assister"));

	new String:Message[256];

	if (CurrentHunted == client)
	{
		if (Killer == 0 || Killer == CurrentHunted)
		{
			Format(Message, sizeof(Message), "%T", "HuntedDied", LANG_SERVER);
			DisplayText(Message, "3");
			HuntedHintText(Message, 3);

			if (!IsPlayerHunted(CurrentHunted))
			{
				PreviousHunted = CurrentHunted;
				CurrentHunted = -1;
			}
		}
		else
		{
			new String:KillerName[256];
			GetClientName(Killer, KillerName, sizeof(KillerName));

			IsHuntedDead = true;
			NewHuntedOnWarning = false;

			// Update the Assassins's score.
			// Thanks to berni for making this update properly!

			new Score = GetTeamScore(2);
			Score += 1;
			SetTeamScore(2, Score);
			// ChangeEdictState(CTeam); // Maybe not berni. :(

			if (Assister == 0)
				Format(Message, sizeof(Message), "%T", "KilledHunted", LANG_SERVER, KillerName);
			else
			{
				new String:AssisterName[256];
				GetClientName(Assister, AssisterName, sizeof(AssisterName));

				Format(Message, sizeof(Message), "%T", "KilledHuntedAssist", LANG_SERVER, KillerName, AssisterName);
			}

			DisplayText(Message, "0");
			PrintHintTextToAll(Message);

			new maxplayers = GetMaxClients();
			//new team;

			Game_EndRound(GetClientTeam(Killer),true,true);
			ServerCommand("mp_restartgame 10");

			for (new i = 1; i <= maxplayers; i++)
			{
				if (IsClientConnected(i) && IsClientInGame(i))
				{
					//team = GetClientTeam(i);
					//if (team == 2)
					  //  EmitSoundToClient(i, "misc/your_team_won.mp3");
					//if (team == 3)
					  //  EmitSoundToClient(i, "misc/your_team_lost.mp3");
				}
			}
		}

		NewHuntedOnWarning = false;
	}
}

// Checks to see if 1.) the Hunted has died, and 2.) if the Hunted respawns
// it forces all players to respawn. It also does another MasterPlayerCheck
// to make sure nobody has tried to pull any shenanigans for changing class.

public Action:event_PlayerRespawn(Handle:event, const String:name[], bool:dontBroadcast)
{
	if (!GetConVarInt(cvarEnabled) || !IsPluginEnabled)
		return;

	new client = GetClientOfUserId(GetEventInt(event, "userid"));

	if (!IsClientConnected(client) && !IsClientInGame(client))
		return;

	if (CurrentHunted == client && IsHuntedDead)
	{
		RespawnPlayers();
		IsHuntedDead = false;
		CreateTimer(0.5, timer_HuntedChangeWeapons);
	}

	if (client == CurrentHunted && !IsPlayerHunted(CurrentHunted))
	{
		PreviousHunted = CurrentHunted;
		CurrentHunted = -1;
		NewHuntedOnWarning = false;
	}

	MasterCheckPlayer(client);
}

// Respawns all players, except the Hunted. The Hunted is not respawned because
// it throws the plugin into an endless loop. This is used when the Hunted
// respawns normally, so there is no real need to respawn him again.

public RespawnPlayers()
{
	if (GetClientCount() < 1)
		return;

	new maxplayers = GetMaxClients();

	for (new i = 1; i <= maxplayers; i++)
	{
		if (IsClientConnected(i) && IsClientInGame(i) && IsClientOnTeam(i))
		{
			if (i == CurrentHunted)
			{
				CreateTimer(0.5, timer_HuntedChangeWeapons);
				continue;
			}

			TF2_RespawnPlayer(i);
		}
	}

	new RedCount = GetTeamClientCount(2);
	new BlueCount = GetTeamClientCount(3);

	if (BlueCount < 2)
		return;

	if (RedCount > BlueCount)
	{
		decl Assassins[maxplayers];
		new index = 0;
		new team;

		for (new i = 1; i <= maxplayers; i++)
		{
			if (IsClientConnected(i) && IsClientInGame(i))
			{
				team = GetClientTeam(i);
				if (team == 2)
				{
					Assassins[index] = i;
					index += 1;
				}
			}
		}

		new rand;
		while (GetTeamClientCount(2) > GetTeamClientCount(3))
		{
			rand = GetRandomInt(0, index - 1);

			team = GetClientTeam(Assassins[rand]);
			if (team == 2 && IsClientConnected(Assassins[rand]) && IsClientInGame(Assassins[rand]) && IsClientOnTeam(Assassins[rand]))
			{
				ChangeClientTeam(Assassins[rand], 3);
				TF2_RespawnPlayer(Assassins[rand]);
				PrintToChat(Assassins[rand], "[HUNTED] %t", "TeamBalanced");
			}
		}
	}
}

// Used to check if the client is on a team, and not a Spectator
public bool:IsClientOnTeam(client)
{
	if (client == -1 || client == 0)
		return false;

	if (IsClientConnected(client) && IsClientInGame(client))
	{
		new team = GetClientTeam(client);
		switch (team)
		{
			case 2:
				return true;
			case 3:
				return true;
			default:
				return false;
		}
	}

	return false;
}

// Check if the Red team can support more Pyros, used when a Red player spawns.
// Returns true if Pyro is not maxed out, false otherwise.

public bool:IsMaxPyros()
{
	new MaxPyros = GetConVarInt(cvarMaxPyros);
	new PyroMode = GetConVarInt(cvarPyroMode);
	new PyroCount = 0;

	//new maxplayers = GetMaxClients();
	for (new i = 1; i <= MaxClients; i++)
	{
		if (IsClientConnected(i) && IsClientInGame(i))
		{
			if (GetClientTeam(i) == 2 && TF2_GetPlayerClass(i) == TFClass_Pyro)
				PyroCount += 1;
		}
	}

	if (PyroMode == 0)
	{
		if (PyroCount > MaxPyros)
			return true;
		else
			return false;
	}
	else if (PyroMode == 1)
	{
		MaxPyros = RoundToCeil(FloatMul(float(GetTeamClientCount(2) * MaxPyros),0.10));
		if (MaxPyros < 1)
			MaxPyros = 0;

		if (PyroCount > MaxPyros)
			return true;
		else
			return false;
	}

	return false;
}

// This is the primary function that controls player class control and whether or
// not someone is allowed to be the Hunted. Right now the allowable classes are hard
// set here, so for future releases where customizable Bodyguard, Assassin, and
// Hunted classes are desired this section will more or less need to be rewritten.

public MasterCheckPlayer(client)
{
	if (!GetConVarInt(cvarEnabled) || !IsPluginEnabled)
		return;

	new TFClassType:class;
	new team;
	new rand;

	if (!IsPlayerHunted(CurrentHunted))
	{
		PreviousHunted = CurrentHunted;
		CurrentHunted = -1;
	}

	class = TF2_GetPlayerClass(client);
	team = GetClientTeam(client);

	switch (team)
	{
		// Assassin class assignments
		case 2:
		{
			switch (class)
			{
				case TFClass_Pyro:
				{
					if (!IsMaxPyros())
						PrintToChat(client, "[HUNTED] %t", "AssassinSpawn");
					else
					{
						ShowVGUIPanel(client, GetClientTeam(client) == 3 ? "class_blue" : "class_red");

						PrintCenterText(client, "Pyro Max Limit Reached!!  Pick Sniper or Spy!");

						rand = GetRandomInt(1, 2);
						if (rand == 1)
							SetPlayerClass(client, TFClass_Sniper);
						if (rand == 2)
							SetPlayerClass(client, TFClass_Spy);
					}
				}
				case TFClass_Sniper:
					PrintToChat(client, "[HUNTED] %t", "AssassinSpawn");
				case TFClass_Spy:
					PrintToChat(client, "[HUNTED] %t", "AssassinSpawn");
				default:
				{
					ShowVGUIPanel(client, GetClientTeam(client) == 3 ? "class_blue" : "class_red");

					PrintCenterText(client, "You can only pick Sniper, Spy, or Pyro!");

					rand = GetRandomInt(1, 3);
					if (rand == 1)
						SetPlayerClass(client, TFClass_Sniper);
					if (rand == 2)
						SetPlayerClass(client, TFClass_Spy);
					if (rand == 3)
						SetPlayerClass(client, TFClass_Pyro);
				}
			}
		}
		// Bodyguard / Hunted class assignements
		case 3:
		{
			switch (class)
			{
				case HUNTED_CLASS:
				{
					// Disallow the PreviousHunted to become the Hunted again for anti-grief
					if (PreviousHunted == client)
					{
						ShowVGUIPanel(client, GetClientTeam(client) == 3 ? "class_blue" : "class_red");

						rand = GetRandomInt(1, 3);
						if (rand == 1)
							SetPlayerClass(client, TFClass_Soldier);
						if (rand == 2)
							SetPlayerClass(client, TFClass_Heavy);
						if (rand == 3)
							SetPlayerClass(client, TFClass_Medic);
					}
					else if (CurrentHunted == -1 || CurrentHunted == 0 || CurrentHunted == client)
					{
						CurrentHunted = client;
						CreateTimer(0.5, timer_HuntedChangeWeapons);
						NewHuntedOnWarning = false;
						PrintToChat(client, "[HUNTED] %t", "HuntedSpawn");
					}
					else
					{
						ShowVGUIPanel(client, GetClientTeam(client) == 3 ? "class_blue" : "class_red");

						rand = GetRandomInt(1, 3);
						if (rand == 1)
							SetPlayerClass(client, TFClass_Soldier);
						if (rand == 2)
							SetPlayerClass(client, TFClass_Heavy);
						if (rand == 3)
							SetPlayerClass(client, TFClass_Medic);
					}
				}
				case TFClass_Soldier:
					PrintToChat(client, "[HUNTED] %t", "BodyguardSpawn");
				case TFClass_Medic:
					PrintToChat(client, "[HUNTED] %t", "BodyguardSpawn");
				case TFClass_Heavy:
					PrintToChat(client, "[HUNTED] %t", "BodyguardSpawn");
				default:
				{
					ShowVGUIPanel(client, GetClientTeam(client) == 3 ? "class_blue" : "class_red");

					PrintCenterText(client, "You can only pick Soldier, Heavy, or Medic!");

					rand = GetRandomInt(1, 3);
					if (rand == 1)
						SetPlayerClass(client, TFClass_Soldier);
					if (rand == 2)
						SetPlayerClass(client, TFClass_Heavy);
					if (rand == 3)
						SetPlayerClass(client, TFClass_Medic);
				}
			}
		}
		default:
			return;
	}
}

// Used to check if the client actually is the Hunted by checking Class and Team.
public bool:IsPlayerHunted(client)
{
	if (client < 1)
		return false;

	if (IsClientConnected(client) && IsClientInGame(client))
	{
		new TFClassType:class = TF2_GetPlayerClass(client);
		new team = GetClientTeam(client);

		if (class == HUNTED_CLASS && team == 3 && client == CurrentHunted)
			return true;

		return false;
	}
	else
		return false;
}

// Set's a client's class and forces them to respawn
public SetPlayerClass(client, TFClassType:class)
{
	if (!GetConVarInt(cvarEnabled) || !IsPluginEnabled)
		return;

	TF2_SetPlayerClass(client, class, false, true);
	TF2_RespawnPlayer(client);
}

// DisplayText function modified from the SM_Showtext plugin by Mammal Master.
// Used to display information about the Hunted's status or death. Since this
// is not shown if a player has Minimal HUD enabled, the HintText has also been
// used at the same time.

public Action:DisplayText(String:string[256], String:team[2])
{
	new Text = CreateEntityByName("game_text_tf");
	DispatchKeyValue(Text, "message", string);
	DispatchKeyValue(Text, "display_to_team", team);
	DispatchKeyValue(Text, "icon", "leaderboard_dominated");
	DispatchKeyValue(Text, "targetname", "game_text1");
	DispatchKeyValue(Text, "background", team);
	DispatchSpawn(Text);

	AcceptEntityInput(Text, "Display", Text, Text);

	CreateTimer(5.0, KillText, Text);
}

public Action:KillText(Handle:timer, any:ent)
{
	if (IsValidEntity(ent))
		AcceptEntityInput(ent, "kill");

	return;
}

// Send Hint text to only a certain team
public HuntedHintText(String:string[256], SendToTeam)
{
	if (!GetConVarInt(cvarEnabled) || !IsPluginEnabled)
		return;

	new maxplayers = GetMaxClients();
	new team;

	for (new i = 1; i <= maxplayers; i++)
	{
		if (IsClientConnected(i) && IsClientInGame(i))
		{
			team = GetClientTeam(i);
			if (team == SendToTeam)
				PrintHintText(i, string);
		}
	}
}

// Event for when a player leaves a Control Point area. This is used to Disable
// the Control Points when the Hunted leaves the zone.

public Action:event_CPEndTouch(Handle:event, const String:name[], bool:dontBroadcast)
{
	if (!GetConVarInt(cvarEnabled) || !IsPluginEnabled)
		return;

	new client = GetEventInt(event, "player");

	if (!IsClientConnected(client) || !IsClientInGame(client))
		return;

	new team = GetClientTeam(client);

	if (team == 3)
	{
		new TFClassType:class = TF2_GetPlayerClass(client);
		if (class == HUNTED_CLASS)
		{
			IsHuntedOnCap = false;
			HuntedCapPoint = -1;

			CreateTimer(3.0, timer_EnableCP);
			ControlCP("Disable");
		}
	}
}

// Event for when a player enters a Control Point area. This is used to Enable or
// Disable all of the control points when the Hunted is or is not in the area.
// This is a super hack but hey, it works.

public Action:event_CPStartTouch(Handle:event, const String:name[], bool:dontBroadcast)
{
	if (!GetConVarInt(cvarEnabled) || !IsPluginEnabled)
		return;

	new client = GetEventInt(event, "player");

	if (!IsClientConnected(client) || !IsClientInGame(client))
		return;

	new area = GetEventInt(event, "area");
	new team = GetClientTeam(client);

	if (team == 3)
	{
		new TFClassType:class = TF2_GetPlayerClass(client);

		if (class == HUNTED_CLASS)
		{
			IsHuntedOnCap = true;
			HuntedCapPoint = area;
			CreateTimer(0.0, timer_EnableCP);
		}
		else
		{
			if (area == HuntedCapPoint)
			{
				if (!IsHuntedOnCap)
				{
					CreateTimer(3.0, timer_EnableCP);
					CreateTimer(0.0, timer_DisableCP);
				}
			}
			else
			{
				IsHuntedOnCap = false;
				CreateTimer(3.0, timer_EnableCP);
				CreateTimer(0.0, timer_DisableCP);
			}
		}
	}
}

// Enable all Control Points after a given time.
public Action:timer_EnableCP(Handle:timer)
{
	ControlCP("Enable");
}

// Disable all Control Points after a given time, if the Hunted is not
// within a Capture zone. The reason for the Timer on this is because
// there was a bug that arose that would not properly allow the capture
// point to be triggered if there were too many Blue members on it at once.

public Action:timer_DisableCP(Handle:timer)
{
	if (!IsHuntedOnCap)
		ControlCP("Disable");
}

// Loop through all possible trigger_capture_area entities in the map and
// Enable or Disable them. This assumes there are no more than 16 possible
// capture zones in a map - it WILL error in some unknown way if this plugin
// is played on a map with more!

public ControlCP(String:input[])
{
	if (!GetConVarInt(cvarEnabled) || !IsPluginEnabled)
		return;

	new i = -1;
	new CP = 0;

	for (new n = 0; n <= 16; n++)
	{
		CP = FindEntityByClassname(i, "trigger_capture_area");
		if (IsValidEntity(CP))
		{
			AcceptEntityInput(CP, input);
			i = CP;
		}
		else
			break;
	}
}
