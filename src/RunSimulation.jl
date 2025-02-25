module RunSimulation

using Langevin.HolsteinModels: HolsteinModel

using Langevin.LangevinSimulationParameters: SimulationParameters

using Langevin.NonLocalMeasurements: make_nonlocal_measurements!, reset_nonlocal_measurements!
using Langevin.NonLocalMeasurements: process_nonlocal_measurements!, construct_nonlocal_measurements_container
using Langevin.NonLocalMeasurements: initialize_nonlocal_measurement_files
using Langevin.NonLocalMeasurements: write_nonlocal_measurements

using Langevin.GreensFunctions: EstimateGreensFunction, update!, estimate_time_ordered

using Langevin.LangevinDynamics: update_euler_fa!, update_rk_fa!

using Langevin.FourierAcceleration: FourierAccelerator

using Langevin.FourierTransforms: calc_fourier_transform_coefficients

export run_simulation!

function run_simulation!(holstein::HolsteinModel{T1,T2}, sim_params::SimulationParameters{T1}, fa::FourierAccelerator{T1}) where {T1<:AbstractFloat, T2<:Number}

    ###############################################################
    ## PRE-ALLOCATING ARRAYS AND VARIABLES NEEDED FOR SIMULATION ##
    ###############################################################

    dϕdt     = zeros(Float64,          length(holstein))
    fft_dϕdt = zeros(Complex{Float64}, length(holstein))

    dSdϕ     = zeros(Float64,          length(holstein))
    fft_dSdϕ = zeros(Complex{Float64}, length(holstein))
    dSdϕ2    = zeros(Float64,          length(holstein))

    g    = zeros(Float64, length(holstein))
    Mᵀg  = zeros(Float64, length(holstein))
    M⁻¹g = zeros(Float64, length(holstein))

    η     = zeros(Float64,          length(holstein))
    fft_η = zeros(Complex{Float64}, length(holstein))

    # declare two electron greens function estimators
    Gr1 = EstimateGreensFunction(holstein)
    Gr2 = EstimateGreensFunction(holstein)

    # declare container for storing non-local measurements in both
    # position-space and momentum-space
    container_rspace, container_kspace = construct_nonlocal_measurements_container(holstein)

    # caluclating Fourier Transform coefficients
    ft_coeff = calc_fourier_transform_coefficients(holstein.lattice)

    # Creating files that data will be written to.
    initialize_nonlocal_measurement_files(container_rspace, container_kspace, sim_params)

    # keeps track of number of iterations needed to solve linear system
    iters = 0.0

    # time taken on langevin dynamics
    simulation_time = 0.0

    # time take on making measurements and write them to file
    measurement_time = 0.0

    # time taken writing data to file
    write_time = 0.0

    ########################
    ## RUNNING SIMULATION ##
    ########################

    # thermalizing system
    for timestep in 1:sim_params.burnin

        if sim_params.euler

            # using Euler method with Fourier Acceleration
            simulation_time += @elapsed iters += update_euler_fa!(holstein, fa, dϕdt, fft_dϕdt, dSdϕ, fft_dSdϕ, g, Mᵀg, M⁻¹g, η, fft_η, sim_params.Δt, sim_params.tol)
        else

            # using Runge-Kutta method with Fourier Acceleration
            simulation_time += @elapsed iters += update_rk_fa!(holstein, fa, dϕdt, fft_dϕdt, dSdϕ2, dSdϕ, fft_dSdϕ, g, Mᵀg, M⁻¹g, η, fft_η, sim_params.Δt, sim_params.tol)
        end
    end

    # iterate over bins
    for bin in 1:sim_params.num_bins

        # reset values in measurement containers
        reset_nonlocal_measurements!(container_rspace)
        reset_nonlocal_measurements!(container_kspace)

        # iterating over the size of each bin i.e. the number of measurements made per bin
        for n in 1:sim_params.bin_size

            # iterate over number of langevin steps per measurement
            for timestep in 1:sim_params.meas_freq

                if sim_params.euler

                    # using Euler method with Fourier Acceleration
                    simulation_time += @elapsed iters += update_euler_fa!(holstein, fa, dϕdt, fft_dϕdt, dSdϕ, fft_dSdϕ, g, Mᵀg, M⁻¹g, η, fft_η, sim_params.Δt, sim_params.tol)
                else

                    # using Runge-Kutta method with Fourier Acceleration
                    simulation_time += @elapsed iters += update_rk_fa!(holstein, fa, dϕdt, fft_dϕdt, dSdϕ2, dSdϕ, fft_dSdϕ, g, Mᵀg, M⁻¹g, η, fft_η, sim_params.Δt, sim_params.tol)
                end
            end

            # making non-local measurements
            measurement_time += @elapsed make_nonlocal_measurements!(container_rspace, holstein, Gr1, Gr2)
        end

        # process non-local measurements. This include normalizing the real-space measurements
        # by the number of measurements made per bin, and also taking the Fourier Transform in order
        # to get the momentum-space measurements.
        measurement_time += @elapsed process_nonlocal_measurements!(container_rspace, container_kspace, sim_params, ft_coeff)

        # Write non-local measurements to file. Note that there is a little bit more averaging going on here as well.
        write_time += @elapsed write_nonlocal_measurements(container_rspace,sim_params,real_space=true)
        write_time += @elapsed write_nonlocal_measurements(container_kspace,sim_params,real_space=false)
    end

    # calculating the average number of iterations needed to solve linear system
    iters /= (sim_params.nsteps+sim_params.burnin)

    # report times in units of minutes
    simulation_time  /= 60.0
    measurement_time /= 60.0
    write_time /= 60.0

    return simulation_time, measurement_time, write_time, iters
end

end