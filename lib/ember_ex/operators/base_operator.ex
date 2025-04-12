defmodule EmberEx.Operators.BaseOperator do
  @moduledoc """
  Base implementation for operators in Ember.
  
  This module provides a base implementation for the Operator protocol,
  handling common functionality like validation and execution.
  
  It implements a Template Method pattern: call/2 orchestrates execution flow
  while forward/2 provides the specific implementation.
  
  It also provides utility functions for working with operators, such as
  setting names and specifications.
  """
  
  @doc """
  Process inputs and return outputs.
  
  This function implements the core computational logic of the operator.
  It receives validated inputs and should return outputs that will be validated.
  
  ## Parameters
  
  - operator: The operator struct
  - inputs: A map of validated input values
  
  ## Returns
  
  A map of output values to be validated
  """
  @callback forward(operator :: struct(), inputs :: map() | struct()) :: map() | struct()
  
  @doc """
  Macro to use in operator modules.
  
  This sets up the module to implement the Operator protocol
  and provides common functionality.
  
  ## Examples
  
      defmodule MyOperator do
        use EmberEx.Operators.BaseOperator
        
        # Implement required callbacks
        def forward(operator, inputs) do
          # ...
        end
      end
  """
  defmacro __using__(_opts) do
    quote do
      @behaviour EmberEx.Operators.BaseOperator
      
      # Default implementation of the Operator protocol
      defimpl EmberEx.Operators.Operator do
        def call(operator, inputs) do
          # Get the specification for this operator
          spec = spec(operator)
          
          # Validate inputs if a specification is provided
          validated_inputs = 
            if spec do
              case EmberEx.Specifications.Specification.validate_input(spec, inputs) do
                {:ok, validated} -> validated
                {:error, reason} -> raise "Input validation error: #{inspect(reason)}"
              end
            else
              inputs
            end
          
          # Call the forward function with validated inputs
          result = forward(operator, validated_inputs)
          
          # Validate outputs if a specification is provided
          if spec do
            case EmberEx.Specifications.Specification.validate_output(spec, result) do
              {:ok, validated} -> validated
              {:error, reason} -> raise "Output validation error: #{inspect(reason)}"
            end
          else
            result
          end
        end
        
        def specification(operator) do
          spec(operator)
        end
        
        def spec(operator) do
          Map.get(operator, :spec)
        end
        
        def name(operator) do
          Map.get(operator, :name, to_string(operator.__struct__))
        end
        
        def forward(operator, inputs) do
          # Call the module's forward function
          apply(operator.__struct__, :forward, [operator, inputs])
        end
      end
      
      @doc """
      Get the specification for this operator.
      
      ## Returns
      
      The specification for this operator
      """
      @spec specification() :: any()
      def specification do
        # Default implementation returns nil
        nil
      end
      
      defoverridable [specification: 0]
    end
  end
  
  @doc """
  Set the name of an operator.
  
  ## Parameters
  
  - operator: The operator struct
  - name: The name to set
  
  ## Returns
  
  The updated operator struct
  
  ## Examples
  
      iex> operator = MapOperator.new(&String.upcase/1, :text, :uppercase_text)
      iex> operator = EmberEx.Operators.BaseOperator.set_name(operator, "uppercase")
      iex> EmberEx.Operators.Operator.name(operator)
      "uppercase"
  """
  @spec set_name(struct(), String.t()) :: struct()
  def set_name(operator, name) do
    Map.put(operator, :name, name)
  end
  
  @doc """
  Set the specification of an operator.
  
  ## Parameters
  
  - operator: The operator struct
  - spec: The specification to set
  
  ## Returns
  
  The updated operator struct
  
  ## Examples
  
      iex> operator = MapOperator.new(&String.upcase/1, :text, :uppercase_text)
      iex> spec = EctoSpecification.new("Uppercase {text}", Input, Output)
      iex> operator = EmberEx.Operators.BaseOperator.set_spec(operator, spec)
      iex> EmberEx.Operators.Operator.spec(operator) == spec
      true
  """
  @spec set_spec(struct(), any()) :: struct()
  def set_spec(operator, spec) do
    Map.put(operator, :spec, spec)
  end
end
