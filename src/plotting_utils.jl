module PlottingUtils

export plot_single_qubit_1_qstate_with_controls
export plot_single_qubit_2_qstate_with_controls
export plot_single_qubit_2_qstate_with_seperated_controls
export plot_multimode
export plot_single_qubit
export plot_transmon
export plot_transmon_population
export plot_twoqubit

using ..Utils
using ..Trajectories
using ..QuantumSystems
using ..Problems

using LaTeXStrings
using CairoMakie

function plot_single_qubit_1_qstate_with_controls(
    prob::QuantumControlProblem,
    filename::String;
    kwargs...
)
    return plot_single_qubit_1_qstate_with_controls(
        prob.trajectory,
        filename,
        prob.system.isodim,
        prob.system.control_order,
        prob.T;
        kwargs...
    )
end


function plot_single_qubit_1_qstate_with_controls(
    traj::Trajectory,
    filename::String,
    isodim::Int,
    control_order::Int,
    T::Int;
    fig_title=nothing,
    i=1
)
    xs = traj.states
    us = traj.actions
    ts = traj.times

    ψ̃s = [xs[t][slice(i, isodim)] for t = 1:T]
    ψ̃s = hcat(ψ̃s...)

    as = [[xs[t][(end - control_order):end]; us[t]] for t = 1:T]
    as = hcat(as...)

    fig = Figure(resolution=(1200, 1000))

    ax1 = Axis(fig[1, 1]; title="qubit components", xlabel=L"t")
    ax2 = Axis(fig[1, 2]; title="control", xlabel=L"t")
    ax3 = Axis(fig[2, 1]; title="first derivative of control", xlabel=L"t")
    ax4 = Axis(fig[2, 2]; title="second derivative of control", xlabel=L"t")

    series!(ax1, ts, ψ̃s;
        labels=[
            L"\mathrm{Re} (\psi_0)",
            L"\mathrm{Re} (\psi_1)",
            L"\mathrm{Im} (\psi_0)",
            L"\mathrm{Im} (\psi_1)"
        ]
    )
    axislegend(ax1; position=:cb)

    lines!(ax2, ts, as[2,:]; label=L"a(t)")
    axislegend(ax2; position=:cb)

    lines!(ax3, ts, as[3,:]; label=L"\mathrm{d}_t a")
    axislegend(ax3; position=:cb)

    lines!(ax4, ts[1:end-1], as[4,1:end-1]; label=L"\mathrm{d}^2_t (t)")
    axislegend(ax4; position=:cb)

    if !isnothing(fig_title)
        Label(fig[0,:], fig_title; textsize=30)
    end

    save(filename, fig)
end

function plot_single_qubit_2_qstate_with_controls(
    prob::QuantumControlProblem,
    filename::String;
    kwargs...
)
    return plot_single_qubit_2_qstate_with_controls(
        prob.trajectory,
        filename,
        prob.system.isodim,
        prob.system.control_order,
        prob.T;
        kwargs...
    )
end

function plot_single_qubit_2_qstate_with_controls(
    traj::Trajectory,
    filename::String,
    isodim::Int,
    control_order::Int,
    T::Int;
    ∫a=false,
    is=(1, 2),
    fig_title=nothing
)

    xs = traj.states
    us = traj.actions
    ts = traj.times

    ψ̃¹s = [xs[t][slice(is[1], isodim)] for t = 1:T]
    ψ̃¹s = hcat(ψ̃¹s...)

    ψ̃²s = [xs[t][slice(is[2], isodim)] for t = 1:T]
    ψ̃²s = hcat(ψ̃²s...)

    as = [[xs[t][slice(∫a + 1, ncontrols)]; us[t]] for t = 1:T]
    as = hcat(as...)
    as[end, end] = as[end, end-1]

    fig = Figure(resolution=(1200, 1000))

    ax_ψ̃¹ = Axis(fig[1, 1]; title="qubit components: U(t)|0⟩", xlabel=L"t")
    ax_ψ̃² = Axis(fig[1, 2]; title="qubit components: U(t)|1⟩", xlabel=L"t")
    ax_as = Axis(fig[2, :]; title="controls", xlabel=L"t")

    series!(ax_ψ̃¹, ts, ψ̃¹s;
        labels=[
            L"\mathrm{Re} (\psi^1_0)",
            L"\mathrm{Re} (\psi^1_1)",
            L"\mathrm{Im} (\psi^1_0)",
            L"\mathrm{Im} (\psi^1_1)"
        ]
    )
    axislegend(ax_ψ̃¹; position=:lb)

    series!(ax_ψ̃², ts, ψ̃²s;
        labels=[
            L"\mathrm{Re} (\psi^2_0)",
            L"\mathrm{Re} (\psi^2_1)",
            L"\mathrm{Im} (\psi^2_0)",
            L"\mathrm{Im} (\psi^2_1)"
        ]
    )
    axislegend(ax_ψ̃²; position=:lb)

    series!(ax_as, ts, as;
        labels=[
            L"a(t)",
            L"\mathrm{d}_t a",
            L"\mathrm{d}^2_t a"
        ]
    )
    axislegend(ax_as; position=:rt)

    if !isnothing(fig_title)
        Label(fig[0,:], fig_title; textsize=30)
    end

    save(filename, fig)
end

function plot_single_qubit_2_qstate_with_seperated_controls(
    traj::Trajectory,
    filename::String,
    isodim::Int,
    control_order::Int,
    T::Int;
    is=(1, 2),
    fig_title=nothing
)

    xs = traj.states
    us = traj.actions
    ts = traj.times

    ψ̃¹s = [xs[t][slice(is[1], isodim)] for t = 1:T]
    ψ̃¹s = hcat(ψ̃¹s...)

    ψ̃²s = [xs[t][slice(is[2], isodim)] for t = 1:T]
    ψ̃²s = hcat(ψ̃²s...)

    as = [[xs[t][(end - control_order + 1):end]; us[t]] for t = 1:T]
    as = hcat(as...)
    as[end, end] = as[end, end-1]

    fig = Figure(resolution=(1200, 1000))

    ax_ψ̃¹ = Axis(
        fig[1:3, 1];
        title="qubit components: U(t)|0⟩",
        xlabel=L"t"
    )

    ax_ψ̃² = Axis(
        fig[1:3, 2];
        title="qubit components: U(t)|1⟩",
        xlabel=L"t"
    )


    series!(ax_ψ̃¹, ts, ψ̃¹s;
        labels=[
            L"\mathrm{Re} (\psi^1_0)",
            L"\mathrm{Re} (\psi^1_1)",
            L"\mathrm{Im} (\psi^1_0)",
            L"\mathrm{Im} (\psi^1_1)"
        ]
    )
    axislegend(ax_ψ̃¹; position=:lb)

    series!(ax_ψ̃², ts, ψ̃²s;
        labels=[
            L"\mathrm{Re} (\psi^2_0)",
            L"\mathrm{Re} (\psi^2_1)",
            L"\mathrm{Im} (\psi^2_0)",
            L"\mathrm{Im} (\psi^2_1)"
        ]
    )
    axislegend(ax_ψ̃²; position=:lb)


    for i = 0:control_order
        ax = Axis(
            fig[4 + i, :];
            xlabel = L"t"
        )

        lines!(
            ax,
            ts,
            as[1 + i, :];
            label = i == 0 ?
                L"a(t)" :
                latexstring(
                    "\\mathrm{d}^{",
                    i == 1 ? "" : "$i",
                    "}_t a"
                )
                # L"\mathrm{d}^{"*(i == 1 ? "" : "$i")*L"}_t a"
                # L"\mathrm{d}^{ \$\(i\) }_t a"
        )

        axislegend(ax; position=:rt)
    end

    if !isnothing(fig_title)
        Label(fig[0,:], fig_title; textsize=30)
    end

    save(filename, fig)
end

function plot_multimode(
    system::QuantumSystem,
    traj::Trajectory,
    path::String;
    components=nothing,
    show_augs=false
)
    # TODO: add this check to all plot functions
    path_parts = split(path, "/")
    dir = joinpath(path_parts[1:end-1])
    if !isdir(dir)
        mkpath(dir)
    end

    fig = Figure(resolution=(1200, 1500))

    ψs = pop_matrix(traj, system; components=components)

    ψax = Axis(
        fig[1:2, :];
        title="multimode system components",
        xlabel=L"t [ns]"
    )

    series!(
        ψax,
        traj.times,
        ψs;
        color=:rainbow1,
        # labels=["|g0⟩", "|g1⟩", "|g2⟩", "|g3⟩", "|g4⟩"]
    )

    axislegend(ψax; position=:lc)

    if show_augs
        for j = 0:system.control_order

            ax_j = Axis(fig[3 + j, :]; xlabel = L"t [ns]")

            data = jth_order_controls_matrix(traj, system, j)

            if j == system.control_order
                data[:, end] = data[:, end-1]
            end

            series!(
                ax_j,
                traj.times,
                data;
                labels = [
                    j == 0 ?
                    latexstring("a_$k (t)") :
                    latexstring(
                        "\\mathrm{d}^{",
                        j == 1 ? "" : "$j",
                        "}_t a_$k"
                    )
                    for k = 1:system.ncontrols
                ]
            )

            axislegend(ax_j; position=:lt)
        end
    else
        ax = Axis(fig[3, :]; xlabel = L"t [ns]")

        data = jth_order_controls_matrix(traj, system, 0)

        series!(
            ax,
            traj.times,
            data;
            labels = [
                latexstring("a_$k (t)")
                    for k = 1:system.ncontrols
            ]
        )

        axislegend(ax; position=:lt)
    end
    save(path, fig)
end

function plot_single_qubit(
    system::QuantumSystem,
    traj::Trajectory,
    path::String;
    fig_title=nothing
)
    path_parts = split(path, "/")
    dir = joinpath(path_parts[1:end-1])
    if !isdir(dir)
        mkpath(dir)
    end

    fig = Figure(resolution=(1200, 1500))

    ψs = wfn_components_matrix(traj, system)

    ψax = Axis(fig[1:2, :]; title="qubit components", xlabel=L"t")
    series!(ψax, traj.times, ψs;
        labels=[
            L"\psi_1^R",
            L"\psi_2^R",
            L"\psi_1^I",
            L"\psi_2^I"]
    )

    axislegend(ψax; position=:lb)

    for j = 0:system.control_order

        ax_j = Axis(fig[3 + j, :]; xlabel = L"t")

        series!(
            ax_j,
            traj.times,
            jth_order_controls_matrix(traj, system, j);
            labels = [
                j == 0 ?
                latexstring("a_$k (t)") :
                latexstring(
                    "\\mathrm{d}^{",
                    j == 1 ? "" : "$j",
                    "}_t a_$k"
                )
                for k = 1:system.ncontrols
            ]
        )

        axislegend(ax_j; position=:lt)
    end

    # TODO: weird plotting behavior, fix this

    # if !isnothing(fig_title)
    #     Label(fig[0,:], fig_title; textsize=30)
    # end

    save(path, fig)
end

function plot_transmon(
    system::QuantumSystem,
    traj::Trajectory,
    path::String;
    fig_title=nothing
)
    fig = Figure(resolution=(1200, 1500))

    ψs = wfn_components_matrix(traj, system)
    #need to rewrite this for arbitrary number of levels
    ψax = Axis(fig[1:2, :]; title="qubit components", xlabel=L"t")
    series!(ψax, traj.times, ψs;
        labels=[
            L"\psi_1^R",
            L"\psi_2^R",
            L"\psi_3^R",
            L"\psi_1^I",
            L"\psi_2^I",
            L"\psi_3^I"]
    )

    axislegend(ψax; position=:lb)

    for j = 0:system.control_order

        ax_j = Axis(fig[3 + j, :]; xlabel = L"t")

        series!(
            ax_j,
            traj.times,
            jth_order_controls_matrix(traj, system, j);
            labels = [
                j == 0 ?
                latexstring("a_$k (t)") :
                latexstring(
                    "\\mathrm{d}^{",
                    j == 1 ? "" : "$j",
                    "}_t a_$k"
                )
                for k = 1:system.ncontrols
            ]
        )

        axislegend(ax_j; position=:lt)
    end

    # if !isnothing(fig_title)
    #     Label(fig[0,:], fig_title; textsize=30)
    # end

    save(path, fig)
end

function plot_transmon_population(
    system::TransmonSystem,
    traj::Trajectory,
    path::String;
    fig_title=nothing
    )



    axislegend(ψax; position=:lb)

    for j = 0:system.control_order

        ax_j = Axis(fig[3 + j, :]; xlabel = L"t")

        series!(
            ax_j,
            traj.times,
            jth_order_controls_matrix(traj, system, j);
            labels = [
                j == 0 ?
                latexstring("a_$k (t)") :
                latexstring(
                    "\\mathrm{d}^{",
                    j == 1 ? "" : "$j",
                    "}_t a_$k"
                )
                for k = 1:system.ncontrols
            ]
        )

        axislegend(ax_j; position=:lt)
    end

    # if !isnothing(fig_title)
    #     Label(fig[0,:], fig_title; textsize=30)
    # end

    save(path, fig)

end

function plot_twoqubit(
    system::QuantumSystem,
    traj::Trajectory,
    path::String;
    fig_title = nothing,
    i = 3
)
    fig = Figure(resolution=(1200, 1500))
    pops = pop_matrix(traj, system, i=i)
    #need to rewrite this for arbitrary number of levels
    ψax = Axis(fig[1:2, :]; title="Population", xlabel=L"t")
    series!(ψax, traj.times, pops;
        labels=[
            "|00⟩",
            "|01⟩",
            "|10⟩",
            "|11⟩",
            ]
    )

    axislegend(ψax; position=:lb)

    for j = 0:system.control_order

        ax_j = Axis(fig[3 + j, :]; xlabel = L"t")

        series!(
            ax_j,
            traj.times,
            jth_order_controls_matrix(traj, system, j);
            labels = [
                j == 0 ?
                latexstring("a_$k (t)") :
                latexstring(
                    "\\mathrm{d}^{",
                    j == 1 ? "" : "$j",
                    "}_t a_$k"
                )
                for k = 1:system.ncontrols
            ]
        )

        axislegend(ax_j; position=:lt)
    end

    # if !isnothing(fig_title)
    #     Label(fig[0,:], fig_title; textsize=30)
    # end

    save(path, fig)

end

end
