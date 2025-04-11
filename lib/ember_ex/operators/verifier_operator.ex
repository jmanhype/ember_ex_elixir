defmodule EmberEx.Operators.VerifierOperator do
  @moduledoc """
  Verifies outputs against a set of conditions or criteria.
  
  The VerifierOperator evaluates if outputs from an operator meet specified
  conditions or constraints, returning verification results.
  """
  
  use EmberEx.Operators.BaseOperator
  
  require Logger
  
  @typedoc "VerifierOperator struct type"
  @type t :: %__MODULE__{
    conditions: list(condition()),
    input_key: atom() | String.t() | nil,
    output_key: atom() | String.t() | nil
  }
  
  @typedoc "Condition function type"
  @type condition :: (any() -> boolean() | {:error, String.t()})
  
  defstruct [:conditions, :input_key, :output_key]
  
  @doc """
  Create a new VerifierOperator with a list of conditions.
  
  ## Parameters
  
  - conditions: A list of functions that evaluate to a boolean or an error tuple
  - input_key: The key to extract from the input map (nil to use the entire input)
  - output_key: The key to use for the output map (nil to return the raw verification result)
  
  ## Returns
  
  A new VerifierOperator struct
  
  ## Examples
  
      iex> length_check = fn text -> String.length(text) > 10 end
      iex> no_numbers = fn text -> not String.match?(text, ~r/[0-9]/) end
      iex> verifier = EmberEx.Operators.VerifierOperator.new([length_check, no_numbers], :text, :validation_results)
      iex> EmberEx.Operators.Operator.call(verifier, %{text: "Hello world!"})
      %{validation_results: %{passed: true, results: [true, true]}}
  """
  @spec new(list(condition()), atom() | String.t() | nil, atom() | String.t() | nil) :: t()
  def new(conditions, input_key \\ nil, output_key \\ nil) do
    %__MODULE__{
      conditions: conditions,
      input_key: input_key,
      output_key: output_key
    }
  end
  
  @doc """
  Create a new VerifierOperator with a name and a list of conditions.
  
  ## Parameters
  
  - name: The name of the operator
  - conditions: A list of functions that evaluate to a boolean or an error tuple
  - input_key: The key to extract from the input map (nil to use the entire input)
  - output_key: The key to use for the output map (nil to return the raw verification result)
  
  ## Returns
  
  A new VerifierOperator struct
  
  ## Examples
  
      iex> length_check = fn text -> String.length(text) > 10 end
      iex> no_numbers = fn text -> not String.match?(text, ~r/[0-9]/) end
      iex> verifier = EmberEx.Operators.VerifierOperator.new_with_name("content_verifier", [length_check, no_numbers], :text, :validation_results)
  """
  @spec new_with_name(String.t(), list(condition()), atom() | String.t() | nil, atom() | String.t() | nil) :: t()
  def new_with_name(name, conditions, input_key \\ nil, output_key \\ nil) do
    %__MODULE__{
      conditions: conditions,
      input_key: input_key,
      output_key: output_key
    }
    |> EmberEx.Operators.BaseOperator.set_name(name)
  end
  
  @doc """
  Process inputs and verify them against conditions.
  
  ## Parameters
  
  - operator: The VerifierOperator struct
  - inputs: A map of input values or a direct input value
  
  ## Returns
  
  Verification results as a map or as a raw result
  
  ## Examples
  
      iex> length_check = fn text -> String.length(text) > 10 end
      iex> verifier = EmberEx.Operators.VerifierOperator.new([length_check], :text, :validation_results)
      iex> EmberEx.Operators.Operator.call(verifier, %{text: "Short"})
      %{validation_results: %{passed: false, results: [false]}}
  """
  @impl true
  def forward(%__MODULE__{} = operator, inputs) do
    # Extract the input value to verify
    input_value = if operator.input_key do
      Map.get(inputs, operator.input_key)
    else
      inputs
    end
    
    # Apply each condition to the input
    results = Enum.map(operator.conditions, fn condition ->
      try do
        condition.(input_value)
      rescue
        e ->
          Logger.error("Error in verification condition: #{inspect(e)}")
          {:error, "Verification condition error: #{inspect(e)}"}
      end
    end)
    
    # Determine overall pass/fail status
    passed = Enum.all?(results, fn
      true -> true
      false -> false
      {:error, _} -> false
    end)
    
    # Prepare the verification result
    verification_result = %{
      passed: passed,
      results: results
    }
    
    # Return the result in the appropriate format
    if operator.output_key do
      %{operator.output_key => verification_result}
    else
      verification_result
    end
  end
  
  @doc """
  Create a verification condition that checks if a value passes a predicate.
  
  ## Parameters
  
  - predicate: A function that takes a value and returns a boolean
  - error_message: The error message to return if the predicate fails
  
  ## Returns
  
  A verification condition function
  
  ## Examples
  
      iex> is_string = EmberEx.Operators.VerifierOperator.condition(
      ...>   fn value -> is_binary(value) end,
      ...>   "Value must be a string"
      ...> )
      iex> is_string.("Hello")
      true
      iex> is_string.(123)
      {:error, "Value must be a string"}
  """
  @spec condition((any() -> boolean()), String.t()) :: condition()
  def condition(predicate, error_message) do
    fn value ->
      if predicate.(value) do
        true
      else
        {:error, error_message}
      end
    end
  end
  
  @doc """
  Create a verification condition that checks if a value is not nil or empty.
  
  ## Parameters
  
  - error_message: The error message to return if the value is nil or empty
  
  ## Returns
  
  A verification condition function
  
  ## Examples
  
      iex> not_empty = EmberEx.Operators.VerifierOperator.not_empty("Value cannot be empty")
      iex> not_empty.("Hello")
      true
      iex> not_empty.("")
      {:error, "Value cannot be empty"}
      iex> not_empty.(nil)
      {:error, "Value cannot be empty"}
  """
  @spec not_empty(String.t()) :: condition()
  def not_empty(error_message \\ "Value cannot be empty or nil") do
    condition(fn
      nil -> false
      "" -> false
      [] -> false
      %{} -> false
      _ -> true
    end, error_message)
  end
  
  @doc """
  Create a verification condition that checks if a value matches a regex pattern.
  
  ## Parameters
  
  - pattern: The regex pattern to match against
  - error_message: The error message to return if the value doesn't match
  
  ## Returns
  
  A verification condition function
  
  ## Examples
  
      iex> email_pattern = ~r/^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$/
      iex> is_email = EmberEx.Operators.VerifierOperator.matches_pattern(email_pattern, "Invalid email format")
      iex> is_email.("user@example.com")
      true
      iex> is_email.("not-an-email")
      {:error, "Invalid email format"}
  """
  @spec matches_pattern(Regex.t(), String.t()) :: condition()
  def matches_pattern(pattern, error_message) do
    condition(fn
      value when is_binary(value) -> String.match?(value, pattern)
      _ -> false
    end, error_message)
  end
  
  @doc """
  Create a verification condition that applies a list of conditions and requires all to pass.
  
  ## Parameters
  
  - conditions: A list of condition functions
  - error_message: The error message to return if any condition fails
  
  ## Returns
  
  A verification condition function
  
  ## Examples
  
      iex> not_empty = EmberEx.Operators.VerifierOperator.not_empty("Value cannot be empty")
      iex> is_string = EmberEx.Operators.VerifierOperator.condition(fn v -> is_binary(v) end, "Must be a string")
      iex> all_conditions = EmberEx.Operators.VerifierOperator.all([not_empty, is_string], "Failed validation")
      iex> all_conditions.("Hello")
      true
      iex> all_conditions.(nil)
      {:error, "Failed validation"}
  """
  @spec all(list(condition()), String.t()) :: condition()
  def all(conditions, error_message) do
    fn value ->
      results = Enum.map(conditions, fn condition -> condition.(value) end)
      
      if Enum.all?(results, fn result -> result == true end) do
        true
      else
        {:error, error_message}
      end
    end
  end
end
