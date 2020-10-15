
#define DEBUG

#define PLUGIN_NAME           "Timescaler"
#define PLUGIN_AUTHOR         "carnifex"
#define PLUGIN_DESCRIPTION    "Scales triggers to match your timescale."
#define PLUGIN_VERSION        "0.6"
#define PLUGIN_URL            ""

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <output_info_plugin>

#pragma semicolon 1

ArrayList g_aTargetChanges[MAXPLAYERS + 1];
ArrayList g_aGravityChanges[MAXPLAYERS + 1];
bool g_bToggled[MAXPLAYERS + 1];
int g_iTick[MAXPLAYERS + 1];

enum struct target_t
{
	int iStartTick;
	char sTargetName[32];
	float fDelay;
}

enum struct gravity_t
{
	float fGravity;
	float fDelay;
	int iStartTick;
}

public Plugin myinfo =
{
	name = PLUGIN_NAME,
	author = PLUGIN_AUTHOR,
	description = PLUGIN_DESCRIPTION,
	version = PLUGIN_VERSION,
	url = PLUGIN_URL
};

public void OnPluginStart()
{
	RegConsoleCmd("sm_scalefix", Command_Toggle, "Toggle timescaling for teleport blocks");
}

public Action Command_Toggle(int client, int args)
{
	if(g_bToggled[client])
	{
		PrintToChat(client, "Timescaling fix now enabled");
		g_bToggled[client] = false;
	} else
	{
		PrintToChat(client, "Timescaling fix now disabled");
		g_bToggled[client] = true;
	}
}

public void OnClientPutInServer(int client)
{
	g_iTick[client] = 0;
	
	g_bToggled[client] = false;
	
	if(g_aTargetChanges[client] == null)
	{
		g_aTargetChanges[client] = new ArrayList(sizeof(target_t));
	} else
	{
		ClearArray(g_aTargetChanges[client]);
	}
	
	if(g_aGravityChanges[client] == null)
	{
		g_aGravityChanges[client] = new ArrayList(sizeof(gravity_t));
	} else
	{
		ClearArray(g_aGravityChanges[client]);
	}
	
	SDKHook(client, SDKHook_PreThink, Hook_PreThink);
}

public void Hook_PreThink(int client)
{
	g_iTick[client]++;
	
	//handle targetname changes
	int size = GetArraySize(g_aTargetChanges[client]);
	for(int i = 0; i < size; i++)
	{
		target_t targetChange;
		g_aTargetChanges[client].GetArray(i, targetChange);
		float tickTime = g_iTick[client] * GetTickInterval();
		float startTime = targetChange.iStartTick * GetTickInterval();
		
		float timescale = GetEntPropFloat(client, Prop_Send, "m_flLaggedMovementValue");
		
		//PrintToChat(client, "tick: %i, setting: %s", g_iTick[client], targetChange.sTargetName);
		
		if(tickTime - startTime >= (targetChange.fDelay / timescale))
		{
			SetEntPropString(client, Prop_Data, "m_iName", targetChange.sTargetName);
			
			//PrintToChat(client, "setting targentname to: %s", targetChange.sTargetName);
			
			g_aTargetChanges[client].Erase(i);
			size = size - 1;
		}
	}
	
	//handle gravity changes.
	int gravitySize = GetArraySize(g_aGravityChanges[client]);
	for(int i = 0; i < gravitySize; i++)
	{
		gravity_t gravChange;
		g_aGravityChanges[client].GetArray(i, gravChange);

		float tickTime = g_iTick[client] * GetTickInterval();
		float startTime = gravChange.iStartTick * GetTickInterval();
		
		float timescale = GetEntPropFloat(client, Prop_Send, "m_flLaggedMovementValue");
		
		if(tickTime - startTime >= (gravChange.fDelay / timescale))
		{
			//PrintToChat(client, "time: %f, del: %f", tickTime - startTime, gravChange.fDelay);
			SetEntityGravity(client, gravChange.fGravity);
			//PrintToChat(client, "setting gravity: %f", gravChange.fGravity);
			
			g_aGravityChanges[client].Erase(i);
			gravitySize = gravitySize - 1;
		}
		
	} 
}

public void OnEntitiesReady()
{
	HookTriggers();
}

void HookTriggers()
{
	HookEntityOutput("trigger_multiple", "OnTrigger", OnTrigger);
	HookEntityOutput("trigger_multiple", "OnStartTouch", OnTrigger); //for fixing prespeed blockers on kz_bhop_badg3s
	HookEntityOutput("trigger_multiple", "OnEndTouch", OnTrigger); 
	HookEntityOutput("trigger_multiple", "OnTouching", OnTrigger);
	
	//fix blue boosters on badges
	HookEntityOutput("func_button", "OnDamaged", OnTrigger);
}

public Action OnTrigger(const char[] output, int caller, int activator, float delay)
{
	Entity entity;
	bool handled;
	
	if(!IsValidEntity(activator))
		return Plugin_Continue;
	
	float timescale = GetEntPropFloat(activator, Prop_Send, "m_flLaggedMovementValue");

	if(g_bToggled[activator] || timescale == 1.0)
		return Plugin_Continue;
		
	if(GetOutputEntity(caller, entity))
	{
		for(int i = 0; i < entity.OutputList.Length; ++i)
		{
			Output out;
			entity.OutputList.GetArray(i, out);
			
			if(StrEqual(out.Output, output, false) && StrEqual(out.Target, "!activator", false))
			{
				char params[2][MEMBER_SIZE];
				ExplodeString(out.Parameters, " ", params, 2, MEMBER_SIZE);
				
				if(StrContains(params[0], "targetname") >= 0)
				{
					target_t targ;
					strcopy(targ.sTargetName, 32, params[1]);
					targ.fDelay = out.Delay;
					targ.iStartTick = g_iTick[activator];
					
					g_aTargetChanges[activator].PushArray(targ);
					handled = true;
					
					//PrintToChat(activator, "output: %s, params: %s", out.Output, out.Parameters);
					
				} 	
				
				if(StrContains(params[0], "gravity") >= 0)
				{
					gravity_t gravityChange;
					gravityChange.fDelay = out.Delay;
					gravityChange.iStartTick = g_iTick[activator];
					gravityChange.fGravity = StringToFloat(params[1]);
					
					g_aGravityChanges[activator].PushArray(gravityChange);
					handled = true;
				} 
			}
		}
	}
	
	entity.CleanUp();
	
	if(handled)
		return Plugin_Handled;
	
	return Plugin_Continue;
}
