# Draft Scout 2026: public edition

Draft Scout is the fantasy baseball draft companion I built for my league's 2026 draft. It lists the draft pool in ADP order, scores hitters and starting pitchers on archetypes (Power, Speed and AVG; Anchor, K Arm and Volatility), and keeps track of your picks and everyone else's during the draft. This public edition rebuilds it on free public data and my own Marcel projections; the original used paid projections.

**[Read the user guide](GUIDE.md)** for a tour of every control, with annotated screenshots.

## How the scores work

- **Every input is a percentile** (0 to 100) within its group: the hitters, or the starting pitchers, in the draft pool (FantasyPros ADP 300 or better).
- **Main** is the headline score: a weighted mean of 2025 results, 2025 Baseball Savant skill measures and the 2026 Marcel projection. Its weights can be changed with the sliders under "Score Dictionary & Weights", and every score updates as you drag.
- **Raw** uses 2025 results as rates (HR per PA, AVG, ERA, QS per start and so on), never counting stats, so playing time doesn't drive it.
- **Underlying** uses 2025 Savant skill measures (barrels, exit velocity, xBA, xERA, whiff rate and so on).
- **The delta** is Underlying minus Raw. Green means the skills point to better results than the player got; red means the results ran ahead of the skills.
  - Speed shows no delta, because its Underlying includes contact rate, so the gap isn't a luck signal.
  - Deltas for players with fewer than 200 PA or 50 IP in 2025 carry a "small 2025 sample" flag.
- **Reliability** is the 2026 tool's score, rebuilt on 2023–25: a blend of recent playing time, projected playing time and age. The Score Dictionary in the tool explains it.
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
