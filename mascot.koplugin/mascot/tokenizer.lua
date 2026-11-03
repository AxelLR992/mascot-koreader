--[[--
Splits page text into lowercase words.

Pure Lua, no KOReader dependency. Works on UTF-8 bytes; lowercasing covers ASCII and the Latin-1
Supplement (accented letters of Spanish, Portuguese, French, German, Italian, ...). Other scripts
are split correctly but not lowercased.
]]

local Tokenizer = {}

-- Typographic punctuation that separates words (UTF-8 byte sequences).
local SEPARATORS = {
    "\226\128\156", "\226\128\157", "\226\128\152",  -- “ ” ‘
    "\194\171", "\194\187",                          -- « »
    "\226\128\148", "\226\128\147", "\226\128\149",  -- — – ―
    "\226\128\166",                                  -- …
    "\194\191", "\194\161",                          -- ¿ ¡
    "\226\128\162", "\194\183",                      -- • ·
}
local CURLY_APOSTROPHE = "\226\128\153"  -- ’

-- ASCII-only lowercase. string.lower() depends on the C locale, which we do not control.
local LOWER = {}
for byte = 65, 90 do LOWER[string.char(byte)] = string.char(byte + 32) end

--- Lowercase a UTF-8 string (ASCII and Latin-1 Supplement).
function Tokenizer.lower(text)
    text = text:gsub("[A-Z]", LOWER)
    return (text:gsub("\195([\128-\158])", function(byte)
        if byte == "\151" then return nil end  -- × is not a letter; keep it
        return "\195" .. string.char(byte:byte() + 32)
    end))
end

--- Lowercase words of `text`, in order. Apostrophes inside a word are kept ("don't").
function Tokenizer.words(text)
    text = text:gsub(CURLY_APOSTROPHE, "'")
    for _, separator in ipairs(SEPARATORS) do
        text = text:gsub(separator, " ")
    end
    text = Tokenizer.lower(text)
    local words = {}
    for word in text:gmatch("[A-Za-z\128-\255']+") do
        word = word:gsub("^'+", ""):gsub("'+$", "")
        if word ~= "" then words[#words + 1] = word end
    end
    return words
end

return Tokenizer
