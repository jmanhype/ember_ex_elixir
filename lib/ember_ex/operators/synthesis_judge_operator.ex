defmodule EmberEx.Operators.SynthesisJudgeOperator do
  @moduledoc """
  Synthesizes and judges multiple responses to select the best one.
  
  This operator combines multiple responses and uses a language model to
  judge which one is best according to specified criteria, or synthesizes
  a new response that combines the best elements of all inputs.
  """
  
  use EmberEx.Operators.BaseOperator
  
  @typedoc "SynthesisJudgeOperator struct type"
  @type t :: %__MODULE__{
    model: EmberEx.Models.ModelCallable.t(),
    criteria: String.t(),
    input_key: atom() | String.t() | nil,
    output_key: atom() | String.t() | nil,
    mode: :select | :synthesize,
    model_kwargs: map()
  }
  
  defstruct [:model, :criteria, :input_key, :output_key, :mode, :model_kwargs]
  
  @doc """
  Create a new SynthesisJudgeOperator.
  
  ## Parameters
  
  - model: The model callable to use for judging
  - criteria: The criteria to use for judging
  - input_key: The key to extract from the input map (nil to use the entire input)
  - output_key: The key to use for the output map (nil to return the raw result)
  - mode: The mode to use (:select to pick the best response, :synthesize to create a new one)
  - model_kwargs: Additional keyword arguments to pass to the model
  
  ## Returns
  
  A new SynthesisJudgeOperator struct
  
  ## Examples
  
      iex> model = EmberEx.Models.create_model_callable("openai/gpt-4")
      iex> criteria = "Select the response that best explains quantum computing in simple terms."
      iex> op = EmberEx.Operators.SynthesisJudgeOperator.new(model, criteria, :responses, :best_response, :select)
  """
  @spec new(
    EmberEx.Models.ModelCallable.t(),
    String.t(),
    atom() | String.t() | nil,
    atom() | String.t() | nil,
    :select | :synthesize,
    map()
  ) :: t()
  def new(model, criteria, input_key \\ nil, output_key \\ nil, mode \\ :select, model_kwargs \\ %{}) do
    %__MODULE__{
      model: model,
      criteria: criteria,
      input_key: input_key,
      output_key: output_key,
      mode: mode,
      model_kwargs: model_kwargs
    }
  end
  
  @doc """
  Create a new SynthesisJudgeOperator with a name.
  
  ## Parameters
  
  - name: The name of the operator
  - model: The model callable to use for judging
  - criteria: The criteria to use for judging
  - input_key: The key to extract from the input map (nil to use the entire input)
  - output_key: The key to use for the output map (nil to return the raw result)
  - mode: The mode to use (:select to pick the best response, :synthesize to create a new one)
  - model_kwargs: Additional keyword arguments to pass to the model
  
  ## Returns
  
  A new SynthesisJudgeOperator struct
  """
  @spec new_with_name(
    String.t(),
    EmberEx.Models.ModelCallable.t(),
    String.t(),
    atom() | String.t() | nil,
    atom() | String.t() | nil,
    :select | :synthesize,
    map()
  ) :: t()
  def new_with_name(name, model, criteria, input_key \\ nil, output_key \\ nil, mode \\ :select, model_kwargs \\ %{}) do
    %__MODULE__{
      model: model,
      criteria: criteria,
      input_key: input_key,
      output_key: output_key,
      mode: mode,
      model_kwargs: model_kwargs
    }
    |> EmberEx.Operators.BaseOperator.set_name(name)
  end
  
  @doc """
  Create a selection prompt for judging responses.
  
  ## Parameters
  
  - responses: A list of responses to judge
  - criteria: The criteria to use for judging
  
  ## Returns
  
  A prompt string for the language model
  """
  @spec create_selection_prompt(list(String.t()), String.t()) :: String.t()
  def create_selection_prompt(responses, criteria) do
    # Create a numbered list of responses
    responses_text = responses
    |> Enum.with_index(1)
    |> Enum.map(fn {response, index} -> "Response #{index}:\n#{response}" end)
    |> Enum.join("\n\n")
    
    """
    I have multiple responses to a query, and I need you to select the best one based on the following criteria:
    
    #{criteria}
    
    Here are the responses:
    
    #{responses_text}
    
    Based on the criteria above, which response is the best? Return only the number of the best response.
    """
  end
  
  @doc """
  Create a synthesis prompt for combining responses.
  
  ## Parameters
  
  - responses: A list of responses to synthesize
  - criteria: The criteria to use for synthesizing
  
  ## Returns
  
  A prompt string for the language model
  """
  @spec create_synthesis_prompt(list(String.t()), String.t()) :: String.t()
  def create_synthesis_prompt(responses, criteria) do
    # Create a numbered list of responses
    responses_text = responses
    |> Enum.with_index(1)
    |> Enum.map(fn {response, index} -> "Response #{index}:\n#{response}" end)
    |> Enum.join("\n\n")
    
    """
    I have multiple responses to a query, and I need you to synthesize a new response that combines the best elements of all of them based on the following criteria:
    
    #{criteria}
    
    Here are the responses:
    
    #{responses_text}
    
    Based on the criteria above, please synthesize a new response that combines the best elements of all the responses. The goal is not to simply pick the best one, but to create a new response that is better than any individual response.
    """
  end
  
  @doc """
  Process inputs and judge or synthesize responses.
  
  ## Parameters
  
  - operator: The SynthesisJudgeOperator struct
  - inputs: A map of input values or a direct input value
  
  ## Returns
  
  The best response or a synthesized response
  
  ## Examples
  
      iex> model = EmberEx.Models.create_model_callable("openai/gpt-4")
      iex> criteria = "Select the response that best explains quantum computing."
      iex> op = EmberEx.Operators.SynthesisJudgeOperator.new(model, criteria, :responses, :best_response, :select)
      iex> responses = [
      ...>   "Quantum computing uses quantum bits or qubits to perform calculations.",
      ...>   "Quantum computers leverage quantum mechanics principles for computation."
      ...> ]
      iex> EmberEx.Operators.Operator.call(op, %{responses: responses})
      %{best_response: "Quantum computers leverage quantum mechanics principles for computation."}
  """
  @impl true
  def forward(%__MODULE__{} = operator, inputs) do
    # Extract the input values
    input_values = if operator.input_key do
      Map.get(inputs, operator.input_key)
    else
      inputs
    end
    
    # Ensure input is a list
    responses = cond do
      is_list(input_values) -> input_values
      is_map(input_values) -> Map.values(input_values)
      true -> raise ArgumentError, "Input must be a list or map of responses"
    end
    
    # Filter out nil or empty responses
    valid_responses = Enum.filter(responses, fn
      nil -> false
      "" -> false
      _ -> true
    end)
    
    # Handle cases based on number of valid responses
    cond do
      # No valid responses
      Enum.empty?(valid_responses) ->
        if operator.output_key, do: %{operator.output_key => nil}, else: nil
        
      # Only one valid response
      length(valid_responses) == 1 ->
        only_response = List.first(valid_responses)
        if operator.output_key, do: %{operator.output_key => only_response}, else: only_response
        
      # Multiple valid responses - process with the model
      true ->
        # Create prompt based on the mode
        prompt = case operator.mode do
          :select -> create_selection_prompt(valid_responses, operator.criteria)
          :synthesize -> create_synthesis_prompt(valid_responses, operator.criteria)
        end
        
        # Prepare model arguments
        model_args = Map.merge(operator.model_kwargs, %{
          messages: [
            %{role: "user", content: prompt}
          ]
        })
        
        # Execute the model
        case operator.model.(model_args) do
          {:ok, response} ->
            # Process the response based on the mode
            result = case operator.mode do
              :select ->
                # Extract the response number
                case Regex.run(~r/(\d+)/, response.content) do
                  [_, index_str] ->
                    # Convert to integer and handle out of bounds
                    index = String.to_integer(index_str)
                    if index > 0 && index <= length(valid_responses) do
                      Enum.at(valid_responses, index - 1)
                    else
                      # If invalid index, return the first response
                      List.first(valid_responses)
                    end
                  _ ->
                    # If no number found, return the first response
                    List.first(valid_responses)
                end
              
              :synthesize ->
                # Return the synthesized response
                response.content
            end
            
            # Return the result in the appropriate format
            if operator.output_key do
              %{operator.output_key => result}
            else
              result
            end
            
          {:error, reason} ->
            # In case of error, return the first response
            fallback = List.first(valid_responses)
            result = if operator.output_key, do: %{operator.output_key => fallback}, else: fallback
            
            # Log the error
            require Logger
            Logger.error("SynthesisJudgeOperator execution failed: #{inspect(reason)}")
            result
        end
    end
  end
end
