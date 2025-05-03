-- MultiblockCraftingAPI.lua

local MultiblockCraftingAPI = {}

MultiblockCraftingAPI.VERSION = "3.0"

-- ENUM FOR MULTIBLOCK TYPES
---@enum MultiblockType
MultiblockCraftingAPI.MultiblockType = {
  MechanicalCrafters = "MechanicalCrafters",
  EnchantingApperatus = "EnchantingApperatus"
}

-- ITEM DETAIL CLASS
---@param itemDetail any
---@return table
function MultiblockCraftingAPI.ItemDetail(itemDetail)
  return {
    name = itemDetail.name,
    displayName = itemDetail.displayName,
    nbt = itemDetail.nbt,
    count = itemDetail.count,
    tags = itemDetail.tags,
  }
end

-- MULTIBLOCK RECIPE CLASS
---@class MultiblockRecipe
---@field version string
---@field type MultiblockType
---@field peripherals table<string, { itemname: string, displayName: string, nbt: any }>
local MultiblockRecipe = {}
MultiblockRecipe.__index = MultiblockRecipe

function MultiblockCraftingAPI.newRecipe()
  local self = setmetatable({}, MultiblockRecipe)
  self.version = MultiblockCraftingAPI.VERSION
  self.peripherals = {}
  return self
end

---@param filename string
function MultiblockRecipe:saveToDisk(filename)
  local f = fs.open(filename, "w")
  if not f then error("Could not open file for writing") end
  f.write(textutils.serialiseJSON(self))
  f.close()
end

---@param filename string
function MultiblockRecipe:loadFromDisk(filename)
  local f = fs.open(filename, "r")
  if not f then error("File not found") end
  local contents = f.readAll()
  f.close()
  if not contents then error("File is empty") end
  local obj = textutils.unserialiseJSON(contents)
  if not obj then error("Failed to parse recipe file") end
  for k,v in pairs(obj) do
    self[k] = v
  end
end

MultiblockCraftingAPI.MultiblockRecipe = MultiblockRecipe

---Automatically detect peripherals by type
---@return table mechanicalCrafters, table arcanePedestals, string? enchantingApparatus
function MultiblockCraftingAPI.detectMultiblockPeripherals()
  local mechanicalCrafters = {}
  local arcanePedestals = {}
  local enchantingApparatus = nil

  for _, name in ipairs(peripheral.getNames()) do
    ---@diagnostic disable param-type-mismatch
    if peripheral.hasType(name, "create_mechanical_crafter") then
      table.insert(mechanicalCrafters, name)
    elseif peripheral.hasType(name, "ars_nouveau:arcane_pedestal") then
      table.insert(arcanePedestals, name)
    elseif peripheral.hasType(name, "ars_nouveau:enchanting_apparatus") then
      enchantingApparatus = name
    end
    ---@diagnostic enable
  end

  return mechanicalCrafters, arcanePedestals, enchantingApparatus
end


---Scan a full Enchanting Apparatus recipe, final item provided manually
---@param pedestalNames string[]
---@param enchantingApparatus string
---@param finalItem table { name: string, displayName: string, nbt: any }
---@return MultiblockRecipe
function MultiblockCraftingAPI.scanApparatusRecipe(pedestalNames, enchantingApparatus, finalItem)
  local recipe = MultiblockCraftingAPI.newRecipe()
  recipe.type = MultiblockCraftingAPI.MultiblockType.EnchantingApperatus

  -- Step 1: Scan pedestals
  for _, name in ipairs(pedestalNames) do
    local itemDetail = peripheral.call(name, "getItemDetail", 1)
    if itemDetail then
      recipe.peripherals[name] = {
        itemname = itemDetail.name,
        displayName = itemDetail.displayName,
        nbt = itemDetail.nbt
      }
    end
  end

  -- Step 2: Add final item manually
  recipe.peripherals[enchantingApparatus] = {
    itemname = finalItem.name,
    displayName = finalItem.displayName,
    nbt = finalItem.nbt
  }

  return recipe
end



---Scan recipe from mechanical crafters
---@param crafterNames string[]
---@return MultiblockRecipe
function MultiblockCraftingAPI.scanCrafterRecipe(crafterNames)
  local recipe = MultiblockCraftingAPI.newRecipe()
  recipe.type = MultiblockCraftingAPI.MultiblockType.MechanicalCrafters

  for _, name in ipairs(crafterNames) do
    local itemDetail = peripheral.call(name, "getItemDetail", 1)
    if itemDetail then
      recipe.peripherals[name] = {
        itemname = itemDetail.name,
        displayName = itemDetail.displayName,
        nbt = itemDetail.nbt
      }
    end
  end

  return recipe
end

---Executes a mechanical crafter recipe
---@param recipe MultiblockRecipe
---@param inputPeripheral string
---@param redstoneSide? string  -- Optional side for redstone pulse (e.g. "back")
---@return boolean allItemsProvided
function MultiblockCraftingAPI.executeMechanicalCrafterRecipe(recipe, inputPeripheral, redstoneSide)
  if recipe.type ~= MultiblockCraftingAPI.MultiblockType.MechanicalCrafters then
    error("Provided recipe is not for MechanicalCrafters")
  end

  local input = peripheral.wrap(inputPeripheral)
  if not input then error("Invalid input peripheral") end
  if not peripheral.hasType(inputPeripheral, "meBridge") then   ---@diagnostic disable-line param-type-mismatch
    error("Only ME Bridge input is supported")
  end

  local allOk = true
  for crafter, entry in pairs(recipe.peripherals) do
    local result = input.exportItemToPeripheral({ name = entry.itemname }, crafter)     ---@diagnostic disable-line param-type-mismatch
    if result == 0 then
      print("Failed to provide item to " .. crafter .. ": " .. entry.itemname)
      allOk = false
    end
  end

  if allOk and redstoneSide then
    redstone.setOutput(redstoneSide, true)
    sleep(0.5)
    redstone.setOutput(redstoneSide, false)
  end

  return allOk
end

---Executes an Enchanting Apparatus recipe using ME Bridge
---@param recipe MultiblockRecipe
---@param meBridge string
---@param redstoneSide? string Optional: Redstone side to send a signal after the last item is placed
function MultiblockCraftingAPI.executeEnchantingApparatusRecipe(recipe, meBridge, redstoneSide)
  if recipe.type ~= MultiblockCraftingAPI.MultiblockType.EnchantingApperatus then
    error("Invalid recipe type for apparatus crafting")
  end

  local input = peripheral.wrap(meBridge)
  if not input then error("ME Bridge peripheral not found") end

  local finalPeripheral = nil

  for name, item in pairs(recipe.peripherals) do
    if peripheral.hasType(name, "ars_nouveau:enchanting_apparatus") then    ---@diagnostic disable-line param-type-mismatch
      finalPeripheral = name -- Store to export last
    else
      local count = input.exportItemToPeripheral({ name = item.itemname }, name)    ---@diagnostic disable-line param-type-mismatch
      if count == 0 then
        print("Missing item for " .. name)
        return
      end
    end
  end

  -- Export the final item last to start the crafting
  if finalPeripheral and recipe.peripherals[finalPeripheral] then
    sleep(0.5) -- slight delay to ensure all pedestal items are placed
    input.exportItemToPeripheral({ name = recipe.peripherals[finalPeripheral].itemname }, finalPeripheral)      ---@diagnostic disable-line undefined-field
  else
    error("No enchanting apparatus item found in recipe")
  end

  -- Optional redstone signal
  if redstoneSide then
    redstone.setOutput(redstoneSide, true)
    sleep(0.5)
    redstone.setOutput(redstoneSide, false)
  end
end





return MultiblockCraftingAPI
