-- Services
-- References to Roblox services used in this script.
local Players = game:GetService("Players")  -- Manages player-related events and actions.
local ReplicatedStorage = game:GetService("ReplicatedStorage") -- Shared storage for remote events and modules.
local DataStoreService = game:GetService("DataStoreService") -- Enables persistent data storage for players.
local HTTPService = game:GetService("HttpService")

local InventoryStore = DataStoreService:GetDataStore("PlayerInventory") -- DataStore for storing player inventory data persistently.
local MarketStore = DataStoreService:GetDataStore("MarketData")
local playerInventories = {} -- Table to store active player inventories in memory during the session.
local saveQueue = {} -- Store items to save
local InventoryEvent = ReplicatedStorage:WaitForChild("InventoryEvent") -- Remote event for client-server communication about inventory updates.
local PrintEvent = ReplicatedStorage:WaitForChild("PrintEvent") -- Used to send debug messages or notifications to clients.

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
    self.Owner = player -- Reference to the player who owns the inventory.
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
        sendPrintToClient(self.Owner, "This item is broken!") -- Notifies the player that the item is broken.
    end
end

function Item:DestroyItem()
    sendPrintToClient(self.Owner, "Item destroyed: " .. self.Name) -- Notifies the player that the item is destroyed.
end

-- Inventory Class Metatable
-- Represents a player's inventory, managing items and their UI updates.
local Inventory = {}
Inventory.__index = Inventory

function Inventory.new(owner)
    local self = setmetatable({}, Inventory) -- Creates a new table and sets its metatable to Inventory.
    self.Owner = owner -- The player who owns this inventory.
    self.Items = {} -- Table to store items by their ID.
    self.InventoryLimit = 50  -- Max number of items a player can hold
    self.PendingUpdates = {}
    return self
end

function Inventory:QueueUpdate(item)
    table.insert(self.PendingUpdates, item) -- Add the item to the pending updates table.
    if #self.PendingUpdates >= 10 or not self.BatchupdateScheduled then -- Schedule a batch update if there are 10 pending updates or none are scheduled.
        self.BatchupdateScheduled = true -- Schedule the batch update.
        task.defer(function()  -- Wait for 0.1 seconds before processing the pending updates.
            task.wait(0.1)
            self:UpdateUI() -- Process the pending updates and reset the flag.
            self.PendingUpdates = {} -- Clear the pending updates table after processing.
            self.BatchupdateScheduled = false -- Reset the batch update flag.
        end)
    end
end

-- Method to add an item to the inventory.
function Inventory:AddItem(item)
    if not item or typeof(item) ~= "table" then  -- Validates that the item is a table.
        warn("Invalid item passed to AddItem")
        sendPrintToClient(self.Owner, "Failed to add item: Invalid item.") -- Notifies Client of the item not being valid
        return
    end

    if self:GetItemCount() >= self.InventoryLimit then -- Validates that the inventory is not full.
        sendPrintToClient(self.Owner, "Inventory is full.")
        return
    end

    -- If the item already exists, increase its stack; otherwise, add it as new.
    if self.Items[item.ID] then
        self.Items[item.ID]:IncreaseStack(1)
        sendPrintToClient(self.Owner, "Item stack increased: " .. item.Name)
    else
        self.Items[item.ID] = item
        sendPrintToClient(self.Owner, "New item added: " .. item.Name)
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
            sendPrintToClient(self.Owner, "Item removed: " .. item.Name)
        else
            sendPrintToClient(self.Owner, "Item stack decreased: " .. item.Name)
        end
        self:UpdateUI()
    end
end

function Inventory:GetItemCount()
    local count = 0 
    for _, item in pairs(self.Items) do -- Iterates through all items in the inventory.
        count = count + item.StackCount -- Adds the item's stack count to the total count.
    end
    return count -- Returns the total count of items in the inventory.
end

-- Method to update the player's inventory UI.
function Inventory:UpdateUI()
    if not self.Owner or not self.Owner.Parent then -- Validates that the player is still in the game.
        return
    end
    -- Error handling for FireClient
    local success, err = pcall(function()
        InventoryEvent:FireClient(self.Owner, self.Items) -- Sends the inventory data to the client.
    end)
    if not success then
        warn("Failed to update UI for " .. self.Owner.Name .. ": " .. err)
        sendPrintToClient(self.Owner, "Error updating inventory UI.")
    else
        sendPrintToClient(self.Owner, "Inventory UI updated.")
    end
end

-- Functions for Item Market
-- Add an item to the market
function addItemToMarket(player, item, price)
    -- Ensure the price is valid (positive number)
    if price <= 0 then
        sendPrintToClient(player, "Invalid price.")
        return
    end

    -- Check that the item is owned by the player
    if item.Owner ~= player then
        sendPrintToClient(player, "You do not own this item.")
        return
    end

    -- Proceed with adding the item to the market
    local marketListing = {
        ItemID = item.ID,
        ItemName = item.Name,
        Price = price,
        Owner = player.UserId,
        ExpirationTime = os.time() + 86400  -- 24 hours
    }

    local success, err = pcall(function()
        MarketStore:SetAsync(item.ID, marketListing)
    end)
    if success then
        sendPrintToClient(player, "Item listed for sale: " .. item.Name)
    else
        warn("Failed to list item: " .. err)
    end
end

-- Item Purchasing from the market
function purchaseItemFromMarket(player, itemID)
    local success, listing = pcall(function()
        return MarketStore:GetAsync(itemID)
    end)
    if success and listing then
        local buyerInventory = getPlayerInventory(player)
        local seller = Players:GetPlayerByUserId(listing.Owner)
        if buyerInventory:GetItemCount() < 50 then
            local item = Item.new(listing.ItemName, listing.ItemID, "Purchased from Market", 64, 100, "Common", "Miscellaneous", false)
            buyerInventory:AddItem(item)
        else
            sendPrintToClient(player, "Your inventory is full.")
        end
    else 
        sendPrintToClient(player, "Item not found on the market.")
    end
end

-- Functions for Saving and Loading Inventory
-- Save the inventory data to the DataStore for persistence.
function SaveInventory(player, inventory)
    if #saveQueue == 0 then
        table.insert(saveQueue, player.UserId)
        local success, err = pcall(function()
            InventoryStore:SetAsync(player.UserId, inventory.Items) -- Saves the inventory to the DataStore.
        end)
        if not success then
            warn("Failed to save inventory for " .. player.Name .. ": " .. err)
            sendPrintToClient(player, "Error saving inventory: " .. err)
        else
            sendPrintToClient(player, "Inventory saved successfully.")
        end
    end
end

function PeriodicSave()
    while true do
        wait(60)
        for _, userId in pairs(saveQueue) do
            local player = Players:GetPlayerByUserId(userId)
            if player then
                SaveInventory(player, getPlayerInventory(player)) -- Save the inventory to the DataStore.
            end
        end
        saveQueue = {} -- Clear the save queue after saving all players' inventories.
    end
end
spawn(PeriodicSave) -- Starts the function in a new thread.

-- Load inventory data from the DataStore and populate the player's inventory.
function LoadInventory (player, inventory)
    local success, data = pcall(function()
        return InventoryStore:GetAsync(player.UserId) -- Retrieves the inventory data from the DataStore.
    end)
    if success and data then
        for _, itemData in pairs(data) do
            -- Recreate item instances from saved data.
            local item = Item.new(itemData.Name, itemData.ID, itemData.Description, itemData.MaxStack, itemData.Durability, itemData.Rarity, itemData.Category, itemData.IsQuestItem) -- Creates a new item instance.
            item.StackCount = itemData.StackCount or 1
            inventory:AddItem(item)
        end
        sendPrintToClient(player, "Inventory loaded from the DataStore.")
    else
        sendPrintToClient(player, "Error loading inventory from the DataStore.")
    end
end

-- Retrieve or initialize a player's inventory.
function getPlayerInventory(player)
    if playerInventories[player.UserId] then
        return playerInventories[player.UserId] -- Returns the existing inventory if it exists.
    end
    local newInventory = Inventory.new(player) -- Creates a new inventory for the player.
    playerInventories[player.UserId] = newInventory
    return newInventory
end

function sendPlayerInventory(userId, page, pageSize)
    local player = Players:GetPlayerByUserId(userId)
    if player then
        local inventory = {}
        local playerInventory = getPlayerInventory(player)
        local allItems = {}

        for _, item in pairs(playerInventory.Items) do -- Adds all items to the 'allItems' table.
            table.insert(allItems, {
                ItemID = item.ID,
                ItemName = item.Name,
                StackCount = item.StackCount
            })
        end

        -- Pagination logic
        page = page or 1
        pageSize = pageSize or 20
        local startIdx = (page - 1) * pageSize + 1 -- Calculates the starting index for the current page.
        local endIdx = math.min(startIdx + pageSize - 1, #allItems) -- Ensures that endIdx is within the bounds of allItems.

        for i = startIdx, endIdx do
            table.insert(inventory, allItems[i]) -- Adds the item to the inventory for the current page.
        end

        return HTTPService:JSONEncode({ -- Returns the inventory data in JSON format.
            Page = page,
            PageSize = pageSize,
            TotalItems = #allItems,
            Inventory = inventory
        })
    else
        return HTTPService:JSONEncode({ -- Returns an error message if the player is not found.
            Error = "Player not found."
        })
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
local function OnPlayerAdded(player)
    local inventory = getPlayerInventory(player)
    if inventory then
        -- Load inventory and notify client
        LoadInventory(player, inventory)
        sendPrintToClient(player, "Inventory loaded successfully.")
    else
        sendPrintToClient(player, "Error loading inventory.")
    end
    -- Create and display the inventory UI.
    local InventoryUI = createInventoryUI(player)
    if InventoryUI then
        -- Example items added to the inventory.
        local harmingPotion = Item.new("Harming Potion", "potion001", "A potion that harms.", 10, 100, "Common", "Potion", false)
        local sword = Item.new("Sword", "sword001", "A basic sword.", 1, 50, "Common", "Weapon", false)
        inventory:AddItem(harmingPotion)
        inventory:AddItem(sword)
        -- Notify client about items added
        sendPrintToClient(player, "New items added to your inventory.")
    end
end

-- Triggered when a player leaves the game.
local function OnPlayerRemoving(player)
    local inventory = getPlayerInventory(player)
    if inventory then
        SaveInventory(player, inventory) -- Saves the inventory when the player leaves.
    end
    playerInventories[player.UserId] = nil -- Cleans up memory.
end

-- Connections
-- Connecting events to the appropriate functions.
Players.PlayerAdded:Connect(OnPlayerAdded)
Players.PlayerRemoving:Connect(OnPlayerRemoving)

-- Discord Bot showing inventory when requested for a specific user
HTTPService:PostAsync('http://localhost:8080/api/getInventory', function(request)
    local userId = tonumber(request.Query["userId"])  -- Extract user ID from the query parameters
    return getPlayerInventory(userId)  -- Fetch and return inventory data as JSON
end)
