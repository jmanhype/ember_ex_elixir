defmodule EmberEx.Operators.BranchOperator do
  @moduledoc """
  A conditional operator that selects between two execution paths.
  
  The BranchOperator evaluates a predicate function on the input and routes
  execution to either the 'true_branch' or 'false_branch' operator based on the result.
  This enables conditional logic within operator pipelines.
  """
  
  use EmberEx.Operators.BaseOperator
  
  @typedoc "Predicate function type"
  @type predicate_fn :: (map() -> boolean())
  
  @typedoc "BranchOperator struct type"
  @type t :: %__MODULE__{
    predicate: predicate_fn(),
    true_branch: EmberEx.Operators.Operator.t(),
    false_branch: EmberEx.Operators.Operator.t()
  }
  
  defstruct [:predicate, :true_branch, :false_branch]
  
  @doc """
  Create a new BranchOperator with the given predicate and branches.
  
  ## Parameters
  
  - predicate: A function that takes the input and returns a boolean
  - true_branch: The operator to execute if the predicate returns true
  - false_branch: The operator to execute if the predicate returns false
  
  ## Returns
  
  A new BranchOperator struct
  
  ## Examples
  
      iex> is_long = fn input -> String.length(input.text) > 100 end
      iex> branch = EmberEx.Operators.BranchOperator.new(
      ...>   is_long,
      ...>   summarize_operator,
      ...>   identity_operator
      ...> )
  """
  @spec new(predicate_fn(), EmberEx.Operators.Operator.t(), EmberEx.Operators.Operator.t()) :: t()
  def new(predicate, true_branch, false_branch) do
    %__MODULE__{
      predicate: predicate,
      true_branch: true_branch,
      false_branch: false_branch
    }
  end
  
  @doc """
  Process inputs by evaluating the predicate and routing to the appropriate branch.
  
  ## Parameters
  
  - operator: The BranchOperator struct
  - inputs: A map of input values
  
  ## Returns
  
  The output from either the true_branch or false_branch operator
  """
  @impl true
  def forward(operator, inputs) do
    # Evaluate the predicate on the inputs
    branch = if operator.predicate.(inputs) do
      operator.true_branch
    else
      operator.false_branch
    end
    
    # Execute the selected branch
    EmberEx.Operators.Operator.call(branch, inputs)
  end
  
  @doc """
  Get the specification for this operator.
  
  The BranchOperator's specification is derived from the common parts of
  both branch operators' specifications.
  
  ## Returns
  
  The combined specification for this operator
  """
  @spec specification() :: any()
  def specification do
    # In a real implementation, we would merge the specifications
    # of the true_branch and false_branch operators
    nil
  end
end
