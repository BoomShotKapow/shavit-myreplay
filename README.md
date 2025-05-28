<div align="center">
  <h1><code>shavit-myreplay</code></h1>
  <p>
    <strong>Personal replay plugin for Shavit's bhop timer</strong>
  </p>
  <p style="margin-bottom: 0.5ex;">
    <img
        src="https://img.shields.io/github/downloads/BoomShotKapow/shavit-myreplay/total"
    />
    <img
        src="https://img.shields.io/github/last-commit/BoomShotKapow/shavit-myreplay"
    />
    <img
        src="https://img.shields.io/github/issues/BoomShotKapow/shavit-myreplay"
    />
    <img
        src="https://img.shields.io/github/issues-closed/BoomShotKapow/shavit-myreplay"
    />
    <img
        src="https://img.shields.io/github/repo-size/BoomShotKapow/shavit-myreplay"
    />
    <img
        src="https://img.shields.io/github/workflow/status/BoomShotKapow/shavit-myreplay/Compile%20and%20release"
    />
  </p>
</div>


## Requirements ##
- SourceMod and MetaMod
- [Shavit's bhop timer](https://github.com/shavitush/bhoptimer)

## Optional Requirements ##
- [observer-mode-switch-lag-fix](https://github.com/PMArkive/random-shavit-bhoptimer-stuff/blob/main/observer-mode-switch-lag-fix.sp)

## Installation ##
1. Grab the latest release from the release page and unzip it in your SourceMod folder.
2. Restart the server or type `sm plugins load shavit-myreplay` in the console to load the plugin.

## Information ##
- The personal replays are stored in the "replayfolder" variable of shavit-replay.cfg, inside the copy folder.
- Each personal replay is saved in the format: {replayfolder}/copy/{auth}_{mapname}.replay

## Usage ##
| Command | Description |
| ----------- | ----------- |
| `sm_rewatch` | Rewatch your personal replay |
| `sm_watch` | Watch another user's personal replay |
| `sm_deletepr` | Delete your personal replay |
| `sm_preview` | Preview your unfinished replay |
| `sm_myreplay` | Displays the MyReplay customization menu |
