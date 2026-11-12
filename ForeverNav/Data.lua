-- 交通网络数据（《魔兽世界：无限》1.60.1）
-- 航线来源：wx-wow.com、kovarel.com、wowforeveratlas.com、warcraftmaps.com、nieyi.cn（2026.11 整理）
-- 航线长度（码）来自 WarcraftMaps；游戏文件里没有航程时间，插件按长度估算。
local _, NS = ...
local D = {}
NS.Data = D

-- 地区：key = { 中文名, 英文名, 大陆, 是否主城, 怀旧服 uiMapID(仅作参考，运行时按名字匹配) }
D.ZONES = {
    -- 东部王国
    tirisfal   = { "提瑞斯法林地", "Tirisfal Glades", "EK", false, 1420 },
    undercity  = { "幽暗城", "Undercity", "EK", true, 1458 },
    silverpine = { "银松森林", "Silverpine Forest", "EK", false, 1421 },
    wpl        = { "西瘟疫之地", "Western Plaguelands", "EK", false, 1422 },
    epl        = { "东瘟疫之地", "Eastern Plaguelands", "EK", false, 1423 },
    alterac    = { "奥特兰克山脉", "Alterac Mountains", "EK", false, 1416 },
    hillsbrad  = { "希尔斯布莱德丘陵", "Hillsbrad Foothills", "EK", false, 1424 },
    hinterlands = { "辛特兰", "The Hinterlands", "EK", false, 1425 },
    arathi     = { "阿拉希高地", "Arathi Highlands", "EK", false, 1417 },
    wetlands   = { "湿地", "Wetlands", "EK", false, 1437 },
    dunmorogh  = { "丹莫罗", "Dun Morogh", "EK", false, 1426 },
    ironforge  = { "铁炉堡", "Ironforge", "EK", true, 1455 },
    lochmodan  = { "洛克莫丹", "Loch Modan", "EK", false, 1432 },
    badlands   = { "荒芜之地", "Badlands", "EK", false, 1418 },
    searing    = { "灼热峡谷", "Searing Gorge", "EK", false, 1427 },
    burning    = { "燃烧平原", "Burning Steppes", "EK", false, 1428 },
    redridge   = { "赤脊山", "Redridge Mountains", "EK", false, 1433 },
    elwynn     = { "艾尔文森林", "Elwynn Forest", "EK", false, 1429 },
    stormwind  = { "暴风城", "Stormwind City", "EK", true, 1453 },
    westfall   = { "西部荒野", "Westfall", "EK", false, 1436 },
    duskwood   = { "暮色森林", "Duskwood", "EK", false, 1431 },
    deadwind   = { "逆风小径", "Deadwind Pass", "EK", false, 1430 },
    swamp      = { "悲伤沼泽", "Swamp of Sorrows", "EK", false, 1435 },
    blasted    = { "诅咒之地", "Blasted Lands", "EK", false, 1419 },
    stv        = { "荆棘谷", "Stranglethorn Vale", "EK", false, 1434 },
    riverglades = { "河林", "Riverglades", "EK", false, nil },      -- 无限新地区，陆路连接未知，只按港口算
    -- 泽风岛（天裔出生地，不在两块大陆地图上，只能坐飞艇进出）
    zephras    = { "泽风岛", "Zephras Isle", "ISLE", false, nil },
    -- 卡利姆多
    teldrassil = { "泰达希尔", "Teldrassil", "KAL", false, 1438 },
    darnassus  = { "达纳苏斯", "Darnassus", "KAL", true, 1457 },
    darkshore  = { "黑海岸", "Darkshore", "KAL", false, 1439 },
    ashenvale  = { "灰谷", "Ashenvale", "KAL", false, 1440 },
    felwood    = { "费伍德森林", "Felwood", "KAL", false, 1448 },
    winterspring = { "冬泉谷", "Winterspring", "KAL", false, 1452 },
    moonglade  = { "月光林地", "Moonglade", "KAL", false, 1450 },
    azshara    = { "艾萨拉", "Azshara", "KAL", false, 1447 },
    durotar    = { "杜隆塔尔", "Durotar", "KAL", false, 1411 },
    orgrimmar  = { "奥格瑞玛", "Orgrimmar", "KAL", true, 1454 },
    barrens    = { "贫瘠之地", "The Barrens", "KAL", false, 1413 },
    mulgore    = { "莫高雷", "Mulgore", "KAL", false, 1412 },
    thunderbluff = { "雷霆崖", "Thunder Bluff", "KAL", true, 1456 },
    stonetalon = { "石爪山脉", "Stonetalon Mountains", "KAL", false, 1442 },
    desolace   = { "凄凉之地", "Desolace", "KAL", false, 1443 },
    feralas    = { "菲拉斯", "Feralas", "KAL", false, 1444 },
    needles    = { "千针石林", "Thousand Needles", "KAL", false, 1441 },
    dustwallow = { "尘泥沼泽", "Dustwallow Marsh", "KAL", false, 1445 },
    tanaris    = { "塔纳利斯", "Tanaris", "KAL", false, 1446 },
    ungoro     = { "安戈洛环形山", "Un'Goro Crater", "KAL", false, 1449 },
    silithus   = { "希利苏斯", "Silithus", "KAL", false, 1451 },
    hyjal      = { "海加尔山", "Mount Hyjal", "KAL", false, nil },  -- 无限新地区，相邻关系按传说地理推测
}

-- 陆路相邻（双向），第三项是骑马穿行的大致分钟数（地区中心到中心）
D.ADJ = {
    { "tirisfal", "undercity", 1 }, { "tirisfal", "silverpine", 4 }, { "tirisfal", "wpl", 4 },
    { "silverpine", "hillsbrad", 4 }, { "silverpine", "alterac", 4 },
    { "wpl", "epl", 4 }, { "wpl", "alterac", 4 },
    { "alterac", "hillsbrad", 3 },
    { "hillsbrad", "hinterlands", 4 }, { "hillsbrad", "arathi", 4 },
    { "arathi", "wetlands", 4 },
    { "wetlands", "lochmodan", 4 },
    { "lochmodan", "dunmorogh", 4 }, { "lochmodan", "badlands", 4 },
    { "dunmorogh", "ironforge", 1 },
    { "searing", "burning", 4 },          -- 经黑石山
    { "burning", "redridge", 4 },
    { "redridge", "elwynn", 4 }, { "redridge", "duskwood", 4 }, { "redridge", "swamp", 5 },
    { "elwynn", "stormwind", 1 }, { "elwynn", "westfall", 4 }, { "elwynn", "duskwood", 4 },
    { "westfall", "duskwood", 4 },
    { "duskwood", "stv", 5 }, { "duskwood", "deadwind", 4 },
    { "deadwind", "swamp", 4 },
    { "swamp", "blasted", 4 },

    { "teldrassil", "darnassus", 1 },     -- 鲁瑟兰村有传送门到达纳苏斯
    { "darkshore", "ashenvale", 5 },
    { "ashenvale", "felwood", 4 }, { "ashenvale", "azshara", 4 }, { "ashenvale", "barrens", 4 }, { "ashenvale", "stonetalon", 4 },
    { "felwood", "winterspring", 4 }, { "felwood", "moonglade", 3 },
    { "winterspring", "moonglade", 3 },
    { "durotar", "orgrimmar", 1 }, { "durotar", "barrens", 3 },
    { "barrens", "mulgore", 4 }, { "barrens", "stonetalon", 4 }, { "barrens", "dustwallow", 4 }, { "barrens", "needles", 5 },
    { "mulgore", "thunderbluff", 1 },
    { "stonetalon", "desolace", 4 },
    { "desolace", "feralas", 5 },
    { "feralas", "needles", 5 },
    { "needles", "tanaris", 4 },
    { "tanaris", "ungoro", 4 },
    { "ungoro", "silithus", 4 },
    { "hyjal", "felwood", 5 }, { "hyjal", "winterspring", 5 }, -- 未核实
}

-- 停靠点：key = { zh, en, 所在地区, 子区域名(到站判断用), 从地区中心走过去的分钟数, 近似坐标x, y(0~100，可无) }
D.STOPS = {
    sw_harbor   = { zh = "暴风城港口", en = "Stormwind Harbor", zone = "stormwind", sub = { "暴风城港口", "Stormwind Harbor" }, walk = 1.5 },
    sw_tram     = { zh = "暴风城矮人区（矿道地铁）", en = "Deeprun Tram (Stormwind)", zone = "stormwind", sub = { "矮人区", "Dwarven District" }, walk = 1, x = 66.5, y = 32.5 },
    if_tram     = { zh = "铁炉堡侏儒区（矿道地铁）", en = "Deeprun Tram (Ironforge)", zone = "ironforge", sub = { "侏儒区", "Tinker Town" }, walk = 1, x = 76.5, y = 51 },
    menethil    = { zh = "米奈希尔港", en = "Menethil Harbor", zone = "wetlands", sub = { "米奈希尔港", "Menethil Harbor" }, walk = 3, x = 5, y = 60 },
    southshore  = { zh = "南海镇", en = "Southshore", zone = "hillsbrad", sub = { "南海镇", "Southshore" }, walk = 2, x = 50, y = 60 },
    auberdine   = { zh = "奥伯丁", en = "Auberdine", zone = "darkshore", sub = { "奥伯丁", "Auberdine" }, walk = 2, x = 32, y = 43 },
    rutheran    = { zh = "鲁瑟兰村", en = "Rut'theran Village", zone = "teldrassil", sub = { "鲁瑟兰村", "Rut'theran Village" }, walk = 2, x = 55, y = 93 },
    theramore   = { zh = "塞拉摩岛", en = "Theramore Isle", zone = "dustwallow", sub = { "塞拉摩岛", "Theramore Isle" }, walk = 2.5, x = 71.5, y = 56.5 },
    feathermoon = { zh = "羽月要塞", en = "Feathermoon Stronghold", zone = "feralas", sub = { "羽月要塞", "Feathermoon Stronghold" }, walk = 3, x = 31, y = 40 },
    forgotten   = { zh = "被遗忘的海岸", en = "The Forgotten Coast", zone = "feralas", sub = { "被遗忘的海岸", "The Forgotten Coast" }, walk = 2, x = 43.3, y = 42.8 },
    ratchet     = { zh = "棘齿城", en = "Ratchet", zone = "barrens", sub = { "棘齿城", "Ratchet" }, walk = 3, x = 63.7, y = 38.6 },
    bootybay    = { zh = "藏宝海湾", en = "Booty Bay", zone = "stv", sub = { "藏宝海湾", "Booty Bay" }, walk = 4, x = 26, y = 73 },
    gromgol     = { zh = "格罗姆高营地", en = "Grom'gol Base Camp", zone = "stv", sub = { "格罗姆高营地", "Grom'gol Base Camp" }, walk = 2, x = 31.6, y = 29.1 },
    org_tower   = { zh = "奥格瑞玛飞艇塔（城外）", en = "Orgrimmar zeppelin tower", zone = "durotar", sub = {}, walk = 1.5, x = 50.8, y = 13.5 },
    uc_tower    = { zh = "幽暗城飞艇塔（城外北边）", en = "Undercity zeppelin tower", zone = "tirisfal", sub = {}, walk = 1.5, x = 61, y = 59 },
    steamwheedle = { zh = "热砂港", en = "Steamwheedle Port", zone = "tanaris", sub = { "热砂港", "Steamwheedle Port" }, walk = 3, x = 67, y = 23 },
    powderfuse  = { zh = "爆破引线港", en = "Powderfuse Port", zone = "riverglades", sub = { "爆破引线港", "Powderfuse Port" }, walk = 2 },
    valanaar    = { zh = "瓦拉纳尔天港", en = "Valanaar", zone = "zephras", sub = { "瓦拉纳尔", "瓦拉纳尔天港", "Valanaar" }, walk = 2 },
    dalaran     = { zh = "达拉然（城北飞艇点）", en = "Dalaran", zone = "alterac", sub = { "达拉然", "Dalaran" }, walk = 2 },
    skywatcher  = { zh = "观天者台地", en = "Skywatcher Plateau", zone = "mulgore", sub = { "观天者台地", "Skywatcher Plateau" }, walk = 2 },
}

-- 航线：type = boat/zeppelin/skyboat/tram；faction = Alliance/Horde/Neutral
-- 两站往返：stops = {A, B}, len = {码数}
-- 单向环线：loop = true, stops = {A, B, C}, len = {A→B, B→C, C→A}
D.ROUTES = {
    { id = "sw_aub",   type = "boat",     faction = "Alliance", stops = { "sw_harbor", "auberdine" }, len = { 1572 }, new = true },
    { id = "triangle", type = "boat",     faction = "Alliance", loop = true, stops = { "menethil", "southshore", "auberdine" }, len = { 3336, 1964, 2154 }, new = true },
    { id = "men_ther", type = "boat",     faction = "Alliance", stops = { "menethil", "theramore" }, len = { 2441 } },
    { id = "aub_rut",  type = "boat",     faction = "Alliance", stops = { "auberdine", "rutheran" }, len = { 2219 } },
    { id = "feather",  type = "boat",     faction = "Alliance", stops = { "feathermoon", "forgotten" }, len = { 899 }, dock = 30 },
    { id = "rat_bb",   type = "boat",     faction = "Neutral",  stops = { "ratchet", "bootybay" }, len = { 2787 } },
    { id = "tan_riv",  type = "boat",     faction = "Neutral",  stops = { "steamwheedle", "powderfuse" }, len = { 1561 }, new = true },
    { id = "org_uc",   type = "zeppelin", faction = "Horde",    stops = { "org_tower", "uc_tower" }, len = { 3297 } },
    { id = "org_gg",   type = "zeppelin", faction = "Horde",    stops = { "org_tower", "gromgol" }, len = { 2422 } },
    -- WarcraftMaps 给出 16386 码，约是其他飞艇的 5 倍，疑似路径数据异常；按 3500 码估算
    { id = "uc_gg",    type = "zeppelin", faction = "Horde",    stops = { "uc_tower", "gromgol" }, len = { 3500 } },
    { id = "val_dal",  type = "skyboat",  faction = "Neutral",  stops = { "valanaar", "dalaran" }, len = { 2690 }, new = true },
    { id = "val_sky",  type = "skyboat",  faction = "Horde",    stops = { "valanaar", "skywatcher" }, len = { 2214 }, new = true },
    { id = "tram",     type = "tram",     faction = "Alliance", stops = { "sw_tram", "if_tram" }, fixed = 1.5 },
}

D.TYPE_NAME = { boat = "坐船", zeppelin = "坐飞艇", skyboat = "坐天空飞艇", tram = "坐矿道地铁" }

-- 副本与团本入口
-- x, y = 入口在所在地区地图上的坐标（0~100）；approx = 近似/未核实；没有坐标的只导航到地区
-- 坐标来源：nieyi.cn（标注了的）、经典怀旧服常用坐标（approx）；无限新副本官方未公布坐标
-- open = 开放时间（nil 表示已开放）
D.POIS = {
    -- 经典 5 人副本
    { key = "rfc", zh = "怒焰裂谷", en = "Ragefire Chasm", kind = "dungeon", zone = "orgrimmar", x = 53.0, y = 48.9, lv = "13-18", alias = { "RFC", "怒焰" }, hint = "奥格瑞玛暗影裂口里" },
    { key = "wc", zh = "哀嚎洞穴", en = "Wailing Caverns", kind = "dungeon", zone = "barrens", x = 47.7, y = 35.0, lv = "17-24", alias = { "WC", "哀嚎" }, hint = "贫瘠之地中部绿洲西南的山洞，入口在洞里" },
    { key = "dm", zh = "死亡矿井", en = "The Deadmines", kind = "dungeon", zone = "westfall", x = 38.2, y = 77.5, lv = "16-22", alias = { "VC", "死矿" }, hint = "月溪镇的矿洞里，一直往下走" },
    { key = "sfk", zh = "影牙城堡", en = "Shadowfang Keep", kind = "dungeon", zone = "silverpine", x = 44.7, y = 67.8, lv = "18-25", alias = { "SFK", "影牙" } },
    { key = "stocks", zh = "监狱", en = "The Stockade", kind = "dungeon", zone = "stormwind", x = 50.4, y = 66.2, lv = "23-26", alias = { "Stocks", "暴风城监狱" }, hint = "暴风城运河区" },
    { key = "bfd", zh = "黑暗深渊", en = "Blackfathom Deeps", kind = "dungeon", zone = "ashenvale", x = 16.5, y = 11.0, lv = "22-28", alias = { "BFD", "黑暗深渊" }, hint = "灰谷佐拉姆海岸的水下神殿，需要潜水" },
    { key = "gnomer", zh = "诺莫瑞根", en = "Gnomeregan", kind = "dungeon", zone = "dunmorogh", x = 17.7, y = 39.2, lv = "25-32", alias = { "Gnomer", "诺莫" } },
    { key = "rfk", zh = "剃刀沼泽", en = "Razorfen Kraul", kind = "dungeon", zone = "barrens", x = 42.3, y = 89.9, lv = "24-30", alias = { "RFK" }, hint = "贫瘠之地南端的荆棘丛" },
    { key = "sm", zh = "血色修道院", en = "Scarlet Monastery", kind = "dungeon", zone = "tirisfal", x = 85.1, y = 31.4, lv = "30-40", alias = { "SM", "血色" }, hint = "提瑞斯法林地最东边" },
    { key = "rfd", zh = "剃刀高地", en = "Razorfen Downs", kind = "dungeon", zone = "needles", x = 47.5, y = 23.5, approx = true, lv = "35-40", alias = { "RFD" }, hint = "贫瘠之地与千针石林交界处" },
    { key = "ulda", zh = "奥达曼", en = "Uldaman", kind = "dungeon", zone = "badlands", x = 42.5, y = 13.0, approx = true, lv = "40-47", alias = { "Ulda" }, hint = "荒芜之地北部" },
    { key = "zf", zh = "祖尔法拉克", en = "Zul'Farrak", kind = "dungeon", zone = "tanaris", x = 38.7, y = 20.0, approx = true, lv = "44-47", alias = { "ZF", "祖尔" }, hint = "塔纳利斯西北" },
    { key = "mara", zh = "玛拉顿", en = "Maraudon", kind = "dungeon", zone = "desolace", x = 29.1, y = 62.5, approx = true, lv = "40-49", alias = { "Mara" }, hint = "凄凉之地西南，从洞口往里走" },
    { key = "st", zh = "阿塔哈卡神庙", en = "Temple of Atal'Hakkar", kind = "dungeon", zone = "swamp", x = 69.9, y = 53.6, approx = true, lv = "50-55", alias = { "ST", "神庙", "沉没的神庙" }, hint = "悲伤沼泽东南的湖里，要潜到湖底" },
    { key = "brd", zh = "黑石深渊", en = "Blackrock Depths", kind = "dungeon", zone = "burning", x = 29.4, y = 38.3, approx = true, lv = "52-60", alias = { "BRD", "黑石" }, hint = "黑石山：从燃烧平原西北进山，往下走到山底" },
    { key = "lbrs", zh = "黑石塔", en = "Blackrock Spire", kind = "dungeon", zone = "burning", x = 29.4, y = 38.3, approx = true, lv = "53-60", alias = { "LBRS", "UBRS", "黑下", "黑上" }, hint = "黑石山：从燃烧平原西北进山，往上走" },
    { key = "dire", zh = "厄运之槌", en = "Dire Maul", kind = "dungeon", zone = "feralas", x = 59.0, y = 44.0, approx = true, lv = "56-60", alias = { "DM", "厄运" }, hint = "菲拉斯中部的古城遗迹" },
    { key = "scholo", zh = "通灵学院", en = "Scholomance", kind = "dungeon", zone = "wpl", x = 69.7, y = 73.2, approx = true, lv = "58-60", alias = { "Scholo", "通灵" }, hint = "西瘟疫之地凯尔达隆岛" },
    { key = "strat", zh = "斯坦索姆", en = "Stratholme", kind = "dungeon", zone = "epl", x = 31.3, y = 15.7, approx = true, lv = "58-60", alias = { "Strat", "斯坦" }, hint = "东瘟疫之地西北，正门；后门在东边" },
    -- 无限新增 5 人副本（官方未公布坐标）
    { key = "thanes", zh = "领主大厅", en = "Hall of Thanes", kind = "dungeon", zone = "ironforge", x = 43.6, y = 51.7, lv = "13-18", new = true, alias = { "领主" }, hint = "铁炉堡：从国王王座厅走左边的路，下到旧铁炉堡" },
    { key = "lordaeron", zh = "洛丹伦废墟", en = "Ruins of Lordaeron", kind = "dungeon", zone = "tirisfal", lv = "15-20", new = true, alias = { "洛丹伦" }, hint = "幽暗城上方的废墟" },
    { key = "excavation", zh = "挖掘场：湿地", en = "Excavation Site", kind = "dungeon", zone = "wetlands", lv = "24-29", new = true, alias = { "挖掘场" }, hint = "湿地维尔加挖掘场上方" },
    { key = "dalaran", zh = "达拉然城", en = "City of Dalaran", kind = "dungeon", zone = "alterac", lv = "28-33", new = true, alias = { "达拉然" }, hint = "先做阵营任务线（联盟南海镇 / 部落塔伦米尔），从下水道进入" },
    { key = "drowned", zh = "沉没之城", en = "The Drowned City", kind = "dungeon", zone = "stv", lv = "35-40", new = true, alias = { "沉没" }, hint = "格罗姆高营地西边海岸，水下入口" },
    { key = "kroldok", zh = "克罗多克要塞", en = "Krol'dok Stronghold", kind = "dungeon", zone = "riverglades", lv = "40-45", new = true, alias = { "克罗多克" }, hint = "河林（从热砂港坐船到爆破引线港）" },
    { key = "alcaz", zh = "奥卡兹监狱", en = "Alcaz Prison", kind = "dungeon", zone = "dustwallow", lv = "48-53", new = true, alias = { "奥卡兹" }, hint = "尘泥沼泽东北的奥卡兹岛" },
    { key = "blackmaw", zh = "黑喉要塞", en = "Blackmaw Hold", kind = "dungeon", zone = "azshara", lv = "55-60", new = true, alias = { "黑喉" } },
    { key = "shaper", zh = "塑造者之台", en = "Shaper's Terrace", kind = "dungeon", zone = "ungoro", lv = "58-60", new = true, alias = { "塑造者" }, hint = "安戈洛环形山北部" },
    -- 团本
    { key = "ony", zh = "奥妮克希亚的巢穴", en = "Onyxia's Lair", kind = "raid", zone = "dustwallow", x = 52.6, y = 76.7, approx = true, lv = "60", open = "12月9日开放", alias = { "Ony", "黑龙", "奥妮" }, hint = "尘泥沼泽南部的龙巢" },
    { key = "barrow", zh = "深穴", en = "Barrow Deeps", kind = "raid", zone = "hyjal", lv = "60 · 10人", new = true, open = "12月9日开放", alias = { "深穴" }, hint = "据报道三个入口之一在海加尔山" },
    { key = "hyjalsummit", zh = "海加尔峰", en = "Hyjal Summit", kind = "raid", zone = "hyjal", lv = "60 · 20人", new = true, open = "12月9日开放", alias = { "海加尔峰" } },
    { key = "mc", zh = "熔火之心", en = "Molten Core", kind = "raid", zone = "burning", x = 29.4, y = 38.3, approx = true, lv = "60 · 40人", open = "开放时间未公布", alias = { "MC", "熔火" }, hint = "黑石山：进入黑石深渊后从里面进入" },
    { key = "bwl", zh = "黑翼之巢", en = "Blackwing Lair", kind = "raid", zone = "burning", x = 29.4, y = 38.3, approx = true, lv = "60 · 40人", open = "开放时间未公布", alias = { "BWL", "黑翼" }, hint = "黑石山：从黑石塔上层进入" },
    { key = "zg", zh = "祖尔格拉布", en = "Zul'Gurub", kind = "raid", zone = "stv", x = 53.9, y = 17.6, approx = true, lv = "60 · 20人", open = "开放时间未公布", alias = { "ZG", "祖格" }, hint = "荆棘谷东北" },
    { key = "aq", zh = "安其拉", en = "Ahn'Qiraj", kind = "raid", zone = "silithus", x = 28.6, y = 92.4, approx = true, lv = "60", open = "开放时间未公布", alias = { "AQ", "TAQ", "安其拉废墟", "安其拉神殿" }, hint = "希利苏斯南部的安其拉之门" },
    { key = "naxx", zh = "纳克萨玛斯", en = "Naxxramas", kind = "raid", zone = "epl", x = 81.0, y = 58.0, approx = true, lv = "60 · 40人", open = "开放时间未公布", alias = { "Naxx", "NAXX", "纳克" }, hint = "东瘟疫之地圣光之愿礼拜堂的传送门" },
}

-- 大陆地图名（运行时按名字找 uiMapID，用于画图和鸟点坐标换算）
D.CONTINENTS = {
    KAL = { "卡利姆多", "Kalimdor" },
    EK = { "东部王国", "Eastern Kingdoms" },
}

-- 炉石绑定点（旅店所在城镇）→ 地区
D.INNS = {
    ["闪金镇"] = "elwynn", ["Goldshire"] = "elwynn", ["湖畔镇"] = "redridge", ["Lakeshire"] = "redridge",
    ["夜色镇"] = "duskwood", ["Darkshire"] = "duskwood", ["哨兵岭"] = "westfall", ["Sentinel Hill"] = "westfall",
    ["塞尔萨玛"] = "lochmodan", ["Thelsamar"] = "lochmodan", ["卡拉诺斯"] = "dunmorogh", ["Kharanos"] = "dunmorogh",
    ["阿斯特兰纳"] = "ashenvale", ["Astranaar"] = "ashenvale", ["多兰纳尔"] = "teldrassil", ["Dolanaar"] = "teldrassil",
    ["十字路口"] = "barrens", ["The Crossroads"] = "barrens", ["剃刀岭"] = "durotar", ["Razor Hill"] = "durotar",
    ["血蹄村"] = "mulgore", ["Bloodhoof Village"] = "mulgore", ["塔伦米尔"] = "hillsbrad", ["Tarren Mill"] = "hillsbrad",
    ["布瑞尔"] = "tirisfal", ["Brill"] = "tirisfal", ["加基森"] = "tanaris", ["Gadgetzan"] = "tanaris",
    ["莫沙彻营地"] = "feralas", ["Camp Mojache"] = "feralas", ["葬影村"] = "desolace", ["Shadowprey Village"] = "desolace",
    ["尼耶尔前哨站"] = "desolace", ["Nijel's Point"] = "desolace", ["落锤镇"] = "arathi", ["Hammerfall"] = "arathi",
    ["避难谷地"] = "arathi", ["Refuge Pointe"] = "arathi", ["卡加斯"] = "badlands", ["Kargath"] = "badlands",
    ["斯通纳德"] = "swamp", ["Stonard"] = "swamp", ["碎木岗哨"] = "ashenvale", ["Splintertree Post"] = "ashenvale",
    ["永望镇"] = "winterspring", ["Everlook"] = "winterspring", ["塞纳里奥城堡"] = "silithus", ["Cenarion Hold"] = "silithus",
    ["马绍尔营地"] = "ungoro", ["Marshal's Refuge"] = "ungoro", ["铁环营地"] = "dustwallow", ["Brackenwall Village"] = "dustwallow",
    ["石爪峰"] = "stonetalon", ["Stonetalon Peak"] = "stonetalon", ["烈日石居"] = "stonetalon", ["Sun Rock Retreat"] = "stonetalon",
    ["瑟伯切尔"] = "silverpine", ["The Sepulcher"] = "silverpine", ["鹰巢山"] = "hinterlands", ["Aerie Peak"] = "hinterlands",
    ["乱风岗"] = "needles", ["Freewind Post"] = "needles", ["圣光之愿礼拜堂"] = "epl", ["Light's Hope Chapel"] = "epl",
}
