defprotocol EmberEx.Specifications.Specification do
  @moduledoc """
  The Specification protocol defines input/output validation for operators.
  
  This protocol separates input/output contracts from implementation logic,
  following the Specification Pattern from the original Ember framework.
  
  Specifications serve as the contract between operators and their inputs/outputs,
  ensuring type safety and proper validation throughout the execution pipeline.
  """
  
  @doc """
  Validate input against the specification.
  
  ## Parameters
  
  - spec: The specification struct
  - input: A map or struct of input values to validate
  
  ## Returns
  
  `{:ok, validated_input}` if validation succeeds, or
  `{:error, reason}` if validation fails
  """
  @spec validate_input(t(), map() | struct()) :: {:ok, map() | struct()} | {:error, term()}
  def validate_input(spec, input)
  
  @doc """
  Validate output against the specification.
  
  ## Parameters
  
  - spec: The specification struct
  - output: A map or struct of output values to validate
  
  ## Returns
  
  `{:ok, validated_output}` if validation succeeds, or
  `{:error, reason}` if validation fails
  """
  @spec validate_output(t(), map() | struct()) :: {:ok, map() | struct()} | {:error, term()}
  def validate_output(spec, output)
  
  @doc """
  Render a prompt using the specification's template and provided inputs.
  
  ## Parameters
  
  - spec: The specification struct
  - inputs: A map or struct of input values
  
  ## Returns
  
  The rendered prompt string
  
  ## Raises
  
  - RuntimeError: If prompt rendering fails (e.g., missing placeholders)
  """
  @spec render_prompt(t(), map() | struct()) :: String.t()
  def render_prompt(spec, inputs)
  
  @doc """
  Get the JSON schema for the input model.
  
  ## Parameters
  
  - spec: The specification struct
  
  ## Returns
  
  A map representing the JSON schema for the input model
  """
  @spec input_schema(t()) :: map()
  def input_schema(spec)
  
  @doc """
  Get the JSON schema for the output model.
  
  ## Parameters
  
  - spec: The specification struct
  
  ## Returns
  
  A map representing the JSON schema for the output model
  """
  @spec output_schema(t()) :: map()
  def output_schema(spec)
end

defmodule EmberEx.Specifications do
  @moduledoc """
  Utility functions for working with specifications.
  
  This module provides helper functions for validating inputs and outputs
  using the Specification protocol, as well as rendering prompts and
  working with schemas.
  """
  
  require Logger
  
  @doc """
  Validate input using the specification.
  
  This function raises an error if validation fails.
  
  ## Parameters
  
  - operator: The operator with a specification
  - inputs: A map or struct of input values to validate
  
  ## Returns
  
  The validated input map or struct
  
  ## Raises
  
  - RuntimeError: If validation fails
  """
  @spec validate_input(any(), map() | struct()) :: map() | struct()
  def validate_input(operator, inputs) do
    spec = EmberEx.Operators.Operator.specification(operator)
    
    case EmberEx.Specifications.Specification.validate_input(spec, inputs) do
      {:ok, validated} -> validated
      {:error, reason} -> 
        Logger.error("Input validation error: #{inspect(reason)}")
        raise "Input validation error: #{inspect(reason)}"
    end
  end
  
  @doc """
  Validate output using the specification.
  
  This function raises an error if validation fails.
  
  ## Parameters
  
  - operator: The operator with a specification
  - outputs: A map or struct of output values to validate
  
  ## Returns
  
  The validated output map or struct
  
  ## Raises
  
  - RuntimeError: If validation fails
  """
  @spec validate_output(any(), map() | struct()) :: map() | struct()
  def validate_output(operator, outputs) do
    spec = EmberEx.Operators.Operator.specification(operator)
    
    case EmberEx.Specifications.Specification.validate_output(spec, outputs) do
      {:ok, validated} -> validated
      {:error, reason} -> 
        Logger.error("Output validation error: #{inspect(reason)}")
        raise "Output validation error: #{inspect(reason)}"
    end
  end
  
  @doc """
  Render a prompt using the specification's template and provided inputs.
  
  ## Parameters
  
  - operator: The operator with a specification
  - inputs: A map or struct of input values
  
  ## Returns
  
  The rendered prompt string
  
  ## Raises
  
  - RuntimeError: If prompt rendering fails (e.g., missing placeholders)
  """
  @spec render_prompt(any(), map() | struct()) :: String.t()
  def render_prompt(operator, inputs) do
    spec = EmberEx.Operators.Operator.specification(operator)
    EmberEx.Specifications.Specification.render_prompt(spec, inputs)
  end
  
  @doc """
  Create a basic specification with the given prompt template and models.
  
  ## Parameters
  
  - prompt_template: The prompt template string with placeholders
  - input_model: The input model module or schema
  - output_model: The output model module or schema
  - opts: Additional options
  
  ## Returns
  
  A new specification struct
  """
  @spec create(String.t(), module() | map(), module() | map(), keyword()) :: struct()
  def create(_prompt_template, _input_model, _output_model, _opts \\ []) do
    # This is a placeholder - actual implementation would depend on
    # the concrete specification implementation
    %{}
  end
end
