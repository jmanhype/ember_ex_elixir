defprotocol EmberEx.Operators.Operator do
  @moduledoc """
  The Operator protocol defines the interface for all computational operators in Ember.
  
  Operators are the fundamental computational units in Ember, transforming inputs to outputs.
  They are designed to be composable, with clear input/output contracts defined by specifications.
  
  Architectural Philosophy:
  - Pure Functions: Operators are stateless, deterministic transformations from input to output
  - Strong Type Safety: Validation ensures specification correctness
  - Composition First: Designed specifically for transparent composition at any scale
  - Explicit Interface: Clear input/output contracts enforced through specifications
  """
  
  @doc """
  Execute the operator with the given inputs.
  
  This function handles the complete lifecycle of an operator invocation:
  1. Input Resolution: Determines the input format and normalizes it
  2. Input Validation: Ensures inputs conform to the specification
  3. Computation: Delegates to forward/2 for the core logic
  4. Output Validation: Ensures results conform to the specification
  5. Error Handling: Catches and wraps all execution errors
  
  ## Parameters
  
  - operator: The operator to execute
  - inputs: A map of input values or a struct that matches the input model
  
  ## Returns
  
  A map of output values or a struct that matches the output model
  
  ## Raises
  
  - RuntimeError: If validation fails or execution encounters an error
  """
  @spec call(t(), map() | struct()) :: map() | struct()
  def call(operator, inputs)
  
  @doc """
  Get the specification for this operator.
  
  ## Parameters
  
  - operator: The operator to get the specification for
  
  ## Returns
  
  The specification for this operator
  """
  @spec specification(t()) :: any()
  def specification(operator)
  
  @doc """
  Implements the core computational logic of the operator.
  
  This function represents the heart of the operator, defining the specific computational
  logic while inheriting the standardized validation and execution flow from the protocol.
  
  The forward function is guaranteed to receive validated inputs that conform
  to the operator's input model specification, removing the need for defensive
  validation code within implementations.
  
  ## Parameters
  
  - operator: The operator instance
  - inputs: Validated input data guaranteed to conform to the operator's input model specification
  
  ## Returns
  
  The computation result, which will be automatically validated against the operator's output model specification
  
  ## Raises
  
  - RuntimeError: For any errors during computation
  """
  @spec forward(t(), map() | struct()) :: map() | struct()
  def forward(operator, inputs)
end

# BaseOperator module is defined in lib/ember_ex/operators/base_operator.ex
