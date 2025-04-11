defmodule EmberEx.Operators.SelectorJudgeOperator do
  @moduledoc """
  Selects the best response from a set of alternatives using a language model as judge.
  
  This operator evaluates multiple responses against specified criteria using a language
  model and returns the best one based on the judgment.
  """
  
  use EmberEx.Operators.BaseOperator
  
  @typedoc "SelectorJudgeOperator struct type"
  @type t :: %__MODULE__{
    model: EmberEx.Models.ModelCallable.t(),
    criteria: String.t(),
    candidate_key: atom() | String.t(),
    output_key: atom() | String.t() | nil,
    include_reasoning: boolean(),
    model_kwargs: map()
  }
  
  defstruct [
    :model,
    :criteria,
    :candidate_key,
    :output_key,
    :include_reasoning,
    :model_kwargs
  ]
  
  @doc """
  Create a new SelectorJudgeOperator.
  
  ## Parameters
  
  - model: The model callable to use for judging
  - criteria: The criteria to use for judging
  - candidate_key: The key to extract candidates from the input map
  - output_key: The key to use for the output map (nil to return the raw result)
  - include_reasoning: Whether to include the reasoning in the output
  - model_kwargs: Additional keyword arguments to pass to the model
  
  ## Returns
  
  A new SelectorJudgeOperator struct
  
  ## Examples
  
      iex> model = EmberEx.Models.create_model_callable("openai/gpt-4")
      iex> criteria = "Select the answer that is most accurate and comprehensive."
      iex> op = EmberEx.Operators.SelectorJudgeOperator.new(model, criteria, :candidates, :best_answer, true)
  """
  @spec new(
    EmberEx.Models.ModelCallable.t(),
    String.t(),
    atom() | String.t(),
    atom() | String.t() | nil,
    boolean(),
    map()
  ) :: t()
  def new(model, criteria, candidate_key, output_key \\ nil, include_reasoning \\ false, model_kwargs \\ %{}) do
    %__MODULE__{
      model: model,
      criteria: criteria,
      candidate_key: candidate_key,
      output_key: output_key,
      include_reasoning: include_reasoning,
      model_kwargs: model_kwargs
    }
  end
  
  @doc """
  Create a new SelectorJudgeOperator with a name.
  
  ## Parameters
  
  - name: The name of the operator
  - model: The model callable to use for judging
  - criteria: The criteria to use for judging
  - candidate_key: The key to extract candidates from the input map
  - output_key: The key to use for the output map (nil to return the raw result)
  - include_reasoning: Whether to include the reasoning in the output
  - model_kwargs: Additional keyword arguments to pass to the model
  
  ## Returns
  
  A new SelectorJudgeOperator struct
  """
  @spec new_with_name(
    String.t(),
    EmberEx.Models.ModelCallable.t(),
    String.t(),
    atom() | String.t(),
    atom() | String.t() | nil,
    boolean(),
    map()
  ) :: t()
  def new_with_name(
    name,
    model,
    criteria,
    candidate_key,
    output_key \\ nil,
    include_reasoning \\ false,
    model_kwargs \\ %{}
  ) do
    %__MODULE__{
      model: model,
      criteria: criteria,
      candidate_key: candidate_key,
      output_key: output_key,
      include_reasoning: include_reasoning,
      model_kwargs: model_kwargs
    }
    |> EmberEx.Operators.BaseOperator.set_name(name)
  end
  
  @doc """
  Process inputs and select the best candidate.
  
  ## Parameters
  
  - operator: The SelectorJudgeOperator struct
  - inputs: A map of input values
  
  ## Returns
  
  The best candidate or a map with the best candidate and reasoning
  
  ## Examples
  
      iex> model = EmberEx.Models.create_model_callable("openai/gpt-4")
      iex> criteria = "Select the most accurate definition."
      iex> op = EmberEx.Operators.SelectorJudgeOperator.new(model, criteria, :definitions, :best_definition, true)
      iex> definitions = [
      ...>   "Quantum computing uses quantum bits to perform calculations.",
      ...>   "Quantum computers use quantum mechanics for computation."
      ...> ]
      iex> EmberEx.Operators.Operator.call(op, %{definitions: definitions})
      %{
        best_definition: "Quantum computers use quantum mechanics for computation.",
        reasoning: "This definition is more accurate because..."
      }
  """
  @impl true
  def forward(%__MODULE__{} = operator, inputs) do
    # Extract candidates from inputs
    candidates = Map.get(inputs, operator.candidate_key)
    
    # Validate candidates
    unless is_list(candidates) do
      raise ArgumentError, "Candidates must be a list"
    end
    
    if Enum.empty?(candidates) do
      raise ArgumentError, "Candidates list cannot be empty"
    end
    
    # Create a numbered list of candidates for the prompt
    candidates_text = candidates
    |> Enum.with_index(1)
    |> Enum.map(fn {candidate, index} -> "Candidate #{index}:\n#{candidate}" end)
    |> Enum.join("\n\n")
    
    # Create the prompt for the LLM
    prompt = """
    I need you to evaluate the following candidates according to these criteria:
    
    #{operator.criteria}
    
    Here are the candidates:
    
    #{candidates_text}
    
    Please select the best candidate based on the criteria. 
    
    Format your response as a JSON object with the following fields:
    - "selected_index": The 1-based index of the best candidate.
    - "reasoning": Your reasoning for this selection.
    """
    
    # Prepare output schema for structured output
    output_schema = %{
      "type" => "object",
      "properties" => %{
        "selected_index" => %{"type" => "integer"},
        "reasoning" => %{"type" => "string"}
      },
      "required" => ["selected_index", "reasoning"]
    }
    
    # Prepare model arguments
    model_args = Map.merge(operator.model_kwargs, %{
      messages: [
        %{role: "user", content: prompt}
      ],
      response_model: output_schema
    })
    
    # Execute the model
    case operator.model.(model_args) do
      {:ok, response} ->
        # Get the selected index and reasoning
        selected_index = response.selected_index
        reasoning = response.reasoning
        
        # Get the selected candidate
        selected_candidate = if selected_index > 0 && selected_index <= length(candidates) do
          Enum.at(candidates, selected_index - 1)
        else
          # If invalid index, return the first candidate
          List.first(candidates)
        end
        
        # Return the result in the appropriate format
        result = if operator.include_reasoning do
          %{
            best_candidate: selected_candidate,
            reasoning: reasoning
          }
        else
          selected_candidate
        end
        
        if operator.output_key do
          if operator.include_reasoning do
            %{
              operator.output_key => selected_candidate,
              :reasoning => reasoning
            }
          else
            %{operator.output_key => selected_candidate}
          end
        else
          result
        end
        
      {:error, reason} ->
        # In case of error, return the first candidate
        fallback = List.first(candidates)
        
        # Log the error
        require Logger
        Logger.error("SelectorJudgeOperator execution failed: #{inspect(reason)}")
        
        if operator.output_key do
          %{operator.output_key => fallback}
        else
          fallback
        end
    end
  end
end
