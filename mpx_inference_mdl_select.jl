## Idea is to have both fitness and SBM effects in sexual contact

using Distributions, StatsBase, StatsPlots
using LinearAlgebra, RecursiveArrayTools
using OrdinaryDiffEq, ApproxBayes
using JLD2, MCMCChains, Roots, Dates
using CSV, DataFrames, StatsPlots, Plots.PlotMeasures
import MonkeypoxUK

## MSM data with data inference

past_mpxv_data_inferred = CSV.File("data/weekly_data_imputation_2022-09-30.csv",
                                missingstring = "NA") |> DataFrame

colname = "seqn_fit5"
inferred_prop_na_msm = past_mpxv_data_inferred[:, colname] |> x -> x[.~ismissing.(x)]
mpxv_wkly =
    past_mpxv_data_inferred[1:size(inferred_prop_na_msm, 1), ["gbmsm", "nongbmsm"]] .+
    past_mpxv_data_inferred[1:size(inferred_prop_na_msm, 1), "na_gbmsm"] .*
    hcat(inferred_prop_na_msm, 1.0 .- inferred_prop_na_msm) |> Matrix

wks = Date.(past_mpxv_data_inferred.week[1:size(mpxv_wkly, 1)], DateFormat("dd/mm/yyyy"))
                                
# Leave out first two weeks because reporting changed in early May
mpxv_wkly = mpxv_wkly[3:end, :]
wks = wks[3:end]
## Set up model

include("setup_model.jl");

## Define priors for the parameters

prior_vect_cng_pnt = [
    Gamma(1, 1), # α_choose 1
    Beta(5, 5), #p_detect  2
    Beta(1, 1), #p_trans  3
    LogNormal(log(0.25), 1), #R0_other 4
    Gamma(3, 1000 / 3),#  M 5
    LogNormal(log(5), 1),#init_scale 6
    Uniform(135, 199),# chp_t 7
    Beta(1.5,1.5),#trans_red 8
    Beta(1.5,1.5),#trans_red_other 9
    Beta(1.5,1.5),#trans_red WHO  10 
    Beta(1.5,1.5),#trans_red_other WHO 11
    Gamma(1, 1), # α_choose no behaviour change 12
    Beta(5, 5), #p_detect no behaviour change   13
    Beta(1, 1), #p_trans no behaviour change   14  
    LogNormal(log(0.25), 1), #R0_other no behaviour change   15
    LogNormal(log(5), 1),#init_scale no behaviour change   16
    Uniform(0.0,1.0) # model choice boolean, true == model with no behavioural change 17
]


#Use SBC for defining the ABC error target and generate prior predictive plots

# ϵ_target, plt_prc, hist_err = MonkeypoxUK.simulation_based_calibration(
#     prior_vect_cng_pnt,
#     wks,
#     mpxv_wkly,
#     constants;
#     target_perc = 0.25,
# )

setup_mdl_select = ABCSMC(
    MonkeypoxUK.mpx_sim_function_mdl_selection, #simulation function
    length(prior_vect_cng_pnt), # number of parameters
    0.2, #target ϵ derived from simulation based calibration
    Prior(prior_vect_cng_pnt); #Prior for each of the parameters
    ϵ1 = 1000,
    convergence = 0.05,
    nparticles = 2000,
    α = 0.3,
    kernel = gaussiankernel,
    constants = constants,
    maxiterations = 10 * 10^5,
)

##Run ABC and save results   

smc_mdl_select = runabc(setup_mdl_select, mpxv_wkly, verbose = true, progress = true)
@save("posteriors/smc_mdl_select_" * string(wks[end]) * ".jld2", smc_mdl_select) #<--- this can be too large
##

param_draws = [particle.params for particle in smc_mdl_select.particles]
@save("posteriors/posterior_mdl_select_param_draws_" * string(wks[end]) * ".jld2", param_draws)
detected_cases = [particle.other.detected_cases for particle in smc_mdl_select.particles]
@save("posteriors/posterior_mdl_select_detected_cases_" * string(wks[end]) * ".jld2", detected_cases)
onsets = [particle.other.onsets for particle in smc_mdl_select.particles]
@save("posteriors/posterior_mdl_select_onsets_" * string(wks[end]) * ".jld2", onsets)
incidences = [particle.other.incidence for particle in smc_mdl_select.particles]
@save("posteriors/posterior_mdl_select_incidences_" * string(wks[end]) * ".jld2", incidences)
susceptibilities = [particle.other.susceptibility for particle in smc_mdl_select.particles]
@save("posteriors/posterior_mdl_select_susceptibilities_" * string(wks[end]) * ".jld2", susceptibilities)
end_states = [particle.other.end_state for particle in smc_mdl_select.particles]
@save("posteriors/posterior_mdl_select_end_states_" * string(wks[end]) * ".jld2", end_states)
begin_vac_states = [particle.other.state_pre_vaccine for particle in smc_mdl_select.particles]
@save("posteriors/posterior_mdl_select_begin_vac_states_" * string(wks[end]) * ".jld2", begin_vac_states)
begin_sept_states = [particle.other.state_sept for particle in smc_mdl_select.particles]
@save("posteriors/posterior_mdl_select_begin_sept_states_" * string(wks[end]) * ".jld2", begin_sept_states)
vac_effectivenesses = [particle.other.vac_effectiveness for particle in smc_mdl_select.particles]
@save("posteriors/posterior_mdl_select_vac_effectivenesses_" * string(wks[end]) * ".jld2", vac_effectivenesses)

##posterior predictive checking - simple plot to see coherence of model with data


post_preds = [part.other.detected_cases for part in smc_mdl_select.particles]
plt = plot(; ylabel = "Weekly cases", title = "Posterior predictive checking")
for pred in post_preds

    plot!(plt, wks[1:end], pred[1:end,:], lab = "", color = [1 2], alpha = 0.1)
end
scatter!(plt, wks[1:end], mpxv_wkly[1:end,:], lab = ["Data: (MSM)" "Data: (non-MSM)"])#, ylims = (0, 800))
display(plt)