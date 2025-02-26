class Archipelago_SlotData extends Object
    dependson(Archipelago_ItemInfo);

// IMPORTANT!! If you add or remove *ANYTHING* in this class, increment the SlotDataVersion value in Archipelago_GameMod!
var transient bool Initialized;
var array<ShuffledAct> ShuffledActList;
var array<LocationInfo> LocationInfoArray;
var array<ShopItemInfo> ShopItemList;
var array<ShopItemName> ShopItemNames;
var array<string> PlayerNames;
var bool PlayerNamesInitialized;

var bool ConnectedOnce;

var int PlayerSlot;
var string SlotName;
var string Password;
var string Host;
var int Port;
var int ShopItemRandStep;
var string Seed;
var string SeedName;
var array<int> CheckedLocations;
var array<int> PageLocationIDs;
var array<string> PendingCompletedActs;
var array<class< Hat_SnatcherContract_DeathWish > > PendingCompletedDeathWishes;
var Vector LastSpaceshipLocation;

var int Goal;
var int TotalLocations;
var int LogicDifficulty; // -1 = Normal, 0 = Moderate, 1 = Hard, 2 = Expert
var bool ActRando;
var bool ShuffleStorybookPages;
var bool ShuffleActContracts;
var bool ShuffleZiplines;
var bool ShuffleSubconPaintings;
var bool NoPaintingSkips;
var int CTRLogic;
var bool UmbrellaLogic;
var bool DeathLink;
var int DeathLinkAmnesty;
var int DWDeathLinkAmnesty;
var bool HatItems;

var bool DLC1;
var bool Tasksanity;
var bool ExcludeTour;
var int ShipShapeCustomTaskGoal;
var int TasksanityTaskStep;
var int TasksanityCheckCount;
var int TaskStep;
var int CompletedTasks;

var bool DLC2;
var int NoTicketSkips; // 2 means only Rush Hour ticket skips are allowed in logic
var bool BaseballBat;

var bool DeathWish;
var bool AutoCompleteBonuses;
var bool BonusRewards;
var bool DeathWishShuffle;
var bool DeathWishOnly;
var int DeathWishTPRequirement;
var array<class<Hat_SnatcherContract_DeathWish> > ShuffledDeathWishes;
var array<class<Hat_SnatcherContract_DeathWish> > CompletedDeathWishes;
var array<class<Hat_SnatcherContract_DeathWish> > PerfectedDeathWishes;
var array<class<Hat_SnatcherContract_DeathWish> > ExcludedContracts;
var array<class<Hat_SnatcherContract_DeathWish> > ExcludedBonuses;

var bool StartWithCompassBadge;
var int CompassBadgeMode;

var int Chapter1Cost;
var int Chapter2Cost;
var int Chapter3Cost;
var int Chapter4Cost;
var int Chapter5Cost;
var int Chapter6Cost;
var int Chapter7Cost;

var int SprintYarnCost;
var int BrewingYarnCost;
var int IceYarnCost;
var int DwellerYarnCost;
var int TimeStopYarnCost;

var int BadgeSellerItemCount;
var int MinPonCost;
var int MaxPonCost;
var int MetroMinPonCost;
var int MetroMaxPonCost;

var array<Hat_ChapterActInfo> LockedBlueRifts;
var array< class<Hat_SnatcherContract_Act> > ObtainedContracts;
var array< class<Hat_SnatcherContract_Act> > TakenContracts;
var array< class<Hat_SnatcherContract_Act> > CheckedContracts;

// hat stitch order
var EHatType Hat1;
var EHatType Hat2;
var EHatType Hat3;
var EHatType Hat4;
var EHatType Hat5;

defaultproperties
{
    Host="localhost";
    Port=11311;
    LastSpaceshipLocation = (x=-134, y=295, z=295);
}