-- Services
-- References to Roblox services used in this script.
local Players = game:GetService("Players") -- Manages player-related events and actions.
local ReplicatedStorage = game:GetService("ReplicatedStorage") -- Shared storage for remote events and modules.
local DataStoreService = game:GetService("DataStoreService") -- Enables persistent data storage for players.

-- DataStore for storing player inventory data persistently.
local InventoryStore = DataStoreService:GetDataStore("PlayerInventory")

-- Table to store active player inventories in memory during the session.
local playerInventories = {}

-- Remote event for client-server communication about inventory updates.
local InventoryEvent = ReplicatedStorage:WaitForChild("InventoryEvent") -- Used to send inventory updates to clients.
local PrintEvent = ReplicatedStorage:WaitForChild("PrintEvent") -- Used to send debug messages or notifications to clients.

-- Client Logging (HD App Reader Purposes)
-- Sends messages to the client for debugging or notifications.
function sendPrintToClient(player, message)
    local success, err = pcall(function()
        PrintEvent:FireClient(player, message) -- Sends the message to the client using the PrintEvent.
    end)
    if not success then
        warn("Failed to send print message to client: " .. err) -- Logs a warning if the operation fails.
    end
end

-- Item Class Metatable
-- Defines the structure and behavior of individual inventory items.
local Item = {}
Item.__index = Item

-- Constructor for creating a new item.
function Item.new(name, id, description, maxStack)
    local self = setmetatable({}, Item) -- Creates a new table and sets its metatable to Item.
    self.Name = name -- Name of the item.
    self.ID = id -- Unique identifier for the item.
    self.Description = description or "No Description" -- Description of the item, defaults to "No Description".
    self.MaxStack = maxStack or 64 -- Maximum number of items that can stack, defaults to 64.
    self.StackCount = 1 -- Number of items in the stack, defaults to 1.
    return self
end

-- Method to increase the item's stack count.
function Item:IncreaseStack(amount)
    self.StackCount = math.min(self.StackCount + amount, self.MaxStack) -- Ensures stack count does not exceed MaxStack.
end

-- Method to decrease the item's stack count.
function Item:DecreaseStack(amount)
    self.StackCount = math.max(self.StackCount - amount, 0) -- Ensures stack count does not go below 0.
end

-- Inventory Class Metatable
-- Represents a player's inventory, managing items and their UI updates.
local Inventory = {}
Inventory.__index = Inventory

-- Constructor for creating a new inventory for a player.
function Inventory.new(owner)
    local self = setmetatable({}, Inventory) -- Creates a new table and sets its metatable to Inventory.
    self.Owner = owner -- The player who owns this inventory.
    self.Items = {} -- Table to store items by their ID.
    return self
end

-- Method to add an item to the inventory.
function Inventory:AddItem(item)
    if not item or typeof(item) ~= "table" then -- Validates that the item is a table.
        warn("Invalid item passed to AddItem")
        sendPrintToClient(self.Owner, "Failed to add item: Invalid item.")
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

-- Functions for Saving and Loading Inventory
-- Save the inventory data to the DataStore for persistence.
function SaveInventory(player, inventory)
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

-- Load inventory data from the DataStore and populate the player's inventory.
function LoadInventory(player, inventory)
    local success, data = pcall(function()
        return InventoryStore:GetAsync(player.UserId) -- Retrieves the inventory data from the DataStore.
    end)
    if success and data then
        for _, itemData in pairs(data) do
            -- Recreate item instances from saved data.
            local item = Item.new(itemData.Name, itemData.ID, itemData.Description, itemData.MaxStack)
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
        local harmingPotion = Item.new("Harming Potion", "potion001", "A potion that harms.", 10)
        local sword = Item.new("Sword", "sword001", "A basic sword.", 1)
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
