pico-8 cartridge // http://www.pico-8.com
version 15
__lua__

-- terminology

-- position: (x,y) float position
-- location: (i,j) integer position on the 8x6 map of 16x16 tiles
-- precise location: (k,l) integer position on the 16x12 map of 8x8 tiles

-- flags

-- Flag 0: should be check for collision

-- convert 16x16 spritesheet coordinates to 8x8 coordinates
-- (16x16 are easier to visualize for big sprites)
function to_spritesheet_precise_indices(i, j)
 return 32*j+2*i
end

-- sprite ID

EMITTER_ID = to_spritesheet_precise_indices(0,1)   -- 32
RECEIVER_ID = to_spritesheet_precise_indices(1,1)  -- 34

-- constants
FIXED_DELTA_TIME = 1/30
MOVING_LETTER_INITIAL_SPEED = 50.0  -- original 20.0

-- colors
BLACK = 0
DARK_BLUE = 1
DARK_PURPLE = 2
DARK_GREEN = 3
BROWN = 4
DARK_GRAY = 5
LIGHT_GRAY = 6
WHITE = 7
RED = 8
ORANGE = 9
YELLOW = 10
GREEN = 11
BLUE = 12
INDIGO = 13
PINK = 14
PEACH = 15

REMAINING_LETTER_COLOR = INDIGO
RECEIVED_LETTER_COLOR = BLACK
MOVING_LETTER_COLOR = RED
BOTTOM_MESSAGE_COLOR = WHITE


-- data

level_data = {
 start_letters = {"b", "a"},
 -- goal_letters = {"a", "b"}
 goal_letters = {"b", "a"},
 bottom_message = "press ❎ to emit letters"
}


-- data cache

level_data_cache = {
 emitter_location = nil
}


-- state variables

-- index of the curent level
current_level = 0

-- game state (playing, failed, succeeded)
current_gamestate = "playing"

-- sequence of letters remaining to emit from the emitter
remaining_letters_to_emit = {}

-- sequence of letters already received by the receiver
received_letters = {}

-- letters already emitted but not yet received
moving_letters = {}

-- the current coroutines
coroutines = {}

-- has the player started emitting letters since the last setup/reset?
has_started_emission = false

-- UI: hint message at the bottom
bottom_message = ""


-- helpers

-- clear a table
function clear_table(t)
 for k in pairs(t) do
  t[k] = nil
 end
end

-- yield as many times as needed so that, assuming you coresume the calling
-- coroutine each frame at 30 FPS, the coroutine resumes after [time] seconds
function yield_delay(time)
 local nb_frames = 30*time
 for frame=1,nb_frames do  -- still works if nb_frames is not integer (~flr(nb_frames))
  yield()
 end
end

-- return the (x,y) position corresponding to an (i,j) location for 16x16 tiles
function location_to_position(location)
 return {x = 16*location.i, y = 16*location.j}
end

-- return the (k,l) precise location corresponding to an (x,y) position for 8x8 tiles
function position_to_precise_location(position)
 return {k = flr(position.x/8), l = flr(position.y/8)}
end

-- return the (i,j) location corresponding to a (k,l) precise location for 8x8->16x16 tiles
function precise_location_to_location(precise_location)
 return {i = flr(precise_location.k/2), j = flr(precise_location.l/2)}
end

-- return the (k,l) previse location of the top-left sub-tile of the big tile containing a given sub-tile
function to_representative_location(precise_location)
 local location = precise_location_to_location(precise_location)
 return {k = 2*location.i, l = 2*location.j}
end


-- factory

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
  }
 }
 return moving_letter
end


-- game loop

function _init()
 -- activate mouse devkit (for mouse input support)
 poke(0x5f2d, 1)

 setup_level(0)
end

function _update()
 handle_input()

 if current_gamestate == "playing" then
  update_moving_letters()
 end

 update_coroutines()
end

function _draw()
 draw_gamespace()
 draw_topbar()
 draw_bottombar()
 draw_cursor()
end


-- input

function handle_input()
 if current_gamestate == "playing" then
  if not has_started_emission and btnp(❎) then
   start_emit_letters()
  end
 end
end


-- game flow

-- setup level state by level index
function setup_level(index)
 -- update level date cache
 local emitter_location = find_emitter_location()
 if not emitter_location then
  printh("error: emitter could not be found on this map")
 end
 level_data_cache.emitter_location = emitter_location

 -- setup game state
 current_gamestate = "playing"

 -- copy start letters sequence
 for letter in all(level_data.start_letters) do
  add(remaining_letters_to_emit, letter)
 end

 -- no received nor moving letters at the beginning
 clear_table(received_letters)
 clear_table(moving_letters)

 -- stop and clear the emit coroutine if needed (coroutines must be resumed to continue;
 -- if they aren't and references to them disappear, they will be GC-ed, effectively being stopped)
 clear_table(coroutines)
 has_started_emission = false

 -- UI
 bottom_message = level_data.bottom_message
end

function succeed_current_level()
 current_gamestate = "succeeded"
 bottom_message = "success!"
 load_level_coroutine = cocreate(load_next_level_async)
 add(coroutines, load_level_coroutine)
end

function fail_current_level()
 current_gamestate = "failed"
 bottom_message = "failed!"
end

function load_next_level_async()
 yield_delay(2.0)
 current_level += 1
 setup_level(current_level)
end


-- logic

-- return the location of the (supposedly unique) emitter in this level, nil if not found
function find_emitter_location()
 local emitter_location = nil
 for i=0,7 do
  for j=0,5 do
   local sprite_id = mget(2*i,2*j)  -- map uses precise location, hence double
   if sprite_id == EMITTER_ID then
    return {i = i, j = j}
   end
  end
 end
 return nil
end

-- start and register coroutine to emit letters at regular intervals from now on
function start_emit_letters()
 local emit_coroutine = cocreate(function()
   while #remaining_letters_to_emit > 0 do
    -- printh("remaining_letters_to_emit before: "..#remaining_letters_to_emit)
    emit_next_letter()
    -- printh("remaining_letters_to_emit after: "..#remaining_letters_to_emit)
    yield_delay(1.0)
   end
  end)
 has_started_emission = true
 add(coroutines, emit_coroutine)
end

-- emit the next letter from the emitter
function emit_next_letter()
 printh("emit_next_letter")

 -- get next letter to emit
 local next_letter = remaining_letters_to_emit[1]

 -- create and emit letter with default velocity
 local emit_position = location_to_position(level_data_cache.emitter_location)
 local moving_letter = make_moving_letter(next_letter,emit_position.x+8,emit_position.y+10,0,-MOVING_LETTER_INITIAL_SPEED)

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
   coresume(coroutine)
  elseif status == "dead" then
   coroutine = nil
  else  -- status == "running"
   printh("WARNING: coroutine should not be running outside its body")
  end
 end
end


-- physics

function update_moving_letters()
 for moving_letter in all(moving_letters) do
  update_position(moving_letter)
  check_collision(moving_letter)
 end
end

-- apply current velocity to moving letter
function update_position(moving_letter)
 moving_letter.position.x += moving_letter.velocity.x*FIXED_DELTA_TIME
 moving_letter.position.y += moving_letter.velocity.y*FIXED_DELTA_TIME
end

-- check if moving letter entered a tile with a special effect, and apply it if so
function check_collision(moving_letter)
 -- since some object colliders occupy precise tiles (e.g. the mirror), we need precise location
 -- to check for collision flag
 local precise_location = position_to_precise_location(moving_letter.position)
 local precise_sprite_id = mget(precise_location.k, precise_location.l)
 if precise_sprite_id != 0 then
  local collision_flag = fget(precise_sprite_id, 0)
  if collision_flag then
   -- for colliding sprite ID, we use the location of the big tile since it's easier to compare
   -- with just the top-left tile ID than with all 4 sub-tile IDs (it's the same 1 time out of 4)
   local representative_location = to_representative_location(precise_location)
   local representative_sprite_id = mget(representative_location.k, representative_location.l)
   if representative_sprite_id == RECEIVER_ID then
    receive(moving_letter)
   end
  end
 end
end

-- confirm reception of moving letter
function receive(moving_letter)
 add(received_letters, moving_letter.letter)
 del(moving_letters, moving_letter)
 check_all_letters_received()
end

function check_all_letters_received()
 -- first, check if all letters have been sent, as some extra letters at the end
 -- may invalidate an otherwise good chain, and even in case of early failure we want
 -- to let the player witness what happens in the long run to improve next time
 if #remaining_letters_to_emit > 0 or #moving_letters > 0 then
  -- some letters still on the move, go on
  return
 end

 -- second, check if we received enough letters to pretend to have reached the goal
 if #received_letters == #level_data.goal_letters then
  -- then check if the letters are correctly ordered
  printh("received_letters nb: "..#received_letters)
  for i,received_letter in pairs(received_letters) do
   printh("comparing "..received_letter.." vs "..level_data.goal_letters[i])
   if received_letter != level_data.goal_letters[i] then
    printh("not equal!")
    -- some letters are wrong; continue playing to let player experiment a bit further
    fail_current_level()
    return
   end
  end
  -- all characters are equal
  printh("equal!")
  succeed_current_level()
 else
  -- different lengths, either some letters have been lost, not duplicated
  -- as they should or duplicated too much
  fail_current_level()
 end
end

-- render

function draw_gamespace()
 -- camera offset
 camera(0,-16)

 -- background
 rectfill(0,0,127,96,7)

 -- map (8x6 @ 16x16 tiles)
 map(0,0,0,0,8*2,6*2)

 draw_remaining_letters()
 draw_moving_letters()
end

function draw_remaining_letters()
 local emitter_location = level_data_cache.emitter_location
 if not emitter_location then
  printh("ERROR: emitter location was not found, cannot draw remaining letters")
  return
 end

 for index=1,#remaining_letters_to_emit do
  remaining_letter = remaining_letters_to_emit[index]
  print(remaining_letter,16*(level_data_cache.emitter_location.i+1)+6*(index-1)+3,16*level_data_cache.emitter_location.j+6,REMAINING_LETTER_COLOR)
 end
end

function draw_moving_letters()
 for index=1,#moving_letters do
  moving_letter = moving_letters[index]
  -- print the letter a bit offset so the character is centered on its position
  print(moving_letter.letter,moving_letter.position.x-2,moving_letter.position.y-3,MOVING_LETTER_COLOR)
 end
end

function draw_topbar()
 -- camera offset: top
 camera(0,0)

 -- background
 rectfill(0,0,127,16,13)

 draw_received_letters()

 -- restart
 spr16(1,6*16,0)
 -- exit
 spr16(2,7*16,0)
end

function draw_received_letters()
 for i,received_letter in pairs(received_letters) do
  print(received_letter,51+4*i,4,RECEIVED_LETTER_COLOR)
 end
end

function draw_bottombar()
 -- camera offset: bottom
 camera(0,-112)

 -- background
 rectfill(0,0,127,16,0)

 draw_bottom_message()
end

function draw_bottom_message()
 if #bottom_message > 0 then
  print(bottom_message, 3, 2, WHITE)
 end
end

function draw_cursor()
-- camera offset: origin
camera(0,0)

 local cursor_x = stat(32)
 local cursor_y = stat(33)
 spr(6,cursor_x,cursor_y)
end

-- draw sprite 16x16 of meta-number n at coords (x,y), optionally flipped in x/y, where n is defined for a spritesheet containing only 16x16 sprites
function spr16(n, x, y, flip_x, flip_y)
 spr(32*flr(n/8)+2*(n%8), x, y, 2, 2, flip_x, flip_y)
end

__gfx__
00000000000000000000000000000000000000000000000001110000000000000000000000000000000000000000000000000000000000005550000000000555
0000000000000000000000000000000000000000000000001dd11000000000000000000000000000000000000000000000000000000000005000000000000005
0000000000000000000000222000000000000044444444401ddd1100000000000000000000000000000000000000000000000000000000005000000000000005
0000000000000000000022000220000000000040040000401dddd110000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000200000002000000000040040000401ddddd11000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000002000000000200000000240040000401dd11dd1000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000002000000020202000000220044000401d110111000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000200000000022200002222220400004011100000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000200000000002000002222220400004000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000200000000000000000002200400004000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000020000000000000000002400400004000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000020000000000000000000400044004000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000002000000020000000000400000444000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000220002200000000000444444444000000000000000000000000000000000000000000000000000000000000000005000000000000005
00000000000000000000002220000000000000000000000000000000000000000000000000000000000000000000000000000000000000005000000000000005
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000005550000000000555
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000003333000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000330000330000000000099000000000000009990000000000000990000000000000009000000000000000000000000000000000000000
00000000000000000003000000003000000000999900000000000009990000000000009990000000000000009900000000000000000000000000000000000000
00000000000000000030000000000300000009999990000000000009990000000000099990000000000000009990000000000000000000000000000000000000
0000000d000000000030000330000300000099999999000000000009990000000000999990000000000000009999000000000000000000000000000000000000
00000000d00000000300000000000030000999999999900000000009990000000009999990000000000000009999900000000000000000000000000000000000
0000000d000000000300030030300030009999999999990000000009990000000099999999999900009999999999990000000000000000000000000000000000
0000000d000000000300030300300030000000099000000000999999999999000099999999999900009999999999990000000000000000000000000000000000
00000000d00000000300000000000030000000099000000000099999999999000009999990000000000000009999900000000000000000000000000000000000
0ddd00dddd00ddd00030000330000300000000099000000000009999999990000000999990000000000000009999000000000000000000000000000000000000
0dccddcdccddccd00030000000000300000000099000000000000999999900000000099990000000000000009990000000000000000000000000000000000000
00dcccddddcccd000003000000003000000000099000000000000099999000000000009990000000000000009900000000000000000000000000000000000000
000ddccccccdd0000000330000330000000000099000000000000009990000000000000990000000000000009000000000000000000000000000000000000000
00000dddddd000000000003333000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
__gff__
0000000000000000000000000000000000000000000000000000000000000000000001010101010101010101000000000000010101010101010101010000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
__map__
0e0f0e0f0e0f22230e0f0e0f28290e0f00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
1e1f1e1f1e1f32331e1f1e1f38391e1f00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0e0f0e0f0e0f0e0f0e0f0e0f0e0f0e0f00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
1e1f1e1f1e1f1e1f1e1f1e1f1e1f1e1f00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0e0f0e0f0e0f2a2b0e0f0e0f24250e0f00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
1e1f1e1f1e1f3a3b1e1f1e1f34351e1f00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0e0f0e0f0e0f0e0f0e0f0e0f0e0f0e0f00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
1e1f1e1f1e1f1e1f1e1f1e1f1e1f1e1f00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0e0f0e0f0e0f0e0f0e0f0e0f0e0f0e0f00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
1e1f1e1f1e1f1e1f1e1f1e1f1e1f1e1f00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0e0f0e0f0e0f20210e0f0e0f0e0f0e0f00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
1e1f1e1f1e1f30311e1f1e1f1e1f1e1f00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
