# Pokémon Ash Version — mechanics prototype

Open `project.godot` in Godot 4.7 and press **F5**. The main scene is the existing Pallet Town world with the original first-person controller and simple mechanics placeholders.

## Play

- **WASD**: move; **mouse**: look; **hold Shift**: sprint.
- **Tab / Esc**: open or close the party menu, inspect HP/PP/EXP, select a healthy lead, or choose **New Game…**.
- **E** near the cyan **HEALING POINT** beside the starting position: restore party HP and PP.
- Walk north along the path beside the house, then left into the marked green **ROUTE 1 — ENCOUNTER GRASS**. Jumping and advanced movement are disabled.
- In battle, use **Fight**, **Bag**, **Pokémon**, or **Run**. Actions lock while the turn resolves. The mouse is released during battles and menus.

You start with level-5 Pikachu, Thunder Shock, Quick Attack, and 20 Poké Balls. The grass contains equally weighted Pidgey and Rattata at levels 3–5. Encounters check every two meters of grounded grass movement with a 20% chance. Battles give four meters of encounter-free grass movement before checks resume.

Lowering a wild Pokémon's HP improves catching. A successful catch keeps its exact HP and remaining PP. The party holds six Pokémon; catching is disabled when full. Defeating a wild opponent grants EXP using cubic level thresholds. Complete party defeat returns you to the start and heals the party. Run always succeeds.

## Saves

Progress saves after completed battles, healing, and lead changes to `user://pokemon_save_v1.json` through a temporary file and replacement. On Windows, Godot's default location is `%APPDATA%\Godot\app_userdata\Pokemon Ash Version\pokemon_save_v1.json`. Reloading resumes at the starting location with the saved party, inventory, HP, PP, and experience. Unfinished battles are never restored.

**New Game…** asks for confirmation and archives the previous save as a timestamped backup before resetting. An unreadable or incompatible save is preserved; the recovery dialog explains that saving stays disabled until you start a new game.

## Mechanics code and configuration

- `Mechanics/Data/`: shared species/move definitions and `.tres` resources. Instance HP, PP, levels, EXP, and IDs live in `PokemonInstance` rather than shared resources.
- `Mechanics/battle_engine.gd`: independent battle rules, injectable `RandomNumberGenerator` seed, priority/Speed order, damage, catching, switching, recoil, and outcomes.
- `Mechanics/encounter_zone.tscn`: reusable `Area3D` with chance, check distance, species weights, and level ranges. One trainer tracker prevents overlapping zones from counting movement twice.
- `Mechanics/mechanics_world.tscn`: world integration; exposed grass/healing positions and turn delay. It preserves the imported maps.
- `Mechanics/game_session.gd`: `GameSession` autoload owns party, inventory, modes, signals, and saving. The UI reads this state.
- `Mechanics/save_store.gd`: versioned save validation and replacement.

The simplified stats use Attack/Defense for all moves. Damage includes level, power, STAB, relevant Normal/Electric/Flying effectiveness, and 85–100% variation. All mechanics use local resources; no online service is required to play.

## Verification

From the project directory in PowerShell (adjust the executable path for your installation):

```powershell
$godotExe = 'D:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe'
& $godotExe --headless --path . --log-file .godot/mechanics-tests.log --script tests/run_mechanics_tests.gd -- --mechanics-test
& $godotExe --headless --path . --fixed-fps 60 --log-file .godot/world-smoke.log --script tests/run_world_smoke.gd -- --mechanics-test
```

Tests use separate files inside `.godot` and do not alter the player's save. They cover battle rules and invalid actions, PP/Struggle, capture limits and duplicate prevention, leveling, encounter distance/cooldown, save validation/replacement/recovery, and walking through the actual world into grass, catching, healing, and reloading progress.

This milestone uses colored primitive Pokémon and functional UI. Trainer battles, storage boxes, quests, evolution, status effects, new art, and animation remain outside its scope.
