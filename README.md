# Timescaler

SourceMod plugin to aid TAS-runs and timescaled runs. 

## What it does

This plugin will:
* Scale bhop platform's teleport times. This means if a platform will teleport you after 10 ticks on a regular timescale, it will now take 100 ticks on a 0.1 timescale 
* Fix Gravity Boosters. 
* Fix trigger_push triggers which breaks when using some TAS-tools.

## Q&A

Q: Can I use a seperate pushfix plugin while using this plugin?

A: Yes, you can do this by setting the ConVar *timescaler_use_pushfix* to 0. The plugin will still attempt to scale the triggers with this off, so players cannot abuse any glitches.

Q: This plugin makes breaks a terribly made booster, how can I disable it?

A: You can disable the plugin by typing !scalefix in the chat. Please report what map it breaks to me in a PM, and I will take a look at it.

## Contributing
Pull requests are welcome. For major changes, please open an issue first to discuss what you would like to change.