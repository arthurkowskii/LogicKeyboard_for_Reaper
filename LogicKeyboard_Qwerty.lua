-- Script Name: Extended MIDI Virtual Keyboard (QWERTY Layout - Z/X Octave)
-- Author: Arthur Kowskii
-- Version: 1.2 (QWERTY with Z/X Octave)

-- Initial configuration
local octave_offset = -12
local velocity = 100
local active_notes = {}
-- local w_key_released = true -- No longer needed for octave
local z_key_released = true -- State of the Z key (true = released) - CHANGED
local x_key_released = true
local shift_pressed = false
local mod_wheel_value = 0
local mod_wheel_step = 10
local mod_wheel_target = 0

-- Table of keys and their associated notes (in semitones from C3 = 60)
-- ** QWERTY Layout **
local key_to_note = {
    -- Base octave (Typical QWERTY piano layout)
    [0x41] = 60,  -- A = C
    [0x57] = 61,  -- W = C#  -- W is now only a note key
    [0x53] = 62,  -- S = D
    [0x45] = 63,  -- E = D#
    [0x44] = 64,  -- D = E
    [0x46] = 65,  -- F = F
    [0x54] = 66,  -- T = F#
    [0x47] = 67,  -- G = G
    [0x59] = 68,  -- Y = G#
    [0x48] = 69,  -- H = A
    [0x55] = 70,  -- U = A#
    [0x4A] = 71,  -- J = B
    -- Upper octave (Continuing the pattern)
    [0x4B] = 72,  -- K = C
    [0x4F] = 73,  -- O = C#
    [0x4C] = 74,  -- L = D
    [0x50] = 75,  -- P = D#
    [0xBA] = 76,  -- ; = E  (Semicolon key)
    [0xDE] = 77,  -- ' = F  (Apostrophe key)
    [0xDB] = 81,  -- [ = A
}

-- Key interception (blocking shortcuts in Reaper)
-- Intercept note keys
for key, _ in pairs(key_to_note) do
    reaper.JS_VKeys_Intercept(key, 1)
end

-- Intercept Z, X, and Shift keys for octave shifting and mod wheel - CHANGED
reaper.JS_VKeys_Intercept(0x5A, 1) -- Z (Octave Down) - CHANGED
reaper.JS_VKeys_Intercept(0x58, 1) -- X (Octave Up)
reaper.JS_VKeys_Intercept(0x10, 1) -- Shift (Mod Wheel)

-- Function to send a MIDI message (No changes needed)
local function send_midi(note, is_note_on)
    local status = is_note_on and 0x90 or 0x80
    reaper.StuffMIDIMessage(0, status, note, velocity)
end

-- Function to send a Control Change message for the mod wheel (No changes needed)
local function send_mod_wheel(value)
    reaper.StuffMIDIMessage(0, 0xB0, 1, value)
end

-- Main function
local function main()
    local key_states = reaper.JS_VKeys_GetState(0)

    -- Manage transposition with Z and X keys - CHANGED
    local z_state = key_states:byte(0x5A) ~= 0  -- 'Z' key (octave -1) - CHANGED
    local x_state = key_states:byte(0x58) ~= 0  -- 'X' key (octave +1)
    local shift_state = key_states:byte(0x10) ~= 0  -- 'Shift' key (mod wheel)

    -- Detect octave changes
    local octave_changed = false
    local old_octave_offset = octave_offset

    -- Z key to decrease the octave (only when the key is pressed and then released) - CHANGED
    if z_state and z_key_released then
        octave_offset = octave_offset - 12
        z_key_released = false -- CHANGED
        octave_changed = true
    elseif not z_state then
        z_key_released = true -- CHANGED
    end

    -- X key to increase the octave (only when the key is pressed and then released) - (No change needed here)
    if x_state and x_key_released then
        octave_offset = octave_offset + 12
        x_key_released = false
        octave_changed = true
    elseif not x_state then
        x_key_released = true
    end

    -- If the octave changed, stop all active notes and restart them at the new octave (No changes needed here)
    if octave_changed then
        local notes_to_restart = {}
        for note, _ in pairs(active_notes) do
            send_midi(note + old_octave_offset, false)
            notes_to_restart[note] = true
        end
        for note, _ in pairs(notes_to_restart) do
            send_midi(note + octave_offset, true)
        end
    end

    -- Manage mod wheel with Shift key (No changes needed here)
    if shift_state then
        mod_wheel_target = 127
    else
        mod_wheel_target = 0
    end
    if mod_wheel_value < mod_wheel_target then
        mod_wheel_value = math.min(mod_wheel_value + mod_wheel_step, mod_wheel_target)
    elseif mod_wheel_value > mod_wheel_target then
        mod_wheel_value = math.max(mod_wheel_value - mod_wheel_step, mod_wheel_target)
    end
    send_mod_wheel(mod_wheel_value)

    -- Loop through all defined keys (No changes needed here)
    for key, note in pairs(key_to_note) do
        local state = key_states:byte(key)
        if state and state ~= 0 and not active_notes[note] then
            send_midi(note + octave_offset, true)
            active_notes[note] = true
        end
        if (not state or state == 0) and active_notes[note] then
            send_midi(note + octave_offset, false)
            active_notes[note] = nil
        end
    end

    reaper.defer(main)
end

-- Cleanup at script termination
local function cleanup()
    -- Stop all active notes
    for note, _ in pairs(active_notes) do
        send_midi(note + octave_offset, false)
    end

    -- Release all intercepted keys
    for key, _ in pairs(key_to_note) do
        reaper.JS_VKeys_Intercept(key, -1)
    end

    -- Release Z, X, and Shift keys - CHANGED
    reaper.JS_VKeys_Intercept(0x5A, -1) -- Z (Octave Down) - CHANGED
    reaper.JS_VKeys_Intercept(0x58, -1) -- X (Octave Up)
    reaper.JS_VKeys_Intercept(0x10, -1) -- Shift (Mod Wheel)
end

-- Check for the SWS extension and start the script (No changes needed)
if not reaper.APIExists("JS_VKeys_GetState") then
    reaper.ShowMessageBox("The SWS extension is required for this script. Install SWS and JS_ReaScript API.", "Error", 0)
    return
end

-- For toolbar button animation (No changes needed)
local _, _, section_id, command_id = reaper.get_action_context()
if command_id ~= 0 then
    reaper.SetToggleCommandState(section_id, command_id, 1)
    reaper.RefreshToolbar2(section_id, command_id)
end

-- Start the script and set up cleanup (No changes needed)
reaper.atexit(function()
    cleanup()
    if command_id ~= 0 then
        reaper.SetToggleCommandState(section_id, command_id, 0)
        reaper.RefreshToolbar2(section_id, command_id)
    end
end)

reaper.defer(main)