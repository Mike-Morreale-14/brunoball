# 04_scores.R: builds percentile inputs for the draft site from ADP, Marcel and 2025 stats.
# Run from the project folder after 03_marcel.R: Rscript data-pipeline/04_scores.R


# ---- Settings ----------------------------------------------------------------

TARGET_SEASON <- 2026 # draft season; must match the Marcel projection files
STATS_SEASON <- TARGET_SEASON - 1 # season the "2025 actual" and Savant inputs come from
ADP_MAX <- 300 # players with FantasyPros ADP at or below this form the pool
SMALL_PA <- 200 # hitters under this many 2025 PA get a "small 2025 sample" flag on deltas
SMALL_IP <- 50 # pitchers under this many 2025 innings get the same flag


# ---- Setup -------------------------------------------------------------------

suppressPackageStartupMessages({
  library(dplyr)
  library(purrr)
  library(readr)
  library(tidyr)
  library(jsonlite)
  library(here)
})

message("Working directory: ", getwd())

# setwd("path/to/brunoball")  # only needed if you didn't open brunoball.Rproj

here::i_am("data-pipeline/04_scores.R")
# The site files live with the site, because data/ is never committed.
SITE_DATA <- here("draft-tool", "data")
dir.create(SITE_DATA, recursive = TRUE, showWarnings = FALSE)

weights <- read_json(here("data-pipeline", "weights.json"), simplifyVector = TRUE)

fixes <- read_csv(here("data-pipeline", "adp_id_fixes.csv"),
  col_types = cols(.default = "c", player_id = "i", adp = "d")
)
adp <- read_csv(here("data", "raw", paste0("fantasypros_adp_", TARGET_SEASON, ".csv")),
  col_types = cols(.default = "c")
)
marcel_h <- read_csv(here("data", "projections", paste0("marcel_hitters_", TARGET_SEASON, ".csv")),
  col_types = cols(.default = "d", player_id = "i", name = "c", team = "c")
)
marcel_p <- read_csv(
  here("data", "projections", paste0("marcel_pitchers_", TARGET_SEASON, ".csv")),
  col_types = cols(.default = "d", player_id = "i", name = "c", team = "c", role = "c")
)
hitters_hist <- read_csv(here("data", "clean", "hitters.csv"),
  col_types = cols(.default = "d", team = "c", player_id = "i", season = "i")
)
pitchers_hist <- read_csv(here("data", "clean", "pitchers.csv"),
  col_types = cols(.default = "d", team = "c", role = "c", player_id = "i", season = "i")
)


# ---- Helpers -----------------------------------------------------------------

# ADP names and MLB names differ in accents, punctuation and suffixes, so both are reduced alike.
normalise_name <- function(x) {
  x |>
    iconv(to = "ASCII//TRANSLIT") |>
    tolower() |>
    gsub("[^a-z ]", "", x = _) |>
    gsub("(^| )(jr|sr|ii|iii|iv)( |$)", " ", x = _) |>
    gsub(" +", " ", x = _) |>
    trimws()
}

# Ties share their average rank, and ranks are stretched so the group runs exactly 0 to 100
# even when several players tie at an end (e.g. 0 SB); "low_" inputs rank lowest value highest.
percentile <- function(x, lower_is_better) {
  r <- rank(if (lower_is_better) -x else x, ties.method = "average", na.last = "keep")
  round(100 * (r - min(r, na.rm = TRUE)) / (max(r, na.rm = TRUE) - min(r, na.rm = TRUE)), 1)
}

# Matches the site's Math.round, which rounds halves up (R's round() rounds them to even).
js_round <- function(x) floor(x + 0.5)

# The site's score: weighted mean of the percentiles a player has, skipping missing ones.
score <- function(df, w) {
  p <- as.matrix(df[paste0("p_", names(w))])
  wt <- matrix(unlist(w), nrow(p), length(w), byrow = TRUE) * !is.na(p)
  s <- rowSums(replace(p, is.na(p), 0) * wt) / rowSums(wt)
  js_round(ifelse(rowSums(wt) > 0, s, NA))
}

# Every input any weight set uses, so percentiles are computed once per input.
input_keys <- function(group) unique(unlist(map(weights[[group]], \(s) map(s, names))))

# Percentiles are taken only among a group's scored players, never across groups.
add_percentiles <- function(df, keys) {
  for (k in keys) df[[paste0("p_", k)]] <- percentile(df[[k]], grepl("low_", k))
  df
}

# Main, Raw and Underlying for each archetype, plus the delta, for the checks and printouts.
all_scores <- function(df, group) {
  imap(weights[[group]], \(sets, arch) {
    out <- tibble(
      player_id = df$player_id, name = df$name, archetype = arch,
      small_2025_sample = df$small_2025_sample
    )
    for (s in names(sets)) out[[s]] <- score(df, sets[[s]])
    out
  }) |>
    bind_rows() |>
    mutate(delta = und - raw) # Volatility has only Main, so its delta stays empty
}

# NaN (0/0, or a mean of nothing) would reach the site as text, so it becomes a plain gap.
nan_to_na <- function(df) mutate(df, across(where(is.double), \(x) replace(x, is.nan(x), NA)))

# The "2023-25" table on player pages: totals over the three seasons, then rates from them.
span_hitting <- function(ids) {
  hitters_hist |>
    filter(player_id %in% ids) |>
    summarise(
      y3_seasons = n(), y3_pa = sum(pa),
      y3_hr_600 = 600 * sum(hr) / sum(pa), y3_r_600 = 600 * sum(r) / sum(pa),
      y3_rbi_600 = 600 * sum(rbi) / sum(pa), y3_sb_600 = 600 * sum(sb) / sum(pa),
      y3_avg = sum(h) / sum(ab),
      y3_ops = sum(h + bb + hbp) / sum(ab + bb + hbp + sf) +
        sum(h + doubles + 2 * triples + 3 * hr) / sum(ab),
      .by = player_id
    ) |>
    nan_to_na()
}

span_pitching <- function(ids) {
  pitchers_hist |>
    filter(player_id %in% ids) |>
    summarise(
      y3_seasons = n(), y3_ip = sum(ip),
      y3_era = 9 * sum(er) / sum(ip), y3_whip = sum(bb + h) / sum(ip),
      y3_k9 = 9 * sum(so) / sum(ip),
      y3_barrel_pct = weighted.mean(barrel_pct, bf, na.rm = TRUE),
      y3_hard_hit_pct = weighted.mean(hard_hit_pct, bf, na.rm = TRUE),
      y3_fb_velo = weighted.mean(fb_velo, ip, na.rm = TRUE),
      .by = player_id
    ) |>
    nan_to_na()
}

# The site shows each player's last three seasons, newest first.
history_of <- function(hist, ids, cols) {
  hist |>
    filter(player_id %in% ids) |>
    arrange(player_id, desc(season)) |>
    select(player_id, season, all_of(cols)) |>
    nest(history = -player_id)
}


# ---- ADP pool and ID matching ------------------------------------------------

# Each ADP name is matched only against projected players of the same kind (hitter or
# pitcher), which settles namesakes like Will Smith (catcher and pitcher).
candidates <- bind_rows(
  transmute(marcel_h, player_id, kind = "hitter", key = normalise_name(name)),
  transmute(marcel_p, player_id, kind = "pitcher", key = normalise_name(name))
)

pool <- adp |>
  transmute(
    adp_name = Name, adp_team = Team, position = Pos, adp = suppressWarnings(as.numeric(ADP))
  ) |>
  filter(!is.na(adp), adp <= ADP_MAX) |>
  mutate(
    key = normalise_name(adp_name),
    kind = if_else(grepl("SP|RP|^P$", position), "pitcher", "hitter")
  )

name_matches <- pool |>
  inner_join(candidates, by = c("key", "kind")) |>
  summarise(n_matches = n(), match_id = first(player_id), .by = c(adp_name, adp_team))

# Fixes may add a row (Ohtani as a pitcher) as well as set an ID, so they are joined many-to-one.
pool <- pool |>
  left_join(name_matches, by = c("adp_name", "adp_team")) |>
  left_join(
    rename(fixes, fix_id = player_id, fix_group = group, fix_adp = adp, adp_note = site_note),
    by = c("adp_name", "adp_team"), relationship = "many-to-many"
  ) |>
  mutate(
    player_id = coalesce(fix_id, if_else(n_matches == 1, match_id, NA_integer_)),
    adp = coalesce(fix_adp, adp),
    reason = case_when(
      !is.na(player_id) ~ NA_character_,
      n_matches > 1 ~ "several MLB players share this name; add a row to adp_id_fixes.csv",
      .default = "no MLB time in 2023-25, so no Marcel projection (rookie or new to MLB)"
    )
  ) |>
  left_join(select(marcel_p, player_id, role), by = "player_id") |>
  mutate(group = coalesce(fix_group, case_when(
    kind == "hitter" ~ "hitter",
    role == "SP" ~ "sp",
    !is.na(role) ~ "relievers",
    grepl("SP", position) ~ "sp",
    .default = "relievers"
  ))) |>
  # Ohtani's single FantasyPros row says DH, which would mislabel his pitcher entry.
  mutate(position = if_else(group == "sp" & !grepl("SP", position), "SP", position)) |>
  select(player_id, adp_name, adp_team, position, adp, adp_note, group, reason)


# ---- Inputs ------------------------------------------------------------------

season_h <- filter(hitters_hist, season == STATS_SEASON)
season_p <- filter(pitchers_hist, season == STATS_SEASON)

hitters <- pool |>
  filter(group == "hitter", is.na(reason)) |>
  left_join(marcel_h, by = "player_id") |>
  left_join(
    select(
      season_h, player_id, max_ev, hard_hit_pct,
      a_pa = pa, a_hr = hr, a_sb = sb, a_avg = avg, a_iso = iso, a_babip = babip,
      a_k_pct = k_pct, barrel_pct, avg_ev, xba, xslg, fb_pct, sprint_speed, chase_contact_pct,
      whiff_pct
    ),
    by = "player_id"
  ) |>
  mutate(
    barrel = barrel_pct, ev = avg_ev, fb = fb_pct, xavg = xba, xiso = xslg - xba,
    proj_iso = iso, proj_hr = hr, proj_sb = sb, proj_avg = avg, proj_low_k = k_pct,
    proj_babip = (h - hr) / (ab - so - hr + sf),
    # Raw uses rates, not counts, so the delta compares skill with results, not playing time.
    act_hr_pa = a_hr / a_pa, act_sb_pa = a_sb / a_pa,
    act_hr = a_hr, act_sb = a_sb, act_avg = a_avg, act_iso = a_iso, act_babip = a_babip,
    act_low_k = a_k_pct, sprint = sprint_speed, ocontact = chase_contact_pct,
    contact = 100 - whiff_pct,
    small_2025_sample = is.na(a_pa) | a_pa < SMALL_PA
  ) |>
  add_percentiles(input_keys("hitter"))

sp <- pool |>
  filter(group == "sp", is.na(reason)) |>
  left_join(marcel_p, by = "player_id") |>
  left_join(
    select(
      season_p, player_id,
      a_bb_pct = bb_pct, a_ip = ip, a_gs = gs, a_qs = qs, a_era = era, a_whip = whip, a_so = so,
      a_k_pct = k_pct, xera, fb_velo, whiff_pct, hard_hit_pct, gb_pct, zone_contact_pct,
      barrel_pct, hr_fb_pct
    ),
    by = "player_id"
  ) |>
  mutate(
    proj_ip = ip, proj_qs = qs, proj_low_era = era, proj_low_whip = whip, proj_k = so,
    proj_k9 = 9 * so / ip, low_xera = xera, low_hard = hard_hit_pct, hard = hard_hit_pct,
    gb = gb_pct, act_qs_gs = if_else(a_gs > 0, a_qs / a_gs, NA_real_),
    act_low_era = a_era, act_low_whip = a_whip, act_k9 = 9 * a_so / a_ip, act_kpct = a_k_pct,
    fbv = fb_velo, whiff = whiff_pct, low_zcon = zone_contact_pct, hrfb = hr_fb_pct,
    barrel_ag = barrel_pct, small_2025_sample = is.na(a_ip) | a_ip < SMALL_IP
  ) |>
  add_percentiles(input_keys("sp"))

relievers <- pool |>
  filter(group == "relievers", is.na(reason)) |>
  left_join(marcel_p, by = "player_id")


# ---- Reliability -------------------------------------------------------------

REL <- weights$reliability
if (REL$weights$consistency != 0) stop("Consistency isn't rebuilt; keep its weight at 0.")

# The 2026 tool's percentile: share of the group strictly below the player, 0-100.
pct_below <- function(x) js_round(100 * map_dbl(x, \(v) sum(x < v)) / (length(x) - 1))

# Older seasons count less: weights e^(lambda * i) by position, oldest (i = 0) to newest.
recency <- function(hist, ids, field) {
  hist |>
    filter(player_id %in% ids) |>
    arrange(player_id, season) |>
    summarise(
      recency = weighted.mean(.data[[field]], exp(REL$recency_lambda * (row_number() - 1))),
      .by = player_id
    )
}

# Full marks through age 33, then a falling penalty, as in the 2026 tool.
age_score <- function(age) {
  case_when(
    is.na(age) ~ 50, age <= 33 ~ 50, age == 34 ~ 40,
    .default = pmax(0, 40 - (age - 34) * 5)
  )
}

# Recency of playing time, projected playing time and age, blended with the reliability weights.
add_reliability <- function(df, hist, field, playing_time) {
  w <- REL$weights
  df |>
    left_join(recency(hist, df$player_id, field), by = "player_id") |>
    mutate(
      rel_recency = pct_below(coalesce(recency, 0)),
      rel_proj = pct_below(coalesce({{ playing_time }}, 0)),
      rel_age = age_score(age),
      reliability_score = js_round(
        (w$recency * rel_recency + w$proj * rel_proj + w$age_rel * rel_age) /
          (w$recency + w$proj + w$age_rel)
      )
    )
}

hitters <- add_reliability(hitters, hitters_hist, "g", pa)
sp <- add_reliability(sp, pitchers_hist, "ip", proj_ip)


# ---- Site files --------------------------------------------------------------

# Only the columns the interface reads: identity, ADP, reliability, percentiles, display stats.
site_hitters <- hitters |>
  transmute(
    player_id, name,
    team = adp_team, position, age, adp, adp_note,
    reliability = reliability_score, small_2025_sample,
    across(starts_with("p_")),
    proj_pa = pa, proj_hr = hr, proj_r = r, proj_rbi = rbi, proj_sb = sb, proj_avg = avg,
    proj_ops = ops, avg_ev, max_ev, barrel_pct, hard_hit_pct, xba, xslg, sprint_speed,
    k_pct_2025 = a_k_pct, chase_contact_pct, whiff_pct, fb_pct
  ) |>
  left_join(span_hitting(hitters$player_id), by = "player_id") |>
  left_join(history_of(
    hitters_hist, hitters$player_id,
    c(
      "team", "g", "pa", "hr", "r", "rbi", "sb", "avg", "ops", "avg_ev", "max_ev", "barrel_pct",
      "hard_hit_pct"
    )
  ), by = "player_id")

pitcher_history_cols <- c(
  "team", "role", "g", "gs", "ip", "qs", "w", "l", "sv", "so", "era", "whip", "fb_velo"
)

site_sp <- sp |>
  transmute(
    player_id, name,
    team = adp_team, position, age, adp, adp_note,
    reliability = reliability_score, small_2025_sample,
    across(starts_with("p_")),
    proj_ip, proj_qs, proj_so = so, proj_era = era, proj_whip = whip, proj_k9,
    fip_proj = fip, fb_velo, whiff_pct, k_pct_2025 = a_k_pct, bb_pct_2025 = a_bb_pct, xera,
    hard_hit_pct, barrel_pct, gb_pct, zone_contact_pct, hr_fb_pct
  ) |>
  left_join(span_pitching(sp$player_id), by = "player_id") |>
  left_join(history_of(pitchers_hist, sp$player_id, pitcher_history_cols), by = "player_id")

# Relievers are shown with their stats only; Marcel doesn't project saves, so none appear here.
site_relievers <- relievers |>
  transmute(
    player_id, name,
    team = adp_team, position, age, adp, adp_note, role,
    proj_ip = ip, proj_so = so, proj_era = era, proj_whip = whip, proj_k9 = 9 * so / ip
  ) |>
  left_join(span_pitching(relievers$player_id), by = "player_id") |>
  left_join(history_of(pitchers_hist, relievers$player_id, pitcher_history_cols), by = "player_id")

# Unscored players still appear in their group's list, with the reason in place of scores.
unscored <- pool |>
  filter(!is.na(reason)) |>
  transmute(
    player_id,
    name = adp_name, team = adp_team, position, adp, adp_note, group,
    unscored_reason = reason
  )

site_files <- list(
  hitters = bind_rows(site_hitters, select(filter(unscored, group == "hitter"), -group)),
  sp = bind_rows(site_sp, select(filter(unscored, group == "sp"), -group)),
  relievers = bind_rows(site_relievers, select(filter(unscored, group == "relievers"), -group))
) |>
  map(\(df) arrange(df, adp))


# ---- Checks ------------------------------------------------------------------

# Every check is printed, and any failure stops the script before a file is written.
check <- function(label, ok) {
  message(if (isTRUE(ok)) "  PASS  " else "  FAIL  ", label)
  isTRUE(ok)
}

# Reproduces the site's loop over weights.json, written separately from score() on purpose.
js_style_score <- function(player, w) {
  num <- 0
  den <- 0
  for (k in names(w)) {
    v <- player[[paste0("p_", k)]]
    if (is.null(v) || is.na(v) || w[[k]] == 0) next
    num <- num + v * w[[k]]
    den <- den + w[[k]]
  }
  if (den == 0) NA else floor(num / den + 0.5)
}

scores <- bind_rows(all_scores(hitters, "hitter"), all_scores(sp, "sp"))

spans_0_100 <- function(df) {
  p <- select(df, starts_with("p_"))
  all(map_lgl(p, \(x) min(x, na.rm = TRUE) == 0 && max(x, na.rm = TRUE) == 100))
}

js_check_ids <- c(592450, 660271, 669373, 682998, 694973) # Judge, Ohtani, Skubal, Carroll, Skenes
js_check <- map(names(site_files)[1:2], \(f) {
  group <- if (f == "hitters") "hitter" else "sp"
  players <- fromJSON(toJSON(site_files[[f]], na = "null", digits = NA), simplifyVector = FALSE)
  keep(players, \(p) isTRUE(p$player_id %in% js_check_ids)) |>
    map(\(p) imap(weights[[group]], \(sets, arch) {
      tibble(
        player_id = p$player_id, archetype = arch, set = names(sets),
        js = unname(map_dbl(sets, \(w) js_style_score(p, w)))
      )
    }) |> bind_rows()) |>
    bind_rows()
}) |>
  bind_rows() |>
  left_join(
    pivot_longer(scores, c(main, raw, und), names_to = "set", values_to = "r"),
    by = c("player_id", "archetype", "set")
  )

message("Checks:")
rel_all <- c(hitters$reliability_score, sp$reliability_score)
message(
  "Reliability (Judge, Ohtani as hitter, Skubal): ",
  toString(c(
    filter(hitters, player_id %in% c(592450, 660271))$reliability_score,
    filter(sp, player_id == 669373)$reliability_score
  ))
)
passed <- c(
  check(
    "every scored player has a reliability score from 0 to 100",
    !anyNA(rel_all) && all(rel_all >= 0 & rel_all <= 100)
  ),
  check(
    paste0("every ADP <= ", ADP_MAX, " row is matched or listed as unscored with a reason"),
    all(!is.na(pool$player_id) | !is.na(pool$reason))
  ),
  check(
    "no player appears twice in a group",
    !anyDuplicated(filter(pool, !is.na(player_id))[c("player_id", "group")])
  ),
  check("hitter percentiles span 0-100 for every input", spans_0_100(hitters)),
  check("SP percentiles span 0-100 for every input", spans_0_100(sp)),
  check(
    sprintf(
      "R scores match the JS-style recomputation (%d scores, %d players)",
      nrow(js_check), n_distinct(js_check$player_id)
    ),
    n_distinct(js_check$player_id) == length(js_check_ids) &&
      identical(js_check$js, js_check$r)
  )
)

message(
  "Pool: ", nrow(pool), " ADP rows -> ", nrow(hitters), " hitters, ", nrow(sp), " SP, ",
  nrow(relievers), " relievers scored or shown; ", nrow(unscored), " unscored"
)
message("Unscored:")
print(
  as.data.frame(select(unscored, name, team, position, adp, unscored_reason)),
  row.names = FALSE
)

show_top <- function(df, label, col, n = 10) {
  message(label, ":")
  print(as.data.frame(head(arrange(df, desc({{ col }})), n)), row.names = FALSE)
}
for (arch in c("pwr", "spd", "avg", "anc", "karm", "vol")) {
  show_top(
    select(filter(scores, archetype == arch), name, main, raw, und, delta),
    paste("Top 10 by Main:", arch), main
  )
}
# Speed has no delta on the site: its Underlying includes contact, so the gap isn't luck.
deltas <- scores |>
  filter(!archetype %in% weights$hide_delta, !is.na(delta)) |>
  select(name, archetype, raw, und, delta, small_2025_sample)
show_top(deltas, "Biggest positive deltas (Underlying above Raw)", delta)
show_top(deltas, "Biggest negative deltas (Raw above Underlying)", -delta)

if (!all(passed)) stop("Some checks failed; nothing was written.", call. = FALSE)


# ---- Write -------------------------------------------------------------------

iwalk(site_files, \(df, name) {
  path <- file.path(SITE_DATA, paste0(name, ".json"))
  write_json(df, path, na = "null", auto_unbox = TRUE, digits = 4)
  message("Wrote draft-tool/data/", basename(path), " (", nrow(df), " players)")
})
# The site reads the same weights file, so its scores match the checks above.
file.copy(here("data-pipeline", "weights.json"), SITE_DATA, overwrite = TRUE)
message("Copied weights.json to draft-tool/data/")
