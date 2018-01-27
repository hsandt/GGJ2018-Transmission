pico-8 cartridge // http://www.pico-8.com
version 15
__lua__

function _init()

end

function _update()

end

function _draw()
 -- game space
 -- background
 rectfill(0,16,127,112,7)

 -- top-bar
 -- background
 rectfill(0,0,127,16,13)
 -- restart
 spr(1,6*16,0)
 -- exit

 -- bottom-bar
 rectfill(0,112,127,127,0)
end
