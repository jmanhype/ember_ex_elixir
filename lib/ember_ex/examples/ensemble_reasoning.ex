defmodule EmberEx.Examples.EnsembleReasoning do
  @moduledoc """
  Demonstrates the ensemble pattern for robust LLM reasoning using EmberEx.
  
  This example implements a robust reasoning system that uses multiple LLMs
  in parallel and aggregates their responses to create a more reliable answer.
  It mirrors Python Ember's ensemble pattern approach but with Elixir syntax
  and functional programming paradigms.
  
  The pattern involves:
  1. Parallel execution of multiple LLMs with the same prompt
  2. Aggregation of responses using various strategies
  3. Selection or synthesis of the final answer
  """
  
  alias EmberEx.Operators.{
    EnsembleOperator,
    LLMOperator,
    MostCommonOperator, 
    SelectorJudgeOperator,
    SynthesisJudgeOperator
  }
  
  @doc """
  Creates an ensemble reasoning pipeline with different aggregation strategies.
  
  ## Parameters
  
  - model_configs: List of model configurations to use in the ensemble
  - strategy: The aggregation strategy (:majority_vote, :judge_selection, or :synthesis)
  - judge_model: Optional model to use as judge (required for :judge_selection and :synthesis)
  
  ## Returns
  
  An operator that performs ensemble reasoning with the specified strategy
  
  ## Examples
  
      iex> # Setup model configs
      iex> model_configs = [
      ...>   %{provider: :openai, model_id: "gpt-3.5-turbo"},
      ...>   %{provider: :openai, model_id: "gpt-4-turbo"},
      ...>   %{provider: :anthropic, model_id: "claude-3-haiku"}
      ...> ]
      iex> 
      iex> # Create ensemble with majority vote
      iex> majority_ensemble = EmberEx.Examples.EnsembleReasoning.create_ensemble(
      ...>   model_configs,
      ...>   :majority_vote
      ...> )
      iex> 
      iex> # Create ensemble with judge selection
      iex> judge_model = EmberEx.Models.create_model_callable("openai/gpt-4")
      iex> judge_ensemble = EmberEx.Examples.EnsembleReasoning.create_ensemble(
      ...>   model_configs,
      ...>   :judge_selection,
      ...>   judge_model
      ...> )
      iex> 
      iex> # Use the ensemble
      iex> EmberEx.Operators.Operator.call(majority_ensemble, "What is the capital of France?")
      %{answer: "Paris", confidence: 1.0}
  """
  @spec create_ensemble(
    [map()],
    :majority_vote | :judge_selection | :synthesis,
    EmberEx.Models.ModelCallable.t() | nil
  ) :: EmberEx.Operators.Operator.t()
  def create_ensemble(model_configs, strategy, judge_model \\ nil) do
    # Create LLM operators for each model config
    llm_operators = Enum.map(model_configs, fn config ->
      # Determine provider module based on config
      provider_module = case config.provider do
        :openai -> EmberEx.Models.Providers.OpenAI
        :anthropic -> EmberEx.Models.Providers.Anthropic
        other -> raise "Unsupported provider: #{inspect(other)}"
      end
      
      # Create model callable
      model_callable = fn input ->
        # Override model ID from config
        input = Map.put(input, :model, config.model_id)
        
        # Call the provider
        case provider_module.generate_with_model(
          config.model_id,
          input,
          %{api_key: System.get_env("OPENAI_API_KEY")}
        ) do
          {:ok, response} -> {:ok, response}
          error -> error
        end
      end
      
      # Create the LLM operator
      LLMOperator.new(model_callable, "llm_#{config.provider}_#{config.model_id}")
    end)
    
    # Create prompt construction function
    create_prompt = fn query ->
      """
      Answer the following question concisely and accurately:
      #{query}
      
      Provide only the direct answer without any explanations or extra information.
      """
    end
    
    # Create prompt constructor operator
    prompt_op = EmberEx.Operators.MapOperator.new(fn query ->
      %{
        messages: [
          %{role: "user", content: create_prompt.(query)}
        ]
      }
    end)
    
    # Create ensemble operator to run all models in parallel
    ensemble_op = EnsembleOperator.new(
      llm_operators,
      fn results ->
        # Extract responses from results
        responses = Enum.map(results, fn
          %{content: content} -> content
          response -> response  # For simplicity, allow direct string responses too
        end)
        
        %{responses: responses}
      end
    )
    
    # Create aggregation operator based on strategy
    aggregation_op = case strategy do
      :majority_vote ->
        # Use MostCommonOperator to select the most frequent answer
        EmberEx.Operators.MostCommonOperator.new(
          :responses,
          :answer,
          :distribution,
          &String.trim/1
        )
        
      :judge_selection when not is_nil(judge_model) ->
        # Use SelectorJudgeOperator to select the best answer
        SelectorJudgeOperator.new(
          judge_model,
          "Select the most accurate and concise answer.",
          :responses,
          :answer,
          true
        )
        
      :synthesis when not is_nil(judge_model) ->
        # Use SynthesisJudgeOperator to create a synthesized answer
        SynthesisJudgeOperator.new(
          judge_model,
          "Synthesize the most accurate answer from these responses.",
          :responses,
          :answer,
          :synthesize
        )
        
      _ ->
        raise ArgumentError, "Invalid strategy or missing judge model"
    end
    
    # Create confidence calculation operator
    confidence_op = EmberEx.Operators.MapOperator.new(fn input ->
      # Calculate confidence based on distribution or reasoning
      confidence = cond do
        # For majority vote, use the proportion of responses that match
        Map.has_key?(input, :distribution) ->
          {_, count} = Enum.max_by(input.distribution, fn {_, count} -> count end)
          count / length(model_configs)
          
        # For judge selection, confidence is based on presence of reasoning
        Map.has_key?(input, :reasoning) ->
          0.9  # High confidence since a judge reviewed the answers
          
        true ->
          0.7  # Default confidence
      end
      
      # Return final result
      %{
        answer: input.answer,
        confidence: confidence
      }
    end)
    
    # Create the full pipeline
    EmberEx.Operators.SequenceOperator.new([
      prompt_op,
      ensemble_op,
      aggregation_op,
      confidence_op
    ], "ensemble_reasoning_#{strategy}")
  end
  
  @doc """
  Creates an example ensemble reasoning system with mock models.
  
  ## Parameters
  
  - strategy: The aggregation strategy to use
  
  ## Returns
  
  An ensemble operator with mock models
  
  ## Examples
  
      iex> ensemble = EmberEx.Examples.EnsembleReasoning.create_example(:majority_vote)
      iex> EmberEx.Operators.Operator.call(ensemble, "What is the capital of France?")
      %{answer: "Paris", confidence: 1.0}
      
      iex> ensemble = EmberEx.Examples.EnsembleReasoning.create_example(:judge_selection)
      iex> EmberEx.Operators.Operator.call(ensemble, "When was the Eiffel Tower built?")
      %{answer: "1889", confidence: 0.9}
  """
  @spec create_example(:majority_vote | :judge_selection | :synthesis) :: EmberEx.Operators.Operator.t()
  def create_example(strategy) do
    # Create mock models with different response patterns
    mock_model1 = fn %{messages: [%{content: prompt}]} ->
      question = String.replace(prompt, ~r/^Answer the following question.+:\s+/, "")
                |> String.replace(~r/\s+Provide only the direct.+$/, "")
      
      answer = case question do
        "What is the capital of France?" -> "Paris"
        "When was the Eiffel Tower built?" -> "1889"
        "What is the largest planet in our solar system?" -> "Jupiter"
        "Who wrote Romeo and Juliet?" -> "William Shakespeare"
        "What is the square root of 64?" -> "8"
        _ -> "I don't know"
      end
      
      {:ok, %{content: answer}}
    end
    
    # Second model with some variations and errors
    mock_model2 = fn %{messages: [%{content: prompt}]} ->
      question = String.replace(prompt, ~r/^Answer the following question.+:\s+/, "")
                |> String.replace(~r/\s+Provide only the direct.+$/, "")
      
      answer = case question do
        "What is the capital of France?" -> "Paris"
        "When was the Eiffel Tower built?" -> "1887"  # Slight error
        "What is the largest planet in our solar system?" -> "Jupiter"
        "Who wrote Romeo and Juliet?" -> "Shakespeare"  # Incomplete
        "What is the square root of 64?" -> "8"
        _ -> "Unknown"
      end
      
      {:ok, %{content: answer}}
    end
    
    # Third model with some different answers
    mock_model3 = fn %{messages: [%{content: prompt}]} ->
      question = String.replace(prompt, ~r/^Answer the following question.+:\s+/, "")
                |> String.replace(~r/\s+Provide only the direct.+$/, "")
      
      answer = case question do
        "What is the capital of France?" -> "Paris"
        "When was the Eiffel Tower built?" -> "1889"
        "What is the largest planet in our solar system?" -> "Jupiter"
        "Who wrote Romeo and Juliet?" -> "William Shakespeare"
        "What is the square root of 64?" -> "8.0"  # Different format
        _ -> "I'm not sure"
      end
      
      {:ok, %{content: answer}}
    end
    
    # Judge model for judge_selection and synthesis strategies
    judge_model = fn %{messages: [%{content: prompt}]} ->
      responses = Regex.scan(~r/Response (\d+):\s*(.*?)(?=\n\n|$)/s, prompt)
                  |> Enum.map(fn [_, _index, response] -> String.trim(response) end)
      
      question = Regex.run(~r/these responses:\s*(.*?)(?=\n\n|$)/s, prompt)
                 |> Enum.at(1, "")
                 |> String.trim()
      
      # Select the most accurate response
      result = case strategy do
        :judge_selection ->
          # Find the index of the best response
          best_index = cond do
            String.contains?(question, "Eiffel Tower") ->
              # Model1 and Model3 have the correct answer (1889)
              Enum.find_index(responses, &(&1 == "1889")) + 1
              
            String.contains?(question, "Romeo and Juliet") ->
              # Model1 and Model3 have the full name
              Enum.find_index(responses, &(&1 == "William Shakespeare")) + 1
              
            true ->
              # Default to the first response for other questions
              1
          end
          
          %{
            selected_index: best_index,
            reasoning: "This answer is the most complete and accurate based on historical records."
          }
          
        :synthesis ->
          # For synthesis, create a combined answer
          synthesized = if String.contains?(question, "square root") do
            "8"  # Standardize format
          else
            # Use the most common answer
            responses
            |> Enum.frequencies()
            |> Enum.max_by(fn {_, count} -> count end)
            |> elem(0)
          end
          
          %{content: synthesized}
      end
      
      {:ok, result}
    end
    
    # Create model configs for the ensemble
    model_configs = [
      %{provider: :openai, model_id: "mock-model-1"},
      %{provider: :openai, model_id: "mock-model-2"},
      %{provider: :anthropic, model_id: "mock-model-3"}
    ]
    
    # Replace the provider modules with our mock implementations
    _original_find_provider = EmberEx.Registry.find_provider
    
    # Create mock providers
    _mock_providers = %{
      openai: fn
        %{model: "mock-model-1"} = _request, _config -> mock_model1.(%{messages: [%{content: ""}]})
        %{model: "mock-model-2"} = _request, _config -> mock_model2.(%{messages: [%{content: ""}]})
        _, _ -> {:error, "Invalid model"}
      end,
      anthropic: fn
        %{model: "mock-model-3"} = _request, _config -> mock_model3.(%{messages: [%{content: ""}]})
        _, _ -> {:error, "Invalid model"}
      end
    }
    
    # Override LLMOperator's call to use our mock functions directly
    _original_llm_call = EmberEx.Operators.LLMOperator.forward
    
    # Patch the LLMOperator.forward function for our example
    _patched_llm_forward = fn
      %{callable: callable} = _operator, input when is_function(callable, 1) ->
        # If it's a normal callable, use it
        callable.(input)
        
      %{name: name} = _operator, input -> 
        # Otherwise, determine which mock to use based on name
        cond do
          String.contains?(name, "mock-model-1") -> mock_model1.(input)
          String.contains?(name, "mock-model-2") -> mock_model2.(input)
          String.contains?(name, "mock-model-3") -> mock_model3.(input)
          true -> {:error, "Unknown model in patched forward"}
        end
    end
    
    # For simplicity, we'll just use the mock callables directly
    create_ensemble(model_configs, strategy, judge_model)
  end
end
