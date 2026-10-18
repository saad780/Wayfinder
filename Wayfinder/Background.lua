-- Cooperative jobs share one budget, rather than each timer spending its own.
-- A job yields after each unit of work; yielding "frame" waits for the next
-- rendered frame (used around potentially expensive client API calls).
local _, ns = ...
local Work = ns:NewModule("Background")
local frame = CreateFrame("Frame")
local jobs, first, last = {}, nil, nil
local BUDGET_MS, MAX_STEPS = 1, 256
Work.stats = {}
frame:Hide()

function Work:Begin()
	if ns.db and ns:GetSetting("debug") then return debugprofilestop() end
end
function Work:Finish(name, started, count)
	if not started then return end
	local stat = self.stats[name] or { calls = 0, total = 0, peak = 0, units = 0 }
	local elapsed = debugprofilestop() - started
	stat.calls, stat.total, stat.peak = stat.calls + 1, stat.total + elapsed, math.max(stat.peak, elapsed)
	stat.units = stat.units + (count or 1)
	self.stats[name] = stat
end
function Work:PrintTimings()
	if not next(self.stats) then ns.Print("No timings collected. Enable /wf debug before /reload."); return end
	local names = {}
	for name in pairs(self.stats) do names[#names+1] = name end
	table.sort(names)
	for _, name in ipairs(names) do
		local s = self.stats[name]
		ns.Print(("%s: %.2f ms total, %.2f ms peak, %d calls, %d units"):format(name, s.total, s.peak, s.calls, s.units))
	end
end
local function Push(job)
	job.next = nil
	if last then last.next = job else first = job end
	last = job
end
function Work:Has(key) return jobs[key] ~= nil end
function Work:Queue(key, fn)
	if jobs[key] then return false end
	local job = { key = key, co = coroutine.create(fn) }
	jobs[key] = job
	Push(job)
	frame:SetScript("OnUpdate", function() self:Run() end)
	frame:Show()
	return true
end
function Work:Run()
	local started = debugprofilestop()
	local steps, deferred = 0, {}
	while first and steps < MAX_STEPS and debugprofilestop() - started < BUDGET_MS do
		local job = first
		first = job.next
		if not first then last = nil end
		job.next = nil
		local before = self:Begin()
		local ok, wait = coroutine.resume(job.co)
		self:Finish(job.key, before)
		steps = steps + 1
		if not ok or coroutine.status(job.co) == "dead" then
			jobs[job.key] = nil
			if not ok then geterrorhandler()(wait) end
		elseif wait == "frame" then
			deferred[#deferred+1] = job
		else
			Push(job)
		end
	end
	for _, job in ipairs(deferred) do Push(job) end
	if not first then
		frame:SetScript("OnUpdate", nil)
		frame:Hide()
	end
	if ns.db and ns:GetSetting("debug") then self:Finish("background frame", started, steps) end
end
function Work:IsIdle() return first == nil end
