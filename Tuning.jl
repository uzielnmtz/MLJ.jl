"""
    Updates the current array of parameters, looping around when out of their
    range. Only modifies array
"""
function update_parameters!(array, range)

    array[1] += 1
    for i in 1:length(array)-1
        if array[i] > range[i][end]
            try
                array[i+1] += 1
            catch e
                println("Array out of bound while updating parameters")
            end
            array[i] = range[i][1]
        end
    end
end

"""
    Creates a dictionary of {"Parameter name"=>"Value", .. }
"""
function parameters_dictionary(ps::ParametersSet, array, discrete_prms_map)
    dict = Dict()
    for i in 1:length(array)
        if typeof(ps[i]) <: ContinuousParameter
            dict[Symbol(ps[i].name)] = ps[i].transform( convert(Float64, array[i]) )
        else
            dict[Symbol(ps[i].name)] = discrete_prms_map[ps[i].name][array[i]]
        end
    end
    dict
end


"""
    Sets up the initial parameter value-indeces and ranges of each parameter
    Also sets up the dictionary used for discrete parameters
    @return
        total number of parameters' combinations
"""
function prepare_parameters!(prms_set, prms_value, prms_range, discrete_prms_map,
                             n_parameters)

    total_parameters = 1
    for i in 1:n_parameters
        if typeof(prms_set[i]) <: ContinuousParameter
            # Setup the initial value and range of each parameter
            lower = prms_set[i].lower
            upper = prms_set[i].upper
            prms_value[i] = lower
            prms_range[i] = Tuple(lower:upper)
            params = length(lower:upper)
        else
            # For discrete parameters, we use a dict index=>discrete_value
            prms_value[i] = 1
            prms_range[i] = Tuple(1:length(prms_set[i].values))
            discrete_prms_map[prms_set[i].name] = prms_set[i].values
            params = length(prms_set[i].values)
        end
        total_parameters *= params
    end
    total_parameters
end


"""
    Tunes learner given a task and parameter sets.
    Returns a learner which contains best tuned model
"""
function tune(learner::Learner, task::MLTask, parameters_set::ParametersSet;
                sampler=Resampling()::Resampling, measure=MLMetrics.accuracy::Function,
                storage=MLJStorage()::MLJStorage)

    # TODO: divide and clean up code. Use better goddam variable names.

    n_parameters = length(parameters_set.parameters)
    n_obs        = size(data,1)

    # TODO: remake this iteration hacky thing
    # prms_value: current value-index of each parameter
    # prms_range: range of each parameter
    # For discrete parameters, the range is set to 1:(number of discrete values)
    # The discrete map variable allows to connect this range to
    # the actual discrete value it represents
    prms_value  = Array{Any}(n_parameters)
    prms_range = Array{Tuple}(n_parameters)
    discrete_prms_map = Dict()

    # Prepare parameters
    total_parameters = prepare_parameters!(parameters_set, prms_value, prms_range,
                                            discrete_prms_map, n_parameters)


    # Loop over parameters
    for i in 1:total_parameters
        # Set new parametersparameters_set[i].values
        pd = parameters_dictionary(parameters_set, prms_value, discrete_prms_map)

        # Update learner with new parameters
        lrn = ModelLearner(learner.name, pd)

        # Get training/testing validation sets
        trainⱼ, testⱼ = get_samples(sampler, n_obs)

        measures = []
        for j in 1:length(trainⱼ)
            modelᵧ = learnᵧ(lrn, task)
            preds, prob = predictᵧ(modelᵧ, task.data[testⱼ[j],task.features], task)

            _measure = measure( task.data[testⱼ[j], task.targets[1]], preds)
            push!(measures, _measure)
        end
        # Store and print cross validation results
        store_results!(storage, measures, lrn)
        println("Trained:")
        println(lrn)
        println("Average CV accuracy: $(mean(measures))\n")

        update_parameters!(prms_value, prms_range)
    end

    println("Retraining best model")
    best_index = indmax(storage.averageCV)
    lrn = ModelLearner(storage.models[best_index], storage.parameters[best_index])
    modelᵧ = learnᵧ(lrn, task)
    lrn = ModelLearner(lrn, modelᵧ, parameters_set)

    lrn
end



"""
    Tune for multiplex type
"""
function tune(multiplex::MLJMultiplex, task::MLTask;
    sampler=Resampling()::Resampling, measure=MLMetrics.accuracy::Function,
    storage=nothing::Union{Void,MLJStorage})

    # Tune each model separately
    for i in 1:multiplex.size
        multiplex.learners[i]  = tune(multiplex.learners[i], task, multiplex.parametersSets[i],
                                        sampler=sampler, measure=measure, storage=storage)
    end
end

"""
    Tunes multiple models with multiple different paramters
"""
function GroupTuner(;learners=nothing::Array{<:Learner}, task=nothing::MLTask, data=nothing::Matrix{Real},
                parameters_sets=nothing::Array{<:ParametersSet}, sampler=Resampling()::Resampling,
                measure=nothing::Function, storage=nothing::Union{Void,MLJStorage})

    storage = MLJStorage()
    for (i,lrn) in enumerate(learners)
        tune(learner=lrn, task=task, data=data, parameters_set=parameters_sets[i],
            sampler=sampler, measure=measure, storage=storage)
    end
    storage
end
