--[[
unrealMap / Locale.lua

The translation layer: a key -> text lookup with a fixed English fallback, and
the language selection that drives it. Same contract as UnrealQuest's
Core/Locale.lua, scaled down to three languages:

  * unrealUI installed -> unrealMap follows unrealUI's language and shows no
    flag selector of its own. A language unrealUI offers but this addon does
    not carry (French) falls back to English.
  * unrealUI absent -> unrealMap's own stored language (unrealMapDB.language),
    picked with the flag row in the top-right of its own settings window.

Neither case is a dependency. unrealUI is detected by the same POLL that
Settings.lua uses for its host (no load order, IsAddOnLoaded or ADDON_LOADED
assumption), and read through two type-checked lookups:

  1. UnrealUI.GetLanguage(), once UnrealUI.ready is true. Before that flag the
     getter still answers with unrealUI's compiled-in default.
  2. UnrealUIProfiles.language, the account-wide value unrealUI persists,
     readable as soon as SavedVariables are loaded. Validated against the
     known codes, never trusted as a key.

A label is translated once, when it is built. Nothing may call L at file
scope: the language is not known yet at file-load time. Changing the language
asks for a /reload, exactly as unrealUI and UnrealQuest do.

The stored value is a four-letter code validated before use, so a mangled
saved file falls back to English (config.savedvariables_backslash_corruption).
Flag texture paths carry backslashes and are rebuilt here, never persisted.

Locales/*.lua are UTF-8 without a BOM. Cyrillic and CJK rendering depends on
the client's own font (fonts.setfont_silent_failure); the selector stays
usable in every language because its choices are flags with an ASCII badge
fallback.
]]

local DEFAULT_LANGUAGE = "enUS"
local FLAG_PATH = "Interface\\AddOns\\unrealMap\\Media\\Textures\\UI\\unrealmap-flag-"

-- Ordered as unrealUI orders its own flags, so a player who has used either
-- sibling addon finds each language in the same place.
local languages = {
  { code = "enUS", short = "EN", label = "English", flag = "en" },
  { code = "zhCN", short = "CN", label = "简体中文", flag = "cn" },
  { code = "ruRU", short = "RU", label = "Русский", flag = "ru" },
}

local languageByCode = {}
do
  local i
  for i = 1, table.getn(languages) do
    languageByCode[languages[i].code] = languages[i]
  end
end

local strings = {}     -- code -> { KEY = text }, filled by Locales/*.lua
local active = DEFAULT_LANGUAGE
local settled = false
local followsUnrealUI = false

-- Registration --------------------------------------------------------------

local function Register(code, entries)
  if not languageByCode[code] or type(entries) ~= "table" then return end
  local target = strings[code]
  if not target then
    target = {}
    strings[code] = target
  end
  local key, text
  for key, text in pairs(entries) do
    if type(key) == "string" and type(text) == "string" then target[key] = text end
  end
end

-- Resolution ----------------------------------------------------------------

local function UnrealUI()
  local found = _G["UnrealUI"]
  if type(found) ~= "table" or type(found.GetLanguage) ~= "function" then return nil end
  return found
end

-- unrealUI's answer, authoritative read first. Returns the code (which may be
-- one this addon does not carry), or nil while unrealUI has said nothing yet.
local function UnrealUILanguage(hostUI)
  if hostUI.ready then
    local ok, code = pcall(hostUI.GetLanguage)
    if ok and type(code) == "string" and code ~= "" then return code end
  end
  local profiles = _G["UnrealUIProfiles"]
  if type(profiles) == "table" and type(profiles.language) == "string"
      and profiles.language ~= "" then
    return profiles.language
  end
  return nil
end

local function StoredLanguage()
  local db = _G["unrealMapDB"]
  local code = type(db) == "table" and db.language or nil
  if languageByCode[code] then return code end
  return nil
end

-- Default before the player has chosen, the rule shared with unrealUI and
-- UnrealQuest: a zhCN client starts in Chinese, a ruRU client in Russian,
-- every other client (zhTW included) in English.
-- GetLocale returns a WoW locale token (DOCUMENTED_NOT_RUNTIME_VERIFIED); an
-- unexpected value or a failed call also gives English. Only a default -- a
-- stored choice always wins.
local function FirstRunLanguage()
  if type(GetLocale) == "function" then
    local ok, clientLocale = pcall(GetLocale)
    if ok and languageByCode[clientLocale] then return clientLocale end
  end
  return DEFAULT_LANGUAGE
end

-- Decides the language. Without `force`, an absent unrealUI leaves the
-- decision open so the poll can try again. Returns true once final.
local function Resolve(force)
  if settled then return true end

  local hostUI = UnrealUI()
  if hostUI then
    followsUnrealUI = true
    local code = UnrealUILanguage(hostUI)
    if code then
      active = languageByCode[code] and code or DEFAULT_LANGUAGE
      settled = true
      return true
    end
    -- Present but not ready and nothing persisted: keep English for now, and
    -- use the client-language default if unrealUI never answers.
    if force then
      active = FirstRunLanguage()
      settled = true
    end
    return settled
  end

  followsUnrealUI = false
  local stored = StoredLanguage()
  active = stored or FirstRunLanguage()
  if force then
    settled = true
    if not stored then
      if type(unrealMapDB) ~= "table" then unrealMapDB = {} end
      unrealMapDB.language = active
    end
  end
  return settled
end

-- Lookup --------------------------------------------------------------------

-- A missing key returns the key itself, so an untranslated string shows up in
-- game as a visible identifier rather than an empty label.
local function Lookup(key)
  if type(key) ~= "string" then return "" end
  local current = strings[active]
  local text = current and current[key]
  if text then return text end
  local fallback = strings[DEFAULT_LANGUAGE]
  text = fallback and fallback[key]
  return text or key
end

-- L("KEY") or L("KEY", a, b): the format is guarded because the pattern comes
-- from a translation file.
local function L(key, a, b, c)
  if not settled then Resolve(false) end
  local text = Lookup(key)
  if a == nil then return text end
  local ok, formatted = pcall(string.format, text, a, b, c)
  if ok and type(formatted) == "string" then return formatted end
  return text
end

-- Selection -----------------------------------------------------------------

-- Persists the standalone choice. Refused while unrealUI owns the language.
-- Returns true when the language actually changed.
local function SetLanguage(code)
  if not languageByCode[code] or followsUnrealUI or code == active then return false end
  active = code
  settled = true
  if type(unrealMapDB) ~= "table" then unrealMapDB = {} end
  unrealMapDB.language = code
  return true
end

unrealMapLocale = {
  Register = Register,
  Resolve = Resolve,
  L = L,
  SetLanguage = SetLanguage,
  GetLanguage = function() return active end,
  GetLanguages = function() return languages end,
  GetLanguageLabel = function(code)
    local entry = languageByCode[code or active]
    return entry and entry.label or tostring(code)
  end,
  FlagTexture = function(code)
    local entry = languageByCode[code]
    return entry and (FLAG_PATH .. entry.flag) or nil
  end,
  IsFollowingUnrealUI = function() return followsUnrealUI end,
  IsSettled = function() return settled end,
}
