# Power Rankings 2026

My league is 10 teams, head to head across 12 categories (R, HR, RBI, SB, AVG, OPS for hitters; W, SV, K, ERA, WHIP, QS for pitchers). A weekly record only shows how a team did against one opponent. This page shows how each team did against the whole league each week, and power rankings that weight recent weeks more.

**[View the rankings](https://mike-morreale-14.github.io/brunoball/power-rankings/)**

[<img src="rank-by-week.png" width="700" alt="Power rank by week, with Team Bruno highlighted">](https://mike-morreale-14.github.io/brunoball/power-rankings/)

## How it works

The page has two rankings. Both are built from roto points, but they cover different spans of the season.

### Weekly power rankings

One week only. Each week, all 10 teams are ranked 1 to 10 in each of the 12 categories on that week's stats: 10 points for first down to 1 for last (lower is better for ERA and WHIP). Tied teams split the points they cover. A team's total is the sum over the 12 categories, out of 120. It's a snapshot of who was best that week. On the page, this is the **Week N Results** table.

### Seasonally weighted power rankings

Every week so far, blended, with recent weeks counting most. What gets weighted is each week's category roto points from the weekly rankings, not the raw stats. Each week counts 0.8 times as much as the week after it. The weighted points are averaged in each category and summed over the 12 categories. On the page, this is the **Power Rankings through Week N** table.

At week 22, that puts 20% of the weight on the latest week, 59% on the last 4 weeks and 90% on the last 10 weeks. The rankings follow a team's current form after trades, injuries and call-ups, but the early season still counts.

### All-play, luck and 70+ weeks

- **All-play.** Each team's categories are compared with all 9 other teams that week, as if it had played everyone. That's 108 category matchups a week, shown as a win-loss-tie record.
- **Avg.** The all-play record divided by 9: the record a team would expect against a typical opponent.
- **Actual.** The category record against that week's real opponent.
- **Luck.** Actual win share minus all-play win share, with ties counted as half a win. A positive number means the team won more categories than its all-play results would suggest; a negative number means fewer.
- **70+ Wk.** The number of weeks a team won 70 or more of its 108 all-play matchups.

In the seasonally weighted table, the Avg and Actual records are season totals, without weighting.

## Reading the page

- Pick a week with the menu or the arrows; it opens on week 22, the last week of the regular season.
- **Week N Results** shows that week: each team's stats in the 12 categories, its roto total and its all-play, actual and luck numbers.
- **Power Rankings through Week N** shows the weighted category points and the season's records up to that week.
- Teams are rows, sorted by rank. Cells are shaded from red (lowest in the column) to green (highest), by rank, so a low ERA is green. Luck is green above +0.05 and red below −0.05; 70+ Wk is green at 3 or more.
- The chart shows every team's seasonally weighted power rank after each week. Hover over a line or a team name to pick it out.

## Data and rerunning

The data is my league's weekly Yahoo results, in [`data/weekly_stats_2026.csv`](data/weekly_stats_2026.csv): one row per team per week, with the opponent, the 12 categories and the category record.

To rebuild `data/rankings.json`, run this from the brunoball folder:

```
Rscript power-rankings/build_rankings.R
```

The script prints its checks and stops without writing anything if one fails. The page is plain HTML, CSS and JavaScript; to view it locally, serve the brunoball folder with any static file server (for example `python -m http.server 8000`) and open http://localhost:8000/power-rankings/.
