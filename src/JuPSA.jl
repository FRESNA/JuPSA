module JuPSA

using DataFrames, LightGraphs

export Network, import_network, idx, rev_idx, select_names, select_by, idx_by, to_symbol, append_idx_col!

include("auxilliaries.jl")
include("lopf.jl")

mutable struct Network
    buses::DataFrame
    generators::DataFrame
    loads::DataFrame
    lines::DataFrame
    links::DataFrame
    storage_units::DataFrame
    transformers::DataFrame
    buses_t::Dict{String,DataFrame}
    generators_t::Dict{String,DataFrame}
    loads_t::Dict{String,DataFrame}
    lines_t::Dict{String,DataFrame}
    links_t::Dict{String,DataFrame}
    storage_units_t::Dict{String,DataFrame}
    transformers_t::Dict{String,DataFrame}
    snapshots::DataFrame
end



function Network(
    buses=DataFrame(repeat([Bool[]], outer=13),
[:name, :area, :area_offshore, :carrier, :control,
:country, :type, :v_nom, :v_mag_pu_set, :v_mag_pu_min,
:v_mag_pu_max, :x, :y]),

    generators=DataFrame(repeat([Bool[]], outer=27),
        [:bus, :control, :type, :p_nom, :p_nom_extendable,
        :p_nom_min, :p_nom_max, :p_min_pu, :p_max_pu, :p_set, :q_set, :sign,
        :carrier, :marginal_cost, :capital_cost, :efficiency, :committable,
        :start_up_cost, :shut_down_cost, :min_up_time, :min_down_time,
        :initial_status, :ramp_limit_up, :ramp_limit_down, :ramp_limit_start_up,
        :ramp_limit_shut_down, :p_nom_opt]),
    loads=DataFrame(repeat([Bool[]], outer=5),
        [:bus, :type, :p_set, :q_set, :sign]),
    lines=DataFrame(repeat([Bool[]], outer=23),
        [:bus0, :bus1, :type, :x, :r, :g, :b, :s_nom, :s_nom_extendable,
        :s_nom_min, :s_nom_max, :capital_cost, :length, :terrain_factor,
        :num_parallel, :v_ang_min, :v_ang_max, :sub_network, :x_pu,
        :r_pu, :g_pu, :b_pu, :s_nom_opt]) ,

    links=DataFrame(repeat([Bool[]], outer=16),
        [:bus0, :bus1, :type, :efficiency, :p_nom,
        :p_nom_extendable, :p_nom_min, :p_nom_max, :p_set, :p_min_pu,
        :p_max_pu, :capital_cost, :marginal_cost, :length, :terrain_factor,
        :p_nom_opt]),

    storage_units=DataFrame(repeat([Bool[]], outer=24),
        [:bus, :control, :type, :p_nom, :p_nom_extendable,
        :p_nom_min, :p_nom_max, :p_min_pu, :p_max_pu, :p_set,
        :q_set, :sign, :carrier, :marginal_cost, :capital_cost,
        :state_of_charge_initial, :state_of_charge_set,
        :cyclic_state_of_charge, :max_hours, :efficiency_store,
        :efficiency_dispatch, :standing_loss, :inflow, :p_nom_opt]),

    transformers=DataFrame(repeat([Bool[]], outer=26),
        [:bus0, :bus1, :type, :model, :x, :r, :g, :b, :s_nom,
        :s_nom_extendable, :s_nom_min, :s_nom_max, :capital_cost,
        :num_parallel, :tap_ratio, :tap_side, :tap_position,
        :phase_shift, :v_ang_min, :v_ang_max, :sub_network,
        :x_pu, :r_pu, :g_pu, :b_pu, :s_nom_opt]),

    buses_t=Dict([("marginal_price",DataFrame()), ("v_ang", DataFrame()),
            ("v_mag_pu_set",DataFrame()), ("q", DataFrame()),
            ("v_mag_pu", DataFrame()), ("p", DataFrame()), ("p_max_pu", DataFrame())]),
    generators_t=Dict{String,DataFrame}(
            [("marginal_price",DataFrame()), ("v_ang", DataFrame()),
            ("v_mag_pu_set",DataFrame()), ("q", DataFrame()),
            ("v_mag_pu", DataFrame()), ("p", DataFrame())]),
    loads_t=Dict{String,DataFrame}([("q_set",DataFrame()), ("p_set", DataFrame()),
            ("q", DataFrame()), ("p", DataFrame())]),
    lines_t=Dict{String,DataFrame}([("q0",DataFrame()), ("q1", DataFrame()),
            ("p0",DataFrame()), ("p1", DataFrame()),
            ("mu_lower", DataFrame()), ("mu_upper", DataFrame())]),
    links_t=Dict{String,DataFrame}([("p_min_pu",DataFrame()), ("p_max_pu", DataFrame()),
            ("p0",DataFrame()), ("p1", DataFrame()),
            ("mu_lower", DataFrame()), ("mu_upper", DataFrame()),
            ("efficiency",DataFrame()), ("p_set", DataFrame())]),
    storage_units_t=Dict{String,DataFrame}([("p_min_pu",DataFrame()), ("p_max_pu", DataFrame()),
        ("inflow",DataFrame()), ("mu_lower", DataFrame()), ("mu_upper", DataFrame()),
        ("efficiency",DataFrame()), ("p_set", DataFrame())]),
    transformers_t=Dict{String,DataFrame}([("p0",DataFrame()), ("p1", DataFrame()),
            ("q0", DataFrame()), ("q1", DataFrame()),
            ("mu_upper",DataFrame())]),
    snapshots=DataFrame(Bool[])
    )
    Network(
        buses, generators, loads, lines, links, transformers, buses_t,
        generators_t, loads_t, lines_t, links_t, storage_unists_t, transformers_t)
end


function import_network(folder)
    network = JuPSA.Network()
    !ispath("$folder") ? error("Path not existent") : nothing
    components = [component for component=fieldnames(network) if String(component)[end-1:end]!="_t"]
    for component=components
        if ispath("$folder/$component.csv")
            setfield!(network,component,readtable("$folder/$component.csv", truestrings=["True"],
                                            falsestrings=["False"]))
        end
    end
    components_t = [field for field=fieldnames(network) if String(field)[end-1:end]=="_t"]
    for component_t=components_t
        for attr in keys(getfield(network, component_t))
            component = Symbol(String(component_t)[1:end-2])
            ispath("$folder/$component-$attr.csv") ? getfield(network,component_t)[attr]= (
                readtable("$folder/$component-$attr.csv", truestrings=["True"], falsestrings=["False"]) ): nothing
        end
    end
    return network
end


function export_network(network, folder)
    !ispath(folder) ? mkdir(folder) : nothing
    components_t = [field for field=fieldnames(network) if String(field)[end-1:end]=="_t"]
    for field_t in components_t
        for df_name=keys(getfield(network,field_t))
            if nrow(getfield(network,field_t)[df_name])>0
                field = Symbol(String(field_t)[1:end-2])
                writetable("$folder/$field-$df_name.csv", getfield(network,field_t)[df_name])
            end
        end
    end
    components = [field for field=fieldnames(network) if String(field)[end-1:end]!="_t"]
    for field in components
        writetable("$folder/$field.csv", getfield(network, field))
    end
end



end
