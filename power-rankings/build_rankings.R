# build_rankings.R: Weekly Rank and Season Rank for the league, plus the weighting heatmap for the README.
# Run from the project folder: Rscript power-rankings/build_rankings.R


# ---- Settings ----------------------------------------------------------------

N_WEEKS <- 22 # regular-season weeks in the data
N_TEAMS <- 10
CATS <- c("R", "HR", "RBI", "SB", "AVG", "OPS", "W", "SV", "K", "ERA", "WHIP", "QS")
LOWER_BETTER <- c("ERA", "WHIP") # every other category ranks highest first
DECAY <- 0.8 # a week counts DECAY times as much as the week after it in the Season Rank
DOMINANT_WINS <- 70 # category wins vs. the league (of 108) that make a "70+ week"
CHECK_WEEK <- 18 # week the reference numbers below come from


# ---- Setup -------------------------------------------------------------------

suppressPackageStartupMessages({
  library(dplyr)
  library(purrr)
  library(readr)
  library(tidyr)
  library(jsonlite)
  library(ggplot2)
  library(here)
})

message("Working directory: ", getwd())

# setwd("path/to/brunoball")  # only needed if you didn't open brunoball.Rproj

here::i_am("power-rankings/build_rankings.R")

stats <- read_csv(here("power-rankings", "data", "weekly_stats_2026.csv"),
  col_types = cols(.default = "d", team = "c", opponent = "c")
)

# Team order is the order of week 1's rows; it sets each team's colour and breaks exact ties in rank.
teams <- filter(stats, week == 1)$team
stats <- stats |>
  mutate(team_i = match(team, teams), opp_i = match(opponent, teams)) |>
  arrange(week, team_i)


# ---- Helpers -----------------------------------------------------------------

# Matches JavaScript's Math.round, so totals agree with the page to the last digit.
round1 <- function(x) floor(x * 10 + 0.5) / 10

# Roto points in one category: 10 for first down to 1 for last, tied teams share the points they span.
roto_points <- function(x, cat) {
  rank(if (cat %in% LOWER_BETTER) -x else x, ties.method = "average")
}

# Category wins, losses and ties of team a against team b in one week (equal values tie).
h2h <- function(wk, a, b) {
  better <- map_lgl(CATS, \(cat) {
    if (cat %in% LOWER_BETTER) wk[[cat]][a] < wk[[cat]][b] else wk[[cat]][a] > wk[[cat]][b]
  })
  tied <- map_lgl(CATS, \(cat) wk[[cat]][a] == wk[[cat]][b])
  c(w = sum(better & !tied), l = sum(!better & !tied), t = sum(tied))
}

# Actual win share minus win share vs. the league, ties counted as half a win.
luck <- function(act, exp) {
  (act[["w"]] + 0.5 * act[["t"]]) / sum(act) - (exp[["w"]] + 0.5 * exp[["t"]]) / sum(exp)
}

# Season Rank weights as of week n, for weeks 1 to n: week n gets 1, week n-1 gets DECAY, and so on; scaled to sum to 1.
season_weights <- function(n) {
  w <- DECAY^(n - seq_len(n))
  w / sum(w)
}

# Ranks teams by a total, best first; exact ties keep week-1 order.
rank_by <- function(total) order(order(-total))


# ---- Weekly results ----------------------------------------------------------

weeks <- map(seq_len(N_WEEKS), \(w) {
  wk <- filter(stats, week == w)
  pts <- sapply(CATS, \(cat) roto_points(wk[[cat]], cat))
  # Record vs. league: every team's categories against all nine others that week.
  vs_league <- t(sapply(seq_len(N_TEAMS), \(i) {
    rowSums(sapply(setdiff(seq_len(N_TEAMS), i), \(j) h2h(wk, i, j)))
  }))
  actual <- t(sapply(seq_len(N_TEAMS), \(i) h2h(wk, i, wk$opp_i[i])))
  list(wk = wk, pts = pts, roto = round1(rowSums(pts)), vs_league = vs_league, actual = actual)
})


# ---- Season Rank as of each week ---------------------------------------------

power <- map(seq_len(N_WEEKS), \(n) {
  w <- season_weights(n)
  cat_pts <- Reduce(`+`, map2(weeks[seq_len(n)], w, \(x, wt) x$pts * wt))
  # Records are season totals, not decayed; "Avg" sums each week's record vs. league divided by 9.
  vs_league <- Reduce(`+`, map(weeks[seq_len(n)], "vs_league"))
  actual <- Reduce(`+`, map(weeks[seq_len(n)], "actual"))
  dominant <- Reduce(`+`, map(weeks[seq_len(n)], \(x) as.integer(x$vs_league[, "w"] >= DOMINANT_WINS)))
  list(cat_pts = cat_pts, roto = round1(rowSums(cat_pts)), avg = vs_league / 9, actual = actual, dominant = dominant)
})


# ---- Tables for the page -----------------------------------------------------

record <- function(m, i, digits = 0) unname(round(m[i, c("w", "l", "t")], digits))

week_table <- function(n) {
  x <- weeks[[n]]
  map(seq_len(N_TEAMS), \(i) {
    list(
      team = i - 1, rank = rank_by(x$roto)[i], roto = x$roto[i],
      stats = as.list(unlist(x$wk[i, CATS])), pts = as.list(x$pts[i, ]),
      total = record(x$vs_league, i), avg = record(x$vs_league / 9, i, 4), actual = record(x$actual, i),
      luck = round(luck(x$actual[i, ], x$vs_league[i, ]), 4)
    )
  })
}

power_table <- function(n) {
  p <- power[[n]]
  map(seq_len(N_TEAMS), \(i) {
    list(
      team = i - 1, rank = rank_by(p$roto)[i], roto = p$roto[i], pts = as.list(round(p$cat_pts[i, ], 4)),
      dominant = p$dominant[i], avg = record(p$avg, i, 4), actual = record(p$actual, i),
      luck = round(luck(p$actual[i, ], p$avg[i, ]), 4)
    )
  })
}

out <- list(
  season = 2026, weeks = N_WEEKS, teams = teams, cats = CATS, lower_better = LOWER_BETTER,
  decay = DECAY, dominant_wins = DOMINANT_WINS,
  by_week = map(seq_len(N_WEEKS), \(n) list(week = n, results = week_table(n), power = power_table(n)))
)


# ---- Checks ------------------------------------------------------------------

# Every check is printed, and any failure stops the script before a file is written.
check <- function(label, ok) {
  message(if (isTRUE(ok)) "  PASS  " else "  FAIL  ", label)
  isTRUE(ok)
}

# Week 18 as shown on my in-season power rankings page, by team.
reference <- tribble(
  ~team, ~week_roto, ~week_luck, ~power_roto, ~power_luck,
  "Team Bruno", 47.5, 0.0046, 70.7, -0.0592,
  "Woo Back Wednesday", 67.5, -0.3056, 59.2, -0.0568,
  "South Side Samurai", 48, -0.0417, 57.7, 0.0069,
  "Kyle Schwarbomb", 80.5, -0.0509, 63, 0.0131,
  "Big Dumpers", 65.5, 0.1713, 64.3, 0.026,
  "I think Yammamoto likes you", 71.5, 0.1574, 77.2, 0.0625,
  "Pete Malonso - White Iverson", 87, 0.0972, 73.4, 0.0157,
  "Elly De La Snooze", 65, 0.2176, 55.8, 0.0136,
  "The Green Monsters", 51, -0.0694, 64.2, 0.0234,
  "CHUZZ HOME", 76.5, -0.1806, 74.5, -0.0453
)
ref_i <- match(reference$team, teams)
w18 <- out$by_week[[CHECK_WEEK]]
# Labels carry the largest difference, since luck values are far smaller than the 0.1 allowed.
close <- function(got, want) !anyNA(got) && all(abs(got - want) <= 0.1)
gap <- function(got, want) sprintf(" (largest difference %.4f)", max(abs(got - want)))
wk_roto <- map_dbl(w18$results, "roto")[ref_i]
wk_luck <- map_dbl(w18$results, "luck")[ref_i]
pw_roto <- map_dbl(w18$power, "roto")[ref_i]
pw_luck <- map_dbl(w18$power, "luck")[ref_i]

per_week_actual <- map(weeks, \(x) as_tibble(x$actual)) |> bind_rows()
grid <- count(stats, week)

message("Checks:")
passed <- c(
  check(
    sprintf("%d weeks x %d teams, no missing values", N_WEEKS, N_TEAMS),
    nrow(grid) == N_WEEKS && all(grid$n == N_TEAMS) && n_distinct(stats$team) == N_TEAMS &&
      !anyNA(stats) && !anyNA(stats$opp_i)
  ),
  check(
    "every Actual record matches Cat W/L/T in the data",
    identical(per_week_actual$w, as.integer(stats$cat_w)) &&
      identical(per_week_actual$l, as.integer(stats$cat_l)) &&
      identical(per_week_actual$t, as.integer(stats$cat_t))
  ),
  check(
    paste0(sprintf("week %d roto totals match my in-season page within 0.1", CHECK_WEEK), gap(wk_roto, reference$week_roto)),
    close(wk_roto, reference$week_roto)
  ),
  check(
    paste0(sprintf("week %d luck matches within 0.1", CHECK_WEEK), gap(wk_luck, reference$week_luck)),
    close(wk_luck, reference$week_luck)
  ),
  check(
    paste0(sprintf("Season Rank totals through week %d match within 0.1", CHECK_WEEK), gap(pw_roto, reference$power_roto)),
    close(pw_roto, reference$power_roto)
  ),
  check(
    paste0(sprintf("Season Rank luck through week %d matches within 0.1", CHECK_WEEK), gap(pw_luck, reference$power_luck)),
    close(pw_luck, reference$power_luck)
  )
)

final <- out$by_week[[N_WEEKS]]$power
message("Final category records (Actual, weeks 1-", N_WEEKS, "), to compare with the league's final standings:")
print(
  tibble(
    team = teams,
    record = map_chr(final, \(r) paste(r$actual, collapse = "-")),
    win_share = map_dbl(final, \(r) (r$actual[1] + 0.5 * r$actual[3]) / sum(r$actual)),
    season_rank = map_int(final, "rank")
  ) |>
    arrange(desc(win_share)) |>
    mutate(win_share = round(win_share, 3)) |>
    as.data.frame(),
  row.names = FALSE
)

if (!all(passed)) stop("Some checks failed; nothing was written.", call. = FALSE)


# ---- Write -------------------------------------------------------------------

path <- here("power-rankings", "data", "rankings.json")
write_json(out, path, auto_unbox = TRUE, digits = NA)
message("Wrote power-rankings/data/rankings.json (", N_WEEKS, " weeks)")


# ---- Weighting heatmap for the README ----------------------------------------

# One row per Season Rank (as of week n), one column per week played; each cell is that week's share of the weight.
weights <- map(seq_len(N_WEEKS), \(n) tibble(as_of = n, played = seq_len(n), share = season_weights(n))) |>
  bind_rows() |>
  mutate(label = if_else(share >= 0.01, sprintf("%.0f%%", 100 * share), ""))

heatmap <- ggplot(weights, aes(played, as_of, fill = share)) +
  geom_tile(colour = "white", linewidth = 0.4) +
  geom_text(aes(label = label, colour = share > 0.3), size = 2.2, show.legend = FALSE) +
  scale_fill_gradient(
    low = "#e3eefa", high = "#0b3d75", trans = "sqrt", limits = c(0, 1),
    breaks = c(0.01, 0.1, 0.25, 0.5, 1), labels = c("1%", "10%", "25%", "50%", "100%"), name = "Share of\nthe weight"
  ) +
  scale_colour_manual(values = c(`FALSE` = "#1a1a1a", `TRUE` = "white")) +
  scale_x_continuous(breaks = seq_len(N_WEEKS), expand = c(0, 0), position = "top") +
  scale_y_reverse(breaks = seq_len(N_WEEKS), expand = c(0, 0)) +
  labs(
    title = "How each week counts in the Season Rank",
    subtitle = sprintf("Each week counts %.1f times as much as the week after it. Blank cells are under 1%%.", DECAY),
    x = "Week played", y = "Season Rank as of week"
  ) +
  coord_equal() +
  theme_minimal(base_size = 9) +
  theme(
    plot.background = element_rect(fill = "white", colour = NA), panel.grid = element_blank(),
    plot.title = element_text(face = "bold", size = 11), plot.title.position = "plot",
    legend.title = element_text(size = 8)
  )
ggsave(here("power-rankings", "weighting-heatmap.png"), heatmap, width = 7, height = 6.6, dpi = 200)
message("Wrote power-rankings/weighting-heatmap.png")
