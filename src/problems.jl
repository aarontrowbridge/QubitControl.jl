module Problems

export AbstractProblem
export FixedTimeProblem
export QuantumControlProblem

export initialize_trajectory!
export update_traj_data!
export get_traj_data
export get_variables

using ..Utils
using ..QuantumSystems
using ..Trajectories
using ..Evaluators
using ..IpoptOptions
using ..Constraints
using ..Dynamics
using ..Objectives

using Libdl
using Ipopt
using MathOptInterface
const MOI = MathOptInterface

abstract type AbstractProblem end

struct QuantumControlProblem <: AbstractProblem
    system::AbstractSystem
    variables::Vector{MOI.VariableIndex}
    optimizer::Ipopt.Optimizer
    trajectory::Trajectory
    params::Dict
end


function problem_constraints(
    system::AbstractSystem,
    params::Dict,
    init_traj::Trajectory
)::Vector{AbstractConstraint}

    cons = AbstractConstraint[]

    # initial quantum state constraints: ψ̃(t=1) = ψ̃1
    ψ1_con = EqualityConstraint(
        1,
        1:system.n_wfn_states,
        system.ψ̃init,
        system.vardim;
        name="initial quantum state constraints"
    )
    push!(cons, ψ1_con)

    #TODO: maybe add ∫a constraint

    # initial and final a(t ∈ {1, T}) = 0 constraints
    a_cons = EqualityConstraint(
        [1, params[:T]],
        system.n_wfn_states .+ slice(system.∫a + 1, system.ncontrols),
        0.0,
        system.vardim;
        name="initial and final augmented state constraints"
    )
    push!(cons, a_cons)

    # initial and final da(t ∈ {1, T}) = 0 constraints
    # aug_cons = EqualityConstraint(
    #     [1, params[:T]],
    #     system.n_wfn_states .+ slice(system.∫a + 2, system.ncontrols),
    #     0.0,
    #     system.vardim;
    #     name="initial and final augmented state constraints"
    # )
    # push!(cons, da_cons)

    # bound |a(t)| < a_bound
    a_bound_con = BoundsConstraint(
        2:params[:T]-1,
        system.n_wfn_states .+ slice(system.∫a + 1, system.ncontrols),
        system.a_bounds,
        system.vardim;
        name="bound |a(t)| < a_bound"
    )
    push!(cons, a_bound_con)

    # bound |u(t)| < u_bound
    u_bound_con = BoundsConstraint(
        1:params[:T],
        system.nstates .+ (1:system.ncontrols),
        params[:u_bounds],
        system.vardim;
        name="bound |u(t)| < u_bound"
    )
    push!(cons, u_bound_con)

    # pin first qstate to be equal to analytic solution
    if params[:pin_first_qstate]
        ψ̃¹goal = system.ψ̃goal[1:system.isodim]
        pin_con = EqualityConstraint(
            params[:T],
            1:system.isodim,
            ψ̃¹goal,
            system.vardim;
            name="pinned first qstate at T"
        )
        push!(cons, pin_con)
    end

    if params[:mode] ∈ (:free_time, :min_time)
        Δt_con = TimeStepBoundsConstraint(
            (params[:Δt_min], params[:Δt_max]),
            params[:Δt_indices],
            params[:T];
            name="time step bounds constraint"
        )
        push!(cons, Δt_con)

        if params[:equal_Δts]
            Δts_all_equal_con = TimeStepsAllEqualConstraint(
                params[:Δt_indices];
                name="time steps all equal constraint"
            )
            push!(cons, Δts_all_equal_con)
        end

        if params[:mode] == :min_time
            if params[:pin_first_qstate]
                ψ̃T_con = EqualityConstraint(
                    params[:T],
                    (system.isodim + 1):system.n_wfn_states,
                    init_traj.states[end][(system.isodim + 1):system.n_wfn_states],
                    system.vardim;
                    name="final qstate constraint"
                )
            else
                ψ̃T_con = EqualityConstraint(
                    params[:T],
                    1:system.n_wfn_states,
                    init_traj.states[end][1:system.n_wfn_states],
                    system.vardim;
                    name="final qstate constraint"
                )
            end
            push!(cons, ψ̃T_con)
        end
    elseif params[:mode] == :fixed_time
        Δt_con = TimeStepEqualityConstraint(
            params[:Δt],
            params[:Δt_indices];
            name="time step constraint"
        )
        push!(cons, Δt_con)
    end

    return cons
end



#
# QuantumControlProblem constructors
#

function QuantumControlProblem(
    system::AbstractSystem;
    T=100,
    Δt=0.01,
    Δt_min=0.25Δt,
    Δt_max=1.25Δt,
    equal_Δts=true,
    mode=:free_time,
    integrator=:FourthOrderPade,
    cost=:infidelity_cost,
    Q=200.0,
    R=0.1,
    Rᵤ=R,
    Rₛ=R,
    eval_hessian=true,
    pin_first_qstate=false,
    options=Options(),
    constraints::Vector{AbstractConstraint}=AbstractConstraint[],
    u_bounds=fill(Inf, length(system.G_drives)),
    additional_objective=nothing,
    L1_regularized_states::Vector{Int}=Int[],
    α=fill(10.0, length(L1_regularized_states)),

    # keyword args below are for initializing the trajactory
    linearly_interpolate=true,
    σ = 0.1,
    init_traj=Trajectory(
        system,
        T,
        Δt;
        linearly_interpolate=linearly_interpolate,
        σ=σ
    ),
    kwargs...
)
    @assert mode ∈ (:fixed_time, :free_time, :min_time)
    @assert length(u_bounds) == length(system.G_drives)

    optimizer = Ipopt.Optimizer()

    set!(optimizer, options)

    Z_indices = 1:system.vardim * T
    Δt_indices = system.vardim * T .+ (1:T) # [Δt; Δt̄]
    # Δt̄ is defined so that Δtᵢ = Δt̄ ∀ i when equal_Δts == true

    n_prob_variables = length(Z_indices) + length(Δt_indices)
    n_variables = n_prob_variables
    n_dynamics_constraints = system.nstates * (T - 1)

    params = Dict(
        :T => T,
        :Δt => Δt,
        :Δt_min => Δt_min,
        :Δt_max => Δt_max,
        :equal_Δts => equal_Δts,
        :mode => mode,
        :integrator => integrator,
        :cost => cost,
        :Q => Q,
        :R => R,
        :Rᵤ => Rᵤ,
        :Rₛ => Rₛ,
        :eval_hessian => eval_hessian,
        :pin_first_qstate => pin_first_qstate,
        :options => options,
        :u_bounds => u_bounds,
        :L1_regularized_states => L1_regularized_states,
        :additional_objective_terms =>
            isnothing(additional_objective) ?
                [] :
                additional_objective.terms,
        :α => α,
        :n_prob_variables => n_prob_variables,
        :n_variables => n_variables,
        :n_dynamics_constraints => n_dynamics_constraints,
        :constraints => constraints,
        :Z_indices => Z_indices,
        :Δt_indices => Δt_indices,
    )

    if mode ∈ (:fixed_time, :free_time)

        quantum_obj = QuantumObjective(
            system=system,
            cost_fn=cost,
            T=T,
            Q=Q,
            eval_hessian=eval_hessian
        )

        u_regularizer = QuadraticRegularizer(
            indices=system.nstates .+ (1:system.ncontrols),
            vardim=system.vardim,
            times=1:T-1,
            R=Rᵤ,
            eval_hessian=eval_hessian
        )

        objective =
            quantum_obj +
            u_regularizer +
            additional_objective

    elseif mode == :min_time

        min_time_obj = MinTimeObjective(
            Δt_indices=Δt_indices,
            T=T,
            eval_hessian=eval_hessian
        )

        u_regularizer = QuadraticRegularizer(
            indices=system.nstates .+ (1:system.ncontrols),
            vardim=system.vardim,
            times=1:T-1,
            R=Rᵤ,
            eval_hessian=eval_hessian
        )

        u_smoothness_regularizer = QuadraticSmoothnessRegularizer(
            indices=system.nstates .+ (1:system.ncontrols),
            vardim=system.vardim,
            times=1:T-1,
            R=Rₛ,
            eval_hessian=eval_hessian
        )

        objective =
            min_time_obj +
            u_regularizer +
            u_smoothness_regularizer +
            additional_objective
    end


    if !isempty(L1_regularized_states)

        n_slack_variables = 2 * length(L1_regularized_states) * T

        x_indices = foldr(
            vcat,
            [
                slice(t, L1_regularized_states, system.vardim)
                    for t = 1:T
            ]
        )

        params[:x_indices] = x_indices

        s1_indices = n_prob_variables .+ (1:n_slack_variables÷2)

        s2_indices = n_prob_variables .+
            (n_slack_variables÷2 + 1:n_slack_variables)

        params[:s1_indices] = s1_indices
        params[:s2_indices] = s2_indices

        α = foldr(vcat, [α for t = 1:T])

        L1_regularizer = L1SlackRegularizer(
            s1_indices=s1_indices,
            s2_indices=s2_indices,
            α=α,
            eval_hessian=eval_hessian
        )

        objective += L1_regularizer

        L1_slack_con = L1SlackConstraint(
            s1_indices,
            s2_indices,
            x_indices;
            name="L1 slack variable constraint"
        )

        params[:n_variables] += n_slack_variables
        params[:n_slack_variables] = n_slack_variables

        constraints = vcat(constraints, L1_slack_con)
    end

    dynamics = QuantumDynamics(
        system,
        integrator,
        Z_indices,
        Δt_indices,
        T;
        eval_hessian=eval_hessian
    )

    evaluator = PicoEvaluator(
        objective,
        dynamics,
        eval_hessian
    )

    prob_constraints = problem_constraints(system, params, init_traj)

    cons = vcat(prob_constraints, constraints)

    variables = initialize_optimizer!(
        optimizer,
        evaluator,
        cons,
        params[:n_dynamics_constraints],
        params[:n_variables]
    )

    params[:objective_terms] = objective.terms

    return QuantumControlProblem(
        system,
        variables,
        optimizer,
        init_traj,
        params
    )
end

function QuantumControlProblem(
    system::AbstractSystem,
    init_traj::Trajectory;
    kwargs...
)
    return QuantumControlProblem(
        system;
        T=init_traj.T,
        Δt=init_traj.Δt,
        init_traj=init_traj,
        kwargs...
    )
end


#
# QuantumControlProblem methods
#

function initialize_optimizer!(
    optimizer::Ipopt.Optimizer,
    evaluator::PicoEvaluator,
    constraints::Vector{AbstractConstraint},
    n_dynamics_constraints::Int,
    n_variables::Int
)
    dynamics_cons = fill(
        MOI.NLPBoundsPair(0.0, 0.0),
        n_dynamics_constraints
    )
    block_data = MOI.NLPBlockData(dynamics_cons, evaluator, true)
    MOI.set(optimizer, MOI.NLPBlock(), block_data)
    MOI.set(optimizer, MOI.ObjectiveSense(), MOI.MIN_SENSE)
    variables = MOI.add_variables(optimizer, n_variables)
    constrain!(optimizer, variables, constraints, verbose=true)
    return variables
end


function initialize_trajectory!(
    prob::QuantumControlProblem,
    traj::Trajectory
)
    for (t, x, u) in zip(1:traj.T, traj.states, traj.actions)
        MOI.set(
            prob.optimizer,
            MOI.VariablePrimalStart(),
            prob.variables[slice(t, prob.system.vardim)],
            [x; u]
        )
    end
    Δts = [traj.times[t + 1] - traj.times[t] for t = 1:traj.T-1]
    Δt = [Δts; Δts[1]]
    MOI.set(
        prob.optimizer,
        MOI.VariablePrimalStart(),
        prob.variables[prob.params[:Δt_indices]],
        Δt
    )
end

initialize_trajectory!(prob::QuantumControlProblem) =
    initialize_trajectory!(prob, prob.trajectory)

function get_variables(prob::QuantumControlProblem)
    return MOI.get(
        prob.optimizer,
        MOI.VariablePrimal(),
        prob.variables
    )
end

@views function update_traj_data!(prob::QuantumControlProblem)
    Z̄ = get_variables(prob)
    Z = Z̄[prob.params[:Z_indices]]
    Δt = Z̄[prob.params[:Δt_indices]][1:end-1]

    xs = []

    for t = 1:prob.trajectory.T
        xₜ = Z[slice(t, prob.system.nstates, prob.system.vardim)]
        push!(xs, xₜ)
    end

    us = []

    for t = 1:prob.trajectory.T
        uₜ = Z[
            slice(
                t,
                prob.system.nstates + 1,
                prob.system.vardim,
                prob.system.vardim
            )
        ]
        push!(us, uₜ)
    end

    times = [0.0; cumsum(Δt)]

    prob.trajectory.states .= xs
    prob.trajectory.actions .= us
    prob.trajectory.times .= times
    prob.trajectory.Δt = Z̄[prob.params[:Δt_indices]][end]
end

end
