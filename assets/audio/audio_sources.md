# Audio Sources and Integration Notes

This document records the contributor's source information and intended playback
for the audio handoff. Paths below are relative to `assets/audio/`.

## Asset handoff

| File | Intended use | Source reported by contributor | Playback |
|:--|:--|:--|:--|
| `music/atlas_theme.ogg` | World selection screen music | Contributor's own mix of multiple Pixabay recordings | Seamless loop, checked by the contributor during creation. Loop while the world selection screen is open; stop or fade when leaving. |
| `music/hcmc_battle_theme.ogg` | Ho Chi Minh City battle music | Contributor's own mix of multiple Pixabay recordings | Seamless loop, checked by the contributor during creation. Loop during the battle; stop or fade when leaving. |
| `sfx/ui/rice_gem_collect_01.wav` | Rice gem collection | Pixabay; confirmed by contributor in the current handoff | Play once per collection. |
| `sfx/ui/rice_gem_collect_02.wav` | Alternative rice gem collection sound | Pixabay; individual recording link not supplied | Alternative to variant 01; use one variant per collection. |
| `sfx/ui/shovel_remove_01.wav` | Shovel digging / plant removal | Pixabay; source link recorded below | Play once after successful removal. |
| `sfx/ui/seedbank_pick_01.wav` | Select a plant in the seed bank | Pixabay; individual recording link not supplied | Play once per selection. |
| `sfx/plants/plant_place_01.wav` | Plant placement | Pixabay; individual recording link not supplied | Play once after successful placement. |
| `sfx/enemies/enemy_eat_01.wav` | Enemy eating a plant | Pixabay | Play with each bite; stop triggering when eating ends. |
| `sfx/ui/ui_click_01.wav` | Interface button click | Pixabay | Play once per button activation. |
| `sfx/ui/battle_start.wav` | Battle opening cue accompanying "Survive the Night" | Pixabay | Play once with the opening banner, rather than with each enemy spawn. |
| `sfx/plants/lotus_shooter_shoot_01.wav` | Lotus seed firing | Pixabay; confirmed by contributor in the current handoff | Play once per shot. |

The contributor confirms the current sound effects are sourced from Pixabay.
This updates earlier AI or unrecorded-source labels. Individual links remain
unrecorded where they have not been supplied.

## Additional assets in this handoff

| File | Source | Intended playback |
|:--|:--|:--|
| `music/hoan_kiem_theme.ogg` | Custom mix by contributor; component links not supplied | Loop during Hoan Kiem battles. |
| `music/hoi_an_theme.ogg` | Custom mix by contributor; component links not supplied | Loop during Hoi An battles. |
| `sfx/ui/battle_defeat.wav` | Pixabay | Play once on defeat. |
| `sfx/ui/battle_victory.wav` | Pixabay | Play once on victory; additional asset beyond the assigned checklist. |
| `sfx/ui/wave_warning.wav` | Pixabay | Play once when a huge wave is announced. |
| `sfx/plants/plant_rotate_01.wav` | Pixabay | Play once when the player rotates a plant with R or Shift+R. |
| `sfx/plants/lotus_seed_hit_01.wav` | Pixabay | Play on lotus seed impact with an enemy. |
| `sfx/plants/sacred_rice_produce_01.wav` | Pixabay | Play when Sacred Rice produces a gem; distinct from collecting it. |
| `sfx/plants/bougainvillea_net_attack_01.wav` | Pixabay | Play with damage ticks; control repetition and overlapping voices. |
| `sfx/plants/popping_pod_attack_01.wav` | Pixabay | Play once on the pod explosion. |

The contributor reports fixing the harsh/rattling sound in the atlas music and
repairing the HCMC music loop. The source audio has not been independently
listened to during this automated handoff check.

## Pixabay source record

The contributor reports using Pixabay content for the assets identified above.
The music tracks are custom mixes by the contributor. Individual component
links have not been supplied for this handoff. Mixing does not change the
licenses of the component recordings.

- Shovel recording: [Digging with shovel](https://pixabay.com/sound-effects/film-special-effects-digging-with-shovel-63069/).
- Original downloaded shovel file: `freesound_community-digging-with-shovel-63069.mp3`.
- Shovel edit: excerpt trimmed in Audacity and exported as WAV.
- License reference supplied by the contributor: [Pixabay Content License Summary](https://pixabay.com/service/license-summary/).
- Full terms: [Pixabay Terms of Service](https://pixabay.com/service/terms/).

The license summary supplied by the contributor describes free use, optional
attribution, and modification, subject to its restrictions. It identifies the
full terms as legally binding and notes possible additional third-party rights.
"Free for use" is a source label, not a claim that a recording has no copyright.
Retain available source links and download/license records with the handoff.

## Technical handoff

- All music files were verified as Ogg Vorbis, stereo, 44,100 Hz.
- The WAV effects were verified as mono, 16-bit PCM, 44,100 Hz.
- Each audio asset has a Godot `.import` file alongside it. Include these files
  with the corresponding assets when handing over the branch.
- The contributor reports listening to the assets in the Godot editor.
- The music tracks are prepared for seamless looping. The contributor confirmed
  checking the end-to-start transitions during creation.
- Music imports have `loop=true`. WAV effects use trim and normalization,
  with looping disabled, following `docs/CONTRACTS.md#add-sound`.
- Check music/effect balance in gameplay. Plant placement is relatively quiet;
  adjust playback volume if needed after listening in context.
- Enemy eating should follow bite timing. Manage overlapping instances if a new
  bite occurs before the previous sound finishes.
- Existing audio is already integrated through `src/core/Audio.gd`. This handoff
  adds assets only; new playback events and world music assignments still need
  to be wired by the integration owner.
