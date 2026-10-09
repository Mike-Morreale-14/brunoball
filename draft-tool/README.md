# Draft Scout 2026

Draft Scout is a fantasy baseball draft companion built on free public data and projections. It lists the draft pool in ADP order, scores hitters and starting pitchers on archetypes (Power, Speed and AVG; Anchor, K Arm and Volatility), and keeps track of your picks and everyone else's during the draft.

**[Read the user guide](GUIDE.md)** for a tour of every control, with annotated screenshots.

## How the scores work

- **Every input is a percentile** (0 to 100) within its group: the hitters, or the starting pitchers, in the draft pool (FantasyPros ADP 300 or better).
- **The archetype score** is the one score per archetype shown throughout the tool: a weighted mean of 2025 results, 2025 Baseball Savant skill measures and the 2026 Marcel projection. Its weights can be changed with the sliders under "Score Dictionary & Weights", and every score updates as you drag.
- **2025 Results vs Skills**, a section on each player page, scores Power, AVG, Anchor and K Arm two more ways:
  - **Results** uses 2025 results as rates (HR per PA, AVG, ERA, QS per start and so on), never counting stats, so playing time doesn't drive it.
  - **Skills** uses 2025 Statcast skill measures (barrels, exit velocity, xBA, xERA, whiff rate and so on).
  - **Gap** is Skills minus Results. Green means the skills point to better results than the player got; red means the results ran ahead of the skills.
  - Gaps for players with fewer than 200 PA or 50 IP in 2025 carry a "small 2025 sample" flag.
  - Speed and Volatility aren't compared: Speed's skill side is sprint speed, already in the Speed score, and Volatility is already built from Statcast contact numbers.
- **Reliability** is a 0–100 blend of recent playing time, projected playing time and age. The Score Dictionary in the tool lists its inputs and weights.
- **Relievers** are shown with stats and projections only. Marcel doesn't project saves, so there's no closer score.
- **The weights** are my own judgement, not fitted to data.

## Where the data comes from

The site reads only the files in [`data/`](data/): `hitters.json`, `sp.json`, `relievers.json` and `weights.json`. They're written by [`data-pipeline/04_scores.R`](../data-pipeline/04_scores.R). The [pipeline README](../data-pipeline/README.md) explains every source, cleaning rule and score input.

In short, the sources are:
- MLB Stats API and Baseball Savant data (© MLB Advanced Media, L.P.);
- the Chadwick Baseball Bureau player register (ODC-By);
- FantasyPros ADP;
- projections from the Marcel the Monkey Forecasting System by Tom Tango.

Player photos load from MLB's public image server.

## Running it locally

It's plain HTML, CSS and JavaScript with no build step. The page loads its data with `fetch`, so it has to be served over HTTP; opening `index.html` straight from disk won't load the players. From this folder, start any static file server, for example:

```
npx serve .                 # Node.js; then open http://localhost:3000
python -m http.server 8000  # or Python; then open http://localhost:8000
```

To host it, upload this folder as static files.

To refresh the data, run the pipeline from the brunoball folder (`Rscript data-pipeline/04_scores.R` after the earlier steps). It rewrites `data/`.
