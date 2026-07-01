----------------------------------------------------------------------
-- main.lua — Study to Earn (Quizlatro)
--
-- Core mod logic:
--   1. Loads the question pool from data.lua
--   2. Manages a shuffled queue so questions don't repeat until
--      all have been seen, then reshuffles
--   3. Provides G.FUNCS.open_study_menu — opens an overlay with
--      a question banner + 4 answer buttons
--   4. Provides answer handlers that award/deny discards
--   5. Forces discards to 0 at the start of every round
----------------------------------------------------------------------

----------------------------------------------------------------------
-- 1. LOAD QUESTION POOL
----------------------------------------------------------------------

-- SMODS.load_file returns a function (the loaded chunk); call it
-- immediately to get the table of questions.
local all_questions = SMODS.load_file("data.lua")()

-- Shuffled queue of indices into all_questions.
-- When empty, we reshuffle and refill.
local question_queue = {}

--- Fisher-Yates shuffle (in-place)
local function shuffle_table(t)
    for i = #t, 2, -1 do
        local j = math.random(1, i)
        t[i], t[j] = t[j], t[i]
    end
end

--- Refill and shuffle the question queue
local function refill_queue()
    question_queue = {}
    for i = 1, #all_questions do
        question_queue[#question_queue + 1] = i
    end
    shuffle_table(question_queue)
end

--- Pop the next question index from the queue.
--- Automatically refills if the queue is exhausted.
local function next_question_index()
    if #question_queue == 0 then
        refill_queue()
    end
    return table.remove(question_queue)
end

-- Seed the queue on load
refill_queue()

----------------------------------------------------------------------
-- 2. DYNAMIC WRONG-ANSWER GENERATION
----------------------------------------------------------------------

--- Given a question index, returns:
---   question_text (string), answers (table of 4 strings), correct_index (int)
---
--- Wrong answers are pulled from other questions' correct answers.
--- All 4 options are shuffled.
local function generate_prompt(q_index)
    local question = all_questions[q_index]
    local correct_answer = question.a

    -- Collect candidate wrong answers (all other questions' answers)
    local candidates = {}
    for i = 1, #all_questions do
        if i ~= q_index then
            candidates[#candidates + 1] = all_questions[i].a
        end
    end
    shuffle_table(candidates)

    -- Pick 3 wrong answers (or fewer if the pool is small)
    local num_wrong = math.min(3, #candidates)
    local options = { correct_answer }
    for i = 1, num_wrong do
        options[#options + 1] = candidates[i]
    end

    -- Shuffle options so the correct answer isn't always first
    shuffle_table(options)

    -- Find the correct answer's position after shuffling
    local correct_idx = 1
    for i, v in ipairs(options) do
        if v == correct_answer then
            correct_idx = i
            break
        end
    end

    return question.q, options, correct_idx
end

----------------------------------------------------------------------
-- 3. FORCE 0 DISCARDS AT ROUND START
----------------------------------------------------------------------

-- Hook into the game's round initialization to zero out discards.
-- This runs every time a new round/blind begins.
local _orig_init_game_object = Game.init_game_object
function Game:init_game_object()
    local ret = _orig_init_game_object(self)
    -- Force starting discards to 0
    ret.round_resets.discards = 0
    return ret
end

----------------------------------------------------------------------
-- 4. STUDY OVERLAY MENU
----------------------------------------------------------------------

-- Stores the current session's correct answer index so the
-- answer-button handlers can check it.
local current_correct_idx = nil
local current_correct_text = nil

--- Build the overlay UIBox definition for the study menu.
--- @param question_text string  The question to display
--- @param options table         Array of 4 answer strings
--- @return table                UIBox definition table
local function build_study_overlay(question_text, options)
    -- Build answer button nodes
    local answer_nodes = {}
    for i, answer_text in ipairs(options) do
        answer_nodes[#answer_nodes + 1] = {
            n = G.UIT.R,
            config = { align = "cm", padding = 0.05 },
            nodes = {
                {
                    n = G.UIT.C,
                    config = {
                        align = "cm",
                        padding = 0.12,
                        r = 0.1,
                        minw = 5.5,
                        minh = 0.7,
                        hover = true,
                        shadow = true,
                        colour = G.C.BLUE,
                        button = "study_select_answer",
                        ref_table = { answer_index = i, answer_text = answer_text },
                    },
                    nodes = {
                        {
                            n = G.UIT.T,
                            config = {
                                text = answer_text,
                                colour = G.C.UI.TEXT_LIGHT,
                                scale = 0.42,
                            },
                        },
                    },
                },
            },
        }
    end

    -- Full overlay definition
    return {
        n = G.UIT.ROOT,
        config = {
            align = "cm",
            colour = { 0, 0, 0, 0.85 }, -- dark semi-transparent background
            padding = 0.5,
            r = 0.15,
        },
        nodes = {
            {
                n = G.UIT.C,
                config = { align = "cm", padding = 0.2 },
                nodes = {
                    -- Question Banner
                    {
                        n = G.UIT.R,
                        config = { align = "cm", padding = 0.15 },
                        nodes = {
                            {
                                n = G.UIT.C,
                                config = {
                                    align = "cm",
                                    padding = 0.25,
                                    r = 0.15,
                                    minw = 6.0,
                                    minh = 1.2,
                                    colour = G.C.BLACK,
                                    emboss = 0.05,
                                },
                                nodes = {
                                    {
                                        n = G.UIT.T,
                                        config = {
                                            text = question_text,
                                            colour = G.C.GOLD,
                                            scale = 0.52,
                                        },
                                    },
                                },
                            },
                        },
                    },

                    -- Spacer
                    {
                        n = G.UIT.R,
                        config = { align = "cm" },
                        nodes = {
                            { n = G.UIT.B, config = { h = 0.15, w = 0.1 } },
                        },
                    },

                    -- Answer Buttons
                    {
                        n = G.UIT.C,
                        config = { align = "cm", padding = 0.05 },
                        nodes = answer_nodes,
                    },

                    -- Spacer
                    {
                        n = G.UIT.R,
                        config = { align = "cm" },
                        nodes = {
                            { n = G.UIT.B, config = { h = 0.1, w = 0.1 } },
                        },
                    },

                    -- Cancel / Close button
                    {
                        n = G.UIT.R,
                        config = { align = "cm" },
                        nodes = {
                            {
                                n = G.UIT.C,
                                config = {
                                    align = "cm",
                                    padding = 0.1,
                                    r = 0.1,
                                    minw = 2.0,
                                    minh = 0.5,
                                    hover = true,
                                    colour = G.C.RED,
                                    button = "study_close_menu",
                                },
                                nodes = {
                                    {
                                        n = G.UIT.T,
                                        config = {
                                            text = "Cancel",
                                            colour = G.C.UI.TEXT_LIGHT,
                                            scale = 0.35,
                                        },
                                    },
                                },
                            },
                        },
                    },
                },
            },
        },
    }
end

----------------------------------------------------------------------
-- 5. G.FUNCS — BUTTON HANDLERS
----------------------------------------------------------------------

--- Opens the study overlay menu with a new question.
G.FUNCS.open_study_menu = function(e)
    -- Don't open if an overlay is already showing
    if G.OVERLAY_MENU then return end

    -- Don't open if we're not in the right game state
    if G.STATE ~= G.STATES.SELECTING_HAND then return end

    -- Get the next question
    local q_idx = next_question_index()
    local question_text, options, correct_idx = generate_prompt(q_idx)

    -- Store the correct answer for the handlers
    current_correct_idx = correct_idx
    current_correct_text = options[correct_idx]

    -- Build and display the overlay
    local overlay_def = build_study_overlay(question_text, options)
    G.OVERLAY_MENU = UIBox({
        definition = overlay_def,
        config = { align = "cm", bond = "Weak" },
    })

    sendDebugMessage("Quizlatro: Opened study menu — Q: " .. question_text)
end

--- Handler for clicking an answer button.
--- The button's ref_table contains { answer_index, answer_text }.
G.FUNCS.study_select_answer = function(e)
    local ref = e.config.ref_table
    if not ref then return end

    local is_correct = (ref.answer_text == current_correct_text)

    -- Close the overlay immediately
    if G.OVERLAY_MENU then
        G.OVERLAY_MENU:remove()
        G.OVERLAY_MENU = nil
    end

    if is_correct then
        -- Award a discard
        G.GAME.current_round.discards_left = G.GAME.current_round.discards_left + 1
        play_sound("tarot1")
        -- Brief attention text
        G.E_MANAGER:add_event(Event({
            trigger = "after",
            delay = 0.1,
            func = function()
                attention_text({
                    text = "CORRECT! +1 Discard",
                    scale = 1.2,
                    hold = 1.0,
                    cover = G.deck,
                    cover_colour = G.C.GREEN,
                })
                return true
            end,
        }))
        sendDebugMessage("Quizlatro: Correct answer! Discards: " .. tostring(G.GAME.current_round.discards_left))
    else
        -- No discard awarded
        play_sound("cancel")
        G.E_MANAGER:add_event(Event({
            trigger = "after",
            delay = 0.1,
            func = function()
                attention_text({
                    text = "WRONG! Answer: " .. (current_correct_text or "???"),
                    scale = 1.0,
                    hold = 1.5,
                    cover = G.deck,
                    cover_colour = G.C.RED,
                })
                return true
            end,
        }))
        sendDebugMessage("Quizlatro: Wrong answer.")
    end

    -- Clear session state
    current_correct_idx = nil
    current_correct_text = nil
end

--- Handler for the Cancel button on the study overlay.
G.FUNCS.study_close_menu = function(e)
    if G.OVERLAY_MENU then
        G.OVERLAY_MENU:remove()
        G.OVERLAY_MENU = nil
    end
    current_correct_idx = nil
    current_correct_text = nil
    sendDebugMessage("Quizlatro: Study menu cancelled.")
end

sendDebugMessage("Quizlatro: main.lua loaded successfully. " .. #all_questions .. " questions in pool.")
