-- Services
-- These are references to essential Roblox services.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DataStoreService = game:GetService("DataStoreService")

-- DataStore for storing player inventory data persistently.
local InventoryStore = DataStoreService:GetDataStore("PlayerInventory")

-- Table to store active player inventories in memory during the session.
local playerInventories = {}

-- Remote event for client-server communication about inventory updates.
local InventoryEvent = ReplicatedStorage:WaitForChild("InventoryEvent")

-- Item Class Metatable
-- Defines the structure and behavior of individual inventory items.
local Item = {}
Item.__index = Item

-- Constructor for creating a new item.
function Item.new(name, id, description, maxStack)
    local self = setmetatable({}, Item)
    self.Name = name
    self.ID = id
    self.Description = description or "No Description"
    self.MaxStack = maxStack or 64 -- Default maximum stack size is 64.
    self.StackCount = 1 -- Default stack count starts at 1.
    return self
end

-- Method to increase the item's stack count.
function Item:IncreaseStack(amount)
    self.StackCount = math.min(self.StackCount + amount, self.MaxStack)
end

-- Method to decrease the item's stack count.
function Item:DecreaseStack(amount)
    self.StackCount = math.max(self.StackCount - amount, 0)
end

-- Inventory Class Metatable
-- Represents a player's inventory, managing items and their UI updates.
local Inventory = {}
Inventory.__index = Inventory

-- Constructor for creating a new inventory for a player.
function Inventory.new(owner)
    local self = setmetatable({}, Inventory)
    self.Owner = owner -- The player who owns this inventory.
    self.Items = {} -- Table to store items by their ID.
    return self
end

-- Method to add an item to the inventory.
function Inventory:AddItem(item)
    if not item or typeof(item) ~= "table" then
        warn("Invalid item passed to AddItem")
        return
    end

    -- If the item already exists, increase its stack; otherwise, add it as new.
    if self.Items[item.ID] then
        self.Items[item.ID]:IncreaseStack(1)
    else
        self.Items[item.ID] = item
    end

    -- Update the inventory UI to reflect the changes.
    self:UpdateUI()
end

-- Method to remove an item from the inventory.
function Inventory:RemoveItem(itemID)
    if self.Items[itemID] then
        self.Items[itemID]:DecreaseStack(1)
        -- Remove the item if its stack count reaches zero.
        if self.Items[itemID].StackCount <= 0 then
            self.Items[itemID] = nil
        end
        self:UpdateUI()
    end
end

-- Method to update the player's inventory UI.
function Inventory:UpdateUI()
    if not self.Owner or not self.Owner.Parent then
        return
    end
    -- Error handling for FireClient
    local success, err = pcall(function()
        InventoryEvent:FireClient(self.Owner, self.Items)
    end)
    if not success then
        warn("Failed to update UI for " .. self.Owner.Name .. ": " .. err)
    end
end

-- Functions for Saving and Loading Inventory
-- Save the inventory data to the DataStore for persistence.
function SaveInventory(player, inventory)
    local success, err = pcall(function()
        InventoryStore:SetAsync(player.UserId, inventory.Items)
    end)
    if not success then
        warn("Failed to save inventory for " .. player.Name .. ": " .. err)
    end
end

-- Load inventory data from the DataStore and populate the player's inventory.
function LoadInventory(player, inventory)
    local success, data = pcall(function()
        return InventoryStore:GetAsync(player.UserId)
    end)
    if success and data then
        for _, itemData in pairs(data) do
            -- Recreate item instances from saved data.
            local item = Item.new(itemData.Name, itemData.ID, itemData.Description, itemData.MaxStack)
            item.StackCount = itemData.StackCount or 1
            inventory:AddItem(item)
        end
    end
end

-- Retrieve or initialize a player's inventory.
function getPlayerInventory(player)
    if playerInventories[player.UserId] then
        return playerInventories[player.UserId]
    end
    local newInventory = Inventory.new(player)
    playerInventories[player.UserId] = newInventory
    return newInventory
end

-- Function to create the inventory UI for the player.
local function createInventoryUI(player)
    local PlayerGui = player:WaitForChild("PlayerGui")
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
        LoadInventory(player, inventory)
    end

    -- Create and display the inventory UI.
    local InventoryUI = createInventoryUI(player)
    if InventoryUI then
        -- Example items added to the inventory.
        local harmingPotion = Item.new("Harming Potion", "potion001", "A potion that harms.", 10)
        local sword = Item.new("Sword", "sword001", "A basic sword.", 1)
        inventory:AddItem(harmingPotion)
        inventory:AddItem(sword)
    end
end

-- Triggered when a player leaves the game.
local function OnPlayerRemoving(player)
    local inventory = getPlayerInventory(player)
    if inventory then
        SaveInventory(player, inventory)
    end
    playerInventories[player.UserId] = nil -- Clean up memory.
end

-- Connections
-- Connecting events to the appropriate functions.
Players.PlayerAdded:Connect(OnPlayerAdded)
Players.PlayerRemoving:Connect(OnPlayerRemoving)
