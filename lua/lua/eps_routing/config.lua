EPS = EPS or {}
EPS.Config = {
  -- Total EPS power on the ship.
  -- We’ll keep our sliders under this so there’s wiggle room for spikes or emergencies.
  MaxBudget = 250,

  -- Sliders shown in the UI.
  -- Defaults add up to 210, leaving ~40 power free for reroutes when things get spicy.
  Subsystems = {
    { id = "shields",                 label = "Shields",               min = 10, max = 140, default = 60 },
    { id = "weapons",                 label = "Weapons",               min =  0, max = 120, default = 50 },
    { id = "replicators.crew",        label = "Crew Replicators",      min = 10, max =  60, default = 20 },
    { id = "sensors",                 label = "Sensors",               min =  0, max =  90, default = 25 },
    { id = "engines",                 label = "Engines",               min =  0, max = 130, default = 40 },
    { id = "replicators.industrial",  label = "Industrial Replicator", min =  0, max =  70, default = 15 },
  },
  -- Default total: 60 + 50 + 20 + 25 + 40 + 15 = 210 (under 250 on purpose)

  -- Who’s allowed to tweak power.
  -- Add ULX groups or team names here. Leave empty to let anyone adjust.
  AllowedGroups = { },

  -- Random “uh-oh” moments to keep Engineering and Ops busy.
  Spikes = {
    Enabled = true,

    -- How often spikes show up and how long they last.
    -- Tuned for the bigger 250 budget so they’re noticeable but not nonstop chaos.
    IntervalMin = 150,  -- earliest a spike can start after the last one (seconds)
    IntervalMax = 360,  -- latest a spike can start (seconds)
    DurationMin =  75,  -- shortest spike (seconds)
    DurationMax = 150,  -- longest spike (seconds)

    -- Which systems are most likely to get hit.
    -- Higher number = more likely.
    Weights = {
      shields = 1,
      weapons = 1,
      ["replicators.crew"] = 2,
      sensors = 3,
      engines = 2,
      ["replicators.industrial"] = 1,
    },

    -- Extra demand added during a spike.
    -- If a system doesn’t have enough headroom, it’ll warn in orange/red.
    ExtraDemandMin = 20,
    ExtraDemandMax = 55,

    -- Optional alert broadcast when a spike begins.
  AlertCommand = "/git",
    AlertMessage = "EPS relays need adjusting on Deck %s!",
    AlertDecks = { 1, 2, 3, 4, 5, 6, 11 },
    AlertRecoveryMessage = "EPS power allocation has been stabilized on Deck %s.",
  },

  -- Open the UI via chat or console.
  Commands = {
    Chat = "/eps",
    ConCommand = "eps_open",
  }
}
