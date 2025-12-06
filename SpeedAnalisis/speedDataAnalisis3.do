*******************************************************
* LOAD RAW RUNS WITH ENHANCED FEATURES
*******************************************************
import delimited "C:\Users\brown\Desktop\‌\ITAM\DDD\Proyect\SpeedDataMining\bin\Debug\net10.0\speedrun_data_nombres.csv", clear

* Rename time_seconds to time for consistency
rename time_seconds time

gen date_part = substr(date_submitted, 1, 10)
gen date = date(date_part, "YMD")
format date %td
drop date_part

*******************************************************
* BASIC TIME VARIABLES
*******************************************************
gen year  = year(date)
gen month = month(date)
gen ym    = ym(year, month)
format ym %tm

*******************************************************
* PERFORMANCE FEATURES
*******************************************************
* PB time per player-category-month
bys player_id category_id ym: egen pb_time_current_month = min(time)

* Percentile rank within category-month
bys category_id ym: egen Ncat = count(time)
bys category_id ym: egen rank_time = rank(time)
gen pb_percentile = rank_time / Ncat

* Install asrol if needed
cap which asrol
if _rc ssc install asrol

* Rolling variance of last 90 days
sort player_id category_id date
asrol time, stat(sd) window(date 90) by(player_id category_id) gen(sd90)
gen var90 = sd90^2
drop sd90

* Attempts per day
bys player_id category_id ym: egen attempts_month = count(run_id)
gen days_month = daysinmonth(date)
gen mean_attempts_per_day = attempts_month / days_month

* NEW: Current rank in leaderboard (lower is better)
bys player_id category_id ym: egen best_rank_month = min(rank)

* NEW: Improvement rate - compare to previous month
sort player_id category_id ym
by player_id category_id: gen time_lag = time[_n-1]
gen time_improvement = time_lag - time if time_lag != .
gen improved = (time_improvement > 0) if time_improvement != .

* NEW: Personal best indicator
bys player_id category_id: egen pb_all_time = min(time)
gen is_personal_best = (time == pb_all_time)

*******************************************************
* BEHAVIORAL FEATURES
*******************************************************
* Categories played per player per month
bys player_id ym category_id: gen tag_cat = (_n == 1)
bys player_id ym: egen categories_played_count = total(tag_cat)
drop tag_cat

* Cross-category switching
gen cross_category_switching = (categories_played_count > 1)

* Experience months
bys player_id: egen first_run_date = min(date)
gen experience_months = (ym - ym(year(first_run_date), month(first_run_date)))

* NEW: Player dedication metrics
bys player_id ym: egen player_total_runs_month = count(run_id)

* FIX: Count unique games per player-month (corrected)
bys player_id ym game_id: gen tag_game = (_n == 1)
bys player_id ym: egen player_unique_games_month = total(tag_game)
drop tag_game

gen player_avg_time_impr_m = .
bys player_id ym: egen mean_improvement = mean(time_improvement)
replace player_avg_time_impr_m = mean_improvement
drop mean_improvement

*******************************************************
* VIDEO & QUALITY FEATURES
*******************************************************
* NEW: Video proof and engagement
gen video_proof_rate = .
bys player_id category_id ym: egen videos_submitted = total(has_video)
bys player_id category_id ym: egen runs_submitted = count(run_id)
replace video_proof_rate = videos_submitted / runs_submitted
drop videos_submitted runs_submitted

* NEW: Comment engagement
gen avg_comment_length = .
bys player_id category_id ym: egen total_comment_length = total(run_comment_length)
bys player_id category_id ym: egen n_runs = count(run_id)
replace avg_comment_length = total_comment_length / n_runs
drop total_comment_length n_runs

* NEW: Emulation usage
gen emulation_rate = .
bys player_id category_id ym: egen emulated_runs = total(emulated)
bys player_id category_id ym: egen runs_submitted2 = count(run_id)
replace emulation_rate = emulated_runs / runs_submitted2
drop emulated_runs runs_submitted2

*******************************************************
* GAME ACTIVITY FEATURES
*******************************************************
* Total runs per game-month
bys game_id ym: egen total_runs_game_month = count(run_id)

* Active players per game-month
bys game_id ym player_id: gen tag_player = (_n == 1)
bys game_id ym: egen active_players_game_month = total(tag_player)
drop tag_player

* Categories in game-month
bys game_id ym category_id: gen tag_cats = (_n == 1)
bys game_id ym: egen cats_game_month = total(tag_cats)
drop tag_cats

* Game niche index
gen game_niche_index = active_players_game_month / cats_game_month

* NEW: Competition intensity
bys category_id ym: egen category_competitiveness = count(run_id)
gen competition_intensity = total_runners_in_category / active_players_game_month

* NEW: Game maturity (years since release)
gen game_age = year - game_release_year

*******************************************************
* MOMENTUM & TREND FEATURES
*******************************************************
* NEW: Recent activity spike (last 30 days vs previous 30 days)
gen date_30_ago = date - 30
gen date_60_ago = date - 60

gen runs_last_30 = .
gen runs_prev_30 = .
bys player_id category_id: egen temp_last = total(date >= date_30_ago & date <= date)
bys player_id category_id: egen temp_prev = total(date >= date_60_ago & date < date_30_ago)
replace runs_last_30 = temp_last
replace runs_prev_30 = temp_prev
drop temp_last temp_prev

gen activity_momentum = (runs_last_30 - runs_prev_30) / (runs_prev_30 + 1)

* NEW: Consistency score (lower variance = more consistent)
gen consistency_score = 1 / (var90 + 1)

drop date_30_ago date_60_ago runs_last_30 runs_prev_30

*******************************************************
* PLAYER PROFILE FEATURES
*******************************************************
* NEW: Player specialization (focus on few categories vs many)
gen player_specialization = 1 / (player_total_categories + 1)

* NEW: Multi-game player indicator
gen is_multi_game_player = (player_total_games > 1)

* NEW: Days active
gen player_activity_span = player_days_active

*******************************************************
* OUTCOME: WR in next 30 days
*******************************************************
gen date_plus_30 = date + 30
preserve
    keep if is_wr == 1
    keep player_id category_id date
    rename date wr_date
    tempfile wrs
    save `wrs'
restore
joinby player_id category_id using `wrs'
gen within_30 = (wr_date > date & wr_date <= date_plus_30)
bys player_id category_id date: egen WR_next_30_days = max(within_30)
replace WR_next_30_days = 0 if missing(WR_next_30_days)
drop wr_date within_30 date_plus_30

*******************************************************
* COLLAPSE TO PLAYER-CATEGORY-MONTH PANEL
*******************************************************
collapse (min) pb_time_current_month best_rank_month                     ///
         (mean) pb_percentile var90 mean_attempts_per_day                ///
                time_improvement video_proof_rate avg_comment_length    ///
                emulation_rate competition_intensity                     ///
                consistency_score activity_momentum                      ///
                player_specialization player_activity_span               ///
         (max) cross_category_switching WR_next_30_days                  ///
               is_personal_best improved is_multi_game_player            ///
         (count) attempts_month                                          ///
         (first) experience_months total_runs_game_month                 ///
                 active_players_game_month game_niche_index               ///
                 category_competitiveness game_age                       ///
                 player_total_runs player_total_games                    ///
                 player_total_categories player_avg_time_improvement     ///
                 player_unique_games_month player_total_runs_month       ///
                 game_name category_name player_name, ///
         by(player_id category_id ym)

*******************************************************
* PANEL SETUP
*******************************************************
egen id = group(player_id category_id)
xtset id ym

* Label variables for clarity
label variable pb_time_current_month "Best time this month"
label variable pb_percentile "Percentile rank in category"
label variable var90 "90-day rolling variance"
label variable best_rank_month "Best rank achieved this month"
label variable time_improvement "Time improvement vs previous run"
label variable video_proof_rate "Proportion of runs with video"
label variable avg_comment_length "Average comment length"
label variable emulation_rate "Proportion of emulated runs"
label variable competition_intensity "Competition level in category"
label variable consistency_score "Performance consistency (inverse variance)"
label variable activity_momentum "Recent activity increase"
label variable player_specialization "Player focus score"
label variable is_multi_game_player "Plays multiple games"
label variable game_age "Years since game release"
label variable WR_next_30_days "World record in next 30 days (outcome)"

save "speedrun_panel3.dta", replace

*******************************************************
* SUMMARY STATISTICS
*******************************************************
describe
summarize WR_next_30_days pb_percentile var90 best_rank_month ///
         video_proof_rate competition_intensity player_specialization

di as text ""
di as text "Dataset ready for prediction modeling!"
di as text "Total observations: " _N
quietly xtdescribe
di as text "Unique player-category combinations: " r(N)
di as text "Time periods covered: " r(Tmin) " to " r(Tmax)
*******************************************************