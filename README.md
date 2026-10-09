# brunoball

I play in a 10-team, head-to-head categories fantasy baseball league
with friends ([league rules](LEAGUE_RULES.md)). Over the 2026 season
I built a few tools for it: a [draft tool](https://mike-morreale-14.github.io/brunoball/draft-tool/) the whole league could use 
before and during the draft, weekly power rankings for the group chat, 
and an end-of-season recap to commemorate the year.

## Draft Scout

[![Draft Scout](draft-tool/screenshot.png)](https://mike-morreale-14.github.io/brunoball/draft-tool/)

A draft tool that lists the top 300 players by FantasyPros ADP.
Hitters are scored on Power, Speed and AVG, and starting
pitchers on Anchor, K Arm and Volatility, so you can see what
role a player would fill on your team. Scores blend 2026
projections (Tom Tango's Marcel method), 2025 stats and Statcast
skills, and you can adjust the weights as you draft.

**[Try the draft tool](https://mike-morreale-14.github.io/brunoball/draft-tool/)**
· [How it works](draft-tool/) · [Data pipeline](data-pipeline/)

## Weekly Power Rankings

[![Power rank by week](power-rankings/rank-by-week.png)](https://mike-morreale-14.github.io/brunoball/power-rankings/)

Weekly roto and all-play results for my league, with power rankings that
weight recent weeks more, so you can see who was strong and who was lucky.

**[View the rankings](https://mike-morreale-14.github.io/brunoball/power-rankings/)**
· [How it works](power-rankings/)

## Season Wrapped

Coming soon: the end-of-season recap slideshow I made for the league.

## Replication

In progress: replicating well respected baseball analysis with updated data, an experiment to see how prior results trend as the league shifts over time. 

## Exploration

In progress: Trading research and new in-season visuals.

## AI Assistance

The code in this project is primarily written using Claude Code.  
