defimpl EmberEx.Operators.Operator, for: Function do
  @moduledoc """
  Implementation of the Operator protocol for Function types.
  
  This allows plain functions with arity 1 to be used as Operators,
  which is useful for the Mesh transform tests and similar situations
  where we want to wrap operators in functions.
  """

  @doc """
  Call a function with the given input.
  
  This simply invokes the function with the input directly.
  """
  def call(func, input) when is_function(func, 1) do
    func.(input)
  end
  
  @doc """
  Get the specification for a function (always nil).
  
  Functions don't have specifications by default.
  """
  def specification(_), do: nil
  
  @doc """
  Forward an input through a function.
  
  For functions, forward is identical to call.
  """
  def forward(func, input) when is_function(func, 1), do: func.(input)
end
