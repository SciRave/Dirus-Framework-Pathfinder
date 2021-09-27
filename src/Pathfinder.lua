local PathfindingService = game:GetService("PathfindingService")

local Heartbeat = game:GetService("RunService").Heartbeat

local ZERO = Vector3.new()

local NoY = Vector3.new(1,0,1) 

local Pathfinder = {}
Pathfinder.__index = Pathfinder

function Pathfinder.new(Humanoid: Humanoid, AgentParamaters: {[string]: any}?)
	
	local Object = setmetatable({}, Pathfinder)
				
	Object.Path = PathfindingService:CreatePath(AgentParamaters)
	
	Object.DoneCalculation = true
	
	Object.Waypoint = 1
	
	Object.GoalWaypoint = 1
	
	Object.ReachedDestination = true
	
	Object.Humanoid = Humanoid
		
	Object.LastCalculation = 0
	
	Object.TimeMultiplier = 0.2
	
	Object.MinTime = 0
	
	Object.MaxTime = 8
	
	Object.MaxDistance = math.huge
	
	Object.ErrorRange = 0
	
	Object.AlwaysMove = false
		
	return Object
	
end

function Pathfinder:HeightOffGround()
	
	local Humanoid = self.Humanoid

	local HeightModifier = 0

	if Humanoid.RigType == Enum.HumanoidRigType.R6 then

		for _, Child in next, Humanoid.RootPart.Parent:GetChildren() do

			if Humanoid:GetLimb(Child) == Enum.Limb.LeftLeg then

				HeightModifier = Child.Size.Y

				break
			end
		end

	end
	
	return HeightModifier + Humanoid.RootPart.Size.Y/2 + Humanoid.HipHeight
	
end

function Pathfinder:GetDifference(Node: Vector3)
	return (Node - self.Humanoid.RootPart.Position)*NoY
end

function Pathfinder:AtNode(Node: Vector3, TimeDelta: number): boolean
	
	local HeightDiff = Node.Y + self:HeightOffGround() - self.Humanoid.RootPart.Position.Y
		
	return (self:GetDifference(Node) + Vector3.new(0, HeightDiff, 0)).Magnitude <= TimeDelta*self.Humanoid.WalkSpeed*2
	
end

function Pathfinder:WithinErrorRange(Node: Vector3): boolean
	return (self.Humanoid.RootPart.Position - Node).Magnitude <= self.ErrorRange
end

function Pathfinder:OutsideMaxDistance(Node: Vector3)
	return (Node - self.Humanoid.RootPart.Position).Magnitude > self.MaxDistance
end

function Pathfinder:Refresh()

	self.Goal = nil

	self.LastGoal = nil

	self.Waypoint = 1

	self.GoalWaypoint = 1

	self.ReachedDestination = true

	self.LastCalculation = 0

end

function Pathfinder:InvalidGoal()
	
	if not self.Goal or self:OutsideMaxDistance(self.Goal) then

		self:Refresh()

		return true
	end
	
end

function Pathfinder:Compute()
	
	local Path = self.Path
		
	pcall(Path.ComputeAsync, Path, self.Humanoid.RootPart.Position, self.Goal)
	
	self.Waypoint = 1
	
	if self.Goal and Path.Status == Enum.PathStatus.Success then
		
		local success, result = pcall(function()
			return Path:GetWaypoints()
		end)		
		
		if success then
			
			self.GoalWaypoint = #result
			
		else
						
			self.GoalWaypoint = 1
			
		end
		
		
	else
		
		self.GoalWaypoint = 1
		
	end
	
	self.DoneCalculation = true
	
end

function Pathfinder:Calculate()
	
	self.LastCalculation = tick()
	
	self.DoneCalculation = false
	
	task.spawn(Pathfinder.Compute, self)
	
end

function Pathfinder:Pathfind()
	
	local Difference = tick() - self.LastCalculation
	
	local Time = self.TimeMultiplier*(self.Goal - self.Humanoid.RootPart.Position).Magnitude
	
	if Difference > self.MinTime then
		
		if Difference > self.MaxTime or Difference*self.Humanoid.WalkSpeed >= Time then
			self:Calculate()
		end
		
	end
	
end


function Pathfinder:RunLogic(TimeDelta: number)
	
	local Humanoid = self.Humanoid
	
	if not Humanoid or not Humanoid.RootPart then return end
	
	if self:InvalidGoal() then return end
		
	local Waypoints = self.Path:GetWaypoints()
	
	self.ReachedDestination = false
	
	if self:WithinErrorRange(self.Goal) then
		
		Humanoid:MoveTo(Humanoid.RootPart.Position)
		
		self.ReachedDestination = true
	
	elseif self.Waypoint < self.GoalWaypoint then
		
		local NextWaypoint = Waypoints[self.Waypoint + 1]
						
		while NextWaypoint and self:AtNode(NextWaypoint.Position, TimeDelta) do
																		
			self.Waypoint = self.Waypoint + 1
			
			NextWaypoint = Waypoints[self.Waypoint + 1]
			
		end
		
		if NextWaypoint then	
							
			if NextWaypoint.Action == Enum.PathWaypointAction.Jump then
				Humanoid.Jump = true
			end
			
			if self.Waypoint + 1 == #Waypoints then
				
				Humanoid:MoveTo(self.Goal)
								
			else
			
				Humanoid:MoveTo(NextWaypoint.Position)
								
			end
			
		end
		
	elseif self.AlwaysMove then
		
		Humanoid:MoveTo(Humanoid.RootPart.Position)
		
		Humanoid:Move(self:GetDifference(self.Goal))
		
	end
	
	if self.DoneCalculation then
		
		if not self.ReachedDestination or self.LastGoal ~= self.Goal then
			
			self:Pathfind()
			
		end
		
		self.LastGoal = self.Goal
		
	end
	
end

function Pathfinder:InstantApplyGoal(Goal: Vector3)
	
	self.Goal = Goal
	
	self.LastCalculation = 0
	
	if self.DoneCalculation then
		self:Calculate()
	end
	
end

function Pathfinder:RemoveGoal()
	
	self:Refresh()
	
	local Humanoid = self.Humanoid

	if not Humanoid or not Humanoid.RootPart then return end
	
	Humanoid:MoveTo(Humanoid.RootPart.Position)
	
end

function Pathfinder:Start(Goal: Vector3?)
	
	assert(not self.Connection, "Pathfinder object is already active!")
	
	self.Connection = Heartbeat:Connect(function(td)
		self:RunLogic(td)
	end)
	
	self.BlockedConnection = self.Path.Blocked:Connect(function(Node)
		
		if self.Goal and not self.ReachedDestination then
		
			if Node > self.Waypoint and Node <= self.GoalWaypoint then
				
				self.GoalWaypoint = Node - 1
				
				self:InstantApplyGoal(self.Goal)
				
			end
				
		end
		
	end)
	
	self.MovingConnection = self.Humanoid.MoveToFinished:Connect(function(Done)	
		
		local Waypoints = self.Path:GetWaypoints()
		
		local Len = #Waypoints
		
		if Len > 0 and Len > self.Waypoint and Waypoints[self.Waypoint + 1].Position == self.Humanoid.WalkToPoint then
			
			if Done then
				
				self.Waypoint = self.Waypoint + 1
				
			elseif self.Goal then
				
				self:InstantApplyGoal(self.Goal)
				
			end
			
		end
					
	end)
	
	if Goal then
		self:InstantApplyGoal(Goal)
	end
	
end

function Pathfinder:Stop()
	
	assert(self.Connection, "Pathfinder object is not active!")
	
	self.Connection:Disconnect()
	
	self.Connection = nil
	
	self.BlockedConnection:Disconnect()
	
	self.BlockedConnection = nil
	
	self.MovingConnection:Disconnect()
	
	self.MovingConnection = nil
	
	self:RemoveGoal()
	
end

return Pathfinder
