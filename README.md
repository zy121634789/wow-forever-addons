# 魔兽世界：无限 插件合集

给《魔兽世界：无限》（World of Warcraft: Forever，客户端 1.60.1，Interface 16001）写的插件。

| 插件 | 文件夹 | 简介 |
|---|---|---|
| **咕咕导航** | `ForeverNav` | 像导航软件一样的跨大陆导航：可缩放地图、路线规划（坐船/飞艇/坐鸟/炉石）、副本与团本入口导航、顶部导航条、偏航重算、每个角色的鸟点同步 |
| **制造利润** | `CraftProfit` | 拍卖行物价与专业制造联动：配方成本/售价/利润、销量估算、实时收支、量化交易建议、关注材料每分钟快速扫描 |

## 安装

1. 点右上角 **Code → Download ZIP** 下载并解压。
2. 把需要的插件文件夹（`ForeverNav`、`CraftProfit`）复制到：

   ```
   World of Warcraft\_forever_\Interface\AddOns\
   ```

   最后应该是 `AddOns\ForeverNav\ForeverNav.toc` 这样的结构，不要多套一层文件夹。
3. 进游戏在角色选择界面左下角「插件」里确认已启用。

## 使用

- 咕咕导航：`/dh` 打开窗口，`/dh 死矿` 直接导航。详见 [ForeverNav/使用说明.md](ForeverNav/使用说明.md)
- 制造利润：`/cpf` 打开利润面板，`/cpf help` 查看全部命令。详见 [CraftProfit/使用说明.md](CraftProfit/使用说明.md)

## 说明

- 无限服的接口资料大多来自社区，部分数据（航线时间、新副本入口坐标等）是估算或未核实的，使用说明里都有标注。
- 插件只读取游戏数据，不会自动购买、出售、制造或移动角色。
- 发现 bug 或想补充坐标，欢迎提 Issue。
