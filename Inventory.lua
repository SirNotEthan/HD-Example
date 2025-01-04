-- Services
-- References to Roblox services used in this script.
local Players = game:GetService("Players")  -- Manages player-related events and actions.
local ReplicatedStorage = game:GetService("ReplicatedStorage") -- Shared storage for remote events and modules.
local DataStoreService = game:GetService("DataStoreService") -- Enables persistent data storage for players.

local InventoryStore = DataStoreService:GetDataStore("PlayerInventory") -- DataStore for storing player inventory data persistently.
local MarketStore = DataStoreService:GetDataStore("MarketData") -- DataStore for storing marketplace data persistently.
local EarningsStore = DataStoreService:GetDataStore("EarningsStore") -- Datastore for storing offline purchases 

local playerInventories = {} -- Table to store active player inventories in memory during the session.
local saveQueue = {} -- Store items to save

local InventoryEvent = ReplicatedStorage:WaitForChild("InventoryEvent") -- Remote event for client-server communication about inventory updates.
local PrintEvent = ReplicatedStorage:WaitForChild("PrintEvent") -- Used to send debug messages or notifications to clients.
local RequestItemsByCategory = ReplicatedStorage:WaitForChild("RequestItemsByCategory") -- Sends all the items on the market for the client to see
local RequestPlayerInventory = ReplicatedStorage:WaitForChild("RequestPlayerInventory") -- Sends all the items in the players inventory to the sell menu
local MarketEvent = ReplicatedStorage:WaitForChild("MarketEvent") -- Market updates such as item listings

-- Sends messages to the client for debugging or notifications.
function sendPrintToClient(player, message)
    PrintEvent:FireClient(player, message) -- Sends the message to the client using the PrintEvent.
end

-- Item Class Metatable
-- Defines the structure and behavior of individual inventory items.
local Item = {}
Item.__index = Item

-- Constructor for creating a new item.
function Item.new(name, id, description, maxStack, durability, rarity, category, isQuestItem)
    local self = setmetatable({}, Item) -- Creates a new table and sets its metatable to Item.
    self.Name = name -- Name of the item
    self.ID = id -- Unique Identifier for the item.
    self.Description = description or "No Description" -- Description of the item, defaults to "No Description".
    self.MaxStack = maxStack or 64 -- Maximum number of items that can stack, defaults to 64.
    self.StackCount = 1 -- Number of items in the stack, defaults to 1.
    self.Durability = durability or 100 -- Durability of the item, defaults to 100.
    self.Rarity = rarity or "Common" -- Rarity of the item, defaults to "Common".
    self.Category = category or "Miscellaneous" -- Category of the item, defaults to "Miscellaneous".
    self.IsQuestItem = isQuestItem or false -- Indicates if the item is a quest item, defaults to false.
    return self
end

-- Method to increase the item's stack count.
function Item:IncreaseStack(amount)
    self.StackCount = math.min(self.StackCount + amount, self.MaxStack) -- Ensures stack count does not exceed MaxStack.
end

function Item:DecreaseStack(amount)
    self.StackCount = math.max(self.StackCount - amount, 0) -- Ensures stack count does not go below 0.
    if self.StackCount <= 0 then
        self:DestroyItem()
    end
end

function Item:UseItem()
    if self.Durability > 0 then -- Ensures the durability is above 0
        self.Durability = self.Durability - 1 -- Deducts one durability on usage
    else
        sendPrintToClient(self.Player, "This item is broken!") -- Notifies the player that the item is broken.
    end
end

function Item:DestroyItem()
    sendPrintToClient(self.Player, "Item destroyed: " .. self.Name) -- Notifies the player that the item is destroyed.
end

-- Inventory Class Metatable
-- Represents a player's inventory, managing items and their UI updates.
local Inventory = {}
Inventory.__index = Inventory

function Inventory.new(player)
    local self = setmetatable({}, Inventory) -- Creates a new table and sets its metatable to Inventory.
    self.Player = player -- The player who owns this inventory.
    self.Items = {} -- Table to store items by their ID.
    self.InventoryLimit = 50 -- Max number of items a player can hold
    self.PendingUpdates = {}
    return self
end

function Inventory:QueueUpdate(item)
    table.insert(self.PendingUpdates, item) -- Add the item to the pending updates table.
    if #self.PendingUpdates >= 10 or not self.BatchUpdateScheduled then -- Schedule a batch update if there are 10 pending updates or none are scheduled.
        self.BatchUpdateScheduled = true -- Schedule the batch update.
        task.spawn(function() -- Wait for 0.1 seconds before processing the pending updates.
            task.wait(0.1)
            self:UpdateUI() -- Process the pending updates and reset the flag.
            self.PendingUpdates = {} -- Clear the pending updates table after processing.
            self.BatchUpdateScheduled = false  -- Reset the batch update flag.
        end)
    end
end

-- Method to add an item to the inventory.
function Inventory:AddItem(item)
    if not item or typeof(item) ~= "table" then -- Validates that the item is a table.
        warn("Invalid item passed to AddItem")
        sendPrintToClient(self.Player, "Failed to add item: Invalid item.") -- Notifies Client of the item not being valid
        return
    end
    
    -- If the item already exists, increase its stack; otherwise, add it as new.
    if self.Items[item.ID] then 
        self.Items[item.ID]:IncreaseStack(1)
        sendPrintToClient(self.Player, "Item stack increased: " .. item.Name)
    else
        self.Items[item.ID] = item
        sendPrintToClient(self.Player, "New item added: " .. item.Name)
    end
    
    -- Update the inventory UI to reflect the changes.
    self:UpdateUI()
end

-- Method to remove an item from the inventory.
function Inventory:RemoveItem(itemID)
    if self.Items[itemID] then
        local item = self.Items[itemID]
        item:DecreaseStack(1)
        -- Remove the item if its stack count reaches zero.
        if item.StackCount <= 0 then
            self.Items[itemID] = nil
            sendPrintToClient(self.Player, "Item removed: " .. item.Name)
        else
            sendPrintToClient(self.Player, "Item stack decreased: " .. item.Name)
        end
        self:UpdateUI()
    end
end

function Inventory:GetItems()
    return self.Items -- Returns the items in the inventory.
end

-- Method to update the player's inventory UI.
function Inventory:UpdateUI()
    if not self.Player or not self.Player.Parent then -- Validates that the player is still in the game.
        return
    end
    InventoryEvent:FireClient(self.Player, self.Items) -- Sends the inventory data to the client.
end

-- Function to load inventory data and populate the player's inventory
function Inventory:Load(inventoryData)
    -- Iterate over each item in the provided inventoryData
    for _, itemData in pairs(inventoryData) do
        -- Create a new item using the data provided in the inventoryData
        local item = Item.new(
            itemData.Name,         -- The name of the item
            itemData.ID,           -- The unique ID of the item
            itemData.Description,  -- A description of the item
            itemData.MaxStack,     -- The maximum stack size for this item
            itemData.Durability,   -- The durability of the item
            itemData.Rarity,       -- The rarity of the item
            itemData.Category,     -- The category of the item (e.g., weapon, armor, consumable)
            itemData.IsQuestItem   -- A boolean flag indicating if the item is a quest item
        )
        -- If StackCount is provided, use it; otherwise, default to 1
        item.StackCount = itemData.StackCount or 1
        -- Add the created item to the player's inventory
        self:AddItem(item)
    end
end

-- Functions for Item Market
-- Add an item to the market
local marketItems = {}

-- Function to load marketplace data from the DataStore
local function loadMarketplace()
    -- Try to retrieve the market items data from the MarketStore DataStore
    local success, data = pcall(function()
        return MarketStore:GetAsync("MarketItems")
    end)

    -- If the data retrieval is successful, assign it to the marketItems table
    if success and data then
        marketItems = data
        -- Print a success message if the data was loaded successfully
        print("Market Data Succeeded")
    else
        -- If there was an error retrieving the data or no data is found, initialize an empty marketItems table
        marketItems = {}
        -- Print a warning if the data retrieval failed
        warn("Market Data Failed")
    end
end

-- Function to add a new item to the market
function addItemToMarket(player, item, price, category)
    -- Add the new item to the marketItems table
    table.insert(marketItems, {
        Seller = player.UserId,  -- Store the seller's UserId
        Name = item.Name,        -- Store the item's name
        Category = category,     -- Store the item's category
        Price = price,           -- Store the item's price
        ID = #marketItems + 1,   -- Assign a unique ID based on the current size of marketItems
    })

    -- Try to save the updated marketItems table to the MarketStore DataStore
    local success, err = pcall(function()
        MarketStore:SetAsync("MarketItems", marketItems)
    end)

    -- If there is an error saving the data, print a warning
    if not success then
        warn("Failed to save marketplace data: " .. err)
    end
end

-- Function to handle the purchase of an item from the market
function purchaseItemFromMarket(player, itemID) 
    -- Loop through all the items in the market to find the one that matches the provided itemID
    for index, item in ipairs(marketItems) do 
        -- Check if the current item in the market matches the requested itemID
        if item.ID == itemID then 
            -- Check if the player has enough currency to purchase the item
            if player.leaderstats.Currency.Value >= item.Price then 
                -- Deduct the item's price from the player's currency
                player.leaderstats.Currency.Value -= item.Price 
                -- Get the seller's player object using the seller's UserId
                local seller = game.Players:GetPlayerByUserId(item.Seller) 
                -- If the seller is online, transfer the money directly to their account
                if seller then
                    seller.leaderstats.CurrencyValue.Value += item.Price
                else 
                    -- If the seller is offline, update their earnings in the DataStore
                    local success, err = pcall(function() 
                        -- Retrieve the seller's current earnings from the DataStore, default to 0 if not found
                        local currentEarnings = EarningsStore:GetAsync(tostring(item.Seller)) or 0  
                        -- Update the seller's earnings in the DataStore by adding the item's price
                        EarningsStore:SetAsync(tostring(item.Seller), currentEarnings + item.Price)
                    end) 
                    -- If an error occurs while updating the seller's earnings, log a warning
                    if not success then
                        warn("Failed to update earnings for offline seller: " .. err)
                    end
                end
                -- Remove the item from the market since it has been purchased
                table.remove(marketItems, index)
                -- Save the updated market items list to the DataStore
                local success, err = pcall(function()
                    -- Update the marketplace DataStore with the modified marketItems list
                    MarketStore:SetAsync("MarketItems", marketItems)
                end)
                -- If an error occurs while saving the market data, log a warning
                if not success then
                    warn("Failed to save marketplace data: " .. err)
                end
                -- Return true to indicate the purchase was successful
                return true
            else
                -- If the player doesn't have enough currency, return a message indicating so
                return 'Not Enough Currency'
            end
        end
    end
    -- If the item was not found in the market, return a message indicating the item wasn't found
    return 'Item Not Found'
end

-- Function to retrieve and reset a player's earnings
function GetEarnings(player)
    -- Attempt to retrieve the player's earnings from the EarningsStore
    local success, data = pcall(function()
        -- Fetches the earnings data from the DataStore using the player's UserId
        return EarningsStore:GetAsync(tostring(player.UserId))
    end)

    -- Check if the data retrieval was successful
    if success and data then
        -- If successful, add the earnings to the player's currency (leaderstats)
        player.leaderstats.Currency.Value += data
        -- After updating the player's currency, reset the earnings in the DataStore to 0
        EarningsStore:SetAsync(tostring(player.UserId), 0)
    else
        -- If there was an error or no data was found, print a warning message
        warn('Failed to retrieve earnings for player: ' .. player.Name)
    end
end

-- Function to get all items from the marketplace that belong to a specific category
function GetItemByCategory(category)
    local items = {}  -- Create an empty table to store the items of the specified category
    -- Iterate through all market items
    for _, item in ipairs(marketItems) do
        -- If the item's category matches the specified category, add it to the 'items' table
        if item.Category == category then
            table.insert(items, item)
        end
    end
    -- Return the list of items that belong to the specified category
    return items
end

-- Function to save the player's inventory to a storage system
function SaveInventory(player, inventory)
    -- If there are no players in the save queue, start saving
    if #saveQueue == 0 then
        -- Add the player's UserId to the save queue
        table.insert(saveQueue, player.UserId)

        -- Try saving the player's inventory to the InventoryStore
        local success, err = pcall(function()
            InventoryStore:SetAsync(player.UserId, inventory.Items)  -- Save the player's inventory items to the store
        end)

        -- If saving fails, print an error message and send it to the player
        if not success then
            warn("Failed to save inventory for " .. player.Name .. ": " .. err)
            sendPrintToClient(player, "Error saving inventory: " .. err)
        else
            -- If saving is successful, notify the player
            sendPrintToClient(player, "Inventory saved successfully.")
        end
    end
end

-- Periodically saves all inventories in the save queue every 60 seconds
function PeriodicSave()
    while true do
        wait(60)  -- Wait for 60 seconds before starting the save process

        -- Iterate through all user IDs in the save queue
        for _, userId in pairs(saveQueue) do
            local player = Players:GetPlayerByUserId(userId)  -- Get the player by their UserId
            if player then
                -- If the player is online, save their inventory
                SaveInventory(player, getPlayerInventory(player))
            end
        end

        -- Clear the save queue after saving all inventories
        saveQueue = {}
    end
end

-- Start the PeriodicSave function as a separate task to run in the background
spawn(PeriodicSave)

-- Function to load a player's inventory from the storage system
function LoadInventory(player, inventory)
    -- Try loading the player's inventory from the InventoryStore
    local success, data = pcall(function()
        return InventoryStore:GetAsync(player.UserId)  -- Get the inventory data for the player from the store
    end)

    -- If loading is successful and data exists, process the items
    if success and data then
        -- Iterate over the data and create items from it
        for _, itemData in pairs(data) do
            -- Create a new item instance using the data from the storage
            local item = Item.new(
                itemData.Name,         -- The name of the item
                itemData.ID,           -- The unique ID of the item
                itemData.Description,  -- The description of the item
                itemData.MaxStack,     -- The maximum stack size of the item
                itemData.Durability,   -- The durability of the item
                itemData.Rarity,       -- The rarity of the item
                itemData.Category,     -- The category of the item
                itemData.IsQuestItem   -- A flag indicating if the item is a quest item
            )
            -- If StackCount is not provided, default it to 1
            item.StackCount = itemData.StackCount or 1
            -- Add the created item to the player's inventory
            inventory:AddItem(item)
        end
    else
        -- If loading fails, print a warning message
        warn("Failed to load inventory for " .. player.Name)
    end
end

-- Function to create the inventory UI for the player.
local function createInventoryUI(player)
    local PlayerGui = player:WaitForChild("PlayerGui") -- Waits for the PlayerGui to load.
    if not PlayerGui then
        warn("PlayerGui not found for " .. player.Name)
        return
    end
    
    -- Main UI container for the inventory.
    local InventoryUI = Instance.new("ScreenGui")
    InventoryUI.Name = "InventoryUI"
    InventoryUI.Parent = PlayerGui
    local InventoryFrame = Instance.new("Frame")
    InventoryFrame.Name = "InventoryFrame"
    InventoryFrame.Size = UDim2.new(0, 300, 0, 500)
    InventoryFrame.Position = UDim2.new(0.5, -150, 0.5, -250)
    InventoryFrame.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
    InventoryFrame.Parent = InventoryUI
    InventoryFrame.Visible = false
    local Title = Instance.new("TextLabel")
    Title.Size = UDim2.new(1, 0, 0, 50)
    Title.Text = "Inventory"
    Title.TextSize = 24
    Title.TextColor3 = Color3.fromRGB(255, 255, 255)
    Title.BackgroundTransparency = 1
    Title.Parent = InventoryFrame
    local ItemList = Instance.new("ScrollingFrame")
    ItemList.Size = UDim2.new(1, 0, 1, -50)
    ItemList.Position = UDim2.new(0, 0, 0, 50)
    ItemList.CanvasSize = UDim2.new(0, 0, 0, 0)
    ItemList.BackgroundTransparency = 1
    ItemList.Parent = InventoryFrame
    local ListLayout = Instance.new("UIListLayout")
    ListLayout.Parent = ItemList
    return InventoryUI
end

-- Events
-- Triggered when a player joins the game.
Players.PlayerAdded:Connect(function(player)
    local inventory = Inventory.new(player)
    playerInventories[player.UserId] = inventory
    LoadInventory(player, inventory)
    sendPrintToClient(player, "Inventory loaded successfully.")

    -- Create and display the inventory UI.
    local InventoryUI = createInventoryUI(player)
    if InventoryUI then
        print("InventoryUI created successfully for player: " .. player.Name)

        -- Example items added to the inventory.
        local harmingPotion = Item.new("Harming Potion", "potion001", "A potion that harms.", 10, 100, "Common", "Potion", false)
        local sword = Item.new("Sword", "sword001", "A basic sword.", 1, 50, "Common", "Weapon", false)
        local sword2 = Item.new("Sword2", "sword002", "A basic sword.", 1, 50, "Common", "Weapon", false)

        inventory:AddItem(harmingPotion)
        inventory:AddItem(sword)
        inventory:AddItem(sword2)

        -- Notify client about items added
        sendPrintToClient(player, "New items added to your inventory.")
    else
        print("Failed to create InventoryUI for player: " .. player.Name)
    end
end)

-- Triggered when a player leaves the game.
Players.PlayerRemoving:Connect(function(player)
    local inventory = playerInventories[player.UserId]
    if inventory then
        SaveInventory(player, inventory)
    end
    playerInventories[player.UserId] = nil
end)

-- Connections
-- Listen for a request from the client to fetch items by category
RequestItemsByCategory.OnServerEvent:Connect(function(player, category)
    -- Get the list of items from the marketplace that belong to the specified category
    local items = GetItemByCategory(category)
    -- Fire an event back to the client, sending the list of items in the specified category
    RequestItemsByCategory:FireClient(player, items)
end)

-- Listen for a request from the client to fetch the player's inventory
RequestPlayerInventory.OnServerEvent:Connect(function(player)
    -- Retrieve the player's inventory from the 'playerInventories' table using the player's UserId
    local inventory = playerInventories[player.UserId]
    -- If the player has an inventory, proceed with sending it to the client
    if inventory then
        local itemNames = {}  -- Create an empty table to store the names of the items in the inventory
        -- Iterate over all the items in the player's inventory
        for _, item in pairs(inventory:GetItems()) do
            -- Add each item's name to the 'itemNames' table
            table.insert(itemNames, item.Name)
        end
        -- Fire an event back to the client, sending the list of item names in the player's inventory
        RequestPlayerInventory:FireClient(player, itemNames)
    end
end)

-- Listen for a request from the client to add an item to the market
MarketEvent.OnServerEvent:Connect(function(player, itemName, price, category)
    -- Add the item to the market using the 'addItemToMarket' function, passing the player, item name, price, and category
    addItemToMarket(player, itemName, price, category)
end)

loadMarketplace()
