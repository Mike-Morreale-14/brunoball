# Data pipeline

The scripts in this folder download public baseball data and turn it into the tables the rest of brunoball uses.

| Script | What it does |
|---|---|
| `01_pull.R` | Downloads raw data, one CSV per source and season. |
| `02_clean.R` | Writes clean player, hitter, pitcher and league tables.  |
| `03_marcel.R` | Writes Marcel projections plus a quality-starts extension. |
| `04_scores.R` | Matches the FantasyPros ADP list to player IDs |

## What `01_pull.R` downloads

The seasons are 2023–2025 by default, set at the top of the script.

| File in `data/raw/` | Source | One row per |
|---|---|---|
| `mlb_hitting_<season>.csv` | MLB Stats API, season hitting totals, every player | Player |
| `mlb_pitching_<season>.csv` | MLB Stats API, season pitching totals, every player | Player |
| `mlb_pitcher_game_logs_<season>.csv` | MLB Stats API game logs for every pitcher with at least one start. Used later to count quality starts | Pitcher-game |
| `savant_batter_expected_<season>.csv` | Baseball Savant expected stats (xBA, xSLG, xwOBA), batters with at least 1 PA | Batter |
| `savant_batter_exit_velo_<season>.csv` | Baseball Savant exit velocity and barrels, batters with at least 1 PA | Batter |
| `savant_sprint_speed_<season>.csv` | Baseball Savant sprint speed | Runner |
| `savant_batter_discipline_<season>.csv` | Baseball Savant custom leaderboard: K%, BB%, chase rate, chase contact, zone contact, zone swing, swing rate, whiff rate, fly-ball rate | Batter |
| `savant_pitcher_measures_<season>.csv` | Baseball Savant custom leaderboard: innings, xERA, fastball velocity, whiff rate, K%, BB%, and allowed: hard-hit rate, barrel rate, ground-ball rate, zone contact, fly balls, home runs | Pitcher |
| `mlb_people_<season>.csv` | MLB Stats API player bios (birth date, bats, throws, position) for every player in that season's files | Player |
| `chadwick_register.csv` | Chadwick Bureau register: players with an MLB ID who last played in 2023 or later | Player |
| `fantasypros_adp_2026.csv` | FantasyPros 2026 ADP, copied by hand in March 2026 | Player |

Hitters and pitchers are kept in separate files. A two-way player such as Shohei Ohtani appears in both, under the same player ID.

## How to run it

1. Install R and the packages, once:
   ```r
   install.packages(c("baseballr", "dplyr", "purrr", "readr", "tidyr", "httr2", "jsonlite", "here"))
   ```
2. From the brunoball project folder, run:
   ```
   Rscript data-pipeline/01_pull.R          # all seasons set at the top of the script
   Rscript data-pipeline/02_clean.R         # then build the clean tables
   Rscript data-pipeline/03_marcel.R        # then the Marcel projections
   Rscript data-pipeline/04_scores.R        # then the draft-site inputs
   ```

**How it behaves**
- **Already-saved files are skipped.** A file is written under a temporary name and renamed only when the save has finished, so a file that exists is complete. To download a file again, delete it.
- **Any failed or empty download stops the script** with a message naming the source and season. Each request is tried up to 3 times first.
- **Pauses between requests are set at the top:** 0.5 s for the MLB Stats API and 5 s for Baseball Savant.
- **The game logs take the longest:** one request per starting pitcher, about 4–6 minutes per season.
- At the end it prints every file in `data/raw/` with its row count.

## What `02_clean.R` writes

Every table is keyed by the MLB player ID (`player_id`). The MLB Stats API tables are the base, and Savant columns are joined on player ID and season, so a player Savant doesn't list keeps the row with those columns empty. Missing values stay empty; they are never filled with zero. Percentages (`_pct` columns) run from 0 to 100; other rates are decimals.

| File | One row per | Columns (units) | Source |
|---|---|---|---|
| `players.csv` | Player | `name`, `birth_date` (YYYY-MM-DD), `bats`, `throws` (L/R/S), `position` (primary) | MLB Stats API bios |
| | | `fangraphs_id`, `bbref_id` | Chadwick register |
| `hitters.csv` | Player and season | `team` (last team if traded), `num_teams`, `g`, `pa`, `ab`, `h`, `doubles`, `triples`, `hr`, `r`, `rbi`, `sb`, `cs`, `bb`, `so`, `hbp`, `sf` (counts) | MLB Stats API |
| | | `avg`, `obp`, `slg`, `ops`, `iso`, `babip` (decimals); `k_pct`, `bb_pct` (% of PA) | Calculated from the counts |
| | | `xba`, `xslg`, `xwoba` (decimals) | Savant expected stats |
| | | `avg_ev`, `max_ev` (mph); `barrel_pct` (% of batted balls); `hard_hit_pct` (% of batted balls at 95+ mph) | Savant exit velocity and barrels |
| | | `sprint_speed` (ft/s) | Savant sprint speed |
| | | `chase_pct` (swings at pitches outside the zone), `chase_contact_pct`, `zone_contact_pct` (% of swings that made contact), `whiff_pct` (% of swings missed); `fb_pct` (% of batted balls) | Savant custom leaderboard |
| | | `age` (years, on June 30 of the season) | Calculated from birth date |
| `pitchers.csv` | Player and season | `team`, `num_teams`, `g`, `gs`, `w`, `l`, `sv`, `bs`, `hld`, `h`, `r`, `er`, `hr`, `bb`, `so`, `hbp`, `bf` (batters faced), `outs` (counts) | MLB Stats API |
| | | `ip` (innings as a true decimal: 5.2 in the API becomes 5.667); `era`, `whip`; `k_pct`, `bb_pct`, `k_bb_pct` (% of batters faced) | Calculated from the counts |
| | | `fip` (ERA scale, using that season's league constant) | Calculated, with `league_season.csv` |
| | | `qs` (starts with 18+ outs and 3 or fewer earned runs) | Calculated from the game logs |
| | | `role`: `SP` if at least half his games were starts; `CL` if saves plus blown saves are at least 15 and at least 40% of his games; otherwise `RP` | Calculated |
| | | `xera` (ERA scale), `fb_velo` (mph), `whiff_pct` (% of swings missed); allowed: `hard_hit_pct`, `barrel_pct`, `gb_pct` (% of batted balls), `zone_contact_pct` (% of swings in the zone that made contact) | Savant custom leaderboard |
| | | `hr_fb_pct` (home runs per 100 fly balls allowed, both counts from Savant) | Calculated |
| | | `age` (as for hitters) | Calculated from birth date |
| `league_season.csv` | Season | `bat_*`: league hitting totals and rates, same names and units as `hitters.csv` | Sum of `hitters.csv` |
| | | `pit_*`: league pitching totals and rates, same names and units as `pitchers.csv`, including `pit_qs` | Sum of `pitchers.csv` |
| | | `fip_constant`: league ERA minus (13 × HR + 3 × (BB + HBP) − 2 × K) / IP | Calculated |

Hitters and pitchers are separate tables, so a two-way player such as Shohei Ohtani has a row in each. Position players who pitched appear in `pitchers.csv` as `RP`.

Before writing anything, the script checks that each table has one row per player and season, that row counts match the raw files, and a few known values (Aaron Judge's 2025 PA and HR, Tarik Skubal's 2025 innings and quality starts, the 2025 league quality-start total). Any failure stops it.

## What `03_marcel.R` projects

`03_marcel.R` writes `data/projections/marcel_hitters_<season>.csv` and `marcel_pitchers_<season>.csv`. It follows Tom Tango's Marcel method: a deliberately simple projection that uses only the last three seasons, weights recent seasons more, pulls everyone toward the league average, and adjusts for age. The season to project is set at the top (`TARGET_SEASON`, 2026), and it always uses the three seasons before it.

| Step | Hitters | Pitchers |
|---|---|---|
| Season weights (most recent first) | 5 / 4 / 3 | 3 / 2 / 1 |
| Rates | Per plate appearance: 1B, 2B, 3B, HR, BB, SO, HBP, SF, SB, CS, R, RBI | Per batter faced: H, HR, BB, HBP, SO, ER, outs |
| Pulled toward the league with | 1,200 weighted PA of league-average rates | 268 weighted IP of league-average rates |
| Playing time | 0.5 × PA last season + 0.1 × PA the season before + 200 | 0.5 × IP last season + 0.1 × IP the season before + 25 (reliever) to 60 (starter), by GS/G |
| Age (target season − birth year) | +0.006 per year under 29, −0.003 per year over | Same |
| Rebaselined to | the last season's league rates | the last season's league rates |

From these it derives AB, H, AVG, OBP, SLG, OPS, ISO, K% and BB% for hitters, and IP, batters faced, GS, ERA, WHIP, K%, BB%, K−BB% and FIP for pitchers. `reliability` (0 to 1) is how much of a projection comes from the player's own record rather than the league average.

- **Who is projected:** only players with MLB time in the three seasons before the target. Rookies with no MLB history are not projected. Hitters whose primary position is pitcher are skipped (two-way players are kept), and position players who pitched are left out of the pitchers.
- **Quality starts are an extension, not part of Marcel.** QS per start uses the same 3/2/1 weights and is pulled toward the league QS rate with 50 weighted starts, then multiplied by projected starts. QS are not rebaselined. Wins and saves are not projected.
- **The age adjustment follows Tango as published:** one multiplier on every rate except playing time, so a young player's strikeouts (and a young pitcher's hits allowed) go up along with everything else.
- **Judgement calls**, each marked in the script: how part-time starters' playing time and projected starts are set. The 268 IP pitcher regression isn't stated on Tango's pages; it was fitted to the reliability column of his 2012 Marcel file using real 2009–11 innings for six pitchers (best fit 268.0).
- **Projecting a past season** to grade it needs the three seasons before it. For 2025 that means pulling 2022 first.

The script prints the projected league rates next to the last season's, the top 15 in HR, SB, pitcher strikeouts and ERA (120+ IP), and the rows for Aaron Judge, Tarik Skubal and Shohei Ohtani. It stops without writing if a player appears twice or the league rates don't match.

## What `04_scores.R` writes

`04_scores.R` builds the inputs for the draft site in [`draft-tool/data/`](../draft-tool/data/): `hitters.json`, `sp.json` and `relievers.json`, plus a copy of `weights.json`. Each file also carries the display stats the site shows: 2025 and 2023–25 numbers, the Marcel projection, key Savant measures and year-by-year history.

**The pool** is every player with a FantasyPros ADP of 300 or better.
- **Matching to MLB IDs:** names are matched after removing accents, punctuation and Jr./II-style suffixes, and only against projected players of the same kind (hitter or pitcher). That settles namesakes such as Will Smith.
- **Manual fixes:** the few rows that still need a hand fix are in [`adp_id_fixes.csv`](adp_id_fixes.csv).
- **Unscored players:** anyone with no MLB time in 2023–25, and so no Marcel projection (mostly 2026 rookies and players arriving from Japan), stays in the list with an `unscored_reason` instead of scores.
- **Shohei Ohtani:** FantasyPros lists one ADP for him, while Yahoo splits him into a hitter and a pitcher. Here he appears in both files: as a hitter at FantasyPros' ADP, and as a pitcher at an ADP of 50, set by hand (marked in the fixes file).

**Groups and percentiles**
- Hitters and starting pitchers each get percentiles, computed only among the scored players of their own group in the pool.
- A pitcher's group is his role in the most recent season (from `03_marcel.R`).
- Ties share their average rank, and each input runs exactly 0 to 100 within the group. Inputs named `low_…` are ranked so the lowest value scores highest.
- Relievers, closers included, are shown with their stats and no score. Marcel doesn't project saves.

**Scores**
tbd

## Sources

The data comes from three sources. The MLB Stats API is MLB's official data service, the one behind MLB.com and its apps; the baseballr functions that start with mlb_ call it for season stats and player birth dates; the script calls the same API directly for pitchers' game logs. Baseball Savant is MLB's public Statcast site; baseballr's statcast_leaderboards() downloads some of its leaderboards, and the plate-discipline and pitcher measures come from Savant's custom leaderboard, which baseballr doesn't cover, so the script downloads that file directly. The Chadwick Bureau register is an independent, openly licensed list that matches each player's IDs across MLB, FanGraphs, Baseball-Reference and Retrosheet; baseballr's chadwick_player_lu() downloads it.

## Data credits

MLB Stats API and Baseball Savant data © MLB Advanced Media, L.P. Player ID register from the Chadwick Baseball Bureau, used under the Open Data Commons Attribution License. Projections use the Marcel the Monkey Forecasting System by Tom Tango ([tangotiger.net/marcel](https://www.tangotiger.net/marcel/)). Average draft position (ADP) from FantasyPros ([fantasypros.com](https://www.fantasypros.com/)), 2026 preseason.

## Not included

- **Third-party projections.** FanGraphs' projections are members-only, and this project makes its own.
- **Park factors**, for now.
