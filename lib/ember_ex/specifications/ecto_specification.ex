defmodule EmberEx.Specifications.EctoSpecification do
  @moduledoc """
  A specification implementation that uses Ecto schemas for validation.
  
  This module provides a concrete implementation of the Specification protocol
  using Ecto schemas for input and output validation.
  """
  
  use EmberEx.Specifications.BaseSpecification
  
  require Logger
  
  # Define struct type
  @type t :: %__MODULE__{
    prompt_template: String.t() | nil,
    input_model: module() | nil,
    structured_output: module() | nil,
    check_all_placeholders: boolean()
  }
  
  @doc """
  Create a new EctoSpecification with the given parameters.
  
  ## Parameters
  
  - prompt_template: The prompt template string with placeholders
  - input_model: The Ecto schema module for input validation
  - output_model: The Ecto schema module for output validation
  - opts: Additional options
    - check_all_placeholders: Whether to check that all required fields are in the template
  
  ## Returns
  
  A new EctoSpecification struct
  
  ## Examples
  
      iex> spec = EmberEx.Specifications.EctoSpecification.new(
      ...>   "Hello, {name}!",
      ...>   MyApp.InputSchema,
      ...>   MyApp.OutputSchema
      ...> )
  """
  @spec new(String.t() | nil, module() | nil, module() | nil, keyword()) :: %__MODULE__{}
  def new(prompt_template \\ nil, input_model \\ nil, output_model \\ nil, opts \\ []) do
    spec = %__MODULE__{
      prompt_template: prompt_template,
      input_model: input_model,
      structured_output: output_model,
      check_all_placeholders: Keyword.get(opts, :check_all_placeholders, true)
    }
    
    # Validate the specification
    case validate(spec) do
      :ok -> spec
      {:error, reason} -> raise "Invalid specification: #{inspect(reason)}"
    end
  end
  
  @doc """
  Validate that the specification is well-formed.
  
  Checks that:
  1. If check_all_placeholders is true and input_model is provided, all required
     fields from the input model are in the prompt template.
  2. The input_model and structured_output are valid Ecto schemas if provided.
  
  ## Parameters
  
  - spec: The specification struct
  
  ## Returns
  
  `:ok` if the specification is valid, or
  `{:error, reason}` if the specification is invalid
  """
  @impl true
  def validate(spec) do
    cond do
      # Check that all required placeholders are in the template
      spec.check_all_placeholders && spec.prompt_template && spec.input_model ->
        required_fields = get_required_fields(spec.input_model)
        missing_fields = Enum.filter(required_fields, fn field ->
          !String.contains?(spec.prompt_template, "{#{field}}")
        end)
        
        if Enum.empty?(missing_fields) do
          :ok
        else
          {:error, "Missing placeholders in prompt_template: #{Enum.join(missing_fields, ", ")}"}
        end
        
      # Check that input_model is a valid Ecto schema if provided
      spec.input_model && !is_ecto_schema?(spec.input_model) ->
        {:error, "Input model must be an Ecto schema"}
        
      # Check that structured_output is a valid Ecto schema if provided
      spec.structured_output && !is_ecto_schema?(spec.structured_output) ->
        {:error, "Output model must be an Ecto schema"}
        
      # All checks passed
      true ->
        :ok
    end
  end
  
  # Private helper functions
  
  # Check if a module is an Ecto schema
  defp is_ecto_schema?(module) do
    Code.ensure_loaded?(module) &&
    function_exported?(module, :__schema__, 1)
  end
  
  # Get required fields from an Ecto schema
  @doc """
  Get required fields from an Ecto schema.
  
  ## Parameters
  
  - schema: The Ecto schema module
  
  ## Returns
  
  A list of field names that are required for this schema
  """
  @spec get_required_fields(module()) :: [atom()]
  defp get_required_fields(schema) do
    # Make sure the schema is loaded
    Code.ensure_loaded?(schema)
    
    # Try to get fields from the schema
    all_fields = try do
      schema.__schema__(:fields)
    rescue
      e ->
        require Logger
        Logger.warning("Could not get fields from schema #{inspect(schema)}: #{Exception.message(e)}")
        []
    end
    
    # Try to determine which fields are required by examining changeset function
    # This is an imperfect heuristic but better than nothing
    try do
      # Get the source code of the changeset function if available
      changeset_source = Code.fetch_docs(schema)
      |> case do
        {:docs_v1, _, _, _, _, _, functions} ->
          # Find the changeset function
          case Enum.find(functions, fn {{name, arity}, _, _, _, _} -> name == :changeset and arity == 2 end) do
            {{:changeset, 2}, _, _, %{source: source}, _} when is_binary(source) -> source
            _ -> nil
          end
        _ -> nil
      end
      
      # If we have the source, look for required fields in validate_required calls
      if changeset_source do
        # Check for validate_required calls
        case Regex.scan(~r/validate_required\(\s*\w+,\s*\[([^\]]+)\]/s, changeset_source) do
          [] -> 
            # No validate_required found, fall back to all fields
            all_fields
          matches ->
            # Extract the fields from validate_required calls
            matches
            |> Enum.map(fn [_, fields_str] -> 
              # Parse the fields list
              fields_str
              |> String.split(",")
              |> Enum.map(&String.trim/1)
              |> Enum.map(fn field ->
                # Convert to atom, removing any quotes
                field
                |> String.replace(~r/[:'"]/,  "")
                |> String.to_atom()
              end)
            end)
            |> List.flatten()
            |> Enum.uniq()
        end
      else
        # No source available, fall back to all fields
        all_fields
      end
    rescue
      _ -> all_fields  # Fall back to all fields if anything goes wrong
    end
  end
end

# Implementation of validate_with_model for Ecto schemas
defimpl EmberEx.Specifications.Specification, for: EmberEx.Specifications.EctoSpecification do
  # Override the default implementation to use Ecto.Changeset
  
  @doc """
  Validate input against the specification.
  """
  @doc """
  Validate input against the specification.
  
  ## Parameters
  
  - spec: The specification struct
  - input: The input data to validate
  
  ## Returns
  
  `{:ok, validated_input}` if validation succeeds, or
  `{:error, errors}` if validation fails
  """
  @spec validate_input(EmberEx.Specifications.EctoSpecification.t(), map()) :: {:ok, struct()} | {:error, map()}
  def validate_input(spec, input) do
    if spec.input_model do
      try do
        validate_with_model(input, spec.input_model)
      rescue
        e ->
          require Logger
          Logger.error("Input validation error: #{Exception.message(e)}")
          {:error, %{validation: "Input validation failed: #{Exception.message(e)}"}}
      end
    else
      {:ok, input}
    end
  end
  
  @doc """
  Validate output against the specification.
  """
  @doc """
  Validate output against the specification.
  
  ## Parameters
  
  - spec: The specification struct
  - output: The output data to validate
  
  ## Returns
  
  `{:ok, validated_output}` if validation succeeds, or
  `{:error, errors}` if validation fails
  """
  @spec validate_output(EmberEx.Specifications.EctoSpecification.t(), map()) :: {:ok, struct()} | {:error, map()}
  def validate_output(spec, output) do
    if spec.structured_output do
      try do
        validate_with_model(output, spec.structured_output)
      rescue
        e ->
          require Logger
          Logger.error("Output validation error: #{Exception.message(e)}")
          {:error, %{validation: "Output validation failed: #{Exception.message(e)}"}}
      end
    else
      {:ok, output}
    end
  end
  
  @doc """
  Render a prompt using the specification's template and provided inputs.
  """
  def render_prompt(spec, inputs) do
    if spec.prompt_template do
      # Replace placeholders in the template with values from inputs
      Enum.reduce(Map.to_list(inputs), spec.prompt_template, fn {key, value}, template ->
        replacement = case value do
          nil -> ""
          v when is_binary(v) -> v
          v when is_atom(v) -> Atom.to_string(v)
          v when is_integer(v) or is_float(v) -> to_string(v)
          v when is_list(v) -> inspect(v)
          _ -> inspect(value)
        end
        String.replace(template, "{#{key}}", replacement)
      end)
    else
      ""
    end
  end
  
  @doc """
  Get the JSON schema for the input model.
  """
  def input_schema(spec) do
    if spec.input_model do
      EmberEx.Specifications.SchemaGenerator.generate_schema(spec.input_model)
    else
      %{}
    end
  end
  
  @doc """
  Get the JSON schema for the output model.
  """
  def output_schema(spec) do
    if spec.structured_output do
      EmberEx.Specifications.SchemaGenerator.generate_schema(spec.structured_output)
    else
      %{}
    end
  end
  
  # Helper function to validate data against an Ecto schema
  @doc """
  Validate data against an Ecto schema model.
  
  ## Parameters
  
  - data: The data to validate
  - model: The Ecto schema module to validate against
  
  ## Returns
  
  `{:ok, validated_data}` if validation succeeds, or
  `{:error, errors}` if validation fails
  """
  @spec validate_with_model(map(), module()) :: {:ok, struct()} | {:error, keyword()}
  defp validate_with_model(data, model) do
    # Ensure the model is loaded
    Code.ensure_loaded?(model)
    
    # Check if model has a changeset function
    unless function_exported?(model, :changeset, 2) do
      raise ArgumentError, "Model #{inspect(model)} does not implement changeset/2 function"
    end
    
    # Attempt to cast and validate the data using the Ecto schema
    changeset = try do
      model.changeset(struct(model, %{}), data)
    rescue
      e ->
        # Log the error for debugging
        require Logger
        Logger.error("Error validating with model #{inspect(model)}: #{Exception.message(e)}")
        
        # Create a fake changeset with errors
        Ecto.Changeset.add_error(
          Ecto.Changeset.change(struct(model, %{})),
          :validation,
          "Failed to validate: #{Exception.message(e)}"
        )
    end
    
    if changeset.valid? do
      # Return the validated data
      {:ok, Ecto.Changeset.apply_changes(changeset)}
    else
      # Return the validation errors
      errors = Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
        Enum.reduce(opts, msg, fn {key, value}, acc ->
          String.replace(acc, "%{#{key}}", to_string(value))
        end)
      end)
      
      {:error, errors}
    end
  end
end
