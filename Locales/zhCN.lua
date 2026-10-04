-- unrealMap / Locales/zhCN.lua -- Simplified Chinese. Missing keys fall back to English.
unrealMapLocale.Register("zhCN", {
  ["COMMON_CLOSE"] = "关闭",

  ["SETTINGS_PAGE_GENERAL"] = "常规",
  ["SETTINGS_HEADING_WORLD_MAP"] = "世界地图",
  ["SETTINGS_REVEAL_FOG"] = "移除战争迷雾",
  ["SETTINGS_REVEAL_FOG_NOTE"] = "在世界地图上显示每个区域的未探索区域。"
    .. "探索进度本身不会改变。"
    .. "保留战争迷雾时，未探索区域保持低清晰度。",
  ["SETTINGS_MINIMAP_BUTTON"] = "显示小地图按钮",
  ["SETTINGS_LANGUAGE_CHANGED"] = "语言已设为 %s。",
  ["SETTINGS_LANGUAGE_RELOAD"] = "输入 /reload 以用该语言重绘界面。",
  ["SETTINGS_WINDOW_FAILED"] = "无法创建设置窗口。",
  ["SETTINGS_WINDOW_NOT_MOVABLE"] = "无法移动设置窗口。",
  ["SETTINGS_HOST_REFUSED"] = "unrealUI 拒绝了设置页面；改用 unrealMap 自己的窗口。",
  ["SETTINGS_IN_UNREALUI"] = "设置位于 unrealUI 的设置窗口中。",
  ["MINIMAP_TOOLTIP"] = "点击打开地图设置。",

  ["CHAT_LOADED"] = "v%s 已加载。输入 /umap 打开设置。",
  ["CHAT_FOG_REMOVED"] = "已移除战争迷雾。",
  ["CHAT_FOG_RESTORED"] = "已恢复战争迷雾。",
  ["CHAT_MINIMAP_SHOWN"] = "已显示小地图按钮。",
  ["CHAT_MINIMAP_HIDDEN"] = "已隐藏小地图按钮。",
  ["CHAT_RAGEFIRE_UPDATED"] = "怒焰裂谷地下城地图已更新。",
  ["CHAT_RAGEFIRE_FAILED"] = "无法更新怒焰裂谷地下城地图。",
  ["CHAT_RAGEFIRE_UNAVAILABLE"] = "怒焰裂谷地下城支持不可用。",
  ["CHAT_HELP"] = "/umap 打开设置。/umap fog [on|off]，/umap minimap，/umap dungeon <地图|off>，/umap raid <地图|off>。",

  ["RAGEFIRE_NEEDS_DUNGEON"] = "怒焰裂谷确认只能在小队地下城内使用。",
  ["RAGEFIRE_ENABLED"] = "已启用怒焰裂谷地下城地图。",
  ["RAGEFIRE_CLEARED"] = "已清除怒焰裂谷地下城地图确认。",
  ["DUNGEON_NEEDS_INSTANCE"] = "只能在小队地下城内选择地下城地图。",
  ["DUNGEON_UNKNOWN"] = "未知地下城地图：%s。",
  ["DUNGEON_ENABLED"] = "已启用地下城地图：%s。",
  ["DUNGEON_CLEARED"] = "已清除地下城地图选择。",
  ["RAID_NEEDS_INSTANCE"] = "团队副本地图选择只能在团队副本内使用。",
  ["RAID_UNKNOWN"] = "未知团队副本地图：%s。",
  ["RAID_ENABLED"] = "团队副本地图已启用：%s。",
  ["RAID_CLEARED"] = "团队副本地图选择已清除。",
  ["RAID_UNAVAILABLE"] = "团队副本地图支持不可用。",

  ["POPUP_QUESTION"] = "喜欢吗？",
  ["POPUP_MESSAGE"] = "请在启动器中为此插件点赞",
  ["POPUP_THANKS"] = "感谢您的支持！",
  ["POPUP_DONT_SHOW"] = "不再显示",
})
