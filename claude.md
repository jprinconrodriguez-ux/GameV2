# Jokers' Gambit — Claude Code Instructions

- The Rule Book is the canonical source of truth for all numbers.
- Tests in tests.lua must assert the spec, not the code.
- Run tests headless with: lua tests.lua
- Never modify deck.lua, evaluator.lua, rules.lua, gamestate.lua, saveload.lua during M1.
- This is a LÖVE2D (LOVE2D) Lua game. love.math is available at runtime but stubbed in tests.
