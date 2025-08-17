-- LogicKeyboard for Reaper
-- by Arthur Kowskii
-- free to use, please consider donation on gumroad !

-- Initial configuration
local octave_offset = -12  -- Offset to start at the C2 octave
local velocity = 100        -- Default velocity of MIDI notes (between 1 and 127)
local active_notes = {}     -- Table to track currently playing notes
local w_key_released = true -- State of the W key (true = released)
local x_key_released = true -- State of the X key (true = released)
local shift_pressed = false  -- State of the Shift key (true = pressed)
local mod_wheel_value = 0    -- Current value of the mod wheel
local mod_wheel_step = 10    -- Step size for smooth transition (doubled for faster transition)
local mod_wheel_target = 0   -- Target value for the mod wheel

-- Table of keys and their associated notes (in semitones from C3 = 60)
local key_to_note = {
    -- Base octave
    [0x51] = 60,  -- Q = C
    [0x5A] = 61,  -- Z = C#
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
    -- Upper octave
    [0x4B] = 72,  -- K = C
    [0x4F] = 73,  -- O = C#
    [0x4C] = 74,  -- L = D
    [0x50] = 75,  -- P = D#
    [0x4D] = 76,  -- M = E
    [0xC0] = 77,  -- ù = F (corrected)
    [0x2A] = 81,  -- * = A (corrected)
}

-- Key interception (blocking shortcuts in Reaper)
for key, _ in pairs(key_to_note) do
    reaper.JS_VKeys_Intercept(key, 1) -- Intercepts the key to block its use in Reaper
end

-- Also intercept the W, X, and Shift keys for octave shifting and mod wheel
reaper.JS_VKeys_Intercept(0x57, 1) -- W
reaper.JS_VKeys_Intercept(0x58, 1) -- X
reaper.JS_VKeys_Intercept(0x10, 1) -- Shift

-- Function to send a MIDI message
local function send_midi(note, is_note_on)
    local status = is_note_on and 0x90 or 0x80  -- Note on = 0x90, Note off = 0x80
    reaper.StuffMIDIMessage(0, status, note, velocity)
end

-- Function to send a Control Change message for the mod wheel
local function send_mod_wheel(value)
    reaper.StuffMIDIMessage(0, 0xB0, 1, value) -- Control Change for Mod Wheel (Controller 1)
end

-- Main function
local function main()
    local key_states = reaper.JS_VKeys_GetState(0) -- Retrieves the key states (256 keys max)

    -- Manage transposition with W and X keys
    local w_state = key_states:byte(0x57) ~= 0  -- 'W' key (octave -1)
    local x_state = key_states:byte(0x58) ~= 0  -- 'X' key (octave +1)
    local shift_state = key_states:byte(0x10) ~= 0  -- 'Shift' key (mod wheel)

    -- Detect octave changes
    local octave_changed = false
    local old_octave_offset = octave_offset

    -- W key to decrease the octave (only when the key is pressed and then released)
    if w_state and w_key_released then
        octave_offset = octave_offset - 12
        w_key_released = false
        octave_changed = true
    elseif not w_state then
        w_key_released = true
    end

    -- X key to increase the octave (only when the key is pressed and then released)
    if x_state and x_key_released then
        octave_offset = octave_offset + 12
        x_key_released = false
        octave_changed = true
    elseif not x_state then
        x_key_released = true
    end

    -- If the octave changed, stop all active notes and restart them at the new octave
    if octave_changed then
        local notes_to_restart = {}

        -- Stop all active notes with the old octave
        for note, _ in pairs(active_notes) do
            send_midi(note + old_octave_offset, false) -- Sends a "note off" message with the old octave
            notes_to_restart[note] = true -- Memorize notes to restart
        end

        -- Restart the notes with the new octave
        for note, _ in pairs(notes_to_restart) do
            send_midi(note + octave_offset, true) -- Sends a "note on" message with the new octave
        end
    end

    -- Manage mod wheel with Shift key
    if shift_state then
        mod_wheel_target = 127 -- Set target value to maximum
    else
        mod_wheel_target = 0 -- Set target value to minimum
    end

    -- Smooth transition for mod wheel
    if mod_wheel_value < mod_wheel_target then
        mod_wheel_value = math.min(mod_wheel_value + mod_wheel_step, mod_wheel_target)
    elseif mod_wheel_value > mod_wheel_target then
        mod_wheel_value = math.max(mod_wheel_value - mod_wheel_step, mod_wheel_target)
    end

    -- Send the current mod wheel value
    send_mod_wheel(mod_wheel_value)

    -- Loop through all defined keys
    for key, note in pairs(key_to_note) do
        local state = key_states:byte(key) -- Check the key state
        -- If the key is pressed and the note is not already playing
        if state and state ~= 0 and not active_notes[note] then
            send_midi(note + octave_offset, true)  -- Sends a "note on" message
            active_notes[note] = true             -- Marks the note as active
        end
        -- If the key is released and the note is active
        if (not state or state == 0) and active_notes[note] then
            send_midi(note + octave_offset, false) -- Sends a "note off" message
            active_notes[note] = nil               -- Removes the note from active ones
        end
    end

    -- Refresh the loop
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

    -- Also release the W, X, and Shift keys
    reaper.JS_VKeys_Intercept(0x57, -1) -- W
    reaper.JS_VKeys_Intercept(0x58, -1) -- X
    reaper.JS_VKeys_Intercept(0x10, -1) -- Shift
end

-- Check for the SWS extension and start the script
if not reaper.APIExists("JS_VKeys_GetState") then
    reaper.ShowMessageBox("The SWS extension is required for this script. Install SWS and JS_ReaScript API.", "Error", 0)
    return
end

-- For toolbar button animation
local _, _, section_id, command_id = reaper.get_action_context()

-- Set the button state to enabled
if command_id ~= 0 then
    reaper.SetToggleCommandState(section_id, command_id, 1) -- State 1 = enabled
    reaper.RefreshToolbar2(section_id, command_id)
end

-- Start the script and set up cleanup
reaper.atexit(function()
    -- Execute normal cleanup
    cleanup()

    -- Reset the button state to disabled
    if command_id ~= 0 then
        reaper.SetToggleCommandState(section_id, command_id, 0) -- State 0 = disabled
        reaper.RefreshToolbar2(section_id, command_id)
    end
end)

reaper.defer(main)