defmodule EmberEx.Specifications.BaseSpecification do
  @moduledoc """
  Base implementation for specifications in Ember.
  
  This module provides a base implementation for the Specification protocol,
  handling common functionality like validation and prompt rendering.
  """
  
  require Logger
  
  defmacro __using__(opts) do
    quote do
      @behaviour EmberEx.Specifications.BaseSpecification
      
      defimpl EmberEx.Specifications.Specification do
        def validate_input(spec, input) do
          # Convert struct to map if needed
          input_map = if is_struct(input), do: Map.from_struct(input), else: input
          
          # Get the input model from the specification
          input_model = spec.input_model
          
          if input_model do
            # Validate using the input model
            case validate_with_model(input_map, input_model) do
              {:ok, validated} -> {:ok, validated}
              {:error, reason} -> {:error, reason}
            end
          else
            # No validation needed
            {:ok, input_map}
          end
        end
        
        def validate_output(spec, output) do
          # Convert struct to map if needed
          output_map = if is_struct(output), do: Map.from_struct(output), else: output
          
          # Get the output model from the specification
          output_model = spec.structured_output
          
          if output_model do
            # Validate using the output model
            case validate_with_model(output_map, output_model) do
              {:ok, validated} -> {:ok, validated}
              {:error, reason} -> {:error, reason}
            end
          else
            # No validation needed
            {:ok, output_map}
          end
        end
        
        def render_prompt(spec, inputs) do
          # Convert struct to map if needed
          input_map = if is_struct(inputs), do: Map.from_struct(inputs), else: inputs
          
          cond do
            # If we have a prompt template, use it
            spec.prompt_template != nil ->
              try do
                # Replace placeholders in the template
                Enum.reduce(input_map, spec.prompt_template, fn {key, value}, template ->
                  String.replace(template, "{#{key}}", to_string(value))
                end)
              rescue
                e -> 
                  Logger.error("Error rendering prompt: #{inspect(e)}")
                  raise "Error rendering prompt: #{inspect(e)}"
              end
              
            # If we have an input model but no template, concatenate required fields
            spec.input_model != nil ->
              # Get required fields and join their values
              required_fields = get_required_fields(spec.input_model)
              Enum.map_join(required_fields, "\n", fn field ->
                Map.get(input_map, field, "")
              end)
              
            # No template or model
            true ->
              raise "No prompt_template or input_model defined for rendering prompt."
          end
        end
        
        def input_schema(spec) do
          if spec.input_model do
            # Generate schema from model
            %{}
          else
            %{}
          end
        end
        
        def output_schema(spec) do
          if spec.structured_output do
            # Generate schema from model
            %{}
          else
            %{}
          end
        end
        
        # Helper function to validate data against a model
        defp validate_with_model(data, model) do
          # This is a placeholder - actual implementation would depend on
          # the validation library used (e.g., Ecto.Changeset)
          {:ok, data}
        end
        
        # Helper function to get required fields from a model
        defp get_required_fields(model) do
          # This is a placeholder - actual implementation would depend on
          # how models are defined
          []
        end
      end
      
      # Define struct fields with defaults from options
      defstruct prompt_template: Keyword.get(unquote(opts), :prompt_template),
                structured_output: Keyword.get(unquote(opts), :structured_output),
                input_model: Keyword.get(unquote(opts), :input_model),
                check_all_placeholders: Keyword.get(unquote(opts), :check_all_placeholders, true)
    end
  end
  
  @doc """
  Validate that the specification is well-formed.
  
  This callback is called when a specification is created to ensure
  that it is valid (e.g., all required placeholders are present).
  
  ## Parameters
  
  - spec: The specification struct
  
  ## Returns
  
  `:ok` if the specification is valid, or
  `{:error, reason}` if the specification is invalid
  """
  @callback validate(spec :: struct()) :: :ok | {:error, term()}
end
