EPS = EPS or {}
EPS.Config = {
-- Total available EPS budget (arbitrary units). Sliders must sum <= this.
MaxBudget = 100,


-- Subsystems you want to expose in the UI
Subsystems = {
{ id = "shields", label = "Shields", min = 5, max = 60, default = 30 },
{ id = "weapons", label = "Weapons", min = 0, max = 50, default = 20 },
{ id = "lifesupport",label = "Life Support",min = 10, max = 40, default = 20 },
{ id = "sensors", label = "Sensors", min = 0, max = 35, default = 15 },
{ id = "engines", label = "Engines", min = 0, max = 50, default = 15 },
},


-- Who can adjust power? ULX groups or team names; set empty to allow all.
AllowedGroups = { "operator", "engineer", "admin", "superadmin" },


-- Random demand spikes to keep Eng/Ops busy
Spikes = {
Enabled = true,
IntervalMin = 30, -- seconds
IntervalMax = 75, -- seconds
DurationMin = 12, -- seconds
DurationMax = 25, -- seconds
-- Each spike targets one of these subsystems; weight = likelihood
Weights = {
shields = 3, weapons = 2, lifesupport = 1, sensors = 2, engines = 2
},
-- Extra demand added during a spike (UI shows orange/red if under)
ExtraDemandMin = 8,
ExtraDemandMax = 18,
},


-- Chat/console bindings
Commands = {
Chat = "/eps",
ConCommand = "eps_open",
}
}