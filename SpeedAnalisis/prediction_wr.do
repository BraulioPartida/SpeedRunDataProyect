*******************************************************
* ENHANCED TOP WR CANDIDATES VISUALIZATION & ANALYSIS
* Improved version with dynamic metrics, better charts, and detailed analysis
*******************************************************

clear all
set more off

* --- 1. Data Loading with Error Handling --------------------------------
capture confirm file "SpeedAnalisis/wr_predictions_test.dta"
if _rc {
    di as error "Error: wr_predictions_test.dta not found!"
    di as error "Please run regression3.do first to generate predictions."
    exit 111
}

use "SpeedAnalisis/wr_predictions_test.dta", clear

* Check required variables exist
capture confirm variable wr_probability WR_next_30_days player_name game_name category_name
if _rc {
    di as error "Error: Required variables missing in dataset!"
    exit 111
}

* Calculate baseline rate (for enrichment calculation)
quietly summarize WR_next_30_days
local baseline_rate = r(mean)
local baseline_pct = `baseline_rate' * 100

* --- Create graphs folder ------------------------------------------------
local graphs_folder "C:\Users\brown\Desktop\‌\ITAM\DDD\Proyect\SpeedAnalisis\graphs"
capture mkdir "`graphs_folder'"
if _rc != 0 {
    di as error "Warning: Could not create graphs folder. Graphs will be saved in current directory."
    local graphs_folder "."
}
else {
    di as text "Graphs will be saved to: `graphs_folder'"
}

* --- 2. Calculate Model Performance Metrics (Dynamic) -------------------
* Calculate AUC
quietly roctab WR_next_30_days wr_probability, detail
local model_auc = r(area)

* Sort by probability and rank all observations
gsort -wr_probability
gen rank = _n
gen in_top20 = (rank <= 20)

* Calculate top 20 performance
count if WR_next_30_days == 1 & rank <= 20
local n_wr_top20 = r(N)
local success_rate_top20 = (`n_wr_top20' / 20) * 100
local enrichment = (`n_wr_top20' / 20) / `baseline_rate'

* --- 3. Game Name Shortening (Enhanced) --------------------------------
gen game_short = game_name

* Major franchises
replace game_short = "Zelda: BOTW" if strpos(game_name, "Breath of the Wild")
replace game_short = "OoT Extensions" if strpos(game_name, "Ocarina of Time")
replace game_short = "Super Mario 64" if strpos(game_name, "Super Mario 64")
replace game_short = "Super Mario Odyssey" if strpos(game_name, "Super Mario Odyssey")
replace game_short = "Super Mario" if strpos(game_name, "Super Mario") & game_short == game_name

* Indie/Popular Games
replace game_short = "Hollow Knight" if strpos(game_name, "Hollow Knight") & !strpos(game_name, "Silksong")
replace game_short = "HK: Silksong" if strpos(game_name, "Silksong")
replace game_short = "Celeste" if game_name == "Celeste"
replace game_short = "Cuphead" if game_name == "Cuphead"
replace game_short = "ULTRAKILL" if game_name == "ULTRAKILL"
replace game_short = "Hades" if strpos(game_name, "Hades") & !strpos(game_name, "2") & !strpos(game_name, "II")
replace game_short = "Hades 2" if strpos(game_name, "Hades") & (strpos(game_name, "2") | strpos(game_name, "II"))
replace game_short = "Pizza Tower" if strpos(game_name, "Pizza Tower")

* Puzzle/Platform
replace game_short = "Portal" if game_name == "Portal" & !strpos(game_name, "2")
replace game_short = "Portal 2" if strpos(game_name, "Portal 2")
replace game_short = "Getting Over It" if strpos(game_name, "Getting Over It") | strpos(game_name, "Bennett Foddy")

* RPG/Adventure
replace game_short = "Skyrim" if strpos(game_name, "Skyrim")
replace game_short = "Elden Ring" if strpos(game_name, "Elden Ring")

* Horror
replace game_short = "Outlast" if game_name == "Outlast"
replace game_short = "Resident Evil 2" if strpos(game_name, "Resident Evil 2") | strpos(game_name, "RE2")
replace game_short = "Poppy Playtime" if strpos(game_name, "Poppy")

* Online/Multiplayer
replace game_short = "Minecraft" if strpos(game_name, "Minecraft")
replace game_short = "Roblox: DOORS" if strpos(game_name, "DOORS")

* --- 4. Create Labels and Formatting ------------------------------------
gen label_short = player_name + " - " + category_name
gen label_with_game = player_name + " | " + game_name
gen label_full = player_name + " (" + game_name + "): " + category_name
gen label_compact = player_name + " | " + game_short + " | " + category_name

* Probability formatting
format wr_probability %6.4f
gen prob_pct = wr_probability * 100
format prob_pct %5.1f

* WR status indicator
gen wr_status = "✓ WR" if WR_next_30_days == 1
replace wr_status = "  —" if WR_next_30_days == 0

* Probability levels for color coding
gen prob_level = 1 if wr_probability < 0.3
replace prob_level = 2 if wr_probability >= 0.3 & wr_probability < 0.6
replace prob_level = 3 if wr_probability >= 0.6 & wr_probability < .

label define prob_lbl 1 "Low (< 30%)" 2 "Medium (30-60%)" 3 "High (≥ 60%)"
label values prob_level prob_lbl

* --- 5. Enhanced Visualizations -----------------------------------------

* Keep top 20 for focused visualizations
preserve
    keep if rank <= 20

    * Chart 1: Top 20 with dynamic metrics in subtitle
    graph hbar wr_probability, ///
        over(label_with_game, sort(wr_probability) descending label(labsize(vsmall))) ///
        ytitle("Probability of WR in Next 30 Days", size(small)) ///
        title("Top 20 Players Most Likely to Achieve World Record", size(medium) color(black)) ///
        subtitle("Player | Game | AUC: `: di %5.3f `model_auc'' | Success Rate: `: di %4.1f `success_rate_top20''%", size(small)) ///
        note("Predictions based on 29 features: performance, momentum, engagement, competition" ///
             "Enrichment: `: di %4.1f `enrichment''x vs baseline (`: di %4.1f `baseline_pct''%)", size(vsmall)) ///
        bar(1, color(navy*0.8) lcolor(navy)) ///
        ylabel(0(0.1)1, format(%3.1f) labsize(small)) ///
        graphregion(color(white) margin(medium)) bgcolor(white) ///
        plotregion(margin(small))
    
    graph export "`graphs_folder'/top_20_wr_with_games.png", replace width(1600) height(1000)

    * Chart 2: Full labels with actual outcomes highlighted
    * Create separate bars for WR achieved vs not achieved
    gen wr_achieved = (WR_next_30_days == 1)
    label define wr_lbl 0 "No WR" 1 "WR Achieved"
    label values wr_achieved wr_lbl
    
    graph hbar wr_probability, ///
        over(label_compact, sort(wr_probability) descending label(labsize(tiny))) ///
        over(wr_achieved, label(labsize(small))) ///
        ytitle("Probability of WR in Next 30 Days", size(small)) ///
        title("Top 20 WR Candidates: Player | Game | Category", size(medium) color(black)) ///
        subtitle("Green bars = Actual WR achieved | Based on Enhanced Logit Model (29 Features)", size(small)) ///
        note("Model correctly identified `n_wr_top20' WR holders in top 20 (`: di %4.1f `success_rate_top20''% success rate)", size(vsmall)) ///
        bar(1, color(red*0.6) lcolor(red)) ///
        bar(2, color(green*0.7) lcolor(green)) ///
        ylabel(0(0.1)1, format(%3.1f) labsize(small)) ///
        legend(order(2 "WR Achieved" 1 "No WR") position(6) rows(1) size(small)) ///
        graphregion(color(white) margin(medium)) bgcolor(white) ///
        plotregion(margin(small))
    
    graph export "`graphs_folder'/top_20_full_labels.png", replace width(1600) height(1000)

    * Chart 3: Color-coded by probability level with actual outcomes
    graph hbar wr_probability, ///
        over(label_with_game, sort(wr_probability) descending label(labsize(tiny))) ///
        over(prob_level, label(labsize(small))) ///
        ytitle("Probability of WR in Next 30 Days", size(small)) ///
        title("Top 20 WR Candidates by Risk Level", size(medium) color(black)) ///
        subtitle("Player | Game | Color indicates probability tier", size(small)) ///
        bar(1, color(red*0.6) lcolor(red)) ///
        bar(2, color(orange*0.7) lcolor(orange)) ///
        bar(3, color(green*0.6) lcolor(green)) ///
        ylabel(0(0.2)1, format(%3.1f) labsize(small)) ///
        legend(order(3 "High Probability (≥60%)" 2 "Medium (30-60%)" 1 "Low (<30%)") ///
               position(6) rows(1) size(small)) ///
        graphregion(color(white) margin(medium)) bgcolor(white) ///
        plotregion(margin(small))
    
    graph export "`graphs_folder'/top_20_by_risk_with_games.png", replace width(1600) height(1000)


restore

* --- 6. Additional Analysis Visualizations -----------------------------

* Chart 5: Predicted vs Actual (Calibration Plot)
preserve
    * Create bins for calibration
    gen prob_bin = floor(wr_probability * 10) / 10
    collapse (mean) actual_rate=WR_next_30_days (count) n=rank, by(prob_bin)
    gen predicted_rate = prob_bin
    gen n_sqrt = sqrt(n) * 2  // Scale for bubble size
    
    twoway (scatter actual_rate predicted_rate [w=n_sqrt], ///
            msymbol(circle) mcolor(navy*0.7) ///
            xlabel(0(0.1)1, format(%3.1f)) ylabel(0(0.1)1, format(%3.1f))) ///
           (function y=x, range(0 1) lcolor(red) lpattern(dash) lwidth(medium)), ///
        xtitle("Predicted Probability", size(small)) ///
        ytitle("Actual WR Rate", size(small)) ///
        title("Model Calibration: Predicted vs Actual WR Rates", size(medium) color(black)) ///
        subtitle("Bubble size = Number of observations | Red line = Perfect calibration", size(small)) ///
        legend(off) ///
        graphregion(color(white) margin(medium)) bgcolor(white) ///
        plotregion(margin(medium))
    
    graph export "`graphs_folder'/calibration_plot.png", replace width(1200) height(900)
restore

* Chart 6: Probability Distribution
histogram wr_probability, ///
    frequency ///
    normal ///
    xlabel(0(0.1)1, format(%3.1f)) ///
    xtitle("Predicted WR Probability", size(small)) ///
    ytitle("Frequency", size(small)) ///
    title("Distribution of Predicted WR Probabilities", size(medium) color(black)) ///
    subtitle("All test set observations", size(small)) ///
    note("Overlay shows normal distribution for reference", size(vsmall)) ///
    graphregion(color(white) margin(medium)) bgcolor(white) ///
    plotregion(margin(medium)) ///
    color(navy*0.7) lcolor(navy)
    
graph export "`graphs_folder'/probability_distribution.png", replace width(1200) height(800)

* Chart 7: Probability Distribution by Outcome (All Test Data)
preserve
    gen outcome_label = "WR Achieved" if WR_next_30_days == 1
    replace outcome_label = "No WR" if WR_next_30_days == 0
    
    twoway (histogram wr_probability if WR_next_30_days == 1, ///
            frequency color(green*0.6) lcolor(green) width(0.05)) ///
           (histogram wr_probability if WR_next_30_days == 0, ///
            frequency color(red*0.6) lcolor(red) width(0.05) fintensity(50)), ///
        xlabel(0(0.1)1, format(%3.1f)) ///
        xtitle("Predicted WR Probability", size(small)) ///
        ytitle("Frequency", size(small)) ///
        title("Probability Distribution: WR Achieved vs Not Achieved", size(medium) color(black)) ///
        subtitle("All test set observations", size(small)) ///
        legend(order(1 "WR Achieved" 2 "No WR") position(6) rows(1) size(small)) ///
        graphregion(color(white) margin(medium)) bgcolor(white) ///
        plotregion(margin(medium))
    
    graph export "`graphs_folder'/probability_distribution_by_outcome.png", replace width(1200) height(800)
restore

* --- 7. Detailed Table Output -------------------------------------------
preserve
    keep if rank <= 20
    
    list rank player_name game_short category_name prob_pct wr_status in 1/20, ///
        table clean noobs separator(5) ///
        string(30)
restore

* --- 8. Enhanced Excel Export -------------------------------------------
preserve
    keep if rank <= 20
    gen prob_pct_formatted = string(prob_pct, "%5.1f") + "%"
    
    export excel rank player_name game_name game_short category_name ///
                 wr_probability prob_pct_formatted WR_next_30_days wr_status ///
        using "top_20_wr_candidates_detailed.xlsx" in 1/20, ///
        firstrow(variables) replace sheet("Top 20 Candidates")
restore

* --- 9. Summary Statistics by Game --------------------------------------
di as text ""
di as text "========================================================="
di as text "         TOP CANDIDATES BY GAME"
di as text "========================================================="
di as text ""

preserve
    keep if rank <= 20
    tab game_short, sort
restore

di as text ""
di as text "Games with most top candidates:"

preserve
    keep if rank <= 20
    sort game_short
    bysort game_short: gen game_count = _N
    bysort game_short: gen first = (_n == 1)
    gsort -game_count game_short
    list game_short game_count if first, clean noobs
restore

di as text ""
di as text "Average probability by game (top 20 only):"

preserve
    keep if rank <= 20
    collapse (mean) avg_prob=wr_probability (count) n_players=rank (sum) n_wr=WR_next_30_days, by(game_short)
    gen avg_prob_pct = avg_prob * 100
    format avg_prob_pct %5.1f
    gen success_rate = (n_wr / n_players) * 100 if n_players > 0
    format success_rate %5.1f
    gsort -avg_prob
    di as text "Game" _col(25) "Avg Prob %" _col(40) "Players" _col(50) "WRs" _col(55) "Success %"
    di as text "---------------------------------------------------------"
    list game_short avg_prob_pct n_players n_wr success_rate, ///
        clean noobs table
restore

* --- 10. Enhanced Performance Summary -----------------------------------
di as text ""
di as text "========================================================="
di as text "         PREDICTION PERFORMANCE SUMMARY"
di as text "========================================================="
di as text ""

* Overall metrics
di as text "Model Performance Metrics:"
di as text "  AUC (Area Under ROC Curve):     " %6.4f `model_auc'
di as text "  Baseline WR Rate:               " %6.1f `baseline_pct' "%"
di as text "  Actual WRs in Top 20:           " %2.0f `n_wr_top20' " out of 20"
di as text "  Success Rate (Top 20):         " %6.1f `success_rate_top20' "%"
di as text "  Enrichment Factor:              " %6.1f `enrichment' "x vs baseline"
di as text ""

* Performance by probability tier
di as text "Performance by Probability Tier:"
preserve
    keep if rank <= 20
    
    * High probability tier
    count if prob_level == 3
    local n_high = r(N)
    if `n_high' > 0 {
        count if WR_next_30_days == 1 & prob_level == 3
        local wr_high = r(N)
        local rate_high = (`wr_high' / `n_high') * 100
        di as text "  High (≥60%):   " %2.0f `n_high' " candidates, " `wr_high' " achieved WR (" %5.1f `rate_high' "%)"
    }
    
    * Medium probability tier
    count if prob_level == 2
    local n_med = r(N)
    if `n_med' > 0 {
        count if WR_next_30_days == 1 & prob_level == 2
        local wr_med = r(N)
        local rate_med = (`wr_med' / `n_med') * 100
        di as text "  Medium (30-60%):" %2.0f `n_med' " candidates, " `wr_med' " achieved WR (" %5.1f `rate_med' "%)"
    }
    
    * Low probability tier
    count if prob_level == 1
    local n_low = r(N)
    if `n_low' > 0 {
        count if WR_next_30_days == 1 & prob_level == 1
        local wr_low = r(N)
        local rate_low = (`wr_low' / `n_low') * 100
        di as text "  Low (<30%):    " %2.0f `n_low' " candidates, " `wr_low' " achieved WR (" %5.1f `rate_low' "%)"
    }
restore

* Statistical significance test
di as text ""
di as text "Statistical Test:"
preserve
    gen top20_indicator = (rank <= 20)
    tabulate WR_next_30_days top20_indicator, chi2
    local chi2_stat = r(chi2)
    local chi2_p = r(p)
    di as text "  Chi-square test (Top 20 vs Rest): χ² = " %6.2f `chi2_stat' ", p = " %6.4f `chi2_p'
restore

di as text ""
di as text "========================================================="
di as text ""
di as text "All visualizations and data exported successfully!"
di as text ""
di as text "Graphs saved to: `graphs_folder'"
di as text "Generated files:"
di as text "  - `graphs_folder'/top_20_wr_with_games.png (Main visualization)"
di as text "  - `graphs_folder'/top_20_full_labels.png (Full details with outcomes)"
di as text "  - `graphs_folder'/top_20_by_risk_with_games.png (Color-coded by risk)"
di as text "  - `graphs_folder'/top_20_grouped_by_game.png (Grouped by game)"
di as text "  - `graphs_folder'/calibration_plot.png (Model calibration)"
di as text "  - `graphs_folder'/probability_distribution.png (Overall distribution)"
di as text "  - `graphs_folder'/probability_distribution_by_outcome.png (By outcome)"
di as text "  - top_20_wr_candidates_detailed.xlsx (Excel export - current directory)"
di as text ""

*******************************************************
