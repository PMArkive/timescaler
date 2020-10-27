
#define DEBUG

#define PLUGIN_NAME           "Timescaler"
#define PLUGIN_AUTHOR         "carnifex"
#define PLUGIN_DESCRIPTION    "Scales triggers to match your timescale."
#define PLUGIN_VERSION        "1.0"
#define PLUGIN_URL            "https://github.com/hermansimensen/timescaler"

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <output_info_plugin>
#include <smlib/entities>
#include <smlib/math>

#pragma semicolon 1

ArrayList g_aTargetChanges[MAXPLAYERS + 1];
ArrayList g_aGravityChanges[MAXPLAYERS + 1];
ArrayList g_aTriggerPush;
bool g_bToggled[MAXPLAYERS + 1];
bool g_bTriggerActive[MAXPLAYERS + 1];
int g_iTick[MAXPLAYERS + 1];
float g_fPrevTimescale[MAXPLAYERS + 1];
float g_fSpeedAdded[MAXPLAYERS + 1];

ConVar g_cvUsePushFix;

enum struct target_t
{
	int iStartTick;
	char sTargetName[64];
	float fDelay;
}

enum struct gravity_t
{
	float fGravity;
	float fDelay;
	int iStartTick;
}

enum struct trigger_push_t
{
	int iIndex;
	int iFilterEntity;
	float fPushSpeed;
	float fPushDir[3];
	char sFilterName[64];
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
	
	g_cvUsePushFix = CreateConVar("timescaler_use_pushfix", "1", "Some TAS-tools break trigger_push on css and csgo, which lets users abuse it and gain a lot more height and speed than what they should have. If you wish to use a seperate pushfix plugin, then disable this.", _, true, 0.0, true, 1.0);
	
	if(g_aTriggerPush == null)
	{
		g_aTriggerPush = new ArrayList(sizeof(trigger_push_t));
	} else
	{
		ClearArray(g_aTriggerPush);
	}
	
	HookEvent("round_start", Event_RoundStart, EventHookMode_PostNoCopy);
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
	float timescale = GetEntPropFloat(client, Prop_Send, "m_flLaggedMovementValue");
	
	//handle targetname changes
	int size = GetArraySize(g_aTargetChanges[client]);
	for(int i = 0; i < size; i++)
	{
		target_t targetChange;
		g_aTargetChanges[client].GetArray(i, targetChange);
		float tickTime = g_iTick[client] * GetTickInterval();
		float startTime = targetChange.iStartTick * GetTickInterval();
		
		if(tickTime - startTime >= (targetChange.fDelay / timescale))
		{
			SetEntPropString(client, Prop_Data, "m_iName", targetChange.sTargetName);
			
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
		
		if(tickTime - startTime >= (gravChange.fDelay / timescale))
		{
			SetEntityGravity(client, gravChange.fGravity);
			
			g_aGravityChanges[client].Erase(i);
			gravitySize = gravitySize - 1;
		}
	}
	g_fPrevTimescale[client] = timescale;
}

public Action Event_RoundStart(Event event, const char[] name, bool dontBroadcast)
{
	g_aTriggerPush.Clear();
	GetTriggerPush();
}

public void OnMapStart()
{
	g_aTriggerPush.Clear();
	GetTriggerPush();
}

public void OnEntitiesReady()
{
	HookTriggers();
}

void GetTriggerPush()
{
	int ent = -1;
	while ((ent = FindEntityByClassname(ent, "trigger_push")) != -1)
	{
		SDKHook(ent, SDKHook_Touch, Hook_Touch);
		
		float pushSpeed = GetEntPropFloat(ent, Prop_Data, "m_flSpeed");
		
		float pushDir[3];
		GetEntPropVector(ent, Prop_Data, "m_vecPushDir", pushDir);
		
		float angs[3];
		GetEntPropVector(ent, Prop_Data, "m_angRotation", angs);
		
		Math_RotateVector(pushDir, angs, pushDir);
		
		char filter[32];
		int filterEnt;
		GetEntPropString(ent, Prop_Data, "m_iFilterName", filter, sizeof(filter));
		
		filterEnt = Entity_FindByName(filter, "filter_activator_name");
		
		trigger_push_t trigger;
		trigger.iIndex = ent;
		trigger.fPushDir = pushDir;
		trigger.fPushSpeed = pushSpeed;
		trigger.iFilterEntity = filterEnt;
		
		if(filterEnt != -1)
		GetEntPropString(filterEnt, Prop_Data, "m_iFilterName", trigger.sFilterName, sizeof(trigger.sFilterName));
		
		g_aTriggerPush.PushArray(trigger);
	}
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

public Action Hook_Touch(int ent, int other)
{
	if(!IsValidEntity(other) || !IsValidEntity(ent))
		return Plugin_Continue;
	
	int spawnflags = GetEntProp(ent, Prop_Data, "m_spawnflags"); 
	
	trigger_push_t trigger;
	
	for(int i = 0; i < g_aTriggerPush.Length; i++)
	{
		g_aTriggerPush.GetArray(i, trigger);
		
		if(trigger.iIndex == ent)
			break;
	}
	
	if(DoesEntityPassFilter(other, ent, trigger))
	{
		float timescale = GetEntPropFloat(other, Prop_Data, "m_flLaggedMovementValue");
		
		if(timescale < g_fPrevTimescale[other])
		{
			//prevent timescale abuse
			float multiplier = g_fSpeedAdded[other] * timescale;
			g_iTick[other] += RoundToCeil(multiplier) * RoundToCeil(g_fPrevTimescale[other] / timescale);
		}
		
		if(g_cvUsePushFix.BoolValue)
		{
			if(spawnflags & 0x80)
			{
				float vec[3];
				GetEntPropVector(other, Prop_Data, "m_vecAbsVelocity", vec);
				
				vec[0] += (trigger.fPushDir[0] * trigger.fPushSpeed);
				vec[1] += (trigger.fPushDir[1] * trigger.fPushSpeed);
				vec[2] += (trigger.fPushDir[2] * trigger.fPushSpeed);
				
				SetEntPropVector(other, Prop_Data, "m_vecAbsVelocity", vec);
				
				if(trigger.fPushDir[2] > 0.0)
				SetEntPropEnt(other, Prop_Send, "m_hGroundEntity", -1);
				
				RemoveEdict(ent);
			}
			
			if(!g_bTriggerActive[other])
			{
				g_fSpeedAdded[other] = 0.0;
				g_bTriggerActive[other] = true;
			}
			
					//lift the player up 1.0 units if they are on the ground..
			if(trigger.fPushDir[2] > 0.0 && GetEntityFlags(other) & FL_ONGROUND)
			{
				SetEntPropEnt(other, Prop_Send, "m_hGroundEntity", -1);
				
				if(GetEngineVersion() == Engine_CSS)
				{
					float origin[3];
					GetEntPropVector(other, Prop_Data, "m_vecAbsOrigin", origin);
					origin[2] += 1.0;
					TeleportEntity(other, origin, NULL_VECTOR, NULL_VECTOR);
				}
			}
			
			float vec[3];
			GetEntPropVector(other, Prop_Send, "m_vecBaseVelocity", vec);
			vec[0] = (trigger.fPushDir[0] * trigger.fPushSpeed);
			vec[1] = (trigger.fPushDir[1] * trigger.fPushSpeed);
			vec[2] = 0.0;
			SetEntPropVector(other, Prop_Data, "m_vecBaseVelocity", vec);
			
			//why add vertical speed manually? Shavit-TAS breaks trigger_push boosters on lower timescales, which lets users gain a lot more height than they should get. This fixes that issue.
			float absVelocity[3];
			GetEntPropVector(other, Prop_Data, "m_vecAbsVelocity", absVelocity);
			absVelocity[2] += (trigger.fPushDir[2] * trigger.fPushSpeed * GetTickInterval()) * timescale;
			g_fSpeedAdded[other] += (trigger.fPushDir[2] * trigger.fPushSpeed * GetTickInterval()) * timescale;
			SetEntPropVector(other, Prop_Data, "m_vecAbsVelocity", absVelocity);
		
			int flags = GetEntityFlags(other) | FL_BASEVELOCITY;
			SetEntityFlags(other, flags);
		}
	} else
	{
		g_bTriggerActive[other] = false;
	}
	
	if(g_cvUsePushFix.BoolValue)
		return Plugin_Handled;
		
	return Plugin_Continue;
}

public bool DoesEntityPassFilter(int entity, int trigger, trigger_push_t triggerPush)
{
	int spawnflags = GetEntProp(trigger, Prop_Data, "m_spawnflags");
	int clientAllowed = spawnflags & 0x01;
	if(clientAllowed == 1 && (entity > 0 && entity < MaxClients))
	{
		MoveType movetype = GetEntityMoveType(entity);
		
		switch(movetype)
		{
			case MOVETYPE_NONE, MOVETYPE_PUSH, MOVETYPE_NOCLIP:
			{
				return false;
			}
			
			default:
			{
				if(triggerPush.iFilterEntity == -1)
				{
					return true;
				} else
				{
					char name[64];
					GetEntPropString(entity, Prop_Data, "m_iName", name, 64);
					if(StrEqual(name, triggerPush.sFilterName, false))
					{
						return true;
					} else
					{
						return false;
					}
				}
			}
		
		}
	}
	
	return true;
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
					strcopy(targ.sTargetName, 64, params[1]);
					targ.fDelay = out.Delay;
					targ.iStartTick = g_iTick[activator];
					
					g_aTargetChanges[activator].PushArray(targ);
					handled = true;			
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
