from BaseClasses import Item, ItemClassification, Region
from .Items import HatInTimeItem, ahit_items, time_pieces, item_frequencies, item_dlc_enabled, item_table, junk_weights
from .Regions import create_region, create_regions, connect_regions, randomize_act_entrances, chapter_act_info
from .Locations import HatInTimeLocation, location_table, get_total_locations
from .Types import HatDLC, HatType, ChapterIndex
from .Options import ahit_options
from ..AutoWorld import World
from .Rules import set_rules
import typing


class HatInTimeWorld(World):
    """
    A Hat in Time is a cute-as-heck 3D platformer featuring a little girl who stitches hats for wicked powers!
    Freely explore giant worlds and recover Time Pieces to travel to new heights!
    """

    game = "A Hat in Time"
    data_version = 1

    item_name_to_id = {name: data.code for name, data in item_table.items()}
    location_name_to_id = {name: data.id for name, data in location_table.items()}

    option_definitions = ahit_options

    hat_craft_order: typing.List[HatType] = [HatType.SPRINT, HatType.BREWING, HatType.ICE,
                                             HatType.DWELLER, HatType.TIME_STOP]

    hat_yarn_costs: typing.Dict[HatType, int] = {HatType.SPRINT: -1, HatType.BREWING: -1, HatType.ICE: -1,
                                                 HatType.DWELLER: -1, HatType.TIME_STOP: -1}

    chapter_timepiece_costs: typing.Dict[ChapterIndex, int] = {ChapterIndex.MAFIA: -1,
                                                               ChapterIndex.BIRDS: -1,
                                                               ChapterIndex.SUBCON: -1,
                                                               ChapterIndex.ALPINE: -1,
                                                               ChapterIndex.FINALE: -1,
                                                               ChapterIndex.CRUISE: -1,
                                                               ChapterIndex.METRO: -1}

    act_connections: typing.Dict[str, str] = {}

    def create_items(self):
        # Item Pool
        itempool: typing.List[Item] = []
        self.calculate_yarn_costs()

        self.topology_present = self.multiworld.ActRandomizer[self.player].value
        yarn_pool: typing.List[Item] = self.create_multiple_items("Yarn", self.multiworld.YarnAvailable[self.player].value)
        total_yarn_required = 0
        for value in self.hat_yarn_costs.values():
            total_yarn_required += value

        count = 0
        for yarn in yarn_pool:
            count += 1
            if count > total_yarn_required:
                yarn.classification = ItemClassification.filler

        itempool += yarn_pool

        if self.multiworld.RandomizeHatOrder[self.player].value > 0:
            self.multiworld.random.shuffle(self.hat_craft_order)

        minimum = self.multiworld.Chapter5MinCost[self.player].value
        maximum = self.multiworld.Chapter5MaxCost[self.player].value
        self.set_chapter_cost(ChapterIndex.FINALE, self.multiworld.random.randint(min(minimum, maximum), max(minimum, maximum)))
        required_time_pieces = self.get_chapter_cost(ChapterIndex.FINALE)

        for name in ahit_items.keys():
            if name == "Yarn":
                continue

            if not item_dlc_enabled(self, name):
                continue

            if ahit_items.get(name).classification == ItemClassification.filler:
                continue

            if ahit_items.get(name).classification == ItemClassification.trap:
                continue

            itempool += self.create_multiple_items(name, item_frequencies.get(name, 1))

        time_piece_count: int = 0
        for name in time_pieces.keys():
            if not item_dlc_enabled(self, name):
                continue

            time_piece = self.create_item(name)
            if time_piece_count > required_time_pieces:
                time_piece.classification = ItemClassification.filler

            itempool += [time_piece]
            time_piece_count += 1

        itempool += self.create_junk_items(get_total_locations(self)-len(itempool))
        self.multiworld.itempool += itempool

    def create_regions(self):
        create_regions(self)

    def set_rules(self):
        if self.multiworld.ActRandomizer[self.player].value > 0:
            randomize_act_entrances(self)

        set_rules(self)

    def write_spoiler(self, spoiler_handle: typing.TextIO):
        for i in self.chapter_timepiece_costs.keys():
            spoiler_handle.write("Chapter %i Cost: %i\n" % (i, self.chapter_timepiece_costs[ChapterIndex(i)]))

        for hat in self.hat_craft_order:
            spoiler_handle.write("Hat Cost: %s: %i\n" % (hat, self.hat_yarn_costs[hat]))

    def fill_slot_data(self) -> dict:
        slot_data: dict = {"SprintYarnCost": self.hat_yarn_costs[HatType.SPRINT],
                           "BrewingYarnCost": self.hat_yarn_costs[HatType.BREWING],
                           "IceYarnCost": self.hat_yarn_costs[HatType.ICE],
                           "DwellerYarnCost": self.hat_yarn_costs[HatType.DWELLER],
                           "TimeStopYarnCost": self.hat_yarn_costs[HatType.TIME_STOP],
                           "Chapter1Cost": self.chapter_timepiece_costs[ChapterIndex.MAFIA],
                           "Chapter2Cost": self.chapter_timepiece_costs[ChapterIndex.BIRDS],
                           "Chapter3Cost": self.chapter_timepiece_costs[ChapterIndex.SUBCON],
                           "Chapter4Cost": self.chapter_timepiece_costs[ChapterIndex.ALPINE],
                           "Chapter5Cost": self.chapter_timepiece_costs[ChapterIndex.FINALE],
                           "Hat1": int(self.hat_craft_order[0]),
                           "Hat2": int(self.hat_craft_order[1]),
                           "Hat3": int(self.hat_craft_order[2]),
                           "Hat4": int(self.hat_craft_order[3]),
                           "Hat5": int(self.hat_craft_order[4])}

        if self.multiworld.ActRandomizer[self.player].value > 0:
            for name in self.act_connections.keys():
                slot_data[name] = self.act_connections[name]

        for option_name in ahit_options:
            option = getattr(self.multiworld, option_name)[self.player]
            slot_data[option_name] = option.value

        return slot_data

    def create_item(self, name: str) -> Item:
        if name in time_pieces.keys():
            data = time_pieces[name]
        else:
            data = ahit_items[name]
            
        return HatInTimeItem(name, data.classification, data.code, self.player)

    def create_multiple_items(self, name: str, count: int = 1) -> typing.List[Item]:
        data = ahit_items[name] or time_pieces[name]
        itemlist: typing.List[Item] = []

        for i in range(count):
            itemlist += [HatInTimeItem(name, data.classification, data.code, self.player)]

        return itemlist

    def create_junk_items(self, count: int) -> typing.List[Item]:
        trap_chance = self.multiworld.TrapChance[self.player].value
        junk_pool: typing.List[Item] = []
        junk_list: typing.Dict[str, int] = {}
        trap_list: typing.Dict[str, int] = {}
        ic: ItemClassification

        for name in ahit_items.keys():
            ic = ahit_items.get(name).classification
            if ic == ItemClassification.filler:
                junk_list[name] = junk_weights.get(name)
            elif trap_chance > 0 and ic == ItemClassification.trap:
                if name == "Baby Trap":
                    trap_list[name] = self.multiworld.BabyTrapWeight[self.player].value
                elif name == "Laser Trap":
                    trap_list[name] = self.multiworld.LaserTrapWeight[self.player].value
                elif name == "Parade Trap":
                    trap_list[name] = self.multiworld.ParadeTrapWeight[self.player].value

        for i in range(count):
            if trap_chance > 0 and self.multiworld.random.randint(1, 100) <= trap_chance:
                junk_pool += [self.create_item(
                    self.multiworld.random.choices(list(trap_list.keys()), weights=list(trap_list.values()), k=1)[0])]
            else:
                junk_pool += [self.create_item(
                    self.multiworld.random.choices(list(junk_list.keys()), weights=list(junk_list.values()), k=1)[0])]

        return junk_pool

    def calculate_yarn_costs(self):
        min_yarn_cost = int(min(self.multiworld.YarnCostMin[self.player].value, self.multiworld.YarnCostMax[self.player].value))
        max_yarn_cost = int(max(self.multiworld.YarnCostMin[self.player].value, self.multiworld.YarnCostMax[self.player].value))
        max_possible_cost = max_yarn_cost * 5
        available_yarn = self.multiworld.YarnAvailable[self.player].value
        if max_possible_cost > available_yarn:
            self.multiworld.YarnAvailable[self.player].value += max_possible_cost - available_yarn

        for i in range(5):
            cost = self.multiworld.random.randint(min(min_yarn_cost, max_yarn_cost), max(max_yarn_cost, min_yarn_cost))
            self.hat_yarn_costs.update({HatType(i): cost})

    def set_chapter_cost(self, chapter: ChapterIndex, cost: int):
        self.chapter_timepiece_costs.update({chapter: cost})

    def get_chapter_cost(self, chapter: ChapterIndex) -> int:
        return self.chapter_timepiece_costs.get(chapter)

    # Sets an act entrance in slot data by specifying the Hat_ChapterActInfo, to be used in-game
    def update_chapter_act_info(self, original_region: Region, new_region: Region):
        original_act_info = chapter_act_info[original_region.name]
        new_act_info = chapter_act_info[new_region.name]
        self.act_connections.setdefault(original_act_info, new_act_info)