defmodule EmberEx.Specifications.SchemaGeneratorFix do
  @moduledoc """
  Direct implementation of SchemaGenerator functions with fixes.
  
  This module replaces problematic functions in the original SchemaGenerator.
  """
  
  @doc """
  Generate a JSON schema from an Ecto schema - fixed version.
  """
  def from_ecto(schema_module) do
    # Get all fields from the schema - safely
    fields = try do
      schema_module.__schema__(:fields)
    rescue
      _ -> []
    end
    
    # Get field types - safely
    field_types = Enum.map(fields, fn field ->
      type = try do
        schema_module.__schema__(:type, field)
      rescue
        _ -> :string
      end
      {field, type}
    end)
    
    # Build the schema
    %{
      "type" => "object",
      "properties" => build_properties(field_types),
      "required" => Enum.map(fields, &to_string/1)  # All fields required for simplicity
    }
  end
  
  # Helper function to build properties from field types
  defp build_properties(field_types) do
    Enum.map(field_types, fn {field, type} ->
      {to_string(field), type_to_json_schema(type)}
    end)
    |> Map.new()
  end
  
  # Helper function to convert Ecto types to JSON schema types
  defp type_to_json_schema(type) do
    case type do
      :string -> %{"type" => "string"}
      :integer -> %{"type" => "integer"}
      :float -> %{"type" => "number"}
      :boolean -> %{"type" => "boolean"}
      :map -> %{"type" => "object"}
      :binary -> %{"type" => "string", "format" => "binary"}
      :decimal -> %{"type" => "number"}
      :id -> %{"type" => "integer"}
      :binary_id -> %{"type" => "string", "format" => "uuid"}
      :utc_datetime -> %{"type" => "string", "format" => "date-time"}
      :naive_datetime -> %{"type" => "string", "format" => "date-time"}
      :date -> %{"type" => "string", "format" => "date"}
      :time -> %{"type" => "string", "format" => "time"}
      {:array, subtype} -> 
        %{
          "type" => "array",
          "items" => type_to_json_schema(subtype)
        }
      {:map, _} -> %{"type" => "object"}
      _ -> %{"type" => "string"} # Default to string for unknown types
    end
  end
end
