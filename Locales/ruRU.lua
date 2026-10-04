-- unrealMap / Locales/ruRU.lua -- Russian. Missing keys fall back to English.
unrealMapLocale.Register("ruRU", {
  ["COMMON_CLOSE"] = "Закрыть",

  ["SETTINGS_PAGE_GENERAL"] = "Общие",
  ["SETTINGS_HEADING_WORLD_MAP"] = "Карта мира",
  ["SETTINGS_REVEAL_FOG"] = "Убрать туман войны",
  ["SETTINGS_REVEAL_FOG_NOTE"] = "Показывает неисследованные области всех зон на карте мира. "
    .. "Сам прогресс исследования не меняется. "
    .. "Если туман войны сохранён, неисследованные области остаются в низком разрешении.",
  ["SETTINGS_MINIMAP_BUTTON"] = "Показывать кнопку у миникарты",
  ["SETTINGS_LANGUAGE_CHANGED"] = "язык установлен на %s.",
  ["SETTINGS_LANGUAGE_RELOAD"] = "введите /reload, чтобы перерисовать интерфейс на этом языке.",
  ["SETTINGS_WINDOW_FAILED"] = "не удалось создать окно настроек.",
  ["SETTINGS_WINDOW_NOT_MOVABLE"] = "не удалось переместить окно настроек.",
  ["SETTINGS_HOST_REFUSED"] = "unrealUI отклонил страницу настроек; используется собственное окно unrealMap.",
  ["SETTINGS_IN_UNREALUI"] = "настройки находятся в окне настроек unrealUI.",
  ["MINIMAP_TOOLTIP"] = "Нажмите, чтобы открыть настройки карты.",

  ["CHAT_LOADED"] = "v%s загружен. Настройки: /umap.",
  ["CHAT_FOG_REMOVED"] = "туман войны убран.",
  ["CHAT_FOG_RESTORED"] = "туман войны восстановлен.",
  ["CHAT_MINIMAP_SHOWN"] = "кнопка у миникарты показана.",
  ["CHAT_MINIMAP_HIDDEN"] = "кнопка у миникарты скрыта.",
  ["CHAT_RAGEFIRE_UPDATED"] = "карта подземелья Огненная Пропасть обновлена.",
  ["CHAT_RAGEFIRE_FAILED"] = "не удалось обновить карту подземелья Огненная Пропасть.",
  ["CHAT_RAGEFIRE_UNAVAILABLE"] = "поддержка подземелья Огненная Пропасть недоступна.",
  ["CHAT_HELP"] = "/umap открывает настройки. /umap fog [on|off], /umap minimap, /umap dungeon <карта|off>, /umap raid <карта|off>.",

  ["RAGEFIRE_NEEDS_DUNGEON"] = "Подтверждение Огненной Пропасти работает только внутри группового подземелья.",
  ["RAGEFIRE_ENABLED"] = "Карта подземелья Огненная Пропасть включена.",
  ["RAGEFIRE_CLEARED"] = "Подтверждение карты Огненной Пропасти сброшено.",
  ["DUNGEON_NEEDS_INSTANCE"] = "Выбор карты работает только внутри группового подземелья.",
  ["DUNGEON_UNKNOWN"] = "Неизвестная карта подземелья: %s.",
  ["DUNGEON_ENABLED"] = "Карта подземелья включена: %s.",
  ["DUNGEON_CLEARED"] = "Выбор карты подземелья сброшен.",
  ["RAID_NEEDS_INSTANCE"] = "Выбор карты рейда работает только внутри рейдового подземелья.",
  ["RAID_UNKNOWN"] = "Неизвестная карта рейда: %s.",
  ["RAID_ENABLED"] = "Карта рейда включена: %s.",
  ["RAID_CLEARED"] = "Выбор карты рейда сброшен.",
  ["RAID_UNAVAILABLE"] = "Поддержка карт рейдов недоступна.",

  ["POPUP_QUESTION"] = "Вам нравится?",
  ["POPUP_MESSAGE"] = "Поставьте лайк этому аддону в лаунчере",
  ["POPUP_THANKS"] = "СПАСИБО ЗА ПОДДЕРЖКУ!",
  ["POPUP_DONT_SHOW"] = "Больше не показывать",
})
