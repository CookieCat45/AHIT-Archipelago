class Archipelago_GameMod extends GameMod
	IterationOptimized
	dependson(Archipelago_ItemInfo)
	dependson(Archipelago_HUDElementBubble)
	config(Mods);

`include(APRandomizer\Classes\Globals.uci);
const SlotDataVersion = 12;

var Archipelago_TcpLink Client;
var Archipelago_SlotData SlotData;
var Archipelago_ItemResender ItemResender;
var array<Hat_GhostPartyPlayerStateBase> Buddies; // Online Party co-op support
var array<class<Object> > CachedShopInvs;
var transient int ActMapChangeChapter;
var transient bool ActMapChange;
var transient bool CollectiblesShuffled;
var transient bool ControllerCapsLock;
var transient bool ContractEventActive;
var transient bool ItemSoundCooldown;
var transient bool DeathLinked;
var transient string DebugMsg;

var config int DebugMode;
var config int DisableInjection;
var config int VerboseLogging;
var const editconst Vector SpaceshipSpawnLocation;

var transient array<Hat_SnatcherContract_Selectable> SelectContracts;
var transient bool TrapsDestroyed;
var transient float TimeSinceLastItem;

struct immutable ShuffledAct
{
	var Hat_ChapterActInfo OriginalAct;
	var Hat_ChapterActInfo NewAct;
	var bool IsDeadBirdBasementOriginalAct;
	var bool IsDeadBirdBasementShuffledAct;
};

struct immutable ShopItemInfo
{
	var class<Archipelago_ShopItem_Base> ItemClass;
	var int ID;
	var string ItemID; // string since it can be item IDs from other games, which can be 64 bit.
	var int ItemFlags;
	var int PonCost;
	var int Player;
	var bool Hinted;
};

struct immutable ShopItemName
{
	var int ID;
	var string ItemName;
};

struct immutable LocationInfo
{
	var int ID;
	var string ItemID; // string since it can be item IDs from other games, which can be 64 bit.
	var int Player;
	var int Flags;
	var bool IsStatic;
	var string MapName;
	
	var Vector Position;
	var class<Actor> ItemClass;
	var class<Actor> ContainerClass;
};

// Level bit prefix
const ArchipelagoPrefix = "AP_";

// Location ID ranges
const BaseIDRange = 2000300000;
const ActCompleteIDRange = 2000310000;
const Chapter3IDRange = 2000320000;
const Chapter4IDRange = 2000330000;
const StoryBookPageIDRange = 2000340000;
const TasksanityIDStart = 2000300204;

// Event checks
const RumbiYarnCheck = 2000301000;
const UmbrellaCheck = 2000301002;

// These have to be hardcoded because camera badge item disappears if you have the camera badge
const CameraBadgeCheck1 = 2000302003;
const CameraBadgeCheck2 = 2000302004;
const SubconBushCheck1 = 2000325478;
const SubconBushCheck2 = 2000325479;
var const editconst Vector Camera1Loc;
var const editconst Vector Camera2Loc;

// Traps
var transient int BabyCount;
var transient int LaserCount;
var int ParadeTrapMembers;
var float ParadeTrapDelay;
var float ParadeTrapSpread;

// Other things
var array<Hat_TreasureChest_Base> ChestArray;
var array<Hat_NPC> BulliedNPCArray;
var array<Hat_Enemy_ScienceBand_Base> ParadeArray;
var array<Texture2D> UnlockScreenNumbers;
var array<string> ThugCatShops;

event OnModLoaded()
{
	if (IsCurrentPatch())
		return;

	HookActorSpawn(class'Hat_Player', 'Player');
	if (IsArchipelagoEnabled())
	{
		HookActorSpawn(class'Actor', 'ActorSpawn');
	}
}

event OnModUnloaded()
{
	if (IsArchipelagoEnabled())
		SaveGame();
}

function OnPreRestartMap(out String MapName)
{
	if (IsArchipelagoEnabled())
		SaveGame();
}

function SaveGame()
{
	if (SlotData != None && SlotData.Initialized)
	{
		class'Engine'.static.BasicSaveObject(SlotData, "APSlotData/slot_data"$`SaveManager.GetCurrentSaveData().CreationTimeStamp, false, SlotDataVersion, true);
	}
	
	if (ItemResender != None)
	{
		class'Engine'.static.BasicSaveObject(ItemResender, "APSlotData/item_resender"$`SaveManager.GetCurrentSaveData().CreationTimeStamp, false, 1, true);
	}
	
	`SaveManager.SaveToFile(true);
	DebugMessage("Saved the game");
}

event Tick(float d)
{
	local int i;
	local array<LocalPlayer> players;
	
	Super.Tick(d);
	if (!IsArchipelagoEnabled())
		return;
	
	IterateChestArray();
	
	if (ParadeArray.Length > 0)
	{
		players = class'Engine'.static.GetEngine().GamePlayers;
	
		for (i = 0; i < ParadeArray.Length; i++)
		{
			if (ParadeArray[i].MimicPlayerIndex >= players.Length)
				continue;
			
			if (ShouldFreezeParade(Hat_PlayerController(players[ParadeArray[i].MimicPlayerIndex].Actor.Pawn.Controller)))
			{
				ParadeArray[i].SetTickIsDisabled(true);
				ParadeArray[i].SetCollision(false);
			}
			else
			{
				ParadeArray[i].SetTickIsDisabled(false);
				ParadeArray[i].SetCollision(true);
			}
		}
	}
}

function bool ShouldFreezeParade(Hat_PlayerController c)
{
	if (c.IsTalking()) return true;
	if (c.PlayerCamera != None && Hat_PlayerCamera(c.PlayerCamera) != None && Hat_PlayerCamera(c.PlayerCamera).IgnorePlayerMovement()) return true;
	if (c.MyHUD != None && Hat_HUD(c.MyHUD) != None && Hat_HUD(c.MyHUD).CacheElementsDisableMovement)
	{
		if (Hat_HUD(c.MyHUD).GetHUD(class'Hat_HUDMenu_ItemWheel', true) == None)
			return true;
	}
	
	// mainly for Snatcher boss end cutscene
	if (c.Pawn.Base.IsA('Hat_Bench_Generic'))
		return true;
	
	return false;
}

event OnHookedActorSpawn(Object newActor, Name identifier)
{
	local int i;
	local array<int> ids;
	local Hat_SaveGame save;
	local Hat_PlayerController ctr;
	
	if (identifier == 'Player')
	{
		if (newActor.IsA('Hat_Player_MustacheGirl'))
			return;
			
		// Need to do this on a timer to prevent the game from overriding our actions
		SetTimer(0.3, false, NameOf(EnableConsoleCommands));
	}
	
	if (IsArchipelagoEnabled())
	{
		if (identifier == 'ActorSpawn')
		{
			if (newActor.IsA('Hat_Vacuum') && !IsLocationChecked(RumbiYarnCheck))
			{
				SetTimer(0.1, true, NameOf(RumbiHitCheckTimer), self, newActor);
			}
			else if (SlotData.ShuffleActContracts)
			{
				if (newActor.IsA('Hat_SnatcherContractEvent'))
				{
					if (newActor.IsA('Hat_SnatcherContractEvent_Initial') || newActor.IsA('Hat_SnatcherContractEvent_GenericTrap')
						|| newActor.IsA('Hat_SnatcherContractEvent_IceBroken'))
					{
						DebugMessage("Hooking contract event: " $newActor.name);
						ContractEventActive = true;
						save = `SaveManager.GetCurrentSaveData();
						
						if (!HasAPBit("ContractScout", 1) && IsFullyConnected())
						{
							ids.AddItem(2000300201);
							ids.AddItem(2000300202);
							ids.AddItem(2000300203);
							SendMultipleLocationChecks(ids, true, true);
							SetAPBits("ContractScout", 1);
						}
						
						for (i = 0; i < SlotData.ObtainedContracts.Length; i++)
						{
							if (SlotData.CheckedContracts.Find(SlotData.ObtainedContracts[i]) != -1)
								continue;
							
							// temporarily remove any obtained contracts so player can still do contract checks
							SlotData.TakenContracts.AddItem(SlotData.ObtainedContracts[i]);
							save.SnatcherContracts.RemoveItem(SlotData.ObtainedContracts[i]);
							save.CompletedSnatcherContracts.RemoveItem(SlotData.ObtainedContracts[i]);
						}
						
						foreach DynamicActors(class'Hat_PlayerController', ctr)
						{
							// Dying while signing a contract may cause the check to not send and become permanently unavailable.
							// This can primarily happen with traps. So we need to enable god mode temporarily.
							ctr.bGodMode = true;
						}
						
						SetTimer(0.5, true, NameOf(WaitForContractEvent));
					}
				}
				else if (newActor.IsA('Hat_SnatcherContract_Selectable'))
				{
					SelectContracts.AddItem(Hat_SnatcherContract_Selectable(newActor));
					ClearTimer(NameOf(CheckContractsForDeletion));
					SetTimer(0.5, false, NameOf(CheckContractsForDeletion));
				}
			}
		}
	}
}

// Override the player's input class so we can use our own console commands (without conflicting with Console Commands Plus!)
function EnableConsoleCommands()
{
	local PlayerController c;
	if (!IsArchipelagoEnabled())
		return;
	
	c = GetALocalPlayerController();
	c.Interactions.RemoveItem(c.PlayerInput);
	c.PlayerInput = None;
	c.InputClass = class'Archipelago_CommandHelper';
	c.InitInputSystem();
}

function CreateClient()
{
	if (client != None)
		return;
	
	client = Spawn(class'Archipelago_TcpLink');
}

event PreBeginPlay()
{
	local Hat_CollectibleBackpackItem relic;
	local Hat_SaveGame save;
	local string path;
	local int i, pos, a, j;
	local bool firstLoad;
	
	Super.PreBeginPlay();
	
	if (IsInTitlescreen() || IsCurrentPatch())
		return;
	
	if (bool(DisableInjection) && !IsArchipelagoEnabled())
		return;
	
	save = `SaveManager.GetCurrentSaveData();
	if (!IsArchipelagoEnabled() && save.TotalPlayTime <= 0.0)
	{
		SetAPBits("ArchipelagoEnabled", 1);
		firstLoad = true;
	}
	
	if (!IsArchipelagoEnabled())
		return;
	
	if (IsSaveFileJustLoaded())
		firstLoad = true;
	
	if (firstLoad)
	{
		// set all to 99 to prevent chapters from unlocking before we get a chance to set the actual costs
		SetChapterTimePieceRequirement(Hat_ChapterInfo'HatinTime_ChapterInfo.maingame.MafiaTown', 99);
		SetChapterTimePieceRequirement(Hat_ChapterInfo'HatinTime_ChapterInfo.maingame.trainwreck_of_science', 99);
		SetChapterTimePieceRequirement(Hat_ChapterInfo'HatinTime_ChapterInfo.maingame.subconforest', 99);
		SetChapterTimePieceRequirement(Hat_ChapterInfo'HatinTime_ChapterInfo.maingame.Sand_and_Sails', 99);
		SetChapterTimePieceRequirement(Hat_ChapterInfo'HatinTime_ChapterInfo.maingame.Mu_Finale', 99);
		SetChapterTimePieceRequirement(Hat_ChapterInfo'HatinTime_ChapterInfo_DLC1.ChapterInfos.ChapterInfo_Cruise', 99);
		SetChapterTimePieceRequirement(Hat_ChapterInfo'hatintime_chapterinfo_dlc2.ChapterInfos.ChapterInfo_Metro', 99);
	}
	
	SlotData = new class'Archipelago_SlotData';
	path = "APSlotData/slot_data"$`SaveManager.GetCurrentSaveData().CreationTimeStamp;
	
	if (class'Engine'.static.BasicLoadObject(SlotData, path, false, SlotDataVersion))
	{
		SlotData.Initialized = true;
		UpdateChapterInfo();
	}
	
	if (SlotData.Initialized)
	{
		if (SlotData.Goal != 1)
		{
			// never play endgame cutscenes if our goal isn't Finale
			class'Hat_SaveBitHelper'.static.SetActBits("thefinale_ending", 0);
			class'Hat_SaveBitHelper'.static.SetLevelBits("MuMission_Finale", 1, "hub_spaceship");
		}
	}
	
	if (!IsInSpaceship())
	{
		if (`GameManager.GetCurrentMapFilename() ~= "subconforest")
		{
			// If player has all contracts (other than Subcon Well), remove one so that traps still spawn
			if (save.SnatcherContracts.Length >= 3 || save.CompletedSnatcherContracts.Length >= 3)
			{
				for (i = 0; i < 4; i++)
				{
					if (i < save.SnatcherContracts.Length || i < save.CompletedSnatcherContracts.Length)
					{
						if (i < save.SnatcherContracts.Length && save.SnatcherContracts[i] != class'Hat_SnatcherContract_IceWall'
						|| i < save.CompletedSnatcherContracts.Length && save.CompletedSnatcherContracts[i] != class'Hat_SnatcherContract_IceWall')
						{
							pos = save.SnatcherContracts.Find(save.SnatcherContracts[i]);
							if (pos != -1)
							{
								SlotData.TakenContracts.AddItem(save.SnatcherContracts[pos]);
								save.SnatcherContracts.RemoveItem(save.SnatcherContracts[pos]);
							}
							
							pos = save.CompletedSnatcherContracts.Find(save.SnatcherContracts[i]);
							if (pos != -1)
							{
								if (SlotData.TakenContracts.Find(save.SnatcherContracts[pos]) == -1)
									SlotData.TakenContracts.AddItem(save.SnatcherContracts[pos]);
							
								save.CompletedSnatcherContracts.RemoveItem(save.SnatcherContracts[pos]);
							}
							
							break;
						}
					}
				}
			}
			else if (save.SnatcherContracts.Length <= 1 && save.CompletedSnatcherContracts.Length <= 1
				&& save.TurnedInSnatcherContracts.Length <= 1)
			{
				// We need to give the player two dummy contracts so that all of the traps spawn,
				// this is due to the MinContractsToSpawn variable in Hat_SnatcherContractSummon
				// (using console commands to set to 0 doesn't work, because some have it set to 2 when the default is 1)
				save.GiveContract(class'Archipelago_SnatcherContract_Dummy1', GetALocalPlayerController());
				save.GiveContract(class'Archipelago_SnatcherContract_Dummy2', GetALocalPlayerController());
			}
			
			if (!class'Hat_SnatcherContract_DeathWish'.static.IsAnyActive(false) && (!HasAPBit("SubconBush1", 1) || !HasAPBit("SubconBush2", 1)))
			{
				SetTimer(0.3, true, NameOf(SubconBushCheckTimer));
			}
		}
		
		if (`GameManager.GetChapterInfo().ChapterID == 4)
		{
			if (!class'Hat_SaveBitHelper'.static.HasActBit("ForceAlpineFinale", 1))
			{
				if (HasAPBit("AlpineFinale", 1))
					EnableAlpineFinale();
				else
					DisableAlpineFinale();
			}
		}
	}
	
	for (i = 0; i < save.HUBDecorations.Length; i++)
	{
		if (save.HUBDecorations[i].Complete)
		{
			for (a = 0; a < save.HUBDecorations[i].Decorations.Length; a++)
			{
				relic = class'Hat_Loadout'.static.MakeCollectibleBackpackItem(save.HUBDecorations[i].Decorations[a]);
				
				for (j = 0; j < save.MyBackpack2017.Collectibles.Length; j++)
				{
					if (save.MyBackpack2017.Collectibles[j].BackpackClass == relic.BackpackClass)
						save.MyBackpack2017.Collectibles[j] = None;
				}
			}
			
			save.HUBDecorations.RemoveItem(save.HUBDecorations[i]);
			i--;
		}
	}
	
	SetAPBits("AlpineFinale", 0);
	ConsoleCommand("set Hat_IntruderInfo_CookingCat HasIntruderAlert false");
}

event PostBeginPlay()
{
	Super.PostBeginPlay();
	
	if (!IsArchipelagoEnabled())
		return;
	
	`SaveManager.SetSavingEnabled(true);
	
	if (IsInSpaceship())
	{
		// Skip the intro cinematic so we don't go to Mafia Town
		class'Hat_SaveBitHelper'.static.SetLevelBits("hub_cinematics", 1);
	}
	
	ItemResender = new class'Archipelago_ItemResender';
}

function OnPostInitGame()
{
	local int i, saveCount;
	local string mapName, realMapName;
	local Hat_BackpackItem item;
	local Hat_TreasureChest_Base chest;
	local TriggerVolume trigger;
	local Hat_SaveGame save;
	local Hat_Player ply;
	local Hat_PlayerController ctr;
	local Hat_NPC npc;
	local Hat_SubconPainting painting;
	local Hat_HookPoint_Desert hookPoint;
	local array<SequenceObject> seqObjects;
	local Hat_MetroTicketBooth_Base booth;
	local ShopInventoryItem dummy;
	local array<Object> shopInvs;
	local Hat_BonfireBarrier barrier;
	local Hat_SandStationHorn_Base horn;
	local array<class<Object > > DeathWishes;
	local class<Hat_SnatcherContract_DeathWish> dw;
	local class<Hat_CosmeticItemQualityInfo> flair;
	local Hat_ImpactInteract_Breakable_ChemicalBadge crate;
	local Actor a;
	
	if (IsCurrentPatch())
		return;
	
	// If on titlescreen, find any Archipelago-enabled save files and do this stuff 
	// to prevent the game from forcing the player into Mafia Town.
	if (IsInTitlescreen())
	{
		saveCount = `SaveManager.NumUsedSaveSlots();
		
		for (i = 0; i < saveCount; i++)
		{
			save = Hat_SaveGame(`SaveManager.GetSaveSlot(i));
			if (save == None)
				continue;
			
			if (HasAPBit("ArchipelagoEnabled", 1, save))
			{
				save.AllowSaving = false;
				SetAPBits("SaveFileLoad", 0, save);
			}
		}
		
		ResetEverything();
	}
	
	if (!IsArchipelagoEnabled())
		return;
	
	if (bool(DebugMode))
		SetTimer(1.0, true, NameOf(PrintItemsNearPlayer));
	
	HideItems();
	
	// Bon Voyage hotfix
	SetTimer(0.5, false, NameOf(HideItems));
	
	if (IsInSpaceship())
	{
		// Stop Mustache Girl tutorial cutscene (it breaks when removing the yarn)
		// The player can still get the yarn by smacking Rumbi after getting 4 time pieces.
		foreach DynamicActors(class'Hat_NPC', npc)
		{
			if (npc.IsA('Hat_NPC_MustacheGirl') && npc.Name == 'Hat_NPC_MustacheGirl_0')
			{
				npc.ShutDown();
			}
			else if (npc.IsA('Hat_NPC_CookingCat'))
			{
				npc.ShutDown();
			}
			else if (SlotData.DeathWishOnly && npc.IsA('Hat_NPC_MafiaBossJar'))
			{
				npc.ShutDown();
			}
		}

		SetTimer(0.01, false, NameOf(SpawnDecorationStands));
		
		// When returning to hub from levels in act rando, the player may get softlocked behind chapter doors, prevent this
		if (SlotData.ActRando)
		{
			foreach DynamicActors(class'Hat_Player', ply)
			{
				if (ply.IsA('Hat_Player_MustacheGirl'))
					continue;
				
				if (SlotData.Initialized)
					ply.SetLocation(SlotData.LastSpaceshipLocation);
				else
					ply.SetLocation(SpaceshipSpawnLocation);
			}
		}
		
		if ((SlotData.DLC1 || SlotData.DeathWishOnly) && IsDLC1Installed())
		{
			// In vanilla, Tour requires ALL but 1 time pieces, which changes depending on the DLC the player has.
			// This may change in the future, but for now, it's always available (once the player unlocks Chapter 5).
			a = FindActorByName('Hat_TimeRiftPortal_2', true);
			if (a != None)
			{
				if (SlotData.ExcludeTour && !SlotData.DeathWishOnly)
				{
					ConsoleCommand("set "$a.Name $" Enabled false");
					ConsoleCommand("set "$a.Name $" IdleSoundComponent none");
					a.SetHidden(true);
				}
				else
				{
					DebugMessage("FORCING TOUR TIME RIFT ENABLED");
					SetTimer(0.8, true, NameOf(ForceTourTimeRift), self, a); // to make sure it's enabled, cause it seems stubborn otherwise
					ConsoleCommand("set "$a.Name $" Enabled true");
					ConsoleCommand("set "$a.Name $" ForceEnable true");
					a.SetHidden(false);
				}
			}
		}
		
		ForceLightsOn();
		OpenBedroomDoor();
		`SetMusicParameterInt('FirstChapterUnlockSilence', 0);
		
		// Set this level bit to 0 so that Rumbi will drop the yarn and trigger the check
		class'Hat_SaveBitHelper'.static.SetLevelBits("mu_preawakening_intruder_tutorial", 0);
	}
	
	foreach DynamicActors(class'Hat_TreasureChest_Base', chest)
	{
		if (chest.Opened || class<Hat_Collectible_Important>(chest.Content) == None
			&& class<Hat_Collectible_StoryBookPage>(chest.Content) == None)
			continue;
		
		if (chest.IsA('Hat_TreasureChest_GiftBox'))
			continue;
		
		if (SlotData.DeathWishOnly || class'Hat_SnatcherContract_DeathWish'.static.IsAnyActive(false))
		{
			if (class<Hat_Collectible_Important>(chest.Content) != None)
				chest.Empty();
			
			continue;
		}
		
		if (IsLocationChecked(ObjectToLocationId(chest)))
		{
			chest.Empty();
			continue;
		}
		
		ChestArray.AddItem(chest);
		
		if (class<Hat_Collectible_StoryBookPage>(chest.Content) == None
		&& class<Hat_Collectible_TreasureBit>(chest.Content) == None)
		{
			chest.Content = class'Hat_Collectible_EnergyBit';
		}
	}
	
	foreach DynamicActors(class'Hat_ImpactInteract_Breakable_ChemicalBadge', crate)
	{
		for (i = 0; i < crate.Rewards.Length; i++)
		{
			if (class<Hat_Collectible_Important>(crate.Rewards[i]) != None)
			{
				// don't allow crate to remove its own rewards
				crate.Rewards[i] = class'Archipelago_RandomizedItem_Base';
			}
		}
	}
	
	if (SlotData.BadgeSellerItemCount <= 0 || SlotData.DeathWishOnly)
	{
		foreach DynamicActors(class'Hat_NPC', npc)
		{
			if (npc.IsA('Hat_NPC_BadgeSalesman'))
				npc.ShutDown();
		}
	}
	
	mapName = class'Hat_SaveBitHelper'.static.GetCorrectedMapFilename();
	realMapName = `GameManager.GetCurrentMapFilename();
	
	// Fix for Rock the Boat
	if (realMapName ~= "ship_sinking")
		mapName = "ship_sinking";
	
	if (IsMapScouted(mapName))
		SetTimer(0.4, false, NameOf(ShuffleCollectibles2));
	
	if (InStr(realMapName, "mafia_town") != -1)
	{
		DeleteCameraParticle();
	}
	else if (realMapName ~= "alpsandsails")
	{
		if (!class'Hat_SnatcherContract_DeathWish_Speedrun_Illness'.static.IsActive())
		{
			if (SlotData.ShuffleZiplines)
			{
				SetTimer(0.8, true, NameOf(UpdateZiplineUnlocks));
			}
			
			foreach DynamicActors(class'Hat_HookPoint_Desert', hookPoint)
			{
				if (hookPoint.IsIntro > 0)
				{
					hookPoint.MoveSpeed = 3000;
				}
				else if (hookPoint.MoveSpeed < 6000)
				{
					hookPoint.MoveSpeed = 6000;
				}
			}
		}
	}
	else if (realMapName ~= "dlc_metro")
	{
		CleanUpMetro();
		
		// so the shopkeeper doesn't say "we're sold out" when the player has the ticket
		foreach DynamicActors(class'Hat_MetroTicketBooth_Base', booth)
		{
			booth.WasBought = false;
			booth.UnlockView = None;
		}
		
		shopInvs = class'Hat_ClassHelper'.static.GetAllObjectsExpensive("Hat_ShopInventory");
		dummy.CollectibleClass = class'Archipelago_ShopItem_Dummy';
		dummy.ItemCost = 99999999;
		
		for (i = 0; i < shopInvs.Length; i++)
		{
			if (shopInvs[i].IsA('Archipelago_ShopInventory_Base')
			|| shopInvs[i].IsA('Hat_ShopInventory_MetroFood'))
				continue;
		
			Hat_ShopInventory(shopInvs[i]).ItemsForSale.AddItem(dummy);
		}
		
		foreach DynamicActors(class'Hat_NPC', npc)
		{
			if (npc.IsA('Hat_NPC_NyakuzaShop'))
				ConsoleCommand("set " $npc.Name $" SoldOut false");
		}
	}
	else if (realMapName ~= "subconforest")
	{
		// If act rando or contracts are shuffled, remove these act transitions for the well/manor if we don't enter from the proper act.
		// This forces the player to find the act/contracts in order to enter them
		if (SlotData.ActRando || SlotData.ShuffleActContracts)
		{
			DebugMessage("Disabling trigger volumes...");
			
			foreach AllActors(class'TriggerVolume', trigger)
			{
				if (trigger.Name == 'TriggerVolume_26' && `GameManager.GetCurrentAct() != 2
				|| trigger.Name == 'TriggerVolume_20' && `GameManager.GetCurrentAct() != 4)
				{
					DebugMessage("Disabling trigger volume: "$trigger.Name);
					trigger.ShutDown();
				}
				
				// If contracts are shuffled, disable the bag trap trigger if we already checked the Subcon Well contract
				if (SlotData.ShuffleActContracts && trigger.Name == 'TriggerVolume_4')
				{
					if (SlotData.CheckedContracts.Find(class'Hat_SnatcherContract_IceWall') != -1)
					{
						DebugMessage("Disabling trigger volume: "$trigger.Name);
						trigger.ShutDown();
					}
				}
			}
		}
		
		if (SlotData.ShuffleSubconPaintings)
		{
			foreach DynamicActors(class'Hat_SubconPainting', painting)
			{
				if (!HasAPBit(string(painting.Name), 1))
				{
					painting.SetHidden(true);
					painting.SetCollision(false, false);
				}
			}
		}
	}
	
	WorldInfo.GetGameSequence().FindSeqObjectsByClass(class'Hat_SeqAct_ClearContractObjective', true, seqObjects);
	for (i = 0; i < seqObjects.Length; i++)
	{
		Hat_SeqAct_ClearContractObjective(seqObjects[i]).ContractClass = None;
	}
	
	if (SlotData.DeathWish)
	{
		ConsoleCommand("set hat_snatchercontract_deathwish_riftcollapse PenaltyWaitTimeInSeconds 0");
		ConsoleCommand("set hat_snatchercontract_deathwish_riftcollapse Condition_3Lives false");
		ConsoleCommand("set hat_snatchercontract_deathwish neverobscureobjectives true");
		if (`SaveManager.GetNumberOfTimePieces() >= SlotData.DeathWishTPRequirement)
		{
			if (!class'Hat_SaveBitHelper'.static.HasLevelBit("DeathWish_intro", 1, `GameManager.HubMapName))
			{
				ScreenMessage("***DEATH WISH has been unlocked! Check your pause menu in the Spaceship!***", 'Warning');
				ScreenMessage("***DEATH WISH has been unlocked! Check your pause menu in the Spaceship!***", 'Warning');
				ScreenMessage("***DEATH WISH has been unlocked! Check your pause menu in the Spaceship!***", 'Warning');
			}
			
			class'Hat_SaveBitHelper'.static.SetLevelBits("DeathWish_intro", 1, `GameManager.HubMapName);
		}
		
		if (class'Hat_SnatcherContract_DeathWish'.static.IsAnyActive(true))
		{
			SetTimer(0.5, true, NameOf(CheckDeathWishObjectives));
			if (class'Hat_SnatcherContract_DeathWish_Speedrun_SubWell'.static.IsActive())
			{
				foreach DynamicActors(class'Hat_BonfireBarrier', barrier)
				{
					barrier.SetHidden(true);
					barrier.SetCollision(false, false);
				}
			}
			
			if (class'Hat_SnatcherContract_DeathWish_Speedrun_Illness'.static.IsActive()
				|| class'Hat_SnatcherContract_DeathWish_NiceBirdhouse'.static.IsActive())
			{
				foreach DynamicActors(class'Hat_SandStationHorn_Base', horn)
				{
					if (horn.IsActivated)
						continue;
						
					horn.IsActivated = true;
					horn.PostTargetUnlocks();
				}
			}
			
			// No Zero Jumps in Boss Rush, too easy
			if (class'Hat_SnatcherContract_DeathWish_BossRush'.static.IsActive())
			{
				if (class'Hat_SnatcherContract_DeathWish_NoAPresses'.static.IsActive())
				{
					Hat_SaveGame(`SaveManager.SaveData).ActiveDeathWishes.RemoveItem(class'Hat_SnatcherContract_DeathWish_NoAPresses');
				}
			}
		}
		
		DeathWishes = class'Hat_ClassHelper'.static.GetAllScriptClasses("Hat_SnatcherContract_DeathWish");
		for (i = 0; i < DeathWishes.Length; i++)
		{
			dw = class<Hat_SnatcherContract_DeathWish>(DeathWishes[i]);
			if (dw.default.CompletionReward == None)
				continue;
				
			flair = class<Hat_CosmeticItemQualityInfo>(dw.default.CompletionReward);
			if (flair == None)
				continue;
			
			// Remove Death Wish flair rewards if we don't have the base hat, since the game doesn't bother checking if you have it.
			if (!class'Hat_Loadout'.static.BackpackHasInventory(flair.static.GetBaseCosmeticItemWeApplyTo()))
			{
				ConsoleCommand("set "$dw $" CompletionReward None");
			}
		}
	}
	
	if (class'Hat_SnatcherContract_DeathWish'.static.IsAnyActive(false))
	{
		foreach DynamicActors(class'Hat_SubconPainting', painting)
			painting.Destroy();
		
		foreach DynamicActors(class'Actor', a)
		{
			if (a.IsA('Hat_SnatcherContractSummon') || a.IsA('Hat_NPC_Bullied') || a.IsA('Hat_TimeRiftPortal'))
				a.Destroy();
			
			if (realMapName ~= "subconforest" && a.IsA('Hat_InteractiveFoliage_HarborBush'))
			{
				if (a.Name == 'Hat_InteractiveFoliage_HarborBush_2' || a.Name == 'Hat_InteractiveFoliage_HarborBush_3')
					a.Destroy();
			}
		}
		
		foreach DynamicActors(class'Hat_ImpactInteract_Breakable_ChemicalBadge', crate)
		{
			for (i = 0; i < crate.Rewards.Length; i++)
			{
				if (class<Hat_Collectible_Important>(crate.Rewards[i]) != None
					|| class<Archipelago_RandomizedItem_Base>(crate.Rewards[i]) != None)
				{
					crate.Destroy();
					continue;
				}
			}
		}
	}
	
	if (SlotData.UmbrellaLogic)
	{
		ReplaceUnarmedWeapon();
	}
	
	ctr = Hat_PlayerController(GetALocalPlayerController());
	save = `SaveManager.GetCurrentSaveData();
	
	// If we load a new save file with at least 1 time piece, the game will force the umbrella into our inventory.
	for (i = 0; i < save.MyBackpack2017.Weapons.Length; i++)
	{
		item = save.MyBackpack2017.Weapons[i];
		if (item != None)
		{
			if (class<Hat_Weapon_Umbrella>(item.BackpackClass) != None 
			&& class<Archipelago_Weapon_Umbrella>(item.BackpackClass) == None)
			{
				ctr.MyLoadout.RemoveBackpack(item);
			}
		}
	}
	
	if (SlotData.Initialized)
		UpdateChapterInfo();
	
	for (i = 0; i < SlotData.ObtainedContracts.Length; i++)
	{
		// these occasionally get wiped for some reason
		SlotData.ObtainedContracts[i].static.UnlockActs(save);
	}
	
	// Remove our dummy contracts from earlier.
	if (save.SnatcherContracts.Find(class'Archipelago_SnatcherContract_Dummy1') != -1)
	{
		save.SnatcherContracts.RemoveItem(class'Archipelago_SnatcherContract_Dummy1');
	}
	
	if (save.SnatcherContracts.Find(class'Archipelago_SnatcherContract_Dummy2') != -1)
	{
		save.SnatcherContracts.RemoveItem(class'Archipelago_SnatcherContract_Dummy2');
	}
	
	if (SlotData != None && SlotData.Initialized)
	{
		// Restore any taken contracts if they're still in the list for some reason
		if (SlotData.TakenContracts.Length > 0)
			OnContractEventEnd();
		
		// Check for new contracts
		if (SlotData.ShuffleActContracts)
			SetTimer(1.0, true, NameOf(CheckForNewContracts));
	}
	
	SetTimer(2.0, true, NameOf(FixInventoryIssues));
	if (Client == None)
		CreateClient();
}

function RumbiHitCheckTimer(Actor rumbi)
{
	if (rumbi.IsInState('DamageFlip'))
	{
		SendLocationCheck(RumbiYarnCheck);
		ClearTimer(NameOf(RumbiHitCheckTimer));
	}
}

function SubconBushCheckTimer(Actor bush)
{
	local Actor yarnBush, magnetBush;
	yarnBush = FindActorByName('Hat_InteractiveFoliage_HarborBush_2');
	magnetBush = FindActorByName('Hat_InteractiveFoliage_HarborBush_3');
	if (HasAPBit("SubconBush1", 1) && HasAPBit("SubconBush2", 1))
	{
		ClearTimer(NameOf(SubconBushCheckTimer));
	}
	else
	{
		if (yarnBush == None && !HasAPBit("SubconBush1", 1))
		{
			SendLocationCheck(SubconBushCheck1);
			SetAPBits("SubconBush1", 1);
		}
		
		if (magnetBush == None && !HasAPBit("SubconBush2", 1))
		{
			SendLocationCheck(SubconBushCheck2);
			SetAPBits("SubconBush2", 1);
		}
	}
}

function ForceTourTimeRift(Actor a)
{
	ConsoleCommand("set "$a.Name $" Enabled true");
	ConsoleCommand("set "$a.Name $" ForceEnable true");
	a.SetHidden(false);
}

function ForceLightsOn()
{
	local Light li;
	local PostProcessVolume vol;
	foreach AllActors(class'Light', li)
	{
		li.LightComponent.SetEnabled(true);
		li.bEnabled = true;
	}
	
	vol = PostProcessVolume(FindActorByName('PostProcessVolume_1'));
	if (vol != None)
	{
		vol.bEnabled = false;
	}
}

function Actor FindActorByName(Name n, optional bool dynamic)
{
	local Actor a;
	if (dynamic)
	{
		foreach DynamicActors(class'Actor', a)
		{
			if (a.Name == n)
			{
				return a;
			}
		}
	}
	else
	{
		foreach AllActors(class'Actor', a)
		{
			if (a.Name == n)
			{
				return a;
			}
		}
	}
}

function FixInventoryIssues()
{
	local Hat_Loadout lo;
	
	if (SlotData == None || !SlotData.Initialized)
		return;
	
	lo = Hat_PlayerController(GetALocalPlayerController()).MyLoadout;
	if (lo == None)
		return;
	
	if (SlotData.StartWithCompassBadge || HasAPBit("Archipelago_Ability_ItemFinder", 1))
	{
		if (!lo.BackpackHasInventory(class'Archipelago_Ability_ItemFinder'))
			lo.AddBackpack(lo.MakeBackpackItem(class'Archipelago_Ability_ItemFinder'));
	}
	
	if (HasAPBit("Archipelago_Weapon_Umbrella", 1) && !lo.BackpackHasInventory(class'Archipelago_Weapon_Umbrella'))
	{
		lo.AddBackpack(lo.MakeBackpackItem(class'Archipelago_Weapon_Umbrella'), true);
	}
	else if (HasAPBit("Archipelago_Weapon_BaseballBat", 1) && !lo.BackpackHasInventory(class'Archipelago_Weapon_BaseballBat'))
	{
		lo.AddBackpack(lo.MakeBackpackItem(class'Archipelago_Weapon_BaseballBat'), true);
	}
}

function OnPostLevelIntro()
{
	if (!IsArchipelagoEnabled())
		return;
	
	if (`GameManager.GetCurrentMapFilename() ~= "dlc_metro")
		SetTimer(0.1, false, NameOf(CleanUpMetro));
}

function HideItems()
{
	local Hat_Collectible_Important a;
	local bool deathWish;
	
	deathWish = class'Hat_SnatcherContract_DeathWish'.static.IsAnyActive(false);
	foreach DynamicActors(class'Hat_Collectible_Important', a)
	{
		if (a.IsA('Hat_Collectible_VaultCode_Base') || a.IsA('Hat_Collectible_Sticker')
			|| a.IsA('Hat_Collectible_MetroTicket_Base'))
			continue;
		
		if (a.IsA('Hat_Collectible_InstantCamera'))
		{
			a.Destroy();
			continue;
		}
		
		// Hide all regular collectibles, just in case
		DebugMessage("Removing " $a.Name);
		
		if (deathWish) // no items in Death Wish
			a.Destroy();
		else
			a.ShutDown();
	}
}

function bool DoesPlayerReallyHaveContract(class<Hat_SnatcherContract_Act> contract)
{
	return SlotData.ObtainedContracts.Find(contract) != -1;
}

function CheckForNewContracts()
{
	local int i, j, id;
	local Hat_SaveGame save;
	local Actor a;
	save = `SaveManager.GetCurrentSaveData();
	
	for (i = 0; i < save.SnatcherContracts.Length; i++)
	{
		if (save.SnatcherContracts[i] == None 
		|| !ContractEventActive && DoesPlayerReallyHaveContract(save.SnatcherContracts[i])
		|| SlotData.CheckedContracts.Find(save.SnatcherContracts[i]) != -1)
			continue;
		
		// We don't have this contract. Remove it and send the check for it.
		for (j = 0; j < save.SnatcherContracts[i].default.UnlockActIDs.Length; j++)
		{
			class'Hat_SaveBitHelper'.static.RemoveLevelBit("contract_unlock_actid", save.SnatcherContracts[i].default.UnlockActIDs[j], "subconforest");
		}
		
		id = class'Archipelago_ItemInfo'.static.GetContractID(save.SnatcherContracts[i]);
		DebugMessage("Sending contract as location: " $save.SnatcherContracts[i] $" ID: " $id);
		SendLocationCheck(id);
		
		SlotData.CheckedContracts.AddItem(save.SnatcherContracts[i]);
		save.SnatcherContracts.RemoveItem(save.SnatcherContracts[i]);
	}
	
	if (!TrapsDestroyed)
	{
		if (SlotData.CheckedContracts.Find(class'Hat_SnatcherContract_Toilet') != -1
		&& SlotData.CheckedContracts.Find(class'Hat_SnatcherContract_Vanessa') != -1
		&& SlotData.CheckedContracts.Find(class'Hat_SnatcherContract_MailDelivery') != -1)
		{
			foreach DynamicActors(class'Actor', a)
			{
				if (a.IsA('Hat_SnatcherContractSummon'))
					a.Destroy();
			}
			
			TrapsDestroyed = true;
		}
	}
}

function OpenConnectBubble(optional float delay=0.0)
{
	local Archipelago_HUDElementBubble bubble;
	local Hat_HUD hud;
	
	if (delay > 0.0)
	{
		SetTimer(delay, false, NameOf(OpenConnectBubble));
		return;
	}
	
	hud = Hat_HUD(Hat_PlayerController(GetALocalPlayerController()).MyHUD);
	bubble = Archipelago_HUDElementBubble(hud.OpenHUD(class'Archipelago_HUDElementBubble'));
	bubble.OpenInputText(hud, "Please enter the IP:Port of the AHITClient (localhost:11311 by default, NOT archipelago.gg). If you do not have the AHITClient, consult the setup guide.", class'Hat_ConversationType_Regular', 'a', 25);
}

function KeepConnectionAlive()
{
	local string message;
	if (!IsFullyConnected())
		return;
	
	message = "[{`cmd`:`Bounce`,`slots`:["$SlotData.PlayerSlot$"]}]";
	message = Repl(message, "`", "\"");
	client.SendBinaryMessage(message);
}

// Called by client the moment a "Connected" packet is received from the Archipelago server.
// Slot data is not available at this point.
function OnPreConnected()
{
	
}

// Called by client when fully connected to Archipelago
// All slot data should be available at this point.
function OnFullyConnected()
{
	local int i;
	local string json, dwClasses;
	local class<Hat_SnatcherContract_DeathWish> dw;
	local array<class< Object> > dws;
	
	SetTimer(0.5, false, NameOf(ShuffleCollectibles));
	UpdateChapterInfo();
	UpdateCurrentMap();
	
	// Have we beaten our seed? Send again in case we somehow weren't connected before.
	if (HasAPBit("HasBeatenGame", 1))
	{
		BeatGame();
	}
	
	// resend any locations we checked while not connected
	class'Engine'.static.BasicLoadObject(ItemResender, "APSlotData/item_resender"$`SaveManager.GetCurrentSaveData().CreationTimeStamp, false, 1);
	SetTimer(2.0, true, NameOf(ResendLocations));
	
	for (i = 0; i < SlotData.ShopItemList.Length; i++)
	{
		if (SlotData.ShopItemList[i].ItemClass.default.DisplayName == "Unknown Item")
			InitShopItemDisplayName(SlotData.ShopItemList[i].ItemClass);
	}
	
	// Call this just to see if we can craft a hat
	OnYarnCollected(0);
	
	if (IsOnlineParty())
	{
		SendOnlinePartyCommand(SlotData.Seed$"+"$SlotData.PlayerSlot, 'APSeedCheck', GetALocalPlayerController().Pawn);
	}
	
	if (SlotData.ShuffleActContracts)
	{
		// The bag trap in Subcon Forest perma-locks if player has Subcon Well contract. Send the location if we enter Act 1 with it.
		if (SlotData.ObtainedContracts.Find(class'Hat_SnatcherContract_IceWall') != -1 && !IsLocationChecked(2000300200) 
		&& `GameManager.GetCurrentMapFilename() == "subconforest" && `GameManager.IsCurrentAct(1))
		{
			SendLocationCheck(2000300200);
		}
	}
	
	// The Hookshot Badge chest in Subcon Well opens itself if the player has Hookshot Badge, leaving the check unobtainable
	if (`GameManager.GetCurrentMapFilename() == "subcon_cave" && !class'Hat_SnatcherContract_DeathWish'.static.IsAnyActive(false)
		&& Hat_PlayerController(GetALocalPlayerController()).MyLoadout.BackpackHasInventory(class'Hat_Ability_Hookshot')
		&& !IsLocationChecked(2000324114))
	{
		SendLocationCheck(2000324114);
	}
	
	json = "[{`cmd`:`Get`,`keys`:[`ahit_clearedacts_"$SlotData.PlayerSlot$"`]}]";
	json = Repl(json, "`", "\"");
	client.SendBinaryMessage(json);
	
	if (SlotData.DeathWish)
	{
		dws = class'Hat_ClassHelper'.static.GetAllScriptClasses("Hat_SnatcherContract_DeathWish");
		for (i = 0; i < dws.Length; i++)
		{
			dw = class<Hat_SnatcherContract_DeathWish>(dws[i]);
			if (dw == class'Hat_SnatcherContract_DeathWish'
			|| dw == class'Hat_SnatcherContract_ChallengeRoad')
				continue;
			
			if (SlotData.ExcludedContracts.Find(dw) != -1 || SlotData.DeathWishShuffle && SlotData.ShuffledDeathWishes.Find(dw) == -1)
				continue;
			
			if (dw.static.IsContractPerfected())
				continue;
			
			if (dwClasses == "")
			{
				dwClasses $= "["$"`"$dw$"_"$SlotData.PlayerSlot$"`";
			}
			else
			{
				dwClasses $= ","$"`"$dw$"_"$SlotData.PlayerSlot$"`";
			}
		}
		
		if (dwClasses != "")
		{
			dwClasses $= "]";
			json = "[{`cmd`:`Get`,`keys`:"$dwClasses$"}]";
			json = Repl(json, "`", "\"");
			client.SendBinaryMessage(json);
		}
		
		for (i = 0; i < SlotData.PendingCompletedDeathWishes.Length; i++)
		{
			UpdateCompletedDeathWishes(SlotData.PendingCompletedDeathWishes[i]);
		}
		
		SlotData.PendingCompletedDeathWishes.Length = 0;
	}
	
	for (i = 0; i < SlotData.PendingCompletedActs.Length; i++)
	{
		UpdateCompletedActs(SlotData.PendingCompletedActs[i]);
	}
	
	SlotData.PendingCompletedActs.Length = 0;
	SetTimer(180.0, true, NameOf(KeepConnectionAlive));
}

function UpdateCurrentMap()
{
	local String json;
	
	if (!IsFullyConnected())
		return;
	
	json = "[{`cmd`:`Set`,`default`:``,`key`:`ahit_currentmap_"$SlotData.PlayerSlot;
	json $= "`,`operations`:[{`operation`:`replace`,`value`:`"$`GameManager.GetCurrentMapFilename()$"`}]}]";
	json = Repl(json, "`", "\"");
	client.SendBinaryMessage(json);
}

event OnOnlinePartyCommand(string Command, Name CommandChannel, Hat_GhostPartyPlayerStateBase Sender)
{
	local Actor a;
	local int slot, i, locId;
	local bool isLive;
	local JsonObject locSync, actSync, dwSync;
	local class<Hat_SnatcherContract_DeathWish> dw;
	local array<Hat_ChapterInfo> chapterInfoArray;
	local String hourglass, map, seed;
	local array<string> hourglasses;
	local Hat_ChapterInfo chapter;
	local Hat_ChapterActInfo act;
	
	if (CommandChannel != 'APSeedCheck' && Buddies.Find(Sender) == -1)
		return;
	
	if (CommandChannel == 'APSeedCheck')
	{
		slot = int(Split(Command, "+", true));
		seed = Repl(Command, "+"$slot, "");
		
		if (SlotData.Seed ~= seed && SlotData.PlayerSlot == slot || Command == "MatchingSeed")
		{
			// If we have a matching seed and slot number, add this guy to our list of valid buddies.
			if (Buddies.Find(Sender) == -1)
			{
				DebugMessage("Adding Online Party buddy: " $Sender.GetDisplayName());
				Buddies.AddItem(Sender);
			}
			
			if (Command == "MatchingSeed")
			{
				// Sync all locations/acts
				PartySyncLocations(SlotData.CheckedLocations, Sender);
				
				chapterInfoArray = class'Hat_ChapterInfo'.static.GetAllChapterInfo();
				foreach chapterInfoArray(chapter)
				{
					chapter.ConditionalUpdateActList();
					foreach chapter.ChapterActInfo(act)
					{
						if (act.hourglass == "" || !IsActReallyCompleted(act))
							continue;
						
						hourglasses.AddItem(act.hourglass);
					}
				}
				
				PartySyncActs(hourglasses, Sender);
			}
			else 
			{
				// send response to let our buddy know we have a matching seed
				SendOnlinePartyCommand("MatchingSeed", 'APSeedCheck', GetALocalPlayerController().Pawn, Sender);
			}
		}
	}
	else if (CommandChannel == 'APLocationSync')
	{
		locSync = class'JsonObject'.static.DecodeJson(Command);
		isLive = locSync.GetBoolValue("IsLive");
		map = `GameManager.GetCurrentMapFilename();
		
		i = 0;
		while (locSync.GetIntValue(string(i)) > 0)
		{
			locId = locSync.GetIntValue(string(i));
			if (!IsLocationChecked(locId))
			{
				SlotData.CheckedLocations.AddItem(locId);
				if (IsLive && map == Sender.CurrentMapName)
				{
					a = LocationIdToObject(locId, class'Archipelago_RandomizedItem_Base');
					if (a != None)
					{
						a.Destroy();
					}
					else
					{
						a = LocationIdToObject(locId, class'Hat_TreasureChest_Base');
						if (a != None && !Hat_TreasureChest_Base(a).Opened
							&& class<Hat_Collectible_StoryBookPage>(Hat_TreasureChest_Base(a).Content) == None)
						{
							Hat_TreasureChest_Base(a).Empty();
						}
					}
				}
				
				DebugMessage("Syncing location" $locId $" from " $Sender.GetDisplayName());
			}
			
			i++;
		}
	}
	else if (CommandChannel == 'APActSync')
	{
		i = 0;
		actSync = class'JsonObject'.static.DecodeJson(Command);
		
		while (actSync.GetStringValue(string(i)) != "")
		{
			hourglass = actSync.GetStringValue(string(i));
			
			if (!HasAPBit("ActComplete_"$hourglass, 1))
			{
				SetAPBits("ActComplete_"$hourglass, 1);
				DebugMessage("Syncing act" $hourglass $" from " $Sender.GetDisplayName());
			}
			
			act = GetChapterActInfoFromHourglass(hourglass);
			if (act != None && IsPurpleRift(act))
			{
				`SaveManager.GetCurrentSaveData().UnlockSecretLevel(hourglass);
			}
			
			i++;
		}
	}
	else if (CommandChannel == 'APDeathWishStamps')
	{
		dwSync = class'JsonObject'.static.DecodeJson(Command);
		dw = class<Hat_SnatcherContract_DeathWish>(class'Hat_ClassHelper'.static.ClassFromName(dwSync.GetStringValue("DeathWishClass")));
		for (i = 0; i <= 2; i++)
		{
			if (dwSync.GetBoolValue(string(i)))
				dw.static.ForceUnlockObjective(i);
		}
	}
	else if (CommandChannel == 'APDeathLink')
	{
		ScreenMessage(Command);
		DeathLinked = true;
		KillEveryone();
	}
	
	SaveGame();
	locSync = None;
	actSync = None;
	dwSync = None;
}

function ResendLocations()
{
	if (ItemResender != None)
	{
		ItemResender.ResendLocations();
	}
}

function LoadSlotData(JsonObject json)
{
	local array<Hat_ChapterInfo> chapters;
	local array<Hat_ChapterActInfo> acts;
	local ShuffledAct actShuffle;
	local string n, hg, itemName;
	local int i, j, v, id;
	local class<Hat_SnatcherContract_DeathWish> dw;
	local JsonObject shopNames;
	local array<class<Object > > shopItemClasses;
	local class<Object> shopItem;
	local ShopItemName shopName;
	
	if (SlotData.Initialized)
		return;
	
	SlotData.ConnectedOnce = true;
	SlotData.Goal = json.GetIntValue("EndGoal");
	SlotData.TotalLocations = json.GetIntValue("TotalLocations");
	SlotData.LogicDifficulty = json.GetIntValue("LogicDifficulty");
	SlotData.ActRando = json.GetBoolValue("ActRandomizer");
	SlotData.StartWithCompassBadge = json.GetBoolValue("StartWithCompassBadge");
	SlotData.ShuffleStorybookPages = json.GetBoolValue("ShuffleStorybookPages");
	SlotData.ShuffleActContracts = json.GetBoolValue("ShuffleActContracts");
	SlotData.ShuffleZiplines = json.GetBoolValue("ShuffleAlpineZiplines");
	SlotData.UmbrellaLogic = json.GetBoolValue("UmbrellaLogic");
	SlotData.ShuffleSubconPaintings = json.GetBoolValue("ShuffleSubconPaintings");
	SlotData.NoPaintingSkips = json.GetBoolValue("NoPaintingSkips");
	SlotData.CTRLogic = json.GetIntValue("CTRLogic");
	SlotData.DeathLink = json.GetBoolValue("death_link");
	SlotData.DeathLinkAmnesty = json.GetIntValue("death_link_amnesty");
	SlotData.DWDeathLinkAmnesty = json.GetIntValue("dw_death_link_amnesty");
	SlotData.Seed = json.GetStringValue("SeedNumber");
	SlotData.SeedName = json.GetStringValue("SeedName");
	SlotData.HatItems = json.GetBoolValue("HatItems");
	SlotData.CompassBadgeMode = json.GetIntValue("CompassBadgeMode");
	SlotData.Chapter1Cost = json.GetIntValue("Chapter1Cost");
	SlotData.Chapter2Cost = json.GetIntValue("Chapter2Cost");
	SlotData.Chapter3Cost = json.GetIntValue("Chapter3Cost");
	SlotData.Chapter4Cost = json.GetIntValue("Chapter4Cost");
	SlotData.Chapter5Cost = json.GetIntValue("Chapter5Cost");
	SlotData.DLC1 = json.GetBoolValue("EnableDLC1");
	SlotData.DLC2 = json.GetBoolValue("EnableDLC2");
	shopNames = json.GetObject("ShopItemNames");
	shopItemClasses = class'Hat_ClassHelper'.static.GetAllScriptClasses("Archipelago_ShopItem_Base");
	foreach shopItemClasses(shopItem)
	{
		id = class<Archipelago_ShopItem_Base>(shopItem).default.LocationID;
		if (id <= 0)
			continue;
		
		itemName = shopNames.GetStringValue(string(id));
		if (itemName != "")
		{
			shopName.ID = id;
			shopName.ItemName = itemName;
			SlotData.ShopItemNames.AddItem(shopName);
		}
	}

	if (SlotData.DLC1)
	{
		SlotData.Chapter6Cost = json.GetIntValue("Chapter6Cost");
		SlotData.ShipShapeCustomTaskGoal = json.GetIntValue("ShipShapeCustomTaskGoal");
		SlotData.Tasksanity = json.GetBoolValue("Tasksanity");
		SlotData.ExcludeTour = json.GetBoolValue("ExcludeTour");
		
		if (SlotData.Tasksanity)
		{
			SlotData.TasksanityTaskStep = json.GetIntValue("TasksanityTaskStep");
			SlotData.TasksanityCheckCount = json.GetIntValue("TasksanityCheckCount");
		}
	}
	
	if (SlotData.DLC2)
	{
		SlotData.Chapter7Cost = json.GetIntValue("Chapter7Cost");
		SlotData.NoTicketSkips = json.GetIntValue("NoTicketSkips");
		for (i = 0; i < ThugCatShops.Length; i++)
		{
			// Set shop item count as level bit
			DebugMessage(ThugCatShops[i] $" THUG SHOP COUNT: "$json.GetIntValue(ThugCatShops[i]));
			SetAPBits(ThugCatShops[i], json.GetIntValue(ThugCatShops[i]));
		}
		
		SlotData.MetroMinPonCost = json.GetIntValue("MetroMinPonCost");
		SlotData.MetroMaxPonCost = json.GetIntValue("MetroMaxPonCost");
		SlotData.MetroMinPonCost = Min(SlotData.MetroMinPonCost, SlotData.MetroMaxPonCost);
		SlotData.MetroMaxPonCost = Max(SlotData.MetroMinPonCost, SlotData.MetroMaxPonCost);
	}
	
	SlotData.DeathWish = json.GetBoolValue("EnableDeathWish");
	if (SlotData.DeathWish)
	{
		SlotData.BonusRewards = json.GetBoolValue("DWEnableBonus");
		SlotData.AutoCompleteBonuses = json.GetBoolValue("DWAutoCompleteBonuses");
		SlotData.DeathWishTPRequirement = json.GetIntValue("DWTimePieceRequirement");
		SlotData.DeathWishShuffle = json.GetBoolValue("DWShuffle");
		if (SlotData.DeathWishShuffle)
		{
			for (i = 0; i <= 99; i++)
			{
				n = json.GetStringValue("dw_"$i);
				if (n == "")
					break;

				dw = class<Hat_SnatcherContract_DeathWish>(class'Hat_ClassHelper'.static.ClassFromName(n));
				if (dw == None)
				{
					ScreenMessage("Invalid Death Wish class: " $n $", please report", 'Warning');
					continue;
				}
				
				SlotData.ShuffledDeathWishes.AddItem(dw);
			}
		}
		
		for (i = 0; i <= 99; i++)
		{
			n = json.GetStringValue("excluded_dw"$i);
			if (n == "")
				break;
			
			dw = class<Hat_SnatcherContract_DeathWish>(class'Hat_ClassHelper'.static.ClassFromName(n));
			if (dw == None)
			{
				ScreenMessage("Invalid Death Wish class: " $n $", please report", 'Warning');
				continue;
			}
			
			SlotData.ExcludedContracts.AddItem(dw);
		}
		
		for (i = 0; i <= 99; i++)
		{
			n = json.GetStringValue("excluded_bonus"$i);
			if (n == "")
				break;
			
			dw = class<Hat_SnatcherContract_DeathWish>(class'Hat_ClassHelper'.static.ClassFromName(n));
			if (dw == None)
			{
				ScreenMessage("Invalid Death Wish class: " $n $", please report", 'Warning');
				continue;
			}
			
			SlotData.ExcludedBonuses.AddItem(dw);
		}
		
		SlotData.DeathWishOnly = json.GetBoolValue("DeathWishOnly");
		if (SlotData.DeathWishOnly)
		{
			class'Hat_SaveBitHelper'.static.SetLevelBits("DeathWish_intro", 1, `GameManager.HubMapName);
			UnlockAlmostEverything();
		}
	}
	
	SlotData.BaseballBat = json.GetBoolValue("BaseballBat");
	
	SlotData.SprintYarnCost = json.GetIntValue("SprintYarnCost");
	SlotData.BrewingYarnCost = json.GetIntValue("BrewingYarnCost");
	SlotData.IceYarnCost = json.GetIntValue("IceYarnCost");
	SlotData.DwellerYarnCost = json.GetIntValue("DwellerYarnCost");
	SlotData.TimeStopYarnCost = json.GetIntValue("TimeStopYarnCost");
	
	SlotData.BadgeSellerItemCount = json.GetIntValue("BadgeSellerItemCount");
	SlotData.MinPonCost = json.GetIntValue("MinPonCost");
	SlotData.MaxPonCost = json.GetIntValue("MaxPonCost");
	SlotData.MinPonCost = Min(SlotData.MinPonCost, SlotData.MaxPonCost);
	SlotData.MaxPonCost = Max(SlotData.MinPonCost, SlotData.MaxPonCost);
	
	// hat stitch order
	SlotData.Hat1 = EHatType(json.GetIntValue("Hat1"));
	SlotData.Hat2 = EHatType(json.GetIntValue("Hat2"));
	SlotData.Hat3 = EHatType(json.GetIntValue("Hat3"));
	SlotData.Hat4 = EHatType(json.GetIntValue("Hat4"));
	SlotData.Hat5 = EHatType(json.GetIntValue("Hat5"));
	
	if (SlotData.ActRando)
	{
		chapters = class'Hat_ChapterInfo'.static.GetAllChapterInfo();
		
		for (i = 0; i < chapters.Length; i++)
		{
			chapters[i].ConditionalUpdateActList();
			for (j = 0; j < chapters[i].ChapterActInfo.Length; j++)
				acts.AddItem(chapters[i].ChapterActInfo[j]);
		}
		
		// Note: HasKey() doesn't work at all
		for (v = 0; v < acts.Length; v++)
		{
			if (IsActFreeRoam(acts[v]))
			{
				if (acts[v].ChapterInfo.ChapterID == 4)
				{
					hg = "AlpineFreeRoam";
				}
				else if (SlotData.DLC2 && acts[v].ChapterInfo.ChapterID == 7)
				{
					hg = "MetroFreeRoam";
				}
			}
			else
			{
				hg = acts[v].Hourglass;
			}
			
			// This is what our act is being replaced with
			n = json.GetStringValue(hg);
			if (n != "")
			{
				if (n ~= "chapter3_secret_finale")
				{
					// Ch.2 true finale needs a special flag, since there's no unique ChapterActInfo for it
					actShuffle = CreateShuffledAct(acts[v], None);
					actShuffle.IsDeadBirdBasementShuffledAct = true;
				}
				else
				{
					actShuffle = CreateShuffledAct(acts[v], GetChapterActInfoFromHourglass(n));
				}
				
				SlotData.ShuffledActList.AddItem(actShuffle);
				DebugMessage("FOUND act pair:" $acts[v].Hourglass $"REPLACED WITH: " $n);
			}
		}
		
		// This is what the basement was replaced with
		n = json.GetStringValue("chapter3_secret_finale");
		actShuffle = CreateShuffledAct(None, GetChapterActInfoFromHourglass(n));
		actShuffle.IsDeadBirdBasementOriginalAct = true;
		if (n ~= "chapter3_secret_finale")
		{
			// Vanilla
			actShuffle.IsDeadBirdBasementShuffledAct = true;
		}
		
		SlotData.ShuffledActList.AddItem(actShuffle);
		DebugMessage("FOUND act pair:" $"chapter3_secret_finale" $"REPLACED WITH: " $n);
	}
	
	if (SlotData.UmbrellaLogic)
	{
		ReplaceUnarmedWeapon();
	}
	
	SlotData.Initialized = true;
	UpdateChapterInfo();
}

function ShuffledAct CreateShuffledAct(Hat_ChapterActInfo originalAct, Hat_ChapterActInfo newAct)
{
	local ShuffledAct actShuffle;
	actShuffle.OriginalAct = originalAct;
	actShuffle.newAct = newAct;
	return actShuffle;
}

function OnPreActSelectMapChange(Object ChapterInfo, out int ActID, out string MapName)
{
	local Hat_ChapterActInfo act, shuffled, ceremony;
	local bool basementShuffle;
	local int basement;
	
	if (!IsArchipelagoEnabled())
		return;
	
	if (SlotData.Initialized && IsInSpaceship())
	{
		SlotData.LastSpaceshipLocation = GetALocalPlayerController().Pawn.Location;
		SaveGame();
	}
	
	if (InStr(MapName, "timerift_", false, true) == 0)
		return;
	
	ActMapChange = true;
	if (!SlotData.ActRando)
	{
		if (Hat_ChapterInfo(ChapterInfo).ChapterID == 4)
		{
			if (ActID == 99)
			{
				if (class'Hat_SaveBitHelper'.static.HasLevelBit("Actless_FreeRoam_Intro_Complete", 1, "AlpsAndSails"))
				{
					ActID = 98;
				}
				
				if (class'Hat_SeqCond_IsAlpineFinale'.static.IsAlpineFinale())
					DisableAlpineFinale();
			}
			else if (ActID == 1)
			{
				EnableAlpineFinale();
			}
		}
		else if (Hat_ChapterInfo(ChapterInfo).ChapterID == 7)
		{
			// ActID 99 is intro, skip if completed
			if (ActID == 99 && HasAPBit("ActComplete_Metro_Intro", 1))
			{
				ActID = 98;
			}
			else if (ActID == 98 && !HasAPBit("ActComplete_Metro_Intro", 1))
			{
				ActID = 99;
			}
		}
		
		if (Hat_ChapterInfo(ChapterInfo).ChapterID != 2)
			return;
	}
	
	if (Hat_ChapterInfo(ChapterInfo).ChapterID == 2)
	{
		ceremony = Hat_ChapterActInfo(DynamicLoadObject(
			"hatintime_chapterinfo.BattleOfTheBirds.BattleOfTheBirds_AwardCeremony", class'Hat_ChapterActInfo'));
		
		if (MapName ~= "DeadBirdStudio")
		{
			// If we are entering the Chapter 2 true finale, force Award Ceremony if it hasn't been completed
			if (ActID == 6)
			{
				if (!IsActReallyCompleted(ceremony))
				{
					if (!SlotData.ActRando)
					{
						MapName = "dead_cinema";
						return;
					}
					else
					{
						act = ceremony;
					}
				}
				else if (SlotData.ActRando)
				{
					basementShuffle = true;
				}
			}
			else
			{
				// This is the actual Act 1
				act = Hat_ChapterInfo(ChapterInfo).GetChapterActInfoFromActID(ActID);
			}
		}
		else if (MapName ~= "dead_cinema")
		{
			// If the game wants us to go to Award Ceremony, go to the true finale instead if Award Ceremony is completed.
			// In the act randomizer, Award Ceremony is not shuffled due to this.
			if (SlotData.ActRando)
			{
				if (!IsActReallyCompleted(ceremony))
					return;
				
				basementShuffle = true; // Go to true finale shuffled act
			}
			else if (IsActReallyCompleted(ceremony))
			{
				MapName = "DeadBirdStudio"; // Go to true finale
				return;
			}
		}
		else
		{
			// Normal Chapter 2 act
			act = Hat_ChapterInfo(ChapterInfo).GetChapterActInfoFromActID(ActID);
		}
	}
	else
	{
		// Normal act
		act = Hat_ChapterInfo(ChapterInfo).GetChapterActInfoFromActID(ActID);
	}
	
	if (!SlotData.ActRando)
		return;
	
	basement = 0;
	
	// We're looking for the Chapter 2 finale's shuffled act if this is true
	if (basementShuffle)
	{
		shuffled = GetDeadBirdBasementShuffledAct(basement);
		if (basement == 1)
		{
			ActMapChangeChapter = 2;
			ActID = 6;
			MapName = "DeadBirdStudio";
			return;
		}
	}
	else
	{
		// Normal act
		shuffled = GetShuffledAct(act, basement);
	}
	
	if (shuffled == None && basement == 0)
	{
		DebugMessage("[ERROR] Failed to find shuffled act for " $act);
		ScriptTrace();
		return;
	}
	
	if (basement == 1)
	{
		ActMapChangeChapter = 2;
		ActID = 6;
		MapName = "DeadBirdStudio";
	}
	else // Normal act shuffle
	{
		ActMapChangeChapter = shuffled.ChapterInfo.ChapterID;
		ActID = shuffled.ActID;
		MapName = shuffled.MapName;
	}
	
	// Game will override it if we do it here
	SetTimer(0.01, false, NameOf(SetMapChangeChapter));

	if (shuffled.ChapterInfo.ChapterID == 4)
	{
		// Free Roam
		if (ActID == 99)
		{
			if (class'Hat_SaveBitHelper'.static.HasLevelBit("Actless_FreeRoam_Intro_Complete", 1, "AlpsAndSails"))
				ActID = 1;
			
			if (class'Hat_SeqCond_IsAlpineFinale'.static.IsAlpineFinale())
				DisableAlpineFinale();
		}
		else if (ActID == 1 && !shuffled.IsBonus)
		{
			EnableAlpineFinale();
		}
	}
	else if (shuffled.ChapterInfo.ChapterID == 7)
	{
		// ActID 99 is intro, skip if completed
		if (ActID == 99 && HasAPBit("ActComplete_Metro_Intro", 1))
		{
			ActID = 98;
		}
		else if (ActID == 98 && !HasAPBit("ActComplete_Metro_Intro", 1))
		{
			ActID = 99;
		}
	}
	
	DebugMessage("Switching act " $PathName(act) $" with act: " $PathName(shuffled) $", map:" $MapName $" Act ID: "$ActID);
}

function SetMapChangeChapter()
{
	`SaveManager.SetCurrentChapter(ActMapChangeChapter);
}

function OnMiniMissionBegin(Object MiniMission)
{
	if (!IsArchipelagoEnabled() || !SlotData.Initialized)
		return;
	
	if (Hat_MiniMissionTaskMaster(MiniMission) == None) 
		return;
	
	if (!`GameManager.IsCurrentAct(2))
		return;
	
	if (class'Hat_SnatcherContract_DeathWish_EndlessTasks'.static.IsActive(true))
		return;
	
	if (Hat_MiniMissionTaskMaster(MiniMission).MissionMode == MiniMissionTaskMaster_ScoreTarget)
		Hat_MiniMissionTaskMaster(MiniMission).ScoreTarget = SlotData.ShipShapeCustomTaskGoal;
}

function OnMiniMissionGenericEvent(Object MiniMission, String id)
{
	if (!IsArchipelagoEnabled() || !SlotData.Initialized || !SlotData.Tasksanity)
		return;
	
	if (Hat_MiniMissionTaskMaster(MiniMission) == None) 
		return;
	
	if (!`GameManager.IsCurrentAct(2))
		return;
	
	if (class'Hat_SnatcherContract_DeathWish_EndlessTasks'.static.IsActive(true))
		return;
	
	if (SlotData.CompletedTasks >= SlotData.TasksanityCheckCount)
		return;
	
	if (id == "score")
	{
		SlotData.TaskStep++;
		if (SlotData.TaskStep >= SlotData.TasksanityTaskStep)
		{
			SlotData.TaskStep = 0;
			SendLocationCheck(TasksanityIDStart + SlotData.CompletedTasks);
			SlotData.CompletedTasks++;
		}
	}
}

function OnPreOpenHUD(HUD InHUD, out class<Object> InHUDElement)
{
	local Archipelago_HUDElementLocationBanner_Metro banner;
	local Name locName;

	if (IsCurrentPatch())
		return;
	
	// These get extremely annoying as they pop up every time a new save file is present when going into the save select screen
	if (InHUDElement == class'Hat_HUDMenuDLCSplash')
		InHUDElement = None;
	
	if (!IsArchipelagoEnabled())
		return;
	
	switch (InHUDElement)
	{
		case class'Hat_HUDMenuLoadout':
			Hat_HUD(InHUD).OpenHUD(class'Archipelago_HUDElementInfoButton', , true);
			break;
		
		case class'Hat_HUDElementGhostPartyJoinAct':
			if (SlotData == None || SlotData.ActRando)
				InHUDElement = None;
			
			break;
		
		case class'Hat_HUDElementLocationBanner_Metro':
			if (`GameManager.GetCurrentMapFilename() != "dlc_metro")
				break;
			
			banner = Archipelago_HUDElementLocationBanner_Metro(Hat_HUD(InHUD).GetHUD(class'Archipelago_HUDElementLocationBanner_Metro'));
			if (banner != None)
			{
				locName = class'Hat_HUDElementLocationBanner_Metro'.static.GetNewLocationName();
				if (locName != '' && banner.LocationName == locName)
				{
					InHUDElement = None;
					break;
				}		
			}
			
			InHUDElement = class'Archipelago_HUDElementLocationBanner_Metro';
			break;
		
		case class'Hat_HUDMenuDeathWish':
			if (!SlotData.DeathWish)
				break;
			
			InHUDElement = class'Archipelago_HUDMenuDeathWish';
			break;
		
		case class'Hat_HUDElementRareStickerAlert':
			SetTimer(0.0001, false, NameOf(RemoveRareStickerAlert), self, Hat_HUD(InHUD));
			break;
		
		case class'Hat_HUDMenuShop':
			SetTimer(0.0001, false, NameOf(CheckShopOverride), self, Hat_HUD(InHUD));
			break;
		
		case class'Hat_HUDMenuActSelect':
			if (!SlotData.DeathWishOnly)
				InHUDElement = class'Archipelago_HUDMenuActSelect';
			
			break;
		
		case class'Hat_HUDElementActTitleCard':
			if (SlotData != None && SlotData.ActRando && !ActMapChange)
				SetTimer(0.0001, false, NameOf(CheckActTitleCard), self, Hat_HUD(InHUD));
			
			break;
		
		case class'Hat_HUDElementCinematic':
			SetTimer(0.1, false, NameOf(OnCutsceneStart), self, Hat_HUD(InHUD));
			break;
	
		default:
			break;
	}
}

function CheckDeathWishObjectives()
{
	local int i;
	local array< class<Hat_SnatcherContract_DeathWish> > dws;
	dws = class'Hat_SnatcherContract_DeathWish'.static.GetActiveDeathWishes();
	for (i = 0; i < dws.Length; i++)
	{
		if (dws[i].default.RequiredDLC == class'Hat_GameDLCInfo_DLC2' && !SlotData.DLC2)
			continue;
		
		if (SlotData.PerfectedDeathWishes.Find(dws[i]) != -1)
			continue;
		
		if (dws[i].static.IsContractPerfected() || dws[i].static.IsContractComplete() && SlotData.CompletedDeathWishes.Find(dws[i]) == -1)
			OnDeathWishObjectiveCompleted(dws[i]);
	}
}

function OnDeathWishObjectiveCompleted(class<Hat_SnatcherContract_DeathWish> dw)
{
	local int id;
	local array<int> locIds;
	local bool update;
	
	id = class'Archipelago_ItemInfo'.static.GetDeathWishLocationID(dw);
	if (id <= 0) // likely a mod
	{
		return;
	}
	
	if (dw.static.IsContractComplete() && SlotData.CompletedDeathWishes.Find(dw) == -1)
	{
		if (SlotData.AutoCompleteBonuses)
		{
			dw.static.SetObjectiveFailed(1, false);
			dw.static.SetObjectiveFailed(2, false);
			class'Hat_HUDElementContractObjectives'.static.TriggerContractObjectiveStatic(dw, 1);
			class'Hat_HUDElementContractObjectives'.static.TriggerContractObjectiveStatic(dw, 2);
			dw.static.ForceUnlockObjective(1);
			dw.static.ForceUnlockObjective(2);
		}
		
		if (SlotData.Goal == 3 && dw.default.class == class'Hat_SnatcherContract_DeathWish_BossRushEX')
		{
			BeatGame();
		}
		
		SlotData.CompletedDeathWishes.AddItem(dw);
		update = true;
		locIds.AddItem(id);
	}
	
	if (SlotData.AutoCompleteBonuses || dw.static.IsContractPerfected() && !dw.static.IsDeathWishEasyMode())
	{
		SlotData.PerfectedDeathWishes.AddItem(dw);
		update = true;
		
		if (SlotData.BonusRewards)
			locIds.AddItem(id+1);
	}
	
	if (locIds.Length > 0)
		SendMultipleLocationChecks(locIds);
	
	if (update)
		UpdateCompletedDeathWishes(dw);
}

function UpdateCompletedDeathWishes(class<Hat_SnatcherContract_DeathWish> dw)
{
	local JsonObject jsonObj;
	local int i;
	local string json, objs;
	
	if (IsOnlineParty())
	{
		jsonObj = new class'JsonObject';
		jsonObj.SetStringValue("DeathWishClass", string(dw));
		for (i = 0; i <= 2; i++)
		{
			if (dw.static.IsObjectiveCompleted(i))
				jsonObj.SetBoolValue(string(i), true);
		}
		
		SendOnlinePartyCommand(jsonObj.EncodeJson(jsonObj), 'APDeathWishStamps', GetALocalPlayerController().Pawn);
	}
	
	if (IsFullyConnected())
	{
		for (i = 0; i <= 2; i++)
		{
			if (dw.static.IsObjectiveCompleted(i))
			{
				objs $= i;
			}
		}
		
		json = "[{`cmd`:`Set`,`default`:``,`key`:`"$string(dw)$"_"$SlotData.PlayerSlot;
		json $= "`,`operations`:[{`operation`:`add`,`value`:`"$objs$"`}]}]";
		json = Repl(json, "`", "\"");
		client.SendBinaryMessage(json);
	}
	else if (SlotData.PendingCompletedDeathWishes.Find(dw) == -1)
	{
		SlotData.PendingCompletedDeathWishes.AddItem(dw);
	}
}

function CheckShopOverride(Hat_HUD hud)
{
	local Actor merchant;
	local Hat_MetroTicketBooth_Base booth;
	local int i;
	local array<int> hintIds;
	local Hat_HUDMenuShop shop;
	local ShopItemInfo shopInfo;
	local array<class <Object> > shopInvs;
	local Archipelago_ShopInventory_Base newShop;
	local Hat_Loadout lo;
	
	if (SlotData.DeathWishOnly)
		return;
	
	shopInvs = class'Hat_ClassHelper'.static.GetAllScriptClasses("Archipelago_ShopInventory_Base");
	shop = Hat_HUDMenuShop(hud.GetHUD(class'Hat_HUDMenuShop'));
	merchant = shop.MerchantActor;
	
	if (merchant.IsA('Hat_NPC_MetroCreepyCat_FoodShop') || merchant.IsA('Hat_NPC_MetroHelpDesk'))
		return;
	
	if (merchant.IsA('Hat_NPC_MetroCreepyCat') && !merchant.IsA('Hat_NPC_NyakuzaShop'))
	{
		foreach DynamicActors(class'Hat_MetroTicketBooth_Base', booth)
		{
			if (booth.BoothCat.Name == merchant.Name)
			{
				merchant = booth;
				break;
			}
		}
	}
	
	if (merchant.IsA('Hat_NPC_MetroCreepyCat') && !merchant.IsA('Hat_NPC_NyakuzaShop'))
		return;
	
	if (merchant.IsA('Hat_NPC_MetroTicketBooth_Base'))
		shop.PurchaseDelegates.Length = 0;
	
	for (i = 0; i < shop.ShopInventory.ItemsForSale.Length; i++)
	{
		if (shop.ShopInventory.ItemsForSale[i].CollectibleClass == class'Hat_Weapon_Nyakuza_BaseballBat')
		{
			// In the case that a Nyakuza thug rolls with 0 items for sale he will sell his default items, which are all cosmetic.
			// But we can't let the player get a free weapon by purchasing the Nyakuza bat.
			// The game already won't allow the player to purchase flairs for hats they don't have, so that's covered.
			shop.ShopInventory.ItemsForSale.Remove(i, 1);
			i--;
		}
	}
	
	for (i = 0; i < shopInvs.Length; i++)
	{
		if (class<Archipelago_ShopInventory_Base>(shopInvs[i]).default.IsBadgeSeller && merchant.IsA('Hat_NPC_BadgeSalesman')
			|| class<Archipelago_ShopInventory_Base>(shopInvs[i]).default.IsMafiaBoss && merchant.IsA('Hat_NPC_MafiaBossJar')
			|| class<Archipelago_ShopInventory_Base>(shopInvs[i]).default.ShopNPCName != ""
			&& class<Archipelago_ShopInventory_Base>(shopInvs[i]).default.ShopNPCName == string(merchant.Name))
		{
			newShop = new class<Archipelago_ShopInventory_Base>(shopInvs[i]);
			break;
		}
	}
	
	if (newShop == None)
		return;
	
	if (newShop.ShopNPCName != "")
	{
		SetAPBits("TalkedTo_"$newShop.ShopNPCName, 1);
	}
	
	for (i = 0; i < newShop.ItemsForSale.Length; i++)
	{
		GetShopItemInfo(class<Archipelago_ShopItem_Base>(newShop.ItemsForSale[i].CollectibleClass), shopInfo);
		newShop.ItemsForSale[i].ItemCost = shopInfo.PonCost;
		if (shopInfo.ItemClass.default.DisplayName == "Unknown Item")
		{
			InitShopItemDisplayName(shopInfo.ItemClass);
		}
		
		if (IsLocationChecked(shopInfo.ID))
		{
			// Someone in Online Party may have already bought this, add the collectible class so it appears as purchased
			lo = Hat_PlayerController(GetALocalPlayerController()).MyLoadout;
			if (!lo.HasCollectible(newShop.ItemsForSale[i].CollectibleClass))
			{
				lo.AddCollectible(newShop.ItemsForSale[i].CollectibleClass);
			}
			
			continue;
		}
		
		if (shopInfo.ID <= 0)
			continue;
		
		if (!shopInfo.Hinted)
		{
			if (shopInfo.ItemFlags == ItemFlag_Important || shopInfo.ItemFlags == ItemFlag_ImportantSkipBalancing)
			{
				if (hintIds.Find(shopInfo.ID) == -1)
					hintIds.AddItem(shopInfo.ID);

				SetShopInfoAsHinted(shopInfo);
			}
		}
	}
	
	if (merchant.IsA('Hat_NPC_BadgeSalesman'))
	{
		newShop.ItemsForSale.Length = SlotData.BadgeSellerItemCount;
	}
	else if (InStr(newShop.ShopNPCName, "Hat_NPC_NyakuzaShop") != -1)
	{
		newShop.ItemsForSale.Length = GetAPBits(newShop.ShopNPCName);
	}
	
	if (newShop.ItemsForSale.Length <= 0 && !merchant.IsA('Hat_NPC_BadgeSalesman'))
		return;
	
	hintIds.Length = newShop.ItemsForSale.Length;
		
	for (i = 0; i < hintIds.Length; i++)
	{
		if (hintIds[i] <= 0)
		{
			hintIds.RemoveItem(hintIds[i]);
			i--;
		}
	}
	
	if (hintIds.Length > 0)
		SendMultipleLocationChecks(hintIds, true, true);
	
	shop.SetShopInventory(hud, newShop);
}

function CheckActTitleCard(Hat_HUD hud)
{
	local string map;
	local int actId, basement, chapterId;
	local Hat_HUDElementActTitleCard card;
	local Hat_ChapterActInfo newAct;
	
	card = Hat_HUDElementActTitleCard(hud.GetHUD(class'Hat_HUDElementActTitleCard', true));
	if (card.IsNonMapChangeTitlecard || card.IsDeathWish)
		return;
	
	if (InStr(card.MapName, "timerift_", false, true) == 0)
	{
		newAct = GetShuffledAct(GetRiftActFromMapName(card.MapName), basement);
		SetAPBits("RiftEntered_"$newAct.hourglass, 1);

		if (basement == 1)
		{
			chapterId = 2;
			actId = 6;
			map = "DeadBirdStudio";
		}
		else
		{
			chapterId = newAct.ChapterInfo.ChapterID;
			map = newAct.MapName;
			actId = newAct.ActID;
		}
		
		if (chapterId == 4)
		{
			if (actId == 99)
			{
				if (class'Hat_SaveBitHelper'.static.HasLevelBit("Actless_FreeRoam_Intro_Complete", 1, "AlpsAndSails"))
					actId = 1;
				
				if (class'Hat_SeqCond_IsAlpineFinale'.static.IsAlpineFinale())
					DisableAlpineFinale();
			}
			else if (actId == 1 && !newAct.IsBonus)
			{
				EnableAlpineFinale();
			}
		}
		else if (chapterId == 7)
		{
			// ActID 99 is intro, skip if completed
			if (actId == 99 && HasAPBit("ActComplete_Metro_Intro", 1))
			{
				actId = 98;
			}
			else if (actId == 98 && !HasAPBit("ActComplete_Metro_Intro", 1))
			{
				actId = 99;
			}
		}
		
		`GameManager.LoadNewAct(chapterId, actId);
		card.MapName = map;
	}
}

function OnCutsceneStart(Hat_HUD hud)
{
	local Hat_HUDElementCinematic cutscene;
	
	cutscene = Hat_HUDElementCinematic(hud.GetHUD(class'Hat_HUDElementCinematic'));
	if (cutscene == None)
		return;
	
	// Skip Nyakuza intro cutscene manually if already watched once since it will keep replaying 
	// presumably due to not having the Metro_Intro time piece
	if (`GameManager.GetCurrentMapFilename() ~= "dlc_metro")
	{
		if (HasAPBit("MetroCutscene", 1))
		{
			cutscene.IsSkippingCinematic = 99;
		}
		
		SetAPBits("MetroCutscene", 1);
	}
}

function RemoveRareStickerAlert(Hat_HUD hud)
{
	local Hat_HUDElementRareStickerAlert alert;
	alert = Hat_HUDElementRareStickerAlert(hud.GetHUD(class'Hat_HUDElementRareStickerAlert', true));
	alert.Progress = 0.99;
}

static function bool HasZipline(EZiplineType zipline)
{
	local string id;
	
	switch (zipline)
	{
		case Zipline_Birdhouse:
			id = "Hat_SandTravelNode_44";
			break;
		
		case Zipline_LavaCake:
			id = "Hat_SandTravelNode_15";
			break;
		
		case Zipline_Windmill:
			id = "Hat_SandTravelNode_17";
			break;
		
		case Zipline_Bell:
			id = "Hat_SandTravelNode_43";
			break;
	}
	
	return HasAPBit("ZiplineUnlock_"$id, 1);
}

function ShowSeedInfoMenu()
{
	Hat_HUD(GetALocalPlayerController().MyHUD).OpenHUD(class'Archipelago_HUDMenuSeedInfo');
}

static function int GetPaintingUnlocks()
{
	return GetAPBits("PaintingUnlock");
}

function bool IsAwardCeremonyCompleted()
{
	return IsActReallyCompleted(GetChapterActInfoFromHourglass("award_ceremony"));
}

static function EnableAlpineFinale()
{
	SetAPBits("AlpineFinale", 1);
	class'Hat_SaveBitHelper'.static.SetActBits("ForceAlpineFinale", 1);
}

static function DisableAlpineFinale()
{
	SetAPBits("AlpineFinale", 0);
	class'Hat_SaveBitHelper'.static.SetActBits("ForceAlpineFinale", 0);
}

function OnTimePieceCollected(string Identifier)
{
	local int i, id;
	local Hat_ChapterActInfo currentAct;
	local string hourglass;
	local bool actless, basement, goal;
	
	if (!IsArchipelagoEnabled() || SlotData.DeathWishOnly)
		return;
	
	if (InStr(Identifier, "ap_timepiece") != -1)
		return;
	
	`SaveManager.GetCurrentSaveData().RemoveTimePiece(Identifier);
	
	if (class'Hat_SnatcherContract_DeathWish'.static.IsAnyActive(false))
		return;
	
	if (SlotData.Goal == 1 && Identifier ~= "TheFinale_FinalBoss"
		|| SlotData.Goal == 2 && Identifier ~= "Metro_Escape")
	{
		BeatGame();
		goal = true;
	}
	
	id = GetTimePieceLocationID(Identifier);
	DebugMessage("Collected Time Piece: "$Identifier $", Location ID = " $id);
	
	actless = (Identifier ~= "Alps_Birdhouse"
	|| Identifier ~= "AlpineSkyline_WeddingCake"
	|| Identifier ~= "Alpine_Twilight"
	|| Identifier ~= "AlpineSkyline_Windmill"
	|| Identifier ~= "Metro_Intro"
	|| InStr(Identifier, "Metro_Route") != -1 || InStr(Identifier, "Metro_Manhole") != -1);
	
	// We actually completed this act, so set the Time Piece ID as a level bit
	if (SlotData.ActRando)
	{
		if (actless || goal)
		{
			hourglass = Identifier;
			DebugMessage("Completed act: " $GetChapterActInfoFromHourglass(Identifier));
		}
		else
		{
			// We entered this act from a different act, set the original act's Time Piece instead
			currentAct = GetChapterActInfoFromHourglass(Identifier);
			basement = (Identifier ~= "chapter3_secret_finale");
			
			for (i = 0; i < SlotData.ShuffledActList.Length; i++)
			{
				if (!basement && SlotData.ShuffledActList[i].NewAct == currentAct 
					|| basement && SlotData.ShuffledActList[i].IsDeadBirdBasementShuffledAct)
				{
					if (!SlotData.ShuffledActList[i].IsDeadBirdBasementOriginalAct)
					{
						if (IsActFreeRoam(SlotData.ShuffledActList[i].OriginalAct))
						{
							if (IsActFreeRoam(SlotData.ShuffledActList[i].OriginalAct))
							{
								if (SlotData.ShuffledActList[i].OriginalAct.ChapterInfo.ChapterID == 4)
								{
									hourglass = "AlpineFreeRoam";
								}
								else
								{
									hourglass = "MetroFreeRoam";
								}
							}
						}
						else
						{
							hourglass = SlotData.ShuffledActList[i].OriginalAct.hourglass;
						}
					}
					else
					{
						hourglass = "chapter3_secret_finale";
					}
					
					DebugMessage("Completed act: " $SlotData.ShuffledActList[i].OriginalAct);
					break;
				}
			}
		}
		
		SetAPBits("ActComplete_"$hourglass, 1);
		UpdateCompletedActs(hourglass);
		PartySyncActs_Single(hourglass);
	}
	else
	{
		DebugMessage("Completed act: " $GetChapterActInfoFromHourglass(Identifier));
		SetAPBits("ActComplete_"$Identifier, 1);
		UpdateCompletedActs(Identifier);
		PartySyncActs_Single(Identifier);
	}
	
	if (SlotData.ActRando && hourglass == "")
	{
		DebugMessage("FAILED to find ChapterActInfo: "$Identifier);
		ScriptTrace();
	}
	
	SendLocationCheck(id);
}

function UpdateCompletedActs(string hourglass)
{
	local String json;
	
	if (!IsFullyConnected())
	{
		if (SlotData.PendingCompletedActs.Find(hourglass) == -1)
			SlotData.PendingCompletedActs.AddItem(hourglass);
		
		return;
	}
	
	json = "[{`cmd`:`Set`,`default`:[],`key`:`ahit_clearedacts_"$SlotData.PlayerSlot;
	json $= "`,`operations`:[{`operation`:`add`,`value`:[`"$hourglass$"`]}]}]";
	json = Repl(json, "`", "\"");
	client.SendBinaryMessage(json);
}

static function int GetTimePieceLocationID(string Identifier)
{
	local int id, i;
	
	// Happens to be the same as Green Clean Station
	if (Identifier ~= "Metro_Escape")
		return 2000311210;
	
	for (i = 0; i < Len(Identifier); i++)
		id += Asc(Mid(Identifier, i, 1));
	
	return id + ActCompleteIDRange;
}

function Hat_ChapterActInfo GetChapterActInfoFromHourglass(string hourglass)
{
	local array<Hat_ChapterInfo> chapterInfoArray;
	local Hat_ChapterInfo chapter;
	local Hat_ChapterActInfo act;
	
	// Special identifiers for act shuffle since Free Roam levels have no Time Piece
	if (hourglass ~= "AlpineFreeRoam")
	{
		return Hat_ChapterActInfo(DynamicLoadObject("hatintime_chapterinfo.AlpineSkyline.AlpineSkyline_IntroMountain", class'Hat_ChapterActInfo'));
	}
	else if (hourglass ~= "MetroFreeRoam")
	{
		return Hat_ChapterActInfo(DynamicLoadObject("hatintime_chapterinfo_dlc2.metro.Metro_FreeRoam", class'Hat_ChapterActInfo'));
	}
	
	chapterInfoArray = class'Hat_ChapterInfo'.static.GetAllChapterInfo();
	foreach chapterInfoArray(chapter)
	{
		chapter.ConditionalUpdateActList();
		foreach chapter.ChapterActInfo(act)
		{
			if (act.Hourglass ~= hourglass)
				return act;
		}
	}
	
	return None;
}

function UpdateChapterInfo()
{
	if (!SlotData.Initialized)
		return;
	
	SetChapterTimePieceRequirement(Hat_ChapterInfo'HatinTime_ChapterInfo.maingame.MafiaTown', SlotData.Chapter1Cost);
	SetChapterTimePieceRequirement(Hat_ChapterInfo'HatinTime_ChapterInfo.maingame.trainwreck_of_science', SlotData.Chapter2Cost);
	SetChapterTimePieceRequirement(Hat_ChapterInfo'HatinTime_ChapterInfo.maingame.subconforest', SlotData.Chapter3Cost);
	SetChapterTimePieceRequirement(Hat_ChapterInfo'HatinTime_ChapterInfo.maingame.Sand_and_Sails', SlotData.Chapter4Cost);
	SetChapterTimePieceRequirement(Hat_ChapterInfo'HatinTime_ChapterInfo.maingame.Mu_Finale', SlotData.Chapter5Cost);
	
	if (SlotData.DLC1)
	{
		SetChapterTimePieceRequirement(Hat_ChapterInfo'HatinTime_ChapterInfo_DLC1.ChapterInfos.ChapterInfo_Cruise', SlotData.Chapter6Cost);
	}
	else
	{
		SetChapterTimePieceRequirement(Hat_ChapterInfo'HatinTime_ChapterInfo_DLC1.ChapterInfos.ChapterInfo_Cruise', 99);
	}
	
	if (SlotData.DLC2)
	{
		SetChapterTimePieceRequirement(Hat_ChapterInfo'hatintime_chapterinfo_dlc2.ChapterInfos.ChapterInfo_Metro', SlotData.Chapter7Cost);
	}
	else
	{
		SetChapterTimePieceRequirement(Hat_ChapterInfo'hatintime_chapterinfo_dlc2.ChapterInfos.ChapterInfo_Metro', 99);
	}
	
	UpdateActUnlocks();
	
	if (IsInSpaceship() && (IsSaveFileJustLoaded() || !class'Hat_SeqCond_IsMuMission'.static.IsFinaleMuMission())
		&& !class'Hat_SaveBitHelper'.static.HasActBit("thefinale_ending", 1))
	{
		UpdatePowerPanels();
		OpenBedroomDoor();
	}
	
	SaveGame();
}

function ResetEverything()
{
	local array<Hat_ChapterInfo> chapterInfoArray;
	local Hat_ChapterInfo chapter;
	local Hat_ChapterActInfo act;

	chapterInfoArray = class'Hat_ChapterInfo'.static.GetAllChapterInfo();
	foreach chapterInfoArray(chapter)
	{
		chapter.ConditionalUpdateActList();
		foreach chapter.ChapterActInfo(act)
		{
			if (act.IsBonus && !IsPurpleRift(act))
			{
				act.RequiredActID.Length = 0;
				
				switch (act.MapName)
				{
					case "TimeRift_Water_Mafia_Easy": // Sewers
						act.RequiredActID.AddItem(4);
						break;

					case "TimeRift_Water_Mafia_Hard": // Bazaar
						act.RequiredActID.AddItem(6);
						break;

					case "TimeRift_Water_TWreck_Panels": // The Owl Express
						act.RequiredActID.AddItem(2);
						act.RequiredActID.AddItem(3);
						break;
					
					case "TimeRift_Water_TWreck_Parade": // The Moon
						act.RequiredActID.AddItem(4);
						act.RequiredActID.AddItem(5);
						break;
					
					case "TimeRift_Water_Subcon_Hookshot": // Pipe
						act.RequiredActID.AddItem(2);
						break;
					
					case "TimeRift_Water_Subcon_Dwellers": // Village
						act.RequiredActID.AddItem(4);
						break;
					
					case "TimeRift_Water_Alp_Cats": // Curly Tail Trail
						act.RequiredActID.AddItem(13);
						break;
					
					case "TimeRift_Water_Alp_Goats": // The Twilight Bell
						act.RequiredActID.AddItem(15);
						break;
					
					case "TimeRift_Water_Cruise_Slide": // Balcony
						act.RequiredActID.AddItem(3);
						break;
					
					default:
						break;
				}
			}
		}
	}
	
	SetChapterTimePieceRequirement(Hat_ChapterInfo'HatinTime_ChapterInfo.maingame.MafiaTown', 1);
	SetChapterTimePieceRequirement(Hat_ChapterInfo'HatinTime_ChapterInfo.maingame.trainwreck_of_science', 4);
	SetChapterTimePieceRequirement(Hat_ChapterInfo'HatinTime_ChapterInfo.maingame.subconforest', 7);
	SetChapterTimePieceRequirement(Hat_ChapterInfo'HatinTime_ChapterInfo.maingame.Sand_and_Sails', 14);
	SetChapterTimePieceRequirement(Hat_ChapterInfo'HatinTime_ChapterInfo.maingame.Mu_Finale', 25);
	SetChapterTimePieceRequirement(Hat_ChapterInfo'HatinTime_ChapterInfo_DLC1.ChapterInfos.ChapterInfo_Cruise', 35);
	
	ConsoleCommand("set Hat_IntruderInfo_CookingCat HasIntruderAlert true");
    ConsoleCommand("set hat_snatchercontract_deathwish_riftcollapse PenaltyWaitTimeInSeconds 300");
    ConsoleCommand("set hat_snatchercontract_deathwish_riftcollapse Condition_3Lives true");
	ConsoleCommand("set hat_snatchercontract_deathwish neverobscureobjectives false");
}

function OpenBedroomDoor()
{
	local Hat_SpaceshipPowerPanel panel;
	foreach DynamicActors(class'Hat_SpaceshipPowerPanel', panel)
	{
		if (panel.ChapterInfo.ChapterID == 3)
		{
			panel.SpaceshipDoor.Enabled = true;
			panel.SpaceshipDoor.bBlocksNavigation = false;
			panel.SpaceshipDoor.SetLockedVisuals(false);
		}
	}
}

function UpdateActUnlocks()
{
	local array<Hat_ChapterInfo> chapterInfoArray;
	local Hat_ChapterInfo chapter;
	local Hat_ChapterActInfo act;
	
	chapterInfoArray = class'Hat_ChapterInfo'.static.GetAllChapterInfo();
	foreach chapterInfoArray(chapter)
	{
		chapter.ConditionalUpdateActList();
		foreach chapter.ChapterActInfo(act)
		{
			if (act.IsBonus && !IsPurpleRift(act) && IsChapterActInfoUnlocked(act))
			{
				act.RequiredActID.Length = 0;
				act.RequiredActID.AddItem(0); // else game thinks it's a purple rift
			}
		}
	}
}

function bool IsActCompletable(Hat_ChapterActInfo act, Hat_Loadout lo, optional bool basement)
{
	local int difficulty;
	local bool canHit, canHitMaskBypass, hookshot, umbrella, sdj;
	
	if (SlotData.DeathWishOnly)
		return true;
	
	difficulty = SlotData.LogicDifficulty; // -1 = Normal, 0 = Moderate, 1 = Hard, 2 = Expert
	
	// Can hit objects, has Umbrella or Brewing Hat, only for umbrella logic
	canHit = !SlotData.UmbrellaLogic || class'Archipelago_HUDElementItemFinder'.static.CanHitObjects();
	
	// Can hit dweller bells, but not needed if player has Dweller Mask, only for umbrella logic
	canHitMaskBypass = !SlotData.UmbrellaLogic || class'Archipelago_HUDElementItemFinder'.static.CanHitObjects(true);
	
	hookshot = lo.BackpackHasInventory(class'Hat_Ability_Hookshot');
	umbrella = !SlotData.UmbrellaLogic || lo.BackpackHasInventory(class'Archipelago_Weapon_Umbrella', true) 
				|| lo.BackpackHasInventory(class'Archipelago_Weapon_BaseballBat', true);
	
	sdj = class'Archipelago_HUDElementItemFinder'.static.CanSDJ();
	
	if (basement)
	{
		return hookshot;
	}
	
	switch (act.hourglass)
	{
		case "mafiatown_lava": case "moon_parade": case "snatcher_boss":
			return umbrella;
		
		case "DeadBirdStudio":
			if (!SlotData.UmbrellaLogic && difficulty < `MODERATE)
				return canHit;
			
			return difficulty >= `EXPERT || canHit;
		
		case "Cruise_Boarding": case "Cruise_WaterRift_Slide": case "TimeRift_Water_Subcon_Hookshot": case "trainwreck_selfdestruct":
			return hookshot;
		
		case "Metro_Escape":
			if (difficulty >= `EXPERT)
				return (SlotData.NoTicketSkips != 1
				|| lo.HasCollectible(class'Hat_Collectible_MetroTicket_RouteA')
				&& lo.HasCollectible(class'Hat_Collectible_MetroTicket_RouteC')
				&& lo.HasCollectible(class'Hat_Collectible_MetroTicket_RouteD'));
			
			if (difficulty >= `HARD)
				return lo.BackpackHasInventory(class'Hat_Ability_Chemical')
				&& (SlotData.NoTicketSkips != 1
				|| lo.HasCollectible(class'Hat_Collectible_MetroTicket_RouteA')
				&& lo.HasCollectible(class'Hat_Collectible_MetroTicket_RouteC')
				&& lo.HasCollectible(class'Hat_Collectible_MetroTicket_RouteD'));
			
			if (difficulty >= `MODERATE)
				return lo.BackpackHasInventory(class'Hat_Ability_StatueFall')
				&& lo.BackpackHasInventory(class'Hat_Ability_Chemical')
				&& lo.HasCollectible(class'Hat_Collectible_MetroTicket_RouteA')
				&& lo.HasCollectible(class'Hat_Collectible_MetroTicket_RouteC')
				&& lo.HasCollectible(class'Hat_Collectible_MetroTicket_RouteD');
			
			return hookshot
				&& lo.BackpackHasInventory(class'Hat_Ability_StatueFall')
				&& lo.BackpackHasInventory(class'Hat_Ability_Chemical')
				&& lo.HasCollectible(class'Hat_Collectible_MetroTicket_RouteA')
				&& lo.HasCollectible(class'Hat_Collectible_MetroTicket_RouteC')
				&& lo.HasCollectible(class'Hat_Collectible_MetroTicket_RouteD');
		
		case "subcon_village_icewall":
			return !SlotData.ShuffleSubconPaintings || GetPaintingUnlocks() >= 1;
		
		case "subcon_cave":
			if (!class'Archipelago_HUDElementItemFinder'.static.CanSkipPaintings() && GetPaintingUnlocks() <= 0)
				return false;
			
			return difficulty >= `MODERATE || canHit && hookshot;
		
		case "chapter2_toiletboss":
			if ((difficulty < `EXPERT || !class'Archipelago_HUDElementItemFinder'.static.CanSkipPaintings()) 
			&& SlotData.ShuffleSubconPaintings && GetPaintingUnlocks() <= 0)
				return false;
			
			return hookshot && canHit;
		
		case "vanessa_manor_attic":
			if (!class'Archipelago_HUDElementItemFinder'.static.CanSkipPaintings() && GetPaintingUnlocks() <= 0)
				return false;
			
			return canHitMaskBypass || difficulty >= `MODERATE;
		
		case "TheFinale_FinalBoss":
			return (difficulty >= `MODERATE || hookshot) && lo.BackpackHasInventory(class'Hat_Ability_FoxMask');
		
		case "Spaceship_WaterRift_Gallery":
			return difficulty >= `MODERATE || lo.BackpackHasInventory(class'Hat_Ability_Chemical');
		
		case "Cruise_Sinking":
			return difficulty >= `MODERATE || lo.BackpackHasInventory(class'Hat_Ability_StatueFall');
		
		case "Cruise_CaveRift_Aquarium":
			return hookshot && (difficulty >= `MODERATE || lo.BackpackHasInventory(class'Hat_Ability_StatueFall'))
					&& (difficulty >= 1 || lo.BackpackHasInventory(class'Hat_Ability_FoxMask'));
		
		case "AlpineSkyline_Finale":
			return hookshot &&
				(!SlotData.ShuffleZiplines || HasZipline(Zipline_Birdhouse) && HasZipline(Zipline_LavaCake) && HasZipline(Zipline_Windmill));
		
		case "TimeRift_Water_AlpineSkyline_Cats":
			return difficulty >= `EXPERT || sdj || lo.BackpackHasInventory(class'Hat_Ability_StatueFall');
		
		case "TimeRift_Water_Alp_Goats":
			return lo.BackpackHasInventory(class'Hat_Ability_FoxMask')
				|| difficulty >= `HARD && lo.BackpackHasInventory(class'Hat_Ability_Sprint') && lo.BackpackHasInventory(class'Hat_Badge_Scooter');
		
		case "harbor_impossible_race":
			if (SlotData.CTRLogic >= 3)
				return true;
			
			if (SlotData.CTRLogic <= 0)
				return lo.BackpackHasInventory(class'Hat_Ability_TimeStop');
			
			return lo.BackpackHasInventory(class'Hat_Ability_TimeStop') 
			|| SlotData.CTRLogic >= 1 && lo.BackpackHasInventory(class'Hat_Ability_Sprint') && (SlotData.CTRLogic == 2 || lo.BackpackHasInventory(class'Hat_Badge_Scooter'));
		
		case "subcon_maildelivery":
			return lo.BackpackHasInventory(class'Hat_Ability_Sprint');
		
		// Hitting the bell with fists wastes too much time with the hitstun to cross the dweller platforms
		case "TimeRift_Water_Subcon_Dwellers":
			return lo.BackpackHasInventory(class'Hat_Ability_FoxMask')
				|| (lo.BackpackHasInventory(class'Hat_Ability_Chemical') 
				|| lo.BackpackHasInventory(class'Archipelago_Weapon_Umbrella', true)
				|| lo.BackpackHasInventory(class'Archipelago_Weapon_BaseballBat', true));
		
		default:
			return true;
	}
}

function UpdatePowerPanels()
{
	local Hat_SpaceshipPowerPanel panel;
	local float val;
	
	foreach DynamicActors(class'Hat_SpaceshipPowerPanel', panel)
	{
		// hide spaceship panels for DLC chapters we have disabled
		if (panel.ChapterInfo.ChapterID == 6 && !SlotData.DLC1 || panel.ChapterInfo.ChapterID == 7 && !SlotData.DLC2)
		{
			panel.ShutDown();
			if (panel.InteractPoint != None)
			{
				panel.InteractPoint.Destroy();
				panel.InteractPoint = None;
			}
		}
		
		if (SlotData.DeathWishOnly && !IsPowerPanelActivated2(panel))
		{
			panel.OnDoUnlock();
			
			if (panel.Telescope != None)
				panel.Telescope.SetUnlocked(true);
			
			continue;
		}
		
		if (SlotData.Initialized && !IsPowerPanelActivated2(panel) && panel.CanBeUnlocked() 
		&& panel.InteractPoint == None && (panel.RuntimeMat == None || !panel.RuntimeMat.GetScalarParameterValue('Unlocked', val) || val == 0))
		{
			panel.InteractPoint = Spawn(class'Hat_InteractPoint',panel,,panel.Location + Vector(panel.Rotation)*10 + vect(0,0,1)*20,panel.Rotation,,true);
			panel.InteractPoint.PushDelegate(panel.OnInteractDelegate);
			
			if (panel.RuntimeMat != None)
				panel.RuntimeMat.SetScalarParameterValue('Unlockable', 1);
			
			panel.ElectricityParticle[0].SetActive(true);
			panel.ElectricityParticle[1].SetActive(true);
			panel.ReadyToActivateParticle.SetActive(true);
			panel.ClearTimer(NameOf(panel.DoAttentionBeep));
			panel.SetTimer(1.8, true, NameOf(panel.DoAttentionBeep));
		}
	}
}

function bool IsPowerPanelActivated2(Hat_SpaceshipPowerPanel panel)
{
	local Hat_ChapterInfo ci;
	ci = panel.GetChapterInfo();
	
	if (ci == None) return false;
	if (ci.ChapterID <= 0) return false;
	if (!ci.HasDLCSupported(true)) return false;
	if (!class'Hat_SaveBitHelper'.static.HasLevelBit(panel.ActivatedLevelBit, ci.ChapterID)) return false;
	
	return true;
}

function SetChapterTimePieceRequirement(Hat_ChapterInfo chapter, int amount)
{
	local Hat_SpaceshipPowerPanel panel;
	chapter.RequiredHourglassCount = amount;
	
	if (IsInSpaceship() && amount <= 50)
	{
		foreach DynamicActors(class'Hat_SpaceshipPowerPanel', panel)
		{
			if (panel.GetChapterInfo() == chapter)
			{
				panel.RuntimeMat = panel.Mesh.CreateAndSetMaterialInstanceConstant(0);
				panel.RuntimeMat.SetTextureParameterValue('CountTexture', UnlockScreenNumbers[amount]);
				break;
			}
		}
	}
}

function bool IsChapterActInfoUnlocked(Hat_ChapterActInfo ChapterActInfo, optional string ModPackageName)
{
	local string hourglass;
	local int j, actid;
	local Hat_ChapterInfo ChapterInfo;
	local Hat_ChapterActInfo RequiredChapterActInfo, shuffled;
	local bool IsFreeRoam;
	
	ChapterInfo = ChapterActInfo.ChapterInfo;
	actid = ChapterActInfo.ActID;
	hourglass = ChapterActInfo.Hourglass;
	IsFreeRoam = IsActFreeRoam(ChapterActInfo);
	
	if (ChapterInfo == None) return false;
	if (!class'Hat_SeqCond_ChapterUnlocked'.static.IsChapterUnlocked(ChapterInfo)) return false;
	if (!ChapterActInfo.IsBonus && (actid <= 0 || actid > 99)) return false;
	if (!ChapterActInfo.IsBonus && (actid >= 99 || (ChapterInfo.ActIDAfterIntro > 0 && actid == ChapterInfo.ActIDAfterIntro)) && !IsFreeRoam) return false;
	if (hourglass == "" && !IsFreeRoam) return false;
	if (!ChapterActInfo.HasDLCSupported(true)) return false;
	
	if (ModPackageName != "")
	{
		hourglass = class'Hat_TimeObject_Base'.static.GetModTimePieceIdentifier(ModPackageName, hourglass);
	}
	
	// If actless and we don't have this Time Piece (and its not the finale nor free roam nor rift), skip!
	if (!ChapterActInfo.IsBonus && ChapterInfo.IsActless && (ChapterInfo.FinaleActID <= 0 || actid != ChapterInfo.FinaleActID) && !IsFreeRoam
		&& !HasAPBit("ActComplete_"$ChapterActInfo.hourglass, 1)) 
		return false;
	
	// Subcon Forest
	if (!ChapterActInfo.IsBonus && !IsFreeRoam && actid > 1 && ChapterInfo.UnlockedByLevelBit != "")
	{
		// hotfix attempt for Chapter 3 levels disappearing after finale completion
		if (ChapterInfo.ChapterID == 3)
		{
			if (HasAPBit("ActComplete_snatcher_boss", 1))
				return true;
		}
		
		return class'Hat_SaveBitHelper'.static.HasLevelBit(ChapterInfo.UnlockedByLevelBit, actid, ChapterInfo.GetActMap(1));
	}
	else if (IsPurpleRift(ChapterActInfo))
	{
		// Purple rift
		return `SaveManager.IsSecretLevelUnlocked(hourglass);
	}
	else // Normal act / Blue rift
	{
		// Check that we meet the Time Piece requirements to have unlocked this act
		for (j = 0; j < ChapterActInfo.RequiredActID.Length; j++)
		{
			if (ChapterActInfo.RequiredActID[j] <= 0) continue;
			
			RequiredChapterActInfo = ChapterInfo.GetChapterActInfoFromActID(ChapterActInfo.RequiredActID[j]);
			if (RequiredChapterActInfo == None) continue;
			
			hourglass = RequiredChapterActInfo.Hourglass;
			if (hourglass == "") continue;
			
			// If a Free Roam act is shuffled onto this act, it's a free space
			shuffled = GetShuffledAct(RequiredChapterActInfo);
			if (shuffled != None && IsActFreeRoam(shuffled) && IsChapterActInfoUnlocked(GetOriginalAct(shuffled)) && shuffled.ActID != 1)
				continue;
			
			if (ModPackageName != "")
			{
				hourglass = class'Hat_TimeObject_Base'.static.GetModTimePieceIdentifier(ModPackageName, hourglass);
			}
			
			if (HasAPBit("ActComplete_"$hourglass, 1)) continue;
			
			j = INDEX_NONE;
			break;
		}
		
		return (j != INDEX_NONE);
	}
}

function bool IsPurpleRift(Hat_ChapterActInfo act)
{
	return (act.IsBonus && InStr(act.hourglass, "_cave", false, true) != -1);
}

function ShuffleCollectibles(optional bool cache)
{
	local Hat_Collectible_Important collectible;
	local Hat_NPC npc;
	local int locId, i, maxItems;
	local Actor a;
	local array<int> locationArray, shopLocationArray, forceSendArray;
	local array<class<Object > > shopInvClasses;
	local LocationInfo locInfo;
	local class<Object> shopInvClass;
	local class<Archipelago_ShopItem_Base> shopItem;
	local string mapName, bitName;
	local Archipelago_ShopInventory_Base shopInv;
	
	if (CollectiblesShuffled || SlotData.DeathWishOnly || class'Hat_SnatcherContract_DeathWish'.static.IsAnyActive(false))
		return;
	
	mapName = class'Hat_SaveBitHelper'.static.GetCorrectedMapFilename();
	
	// Fix for Rock the Boat
	DebugMessage("Map Name: "$mapName);
	if (`GameManager.GetCurrentMapFilename() ~= "ship_sinking")
		mapName = "ship_sinking";
	
	foreach DynamicActors(class'Hat_Collectible_Important', collectible)
	{
		if (collectible.IsA('Hat_Collectible_VaultCode_Base') || collectible.IsA('Hat_Collectible_InstantCamera')
		|| collectible.IsA('Hat_Collectible_Sticker') || collectible.IsA('Hat_Collectible_MetroTicket_Base'))
			continue;
		
		// Some items only appear in certain acts
		locId = ObjectToLocationId(collectible);
		if (IsMapScouted(mapName) && !IsLocationCached(locId))
		{
			// We are trying to load from cache. This means we aren't connected. Wait until we are.
			if (cache)
				return;
			
			forceSendArray.AddItem(locId);
		}
		
		locationArray.AddItem(locId);
		if (bool(DebugMode))
		{
			DebugMessage("[ShuffleCollectibles] Found item: " $collectible.GetLevelName() $"."$collectible.Name $ObjectToLocationId(collectible));
		}
	}
	
	DebugMessage("Map Name: " $mapName);
	if (mapName ~= "mafia_town")
	{
		locationArray.AddItem(CameraBadgeCheck1);
		locationArray.AddItem(CameraBadgeCheck2);
	}
	else if (mapName ~= "subconforest")
	{
		locationArray.AddItem(SubconBushCheck1);
		locationArray.AddItem(SubconBushCheck2);
	}
	else if (mapName ~= "hub_spaceship")
	{
		// Rumbi
		locationArray.AddItem(2000301000);
	}
	
	for (i = 0; i < ChestArray.Length; i++)
	{
		if (ChestArray[i] == None)
			continue;
		
		locationArray.AddItem(ObjectToLocationId(ChestArray[i]));
	}
	
	foreach DynamicActors(class'Actor', a)
	{
		if (a.IsA('Hat_Goodie_Vault_Base'))
		{
			if (a.Name == 'Hat_Goodie_Vault_1') // golden vault
				continue;
			
			locId = ObjectToLocationId(a);

			// Vaults don't appear in HUMT
			if (IsMapScouted(mapName) && !IsLocationCached(locId))
			{
				// We are trying to load from cache. This means we aren't connected. Wait until we are.
				if (cache)
					return;
				
				forceSendArray.AddItem(locId);
			}
			
			locationArray.AddItem(locId);
		}
		else if (a.IsA('Hat_ImpactInteract_Breakable_ChemicalBadge'))
		{
			if (Hat_ImpactInteract_Breakable_ChemicalBadge(a).Rewards.Length <= 0)
				continue;
			
			for (i = 0; i < Hat_ImpactInteract_Breakable_ChemicalBadge(a).Rewards.Length; i++)
			{
				if (class<Archipelago_RandomizedItem_Base>(Hat_ImpactInteract_Breakable_ChemicalBadge(a).Rewards[i]) != None)
				{
					locationArray.AddItem(ObjectToLocationId(a));
					break;
				}
			}
		}
		else if (SlotData.ShuffleStorybookPages && a.IsA('Hat_Collectible_StoryBookPage') && a.CreationTime <= 0)
		{
			locId = ObjectToLocationId(a);
			locationArray.AddItem(locId);
			
			if (SlotData.PageLocationIDs.Find(locId) == -1)
				SlotData.PageLocationIDs.AddItem(locId);
		}
	}
	
	BulliedNPCArray.Length = 0;
	foreach DynamicActors(class'Hat_NPC', npc)
	{
		if (npc.bHidden || !npc.IsA('Hat_NPC_Bullied'))
			continue;
		
		locId = ObjectToLocationId(npc);
		if (locId != 2000303832 && locId != 2000303833)
			continue;
		
		// Old guys don't appear in SCFOS/HUMT
		if (IsMapScouted(mapName) && !IsLocationCached(locId))
		{
			// We are trying to load from cache. This means we aren't connected. Wait until we are.
			if (cache)
				return;
			
			forceSendArray.AddItem(locId);
		}
		
		bitName = class'Hat_SaveBitHelper'.static.GetBitId(npc, 0);
		if (class'Hat_SaveBitHelper'.static.HasLevelBit(bitName, 1))
			continue;
		
		BulliedNPCArray.AddItem(npc);
		locationArray.AddItem(locId);
	}
	
	shopInvClasses = class'Hat_ClassHelper'.static.GetAllScriptClasses("Archipelago_ShopInventory_Base");
	foreach shopInvClasses(shopInvClass)
	{
		shopInv = new class<Archipelago_ShopInventory_Base>(shopInvClass);
		
		if (shopInv.ItemsForSale.Length <= 0)
			continue;
		
		if (InStr(shopInv.ShopNPCName, "Hat_NPC_NyakuzaShop") != -1 && !SlotData.DLC2
			|| InStr(shopInv.ShopNPCName, "Hat_MetroTicketBooth") != -1 && !SlotData.DLC2)
			continue;
		
		if (InStr(shopInv.ShopNPCName, "Hat_NPC_NyakuzaShop", false, true) != -1
			|| shopInv.IsBadgeSeller)
		{
			maxItems = shopInv.IsBadgeSeller ? SlotData.BadgeSellerItemCount : GetAPBits(shopInv.ShopNPCName, 0);	
		}
		else
		{
			maxItems = 1;
		}
		
		if (maxItems <= 0)
			continue;
		
		for (i = 0; i < maxItems; i++)
		{
			if (!GetShopItemClassFromLocation(
				class<Archipelago_ShopItem_Base>(shopInv.ItemsForSale[i].CollectibleClass).default.LocationID, shopItem))
				continue;
			
			if (IsShopItemCached(shopItem))
				continue;
			
			shopLocationArray.AddItem(shopItem.default.LocationID);
		}
	}
	
	if (cache)
		shopLocationArray.Length = 0;
	
	if (locationArray.Length > 0 || shopLocationArray.Length > 0 || forceSendArray.Length > 0)
	{
		if (!IsMapScouted(mapName))
		{
			for (i = 0; i < shopLocationArray.Length; i++)
				locationArray.AddItem(shopLocationArray[i]);
			
			if (locationArray.Length > 0)
				SendMultipleLocationChecks(locationArray, true);
		}
		else
		{
			// Load from cache
			for (i = 0; i < locationArray.Length; i++)
			{
				if (IsLocationChecked(locationArray[i]))
					continue;
				
				locInfo = GetLocationInfoFromID(locationArray[i]);
				if (locInfo.ContainerClass != None || locInfo.IsStatic
				|| locInfo.Position.x == 0 && locInfo.Position.y == 0 && locInfo.position.z == 0)
					continue;
				
				CreateItemFromInfo(GetLocationInfoFromID(locationArray[i]));
			}
			
			foreach DynamicActors(class'Hat_Collectible_Important', collectible)
			{
				if (collectible.IsA('Hat_Collectible_VaultCode_Base') || collectible.IsA('Hat_Collectible_Sticker')
				 	|| collectible.IsA('Hat_Collectible_MetroTicket_Base') || collectible.IsA('Hat_Collectible_InstantCamera'))
					continue;
				
				if (forceSendArray.Find(ObjectToLocationId(collectible)) != -1)
					continue;
				
				collectible.Destroy();
			}
		}
		
		if (forceSendArray.Length > 0)
		{
			SendMultipleLocationChecks(forceSendArray, true);
		}
	}
	
	CollectiblesShuffled = true;
}

function ShuffleCollectibles2()
{
	ShuffleCollectibles(true);
}

function LocationInfo GetLocationInfoFromID(int id)
{
	local int i;
	local LocationInfo locInfo;
	for (i = 0; i < SlotData.LocationInfoArray.Length; i++)
	{
		if (SlotData.LocationInfoArray[i].ID == id)
			return SlotData.LocationInfoArray[i];
	}
	
	return locInfo;
}

function bool IsShopItemCached(class<Archipelago_ShopItem_Base> shopClass)
{
	local int i;
	
	if (SlotData == None || !SlotData.Initialized)
		return false;
	
	for (i = 0; i < SlotData.ShopItemList.Length; i++)
	{
		if (SlotData.ShopItemList[i].ItemClass == shopClass)
			return true;
	}
	
	return false;
}

function SetShopInfoAsHinted(ShopItemInfo shopInfo)
{
	local int i;
	for (i = 0; i < SlotData.ShopItemList.Length; i++)
	{
		if (SlotData.ShopItemList[i].ItemClass == shopInfo.ItemClass)
		{
			SlotData.ShopItemList[i].Hinted = true;
			break;
		}
	}
}

function bool IsLocationCached(int id)
{
	local int i;
	
	if (SlotData == None || !SlotData.Initialized)
		return false;
	
	for (i = 0; i < SlotData.LocationInfoArray.Length; i++)
	{
		if (SlotData.LocationInfoArray[i].ID == id)
			return true;
	}
	
	return false;
}

function bool IsLocationIDPage(int id)
{
	return SlotData.PageLocationIDs.Find(id) != -1;
}

function bool IsMapScouted(string map)
{
	return HasAPBit("MapScouted_"$Locs(map), 1);
}

function Archipelago_RandomizedItem_Base CreateItem(int locId, string itemId, int flags, int player, 
	optional Hat_Collectible_Important collectible, optional Vector pos)
{
	local string mapName;
	local class<Actor> worldClass;
	local Archipelago_RandomizedItem_Base item;
	local int i;
	local bool found;
	local LocationInfo locInfo;

	if (!class'Archipelago_ItemInfo'.static.GetNativeItemData(itemId, worldClass)) // not a regular item
	{
		worldClass = class'Archipelago_RandomizedItem_Misc';
	}
	
	item = Archipelago_RandomizedItem_Base(Spawn(worldClass, , , collectible != None ? collectible.Location : pos, , , true));
	item.LocationId = locId;
	item.ItemId = itemId;
	item.ItemFlags = flags;
	item.ItemOwner = player;
	
	if (collectible != None)
	{
		if (locId == CameraBadgeCheck1 || locId == CameraBadgeCheck2)
		{
			item.OriginalCollectibleName = locId == CameraBadgeCheck1 ? "AP_Camera1Check" : "AP_Camera2Check";
		}
		else
		{
			item.OriginalCollectibleName = class'Hat_SaveBitHelper'.static.GetCorrectedMapFilename(string(collectible.GetLevelName()))$"."$collectible.Name;
		}
	}
	
	if (!item.Init())
		return None;
	
	mapName = class'Hat_SaveBitHelper'.static.GetCorrectedMapFilename();
	
	// can we cache this item?
	for (i = 0; i < SlotData.LocationInfoArray.Length; i++)
	{
		if (locId == SlotData.LocationInfoArray[i].ID && mapName ~= SlotData.LocationInfoArray[i].MapName)
		{
			found = true;
			break;
		}
	}
	
	if (!found)
	{
		DebugMessage("Caching location: "$locId);
		locInfo.ID = locId;
		locInfo.ItemID = itemId;
		locInfo.Player = player;
		locInfo.Flags = flags;
		locInfo.MapName = mapName;
		locInfo.ItemClass = item.class;
		locInfo.Position = item.Location;
		SlotData.LocationInfoArray.AddItem(locInfo);
	}
	
	return item;
}

function Archipelago_RandomizedItem_Base CreateItemFromInfo(LocationInfo locInfo)
{
	local Archipelago_RandomizedItem_Base item;
	
	item = Archipelago_RandomizedItem_Base(Spawn(locInfo.ItemClass, , , locInfo.Position, , , true));
	item.LocationId = locInfo.ID;
	item.ItemId = locInfo.ItemID;
	item.ItemFlags = locInfo.Flags;
	item.ItemOwner = locInfo.Player;
	
	if (!item.Init())
		return None;
	
	return item;
}

function bool IsLocationChecked(int id)
{
	return SlotData.CheckedLocations.Find(id) != -1;
}

function bool GetShopItemClassFromLocation(int locationId, out class<Archipelago_ShopItem_Base> outClass)
{
	local array<class<Object > > shopItemClasses;
	local class<Object> shopItem;
	
	shopItemClasses = class'Hat_ClassHelper'.static.GetAllScriptClasses("Archipelago_ShopItem_Base");
	
	foreach shopItemClasses(shopItem)
	{
		if (class<Archipelago_ShopItem_Base>(shopItem).default.LocationID <= 0)
			continue;
		
		if (class<Archipelago_ShopItem_Base>(shopItem).default.LocationID == locationId)
		{
			outClass = class<Archipelago_ShopItem_Base>(shopItem);
			return true;
		}
	}
	
	return false;
}

// way less expensive, but needs the class array upfront
function bool GetShopItemClassFromLocation_Cheap(array<class< Object > > shopItemClasses, int locationId, out class<Archipelago_ShopItem_Base> outClass)
{
	local class<Object> shopItem;
	foreach shopItemClasses(shopItem)
	{
		if (class<Archipelago_ShopItem_Base>(shopItem).default.LocationID <= 0)
			continue;
		
		if (class<Archipelago_ShopItem_Base>(shopItem).default.LocationID == locationId)
		{
			outClass = class<Archipelago_ShopItem_Base>(shopItem);
			return true;
		}
	}
	
	return false;
}

function ShopItemInfo CreateShopItemInfo(class<Archipelago_ShopItem_Base> itemClass, string ItemID, int flags, int player)
{
	local ShopItemInfo shopInfo;
	
	shopInfo.ID = itemClass.default.LocationID;
	shopInfo.ItemClass = itemClass;
	shopInfo.ItemID = itemId;
	shopInfo.ItemFlags = flags;
	shopInfo.Player = player;
	
	if (class<Archipelago_ShopItem_Metro>(itemClass) != None)
	{
		shopInfo.PonCost = SlotData.MetroMinPonCost + 
			class'Hat_Math'.static.SeededRandWithSeed(SlotData.MetroMaxPonCost-SlotData.MetroMinPonCost+1, int(SlotData.Seed)+SlotData.ShopItemRandStep);
	}
	else
	{
		shopInfo.PonCost = SlotData.MinPonCost + 
			class'Hat_Math'.static.SeededRandWithSeed(SlotData.MaxPonCost-SlotData.MinPonCost+1, int(SlotData.Seed)+SlotData.ShopItemRandStep);
	}
	
	SlotData.ShopItemRandStep++;
	SlotData.ShopItemList.AddItem(shopInfo);
	InitShopItemDisplayName(itemClass);
	
	return shopInfo;
}

function Archipelago_ShopInventory_Base GetShopInventoryFromShopItem(class<Archipelago_ShopItem_Base> itemClass)
{
	local int i, j;
	local Archipelago_ShopInventory_Base shopInv;
	
	if (CachedShopInvs.Length <= 0)
		CachedShopInvs = class'Hat_ClassHelper'.static.GetAllScriptClasses("Archipelago_ShopInventory_Base");
	
	for (i = 0; i < CachedShopInvs.Length; i++)
	{
		shopInv = new class<Archipelago_ShopInventory_Base>(CachedShopInvs[i]);

		for (j = 0; j < shopInv.ItemsForSale.Length; j++)
		{
			if (shopInv.ItemsForSale[j].CollectibleClass == itemClass)
				return shopInv;
		}
	}
	
	return None;
}

function string GetShopItemMerchantName(class<Archipelago_ShopItem_Base> itemClass)
{
	return GetShopInventoryFromShopItem(itemClass).ShopNPCName;
}

function InitShopItemDisplayName(class<Archipelago_ShopItem_Base> itemClass)
{
	local ShopItemInfo shopInfo;
	local string displayName;
	local class<Actor> worldClass;
	local int i;
	
	if (!SlotData.Initialized || !GetShopItemInfo(itemClass, shopInfo))
		return;
	
	if (class'Archipelago_ItemInfo'.static.GetNativeItemData(shopInfo.ItemID, worldClass))
	{
		itemClass.static.SetHUDIcon(class<Archipelago_RandomizedItem_Base>(worldClass).default.HUDIcon);
	}
	else
	{
		itemClass.static.SetHUDIcon(class'Archipelago_ShopItem_Base'.default.HUDIcon);
	}
	
	for (i = 0; i < SlotData.ShopItemNames.Length; i++)
	{
		if (SlotData.ShopItemNames[i].ID == itemClass.default.LocationID)
		{
			displayName = SlotData.ShopItemNames[i].ItemName;
			break;
		}
	}
	
	DebugMessage("Shop Item Name: " $itemClass.default.LocationID $displayName);
	// Hotfix for metro shops having blank item names for some reason?
	if (displayName ~= "")
		return;
	
	//if (displayName != "Unknown Item")
	//	displayName $= " ("$PlayerIdToName(shopInfo.Player)$")";
	
	itemClass.static.SetDisplayName(displayName);
}

function string GetShopItemID(class<Archipelago_ShopItem_Base> itemClass)
{
	local int i;
	for (i = 0; i < SlotData.ShopItemList.Length; i++)
	{
		if (SlotData.ShopItemList[i].ItemClass == itemClass)
			return SlotData.ShopItemList[i].ItemID;
	}
	
	return "0";
}

function bool GetShopItemInfo(class<Archipelago_ShopItem_Base> itemClass, optional out ShopItemInfo shopInfo)
{
	local int i;
	for (i = 0; i < SlotData.ShopItemList.Length; i++)
	{
		if (SlotData.ShopItemList[i].ItemClass == itemClass)
		{
			shopInfo = SlotData.ShopItemList[i];
			return true;
		}
	}
	
	return false;
}

function bool DoesShopHaveImportantItems(Archipelago_ShopInventory_Base shop, optional bool excludePurchased)
{
	local int i;
	local ShopItemInfo shopInfo;
	local Hat_PlayerController pc;
	
	pc = Hat_PlayerController(GetALocalPlayerController());
	for (i = 0; i < shop.ItemsForSale.Length; i++)
	{
		if (GetShopItemInfo(class<Archipelago_ShopItem_Base>(shop.ItemsForSale[i].CollectibleClass), shopInfo))
		{
			if ((shopInfo.ItemFlags == ItemFlag_Important || shopInfo.ItemFlags == ItemFlag_ImportantSkipBalancing)
			&& (!excludePurchased || !pc.HasCollectible(shop.ItemsForSale[i].CollectibleClass)))
				return true;
		}
	}
	
	return false;
}

function Archipelago_ShopInventory_Base GetShopInventoryFromName(Name n)
{
	local int i;
	
	if (CachedShopInvs.Length <= 0)
		CachedShopInvs = class'Hat_ClassHelper'.static.GetAllScriptClasses("Archipelago_ShopInventory_Base");
	
	for (i = 0; i < CachedShopInvs.Length; i++)
	{
		if (class<Archipelago_ShopInventory_Base>(CachedShopInvs[i]).default.ShopNPCName != ""
			&& class<Archipelago_ShopInventory_Base>(CachedShopInvs[i]).default.ShopNPCName == string(n))
		{
			return new class<Archipelago_ShopInventory_Base>(CachedShopInvs[i]);
		}
	}
	
	return None;
}

function IterateChestArray()
{
	local int i;
	local string message, bitName;
	local array<int> locationArray;
	
	if (ChestArray.Length <= 0 && BulliedNPCArray.Length <= 0)
		return;
	
	for (i = 0; i < ChestArray.Length; i++)
	{
		if (!ChestArray[i].FullOpened)
			continue;
			
		if (bool(DebugMode))
		{
			message = "";
			message = class'Hat_SaveBitHelper'.static.GetCorrectedMapFilename(string(ChestArray[i].GetLevelName()));
			message $= "."$ChestArray[i].Name;
			message $= "("$ObjectToLocationId(ChestArray[i])$")";
			DebugMessage(message);
		}
		
		locationArray.AddItem(ObjectToLocationId(ChestArray[i]));
		ChestArray.RemoveItem(ChestArray[i]);
	}
	
	for (i = 0; i < BulliedNPCArray.Length; i++)
	{
		bitName = class'Hat_SaveBitHelper'.static.GetBitId(BulliedNPCArray[i], 0);
		if (!class'Hat_SaveBitHelper'.static.HasLevelBit(bitName, 1))
			continue;
			
		if (bool(DebugMode))
		{
			message = "";
			message = class'Hat_SaveBitHelper'.static.GetCorrectedMapFilename(string(BulliedNPCArray[i].GetLevelName()));
			message $= "."$BulliedNPCArray[i].Name;
			message $= "("$ObjectToLocationId(BulliedNPCArray[i])$")";
			DebugMessage(message);
		}
		
		locationArray.AddItem(ObjectToLocationId(BulliedNPCArray[i]));
		BulliedNPCArray.RemoveItem(BulliedNPCArray[i]);
	}
	
	if (locationArray.Length > 0)
	{
		SendMultipleLocationChecks(locationArray);
	}
}

function bool IsLocationIDContainer(int id, optional out Actor container)
{
	local Actor a;
	
	foreach DynamicActors(class'Actor', a)
	{
		if (id == SubconBushCheck1 || id == SubconBushCheck2)
		{
			if (a.IsA('Hat_InteractiveFoliage_HarborBush'))
			{
				if (id == SubconBushCheck1 && a.Name == 'Hat_InteractiveFoliage_HarborBush_2'
					|| id == SubconBushCheck2 && a.Name == 'Hat_InteractiveFoliage_HarborBush_3')
				{
					container = a;
					return true;
				}
			}
		}
		else if (a.IsA('Hat_TreasureChest_Base') || a.IsA('Hat_Goodie_Vault_Base') || a.IsA('Hat_NPC_Bullied')
			|| a.IsA('Hat_ImpactInteract_Breakable_ChemicalBadge'))
		{
			if (ObjectToLocationId(a) == id)
			{
				DebugMessage("Found container: "$a.Name $", ID: "$id);
				container = a;
				return true;
			}
		}
	}
	
	return false;
}

// for breakable objects that contain important items
function OnPreBreakableBreak(Actor Breakable, Pawn Breaker)
{
	local Hat_ImpactInteract_Breakable_ChemicalBadge b;
	local class<Actor> spawnClass;
	local Archipelago_RandomizedItem_Base item;
	local int i;
	local bool hasImportantItem;
	local string message;
	local Vector vel;
	local LocationInfo locInfo;
	
	if (!IsArchipelagoEnabled())
		return;
	
	if (Breakable.IsA('Hat_ImpactInteract_Breakable_ChemicalBadge'))
	{
		b = Hat_ImpactInteract_Breakable_ChemicalBadge(Breakable);
		if (b.Rewards.Length <= 0)
			return;
		
		for (i = 0; i < b.Rewards.Length; i++)
		{
			if (class<Archipelago_RandomizedItem_Base>(b.Rewards[i]) == None)
				continue;
			
			b.Rewards.RemoveItem(b.Rewards[i]);
			b.RememberDestroyed = false;
			hasImportantItem = true;
		}
		
		if (hasImportantItem)
		{
			if (bool(DebugMode))
			{
				message = class'Hat_SaveBitHelper'.static.GetCorrectedMapFilename(string(b.GetLevelName()));
				message $= "."$b.Name;
				message $= "("$ObjectToLocationId(b)$")";
				DebugMessage(message);
			}
			
			if (IsLocationChecked(ObjectToLocationId(b)))
			{
				return;
			}
			
			locInfo = GetLocationInfoFromID(ObjectToLocationId(b));
			if (locInfo.ID == 0)
			{
				// failsafe
				SendLocationCheck(ObjectToLocationId(b));
				return;
			}

			spawnClass = locInfo.ItemClass;
			item = Archipelago_RandomizedItem_Base(Spawn(spawnClass,,,b.Location + vect(0,0,50),,,true));
			item.LocationId = locInfo.ID;
			item.ItemFlags = locInfo.Flags;
			item.ItemOwner = locInfo.Player;
			item.Init();
			vel = vect(0,0,1)*RandRange(200,500);
			item.Bounce(vel);
		}
	}
}

function OnPlayerDeath(Pawn Player)
{
	local string message, deathString, amnestyType;
	local int CurrentAmnesty, TotalAmnesty;
	
	if (!IsDeathLinkEnabled() || !IsArchipelagoEnabled() || !IsFullyConnected())
		return;

	// pick amnesty type based on if a death wish is active
	if (class'Hat_SnatcherContract_DeathWish'.static.IsAnyActive(false)) {
		amnestyType = "DWCurrentDeathLinkAmnesty";
		TotalAmnesty = SlotData.DWDeathLinkAmnesty;
	} else {
		amnestyType = "CurrentDeathLinkAmnesty";
		TotalAmnesty = SlotData.DeathLinkAmnesty;
	}
	CurrentAmnesty = GetAPBits(amnestyType, TotalAmnesty);
	DebugMessage("[DeathLink] Amnesty type is " $ amnestyType $ " with " $ CurrentAmnesty $ " of " $ TotalAmnesty $ " left");
	
	if (TotalAmnesty != 0 && CurrentAmnesty > 0) {
		SetAPBits(amnestyType, CurrentAmnesty - 1);
		return;
	}
	
	// commit myurder
	DeathLinked = true;
	SetAPBits(amnestyType, TotalAmnesty);
	message = "[{`cmd`:`Bounce`,`tags`:[`DeathLink`],`data`:{`time`:" $float(class'Hat_Math_Base'.static.GetApproximateTimeStamp_Now()) $",`source`:" $"`" $SlotData.SlotName $"`" $"}}]";
	message = Repl(message, "`", "\"");
	client.SendBinaryMessage(message);
	KillEveryone(); // kill co op players
	if (IsOnlineParty())
	{
		deathString = "You were MYURRDERRRRED by: " $ GetLocalPlayerName(Hat_Player(Player));
		SendOnlinePartyCommand(deathString, 'APDeathLink', Player); // and online party players in our slot as well
	}
}

function String GetLocalPlayerName(Hat_Player ply)
{
	local Hat_PlayerController pc;
	local Array<Object> playerStates;
	local int i;
	local Hat_GhostPartyPlayerStateBase playerState;

	pc = Hat_PlayerController(ply.Controller);
	pc.GetGhostPartyPlayerStates(PlayerStates);
	for (i = 0; i < PlayerStates.Length; i++)
	{
		PlayerState = Hat_GhostPartyPlayerStateBase(PlayerStates[i]);
		if (PlayerState.IsLocalPlayer())
			return PlayerState.GetDisplayName();
	}
	
	return "Me";
}

function KillEveryone()
{
	local Hat_Player player;
	foreach DynamicActors(class'Hat_Player', player)
	{
		if (player.Health > 0)
			player.Suicide();
	}
}

function OnLoadoutChanged(PlayerController controller, Object loadout, Object backpackItem)
{
	local Hat_BackpackItem item;
	
	if (!IsArchipelagoEnabled() || SlotData.DeathWishOnly)
		return;
	
	item = Hat_BackpackItem(backpackItem);
	if (item == None)
		return;
	
	// remove base game umbrella in favor of our own. This is the umbrella check in Mafia Town.
	if (class<Hat_Weapon_Umbrella>(item.BackpackClass) != None 
	&& class<Archipelago_Weapon_Umbrella>(item.BackpackClass) == None
	&& class<Archipelago_Weapon_BaseballBat>(item.BackpackClass) == None)
	{
		Hat_Loadout(loadout).RemoveBackpack(item);
		if (`GameManager.GetCurrentMapFilename() ~= "mafia_town" && `GameManager.IsCurrentAct(1))
		{
			SendLocationCheck(UmbrellaCheck);
			SetAPBits("UmbrellaCheck", 1);
		}
	}
}

function UpdateZiplineUnlocks()
{
	local Hat_SandTravelNode node;
	
	if (`GameManager.GetChapterInfo().ChapterID != 4)
		return;
	
	foreach DynamicActors(class'Hat_SandTravelNode', node)
	{
		if (node.Name == 'Hat_SandTravelNode_15' || node.Name == 'Hat_SandTravelNode_17'
			|| node.Name == 'Hat_SandTravelNode_43' || node.Name == 'Hat_SandTravelNode_44')
		{
			if (node.HookPoint == None || node.BlockedInFinale && class'Hat_SeqCond_IsAlpineFinale'.static.IsAlpineFinale())
				continue;
			
			if (node.ActivatorHorn == None || !node.ActivatorHorn.IsActivated)
				continue;
			
			if (!HasAPBit("ZiplineUnlock_"$string(node.Name), 1))
			{
				node.HookPoint.Enabled = false;
				node.BlockedMesh.SetHidden(false);
				node.BlockedParticle.SetHidden(false);
				node.BlockedParticle.SetActive(true);
			}
			else
			{
				node.HookPoint.Enabled = true;
				node.BlockedMesh.SetHidden(true);
				node.BlockedParticle.SetHidden(true);
				node.BlockedParticle.SetActive(false);
			}
			
			node.SetTickIsDisabled(false);
		}
	}
}

function OnCollectibleSpawned(Object collectible)
{
	local Archipelago_RandomizedItem_Base item;
	local class<Actor> spawnClass;
	local Vector vel;
	local Rotator rot;
	local float range;
	local LocationInfo locInfo;
	
	if (!IsArchipelagoEnabled() || collectible.IsA('Archipelago_RandomizedItem_Base') || collectible.IsA('Archipelago_ShopItem_Base'))
		return;
	
	if (SlotData.DeathWishOnly)
		return;
	
	if (Hat_Collectible_Important(collectible) != None && Actor(collectible).CreationTime > 0)
	{
		if (Actor(collectible).Owner != None)
		{
			DebugMessage(collectible.Name $" - Owner Name: " $Actor(collectible).Owner.Name);
			
			if (Actor(collectible).Owner.IsA('Hat_Goodie_Vault_Base'))
			{
				class'Hat_SaveBitHelper'.static.RemoveLevelBit(
					class'Hat_SaveBitHelper'.static.GetBitId(Actor(collectible).Owner, 0), 1);
				
				if (class'Hat_SnatcherContract_DeathWish'.static.IsAnyActive(false))
				{
					Actor(collectible).Destroy();
					return;
				}
				
				if (IsLocationChecked(ObjectToLocationId(Actor(collectible).Owner)))
				{
					SendLocationCheck(ObjectToLocationId(Actor(collectible).Owner));
					Actor(collectible).Destroy();
					return;
				}
				
				locInfo = GetLocationInfoFromID(ObjectToLocationId(Actor(collectible).Owner));
				
				// failsafe
				if (locInfo.ID <= 0)
				{
					SendLocationCheck(ObjectToLocationId(Actor(collectible).Owner));
					Actor(collectible).Destroy();
					return;
				}
				
				spawnClass = locInfo.ItemClass;
				item = Archipelago_RandomizedItem_Base(Spawn(spawnClass,,,Actor(collectible).Location, Actor(collectible).Rotation,,true));
				item.LocationId = locInfo.ID;
				item.ItemFlags = locInfo.Flags;
				item.ItemOwner = locInfo.Player;
				item.Init();
				
				rot = item.Rotation;
				range = 65536/8;
				rot.Yaw += RandRange(range*-1,range);
				rot.Pitch += RandRange(range*-1,range);
				vel = Vector(rot)*RandRange(150,300) + vect(0,0,1)*RandRange(200,500);
				item.Bounce(vel);
				Actor(collectible).Destroy();
				return;
			}
		}
		
		if (collectible.IsA('Hat_Collectible_BadgePart') && !collectible.IsA('Hat_Collectible_BadgePart_Scooter_Subcon'))
		{
			Actor(collectible).Destroy();
		}
	}
}

function OnCollectedCollectible(Object collectible)
{
	local string message;
	local Archipelago_RandomizedItem_Base item;
	
	if (bool(DebugMode) && collectible.IsA('Hat_Collectible_Important'))
	{
		// Show location ID
		message = class'Hat_SaveBitHelper'.static.GetCorrectedMapFilename(string(Actor(collectible).GetLevelName()));
		message $= "."$collectible.Name;
		message $= "("$ObjectToLocationId(collectible)$")";
		DebugMessage(message);
	}
	
	if (!IsArchipelagoEnabled() || SlotData.DeathWishOnly)
		return;
	
	// If this is an Archipelago item or a storybook page, send it
	// CreationTime > 0 means it was from a chest, in which case we would send the chest instead
	if (SlotData.ShuffleStorybookPages && collectible.IsA('Hat_Collectible_StoryBookPage')
		&& Actor(collectible).CreationTime <= 0 && !class'Hat_SnatcherContract_DeathWish'.static.IsAnyActive(false))
	{
		SendLocationCheck(ObjectToLocationId(collectible));
		SetAPBits(class'Hat_SaveBitHelper'.static.GetBitID(collectible), 1);
	}
	else // Normal item
	{
		item = Archipelago_RandomizedItem_Base(collectible);
		
		if (item != None && !item.WasFromServer())
			SendLocationCheck(item.LocationId);
	}
}

function OnYarnCollected(optional int amount=1)
{
	local int count, cost, index, pons, i;
	local Hat_PlayerController pc;
	local Hat_Loadout loadout;
	local Hat_BackpackItem item;
	local class<Hat_Ability> abilityClass;
	
	count = GetAPBits("TotalYarnCollected", 0) + amount;
	SetAPBits("TotalYarnCollected", count);
	`GameManager.AddBadgePoints(amount);
	
	if (!SlotData.Initialized || SlotData.DeathWishOnly || SlotData.HatItems)
		return;
	
	foreach DynamicActors(class'Hat_PlayerController', pc)
	{
		loadout = pc.MyLoadout;
		break;
	}
	
	index = GetAPBits("HatCraftIndex", 1);
	for (i = index; i <= 5; i++)
	{
		if (GetHatYarnCost(GetHatByIndex(i)) <= 0)
		{
			// hats can have a cost of 0, this simply means they were put into starting inventory
			index++;
		}
	}
	
	SetAPBits("HatCraftIndex", index);
	abilityClass = GetNextHat();
	cost = GetHatYarnCost(abilityClass);
	
	if (abilityClass != None && index <= 5)
	{
		if (amount > 0)
		{
			ScreenMessage("Yarn: "$count $"/"$cost, 'Warning');
		}
		
		// Stitch our new hat!
		if (count >= cost)
		{
			item = class'Hat_Loadout'.static.MakeLoadoutItem(abilityClass);
			loadout.AddBackpack(item);
			PlayHatStitchAnimation(pc, item);
			ScreenMessage("Got " $GetHatName(abilityClass), 'Warning');
			`GameManager.AddBadgePoints(-cost);
			SetAPBits("TotalYarnCollected", 0);
			SetAPBits("HatCraftIndex", index+1);
			SortPlayerHats();
		}
	}
	else if (amount > 0)
	{
		pons = 75 * amount;
		`GameManager.AddEnergyBits(pons);
		ScreenMessage("Got " $pons $" Pons from Yarn", 'Warning');
	}
}

function SortPlayerHats()
{
	`SaveManager.GetCurrentSaveData().MyBackpack2017.Hats.Sort(SortHats);
}

function class<Hat_Ability> GetNextHat()
{
	return GetHatByIndex(GetAPBits("HatCraftIndex", 1));
}

function class<Hat_Ability> GetHatByIndex(int index)
{
	local EHatType type;
	switch (index)
	{
		case 1:
			type = SlotData.Hat1;
			break;
		
		case 2:
			type = SlotData.Hat2;
			break;
		
		case 3:
			type = SlotData.Hat3;
			break;

		case 4:
			type = SlotData.Hat4;
			break;

		case 5:
			type = SlotData.Hat5;
			break;
	}
	
	switch (type)
	{
		case HatType_Sprint: 
			return class'Hat_Ability_Sprint';
		
		case HatType_Brewing: 
			return class'Hat_Ability_Chemical';
		
		case HatType_Ice: 
			return class'Hat_Ability_StatueFall';
		
		case HatType_Dweller: 
			return class'Hat_Ability_FoxMask';
		
		case HatType_TimeStop: 
			return class'Hat_Ability_TimeStop';
	}
}

function int GetHatYarnCost(class<Hat_Ability> hatClass)
{
	switch (hatClass)
	{
		case class'Hat_Ability_Sprint':
			return SlotData.SprintYarnCost;
		
		case class'Hat_Ability_Chemical':
			return SlotData.BrewingYarnCost;

		case class'Hat_Ability_StatueFall':
			return SlotData.IceYarnCost;
		
		case class'Hat_Ability_FoxMask':
			return SlotData.DwellerYarnCost;
		
		case class'Hat_Ability_TimeStop':
			return SlotData.TimeStopYarnCost;
	}
	
	return 0;
}

function SendLocationCheck(int id, optional bool scout, optional bool hint)
{
	local string jsonMessage;
	
	if (!IsFullyConnected())
	{
		if (scout)
		{
			DebugMessage("[WARNING] Tried to scout a location while not connected!");
			return;
		}
		
		ItemResender.AddLocation(id);
		SaveGame();
		return;
	}
	
	if (!scout)
	{
		jsonMessage = "[{`cmd`:`LocationChecks`,`locations`:[" $id $"]}]";
		DebugMessage("Sending location ID: " $id);
		
		if (!IsLocationChecked(id))
			SlotData.CheckedLocations.AddItem(id);
		
		PartySyncLocations_Single(id, , true);
		SaveGame();
	}
	else
	{
		if (hint)
		{
			jsonMessage = "[{`cmd`:`LocationScouts`,`locations`:[" $id $"],`create_as_hint`:2}]";
		}
		else
		{
			jsonMessage = "[{`cmd`:`LocationScouts`,`locations`:[" $id $"]}]";
		}
	}
	
	jsonMessage = Repl(jsonMessage, "`", "\"");
	Client.SendBinaryMessage(jsonMessage);
}

function SendMultipleLocationChecks(array<int> locationArray, optional bool scout, optional bool hint)
{
	local string jsonMessage;
	local int i;
	
	if (!IsFullyConnected())
	{
		if (scout || hint)
		{
			DebugMessage("[WARNING] Tried to scout locations while not connected!");
			return;
		}
		
		ItemResender.AddMultipleLocations(locationArray);
		SaveGame();
		return;
	}
	
	if (!scout)
	{
		jsonMessage = "[{`cmd`:`LocationChecks`,`locations`:[";
		for (i = 0; i < locationArray.Length; i++)
		{
			jsonMessage $= locationArray[i];
			DebugMessage("Sending location ID: " $locationArray[i]);
			
			if (!IsLocationChecked(locationArray[i]))
				SlotData.CheckedLocations.AddItem(locationArray[i]);
			
			if (i+1 < locationArray.Length)
				jsonMessage $= ",";
		}
		
		PartySyncLocations(locationArray, , true);
		SaveGame();
	}
	else
	{
		jsonMessage = "[{`cmd`:`LocationScouts`,`locations`:[";
		for (i = 0; i < locationArray.Length; i++)
		{
			jsonMessage $= locationArray[i];
			if (i+1 < locationArray.Length)
			{
				jsonMessage $= ",";
			}
		}
	}
	
	if (scout && hint)
	{
		jsonMessage $= "],`create_as_hint`:2";
	}
	else
	{
		jsonMessage $= "]";
	}
	
	jsonMessage $= "}]";
	jsonMessage = Repl(jsonMessage, "`", "\"");
	client.SendBinaryMessage(jsonMessage);
}

function WaitForContractEvent()
{
	local Actor event;
	
	// Stupid, but sending in the event actor as a timer parameter and checking if it's None/has bDeleteMe doesn't seem to work
	foreach DynamicActors(class'Actor', event)
	{
		if (event.IsA('Hat_SnatcherContractEvent'))
			return;
	}
	
	ClearTimer(NameOf(WaitForContractEvent));
	OnContractEventEnd();
}

function OnContractEventEnd()
{
	local int i;
	local Hat_SaveGame save;
	local Hat_PlayerController ctr;
	
	ContractEventActive = false;
	
	foreach DynamicActors(class'Hat_PlayerController', ctr)
	{
		ctr.bGodMode = false;
	}

	if (SlotData.TakenContracts.Length == 0)
		return;
	
	save = `SaveManager.GetCurrentSaveData();
	for (i = 0; i < SlotData.TakenContracts.Length; i++)
	{
		if (save.SnatcherContracts.Find(SlotData.TakenContracts[i]) == -1)
			save.SnatcherContracts.AddItem(SlotData.TakenContracts[i]);

		if (SlotData.TakenContracts[i].static.IsContractComplete() && save.CompletedSnatcherContracts.Find(SlotData.TakenContracts[i]) == -1)
		{
			save.CompletedSnatcherContracts.AddItem(SlotData.TakenContracts[i]);
		}
		
		DebugMessage("Restored player's contract: " $SlotData.TakenContracts[i]);
	}
	
	SlotData.TakenContracts.Length = 0;
	SaveGame();
}

function CheckContractsForDeletion()
{
	local int i, count;
	if (IsIceBrokenEvent())
		return;
	
	for (i = 0; i < SelectContracts.Length; i++)
	{
		DebugMessage("Contract Class: " $SelectContracts[i].ContractClass);
		if (SelectContracts[i].ContractClass == None ||
			SelectContracts[i].ContractClass == class'Hat_SnatcherContract_IceWall')
			continue;
		
		if (SlotData.CheckedContracts.Find(SelectContracts[i].ContractClass) != -1)
		{
			count++;
			if (count >= SelectContracts.Length) // leave at least one to prevent any edge cases where the player gets softlocked
				break;
			
			SelectContracts[i].Destroy();
		}
	}
	
	SelectContracts.Length = 0;
}

function bool IsIceBrokenEvent()
{
	local Actor a;
	foreach DynamicActors(class'Actor', a)
	{
		if (a.IsA('Hat_SnatcherContractEvent_IceBroken'))
			return true;
	}
	
	return false;
}

function BabyTrapTimer()
{
	local Hat_Player player;
	local class<Hat_CarryObject_Stackable> stackClass;
	local Hat_CarryObject_Stackable stack;
	
	foreach DynamicActors(class'Hat_Player', player)
	{
		if (player.IsA('Hat_Player_MustacheGirl'))
			continue;
	
		if (RandRange(1, 250) == 2)
		{
			stackClass = class'Archipelago_Stackable_Conductor';
		}
		else
		{
			stackClass = class'Archipelago_Stackable_ConductorBaby';
		}
		
		stack = Spawn(stackClass, , , player.Location);
		if (!player.BeginCarry(stack, true))
		{
			stack.Destroy();
			return; // There is no escape from your fate as a babysitter!
		}
	}
	
	BabyCount--;
	if (BabyCount <= 0)
	{
		ClearTimer(NameOf(BabyTrapTimer));
		SetTimer(60.0, false, NameOf(OnBabyTrapEnd));
	}
}

function OnPlayerEnterCannon(Pawn Player, Actor Cannon)
{
	DropAllBabies(Player);
}

function OnBabyTrapEnd()
{
	local Hat_Player player;
	foreach DynamicActors(class'Hat_Player', player)
	{
		DropAllBabies(player);
	}
}

function DropAllBabies(Pawn Player)
{
	local Archipelago_Stackable_Base stack;
	foreach DynamicActors(class'Archipelago_Stackable_Base', stack)
	{
		if (stack.Carrier != Player)
			continue;
		
		stack.ForceDrop();
		stack.Destroy();
	}
	
	Hat_PawnCarryable(Player).SetAnimCarryMode(ECarryMode_None);
	Hat_HUD(PlayerController(player.Controller).MyHUD).CloseHUD(class'Hat_HUDElementCarryHelp');
}

function LaserTrapTimer()
{
	local Hat_Player player;
	
	if (WorldInfo.Pauser != None)
		return;
	
	foreach DynamicActors(class'Hat_Player', player)
	{
		if (player.IsA('Hat_Player_MustacheGirl'))
			continue;
	
		Spawn(class'Archipelago_Hazard_SnatcherLaser', , , player.Location);
	}
	
	LaserCount--;
	if (LaserCount <= 0)
		ClearTimer(NameOf(LaserTrapTimer));
}

function DoParadeTrap()
{
	local Hat_Enemy_ScienceBand_Base member, lastMember[2];
	local int i, playerIndex;
	local Hat_Player p, player, player2;
	local Vector loc;
	local float time, mult;
	local bool timerActive;
	
	foreach DynamicActors(class'Hat_Player', p)
	{
		if (p.IsA('Hat_Player_MustacheGirl'))
			continue;
			
		if (p.IsA('Hat_Player_CoPartner'))
			player2 = p;
		else
			player = p;
	}
	
	lastMember[0] = None;
	lastMember[1] = None;
	timerActive = IsTimerActive(NameOf(ActivateParade));
	
	for (i = 0; i < ParadeTrapMembers; i++)
	{
		for (playerIndex = 0; playerIndex < 2; playerIndex++)
		{
			if (playerIndex == 0 || player2 == None)
				loc = player.Location;
			else if (playerIndex == 1)
				loc = player2.Location;
				
			mult = timerActive ? ParadeArray.Length/2 : i;
				
			loc += vect(1,1,0) * (mult * 50);
			member = Spawn(class'Hat_Enemy_ScienceBand_DeadBirdBoss', , , loc, , , true);
			member.DropDownLandStingerSoundPitch = 1.0 + (ParadeArray.Length/2) * 0.2;
			member.DoDropDown(0.3*mult);
			member.FrontBandMember = lastMember[playerIndex];
			member.MimicDelay = ParadeTrapDelay + (ParadeArray.Length/2) * ParadeTrapSpread;
			member.MimicPlayerIndex = playerIndex;
			
			ParadeArray.AddItem(member);
			lastMember[playerIndex] = member;
			time += 0.3;
		}
	}
	
	if (timerActive)
		ClearTimer(NameOf(ActivateParade));
		
	SetTimer(1.0+time, false, NameOf(ActivateParade));
}

function ActivateParade()
{
	local int i;
	for (i = 0; i < ParadeArray.Length; i++)
	{
		if (ParadeArray[i].Active)
			continue;
	
		ParadeArray[i].Active = true;
		ParadeArray[i].AutoSetMimickActor();
	}
}

function ItemSoundTimer()
{
	ItemSoundCooldown = false;
}

function SpawnDecorationStands()
{
	local Actor stand;
	if (class'Hat_SeqCond_IsMuMission'.static.IsFinaleMuMission() || class'Hat_SaveBitHelper'.static.HasActBit("thefinale_ending", 1))
		return;
	
	foreach DynamicActors(class'Actor', stand)
	{
		if (stand.IsA('Hat_DecorationStand') && stand.bHidden)
		{
			stand.SetHidden(false);
		}
	}
}

function PlayHatStitchAnimation(Hat_PlayerController pc, Hat_BackpackItem item)
{
	local Hat_HUDElement element;
	element = Hat_HUD(pc.MyHUD).OpenHUD(class'Hat_HUDElementStitchNewHat');
	Hat_HUDElementStitchNewHat(element).SetItemInfo(pc.MyHUD, item);
}

function string GetHatName(class<Hat_Ability> abilityClass)
{
	switch (abilityClass)
	{
		case class'Hat_Ability_Sprint':
			return "Sprint Hat";
			
		case class'Hat_Ability_Chemical':
			return "Brewing Hat";
			
		case class'Hat_Ability_StatueFall':
			return "Ice Hat";
			
		case class'Hat_Ability_FoxMask':
			return "Dweller Mask";
			
		case class'Hat_Ability_TimeStop':
			return "Time Stop Hat";
			
		default:
			return "None";
	}
}

function ReplaceUnarmedWeapon()
{
	local int i;
	local Hat_SaveGame save;
	local Hat_BackpackItem item;
	local Hat_PlayerController ctr;
	
	ctr = Hat_PlayerController(GetALocalPlayerController());
	if (ctr.MyLoadout.BackpackHasInventory(class'Archipelago_Weapon_Umbrella', true)
	|| ctr.MyLoadout.BackpackHasInventory(class'Archipelago_Weapon_BaseballBat', true))
		return;
	
	save = `SaveManager.GetCurrentSaveData();
	
	for (i = 0; i < save.MyBackpack2017.Weapons.Length; i++)
	{
		item = save.MyBackpack2017.Weapons[i];
		if (item != None)
		{
			if (class<Hat_Weapon_Umbrella>(item.BackpackClass) != None 
			&& class<Archipelago_Weapon_Umbrella>(item.BackpackClass) == None)
			{
				ctr.MyLoadout.RemoveBackpack(item);
			}
			
			if (SlotData.UmbrellaLogic && class<Hat_Weapon_Unarmed>(item.BackpackClass) != None)
			{
				ctr.MyLoadout.RemoveBackpack(item);
				item.BackpackClass = class'Archipelago_Weapon_Unarmed';
				ctr.MyLoadout.AddBackpack(item, true, true, Hat_Player(ctr.Pawn));
			}
		}
	}
}

function DeleteCameraParticle()
{
	local Emitter e;
	foreach AllActors(class'Emitter', e)
	{
		if (e.Name == 'Emitter_265' || e.Name == 'Emitter_267')
		{
			e.ParticleSystemComponent.KillParticlesForced();
			e.ShutDown();
		}
	}
}

// For recording location IDs
function PrintItemsNearPlayer()
{
	local Hat_Player player;
	local Hat_Collectible_Important collectible;
	local Hat_Collectible_StoryBookPage page;
	
	if (!bool(DebugMode))
		return;

	player = Hat_Player(GetALocalPlayerController().Pawn);
	foreach DynamicActors(class'Hat_Collectible_Important', collectible)
	{
		if (!collectible.Enabled || collectible.IsA('Archipelago_RandomizedItem_Base') || collectible.IsA('Hat_Collectible_VaultCode_Base'))
			continue;
	
		if (GetVectorDistance(player.Location, collectible.Location) <= 1000.0)
		{
			ScreenMessage("[PrintItemsNearPlayer] Found collectible: " $collectible.Name $"("$ObjectToLocationId(collectible)$")");
		}
	}
	
	foreach DynamicActors(class'Hat_Collectible_StoryBookPage', page)
	{
		if (GetVectorDistance(player.Location, page.Location) <= 1000.0)
		{
			ScreenMessage("[PrintItemsNearPlayer] Found collectible: " $page.Name $"("$ObjectToLocationId(page)$")");
		}
	}
}

function BeatGame()
{
	local JsonObject json;
	
	SetAPBits("HasBeatenGame", 1);
	if (!IsFullyConnected())
		return;
	
	json = new class'JsonObject';
	json.SetStringValue("cmd", "StatusUpdate");
	json.SetIntValue("status", 30);
	client.SendBinaryMessage(EncodeJson2(json));
	ScreenMessage("Total Checks: " $SlotData.CheckedLocations.Length $"/"$SlotData.TotalLocations);
	json = None;
}

function bool IsDLC1Installed(optional bool AndEnabled)
{
	return class'Hat_GameDLCInfo'.static.IsGameDLCInfoInstalled(class'Hat_GameDLCInfo_DLC1') && (!AndEnabled || SlotData.DLC1);
}

function bool IsDLC2Installed(optional bool AndEnabled)
{
	return class'Hat_GameDLCInfo'.static.IsGameDLCInfoInstalled(class'Hat_GameDLCInfo_DLC2') && (!AndEnabled || SlotData.DLC2);
}

function bool IsOnlineParty()
{
	return class'Hat_GhostPartyPlayerStateBase'.static.ConfigGetUseOnlineFunctionality();
}

function PartySyncLocations(array<int> locIds, optional Hat_GhostPartyPlayerStateBase Receiver, optional bool IsLive)
{
	local JsonObject locSync;
	local int i;
	
	if (!IsOnlineParty())
		return;

	locSync = new class'JsonObject';
	for (i = 0; i < locIds.Length; i++)
	{
		locSync.SetIntValue(string(i), locIds[i]);
	}
	
	if (IsLive)
	{
		locSync.SetBoolValue("IsLive", true);
	}
	
	SendOnlinePartyCommand(locSync.EncodeJson(locSync), 'APLocationSync', GetALocalPlayerController().Pawn, Receiver);
	locSync = None;
}

function PartySyncActs(array<string> hourglasses, optional Hat_GhostPartyPlayerStateBase Receiver)
{
	local JsonObject actSync;
	local int i;

	if (!IsOnlineParty())
		return;
	
	actSync = new class'JsonObject';
	for (i = 0; i < hourglasses.Length; i++)
	{
		actSync.SetStringValue(string(i), hourglasses[i]);
	}
	
	SendOnlinePartyCommand(actSync.EncodeJson(actSync), 'APActSync', GetALocalPlayerController().Pawn, Receiver);
	actSync = None;
}

function PartySyncLocations_Single(int locId, optional Hat_GhostPartyPlayerStateBase Receiver, optional bool IsLive)
{
	local array<int> dummy;
	dummy.AddItem(locId);
	PartySyncLocations(dummy, Receiver, IsLive);
}

function PartySyncActs_Single(string hourglass, optional Hat_GhostPartyPlayerStateBase Receiver)
{
	local array<string> dummy;
	dummy.AddItem(hourglass);
	PartySyncActs(dummy, Receiver);
}

function bool IsArchipelagoEnabled()
{
	if (IsInTitlescreen() || IsCurrentPatch())
		return false;
	
	return HasAPBit("ArchipelagoEnabled", 1);
}

function bool IsCurrentPatch()
{
	local string version;
	version = class'Engine'.static.GetBuildDate();
	
	// 2021 and later is around the time when TcpLink broke, which means we can't function. We only want 2019 or 2020 builds.
	if (InStr(version, "2019") == -1 && InStr(version, "2020") == -1)
		return true;
	
	return false;
}

function bool IsInTitlescreen()
{
	return `GameManager.GetCurrentMapFilename() ~= `GameManager.TitleScreenMapName;
}

// Archipelago requires JSON messages to be encased in []
function string EncodeJson2(JsonObject json)
{
	local string message;
	message = "["$class'JsonObject'.static.EncodeJson(json)$"]";
	return message;
}

// Removes the \# at the start of the string when reading a value
// This is mainly used to properly retrieve number values that could potentially be 64 bit which would break with JsonObject.GetIntValue()
function string GetStringValue2(JsonObject json, string key)
{
	return Mid(json.GetStringValue(key), 2);
}

function bool IsFullyConnected()
{
	return client != None && client.FullyConnected && !client.ConnectingToAP && client.LinkState == STATE_Connected;
}

function bool IsDeathLinkEnabled()
{
	return !DeathLinked && SlotData.DeathLink && !ContractEventActive;
}

function bool IsInSpaceship()
{
	return `GameManager.GetCurrentMapFilename() ~= `GameManager.HubMapName;
}

function bool IsActReallyCompleted(Hat_ChapterActInfo act)
{
	local Hat_ChapterActInfo shuffled;
	if (SlotData != None && SlotData.Initialized)
	{
		if (SlotData.DeathWishOnly)
			return true;
		
		if (SlotData.ActRando)
		{
			// Free roam acts are free!
			if (IsChapterActInfoUnlocked(act))
			{
				shuffled = GetShuffledAct(act);
				if (shuffled != None && shuffled.hourglass == "")
				{
					// If the original act is a rift, and the new act a free roam, check if we actually entered the rift portal
					if (act.IsBonus && !HasAPBit("RiftEntered_"$act.hourglass, 1))
						return false;
					
					// hotfix for metro intro time piece becoming unobtainable if nyakuza is vanilla
					if (act.hourglass ~= "Metro_Intro" && shuffled.ActID >= 98)
						return true;
					
					SetAPBits("ActComplete_"$act.hourglass, 1);
					PartySyncActs_Single(act.hourglass);
					return true;
				}
			}
		}
		else if (act.hourglass == "")
		{
			return true;
		}
	}
	
	return HasAPBit("ActComplete_"$act.hourglass, 1);
}

function bool IsSaveFileJustLoaded()
{
	return GetAPBits("SaveFileLoad") == 0;
}

function bool IsActFreeRoam(Hat_ChapterActInfo act)
{
	// -_-
	if (act.Hourglass ~= "AlpineSkyline_Finale")
		return false;
	
	return (act.ChapterInfo != None && (act.ChapterInfo.IsActless || act.ChapterInfo.HasFreeRoam)
	&& (act.ActID == 99 || (act.ChapterInfo.ActIDAfterIntro > 0 && act.ActID == act.ChapterInfo.ActIDAfterIntro)) && !act.IsBonus);
}

function Hat_ChapterActInfo GetOriginalAct(Hat_ChapterActInfo act, optional out int basement)
{
	local int i;
	for (i = 0; i < SlotData.ShuffledActList.Length; i++)
	{
		if (SlotData.ShuffledActList[i].NewAct != None && SlotData.ShuffledActList[i].NewAct == act)
		{
			basement = int(SlotData.ShuffledActList[i].IsDeadBirdBasementOriginalAct);
			return SlotData.ShuffledActList[i].OriginalAct;
		}
	}
	
	return None;
}

function Hat_ChapterActInfo GetShuffledAct(Hat_ChapterActInfo act, optional out int basement)
{
	local int i;
	for (i = 0; i < SlotData.ShuffledActList.Length; i++)
	{
		if (SlotData.ShuffledActList[i].OriginalAct != None && SlotData.ShuffledActList[i].OriginalAct == act)
		{
			basement = int(SlotData.ShuffledActList[i].IsDeadBirdBasementShuffledAct);
			return SlotData.ShuffledActList[i].NewAct;
		}
	}
	
	return None;
}

function Hat_ChapterActInfo GetDeadBirdBasementShuffledAct(optional out int vanilla)
{
	local int i;
	for (i = 0; i < SlotData.ShuffledActList.Length; i++)
	{
		if (SlotData.ShuffledActList[i].IsDeadBirdBasementOriginalAct)
		{
			if (SlotData.ShuffledActList[i].IsDeadBirdBasementShuffledAct)
			{
				vanilla = 1;
			}
			
			return SlotData.ShuffledActList[i].NewAct;
		}
	}
	
	return None;
}

function Hat_ChapterActInfo GetRiftActFromMapName(string MapName)
{
	local array<Hat_ChapterInfo> chapterInfoArray;
	local Hat_ChapterInfo chapter;
	local Hat_ChapterActInfo act;
	
	chapterInfoArray = class'Hat_ChapterInfo'.static.GetAllChapterInfo();
	foreach chapterInfoArray(chapter)
	{
		chapter.ConditionalUpdateActList();
		foreach chapter.ChapterActInfo(act)
		{
			if (act.MapName ~= MapName)
				return act;
		}
	}
	
	return None;
}

function ScreenMessage(String message, optional Name type)
{
	local PlayerController pc;
	
	if (bool(VerboseLogging))
	{
		// Don't ask.
		DebugMsg = message;
		ConsoleCommand("getall Archipelago_GameMod DebugMsg");
	}
	
	pc = GetALocalPlayerController();
    if (pc == None)
		return;
    
    pc.ClientMessage(message, type, 8);
}

function DebugMessage(String message, optional Name type)
{
	local PlayerController pc;
	if (bool(VerboseLogging))
	{
		DebugMsg = message;
		ConsoleCommand("getall Archipelago_GameMod DebugMsg");
	}
	
	if (!bool(DebugMode))
		return;
	
	pc = GetALocalPlayerController();
    if (pc == None)
		return;
    
    pc.ClientMessage(message, type, 8);
}

delegate int SortHats(Hat_LoadoutBackpackItem A, Hat_LoadoutBackpackItem B)
{
	return GetHatPriority(class<Hat_Ability>(A.BackpackClass)) > GetHatPriority(class<Hat_Ability>(B.BackpackClass)) ? -1 : 0;
}

function int GetHatPriority(class<Hat_Ability> hat)
{
	switch (hat)
	{
		case class'Hat_Ability_Help':
			return 0;

		case class'Hat_Ability_Sprint':
			return 1;

		case class'Hat_Ability_Chemical':
			return 2;
		
		case class'Hat_Ability_StatueFall':
			return 3;

		case class'Hat_Ability_FoxMask':
			return 4;
		
		case class'Hat_Ability_TimeStop':
			return 5;
	}
}

function int ObjectToLocationId(Object obj)
{
	local int i, id;
	local string fullName;
	
	if (obj == None)
	{
		DebugMessage("[ObjectToLocationId] obj is None");
		ScriptTrace();
	}
	
	fullName = class'Hat_SaveBitHelper'.static.GetCorrectedMapFilename(string(Actor(obj).GetLevelName()))$"."$obj.Name;
	
	// Convert the object's name to an ID, using the Unicode values of the characters
	for (i = 0; i < Len(fullName); i++)
	{
		id += Asc(Mid(fullName, i, 1));
	}
	
	if (obj.IsA('Hat_Collectible_StoryBookPage'))
	{
		id += StoryBookPageIDRange;
		if (`GameManager.GetChapterInfo().ChapterID == 6)
		{
			id += 1000;
		}
	}
	else
	{
		id += GetChapterIDRange(`GameManager.GetChapterInfo());
	}
	
	return id;
}

function Actor LocationIdToObject(int id, optional class<Actor> TargetClass)
{
	local Actor a;
	foreach DynamicActors(class'Actor', a)
	{
		if (TargetClass == class'Archipelago_RandomizedItem_Base')
		{
			if (a.Class == TargetClass || ClassIsChildOf(a.class, TargetClass))
			{
				if (Archipelago_RandomizedItem_Base(a).LocationID == id)
					return a;
			}
		}
		else if (ObjectToLocationId(a) == id && (TargetClass == None || a.Class == TargetClass || ClassIsChildOf(a.class, TargetClass)))
		{
			return a;
		}
	}
	
	return None;
}

function UnlockAlmostEverything()
{
	local Hat_SaveGame save;
	local array<Hat_ChapterInfo> chapterArray;
	local Hat_ChapterInfo chapter;
	local Hat_ChapterActInfo act;
	local Hat_Loadout lo;

	lo = Hat_PlayerController(GetALocalPlayerController()).MyLoadout;
	
	// all Time Pieces
	chapterArray = class'Hat_ChapterInfo'.static.GetAllChapterInfo();
	save = `SaveManager.GetCurrentSaveData();
	
	foreach chapterArray(chapter)
	{
		foreach chapter.ChapterActInfo(act)
		{
			if (act.hourglass == "")
				continue;
			
			if (act.RequiredDLC != None && !class'Hat_GameDLCInfo'.static.IsGameDLCInfoInstalled(act.RequiredDLC))
				continue;
			
			save.GiveTimePiece(act.hourglass, false);
			if (IsPurpleRift(act))
				save.UnlockSecretLevel(act.hourglass);
		}
	}
	
	save.GiveTimePiece("chapter3_secret_finale", false);
	save.GiveTimePiece("Metro_Intro", false);
	
	// all hats
	lo.AddBackpack(class'Hat_Loadout'.static.MakeLoadoutItem(class'Hat_Ability_Sprint'));
	lo.AddBackpack(class'Hat_Loadout'.static.MakeLoadoutItem(class'Hat_Ability_Chemical'));
	lo.AddBackpack(class'Hat_Loadout'.static.MakeLoadoutItem(class'Hat_Ability_StatueFall'));
	lo.AddBackpack(class'Hat_Loadout'.static.MakeLoadoutItem(class'Hat_Ability_FoxMask'));
	lo.AddBackpack(class'Hat_Loadout'.static.MakeLoadoutItem(class'Hat_Ability_TimeStop'));
	
	// umbrella
	if (SlotData.BaseballBat)
		lo.AddBackpack(class'Hat_Loadout'.static.MakeBackpackItem(class'Archipelago_Weapon_BaseballBat'), true);
	else
		lo.AddBackpack(class'Hat_Loadout'.static.MakeBackpackItem(class'Archipelago_Weapon_Umbrella'), true);
	
	// hookshot, camera, one hit hero
	lo.AddBackpack(class'Hat_Loadout'.static.MakeBackpackItem(class'Hat_Ability_Hookshot'), true);
	lo.AddBackpack(class'Hat_Loadout'.static.MakeBackpackItem(class'Hat_Badge_OneHitDeath'));
	lo.AddBackpack(class'Hat_Loadout'.static.MakeBackpackItem(class'Hat_Ability_Camera'));
	
	`GameManager.AddBadgeSlots(2);
	`GameManager.AddEnergyBits(99999);
}

// DO NOT use the 2000310000 range, that is for act completion location IDs
function int GetChapterIDRange(Hat_ChapterInfo chapter)
{
	switch (chapter)
	{
		case Hat_ChapterInfo'HatinTime_ChapterInfo.maingame.subconforest':
			return Chapter3IDRange;
			
		case Hat_ChapterInfo'HatinTime_ChapterInfo.maingame.Sand_and_Sails':
			return Chapter4IDRange;
			
		default:
			return BaseIDRange;
	}
}

function string PlayerIdToName(int id)
{
	if (id <= 0)
		return "Archipelago";
	
	if (id >= SlotData.PlayerNames.Length || SlotData.PlayerNames[id] == "")
		return "Unknown Player";
	
	return SlotData.PlayerNames[id];
}

// Equivalent to Repl(), but only replaces the given string once
function bool ReplOnce(string str, string match, string with, out string result, optional bool caseSensitive)
{
	local int index;
	local string l;
	local string r;
	local bool found;
	
	result = str;
	index = InStr(str, match, false, !caseSensitive);
	
	if (index != -1)
	{
		found = true;
	
		// Slice out the left and right parts of the string
		l = Left(str, index+Len(match));
		r = Split(str, l, true);
		l = Repl(l, match, "", caseSensitive);
		result = l$with$r;
	}
	
	return found;
}

function CleanUpMetro()
{
	local int i;
	local Actor a;
	local array<SequenceObject> seqObjects;
	
	foreach DynamicActors(class'Actor', a)
	{
		// Force open jewelry store door, otherwise player gets trapped inside of it after collecting a Time Piece
		// Force open the barrier near the jewelry store, and remove the crates covering the mud puddle
		if (a.Name == 'InterpActor_10' || a.Name == 'InterpActor_13'
			|| a.Name == 'Hat_DynamicStaticActor_17' || a.Name == 'Hat_DynamicStaticActor_18'
			|| a.Name == 'Hat_DynamicStaticActor_35' || a.Name == 'Hat_DynamicStaticActor_36'
			|| a.Name == 'Hat_DynamicStaticActor_37' || a.Name == 'Hat_DynamicStaticActor_38')
		{
			ConsoleCommand("set " $a.Name $" bnodelete false"); // Fuck you. Die.
			a.Destroy();
		}
		
		// These are the opened jewelery store doors, unhide them
		if (a.Name == 'InterpActor_14' || a.Name == 'InterpActor_17')
		{
			a.SetHidden(false);
		}
		
		// Remove the cat holding the time piece if we already completed the intro
		if (a.IsA('Hat_Goodie_Chaser_Base') && HasAPBit("ActComplete_Metro_Intro", 1))
		{
			a.Destroy();
		}
		
		// Hide the Time Piece as well
		if (a.Name == 'Hat_TimeObject_Metro_2' && HasAPBit("ActComplete_Metro_Intro", 1))
		{
			a.SetHidden(true);
		}
	}
	
	WorldInfo.GetGameSequence().FindSeqObjectsByClass(class'SeqAct_ToggleHidden', true, seqObjects);
	for (i = 0; i < seqObjects.Length; i++)
	{
		// this hides the opened doors in the jewelery store
		if (seqObjects[i].Name == 'SeqAct_ToggleHidden_18')
		{
			SeqAct_ToggleHidden(seqObjects[i]).Targets.Length = 0;
			break;
		}
	}
}

function float GetVectorDistance(Vector start, Vector end)
{
	local float distance;
	distance = Abs(start.x - end.x);
	distance += Abs(start.y - end.y);
	distance += Abs(start.z - end.z);
	return distance;
}

static function bool SetAPBits(string id, int i, optional Hat_SaveGame_Base save)
{
	return class'Hat_SaveBitHelper'.static.SetLevelBits(id, i, ArchipelagoPrefix, save);
}

static function bool HasAPBit(string id, int i, optional Hat_SaveGame_Base save)
{
	return class'Hat_SaveBitHelper'.static.HasLevelBit(id, i, ArchipelagoPrefix, save);
}

static function int GetAPBits(string id, optional int defaultValue=0, optional Hat_SaveGame_Base save)
{
	return class'Hat_SaveBitHelper'.static.GetLevelBits(id, ArchipelagoPrefix, save, defaultValue);
}

// Borrowed this handy function from Jawchewa, 
// you can access the mod actor via the `AP macro
// if you have `include(APRandomizer\Classes\Globals.uci); in your file.
static function Archipelago_GameMod GetGameMod()
{
    local Archipelago_GameMod mod;
    
    foreach class'WorldInfo'.static.GetWorldInfo().DynamicActors(class'Archipelago_GameMod', mod)
    {
		return mod;
    }
    
    return None;
}

defaultproperties
{
	bAlwaysTick = true;
	ParadeTrapMembers = 4;
	ParadeTrapDelay = 1;
	ParadeTrapSpread = 1;
	SpaceshipSpawnLocation = (x=-134, y=295, z=295);
	Camera1Loc = (x=-5367,y=6471,z=-468);
	Camera2Loc = (x=5767,y=6763,z=-496);
	
	UnlockScreenNumbers[0] = Texture2D'APRandomizer_content.unlock_screen_numbers_00';
	UnlockScreenNumbers[1] = Texture2D'APRandomizer_content.unlock_screen_numbers_01';
	UnlockScreenNumbers[2] = Texture2D'APRandomizer_content.unlock_screen_numbers_02';
	UnlockScreenNumbers[3] = Texture2D'APRandomizer_content.unlock_screen_numbers_03';
	UnlockScreenNumbers[4] = Texture2D'APRandomizer_content.unlock_screen_numbers_04';
	UnlockScreenNumbers[5] = Texture2D'APRandomizer_content.unlock_screen_numbers_05';
	UnlockScreenNumbers[6] = Texture2D'APRandomizer_content.unlock_screen_numbers_06';
	UnlockScreenNumbers[7] = Texture2D'APRandomizer_content.unlock_screen_numbers_07';
	UnlockScreenNumbers[8] = Texture2D'APRandomizer_content.unlock_screen_numbers_08';
	UnlockScreenNumbers[9] = Texture2D'APRandomizer_content.unlock_screen_numbers_09';
	UnlockScreenNumbers[10] = Texture2D'APRandomizer_content.unlock_screen_numbers_10';
	UnlockScreenNumbers[11] = Texture2D'APRandomizer_content.unlock_screen_numbers_11';
	UnlockScreenNumbers[12] = Texture2D'APRandomizer_content.unlock_screen_numbers_12';
	UnlockScreenNumbers[13] = Texture2D'APRandomizer_content.unlock_screen_numbers_13';
	UnlockScreenNumbers[14] = Texture2D'APRandomizer_content.unlock_screen_numbers_14';
	UnlockScreenNumbers[15] = Texture2D'APRandomizer_content.unlock_screen_numbers_15';
	UnlockScreenNumbers[16] = Texture2D'APRandomizer_content.unlock_screen_numbers_16';
	UnlockScreenNumbers[17] = Texture2D'APRandomizer_content.unlock_screen_numbers_17';
	UnlockScreenNumbers[18] = Texture2D'APRandomizer_content.unlock_screen_numbers_18';
	UnlockScreenNumbers[19] = Texture2D'APRandomizer_content.unlock_screen_numbers_19';
	UnlockScreenNumbers[20] = Texture2D'APRandomizer_content.unlock_screen_numbers_20';
	UnlockScreenNumbers[21] = Texture2D'APRandomizer_content.unlock_screen_numbers_21';
	UnlockScreenNumbers[22] = Texture2D'APRandomizer_content.unlock_screen_numbers_22';
	UnlockScreenNumbers[23] = Texture2D'APRandomizer_content.unlock_screen_numbers_23';
	UnlockScreenNumbers[24] = Texture2D'APRandomizer_content.unlock_screen_numbers_24';
	UnlockScreenNumbers[25] = Texture2D'APRandomizer_content.unlock_screen_numbers_25';
	UnlockScreenNumbers[26] = Texture2D'APRandomizer_content.unlock_screen_numbers_26';
	UnlockScreenNumbers[27] = Texture2D'APRandomizer_content.unlock_screen_numbers_27';
	UnlockScreenNumbers[28] = Texture2D'APRandomizer_content.unlock_screen_numbers_28';
	UnlockScreenNumbers[29] = Texture2D'APRandomizer_content.unlock_screen_numbers_29';
	UnlockScreenNumbers[30] = Texture2D'APRandomizer_content.unlock_screen_numbers_30';
	UnlockScreenNumbers[31] = Texture2D'APRandomizer_content.unlock_screen_numbers_31';
	UnlockScreenNumbers[32] = Texture2D'APRandomizer_content.unlock_screen_numbers_32';
	UnlockScreenNumbers[33] = Texture2D'APRandomizer_content.unlock_screen_numbers_33';
	UnlockScreenNumbers[34] = Texture2D'APRandomizer_content.unlock_screen_numbers_34';
	UnlockScreenNumbers[35] = Texture2D'APRandomizer_content.unlock_screen_numbers_35';
	UnlockScreenNumbers[36] = Texture2D'APRandomizer_content.unlock_screen_numbers_36';
	UnlockScreenNumbers[37] = Texture2D'APRandomizer_content.unlock_screen_numbers_37';
	UnlockScreenNumbers[38] = Texture2D'APRandomizer_content.unlock_screen_numbers_38';
	UnlockScreenNumbers[39] = Texture2D'APRandomizer_content.unlock_screen_numbers_39';
	UnlockScreenNumbers[40] = Texture2D'APRandomizer_content.unlock_screen_numbers_40';
	UnlockScreenNumbers[41] = Texture2D'APRandomizer_content.unlock_screen_numbers_41';
	UnlockScreenNumbers[42] = Texture2D'APRandomizer_content.unlock_screen_numbers_42';
	UnlockScreenNumbers[43] = Texture2D'APRandomizer_content.unlock_screen_numbers_43';
	UnlockScreenNumbers[44] = Texture2D'APRandomizer_content.unlock_screen_numbers_44';
	UnlockScreenNumbers[45] = Texture2D'APRandomizer_content.unlock_screen_numbers_45';
	UnlockScreenNumbers[46] = Texture2D'APRandomizer_content.unlock_screen_numbers_46';
	UnlockScreenNumbers[47] = Texture2D'APRandomizer_content.unlock_screen_numbers_47';
	UnlockScreenNumbers[48] = Texture2D'APRandomizer_content.unlock_screen_numbers_48';
	UnlockScreenNumbers[49] = Texture2D'APRandomizer_content.unlock_screen_numbers_49';
	UnlockScreenNumbers[50] = Texture2D'APRandomizer_content.unlock_screen_numbers_50';
	
	ThugCatShops[0] = "Hat_NPC_NyakuzaShop_0";
	ThugCatShops[1] = "Hat_NPC_NyakuzaShop_1";
	ThugCatShops[2] = "Hat_NPC_NyakuzaShop_2";
	ThugCatShops[3] = "Hat_NPC_NyakuzaShop_5";
	ThugCatShops[4] = "Hat_NPC_NyakuzaShop_13";
	ThugCatShops[5] = "Hat_NPC_NyakuzaShop_12";
	ThugCatShops[6] = "Hat_NPC_NyakuzaShop_14";
	ThugCatShops[7] = "Hat_NPC_NyakuzaShop_4";
	ThugCatShops[8] = "Hat_NPC_NyakuzaShop_6";
	ThugCatShops[9] = "Hat_NPC_NyakuzaShop_7";
}
