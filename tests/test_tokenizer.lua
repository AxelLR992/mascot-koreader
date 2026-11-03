local T = require("lib")
local Tokenizer = require("mascot.tokenizer")

T.test("tokenizer: lowercases ASCII", function()
    T.eq(Tokenizer.words("The Sea AND the Ship"), { "the", "sea", "and", "the", "ship" })
end)

T.test("tokenizer: lowercases Latin-1 accented letters", function()
    T.eq(Tokenizer.words("ÁRBOL Ñandú ÉPOCA Über"), { "árbol", "ñandú", "época", "über" })
end)

T.test("tokenizer: leaves the multiplication sign alone", function()
    T.eq(Tokenizer.lower("2×3 X"), "2×3 x")
end)

T.test("tokenizer: typographic quotes and dashes separate words", function()
    T.eq(Tokenizer.words("“Hola” —dijo— «adiós»…"), { "hola", "dijo", "adiós" })
end)

T.test("tokenizer: Spanish inverted marks separate words", function()
    T.eq(Tokenizer.words("¿Qué? ¡Nada!"), { "qué", "nada" })
end)

T.test("tokenizer: keeps inner apostrophes, curly or straight", function()
    T.eq(Tokenizer.words("Don't stop; it’s fine"), { "don't", "stop", "it's", "fine" })
end)

T.test("tokenizer: trims quoting apostrophes", function()
    T.eq(Tokenizer.words("'quoted' words"), { "quoted", "words" })
end)

T.test("tokenizer: ignores digits and punctuation", function()
    T.eq(Tokenizer.words("Chapter 12, page 3!"), { "chapter", "page" })
end)

T.test("tokenizer: empty text gives no words", function()
    T.eq(Tokenizer.words(""), {})
end)
