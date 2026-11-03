-- Tiny locales used only by the tests. Real locales live in character packs.
return {
    en = {
        keywords = {
            themes = {
                death = { "death", "die*", "funeral" },
                sea = { "sea", "ship*", "wave*" },
                night = { "night", "dark*", "die*" },  -- shares "die*" with death on purpose
            },
            events = { funeral = { "funeral", "burial" } },
            tone = {
                positive = { "joy", "happy", "love*" },
                negative = { "grief", "sad", "die*" },
            },
        },
    },
    es = {
        keywords = {
            themes = {
                death = { "muerte", "mor*", "murió" },
                sea = { "mar", "barco*", "ola*" },
            },
        },
    },
}
