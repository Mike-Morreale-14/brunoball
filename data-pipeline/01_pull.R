# 01_pull.R: downloads raw MLB Stats API, Baseball Savant and Chadwick data into data/raw/, one CSV per source and season, unedited.
# Run from the project folder: Rscript data-pipeline/01_pull.R  (add years, e.g. 2025, to pull only those seasons)
# rm(list=ls())

# ---- Settings ----------------------------------------------------------------

SEASONS <- 2023:2025 # seasons to download
CHADWICK_MIN_LAST_PLAYED <- 2023 # oldest "last MLB season" kept from the register

MLB_PAUSE <- 0.5 # seconds between MLB Stats API requests
SAVANT_PAUSE <- 5 # seconds between Baseball Savant requests

MAX_TRIES <- 3 # attempts per request before stopping
RETRY_WAIT <- 20 # seconds between attempts
PEOPLE_BATCH <- 100 # player IDs per bio request

# Years typed after the script name replace SEASONS for this run only.
cli_seasons <- commandArgs(trailingOnly = TRUE)
if (length(cli_seasons) > 0) {
  SEASONS <- suppressWarnings(as.integer(cli_seasons))
  if (anyNA(SEASONS)) stop("Seasons after the script name must be years, e.g. 2025")
}


# ---- Setup -------------------------------------------------------------------

suppressPackageStartupMessages({
  library(baseballr)
  library(dplyr)
  library(purrr)
  library(readr)
  library(httr2)
  library(jsonlite)
  library(here)
})

message("Working directory: ", getwd())

# setwd("path/to/brunoball")  # only needed if you didn't open brunoball.Rproj

here::i_am("data-pipeline/01_pull.R")
dir.create(here("data", "raw"), recursive = TRUE, showWarnings = FALSE)

SAVANT_BATTER_SELECTIONS <- paste(
  c(
    "pa", "k_percent", "bb_percent", "oz_swing_percent", "oz_contact_percent",
    "iz_contact_percent", "z_swing_percent", "swing_percent", "whiff_percent",
    "flyballs_percent"
  ),
  collapse = ","
)
SAVANT_PITCHER_SELECTIONS <- paste(
  c(
    "pa", "p_formatted_ip", "xera", "fastball_avg_speed", "whiff_percent",
    "k_percent", "bb_percent", "hard_hit_percent", "barrel_batted_rate",
    "groundballs_percent", "iz_contact_percent", "flyballs", "home_run"
  ),
  collapse = ","
)


# ---- Helpers -----------------------------------------------------------------

# Keeps file naming in one place, so every step agrees on where a source's file lives.
raw_path <- function(source, season = NULL) {
  here("data", "raw", paste0(paste(c(source, season), collapse = "_"), ".csv"))
}

# Raw files are read back as text so nothing is reinterpreted on the way in.
read_raw <- function(path) read_csv(path, col_types = cols(.default = col_character()))

# baseballr functions hide the web request, so retries wrap the whole function call.
retrying <- function(f) {
  insistently(f, rate = rate_delay(RETRY_WAIT, max_times = MAX_TRIES), quiet = FALSE)
}

# Direct requests get httr2's built-in retries, timeout and HTTP-error handling.
get_text <- function(url, ...) {
  request(url) |>
    req_url_query(...) |>
    req_user_agent("brunoball (github.com/Mike-Morreale-14/brunoball)") |>
    req_timeout(120) |>
    req_retry(max_tries = MAX_TRIES, retry_on_failure = TRUE, backoff = \(i) RETRY_WAIT) |>
    req_perform() |>
    resp_body_string()
}

# An empty or reshaped response usually means the source changed, and must never be saved as data.
check_result <- function(df, name, needed_cols) {
  if (!is.data.frame(df) || nrow(df) == 0) stop(name, " returned no rows.", call. = FALSE)
  missing <- setdiff(needed_cols, names(df))
  if (length(missing) > 0) stop(name, " is missing columns: ", toString(missing), call. = FALSE)
}

# A CSV cell can only hold text, so list columns are stored as JSON.
lists_to_json <- function(df) {
  to_json <- \(x) as.character(toJSON(x, auto_unbox = TRUE))
  mutate(as.data.frame(df), across(where(is.list), \(col) map_chr(col, to_json)))
}

# Every source follows the same skip, download, check, save and pause steps; this keeps them identical.
pull_to_file <- function(path, pause, needed_cols, fetch) {
  name <- basename(path)
  if (file.exists(path)) {
    message("  skip  ", name, " (already saved)")
    return(invisible(NULL))
  }
  df <- tryCatch(
    fetch(),
    error = \(e) stop("PULL FAILED: ", name, ": ", conditionMessage(e), call. = FALSE)
  )
  check_result(df, paste("PULL FAILED:", name), needed_cols)
  df <- lists_to_json(df)
  # Written under a temporary name and renamed when complete, so the skip check can trust any file it finds.
  tmp <- paste0(path, ".partial")
  write_csv(df, tmp, na = "")
  if (!file.rename(tmp, path)) stop("Could not save ", path, call. = FALSE)
  message("  saved ", name, " (", format(nrow(df), big.mark = ","), " rows)")
  Sys.sleep(pause)
}

# ---- Sources -----------------------------------------------------------------

# A partial player list looks like valid data, so it's checked against the API's own count.
fetch_mlb_season <- function(group, season) {
  df <- retrying(mlb_stats)(
    stat_type = "season", stat_group = group, season = season,
    player_pool = "All", limit = 5000
  )
  check_result(df, paste("MLB", group, season), "total_splits")
  if (!identical(as.integer(unique(df$total_splits)), nrow(df))) {
    stop(sprintf(
      "got %d rows but the API reports %s players",
      nrow(df), toString(unique(df$total_splits))
    ))
  }
  df
}

# Quality starts need per-game outs and earned runs, and baseballr has no game-log function.
fetch_starter_game_logs <- function(season) {
  pitching <- read_raw(raw_path("mlb_pitching", season))
  starters <- unique(pitching$player_id[which(as.integer(pitching$games_started) >= 1)])
  message("  ", length(starters), " pitchers with at least one start")
  map(starters, \(id) {
    Sys.sleep(MLB_PAUSE)
    json <- get_text(
      paste0("https://statsapi.mlb.com/api/v1/people/", id, "/stats"),
      stats = "gameLog", season = season, group = "pitching", gameType = "R"
    )
    games <- fromJSON(json, flatten = TRUE)$stats$splits[[1]]
    if (NROW(games) == 0) stop("no games returned for pitcher ", id)
    games
  }, .progress = "game logs") |>
    bind_rows()
}

# Savant's custom leaderboard has the discipline and pitcher measures; baseballr doesn't cover it.
fetch_savant_custom <- function(type, selections, season) {
  csv <- get_text(
    "https://baseballsavant.mlb.com/leaderboard/custom",
    year = season, type = type, min = 1, selections = selections, csv = "true"
  )
  # I() tells readr this is the file's text, not a file name.
  read_csv(I(csv), show_col_types = FALSE)
}

# Bios for every player in this season's files; a missing one would leave a gap in birth dates.
fetch_people <- function(season) {
  sources <- c(
    "mlb_hitting", "mlb_pitching", "savant_batter_expected", "savant_batter_exit_velo",
    "savant_sprint_speed", "savant_batter_discipline", "savant_pitcher_measures"
  )
  ids <- map(sources, \(s) read_raw(raw_path(s, season))$player_id) |>
    unlist() |>
    as.integer() |>
    discard(is.na) |>
    unique() |>
    sort()
  people <- split(ids, ceiling(seq_along(ids) / PEOPLE_BATCH)) |>
    map(\(batch) {
      Sys.sleep(MLB_PAUSE)
      retrying(mlb_people)(person_ids = batch)
    }) |>
    bind_rows()
  missing <- setdiff(ids, as.integer(people$id))
  if (length(missing) > 0) {
    stop(length(missing), " IDs not returned, e.g. ", toString(head(missing, 10)))
  }
  people
}


# ---- Pull every source, season by season -------------------------------------

start_time <- Sys.time()

for (season in SEASONS) {
  message("==== Season ", season, " ====")

  pull_to_file(
    raw_path("mlb_hitting", season), MLB_PAUSE,
    c("player_id", "plate_appearances"),
    \() fetch_mlb_season("hitting", season)
  )
  pull_to_file(
    raw_path("mlb_pitching", season), MLB_PAUSE,
    c("player_id", "games_started", "innings_pitched"),
    \() fetch_mlb_season("pitching", season)
  )
  # Must come after the pitching file, which supplies the list of starters.
  pull_to_file(
    raw_path("mlb_pitcher_game_logs", season), MLB_PAUSE,
    c("player.id", "game.gamePk", "stat.outs", "stat.earnedRuns", "stat.gamesStarted"),
    \() fetch_starter_game_logs(season)
  )
  pull_to_file(
    raw_path("savant_batter_expected", season), SAVANT_PAUSE,
    c("player_id", "pa", "est_ba", "est_slg", "est_woba"),
    \() retrying(statcast_leaderboards)(
      leaderboard = "expected_statistics", year = season,
      player_type = "batter", min_pa = 1
    )
  )
  pull_to_file(
    raw_path("savant_batter_exit_velo", season), SAVANT_PAUSE,
    c("player_id", "avg_hit_speed", "brl_percent"),
    \() retrying(statcast_leaderboards)(
      leaderboard = "exit_velocity_barrels", year = season,
      player_type = "batter", min_pa = 1
    )
  )
  pull_to_file(
    raw_path("savant_sprint_speed", season), SAVANT_PAUSE,
    c("player_id", "sprint_speed"),
    \() retrying(statcast_leaderboards)(
      leaderboard = "sprint_speed", year = season, min_run = 0
    )
  )
  pull_to_file(
    raw_path("savant_batter_discipline", season), SAVANT_PAUSE,
    c(
      "player_id", "oz_swing_percent", "iz_contact_percent", "whiff_percent", "k_percent",
      "bb_percent", "flyballs_percent"
    ),
    \() fetch_savant_custom("batter", SAVANT_BATTER_SELECTIONS, season)
  )
  pull_to_file(
    raw_path("savant_pitcher_measures", season), SAVANT_PAUSE,
    c(
      "player_id", "xera", "fastball_avg_speed", "whiff_percent", "hard_hit_percent",
      "barrel_batted_rate", "groundballs_percent", "iz_contact_percent", "flyballs", "home_run"
    ),
    \() fetch_savant_custom("pitcher", SAVANT_PITCHER_SELECTIONS, season)
  )
  # Last, because it collects player IDs from all of this season's files above.
  pull_to_file(
    raw_path("mlb_people", season), MLB_PAUSE,
    c("id", "birth_date"),
    \() fetch_people(season)
  )
}

message("==== Chadwick register ====")
pull_to_file(
  raw_path("chadwick_register"), MLB_PAUSE,
  c("key_mlbam", "key_fangraphs", "key_bbref"),
  \() retrying(chadwick_player_lu)() |>
    filter(
      !is.na(key_mlbam), !is.na(mlb_played_last),
      mlb_played_last >= CHADWICK_MIN_LAST_PLAYED
    )
)


# ---- Summary -----------------------------------------------------------------

files <- list.files(here("data", "raw"), pattern = "\\.csv$", full.names = TRUE)
print(data.frame(
  file = basename(files),
  rows = map_int(files, \(f) nrow(read_raw(f))),
  size_kb = round(file.size(files) / 1024)
), row.names = FALSE)
message(sprintf(
  "Done in %.1f minutes.",
  as.numeric(difftime(Sys.time(), start_time, units = "mins"))
))
