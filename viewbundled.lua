
computerSidesTable = { "top", "bottom", "left", "right", "front", "back" }

term.clear()

while true do
  for iside=0, #computerSidesTable-1 do
    local y = 2 + iside * 3
    local side = computerSidesTable[iside+1]
    local bundledState = redstone.getBundledInput(side)

    term.setCursorPos(1, y)
    term.write(string.format("%-7s 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6", side))
    
    for i=0,15 do
      term.setCursorPos(8+(2*i), y+1)
      if colors.test(bundledState, 2^i) then
        term.setBackgroundColor(2^i)
        term.write("xx")
      else
        term.write("__")
      end
      term.setBackgroundColor(colors.black)
    end

    term.setCursorPos(40, y+1)
    term.write(string.format("%7s", bundledState))
  end
  os.sleep(3)
end
