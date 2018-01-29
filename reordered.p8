pico-8 cartridge // http://www.pico-8.com
version 15
__lua__

-- title: reordered
-- version: 0.1
-- github page: https://github.com/hsandt/ggj2018-transmission
-- copyright: long nguyen huu
-- see license for license details


-- terminology

-- position: (x,y) float position
-- location: (i,j) integer position on the 8x6 map of 16x16 tiles
-- precise location: (k,l) integer position on the 16x12 map of 8x8 tiles
-- (precise, sub-) sprite: 8x8 sprite
-- big sprite: 16x16 sprite
-- representative sprite: 8x8 top-left sprite of the big sprite containing a 8x8 sprite

-- flags

-- flag 0: is static (set on all sub-sprites so we can draw layer with map, but logic only uses big sprite flag)
-- flag 1: is toggable (set on all sub-sprites in case we want to draw layer with map or check flag quickly without getting the representative sub-tile)
-- flag 2: should be check for collision (set on all relevant sub-sprites)

static_flag_id = 0
toggable_flag_id = 1
collision_flag_id = 2

-- sprite big id
restart_big_id = 1
exit_big_id = 2
emitter_big_id = 8
receiver_big_id = 9
forwarder_up_big_id = 4
mirror_horizontal_big_id = 16

-- a sprite just below another in the big spritesheet is its toggable variant (if applicable)
toggable_offset = 8
toggable_forwarder_up_big_id = forwarder_up_big_id+toggable_offset
toggable_mirror_horizontal_big_id = mirror_horizontal_big_id+toggable_offset

-- constants
fixed_delta_time = 1/30

-- ui parameters
topbar_height = 16
title_y = 2
level_id_x = 90
level_id_y = 2
start_letters_start_x = 2
start_letters_start_y = 2
goal_letters_start_x = 2
goal_letters_start_y = 9
received_letters_start_x = 51
received_letters_start_y = 9
restart_icon_x = 7*16
exit_icon_x = 7*16
bottombar_height = 16

-- dimensions
level_width = 8
level_height = 6
deadzone_margin = 0

-- text
title = "-reordered-"
fail_message_wrong_letter_sequence = "letters are out-of-order!\ntry again!"
fail_message_too_short = "some letters are missing!\ntry again!"
fail_message_too_long = "there are too many letters!\ntry again!"
success_message = "you transmitted the word!\nlevel completed!"
finish_message = "last level cleared!\ncongratulations!"

-- gameplay parameters
moving_letter_initial_speed = 50.0  -- original 20.0

-- colors
black = 0
dark_blue = 1
dark_purple = 2
dark_green = 3
brown = 4
dark_gray = 5
light_gray = 6
white = 7
red = 8
orange = 9
yellow = 10
green = 11
blue = 12
indigo = 13
pink = 14
peach = 15

-- gameplay
untoggable_color = orange
toggable_color = green
gamespace_bgcolor = white
active_color = green
inactive_color = dark_gray

-- ui
topbar_bgcolor = black
title_color = white
level_id_color = white
start_letter_color = light_gray
goal_letter_color = orange
received_letter_color = red
remaining_letter_color = indigo
moving_letter_color = red
bottombar_bgcolor = black
bottom_message_color = white


-- enums
directions = {
 up = 1,
 down = 2,
 left = 3,
 right = 4
}

directions_sequence = {
 directions.up,
 directions.down,
 directions.left,
 directions.right
}

directions_vector = {
 {x = 0.0, y = -1.0},
 {x = 0.0, y = 1.0},
 {x = -1.0, y = 0.0},
 {x = 1.0, y = 0.0}
}

mirror_directions = {
 horizontal = 1,
 vertical = 2,
 slash = 3,
 antislash = 4
}

mirror_directions_sequence = {
 mirror_directions.horizontal, -- like -
 mirror_directions.vertical,   -- like |
 mirror_directions.slash,      -- like / but at 45 degrees
 mirror_directions.antislash   -- like \ but at 45 degrees
}

-- mirror normals (can be not unit, in any sense)
mirror_directions_normal = {
 {x = 0.0, y = 1.0},
 {x = 1.0, y = 0.0},
 {x = 1.0, y = 1.0},  -- convention y down!
 {x = 1.0, y = -1.0}  -- convention y down!
}

effector_types = {
 forwarder = "forwarder",
 mirror = "mirror"
}

fail_causes = {
 wrong_letter_sequence = 1,
 too_short = 2,
 too_long = 3
}

-- data

levels_data = {
 {
  id = 3,
  start_letters = {"1", "2", "3", "4"},
  goal_letters = {"4", "3", "2", "1"},
  map_index = 1,
  bottom_message = "press ❎ to emit letters\nclick to toggle central arrow"
 },
 {
  id = 1,
  start_letters = {"b", "g", "i"},
  goal_letters = {"b", "i", "g"},
  map_index = 0,
  bottom_message = "press ❎ to emit letters\nclick to toggle central arrow"
 },
 {
  id = 2,
  start_letters = {"a", "w", "e", "v"},
  goal_letters = {"w", "a", "v", "e"},
  map_index = 0,
  bottom_message = "try a longer word now!"
 }
}


-- data cache

current_level_data_cache = {
 emitter_location = nil
}


-- state variables

-- input info
input_info = {
 mouse_primary = {
  down = false,
  pressed = false,
  released = false
 },
 mouse_secondary = {
  down = false,
  pressed = false,
  released = false
 }
}

-- the current coroutines
coroutines = {}

-- index of the curent level
current_level = 0

-- reference to the current level data in levels data
current_level_data = nil

-- game state (start, playing, failed, succeeded)
current_gamestate = "start"

-- is the game in a transition? (between levels or menus)
is_in_transition = false

-- sequence of letters remaining to emit from the emitter
remaining_letters_to_emit = {}

-- sequence of letters already received by the receiver
received_letters = {}

-- letters already emitted but not yet received
moving_letters = {}

-- has the player started emitting letters since the last setup/reset?
has_started_emission = false

-- map of all dynamic tiles, by linear index (unwrapping big tile coordinates in 1d)
toggable_actors_linear_map = {}

-- ui: hint message at the bottom
bottom_message = ""


-- helpers

-- clear a table
function clear_table(t)
 for k in pairs(t) do
  t[k] = nil
 end
end

-- yield as many times as needed so that, assuming you coresume the calling
-- coroutine each frame at 30 fps, the coroutine resumes after [time] seconds
function yield_delay(time)
 local nb_frames = 30*time
 for frame=1,nb_frames do  -- still works if nb_frames is not integer (~flr(nb_frames))
  yield()
 end
end

-- create and register coroutine
function add_coroutine(async_function)
 coroutine = cocreate(async_function)
 add(coroutines, coroutine)
end


-- conversion helpers

-- convert 16x16 spritesheet coordinates to 8x8 sprite id
-- [non-surjective]
function indices_to_spritesheet_sprite_id(i, j)
 return 32*j+2*i
end

-- convert 8x8 sprite id to 16x16 spritesheet coordinates
-- [non-injective]
function sprite_id_to_spritesheet_indices(sprite_id)
-- %16 instead of %32 allows support for other sub-sprite than the top-left (representative)
 return {i = flr((sprite_id%16)/2), j = flr(sprite_id/32)}
end

-- convert 8x8 sprite id to 16x16 fictive sprite id (with pages of 8 big sprites per line)
-- [non-injective]
function sprite_id_to_big_sprite_id(sprite_id)
 indices = sprite_id_to_spritesheet_indices(sprite_id)
 return 8*indices.j+indices.i
end

-- convert 16x16 fictive sprite id to 8x8 sprite id (with pages of 8 big sprites per line)
-- [non-surjective]
function big_sprite_id_to_sprite_id(big_sprite_id)
 return 32*flr(big_sprite_id/8)+2*(big_sprite_id%8)
end

-- return the (x,y) position corresponding to an (i,j) location for 16x16 tiles
-- [non-surjective]
function location_to_position(location)
 return {x = 16*location.i, y = 16*location.j}
end

-- return the (i,j) location corresponding to an (x,y) position for 16x16 tiles
-- [non-injective]
function position_to_location(position)
 return {i = flr(position.x/16), j = flr(position.y/16)}
end

-- return the (k,l) precise location corresponding to an (x,y) position for 8x8 tiles
-- [non-injective]
function position_to_precise_location(position)
 return {k = flr(position.x/8), l = flr(position.y/8)}
end

-- return the (i,j) location corresponding to a (k,l) precise location for 8x8->16x16 tiles
-- [non-injective]
function precise_location_to_location(precise_location)
 return {i = flr(precise_location.k/2), j = flr(precise_location.l/2)}
end

-- return the (k,l) previse location of the top-left sub-tile of the big tile containing a given sub-tile
-- [non-injective]
function to_representative_location(precise_location)
 local location = precise_location_to_location(precise_location)
 return {k = 2*location.i, l = 2*location.j}
end

-- convert map (i,j) location to a linear index, starting at 0, incremented by moving to
-- the right then down to the next line, etc.
-- [bijective]
function location_to_map_linear_index(location)
 return level_width*location.j+location.i
end

-- convert map linear index to (i,j) location
-- [bijective]
function map_linear_index_to_location(linear_index)
 return {i = linear_index%level_width, j = flr(linear_index/level_width)}
end

-- convert screen position to gamespace location
function screen_position_to_gamespace_location(screen_position)
 -- subtract top bar height
 local gamespace_position = {x = screen_position.x, y = screen_position.y-topbar_height}
 return position_to_location(gamespace_position)
end


-- string helpers

function join(sequence, separator)
 local final_string = ""
 local i = 0  -- increment at beginning of loop, so start at 1
 for v in all(sequence) do  -- use all to guarantee order
  i += 1
  final_string = final_string..tostr(v)
  if separator and i < #sequence then
   final_string = final_string..separator
  end
 end
 return final_string
end


-- input helpers

mouse_devkit_address = 0x5f2d

function toggle_mouse(active)
 value = active and 1 or 0
 poke(mouse_devkit_address, value)
end

function get_mouse_screen_position()
 assert(peek(mouse_devkit_address) == 1)
 return {x = stat(32), y = stat(33)}
end

function get_mouse_button_bitmask()
 assert(peek(mouse_devkit_address) == 1)
 return stat(34)
end

-- return true is primary button is currently down
function get_mouse_primary()
 return band(get_mouse_button_bitmask(), 0x1) == 0x1
end

-- return true is secondary button is currently down
function get_mouse_secondary()
 return band(get_mouse_button_bitmask(), 0x2) == 0x2
end

-- return true if button is down according to system
-- for usage in process_input
function query_down(button_name)
 if button_name == "mouse_primary" then
  return get_mouse_primary()
 elseif button_name == "mouse_secondary" then
  return get_mouse_secondary()
 else
  printh("error: unknown button name: "..button_name)
 end
end

-- return true if button is down according to the input manager
-- for usage after process_input
function is_down(button_name)
 return input_info[button_name].down
end

-- return true if button has just been pressed according to the input manager
-- for usage after process_input
function is_pressed(button_name)
 return input_info[button_name].pressed
end

-- return true if button has just been released according to the input manager
-- for usage after process_input
function is_released(button_name)
 return input_info[button_name].released
end


-- math helpers

v8 = {x = 8, y = 8}
v16 = {x = 16, y = 16}

function vector_to_string(v)
 return "("..v.x..","..v.y..")"
end

function vector_length(v)
 return sqrt(v.x^2+v.y^2)
end

function vector_sqrlength(v)
 return v.x^2+v.y^2
end

function vector_oppose(v)
 return {x = -v.x, y = -v.y}
end

function vector_add(v, w)
 return {x = v.x+w.x, y = v.y+w.y}
end

function vector_sub(v, w)
 return {x = v.x-w.x, y = v.y-w.y}
end

function dot(v, w)
 return v.x*w.x+v.y*w.y
end

function project_parallel(v, w)
 local projected_abs = dot(v,w)/vector_sqrlength(w)
 return {x = projected_abs*w.x, y = projected_abs*w.y}
end

function project_ortho(v, w)
 local projected_parallel = project_parallel(v,w)
 return vector_sub(v,projected_parallel)
end

function reflect(v,w)
 local projected_parallel = project_parallel(v,w)
 local projected_ortho = vector_sub(v,projected_parallel)
 return vector_sub(projected_parallel,projected_ortho)
end

-- draw helpers

-- draw "big" sprite 16x16 of big sprite id at coords (x,y), optionally flipped in x/y
function bigspr(big_sprite_id, x, y, flip_x, flip_y)
 spr(big_sprite_id_to_sprite_id(big_sprite_id), x, y, 2, 2, flip_x, flip_y)
end

-- draw "big" sprite 16x16 of big sprite id at location (i,j), optionally flipped in x/y
function bigtile(big_sprite_id, location, active, flip_x, flip_y)
 -- default (nil is not false!!)
 if active == nil then
  active = true
 end

 local sprite_id = big_sprite_id_to_sprite_id(big_sprite_id)
 local position = location_to_position(location)

 printh("bigtile: "..big_sprite_id)
 if not active then
  printh("not active")
  -- inactive objects switch palette to inactive
  pal(active_color, inactive_color)
 end

 spr(sprite_id, position.x, position.y, 2, 2, flip_x, flip_y)

 if not active then
  pal()
 end
end


-- factory

function make_toggable(big_sprite_id)
 local effector_type = nil
 local direction = nil
 if big_sprite_id >= toggable_forwarder_up_big_id and big_sprite_id < toggable_forwarder_up_big_id+4 then
  effector_type = effector_types.forwarder
  direction = directions_sequence[big_sprite_id-(toggable_forwarder_up_big_id)+1]  -- sequence starts at 1
 elseif big_sprite_id >= mirror_horizontal_big_id+toggable_offset and big_sprite_id < mirror_horizontal_big_id+toggable_offset+4 then
  effector_type = effector_types.mirror
  direction = mirror_directions_sequence[big_sprite_id-(toggable_mirror_horizontal_big_id)+1]  -- sequence starts at 1
 end

 if not effector_type then
  printh("error: unknown effector type")
  return nil
 end

 local toggable_actor = {
  big_sprite_id = big_sprite_id,
  effector_type = effector_type,
  direction = direction,
  active = true
 }
 return toggable_actor
end

function make_moving_letter(letter, x, y, vx, vy)
 local moving_letter = {
  letter = letter,
  position = {
   x = x,
   y = y
  },
  velocity = {
   x = vx,
   y = vy
  },
  active = true
 }
 return moving_letter
end


-- game loop

function _init()
 run_unit_tests()

 -- activate mouse devkit (for mouse input support)
 toggle_mouse(true)

 load_level(1)
end

function _update()
 process_input()
 handle_input()

 if current_gamestate == "playing" then
  update_moving_letters()
 end

 update_coroutines()
end

function _draw()
 if current_gamestate != "start" then
  draw_gamespace()
  draw_topbar()
  draw_bottombar()
 end
 draw_cursor()
end


-- input

function process_input()
 for button_name, button_state in pairs(input_info) do
  -- release any previous pressed/release
  button_state.pressed = false
  button_state.released = false

  -- check previous mouse button state to decide if button has just been pressed
  -- also update the mouse button current state
  if not button_state.down and query_down(button_name) then
    button_state.down = true
    button_state.pressed = true
  elseif button_state.down and not query_down(button_name) then
   button_state.down = false
   button_state.released = true
  end
 end
end

function handle_input()
 if current_gamestate == "playing" then
  -- emission
  if not has_started_emission and btnp(❎) then
   start_emit_letters()
  end

  -- toggle
  if is_pressed("mouse_primary") then
   local click_position = get_mouse_screen_position()
   if click_position.y < topbar_height then
    -- click on topbar
    if click_position.x >= restart_icon_x and click_position.x < restart_icon_x+16 then
     reload_current_level_immediate()
    elseif click_position.x >= exit_icon_x then
     printh("exit (not implemented)")
    end
   elseif click_position.y >= topbar_height+16*level_height then
    -- click on bottombar
     printh("click on bottombar (does nothing)")
   else
    local location = screen_position_to_gamespace_location(click_position)
    local toggable_actor = get_toggable_actor_at_location(location)
    if toggable_actor then
     toggle(toggable_actor)
    end
   end -- click in different areas
  end -- primary
 end -- playing
end


-- game flow

-- setup level state by level index
function setup_current_level()
 printh("setup_current_level: "..current_level)
 current_level_data = levels_data[current_level]
 assert(current_level_data)

 -- find emitter and toggable elements (will set emitter_location and toggable_actors_linear_map)
 register_dynamic_tiles(current_level_data.map_index)
 if not current_level_data_cache.emitter_location then
  printh("error: emitter could not be found on this map")
 end

 -- setup game state
 current_gamestate = "playing"

 -- stop locking transitions
 is_in_transition = false

 -- copy start letters sequence
 clear_table(remaining_letters_to_emit)
 for letter in all(current_level_data.start_letters) do
  add(remaining_letters_to_emit, letter)
 end

 -- no received nor moving letters at the beginning
 clear_table(received_letters)
 clear_table(moving_letters)

 -- stop and clear the emit coroutine if needed (coroutines must be resumed to continue;
 -- if they aren't and references to them disappear, they will be gc-ed, effectively being stopped)
 clear_table(coroutines)
 has_started_emission = false

 -- ui
 bottom_message = current_level_data.bottom_message
end

function load_level(level_index)
 current_level = level_index
 setup_current_level()
end

function fail_current_level(fail_cause)
 current_gamestate = "failed"

 if fail_cause == fail_causes.wrong_letter_sequence then
  bottom_message = fail_message_wrong_letter_sequence
 elseif fail_cause == fail_causes.too_short then
  bottom_message = fail_message_too_short
 elseif fail_cause == fail_causes.too_long then
  bottom_message = fail_message_too_long
 else
  bottom_message = "failed for unknown reason"
 end

 if not is_in_transition then
  is_in_transition = true
  add_coroutine(reload_current_level_async)
 end
end

function succeed_current_level()
 current_gamestate = "succeeded"
 bottom_message = success_message
 if not is_in_transition then
  is_in_transition = true
  if current_level == #levels_data then
   -- last level succeeded!
   add_coroutine(finish_game_async)
  else
   add_coroutine(load_next_level_async)
  end
 end
end

function reload_current_level_immediate()
 if not is_in_transition then
  is_in_transition = true
  setup_current_level()
 end
end

function reload_current_level_async()
 yield_delay(2.0)
 setup_current_level()
end

function load_next_level_async()
 assert(current_level < #levels_data)
 yield_delay(2.0)
 load_level(current_level + 1)
end

function finish_game_async()
 yield_delay(2.0)
 bottom_message = finish_message
 yield_delay(2.0)
 load_level(1)
end

-- map

-- return the location of dynamic tiles (also the emitter for letter display)
function register_dynamic_tiles(map_index)
 -- reset any previous data to make sure they don't stack when loading a new level
 current_level_data_cache.emitter_location = nil
 clear_table(toggable_actors_linear_map)

 local celx, cely = get_map_topleft(map_index)

 for i=0,level_width-1 do
  for j=0,level_height-1 do
   local sprite_id = mget(celx+2*i,cely+2*j)  -- map uses precise location, hence double
   local big_sprite_id = sprite_id_to_big_sprite_id(sprite_id)
   if big_sprite_id == emitter_big_id then
    current_level_data_cache.emitter_location = {i = i, j = j}
   elseif is_toggable(big_sprite_id) then
    local linear_index = location_to_map_linear_index({i = i, j = j})
    local toggable_actor = make_toggable(big_sprite_id)
    if toggable_actor then
     toggable_actors_linear_map[linear_index] = toggable_actor
     printh("added toggable "..toggable_actor.effector_type.." at "..linear_index)
    else
     printh("->error: could not make toggable actor")
    end
   end
  end
 end
end

function is_toggable(big_sprite_id)
 local sprite_id = big_sprite_id_to_sprite_id(big_sprite_id)
 return fget(sprite_id, toggable_flag_id)
end

function get_toggable_actor_at_location(location)
 return toggable_actors_linear_map[location_to_map_linear_index(location)]
end


-- gameplay

-- start and register coroutine to emit letters at regular intervals from now on
function start_emit_letters()
 local emit_coroutine = cocreate(function()
   while #remaining_letters_to_emit > 0 do
    emit_next_letter()
    yield_delay(1.0)
   end
  end)
 has_started_emission = true
 add(coroutines, emit_coroutine)
end

-- emit the next letter from the emitter
function emit_next_letter()
 -- get next letter to emit
 local next_letter = remaining_letters_to_emit[1]

 -- create and emit letter with default velocity
 local emit_position = location_to_position(current_level_data_cache.emitter_location)
 local moving_letter = make_moving_letter(next_letter,emit_position.x+8,emit_position.y+10,0,-moving_letter_initial_speed)

 -- remove letter from sequence of remaining letters
 del(remaining_letters_to_emit,next_letter)
 -- add letter to sequence of moving letters
 add(moving_letters, moving_letter)
end

-- update emit coroutine if active, remove if dead
function update_coroutines()
 for coroutine in all(coroutines) do
  local status = costatus(coroutine)
  if status == "suspended" then
   assert(coresume(coroutine))
  elseif status == "dead" then
   coroutine = nil
  else  -- status == "running"
   printh("warning: coroutine should not be running outside its body")
  end
 end
end

-- toggle a toggable actor
function toggle(toggable_actor)
 printh("toggle actor: "..toggable_actor.effector_type)
 toggable_actor.active = not toggable_actor.active
end


-- physics

function update_moving_letters()
 for moving_letter in all(moving_letters) do
  update_position(moving_letter)
  check_out_of_bounds(moving_letter)
  -- the previous check may have killed the moving letter
  if moving_letter.active then
   check_collision(moving_letter)
  end
 end
end

-- apply current velocity to moving letter
function update_position(moving_letter)
 moving_letter.position.x += moving_letter.velocity.x*fixed_delta_time
 moving_letter.position.y += moving_letter.velocity.y*fixed_delta_time
end

-- check if moving letter entered a tile with a special effect, and apply it if so
function check_collision(moving_letter)
 local celx, cely = get_map_topleft(current_level_data.map_index)

 -- since some object colliders occupy precise tiles (e.g. the mirror), we need precise location
 -- to check for collision flag
 local precise_location = position_to_precise_location(moving_letter.position)
 local precise_sprite_id = mget(celx+precise_location.k,cely+precise_location.l)
 if precise_sprite_id != 0 then
  local collision_flag = fget(precise_sprite_id,collision_flag_id)
  if collision_flag then
   -- for colliding sprite id, we use the location of the big tile since it's easier to compare
   -- with just the top-left tile id than with all 4 sub-tile ids (it's the same 1 time out of 4)
   local big_sprite_id = sprite_id_to_big_sprite_id(precise_sprite_id)
   local toggable_flag = fget(precise_sprite_id,toggable_flag_id)  -- caution: this requires to set toggable flag on all sub-tiles
   local location = precise_location_to_location(precise_location)

   if big_sprite_id == receiver_big_id then
    receive(moving_letter)
   else
    local out_info = {}
    if check_if_forwarder(big_sprite_id, toggable_flag, location, out_info) then
     forward(moving_letter, out_info.direction)
    elseif check_if_mirror(big_sprite_id, toggable_flag, location, out_info) then
     mirror(moving_letter, out_info.direction, location)
    else
     printh("error: unsupported collider: (big_sprite_id: "..big_sprite_id..", toggable_flag: "..(toggable_flag and "true" or "false")..", location: "..location.i..","..location.j..")")
    end
   end
  end
 end
end

-- destroy letters completely outside the screen
function check_out_of_bounds(moving_letter)
 -- we want to check if the letter center is outside the screen, + a small offset
 -- to make sure it is not still rendered on the screen edges, so we check its
 -- exact position rather than the rounded location
 if moving_letter.position.x < 0-deadzone_margin or
   moving_letter.position.x >= 16*level_width+deadzone_margin or
   moving_letter.position.y < 0-deadzone_margin or
   moving_letter.position.y >= 16*level_height+deadzone_margin then
  kill_letter(moving_letter)
 end
end

function kill_letter(moving_letter)
 printh("kill_letter: "..moving_letter.letter)
 moving_letter.active = false  -- flag so we know it's dead until it's garbage collected
 del(moving_letters, moving_letter)
 check_success_and_failure()
end

-- confirm reception of moving letter
function receive(moving_letter)
 add(received_letters, moving_letter.letter)
 del(moving_letters, moving_letter)
 check_success_and_failure()
end

function check_success_and_failure()
 -- first, check if all letters have been sent, as some extra letters at the end
 -- may invalidate an otherwise good chain, and even in case of early failure we want
 -- to let the player witness what happens in the long run to improve next time
 if #remaining_letters_to_emit > 0 or #moving_letters > 0 then
  -- some letters still on the move, go on
  return
 end

 -- second, check if we received enough letters to pretend to have reached the goal
 if #received_letters == #current_level_data.goal_letters then
  -- then check if the letters are correctly ordered
  for i,received_letter in pairs(received_letters) do
   if received_letter != current_level_data.goal_letters[i] then
    -- some letters are wrong; continue playing to let player experiment a bit further
    fail_current_level(fail_causes.wrong_letter_sequence)
    return
   end
  end
  -- all characters are equal
  succeed_current_level()
 elseif #received_letters < #current_level_data.goal_letters then
  -- some letters were lost (or not duplicated enough)
  fail_current_level(fail_causes.too_short)
 else
  -- too many duplications (or not lost enough)
  fail_current_level(fail_causes.too_long)
 end
end

-- return true if the big sprite id represents an effector of a given type,
-- that is static or active
-- out_info contains the effector direction if return true
-- we also pass the effector_directions_sequence, although not required since
-- they all come back to values 1, 2, 3, 4 in the end
function check_if_effector(effector_type, first_big_sprite_id, effector_directions_sequence, big_sprite_id, toggable_flag, location, out_info)
 if not toggable_flag then
  -- check for static effector of this type
  local offset = big_sprite_id - first_big_sprite_id
  if offset >= 0 and offset < 4 then
   out_info.direction = effector_directions_sequence[offset+1]  -- sequence index starts at 1
   return true
  end
 else
  -- check for toggable effector of this type
  local toggable_actor = get_toggable_actor_at_location(location)
  assert(toggable_actor)
  if toggable_actor.effector_type == effector_type and toggable_actor.active then
   out_info.direction = toggable_actor.direction
   return true
  end
 end
 return false
end

-- return true if the big sprite id represents a forwarder that is static or active
-- out_info contains the forwarder direction if return true
function check_if_forwarder(big_sprite_id, toggable_flag, location, out_info)
 return check_if_effector(effector_types.forwarder, forwarder_up_big_id, directions_sequence,
  big_sprite_id, toggable_flag, location, out_info)
end

-- return true if the big sprite id represents a mirror that is static or active
-- out_info contains the mirror direction if return true
function check_if_mirror(big_sprite_id, toggable_flag, location, out_info)
 return check_if_effector(effector_types.mirror, mirror_horizontal_big_id, mirror_directions_sequence,
  big_sprite_id, toggable_flag, location, out_info)
end

-- change the velocity of the moving letter toward a new direction, preserves speed
function forward(moving_letter, direction)
 local speed = sqrt(moving_letter.velocity.x^2+moving_letter.velocity.y^2)
 local direction_vector = directions_vector[direction]
 moving_letter.velocity.x = speed*direction_vector.x
 moving_letter.velocity.y = speed*direction_vector.y
end

-- mirror the velocity of the moving letter orthogonally to a direction, preserves speed
function mirror(moving_letter, direction, location)
 -- check if letter is moving toward the mirror, or has already been reflected and is going away
 -- for 45 degree motion, the test below is enough to decide if letter is ahead toward mirror
 -- for more precision, we'd need to check for future trajectory with mirror segment collision
 local mirror_center = vector_add(location_to_position(location), v8)
 local relative_position = vector_sub(moving_letter.position,mirror_center)
 local normal = mirror_directions_normal[direction]  -- normal doesn't need to be unit, reflect will normalize
 local position_side_dot = dot(relative_position,normal)  -- normal convention doesn't matter, it's to compare
 local velocity_side_dot = dot(moving_letter.velocity,normal)
 if (position_side_dot < 0 and velocity_side_dot > 0) or
   (position_side_dot > 0 and velocity_side_dot < 0) then
  -- caution: a wave reflection bounces on the tangent, so we need the opposite of the reflected vector!
  local mirrored_velocity = vector_oppose(reflect(moving_letter.velocity,normal))
  moving_letter.velocity = mirrored_velocity
 end
end

-- render

function draw_gamespace()
 -- camera offset
 camera(0,-topbar_height)

 -- background
 rectfill(0,0,16*level_width-1,16*level_height-1,gamespace_bgcolor)

 -- map (2x everything to get 8x8 -> 16x16 tiles)
 draw_level_map(current_level_data.map_index)
 draw_toggable_actors()

 -- letters
 draw_remaining_letters()
 draw_moving_letters()
end

-- return the topleft (celx, cely) of a map by index
function get_map_topleft(map_index)
 local nb_level_maps_per_bigmap_line = flr(128/(2*level_width))
 local celx = 2*level_width*(map_index%nb_level_maps_per_bigmap_line)
 local cely = 2*level_height*flr(map_index/nb_level_maps_per_bigmap_line)
 return celx, cely
end

function draw_level_map(map_index)
 -- retrieve location of level map in pico-8 map "bigmap" in memory
 -- which is 128x32 8x8 it 64x16 16x16
 local celx, cely = get_map_topleft(map_index)
 map(celx,cely,0,0,level_width*2,level_height*2, 2^static_flag_id)
end

function draw_toggable_actors()
 for linear_index,toggable_actor in pairs(toggable_actors_linear_map) do
  local location = map_linear_index_to_location(linear_index)
  bigtile(toggable_actor.big_sprite_id,location,toggable_actor.active)
 end
end

function draw_remaining_letters()
 local emitter_location = current_level_data_cache.emitter_location
 if not emitter_location then
  printh("error: emitter location was not found, cannot draw remaining letters")
  return
 end

 for index=1,#remaining_letters_to_emit do
  remaining_letter = remaining_letters_to_emit[index]
  print(remaining_letter,16*(current_level_data_cache.emitter_location.i+1)+6*(index-1)+3,16*current_level_data_cache.emitter_location.j+6,remaining_letter_color)
 end
end

function draw_moving_letters()
 for index=1,#moving_letters do
  moving_letter = moving_letters[index]
  -- print the letter a bit offset so the character is centered on its position
  print(moving_letter.letter,moving_letter.position.x-2,moving_letter.position.y-3,moving_letter_color)
 end
end

function draw_topbar()
 -- camera offset: top
 camera(0,0)

 -- background
 rectfill(0,0,127,topbar_height-1,topbar_bgcolor)

 draw_title()
 draw_level_id()
 draw_start_letters()
 draw_goal_letters()
 draw_received_letters()

 -- restart
 bigspr(restart_big_id,restart_icon_x,0)
 -- exit (not implemented until there is a title menu)
 -- bigspr(exit_big_id,exit_icon_x,0)
end

function draw_title()
 -- center x
 print(title,64-#title*2,title_y,title_color)
end

function draw_level_id()
 print("lv"..current_level_data.id,level_id_x,level_id_y,level_id_color)
end

function draw_start_letters()
 print("start:"..join(current_level_data.start_letters),start_letters_start_x,start_letters_start_y,start_letter_color)
end

function draw_goal_letters()
 print("goal :"..join(current_level_data.goal_letters),goal_letters_start_x,goal_letters_start_y,goal_letter_color)
end

function draw_received_letters()
 print(join(received_letters),received_letters_start_x,received_letters_start_y,received_letter_color)
end

function draw_bottombar()
 -- camera offset: bottom
 camera(0,-(topbar_height+16*level_height))

 -- background
 rectfill(0,0,127,bottombar_height-1,bottombar_bgcolor)

 draw_bottom_message()
end

function draw_bottom_message()
 if #bottom_message > 0 then
  print(bottom_message, 3, 2, white)
 end
end

function draw_cursor()
-- camera offset: origin
camera(0,0)

 local cursor_x = stat(32)
 local cursor_y = stat(33)
 spr(6,cursor_x,cursor_y)
end


-- unit tests

function run_unit_tests()
 assert(indices_to_spritesheet_sprite_id(0,0) == 0)
 assert(indices_to_spritesheet_sprite_id(1,0) == 2)
 assert(indices_to_spritesheet_sprite_id(7,0) == 14)
 assert(indices_to_spritesheet_sprite_id(0,1) == 32)
 assert(indices_to_spritesheet_sprite_id(1,1) == 34)
 assert(indices_to_spritesheet_sprite_id(7,1) == 46)

 local indices
 indices = sprite_id_to_spritesheet_indices(0)
 assert(indices.i == 0 and indices.j == 0)
 indices = sprite_id_to_spritesheet_indices(1)
 assert(indices.i == 0 and indices.j == 0, indices.i)
 indices = sprite_id_to_spritesheet_indices(2)
 assert(indices.i == 1 and indices.j == 0)
 indices = sprite_id_to_spritesheet_indices(3)
 assert(indices.i == 1 and indices.j == 0)
 indices = sprite_id_to_spritesheet_indices(14)
 assert(indices.i == 7 and indices.j == 0)
 indices = sprite_id_to_spritesheet_indices(15)
 assert(indices.i == 7 and indices.j == 0)
 indices = sprite_id_to_spritesheet_indices(16)
 assert(indices.i == 0 and indices.j == 0)
 indices = sprite_id_to_spritesheet_indices(17)
 assert(indices.i == 0 and indices.j == 0)
 indices = sprite_id_to_spritesheet_indices(18)
 assert(indices.i == 1 and indices.j == 0)
 indices = sprite_id_to_spritesheet_indices(30)
 assert(indices.i == 7 and indices.j == 0)
 indices = sprite_id_to_spritesheet_indices(31)
 assert(indices.i == 7 and indices.j == 0)
 indices = sprite_id_to_spritesheet_indices(32)
 assert(indices.i == 0 and indices.j == 1)
 indices = sprite_id_to_spritesheet_indices(33)
 assert(indices.i == 0 and indices.j == 1)
 indices = sprite_id_to_spritesheet_indices(34)
 assert(indices.i == 1 and indices.j == 1)
 indices = sprite_id_to_spritesheet_indices(35)
 assert(indices.i == 1 and indices.j == 1)
 indices = sprite_id_to_spritesheet_indices(46)
 assert(indices.i == 7 and indices.j == 1)
 indices = sprite_id_to_spritesheet_indices(47)
 assert(indices.i == 7 and indices.j == 1)
 indices = sprite_id_to_spritesheet_indices(62)
 assert(indices.i == 7 and indices.j == 1)
 indices = sprite_id_to_spritesheet_indices(63)
 assert(indices.i == 7 and indices.j == 1)

 assert(sprite_id_to_big_sprite_id(0) == 0)
 assert(sprite_id_to_big_sprite_id(1) == 0)
 assert(sprite_id_to_big_sprite_id(2) == 1)
 assert(sprite_id_to_big_sprite_id(3) == 1)
 assert(sprite_id_to_big_sprite_id(14) == 7)
 assert(sprite_id_to_big_sprite_id(15) == 7)
 assert(sprite_id_to_big_sprite_id(16) == 0)
 assert(sprite_id_to_big_sprite_id(17) == 0)
 assert(sprite_id_to_big_sprite_id(18) == 1)
 assert(sprite_id_to_big_sprite_id(19) == 1)
 assert(sprite_id_to_big_sprite_id(30) == 7)
 assert(sprite_id_to_big_sprite_id(31) == 7)
 assert(sprite_id_to_big_sprite_id(32) == 8)
 assert(sprite_id_to_big_sprite_id(33) == 8)
 assert(sprite_id_to_big_sprite_id(62) == 15)
 assert(sprite_id_to_big_sprite_id(63) == 15)

 assert(location_to_map_linear_index({i = 0, j = 0}) == 0)
 assert(location_to_map_linear_index({i = 1, j = 0}) == 1)
 assert(location_to_map_linear_index({i = 7, j = 0}) == 7)
 assert(location_to_map_linear_index({i = 0, j = 1}) == 8)
 assert(location_to_map_linear_index({i = 1, j = 1}) == 9)
 assert(location_to_map_linear_index({i = 7, j = 1}) == 15)

 location = map_linear_index_to_location(0)
 assert(location.i == 0 and location.j == 0)
 location = map_linear_index_to_location(1)
 assert(location.i == 1 and location.j == 0)
 location = map_linear_index_to_location(7)
 assert(location.i == 7 and location.j == 0)
 location = map_linear_index_to_location(8)
 assert(location.i == 0 and location.j == 1)
 location = map_linear_index_to_location(9)
 assert(location.i == 1 and location.j == 1)
 location = map_linear_index_to_location(15)
 assert(location.i == 7 and location.j == 1)

 -- reciprocity
 assert(location_to_map_linear_index(map_linear_index_to_location(23)) == 23)
 assert(location_to_map_linear_index(map_linear_index_to_location(36)) == 36)
 location = map_linear_index_to_location(location_to_map_linear_index({i = 3, j = 5}))
 assert(location.i == 3 and location.j == 5)
 location = map_linear_index_to_location(location_to_map_linear_index({i = 7, j = 2}))
 assert(location.i == 7 and location.j == 2)

 local v = {x = 1, y = 1}
 local w = {x = 0, y = -1}
 assert(vector_length(v)==sqrt(2))
 assert(vector_sqrlength(v)==2)
 local x = vector_add(v,w)
 assert(x.x==1 and x.y==0)
 x = vector_sub(v,w)
 assert(x.x==1 and x.y==2)
 assert(dot(v,w)==-1)
 x = project_parallel(v,w)
 assert(x.x==0 and x.y==1)
 x = project_ortho(v,w)
 assert(x.x==1 and x.y==0)
 x = reflect(v,w)
 assert(x.x==-1 and x.y==1)
 x = reflect(w,v)
 assert(x.x==-1 and x.y==0)
end

__gfx__
00000000000000000000000000000000000000000000000001110000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000001dd11000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000222000000000000044444444401ddd1100000000000000000990000000000000099900000000000009900000000000000090000000
0000000000000000000022000220000000000040040000401dddd110000000000000009999000000000000099900000000000099900000000000000099000000
0000000000000000000200000002000000000040040000401ddddd11000000000000099999900000000000099900000000000999900000000000000099900000
0000000000000000002000000000200000000240040000401dd11dd1000000000000999999990000000000099900000000009999900000000000000099990000
0000000000000000002000000020202000000220044000401d110111000000000009999999999000000000099900000000099999900000000000000099999000
00000000000000000200000000022200002222220400004011100000000000000099999999999900000000099900000000999999999999000099999999999900
00000000000000000200000000002000002222220400004000000000000000000000000990000000009999999999990000999999999999000099999999999900
00000000000000000200000000000000000002200400004000000000000000000000000990000000000999999999990000099999900000000000000099999000
00000000000000000020000000000000000002400400004000000000000000000000000990000000000099999999900000009999900000000000000099990000
00000000000000000020000000000000000000400044004000000000000000000000000990000000000009999999000000000999900000000000000099900000
00000000000000000002000000020000000000400000444000000000000000000000000990000000000000999990000000000099900000000000000099000000
00000000000000000000220002200000000000444444444000000000000000000000000990000000000000099900000000000009900000000000000090000000
00000000000000000000002220000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000555000000000055500000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000003333000000500000000000000500000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000330000330000500000000000000500000000000000000000000bb00000000000000bb00000000000000bb000000000000000b0000000
0000000000000000000300000000300000000000000000000000000000000000000000bbbb0000000000000bb0000000000000bbb000000000000000bb000000
000000000000000000300000000003000000000000000000000000000000000000000bbbbbb000000000000bb000000000000bbbb000000000000000bbb00000
0000000d000000000030000330000300000000000000000000000000000000000000bbbccbbb00000000000cc00000000000bbbcc00000000000000ccbbb0000
00000000d0000000030000000000003000000000000000000000000000000000000bbb177cbbb000000000177c000000000bbb177c000000000000177cbbb000
0000000d0000000003000300303000300000000000000000000000000000000000bbbc7c17cbbb0000000c7c17c0000000bbbc7c17cbbbb000bbbc7c17cbbb00
0000000d0000000003000303003000300000000000000000000000000000000000000c71c7c0000000bbbc71c7cbbb0000bbbc71c7cbbbb000bbbc71c7cbbb00
00000000d0000000030000000000003000000000000000000000000000000000000000c771000000000bbbc771bbb000000bbbc771000000000000c771bbb000
0ddd00dddd00ddd00030000330000300000000000000000000000000000000000000000cc00000000000bbbccbbb00000000bbbcc00000000000000ccbbb0000
0dccddcdccddccd00030000000000300000000000000000000000000000000000000000bb000000000000bbbbbb0000000000bbbb000000000000000bbb00000
00dcccddddcccd000003000000003000000000000000000000000000000000000000000bb0000000000000bbbb000000000000bbb000000000000000bb000000
000ddccccccdd0000000330000330000500000000000000500000000000000000000000bb00000000000000bb00000000000000bb000000000000000b0000000
00000dddddd000000000003333000000500000000000000500000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000555000000000055500000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000dd000000000000000000000ddddd00000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000dd000000000000000000000ddddd00000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000dd0000000000000000000dd0000ddd000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000dd0000000000000000000dd0000ddd000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000dd00000000000000000dd00000000ddd0000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000dd00000000000000000dd00000000ddd0000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000dd000000000000000dd000000000000ddd00000000000000000000000000000000000000000000000000000000000000000000000
dddddddddddddddd0000000dd000000000000000dd000000000000ddd00000000000000000000000000000000000000000000000000000000000000000000000
dddddddddddddddd0000000dd0000000000000dd0000000000000000ddd000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000dd0000000000000dd0000000000000000ddd000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000dd00000000000dd00000000000000000000ddd0000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000dd00000000000dd00000000000000000000ddd0000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000dd000000000dd000000000000000000000000ddd00000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000dd000000000dd000000000000000000000000ddd00000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000dd0000000dd0000000000000000000000000000dd0000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000dd0000000dd0000000000000000000000000000dd0000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000bb000000000000000000000bbbbb00000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000bb0000000000000000000bbbbbbb00000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000bb0000000000000000000bb0000bbb000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000bb00000000000000000bbbb0000bbb000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000bb00000000000000000bb00000000bbb0000000000000000000000000000000000000000000000000000000000000000000000000
0000001ccc0000000000001ccc0000000000001ccbbb00000000bbbccc0000000000000000000000000000000000000000000000000000000000000000000000
00000c177cc0000000000c177cc0000000000c177cc00000000000177cc000000000000000000000000000000000000000000000000000000000000000000000
bbbbbc7c17cbbbbb00000c7c17c0000000000c7c17c0000000000c7c17c000000000000000000000000000000000000000000000000000000000000000000000
bbbbbc71c7cbbbbb00000c71c7c0000000000c71c7c0000000000c71c7c000000000000000000000000000000000000000000000000000000000000000000000
000000c771000000000000c7710000000000bbc771000000000000c7713000000000000000000000000000000000000000000000000000000000000000000000
0000000cc00000000000000cc00000000000bb0cc00000000000000cccbbb0000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000bb000000000bbbb00000000000000000000bbb0000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000bb000000000bb000000000000000000000000bbb00000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000bb0000000bbbb000000000000000000000000bbb00000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000bb0000000bb0000000000000000000000000000bb0000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000bb0000000bb0000000000000000000000000000bb0000000000000000000000000000000000000000000000000000000000000000
__gff__
0000000000000000050505050505050500000000000000000505050505050505010105050101000006060606060606060101050501010000060606060606060605050505010505010000000000000000050505050501010500000000000000000606060602060602000000000000000006060606060202060000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
__map__
0001000124252223242524250c0d242524252425242544456667242524254647242500000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
1011101134353233343534351c1d343534353435343554557677343534355657343500000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
2425242524252425242524252425242544452425242564652425242524256667242500000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
3435343534353435343534353435343554553435343574753435343534357677343500000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
2425242524252e2f242524250809242524252425242522232425242524252425242500000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
3435343534353e3f343534351819343534353435343532333435343534353435343500000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
2425242524252425242524252425242546472425242544452e2f242524254445242500000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
3435343534353435343534353435343556573435343554553e3f343534355455343500000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
2425242524252425242524252425242524252425242524252425242524252425242500000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
3435343534353435343534353435343534353435343534353435343534353435343500000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
2425242524252021242524252425242524252425242524252021242524252425242500000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
3435343534353031343534353435343534353435343534353031343534353435343500000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
