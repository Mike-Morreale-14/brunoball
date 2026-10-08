# 02_clean.R: builds clean player, hitter, pitcher and league tables in data/clean/ from data/raw/.
# Run from the project folder after 01_pull.R: Rscript data-pipeline/02_clean.R


# ---- Settings ----------------------------------------------------------------

SEASONS <- 2023:2025 # seasons to clean
AGE_DATE <- "06-30" # age is measured on this month-day of each season

QS_MIN_OUTS <- 18 # quality start: at least this many outs...
QS_MAX_ER <- 3 # ...and no more than this many earned runs

STARTER_SHARE <- 0.5 # starter: at least this share of games were starts
CLOSER_MIN_CHANCES <- 15 # closer: at least this many saves plus blown saves...
CLOSER_SHARE <- 0.4 # ...making up at least this share of games


# ---- Setup -------------------------------------------------------------------

suppressPackageStartupMessages({
  library(dplyr)
  library(purrr)
  library(readr)
  library(here)
})

message("Working directory: ", getwd())

# setwd("path/to/brunoball")  # only needed if you didn't open brunoball.Rproj

here::i_am("data-pipeline/02_clean.R")
dir.create(here("data", "clean"), showWarnings = FALSE)

# Raw column name for each clean column; the clean names are the ones written out.
HITTING_COLS <- c(
  g = "games_played", pa = "plate_appearances", ab = "at_bats", h = "hits",
  doubles = "doubles", triples = "triples", hr = "home_runs", r = "runs", rbi = "rbi",
  sb = "stolen_bases", cs = "caught_stealing", bb = "base_on_balls", so = "strike_outs",
  hbp = "hit_by_pitch", sf = "sac_flies"
)
PITCHING_COLS <- c(
  g = "games_pitched", gs = "games_started", w = "wins", l = "losses", sv = "saves",
  bs = "blown_saves", hld = "holds", h = "hits", r = "runs", er = "earned_runs",
  hr = "home_runs", bb = "base_on_balls", so = "strike_outs", hbp = "hit_batsmen",
  bf = "batters_faced", outs = "outs"
)


# ---- Helpers -----------------------------------------------------------------

# Same file naming as 01_pull.R, so the two scripts always agree on where a source lives.
raw_path <- function(source, season = NULL) {
  here("data", "raw", paste0(paste(c(source, season), collapse = "_"), ".csv"))
}

# Everything is read as text, so each column's type is set on purpose rather than guessed.
read_raw <- function(source, season = NULL) {
  path <- raw_path(source, season)
  if (!file.exists(path)) stop("Missing raw file: ", basename(path), ". Run 01_pull.R first.")
  read_csv(path, col_types = cols(.default = col_character()), progress = FALSE)
}

# A rate with nothing to divide by is unknown, not zero or infinite.
safe_div <- function(num, den) if_else(den > 0, num / den, NA_real_)

# "5.2" innings means 5 and 2/3, so the digit after the point counts thirds.
ip_from_thirds <- function(x) {
  x <- as.numeric(x)
  trunc(x) + round((x - trunc(x)) * 10) / 3
}

# Ages must be comparable across seasons, so everyone is measured on the same day of the year.
age_on <- function(birth_date, season) {
  season - as.integer(format(birth_date, "%Y")) - (format(birth_date, "%m-%d") > AGE_DATE)
}

# Rates are recomputed from the totals, so players and the league use exactly the same formulas.
add_hitting_rates <- function(df) {
  df |>
    mutate(
      avg = safe_div(h, ab),
      obp = safe_div(h + bb + hbp, ab + bb + hbp + sf),
      slg = safe_div(h + doubles + 2 * triples + 3 * hr, ab),
      ops = obp + slg,
      iso = slg - avg,
      babip = safe_div(h - hr, ab - so - hr + sf),
      k_pct = 100 * safe_div(so, pa),
      bb_pct = 100 * safe_div(bb, pa)
    )
}

# FIP needs the league constant, so it is added separately once the league table exists.
add_pitching_rates <- function(df) {
  df |>
    mutate(
      ip = outs / 3,
      era = 9 * safe_div(er, ip),
      whip = safe_div(bb + h, ip),
      k_pct = 100 * safe_div(so, bf),
      bb_pct = 100 * safe_div(bb, bf),
      k_bb_pct = k_pct - bb_pct
    )
}

# Savant files carry a name column whose header can hide a stray character, so only the ID and
# the wanted columns are kept, and names are never used to match.
read_savant <- function(source, season, cols) {
  df <- read_raw(source, season) |>
    select(player_id, all_of(cols)) |>
    mutate(player_id = as.integer(player_id), across(all_of(names(cols)), as.numeric))
  if (anyDuplicated(df$player_id)) stop(source, " ", season, " has duplicate player IDs.")
  df
}

# Unmatched players are normal (Savant skips some), but the count should be visible on every run.
join_savant <- function(base, savant, source) {
  unmatched <- sum(!paste(base$player_id, base$season) %in%
    paste(savant$player_id, savant$season))
  message(sprintf("  %-26s %4d of %4d rows found no match", source, unmatched, nrow(base)))
  left_join(base, savant, by = c("player_id", "season"))
}

# Savant reports each source per season, so all seasons are stacked before joining.
savant_all_seasons <- function(source, cols) {
  map(SEASONS, \(s) mutate(read_savant(source, s, cols), season = s)) |> bind_rows()
}


# ---- Players -----------------------------------------------------------------

# A player's bio can appear in several seasons; the latest season's copy is kept.
people <- map(rev(SEASONS), \(s) read_raw("mlb_people", s)) |>
  bind_rows() |>
  distinct(id, .keep_all = TRUE)

chadwick <- read_raw("chadwick_register") |>
  transmute(
    player_id = as.integer(key_mlbam), fangraphs_id = key_fangraphs, bbref_id = key_bbref
  )

players <- people |>
  transmute(
    player_id = as.integer(id), name = full_name, birth_date = as.Date(birth_date),
    bats = bat_side_code, throws = pitch_hand_code, position = primary_position_abbreviation
  ) |>
  left_join(chadwick, by = "player_id") |>
  arrange(player_id)


# ---- Hitters -----------------------------------------------------------------

mlb_hitting <- map(SEASONS, \(s) read_raw("mlb_hitting", s)) |>
  bind_rows() |>
  select(player_id, season, team = team_name, num_teams, all_of(HITTING_COLS)) |>
  mutate(across(c(player_id, season, num_teams, all_of(names(HITTING_COLS))), as.integer))

message("Hitters:")

hitters <- mlb_hitting |>
  add_hitting_rates() |>
  join_savant(
    savant_all_seasons(
      "savant_batter_expected", c(xba = "est_ba", xslg = "est_slg", xwoba = "est_woba")
    ),
    "savant_batter_expected"
  ) |>
  join_savant(
    savant_all_seasons("savant_batter_exit_velo", c(
      avg_ev = "avg_hit_speed", max_ev = "max_hit_speed",
      barrel_pct = "brl_percent", hard_hit_pct = "ev95percent"
    )),
    "savant_batter_exit_velo"
  ) |>
  join_savant(
    savant_all_seasons("savant_sprint_speed", c(sprint_speed = "sprint_speed")),
    "savant_sprint_speed"
  ) |>
  join_savant(
    savant_all_seasons("savant_batter_discipline", c(
      chase_pct = "oz_swing_percent", chase_contact_pct = "oz_contact_percent",
      zone_contact_pct = "iz_contact_percent", whiff_pct = "whiff_percent",
      fb_pct = "flyballs_percent"
    )),
    "savant_batter_discipline"
  ) |>
  left_join(select(players, player_id, birth_date), by = "player_id") |>
  mutate(age = age_on(birth_date, season), .after = team) |>
  select(-birth_date) |>
  arrange(season, player_id)


# ---- Pitchers ----------------------------------------------------------------

mlb_pitching <- map(SEASONS, \(s) read_raw("mlb_pitching", s)) |>
  bind_rows() |>
  select(player_id, season, team = team_name, num_teams, innings_pitched, all_of(PITCHING_COLS)) |>
  mutate(
    across(c(player_id, season, num_teams, all_of(names(PITCHING_COLS))), as.integer),
    ip_thirds = ip_from_thirds(innings_pitched)
  )

message("Pitchers:")
message(
  "  rows where innings (from thirds) disagree with outs: ",
  sum(round(mlb_pitching$ip_thirds * 3) != mlb_pitching$outs)
)

# Only starts can be quality starts, and the season file has no QS column.
quality_starts <- map(SEASONS, \(s) read_raw("mlb_pitcher_game_logs", s)) |>
  bind_rows() |>
  filter(stat.gamesStarted == "1") |>
  transmute(
    player_id = as.integer(player.id), season = as.integer(season),
    qs = as.integer(stat.outs) >= QS_MIN_OUTS & as.integer(stat.earnedRuns) <= QS_MAX_ER
  ) |>
  count(player_id, season, wt = qs, name = "qs")

pitchers_base <- mlb_pitching |>
  select(-innings_pitched, -ip_thirds) |>
  add_pitching_rates() |>
  left_join(quality_starts, by = c("player_id", "season")) |>
  # No starts means truly zero quality starts; a starter missing from the logs stays NA.
  mutate(
    qs = if_else(gs == 0, 0L, qs),
    role = case_when(
      gs >= STARTER_SHARE * g ~ "SP",
      sv + bs >= CLOSER_MIN_CHANCES & sv + bs >= CLOSER_SHARE * g ~ "CL",
      .default = "RP"
    )
  )


# ---- League by season --------------------------------------------------------

league_hitting <- hitters |>
  group_by(season) |>
  summarise(across(all_of(names(HITTING_COLS)[-1]), sum)) |>
  add_hitting_rates() |>
  rename_with(\(x) paste0("bat_", x), -season)

league_pitching <- pitchers_base |>
  group_by(season) |>
  summarise(across(c(all_of(names(PITCHING_COLS)[-1]), qs), sum)) |>
  add_pitching_rates() |>
  # FIP's constant puts it on the ERA scale for that season's run environment.
  mutate(fip_constant = era - (13 * hr + 3 * (bb + hbp) - 2 * so) / ip) |>
  rename_with(\(x) paste0("pit_", x), -c(season, fip_constant))

league_season <- left_join(league_hitting, league_pitching, by = "season") |>
  relocate(fip_constant, .after = season)

pitchers <- pitchers_base |>
  left_join(select(league_season, season, fip_constant), by = "season") |>
  mutate(
    fip = safe_div(13 * hr + 3 * (bb + hbp) - 2 * so, ip) + fip_constant,
    .after = k_bb_pct
  ) |>
  select(-fip_constant) |>
  join_savant(
    savant_all_seasons("savant_pitcher_measures", c(
      xera = "xera", fb_velo = "fastball_avg_speed", whiff_pct = "whiff_percent",
      hard_hit_pct = "hard_hit_percent", barrel_pct = "barrel_batted_rate",
      gb_pct = "groundballs_percent", zone_contact_pct = "iz_contact_percent",
      sc_flyballs = "flyballs", sc_hr = "home_run"
    )),
    "savant_pitcher_measures"
  ) |>
  # HR and fly balls both from Savant, so the ratio uses one source's batted-ball labels.
  mutate(hr_fb_pct = 100 * safe_div(sc_hr, sc_flyballs), .keep = "unused") |>
  left_join(select(players, player_id, birth_date), by = "player_id") |>
  mutate(age = age_on(birth_date, season), .after = team) |>
  relocate(role, .after = age) |>
  relocate(ip, .before = outs) |>
  select(-birth_date) |>
  arrange(season, player_id)


# ---- Checks ------------------------------------------------------------------

# Every check is printed, and any failure stops the script before a file is written.
check <- function(label, ok) {
  message(if (isTRUE(ok)) "  PASS  " else "  FAIL  ", label)
  isTRUE(ok)
}

raw_rows <- \(source) sum(map_int(SEASONS, \(s) nrow(read_raw(source, s))))
judge <- filter(hitters, player_id == 592450, season == 2025)
skubal <- filter(pitchers, player_id == 669373, season == 2025)

message("Checks:")
passed <- c(
  check("one row per player in players", !anyDuplicated(players$player_id)),
  check("one row per player and season in hitters", !anyDuplicated(hitters[1:2])),
  check("one row per player and season in pitchers", !anyDuplicated(pitchers[1:2])),
  check("one row per season in league_season", !anyDuplicated(league_season$season)),
  check("every hitter and pitcher is in players", all(
    c(hitters$player_id, pitchers$player_id) %in% players$player_id
  )),
  check("Aaron Judge 2025: 679 PA and 53 HR", judge$pa == 679 && judge$hr == 53),
  check(
    "Tarik Skubal 2025: 195 1/3 innings and 21 quality starts",
    isTRUE(all.equal(skubal$ip, 195 + 1 / 3)) && skubal$qs == 21
  ),
  check(
    "League quality starts in 2025: 1,676",
    league_season$pit_qs[league_season$season == 2025] == 1676
  ),
  check("hitters rows match raw MLB hitting rows", nrow(hitters) == raw_rows("mlb_hitting")),
  check("pitchers rows match raw MLB pitching rows", nrow(pitchers) == raw_rows("mlb_pitching")),
  check("players rows match unique IDs in raw bios", nrow(players) == nrow(people))
)
if (!all(passed)) stop("Some checks failed; nothing was written.", call. = FALSE)


# ---- Write -------------------------------------------------------------------

outputs <- list(
  players = players, hitters = hitters, pitchers = pitchers, league_season = league_season
)
iwalk(outputs, \(df, name) write_csv(df, here("data", "clean", paste0(name, ".csv")), na = ""))

print(data.frame(
  file = paste0(names(outputs), ".csv"),
  rows = map_int(outputs, nrow),
  columns = map_int(outputs, ncol)
), row.names = FALSE)
