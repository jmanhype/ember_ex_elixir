defmodule EmberEx.Operators.EnsembleOperator do
  @moduledoc """
  An operator that runs multiple operators in parallel and combines their outputs.
  
  The EnsembleOperator executes a collection of operators on the same input
  and combines their outputs according to a specified aggregation strategy.
  This enables ensemble methods and multi-path processing.
  """
  
  use EmberEx.Operators.BaseOperator
  
  @typedoc "Aggregation function type"
  @type aggregation_fn :: (list(map()) -> map())
  
  @typedoc "EnsembleOperator struct type"
  @type t :: %__MODULE__{
    operators: list(EmberEx.Operators.Operator.t()),
    aggregation_fn: aggregation_fn()
  }
  
  defstruct [:operators, :aggregation_fn]
  
  @doc """
  Create a new EnsembleOperator with the given operators and aggregation function.
  
  ## Parameters
  
  - operators: A list of operators to execute in parallel
  - aggregation_fn: A function that combines the outputs of all operators
  
  ## Returns
  
  A new EnsembleOperator struct
  
  ## Examples
  
      iex> # Combine outputs by taking the average of 'score' field
      iex> avg_scores = fn outputs ->
      ...>   avg = Enum.reduce(outputs, 0, & &1.score + &2) / length(outputs)
      ...>   %{score: avg}
      ...> end
      iex> ensemble = EmberEx.Operators.EnsembleOperator.new(
      ...>   [model1_op, model2_op, model3_op],
      ...>   avg_scores
      ...> )
  """
  @spec new(list(EmberEx.Operators.Operator.t()), aggregation_fn()) :: t()
  def new(operators, aggregation_fn) do
    %__MODULE__{
      operators: operators,
      aggregation_fn: aggregation_fn
    }
  end
  
  @doc """
  Process inputs by executing all operators in parallel and aggregating results.
  
  ## Parameters
  
  - operator: The EnsembleOperator struct
  - inputs: A map of input values
  
  ## Returns
  
  The aggregated output from all operators
  """
  @impl true
  def forward(operator, inputs) do
    # Execute all operators in parallel
    results = 
      operator.operators
      |> Enum.map(fn op -> 
        Task.async(fn -> EmberEx.Operators.Operator.call(op, inputs) end)
      end)
      |> Enum.map(&Task.await/1)
    
    # Aggregate the results
    operator.aggregation_fn.(results)
  end
  
  @doc """
  Create an EnsembleOperator that merges outputs by taking the union of all fields.
  
  ## Parameters
  
  - operators: A list of operators to execute in parallel
  
  ## Returns
  
  A new EnsembleOperator with a merge aggregation function
  
  ## Examples
  
      iex> ensemble = EmberEx.Operators.EnsembleOperator.merge([op1, op2, op3])
  """
  @spec merge(list(EmberEx.Operators.Operator.t())) :: t()
  def merge(operators) do
    # Define a merge function that combines all fields
    merge_fn = fn outputs ->
      Enum.reduce(outputs, %{}, fn output, acc ->
        Map.merge(acc, output)
      end)
    end
    
    new(operators, merge_fn)
  end
  
  @doc """
  Create an EnsembleOperator that selects the best output based on a scoring function.
  
  ## Parameters
  
  - operators: A list of operators to execute in parallel
  - score_fn: A function that assigns a score to each output (higher is better)
  
  ## Returns
  
  A new EnsembleOperator with a best-selection aggregation function
  
  ## Examples
  
      iex> # Select the output with the highest confidence
      iex> confidence_score = fn output -> output.confidence end
      iex> ensemble = EmberEx.Operators.EnsembleOperator.best([op1, op2, op3], confidence_score)
  """
  @spec best(list(EmberEx.Operators.Operator.t()), (map() -> number())) :: t()
  def best(operators, score_fn) do
    # Define a function that selects the output with the highest score
    best_fn = fn outputs ->
      outputs
      |> Enum.max_by(score_fn)
    end
    
    new(operators, best_fn)
  end
end
