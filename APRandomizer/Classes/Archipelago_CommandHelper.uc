class Archipelago_CommandHelper extends Hat_PlayerInput;

`include(APRandomizer\Classes\Globals.uci);

exec function ap_set_connection_info(string ip, int port)
{
	`AP.SlotData.Host = ip;
	`AP.SlotData.Port = port;
	`AP.SaveGame();
	`AP.ScreenMessage("Set target host to: "$ip $":" $port);
}

exec function ap_set_port(int port)
{
	`AP.SlotData.Port = port;
	`AP.SaveGame();
	`AP.ScreenMessage("Set port to: "$port);
}

exec function ap_show_connection_info()
{
	`AP.ScreenMessage("Current target host: "$`AP.SlotData.Host $":" $`AP.SlotData.Port);
}

exec function test_clienttravel(string URL, ETravelType TravelType, optional bool bSeamless = false, optional init Guid MapPackageGuid)
{
	`AP.GetALocalPlayerController().ClientTravel(URL, TravelType, bSeamless, MapPackageGuid);
}

exec function ap_say(string message)
{
	local JsonObject json;
	
	if (!`AP.IsFullyConnected())
	{
		`AP.ScreenMessage("You are not connected.");
		return;
	}
	
	json = new class'JsonObject';
	json.SetStringValue("cmd", "Say");
	json.SetStringValue("text", message);
	`AP.Client.SendBinaryMessage("[" $class'JsonObject'.static.EncodeJson(json) $"]");
}

exec function ap_connect()
{
	if (`AP.IsFullyConnected() || `AP.Client == None)
		return;
	
	`AP.Client.Connect();
}

exec function ap_deathlink()
{
	local bool val;
	local string message;
	
	if (`AP.Client == None || !`AP.IsFullyConnected())
	{
		`AP.ScreenMessage("You are not connected.");
		return;
	}
	
	val = !`AP.SlotData.DeathLink;
	
	if (val)
	{
		message = "[{\"cmd\": \"ConnectUpdate\", \"tags\": [\"DeathLink\", \"AP\"]}]";
		`AP.ScreenMessage("Death Link enabled.");
	}
	else
	{
		message = "[{\"cmd\": \"ConnectUpdate\", \"tags\": [\"AP\"]]}]";
		`AP.ScreenMessage("Death Link disabled.");
	}
	
	`AP.Client.SendBinaryMessage(message);
	`AP.SlotData.DeathLink = val;
	`AP.SaveGame();
}

// -------------------------------------------- DEBUG COMMANDS -------------------------------------------- \\
exec function ap_teleport(float x, float y, float z)
{
	local Vector loc;
	
	if (!bool(`AP.DebugMode))
		return;
	
	loc.x = x;
	loc.y = y;
	loc.z = z;
	Pawn.SetLocation(loc);
}

exec function ap_give_yarn(int count)
{
	if (!bool(`AP.DebugMode) || count <= 0)
		return;
		
	`AP.OnYarnCollected(count);
	`AP.ScreenMessage("Gave " $count $" yarn");
}

exec function ap_complete_act(string id)
{
	if (!bool(`AP.DebugMode))
		return;
		
	`AP.SetAPBits("ActComplete_"$id, 1);
	`AP.ScreenMessage("Completed act: " $id);
}

exec function ap_alpine_finale()
{
	if (!bool(`AP.DebugMode))
		return;
	
	`AP.SetAPBits("AlpineFinale", 1);
	`GameManager.LoadNewAct(4, 1);
	ConsoleCommand("servertravel alpsandsails");
}

exec function ap_closest_actors(float radius)
{
	local Actor a;
	local Archipelago_GameMod m;
	local float distance;

	m = `AP;
	if (!bool(m.DebugMode))
		return;
	
	m.DebugMessage("Finding closest actors...");
	foreach Pawn.AllActors(class'Actor', a)
	{
		distance = m.GetVectorDistance(Pawn.Location, a.Location);
		if (distance > radius)
			continue;
		
		m.DebugMessage("ACTOR: " $a.Name $ ", DISTANCE: " $distance);
	}
}