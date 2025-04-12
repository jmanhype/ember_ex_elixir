defmodule EmberEx.Operators.MostCommonOperator do
  @moduledoc """
  Selects the most common element from a list of values.
  
  This operator is useful for selecting the most frequently occurring element
  from a collection, such as making decisions based on multiple responses.
  """
  
  use EmberEx.Operators.BaseOperator
  
  @typedoc "MostCommonOperator struct type"
  @type t :: %__MODULE__{
    input_key: atom() | String.t() | nil,
    output_key: atom() | String.t() | nil,
    count_key: atom() | String.t() | nil,
    normalize_fn: (any() -> any()) | nil
  }
  
  defstruct [:input_key, :output_key, :count_key, :normalize_fn]
  
  @doc """
  Create a new MostCommonOperator.
  
  ## Parameters
  
  - input_key: The key to extract from the input map (nil to use the entire input)
  - output_key: The key to use for the output map (nil to return the raw result)
  - count_key: The key to use for storing occurrence counts (nil to not include counts)
  - normalize_fn: Optional function to normalize inputs before counting (nil to use as-is)
  
  ## Returns
  
  A new MostCommonOperator struct
  
  ## Examples
  
      iex> op = EmberEx.Operators.MostCommonOperator.new(:values, :most_common, :counts)
      iex> EmberEx.Operators.Operator.call(op, %{values: ["a", "b", "a", "c", "a", "b"]})
      %{most_common: "a", counts: %{"a" => 3, "b" => 2, "c" => 1}}
  """
  @spec new(
    atom() | String.t() | nil,
    atom() | String.t() | nil,
    atom() | String.t() | nil,
    (any() -> any()) | nil
  ) :: t()
  def new(input_key \\ nil, output_key \\ nil, count_key \\ nil, normalize_fn \\ nil) do
    %__MODULE__{
      input_key: input_key,
      output_key: output_key,
      count_key: count_key,
      normalize_fn: normalize_fn
    }
  end
  
  @doc """
  Create a new MostCommonOperator with a name.
  
  ## Parameters
  
  - name: The name of the operator
  - input_key: The key to extract from the input map (nil to use the entire input)
  - output_key: The key to use for the output map (nil to return the raw result)
  - count_key: The key to use for storing occurrence counts (nil to not include counts)
  - normalize_fn: Optional function to normalize inputs before counting (nil to use as-is)
  
  ## Returns
  
  A new MostCommonOperator struct
  
  ## Examples
  
      iex> normalize_fn = fn s -> String.downcase(s) end
      iex> op = EmberEx.Operators.MostCommonOperator.new_with_name(
      ...>   "text_consensus",
      ...>   :values,
      ...>   :consensus,
      ...>   :distribution,
      ...>   normalize_fn
      ...> )
  """
  @spec new_with_name(
    String.t(),
    atom() | String.t() | nil,
    atom() | String.t() | nil,
    atom() | String.t() | nil,
    (any() -> any()) | nil
  ) :: t()
  def new_with_name(name, input_key \\ nil, output_key \\ nil, count_key \\ nil, normalize_fn \\ nil) do
    %__MODULE__{
      input_key: input_key,
      output_key: output_key,
      count_key: count_key,
      normalize_fn: normalize_fn
    }
    |> EmberEx.Operators.BaseOperator.set_name(name)
  end
  
  @doc """
  Find the most common element in a list.
  
  ## Parameters
  
  - operator: The MostCommonOperator struct
  - inputs: A map of input values or a direct input value
  
  ## Returns
  
  The most common element and optionally the count of occurrences
  
  ## Examples
  
      iex> op = EmberEx.Operators.MostCommonOperator.new()
      iex> EmberEx.Operators.Operator.call(op, ["a", "b", "a", "c", "a", "b"])
      "a"
      
      iex> op = EmberEx.Operators.MostCommonOperator.new(:values, :most_common, :counts)
      iex> EmberEx.Operators.Operator.call(op, %{values: [1, 2, 1, 3, 1, 2]})
      %{most_common: 1, counts: %{1 => 3, 2 => 2, 3 => 1}}
  """
  @impl true
  def forward(%__MODULE__{} = operator, inputs) do
    # Extract the input values
    input_values = if operator.input_key do
      Map.get(inputs, operator.input_key)
    else
      inputs
    end
    
    unless is_list(input_values) do
      raise ArgumentError, "Input values must be a list"
    end
    
    # Normalize values if a normalization function is provided
    normalized_values = if operator.normalize_fn do
      Enum.map(input_values, operator.normalize_fn)
    else
      input_values
    end
    
    # Count occurrences of each value
    counts = Enum.reduce(normalized_values, %{}, fn value, acc ->
      Map.update(acc, value, 1, &(&1 + 1))
    end)
    
    # Find the most common value
    {most_common, _} = counts
    |> Enum.max_by(fn {_, count} -> count end, fn -> {nil, 0} end)
    
    # If there's a normalization function, we need to find an original value
    # that corresponds to the most common normalized value
    result = if operator.normalize_fn && most_common != nil do
      # Find the first original value that normalizes to the most common value
      Enum.zip(input_values, normalized_values)
      |> Enum.find(fn {_, normalized} -> normalized == most_common end)
      |> elem(0)
    else
      most_common
    end
    
    # Return the result in the appropriate format
    cond do
      operator.output_key && operator.count_key ->
        %{
          operator.output_key => result,
          operator.count_key => counts
        }
      operator.output_key ->
        %{operator.output_key => result}
      true ->
        result
    end
  end
end
