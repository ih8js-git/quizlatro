----------------------------------------------------------------------
-- study_button.lua
-- This file is COPY-APPENDED into game.lua by Lovely (patches.copy).
-- It wraps Game:update to inject a floating "Study" UIBox button
-- whenever the player is in the hand-selection state.
--
-- IMPORTANT: Because this runs as part of game.lua's main chunk,
-- the global `G` does NOT exist yet at load time. ALL references
-- to `G` must be inside functions that execute later (e.g. inside
-- the Game:update wrapper), never at the top level.
----------------------------------------------------------------------

-- Guard: only initialize once
if not _QUIZLATRO_BUTTON_INIT then
    _QUIZLATRO_BUTTON_INIT = true

    -- Reference to the floating UIBox so we can manage its lifecycle
    local study_uibox = nil

    -- Track whether we've done the one-time G.FUNCS setup
    local _funcs_registered = false

    -- Wrap Game:update to inject/remove the study button each frame
    local _original_game_update = Game.update
    function Game:update(dt)
        _original_game_update(self, dt)

        -- Lazy init: register G.FUNCS once G is available.
        -- G doesn't exist when game.lua is first loaded, but by the
        -- time Game:update runs, G is fully initialized.
        if not _funcs_registered and G and G.FUNCS then
            _funcs_registered = true

            -- Gate function: controls whether the button appears active
            G.FUNCS.study_button_can_open = function(e)
                if G.FUNCS.open_study_menu and G.GAME and G.GAME.current_round then
                    e.config.colour = G.C.ORANGE
                    e.config.button = "open_study_menu"
                else
                    e.config.colour = G.C.UI.BACKGROUND_INACTIVE
                    e.config.button = nil
                end
            end
        end

        -- Safety: bail if G isn't ready yet
        if not G or not G.STATES then return end

        -- Only show the button during the hand-selection phase of a run
        local should_show = (
            G.STATE == G.STATES.SELECTING_HAND
            and G.GAME
            and G.GAME.current_round
            and G.play             -- play area exists (we're in a run)
            and not G.OVERLAY_MENU -- don't show if an overlay is already open
        )

        if should_show and not study_uibox then
            -- Create the floating Study button UIBox
            study_uibox = UIBox({
                definition = {
                    n = G.UIT.ROOT,
                    config = {
                        align = "cm",
                        colour = G.C.CLEAR,
                        padding = 0.1,
                    },
                    nodes = {
                        {
                            n = G.UIT.C,
                            config = {
                                align = "cm",
                                padding = 0.15,
                                r = 0.1,
                                minw = 2.5,
                                minh = 0.8,
                                hover = true,
                                shadow = true,
                                colour = G.C.ORANGE,
                                button = "open_study_menu",
                                func = "study_button_can_open",
                            },
                            nodes = {
                                {
                                    n = G.UIT.T,
                                    config = {
                                        text = "STUDY",
                                        colour = G.C.UI.TEXT_LIGHT,
                                        scale = 0.55,
                                    },
                                },
                            },
                        },
                    },
                },
                config = {
                    align = "bm",       -- bottom-middle of hand area
                    bond = "Weak",
                    offset = { x = -4.5, y = 1.5 },  -- below cards, left of Play Hand
                    major = G.hand,
                },
            })

        elseif not should_show and study_uibox then
            -- Remove the button when we leave the hand-selection state
            study_uibox:remove()
            study_uibox = nil
        end
    end
end
