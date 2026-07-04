-- Quizlatro: Quiz-gated discard mod for Balatro
-- Intercepts discard to present a multiple-choice question.
-- Correct answer = discard goes through. Wrong answer = no penalty, overlay closes.

QUIZLATRO = QUIZLATRO or {}

local MOD_DIR = nil -- patched by lovely

----------------------------------------------------------------------
-- QUESTION LOADING & SHUFFLING (deck-aware)
----------------------------------------------------------------------

local decks = {}          -- Array of loaded decks: { name, questions }
local active_deck = nil   -- Currently selected deck (reference into decks[])
local order = {}          -- Shuffled indices within active_deck.questions
local current_index = 0   -- Position in the shuffled order

-- Fisher-Yates shuffle
local function shuffle(t)
    for i = #t, 2, -1 do
        local j = math.random(1, i)
        t[i], t[j] = t[j], t[i]
    end
end

local function reset_order()
    order = {}
    if not active_deck then return end
    for i = 1, #active_deck.questions do
        order[i] = i
    end
    shuffle(order)
    current_index = 0
end

local function select_deck(idx)
    active_deck = decks[idx]
    QUIZLATRO.active_deck_idx = idx
    reset_order()
    print('[Quizlatro] Selected deck: ' .. active_deck.name .. ' (' .. #active_deck.questions .. ' questions)')
end

local function next_question()
    current_index = current_index + 1
    if current_index > #order then
        reset_order()
        current_index = 1
    end
    local q_idx = order[current_index]
    return active_deck.questions[q_idx], q_idx
end

-- Pick 3 random wrong answers from the SAME deck only
local function get_choices(correct_idx)
    local qs = active_deck.questions
    local pool = {}
    for i = 1, #qs do
        if i ~= correct_idx then
            pool[#pool + 1] = qs[i].a
        end
    end
    shuffle(pool)

    local choices = {
        qs[correct_idx].a,
        pool[1],
        pool[2],
        pool[3],
    }
    shuffle(choices)
    return choices
end

----------------------------------------------------------------------
-- DECK SELECTOR UI
----------------------------------------------------------------------

local function build_deck_selector_ui()
    local scale = 0.45

    local rows = {}

    -- Title
    rows[#rows + 1] = {n = G.UIT.R, config = {align = "cm", padding = 0.05, colour = G.C.DYN_UI.DARK, r = 0.1, emboss = 0.05}, nodes = {
        {n = G.UIT.T, config = {text = "Choose a Study Deck", scale = scale * 1.3, colour = G.C.GOLD, shadow = true}}
    }}
    rows[#rows + 1] = {n = G.UIT.B, config = {w = 0.1, h = 0.15}}

    -- One button per deck
    for idx, deck in ipairs(decks) do
        local btn_id = 'quizlatro_deck_' .. idx
        G.FUNCS[btn_id] = function(btn_e)
            btn_e.config.button = nil
            play_sound('generic1', 0.9, 0.6)
            select_deck(idx)
            G.FUNCS.exit_overlay_menu()
            attention_text({
                text = deck.name,
                scale = 1.0,
                hold = 1.2,
                major = G.play,
                backdrop_colour = G.C.BLUE,
                colour = G.C.WHITE,
                align = 'cm',
                offset = {x = 0, y = -1},
            })
        end

        local label = deck.name .. "  (" .. #deck.questions .. ")"

        rows[#rows + 1] = {n = G.UIT.R, config = {align = "cm", padding = 0.06}, nodes = {
            {n = G.UIT.C, config = {
                align = "cm", padding = 0.12, r = 0.1, minw = 4.0, minh = 0.65,
                hover = true, colour = (idx == (QUIZLATRO.active_deck_idx or 1)) and G.C.GREEN or G.C.BLUE,
                button = btn_id, shadow = true, one_press = true
            }, nodes = {
                {n = G.UIT.T, config = {text = label, scale = scale * 0.9, colour = G.C.WHITE, shadow = true}}
            }}
        }}
    end

    local definition = {n = G.UIT.ROOT, config = {
        align = "cm", colour = G.C.DYN_UI.MAIN, r = 0.1, padding = 0.15, emboss = 0.05,
        minw = 5, minh = 3
    }, nodes = rows}

    return definition
end

----------------------------------------------------------------------
-- QUIZ UI (uses native overlay_menu)
----------------------------------------------------------------------

local function build_quiz_ui(question_entry, correct_idx, on_correct, on_dismiss)
    local choices = get_choices(correct_idx)
    local correct_answer = question_entry.a
    local scale = 0.45

    -- Wrap long question text into lines
    local question_text = question_entry.q
    local max_chars = 45
    local lines = {}
    local remaining = question_text
    while #remaining > 0 do
        if #remaining <= max_chars then
            lines[#lines + 1] = remaining
            remaining = ""
        else
            local cut = max_chars
            local space = remaining:sub(1, cut):match(".*()%s")
            if space and space > 1 then
                cut = space - 1
            end
            lines[#lines + 1] = remaining:sub(1, cut)
            remaining = remaining:sub(cut + 1):match("^%s*(.*)$") or ""
        end
    end

    -- Build question text rows
    local q_rows = {}
    for _, line in ipairs(lines) do
        q_rows[#q_rows + 1] = {n = G.UIT.R, config = {align = "cm", padding = 0.02}, nodes = {
            {n = G.UIT.T, config = {text = line, scale = scale * 1.1, colour = G.C.WHITE, shadow = true, lang = G.LANGUAGES['ja'] or G.LANG}}
        }}
    end

    -- Build answer buttons
    local function make_answer_button(text, index)
        local btn_id = 'quizlatro_answer_' .. index
        G.FUNCS[btn_id] = function(btn_e)
            btn_e.config.button = nil
            if text == correct_answer then
                play_sound('generic1', 0.9, 0.6)
                G.FUNCS.exit_overlay_menu()
                on_correct()
            else
                -- Wrong answer: play error sound, close overlay, no penalty
                G.E_MANAGER:add_event(Event({trigger = 'after', delay = 0.06, blockable = false, blocking = false, func = function()
                    play_sound('tarot2', 0.76, 0.4)
                    return true
                end}))
                play_sound('tarot2', 1, 0.4)
                G.FUNCS.exit_overlay_menu()
                -- Show "Wrong!" floating text
                attention_text({
                    text = "Wrong!",
                    scale = 1.4,
                    hold = 1,
                    major = G.play,
                    backdrop_colour = G.C.RED,
                    colour = G.C.WHITE,
                    align = 'cm',
                    offset = {x = 0, y = -1},
                })
                -- Re-enable the discard button
                if on_dismiss then on_dismiss() end
            end
        end

        local display = text
        if #display > 28 then
            display = display:sub(1, 25) .. "..."
        end

        return {n = G.UIT.C, config = {
            align = "cm", padding = 0.12, r = 0.1, minw = 2.6, minh = 0.7,
            hover = true, colour = G.C.BLUE, button = btn_id, shadow = true, one_press = true
        }, nodes = {
            {n = G.UIT.T, config = {text = display, scale = scale * 0.85, colour = G.C.WHITE, shadow = true, lang = G.LANGUAGES['ja'] or G.LANG}}
        }}
    end

    -- Cancel button callback
    G.FUNCS.quizlatro_cancel = function()
        G.FUNCS.exit_overlay_menu()
        if on_dismiss then on_dismiss() end
    end

    -- Deck switcher callback
    G.FUNCS.quizlatro_switch_deck = function()
        G.FUNCS.exit_overlay_menu()
        if on_dismiss then on_dismiss() end
        -- Small delay then show deck selector
        G.E_MANAGER:add_event(Event({trigger = 'after', delay = 0.15, blockable = false, blocking = false, func = function()
            G.SETTINGS.paused = true
            G.FUNCS.overlay_menu{
                definition = build_deck_selector_ui()
            }
            return true
        end}))
    end

    -- Deck name label
    local deck_label = active_deck and active_deck.name or "?"

    -- Assemble UI
    local definition = {n = G.UIT.ROOT, config = {
        align = "cm", colour = G.C.DYN_UI.MAIN, r = 0.1, padding = 0.15, emboss = 0.05,
        minw = 6, minh = 3
    }, nodes = {
        -- Title
        {n = G.UIT.R, config = {align = "cm", padding = 0.05, colour = G.C.DYN_UI.DARK, r = 0.1, emboss = 0.05}, nodes = {
            {n = G.UIT.T, config = {text = "Study to Discard!", scale = scale * 1.3, colour = G.C.GOLD, shadow = true}}
        }},
        -- Deck indicator
        {n = G.UIT.R, config = {align = "cm", padding = 0.03}, nodes = {
            {n = G.UIT.T, config = {text = "Deck: " .. deck_label, scale = scale * 0.65, colour = G.C.UI.TEXT_INACTIVE, shadow = false}}
        }},
        {n = G.UIT.B, config = {w = 0.1, h = 0.1}},
        -- Question
        {n = G.UIT.R, config = {align = "cm", padding = 0.1, colour = G.C.BLACK, r = 0.1, minw = 5.8}, nodes = q_rows},
        {n = G.UIT.B, config = {w = 0.1, h = 0.15}},
        -- Answers (2x2 grid)
        {n = G.UIT.R, config = {align = "cm", padding = 0.06}, nodes = {
            make_answer_button(choices[1], 1),
            {n = G.UIT.B, config = {w = 0.15, h = 0.1}},
            make_answer_button(choices[2], 2),
        }},
        {n = G.UIT.R, config = {align = "cm", padding = 0.06}, nodes = {
            make_answer_button(choices[3], 3),
            {n = G.UIT.B, config = {w = 0.15, h = 0.1}},
            make_answer_button(choices[4], 4),
        }},
        {n = G.UIT.B, config = {w = 0.1, h = 0.05}},
        -- Bottom row: Switch Deck + Cancel
        {n = G.UIT.R, config = {align = "cm", padding = 0.08}, nodes = {
            {n = G.UIT.C, config = {
                align = "cm", padding = 0.1, r = 0.1, minw = 1.8, minh = 0.5,
                hover = true, colour = G.C.ORANGE, button = 'quizlatro_switch_deck', shadow = true
            }, nodes = {
                {n = G.UIT.T, config = {text = "Switch Deck", scale = scale * 0.7, colour = G.C.WHITE, shadow = true}}
            }},
            {n = G.UIT.B, config = {w = 0.15, h = 0.1}},
            {n = G.UIT.C, config = {
                align = "cm", padding = 0.1, r = 0.1, minw = 1.5, minh = 0.5,
                hover = true, colour = G.C.GREY, button = 'quizlatro_cancel', shadow = true
            }, nodes = {
                {n = G.UIT.T, config = {text = "Cancel", scale = scale * 0.75, colour = G.C.WHITE, shadow = true}}
            }}
        }},
    }}

    return definition
end

----------------------------------------------------------------------
-- INITIALIZATION
----------------------------------------------------------------------

local function load_questions()
    if not MOD_DIR then
        print('[Quizlatro] MOD_DIR not set (lovely patch failed?). Mod disabled.')
        return false
    end

    -- Load questions.lua using love.filesystem (lovely mounts mod dirs)
    local load_path = MOD_DIR .. '/questions.lua'
    local chunk, err = love.filesystem.load(load_path)
    if not chunk then
        -- Fallback: try nativefs / io.open for absolute paths
        local f = io.open(load_path, 'r')
        if f then
            local content = f:read('*a')
            f:close()
            chunk, err = load(content)
        end
    end

    if not chunk then
        print('[Quizlatro] Failed to load questions: ' .. tostring(err))
        print('[Quizlatro] Tried path: ' .. tostring(load_path))
        print('[Quizlatro] Mod disabled - discards will work normally.')
        return false
    end

    local ok, result = pcall(chunk)
    if not ok then
        print('[Quizlatro] Error executing questions.lua: ' .. tostring(result))
        return false
    end

    -- Validate deck structure
    if not result or type(result) ~= 'table' or #result < 1 then
        print('[Quizlatro] questions.lua must return at least 1 deck.')
        print('[Quizlatro] Mod disabled - discards will work normally.')
        return false
    end

    -- Backward compat: if the first entry has .q/.a, treat as a single flat deck
    if result[1].q and result[1].a then
        print('[Quizlatro] Detected flat question list - wrapping in a single deck.')
        result = { { name = "Default", questions = result } }
    end

    -- Validate each deck has at least 4 questions
    for i, deck in ipairs(result) do
        if not deck.questions or type(deck.questions) ~= 'table' or #deck.questions < 4 then
            print('[Quizlatro] Deck "' .. tostring(deck.name or i) .. '" needs at least 4 questions. Found: ' .. tostring(deck.questions and #deck.questions or 0))
            print('[Quizlatro] Mod disabled - discards will work normally.')
            return false
        end
    end

    decks = result
    print('[Quizlatro] Loaded ' .. #decks .. ' deck(s):')
    for i, deck in ipairs(decks) do
        print('  [' .. i .. '] ' .. deck.name .. ' (' .. #deck.questions .. ' questions)')
    end

    -- Select first deck by default
    select_deck(1)
    return true
end

local function install_discard_hook()
    local original_discard = G.FUNCS.discard_cards_from_highlighted

    G.FUNCS.discard_cards_from_highlighted = function(e, hook)
        -- Bypass quiz for blind hooks (e.g. The Hook blind)
        if hook then
            return original_discard(e, hook)
        end

        -- Bypass if no cards highlighted or no discards left
        if not G.hand or not G.hand.highlighted or #G.hand.highlighted <= 0 then
            return original_discard(e, hook)
        end
        if G.GAME.current_round.discards_left <= 0 then
            return original_discard(e, hook)
        end

        -- Get next question
        local q, q_idx = next_question()

        -- Show quiz overlay
        G.SETTINGS.paused = true
        G.FUNCS.overlay_menu{
            definition = build_quiz_ui(q, q_idx, function()
                -- Correct answer callback: execute real discard
                original_discard(e, hook)
            end, function()
                -- Dismiss callback: re-enable the discard button (one_press disables it)
                if e then
                    e.disable_button = nil
                end
            end)
        }
    end
end

-- Deferred init: hooks into Game:start_up so G.FUNCS exists
local game_start_ref = Game.start_up
function Game:start_up(...)
    local result = game_start_ref(self, ...)
    if not QUIZLATRO.loaded then
        if load_questions() then
            install_discard_hook()
            QUIZLATRO.loaded = true
            print('[Quizlatro] Mod initialized successfully.')
        end
    end
    return result
end
