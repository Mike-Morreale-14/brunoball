# 03_marcel.R: projects hitters and pitchers for TARGET_SEASON with Tom Tango's Marcel method.
# Run from the project folder after 02_clean.R: Rscript data-pipeline/03_marcel.R


# ---- Settings ----------------------------------------------------------------

TARGET_SEASON <- 2026 # season to project; uses the three seasons before it

# Sources: "Introduction to Marcel", tangotiger.net/archives/stud0346.shtml (Tango's own
# description, linked from tangotiger.net/marcel), and Tango's marcel2012.zip from that page.

HITTER_WEIGHTS <- c(5, 4, 3) # most recent season first; stud0346: "Weight each season as 5/4/3"
PITCHER_WEIGHTS <- c(3, 2, 1) # stud0346, pitcher changes: weights 3/2/1

# stud0346: league average forced in "at a total of 1200 PA" (in 5/4/3-weighted PA).
HITTER_REGRESS_PA <- 1200
# Tango's pages don't state the pitcher amount ("same"). Fitted to the reliability column of
# marcel2012.zip using 2009-11 MLB Stats API innings for Verlander, Halladay, Kershaw, Mariano
# Rivera, Sale and Venters: least-squares fit 268.0; 264.9-269.2 reproduces all six exactly.
PITCHER_REGRESS_IP <- 268

PT_WEIGHTS <- c(0.5, 0.1) # stud0346: projected PA = 0.5 * PA(y-1) + 0.1 * PA(y-2) + 200
HITTER_BASE_PA <- 200 # stud0346, as above
SP_BASE_IP <- 60 # stud0346: the 200 "becomes 25 for relievers and 60 for starters"
RP_BASE_IP <- 25 # stud0346, as above; part-timers in between "based on GS/G" (see below)

PEAK_AGE <- 29 # stud0346: age = target season - year of birth, compared with 29
AGE_GAIN_YOUNG <- 0.006 # stud0346: (29 - age) * .006 per year under 29 (with Tango's sign fix)
AGE_LOSS_OLD <- 0.003 # stud0346: (29 - age) * .003 per year over 29

# Extension, not Marcel: quality starts per start, regressed with this many weighted starts.
# Judgement call: about PITCHER_REGRESS_IP divided by the ~5.3 innings of an average start.
QS_REGRESS_GS <- 50

HITTER_EVENTS <- c(
  "singles", "doubles", "triples", "hr", "bb", "so", "hbp", "sf", "sh_ci", "sb", "cs", "r", "rbi"
)
PITCHER_EVENTS <- c("h", "hr", "bb", "hbp", "so", "er", "outs")
PITCHER_RATE_EVENTS <- setdiff(PITCHER_EVENTS, "outs") # every pitcher event except outs


# ---- Setup -------------------------------------------------------------------

suppressPackageStartupMessages({
  library(dplyr)
  library(purrr)
  library(readr)
  library(tidyr)
  library(here)
})

message("Working directory: ", getwd())

# setwd("path/to/brunoball")  # only needed if you didn't open brunoball.Rproj

here::i_am("data-pipeline/03_marcel.R")
dir.create(here("data", "projections"), showWarnings = FALSE)

players <- read_csv(here("data", "clean", "players.csv"),
  col_types = cols(.default = "c", player_id = "i", birth_date = "D")
)
hitters_hist <- read_csv(here("data", "clean", "hitters.csv"),
  col_types = cols(.default = "d", team = "c", player_id = "i", season = "i")
)
pitchers_hist <- read_csv(here("data", "clean", "pitchers.csv"),
  col_types = cols(.default = "d", team = "c", role = "c", player_id = "i", season = "i")
)
league_season <- read_csv(here("data", "clean", "league_season.csv"),
  col_types = cols(.default = "d", season = "i")
)


# ---- Helpers -----------------------------------------------------------------

# Marcel's events are counts; singles and the non-AB remainder aren't in the clean tables.
hitting_events <- function(df) {
  mutate(df, singles = h - doubles - triples - hr, sh_ci = pa - ab - bb - hbp - sf)
}

# League totals carry a bat_ or pit_ prefix; stripping it lets players and league share formulas.
league_totals <- function(prefix) {
  league_season |>
    select(season, starts_with(prefix)) |>
    rename_with(\(x) sub(prefix, "", x), -season)
}

# The three seasons before the target, most recent first, so weights line up by position.
history_seasons <- function(target) {
  seasons <- target - 1:3
  missing <- setdiff(seasons, league_season$season)
  if (length(missing) > 0) stop("No clean data for ", toString(missing), "; run 01 and 02 first.")
  seasons
}

# Follows Tango as published: one multiplier, 1 + this, on every rate except playing time
# (PA, AB, IP), so it raises a young player's strikeouts and hits allowed too.
age_adjustment <- function(age) {
  if_else(age < PEAK_AGE, (PEAK_AGE - age) * AGE_GAIN_YOUNG, (PEAK_AGE - age) * AGE_LOSS_OLD)
}

# The heart of Marcel: weighted player rates blended with the league rates of the same seasons,
# with the blend set by how much playing time (rel_time) the player has.
marcel_rates <- function(history, league, events, denom, rel_time, weights, regress, target) {
  league_long <- league |>
    mutate(across(all_of(events), \(x) x / .data[[denom]])) |>
    pivot_longer(all_of(events), names_to = "event", values_to = "lg_rate") |>
    select(season, event, lg_rate)

  history |>
    mutate(w = weights[target - season], d = .data[[denom]], t = .data[[rel_time]]) |>
    pivot_longer(all_of(events), names_to = "event", values_to = "count") |>
    left_join(league_long, by = c("season", "event")) |>
    group_by(player_id, event) |>
    summarise(
      player_rate = sum(w * count) / sum(w * d),
      league_rate = sum(w * d * lg_rate) / sum(w * d),
      reliability = sum(w * t) / (sum(w * t) + regress),
      .groups = "drop"
    ) |>
    mutate(rate = reliability * player_rate + (1 - reliability) * league_rate) |>
    pivot_wider(id_cols = c(player_id, reliability), names_from = event, values_from = rate)
}

# FIP is put on the scale of the season the projection is rebaselined to.
last_league_fip <- function(target) league_season$fip_constant[league_season$season == target - 1]

# Rebaselining scales each rate so the projected league matches the last real season.
rebaseline <- function(rate, weight, target_rate) rate * target_rate / weighted.mean(rate, weight)

# Last season's team, role and age inputs, shared by both projections.
latest_info <- function(history, target, cols) {
  history |>
    filter(season == max(season), .by = player_id) |>
    select(player_id, all_of(cols)) |>
    left_join(select(players, player_id, name, birth_date), by = "player_id") |>
    mutate(age = target - as.integer(format(birth_date, "%Y")), .after = name) |>
    select(-birth_date)
}


# ---- Hitters -----------------------------------------------------------------

# A function of the target season, so a past season can be projected and graded later.
project_hitters <- function(target) {
  seasons <- history_seasons(target)
  eligible <- filter(players, position != "P")$player_id

  history <- hitters_hist |>
    filter(season %in% seasons, player_id %in% eligible) |>
    hitting_events() |>
    filter(sum(pa) > 0, .by = player_id)
  league <- hitting_events(league_totals("bat_"))
  last_league <- filter(league, season == target - 1)

  playing_time <- history |>
    group_by(player_id) |>
    summarise(pa = PT_WEIGHTS[1] * sum(pa[season == target - 1]) +
      PT_WEIGHTS[2] * sum(pa[season == target - 2]) + HITTER_BASE_PA)

  rates <- marcel_rates(
    history, league, HITTER_EVENTS, "pa", "pa", HITTER_WEIGHTS, HITTER_REGRESS_PA, target
  )
  last_rate <- \(event) last_league[[event]] / last_league$pa

  latest_info(history, target, "team") |>
    left_join(playing_time, by = "player_id") |>
    left_join(rates, by = "player_id") |>
    mutate(
      across(all_of(HITTER_EVENTS), \(x) x * (1 + age_adjustment(age))),
      across(all_of(HITTER_EVENTS), \(x) rebaseline(x, pa, last_rate(cur_column()))),
      across(all_of(HITTER_EVENTS), \(x) x * pa),
      ab = pa - bb - hbp - sf - sh_ci,
      h = singles + doubles + triples + hr,
      avg = h / ab,
      obp = (h + bb + hbp) / (ab + bb + hbp + sf),
      slg = (h + doubles + 2 * triples + 3 * hr) / ab,
      ops = obp + slg,
      iso = slg - avg,
      k_pct = 100 * so / pa,
      bb_pct = 100 * bb / pa
    ) |>
    select(
      player_id, name, age, team, reliability, pa, ab, h, singles, doubles, triples, hr,
      r, rbi, sb, cs, bb, so, hbp, sf, avg, obp, slg, ops, iso, k_pct, bb_pct
    ) |>
    arrange(player_id)
}


# ---- Pitchers ----------------------------------------------------------------

# Same steps as hitters, but innings set playing time and batters faced are the rate base.
project_pitchers <- function(target) {
  seasons <- history_seasons(target)
  eligible <- filter(players, position %in% c("P", "TWP"))$player_id

  history <- pitchers_hist |>
    filter(season %in% seasons, player_id %in% eligible) |>
    filter(sum(bf) > 0, .by = player_id)
  league <- league_totals("pit_")
  last_league <- filter(league, season == target - 1)

  # Judgement call: Tango puts part-timers between 25 and 60 IP "based on GS/G"; here that is a
  # straight line on GS/G over all three seasons.
  playing_time <- history |>
    mutate(w = PITCHER_WEIGHTS[target - season]) |>
    left_join(transmute(league, season, lg_qs_rate = qs / gs), by = "season") |>
    group_by(player_id) |>
    summarise(
      ip = PT_WEIGHTS[1] * sum(ip[season == target - 1]) +
        PT_WEIGHTS[2] * sum(ip[season == target - 2]) +
        RP_BASE_IP + (SP_BASE_IP - RP_BASE_IP) * sum(gs) / sum(g),
      # Judgement call: starts keep the player's weighted starts-per-inning ratio.
      gs_per_ip = if_else(sum(w * ip) > 0, sum(w * gs) / sum(w * ip), 0),
      # Extension: QS per start, weighted 3/2/1 and regressed to the league QS rate.
      qs_per_start = (sum(w * qs) + QS_REGRESS_GS * weighted.mean(lg_qs_rate, w * gs)) /
        (sum(w * gs) + QS_REGRESS_GS)
    )

  rates <- marcel_rates(
    history, league, PITCHER_EVENTS, "bf", "ip", PITCHER_WEIGHTS, PITCHER_REGRESS_IP, target
  )
  last_rate <- \(event) last_league[[event]] / last_league$bf

  latest_info(history, target, c("team", "role")) |>
    left_join(playing_time, by = "player_id") |>
    left_join(rates, by = "player_id") |>
    mutate(
      across(all_of(PITCHER_RATE_EVENTS), \(x) x * (1 + age_adjustment(age))),
      # Innings are fixed, so batters faced follow from outs per batter; rebaselining outs uses
      # innings as the weight (a harmonic mean) so league outs per batter lands exactly.
      outs = outs * last_rate("outs") / (sum(3 * ip) / sum(3 * ip / outs)),
      bf = 3 * ip / outs,
      across(all_of(PITCHER_RATE_EVENTS), \(x) rebaseline(x, bf, last_rate(cur_column()))),
      across(all_of(PITCHER_RATE_EVENTS), \(x) x * bf),
      gs = ip * gs_per_ip,
      # No projected starts: a rate per start is undefined, but the count is truly zero.
      qs_per_start = if_else(gs > 0, qs_per_start, NA_real_),
      qs = if_else(gs > 0, gs * qs_per_start, 0),
      era = 9 * er / ip,
      whip = (bb + h) / ip,
      k_pct = 100 * so / bf,
      bb_pct = 100 * bb / bf,
      k_bb_pct = k_pct - bb_pct,
      fip = (13 * hr + 3 * (bb + hbp) - 2 * so) / ip + last_league_fip(target)
    ) |>
    select(
      player_id, name, age, team, role, reliability, ip, bf, gs, h, hr, bb, hbp, so, er,
      era, whip, k_pct, bb_pct, k_bb_pct, fip, qs_per_start, qs
    ) |>
    arrange(player_id)
}


# ---- Project -----------------------------------------------------------------

hitters <- project_hitters(TARGET_SEASON)
pitchers <- project_pitchers(TARGET_SEASON)


# ---- Checks ------------------------------------------------------------------

# Every check is printed, and any failure stops the script before a file is written.
check <- function(label, ok) {
  message(if (isTRUE(ok)) "  PASS  " else "  FAIL  ", label)
  isTRUE(ok)
}

last <- filter(league_season, season == TARGET_SEASON - 1)
league_check <- tribble(
  ~stat, ~projected, ~last_season,
  "AVG", sum(hitters$h) / sum(hitters$ab), last$bat_avg,
  "OBP", with(hitters, sum(h + bb + hbp) / sum(ab + bb + hbp + sf)), last$bat_obp,
  "SLG", with(hitters, sum(h + doubles + 2 * triples + 3 * hr) / sum(ab)), last$bat_slg,
  "HR per PA", sum(hitters$hr) / sum(hitters$pa), last$bat_hr / last$bat_pa,
  "SB per PA", sum(hitters$sb) / sum(hitters$pa), last$bat_sb / last$bat_pa,
  "Hitter K%", 100 * sum(hitters$so) / sum(hitters$pa), last$bat_k_pct,
  "Hitter BB%", 100 * sum(hitters$bb) / sum(hitters$pa), last$bat_bb_pct,
  "ERA", 9 * sum(pitchers$er) / sum(pitchers$ip), last$pit_era,
  "WHIP", with(pitchers, sum(bb + h) / sum(ip)), last$pit_whip,
  "Pitcher K%", 100 * sum(pitchers$so) / sum(pitchers$bf), last$pit_k_pct,
  "Pitcher BB%", 100 * sum(pitchers$bb) / sum(pitchers$bf), last$pit_bb_pct,
  "FIP", with(pitchers, sum(13 * hr + 3 * (bb + hbp) - 2 * so) / sum(ip)) +
    last$fip_constant, last$pit_era,
  "QS per start", sum(pitchers$qs) / sum(pitchers$gs), last$pit_qs / last$pit_gs
)

message("Projected league vs ", TARGET_SEASON - 1, ":")
print(mutate(league_check, across(where(is.numeric), \(x) round(x, 4))), n = Inf)

message("Checks:")
passed <- c(
  check("one row per player in hitters", !anyDuplicated(hitters$player_id)),
  check("one row per player in pitchers", !anyDuplicated(pitchers$player_id)),
  check(
    "projected league rates match last season within rounding (all but QS)",
    all(abs(league_check$projected - league_check$last_season)[-nrow(league_check)] < 5e-4)
  )
)

# Leaderboards are the quickest way for a person to spot a projection that looks wrong.
show_top <- function(df, label, col, n = 15, desc = TRUE) {
  message("Top ", n, " ", label, ":")
  df |>
    arrange(if (desc) desc({{ col }}) else {{ col }}) |>
    head(n) |>
    transmute(name, team, age, value = round({{ col }}, 2)) |>
    print(n = n)
}
show_top(hitters, "projected HR", hr)
show_top(hitters, "projected SB", sb)
show_top(pitchers, "projected SO (pitchers)", so)
show_top(filter(pitchers, ip >= 120), "lowest projected ERA (120+ IP)", era, desc = FALSE)

message("Named players:")
named <- c(592450, 669373, 660271) # Judge, Skubal, Ohtani
print(as.data.frame(mutate(
  filter(hitters, player_id %in% named), across(where(is.double), \(x) round(x, 3))
)))
print(as.data.frame(mutate(
  filter(pitchers, player_id %in% named), across(where(is.double), \(x) round(x, 3))
)))

if (!all(passed)) stop("Some checks failed; nothing was written.", call. = FALSE)


# ---- Write -------------------------------------------------------------------

# Rounded on the way out only, so the checks above use full precision.
write_projection <- function(df, kind) {
  path <- here("data", "projections", paste0("marcel_", kind, "_", TARGET_SEASON, ".csv"))
  write_csv(mutate(df, across(where(is.double), \(x) round(x, 3))), path, na = "")
  message("Wrote ", basename(path), " (", nrow(df), " players)")
}
write_projection(hitters, "hitters")
write_projection(pitchers, "pitchers")
