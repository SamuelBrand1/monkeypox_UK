## Idea is to have both fitness and SBM effects in sexual contact



## Grab UK data

include("mpxv_datawrangling.jl");
include("setup_model.jl");

##
_p = [0.01, 0.5, 20, 0.2, 0.5, 6, 1.5, 130, 0.7, 0.3,0.5,0.5]

err, pred = mpx_sim_function_chp(_p, constants, mpxv_wkly)

plt = plot(pred, color=[1 2])
scatter!(plt, mpxv_wkly, color=[1 2])
display(plt)
print(err)

## Priors

prior_vect_cng_pnt = [Gamma(1, 1), # α_choose 1
    Beta(5, 5), #p_detect  2
    truncated(Gamma(3, 6 / 3), 0, 21), #mean_inf_period - 1  3
    Beta(1, 9), #p_trans  4
    LogNormal(log(0.75), 0.25), #R0_other 5
    Gamma(3, 10 / 3),#  M 6
    LogNormal(0, 1),#init_scale 7
    Uniform(135, 199),# chp_t 8
    Beta(1.5, 1.5),#trans_red 9
    Beta(1.5, 1.5),#trans_red_other 10
    Beta(1, 4),#trans_red WHO  11
    Beta(1, 4)]#trans_red_other WHO 12

## Prior predictive checking - simulation
draws = [rand.(prior_vect_cng_pnt) for i = 1:1000]
prior_sims = map(θ -> mpx_sim_function_chp(θ, constants, mpxv_wkly), draws)

##Prior predictive checking - simulation
prior_preds = [sim[2] for sim in prior_sims]
plt = plot(; ylabel="Weekly cases",
    title="Prior predictive checking")
for pred in prior_preds
    plot!(plt, wks, pred, lab="", color=[1 2], alpha=0.3)
end
display(plt)
savefig(plt, "plots/prior_predictive_checking_plot.png")

## Model-based calibration of target tolerance
# min_mbc_errs = map(n -> minimum(map(x -> mpx_sim_function_chp(draws[n],constants,prior_sims[n][2])[1],1:5)),1:1000)
mbc_errs = map(n -> mpx_sim_function_chp(draws[n], constants, prior_sims[n][2])[1], 1:1000)

##Find target tolerance and plot error distribution
target_perc = 0.05 #Where in error distribution to target tolerance
ϵ_target = find_zero(x -> target_perc - sum(mbc_errs .< x) / length(mbc_errs), (0, 2))
err_hist = histogram(mbc_errs, norm=:pdf, nbins=500,
    lab="",
    title="Sampled errors from simulations with exact parameters",
    xlabel="L1 relative error",
    xlims=(0, 5),
    size=(700, 400))
vline!(err_hist, [ϵ_target], lab="$(round(Int64,target_perc*100))th percentile (target err. = $(round(ϵ_target,digits = 3)))", lw=3)
display(err_hist)
savefig(err_hist, "plots/mbc_error_calibration_plt.png")

##Run inference
setup_cng_pnt = ABCSMC(mpx_sim_function_chp, #simulation function
    12, # number of parameters
    ϵ_target, #target ϵ
    Prior(prior_vect_cng_pnt); #Prior for each of the parameters
    ϵ1=1000,
    convergence=0.05,
    nparticles=2000,
    α=0.5,
    kernel=gaussiankernel,
    constants=constants,
    maxiterations=10^10)

smc_cng_pnt = runabc(setup_cng_pnt, mpxv_wkly, verbose=true, progress=true)#, parallel=true)

##
@save("posteriors/smc_posterior_draws_"*string(wks[end])*".jld2", smc_cng_pnt)


##posterior predictive checking - simple plot to see coherence of model with data

post_preds = [part.other for part in smc_cng_pnt.particles]
plt = plot(; ylabel="Weekly cases",
    title="Posterior predictive checking")
for pred in post_preds
    plot!(plt, wks, pred, lab="", color=[1 2], alpha=0.3)
end
scatter!(plt, wks, mpxv_wkly, lab=["Data: (MSM)" "Data: (non-MSM)"],ylims = (0,800))
display(plt)




