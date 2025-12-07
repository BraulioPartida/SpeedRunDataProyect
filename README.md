# SpeedRun Data Project

A comprehensive data mining and predictive analytics project for analyzing speedrun data from [speedrun.com](https://www.speedrun.com). This project collects speedrun data via API, processes it using Stata, and builds machine learning models to predict which players and runs are most likely to become world records.

## Table of Contents

- [Overview](#overview)
- [Project Structure](#project-structure)
- [Features](#features)
- [Requirements](#requirements)
- [Installation](#installation)
- [Usage](#usage)
- [Data Collection](#data-collection)
- [Data Analysis](#data-analysis)
- [Results](#results)
- [License](#license)

## Overview

This project consists of two main components:

1. **SpeedDataMining** - A C# .NET application that collects speedrun data from the speedrun.com API
2. **SpeedAnalisis** - Stata scripts for data processing, feature engineering, and predictive modeling

The goal is to identify patterns and factors that predict whether a speedrun will become a world record within 30 days, using various machine learning techniques including OLS regression, LASSO, and logistic regression.

## Project Structure

```
SpeedRunDataProyect/
├── SpeedDataMining/          # C# data collection application
│   ├── Program.cs            # Main data collection script
│   ├── SpeedData.csproj      # Project configuration
│   └── bin/                  # Compiled binaries and output CSV files
│
├── SpeedAnalisis/            # Stata analysis scripts
│   ├── speedDataAnalisis3.do # Data processing and feature engineering
│   ├── regression3.do        # Model training and evaluation
│   ├── prediction_wr.do      # WR candidate prediction and visualization
│   ├── graphs/               # Generated visualizations
│   ├── graphs_regression3/   # Regression analysis graphs
│   ├── results_regression3/   # Model results and exports
│   └── *.dta                 # Stata data files
│
├── .gitignore
├── LICENSE
└── README.md
```

## Features

### Data Collection
- Fetches speedrun data for 20+ popular games
- Collects comprehensive run metadata including:
  - Run times and rankings
  - Player statistics and history
  - Category information
  - Video links and verification status
  - Platform and emulation data
- Calculates player-level statistics (total runs, games, categories, time improvements)
- Exports data to CSV format for analysis

### Data Analysis
- **Feature Engineering**: Creates 20+ predictive features including:
  - Performance metrics (PB times, percentiles, variance)
  - Player characteristics (experience, specialization, activity)
  - Game-level metrics (competitiveness, niche index)
  - Momentum indicators (activity trends, consistency)
  
- **Predictive Modeling**: Implements three models:
  - **OLS Regression**: Linear prediction model
  - **LASSO**: Regularized regression with feature selection
  - **Logistic Regression**: Probability-based classification

- **Evaluation Metrics**:
  - AUC (Area Under Curve)
  - Precision, Recall, F1-Score
  - Calibration plots
  - ROC curves
  - Top-20 candidate identification

- **Visualizations**:
  - Probability distributions
  - Calibration plots
  - ROC curves for model comparison
  - Top WR candidates with detailed breakdowns

## Requirements

### For Data Collection (SpeedDataMining)
- .NET 10.0 SDK or later
- Internet connection for API access
- NuGet packages (automatically restored):
  - `SpeedrunComApi` (v0.0.15)
  - `SrcomLib` (v1.0.3)

### For Data Analysis (SpeedAnalisis)
- Stata (version 14 or later recommended)
- Required Stata packages (installed automatically by scripts):
  - `asrol` - Rolling statistics
  - `lassopack` - LASSO regression
  - Standard Stata packages for regression and visualization

## Installation

1. **Clone the repository**:
   ```bash
   git clone <repository-url>
   cd SpeedRunDataProyect
   ```

2. **Build the C# application**:
   ```bash
   cd SpeedDataMining
   dotnet restore
   dotnet build
   ```

3. **Install Stata packages** (if needed):
   The Stata scripts will automatically install required packages on first run.

## Usage

### Step 1: Collect Data

Run the C# application to collect speedrun data:

```bash
cd SpeedDataMining
dotnet run
```

This will:
- Query the speedrun.com API for multiple games
- Collect run data, player statistics, and leaderboard information
- Export results to `speedrun_data.csv` in the `bin/Debug/net10.0/` directory

**Note**: The data collection process may take several minutes due to API rate limiting.

### Step 2: Process Data

Open Stata and run the data processing script:

```stata
do speedDataAnalisis3.do
```

This script:
- Loads the CSV data
- Creates a panel dataset
- Engineers features for prediction
- Saves processed data as `speedrun_panel3.dta`

**Important**: Update the file paths in the Stata scripts to match your system paths.

### Step 3: Train Models

Run the regression analysis:

```stata
do regression3.do
```

This script:
- Splits data into training (70%) and test (30%) sets
- Trains OLS, LASSO, and Logit models
- Evaluates model performance
- Generates predictions and saves results

### Step 4: Predict WR Candidates

Generate predictions and visualizations:

```stata
do prediction_wr.do
```

This script:
- Loads model predictions
- Identifies top 20 WR candidates
- Generates detailed visualizations
- Exports results to Excel

## Data Collection

The data collection process gathers information on:

- **Games**: Minecraft, Celeste, Portal, Hollow Knight, Super Mario Odyssey, and 15+ more
- **Runs**: All submitted runs with metadata
- **Players**: Statistics including total runs, games played, categories, and improvement rates
- **Categories**: All speedrun categories per game
- **Leaderboards**: Rankings and world record information

### Data Fields

The collected CSV includes:
- Run identifiers (run_id, game_id, category_id)
- Timing data (time_seconds, date_submitted)
- Player information (player_id, player_name, player statistics)
- Performance metrics (rank, is_wr, total_runners_in_category)
- Media (video_link, has_video)
- Platform information (platform, emulated)
- Player history (total_runs, total_games, time_improvement, days_active)

## Data Analysis

### Feature Categories

1. **Performance Features**:
   - `pb_time_current_month`: Personal best time in current month
   - `pb_percentile`: Percentile rank within category
   - `var90`: Variance of times in last 90 days
   - `mean_attempts_per_day`: Average attempts per day

2. **Game-Level Features**:
   - `total_runs_game_month`: Total runs in game for the month
   - `competition_intensity`: Level of competition in category
   - `game_age`: Years since game release

3. **Player Features**:
   - `player_total_runs`: Total runs by player
   - `player_specialization`: Category specialization index
   - `player_activity_span`: Days active as speedrunner

4. **Momentum Features**:
   - `activity_momentum`: Recent activity trend
   - `consistency_score`: Consistency of performance
   - `improved`: Whether run is a personal best

### Target Variable

- `WR_next_30_days`: Binary indicator (1 if run becomes WR within 30 days, 0 otherwise)

## Results

The analysis produces:

1. **Model Comparison**: Performance metrics comparing OLS, LASSO, and Logit models
2. **Top 20 WR Candidates**: Ranked list of runs most likely to become world records
3. **Visualizations**:
   - Probability distributions by outcome
   - Calibration plots
   - ROC curves for each model
   - Detailed candidate breakdowns by game and category

Results are saved in:
- `results_regression3/`: Model outputs and Excel exports
- `graphs_regression3/`: Model evaluation graphs
- `graphs/`: WR candidate visualizations

## Notes

- **File Paths**: Update the file paths in Stata scripts to match your system
- **API Rate Limiting**: The C# application includes delays to respect API rate limits
- **Data Size**: Collected datasets can be large (100K+ runs); ensure sufficient disk space
- **Processing Time**: Full analysis pipeline may take 30+ minutes depending on data size

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Acknowledgments

- Data provided by [speedrun.com](https://www.speedrun.com) API
- Built for academic research and analysis purposes

---

**Author**: BraulioP  
**Year**: 2025

