--!strict
-- Feature flags that follow the roadmap. Week 1 only needs the core loop.

return {
	secretStacks = false, -- week 3
	goldenScoops = false, -- week 3
	bump = false, -- week 2
	greg = false, -- week 3
	churn = false, -- week 5

	-- Temporary diagnostics for the catch fix: the server prints rejected catch claims with the reason (at most one
	-- line per player per second). Turn off once catching is confirmed in Studio.
	debugCatch = true,
}
