*******************************************************
* ENHANCED WR PREDICTION: OLS, LASSO, LOGIT
* Improved version with error handling, additional metrics, 
* better visualizations, and organized output
*******************************************************

clear all
set more off
set seed 12345

* --- 1. Data Loading with Error Handling --------------------------------
capture confirm file "C:\Users\brown\Desktop\‌\ITAM\DDD\Proyect\SpeedAnalisis\speedrun_panel3.dta"
if _rc {
    di as error "Error: speedrun_panel3.dta not found!"
    di as error "Please run speedDataAnalisis3.do first to generate the panel dataset."
    exit 111
}

use "C:\Users\brown\Desktop\‌\ITAM\DDD\Proyect\SpeedAnalisis\speedrun_panel3.dta", clear

* Check required variables
capture confirm variable WR_next_30_days
if _rc {
    di as error "Error: WR_next_30_days variable missing!"
    exit 111
}

* Drop observations with missing values in key variables
drop if missing(var90) | missing(pb_percentile) | missing(mean_attempts_per_day)

* Create output folders
local graphs_folder "C:\Users\brown\Desktop\‌\ITAM\DDD\Proyect\SpeedAnalisis\graphs_regression3"
capture mkdir "`graphs_folder'"

di as text "Output folders created/verified"
di as text "  Graphs: `graphs_folder'"
di as text ""

* --- 2. Train / Test Split --------------------------------------------
gen random_var = runiform()
gen train = (random_var <= 0.7)
drop random_var

di as text "Train/Test Split:"
tab WR_next_30_days train, row

* --- 3. Define Predictors (EXPANDED WITH NEW FEATURES) ----------------
global Xvars_base pb_time_current_month pb_percentile var90 mean_attempts_per_day ///
                  cross_category_switching experience_months attempts_month

global Xvars_game total_runs_game_month active_players_game_month game_niche_index ///
                  category_competitiveness competition_intensity game_age

global Xvars_player best_rank_month time_improvement video_proof_rate ///
                    avg_comment_length emulation_rate player_specialization ///
                    is_multi_game_player player_activity_span ///
                    player_total_runs player_total_games player_total_categories ///
                    player_avg_time_improvement

global Xvars_momentum activity_momentum consistency_score is_personal_best improved

* Combined full set
global Xvars $Xvars_base $Xvars_game $Xvars_player $Xvars_momentum

* Display feature count
local nfeatures : word count $Xvars
di as text "Total features: `nfeatures'"
di as text ""

* --- 4. Install required packages -------------------------------------
cap which lassologit
if _rc {
    di as text "Installing lassopack..."
    ssc install lassopack
}

* --- 5. Enhanced Evaluation Program with Additional Metrics -----------
capture program drop predict_wr_enhanced
program define predict_wr_enhanced
    args command options

    local vars $Xvars
    di as text "==========================================================="
    di as text "Running `command'..."
    di as text "==========================================================="

    * Run model
    quietly `command' WR_next_30_days `vars' if train == 1, `options'
    estimates store `command'
    
    * Get predictions (probabilities for logit, linear for others)
    capture drop y_`command' prob_`command'
    if "`command'" == "logit" {
        predict prob_`command' if train == 0, pr
    }
    else if "`command'" == "cvlasso" {
        predict y_`command' if train == 0, xb
        * Normalize linear predictions to [0,1] range for threshold comparison
        quietly summarize y_`command' if train == 0
        local min_pred = r(min)
        local max_pred = r(max)
        local range = `max_pred' - `min_pred'
        if `range' > 0.0001 {
            gen prob_`command' = (y_`command' - `min_pred') / `range' if train == 0
        }
        else {
            gen prob_`command' = y_`command' if train == 0
        }
    }
    else {
        predict y_`command' if train == 0, xb
        * Normalize linear predictions to [0,1] range for threshold comparison
        quietly summarize y_`command' if train == 0
        local min_pred = r(min)
        local max_pred = r(max)
        local range = `max_pred' - `min_pred'
        if `range' > 0.0001 {
            gen prob_`command' = (y_`command' - `min_pred') / `range' if train == 0
        }
        else {
            gen prob_`command' = y_`command' if train == 0
        }
    }
    
    * Calculate base rate in test set
    quietly summarize WR_next_30_days if train == 0
    local base_rate = r(mean)
    
    * Calculate AUC (threshold-free metric)
    capture drop roc_`command'
    quietly roctab WR_next_30_days prob_`command' if train == 0, detail
    global auc_`command' = r(area)
    
    * Try multiple thresholds and find optimal (Youden's index)
    di as text ""
    di as text "Threshold    MPE      Accuracy    Sensitivity    Specificity    Precision    F1      Youden"
    di as text "------------------------------------------------------------------------------------------------"
    
    local best_youden = -1
    local best_thresh = 0.2
    local best_f1 = -1
    local best_thresh_f1 = 0.2
    
    foreach thresh in 5 10 15 20 25 30 35 40 45 50 {
        local t = `thresh' / 100
        capture drop pred_t`thresh' correct_t`thresh' pe_t`thresh'
        
        * Generate predictions at this threshold
        gen pred_t`thresh' = (prob_`command' >= `t') if train == 0
        gen pe_t`thresh' = abs(pred_t`thresh' - WR_next_30_days) if train == 0
        gen correct_t`thresh' = (pred_t`thresh' == WR_next_30_days) if train == 0
        
        * Calculate metrics
        quietly summarize pe_t`thresh'
        local mpe = r(mean)
        
        quietly summarize correct_t`thresh'
        local accuracy = r(mean)
        
        * Sensitivity (recall for WR=1)
        quietly summarize pred_t`thresh' if WR_next_30_days == 1 & train == 0
        local sensitivity = r(mean)
        if missing(`sensitivity') local sensitivity = 0
        
        * Specificity (recall for WR=0)
        quietly count if WR_next_30_days == 0 & pred_t`thresh' == 0 & train == 0
        local tn = r(N)
        quietly count if WR_next_30_days == 0 & train == 0
        local total_neg = r(N)
        if `total_neg' > 0 {
            local specificity = `tn' / `total_neg'
        }
        else {
            local specificity = 0
        }
        
        * Precision (positive predictive value)
        quietly count if pred_t`thresh' == 1 & train == 0
        local total_pos_pred = r(N)
        if `total_pos_pred' > 0 {
            quietly count if pred_t`thresh' == 1 & WR_next_30_days == 1 & train == 0
            local tp = r(N)
            local precision = `tp' / `total_pos_pred'
        }
        else {
            local precision = 0
        }
        if missing(`precision') local precision = 0
        
        * F1 Score
        if (`precision' + `sensitivity') > 0 {
            local f1 = 2 * (`precision' * `sensitivity') / (`precision' + `sensitivity')
        }
        else {
            local f1 = 0
        }
        if missing(`f1') local f1 = 0
        
        * Youden's index (sensitivity + specificity - 1)
        local youden = `sensitivity' + `specificity' - 1
        
        di as text %5.2f `t' "      " %6.4f `mpe' "   " %6.4f `accuracy' "      " %6.4f `sensitivity' "         " %6.4f `specificity' "      " %6.4f `precision' "   " %6.4f `f1' "   " %6.4f `youden'
        
        * Track best threshold (highest Youden's index)
        if `youden' > `best_youden' {
            local best_youden = `youden'
            local best_thresh = `t'
        }
        
        * Track best F1 threshold
        if `f1' > `best_f1' {
            local best_f1 = `f1'
            local best_thresh_f1 = `t'
        }
        
        * Store metrics for threshold 0.2 (for comparison)
        if `thresh' == 20 {
            global mpe_`command' = `mpe'
            global acc_`command' = `accuracy'
            global sens_`command' = `sensitivity'
            global spec_`command' = `specificity'
            global prec_`command' = `precision'
            global f1_`command' = `f1'
        }
    }
    
    * Calculate metrics at optimal threshold (Youden's)
    capture drop pred_opt correct_opt pe_opt
    gen pred_opt = (prob_`command' >= `best_thresh') if train == 0
    gen pe_opt = abs(pred_opt - WR_next_30_days) if train == 0
    gen correct_opt = (pred_opt == WR_next_30_days) if train == 0
    
    quietly summarize pe_opt
    local mpe_opt = r(mean)
    quietly summarize correct_opt
    local acc_opt = r(mean)
    quietly summarize pred_opt if WR_next_30_days == 1 & train == 0
    local sens_opt = r(mean)
    if missing(`sens_opt') local sens_opt = 0
    quietly count if WR_next_30_days == 0 & pred_opt == 0 & train == 0
    local tn = r(N)
    quietly count if WR_next_30_days == 0 & train == 0
    local total_neg = r(N)
    if `total_neg' > 0 {
        local spec_opt = `tn' / `total_neg'
    }
    else {
        local spec_opt = 0
    }
    if missing(`spec_opt') local spec_opt = 0
    
    * Precision and F1 at optimal threshold
    quietly count if pred_opt == 1 & train == 0
    local total_pos_pred = r(N)
    if `total_pos_pred' > 0 {
        quietly count if pred_opt == 1 & WR_next_30_days == 1 & train == 0
        local tp = r(N)
        local prec_opt = `tp' / `total_pos_pred'
    }
    else {
        local prec_opt = 0
    }
    if missing(`prec_opt') local prec_opt = 0
    
    if (`prec_opt' + `sens_opt') > 0 {
        local f1_opt = 2 * (`prec_opt' * `sens_opt') / (`prec_opt' + `sens_opt')
    }
    else {
        local f1_opt = 0
    }
    if missing(`f1_opt') local f1_opt = 0
    
    * Store optimal threshold metrics
    global mpe_opt_`command' = `mpe_opt'
    global acc_opt_`command' = `acc_opt'
    global sens_opt_`command' = `sens_opt'
    global spec_opt_`command' = `spec_opt'
    global prec_opt_`command' = `prec_opt'
    global f1_opt_`command' = `f1_opt'
    global thresh_opt_`command' = `best_thresh'
    global thresh_f1_`command' = `best_thresh_f1'
    global f1_max_`command' = `best_f1'
    
    di as text "------------------------------------------------------------------------------------------------"
    di as text "Optimal threshold (Youden): " %5.2f `best_thresh' " (Youden's index: " %5.4f `best_youden' ")"
    di as text "Optimal threshold (F1):     " %5.2f `best_thresh_f1' " (F1 score: " %5.4f `best_f1' ")"
    di as text "AUC: " %5.4f ${auc_`command'}
    di as text "Base rate of WR in test set: " %5.4f `base_rate'
    di as text ""
end

* --- 6. Run Enhanced Analysis -----------------------------------------
predict_wr_enhanced reg
predict_wr_enhanced cvlasso
predict_wr_enhanced logit

* --- 7. Enhanced Summary Tables ---------------------------------------
di as text ""
di as text "========================================================="
di as text "        MODEL COMPARISON (AUC - Threshold-Free)"
di as text "========================================================="
di as text "Model          AUC"
di as text "-------------------------------------------------------------"
di as text "OLS       " %9.4f ${auc_reg}
di as text "LASSO     " %9.4f ${auc_cvlasso}
di as text "LOGIT     " %9.4f ${auc_logit}
di as text "========================================================="
di as text ""

di as text "========================================================="
di as text "        MODEL COMPARISON (Fixed Threshold = 0.2)"
di as text "========================================================="
di as text "Model          MPE      Accuracy    Sensitivity    Specificity    Precision    F1"
di as text "-------------------------------------------------------------"
di as text "OLS       " %9.4f ${mpe_reg} "   " %9.4f ${acc_reg} "      " %9.4f ${sens_reg} "         " %9.4f ${spec_reg} "      " %9.4f ${prec_reg} "   " %9.4f ${f1_reg}
di as text "LASSO     " %9.4f ${mpe_cvlasso} "   " %9.4f ${acc_cvlasso} "      " %9.4f ${sens_cvlasso} "         " %9.4f ${spec_cvlasso} "      " %9.4f ${prec_cvlasso} "   " %9.4f ${f1_cvlasso}
di as text "LOGIT     " %9.4f ${mpe_logit} "   " %9.4f ${acc_logit} "      " %9.4f ${sens_logit} "         " %9.4f ${spec_logit} "      " %9.4f ${prec_logit} "   " %9.4f ${f1_logit}
di as text "========================================================="
di as text ""

di as text "========================================================="
di as text "        MODEL COMPARISON (Optimal Threshold - Youden)"
di as text "========================================================="
di as text "Model      Threshold    MPE      Accuracy    Sensitivity    Specificity    Precision    F1"
di as text "-------------------------------------------------------------"
di as text "OLS       " %9.2f ${thresh_opt_reg} "   " %9.4f ${mpe_opt_reg} "   " %9.4f ${acc_opt_reg} "      " %9.4f ${sens_opt_reg} "         " %9.4f ${spec_opt_reg} "      " %9.4f ${prec_opt_reg} "   " %9.4f ${f1_opt_reg}
di as text "LASSO     " %9.2f ${thresh_opt_cvlasso} "   " %9.4f ${mpe_opt_cvlasso} "   " %9.4f ${acc_opt_cvlasso} "      " %9.4f ${sens_opt_cvlasso} "         " %9.4f ${spec_opt_cvlasso} "      " %9.4f ${prec_opt_cvlasso} "   " %9.4f ${f1_opt_cvlasso}
di as text "LOGIT     " %9.2f ${thresh_opt_logit} "   " %9.4f ${mpe_opt_logit} "   " %9.4f ${acc_opt_logit} "      " %9.4f ${sens_opt_logit} "         " %9.4f ${spec_opt_logit} "      " %9.4f ${prec_opt_logit} "   " %9.4f ${f1_opt_logit}
di as text "========================================================="
di as text ""

di as text "Notes:"
di as text "- AUC: Area Under ROC Curve (higher is better, threshold-free)"
di as text "- MPE: Mean Prediction Error (lower is better)"
di as text "- Accuracy: Overall correct predictions"
di as text "- Sensitivity (Recall): True Positive Rate (WR detection)"
di as text "- Specificity: True Negative Rate (non-WR detection)"
di as text "- Precision: Positive Predictive Value"
di as text "- F1: Harmonic mean of Precision and Recall"
di as text "- Optimal threshold found using Youden's index (maximizes sensitivity + specificity)"
di as text "- OLS/LASSO predictions normalized to [0,1] for threshold comparison"
di as text "- Model includes " `: word count $Xvars' " predictor variables"
di as text ""

* --- 8. Confusion Matrices at Optimal Thresholds --------------------
di as text "========================================================="
di as text "        CONFUSION MATRICES (Optimal Thresholds)"
di as text "========================================================="

foreach model in reg cvlasso logit {
    di as text ""
    di as text "`model' Model (Threshold = ${thresh_opt_`model'}):"
    preserve
        capture drop pred_opt_temp
        if "`model'" == "logit" {
            quietly logit WR_next_30_days $Xvars if train == 1
            predict prob_temp if train == 0, pr
        }
        else if "`model'" == "cvlasso" {
            quietly cvlasso WR_next_30_days $Xvars if train == 1
            predict y_temp if train == 0, xb
            quietly summarize y_temp if train == 0
            local min_temp = r(min)
            local max_temp = r(max)
            local range_temp = `max_temp' - `min_temp'
            if `range_temp' > 0.0001 {
                gen prob_temp = (y_temp - `min_temp') / `range_temp' if train == 0
            }
            else {
                gen prob_temp = y_temp if train == 0
            }
        }
        else {
            quietly reg WR_next_30_days $Xvars if train == 1
            predict y_temp if train == 0, xb
            quietly summarize y_temp if train == 0
            local min_temp = r(min)
            local max_temp = r(max)
            local range_temp = `max_temp' - `min_temp'
            if `range_temp' > 0.0001 {
                gen prob_temp = (y_temp - `min_temp') / `range_temp' if train == 0
            }
            else {
                gen prob_temp = y_temp if train == 0
            }
        }
        gen pred_opt_temp = (prob_temp >= ${thresh_opt_`model'}) if train == 0
        tabulate WR_next_30_days pred_opt_temp if train == 0, row
        capture drop prob_temp y_temp pred_opt_temp
    restore
}

* --- 9. Enhanced ROC Curves ------------------------------------------
di as text ""
di as text "Generating ROC curves for all models..."

* Prepare predictions for combined ROC plot
quietly logit WR_next_30_days $Xvars if train == 1
predict prob_logit_roc if train == 0, pr

quietly cvlasso WR_next_30_days $Xvars if train == 1
predict y_lasso_roc if train == 0, xb
quietly summarize y_lasso_roc if train == 0
local min_lasso = r(min)
local max_lasso = r(max)
local range_lasso = `max_lasso' - `min_lasso'
if `range_lasso' > 0.0001 {
    gen prob_lasso_roc = (y_lasso_roc - `min_lasso') / `range_lasso' if train == 0
}
else {
    gen prob_lasso_roc = y_lasso_roc if train == 0
}

quietly reg WR_next_30_days $Xvars if train == 1
predict y_ols_roc if train == 0, xb
quietly summarize y_ols_roc if train == 0
local min_ols = r(min)
local max_ols = r(max)
local range_ols = `max_ols' - `min_ols'
if `range_ols' > 0.0001 {
    gen prob_ols_roc = (y_ols_roc - `min_ols') / `range_ols' if train == 0
}
else {
    gen prob_ols_roc = y_ols_roc if train == 0
}

* Individual ROC curves
* Use roctab for consistency (works with predictions directly)
roctab WR_next_30_days prob_logit_roc if train == 0, graph title("ROC Curve - Logit Model (Test Set)") name(roc_logit, replace)
graph export "`graphs_folder'/roc_curve_logit.png", replace width(1200) height(900)

roctab WR_next_30_days prob_lasso_roc if train == 0, graph title("ROC Curve - LASSO Model (Test Set)") name(roc_lasso, replace)
graph export "`graphs_folder'/roc_curve_lasso.png", replace width(1200) height(900)

roctab WR_next_30_days prob_ols_roc if train == 0, graph title("ROC Curve - OLS Model (Test Set)") name(roc_ols, replace)
graph export "`graphs_folder'/roc_curve_ols.png", replace width(1200) height(900)

* Note: Individual ROC curves saved above
* For combined comparison, see individual files or use external tools

di as text "ROC curves saved to: `graphs_folder'"

* --- 10. Feature Importance Analysis ---------------------------------
di as text ""
di as text "========================================================="
di as text "        LASSO FEATURE SELECTION"
di as text "========================================================="
quietly cvlasso WR_next_30_days $Xvars if train == 1
di as text ""
di as text "Selected features (non-zero coefficients):"
di as text "---------------------------------------------------------"

* --- 11. Detailed Logit Results ---------------------------------------
di as text ""
di as text "========================================================="
di as text "        DETAILED LOGIT MODEL RESULTS"
di as text "========================================================="
logit WR_next_30_days $Xvars if train == 1
estimates store logit_full

* --- 12. Feature Set Comparison --------------------------------------
di as text ""
di as text "========================================================="
di as text "    FEATURE SET COMPARISON"
di as text "========================================================="

* Base model (original features only)
quietly logit WR_next_30_days $Xvars_base if train == 1
predict prob_base if train == 0, pr
gen pred_base = (prob_base >= 0.2)
quietly summarize pred_base if WR_next_30_days == 1 & train == 0
local sens_base = r(mean)
quietly count if WR_next_30_days == 0 & pred_base == 0 & train == 0
local tn = r(N)
quietly count if WR_next_30_days == 0 & train == 0
local spec_base = `tn' / r(N)

* Full model (all features)
quietly logit WR_next_30_days $Xvars if train == 1
predict prob_full if train == 0, pr
gen pred_full = (prob_full >= 0.2)
quietly summarize pred_full if WR_next_30_days == 1 & train == 0
local sens_full = r(mean)
quietly count if WR_next_30_days == 0 & pred_full == 0 & train == 0
local tn = r(N)
quietly count if WR_next_30_days == 0 & train == 0
local spec_full = `tn' / r(N)

di as text "Feature Set         Sensitivity    Specificity"
di as text "---------------------------------------------------------"
di as text "Base (9 features)   " %9.4f `sens_base' "      " %9.4f `spec_base'
di as text "Full (30+ features) " %9.4f `sens_full' "      " %9.4f `spec_full'
di as text "---------------------------------------------------------"
di as text "Improvement:        " %9.4f (`sens_full' - `sens_base') "      " %9.4f (`spec_full' - `spec_base')
di as text ""

* --- 13. Save predictions for visualization -------------------------
preserve
    keep if train == 0
    keep player_id category_id player_name category_name game_name ///
         prob_logit WR_next_30_days
    rename prob_logit wr_probability
    save "wr_predictions_test.dta", replace
restore

di as text ""
di as text "========================================================="
di as text "        ANALYSIS COMPLETE"
di as text "========================================================="
di as text ""
di as text "Output files:"
di as text "  - wr_predictions_test.dta (predictions for visualization)"
di as text "  - `graphs_folder'/roc_curve_logit.png"
di as text "  - `graphs_folder'/roc_curve_lasso.png"
di as text "  - `graphs_folder'/roc_curve_ols.png"
di as text ""
di as text "Ready for top WR candidates visualization!"
di as text ""

*******************************************************
