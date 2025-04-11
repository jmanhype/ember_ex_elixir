defmodule EmberEx.Specifications.SchemaGenerator do
  @moduledoc """
  Utilities for generating JSON schemas from Ecto schemas.
  
  This module provides functions to convert Ecto schemas to JSON schemas
  for use with Instructor and other schema validation systems.
  """
  
  @doc """
  Generate a JSON schema from a module (either Ecto schema or struct).
  
  This is the main entry point for generating schemas and will automatically
  determine the appropriate method to use based on the module type.
  
  ## Parameters
  
  - module: The module to generate a schema for
  
  ## Returns
  
  A map representing the JSON schema
  
  ## Examples
  
      iex> schema = EmberEx.Specifications.SchemaGenerator.generate_schema(MyApp.User)
      %{
        "type" => "object",
        "properties" => %{
          "name" => %{"type" => "string"},
          "age" => %{"type" => "integer"}
        },
        "required" => ["name"]
      }
  """
  @spec generate_schema(module() | map()) :: map()
  def generate_schema(module) when is_atom(module) do
    cond do
      # Check if it's an Ecto schema
      function_exported?(module, :__schema__, 1) ->
        from_ecto(module)
        
      # Check if it's a struct
      function_exported?(module, :__struct__, 0) ->
        from_struct(module)
        
      # Fall back to a simple map
      true ->
        %{
          "type" => "object",
          "properties" => %{},
          "required" => []
        }
    end
  end
  
  # Handle maps directly
  def generate_schema(%{} = map) do
    # Infer types from the map values
    properties = Enum.map(map, fn {key, value} ->
      {to_string(key), infer_type(value)}
    end)
    |> Map.new()
    
    %{
      "type" => "object",
      "properties" => properties,
      "required" => []
    }
  end
  
  @doc """
  Generate a JSON schema from an Ecto schema.
  
  ## Parameters
  
  - schema_module: The Ecto schema module to generate a schema for
  
  ## Returns
  
  A map representing the JSON schema
  
  ## Examples
  
      iex> schema = EmberEx.Specifications.SchemaGenerator.from_ecto(MyApp.User)
      %{
        "type" => "object",
        "properties" => %{
          "name" => %{"type" => "string"},
          "age" => %{"type" => "integer"}
        },
        "required" => ["name"]
      }
  """
  @spec from_ecto(module()) :: map()
  def from_ecto(schema_module) do
    # Get all fields from the schema
    fields = schema_module.__schema__(:fields)
    
    # Get field types
    field_types = Enum.map(fields, fn field ->
      {field, schema_module.__schema__(:type, field)}
    end)
    
    # Get required fields (those without defaults)
    required_fields = get_required_fields(schema_module)
    
    # Build the schema
    %{
      "type" => "object",
      "properties" => build_properties(field_types),
      "required" => Enum.map(required_fields, &to_string/1)
    }
  end
  
  @doc """
  Generate a JSON schema from a struct module.
  
  ## Parameters
  
  - struct_module: The struct module to generate a schema for
  
  ## Returns
  
  A map representing the JSON schema
  
  ## Examples
  
      iex> schema = EmberEx.Specifications.SchemaGenerator.from_struct(MyApp.Config)
      %{
        "type" => "object",
        "properties" => %{
          "api_key" => %{"type" => "string"},
          "timeout" => %{"type" => "integer"}
        },
        "required" => []
      }
  """
  @spec from_struct(module()) :: map()
  def from_struct(struct_module) do
    # Get the struct fields
    fields = struct_module.__struct__()
    |> Map.from_struct()
    |> Map.drop([:__struct__])
    
    # Build the properties
    properties = Enum.map(fields, fn {field, default} ->
      {field, infer_type(default)}
    end)
    |> Map.new()
    
    # Build the schema
    %{
      "type" => "object",
      "properties" => properties,
      "required" => [] # All fields have defaults in a struct
    }
  end
  
  @doc """
  Generate a JSON schema for a simple map with specified types.
  
  ## Parameters
  
  - fields: A map of field names to their types
  - required: A list of required field names
  
  ## Returns
  
  A map representing the JSON schema
  
  ## Examples
  
      iex> schema = EmberEx.Specifications.SchemaGenerator.from_map(
      ...>   %{
      ...>     name: :string,
      ...>     age: :integer,
      ...>     tags: {:array, :string}
      ...>   },
      ...>   [:name]
      ...> )
      %{
        "type" => "object",
        "properties" => %{
          "name" => %{"type" => "string"},
          "age" => %{"type" => "integer"},
          "tags" => %{
            "type" => "array",
            "items" => %{"type" => "string"}
          }
        },
        "required" => ["name"]
      }
  """
  @spec from_map(map(), list()) :: map()
  def from_map(fields, required \\ []) do
    # Build the properties
    properties = Enum.map(fields, fn {field, type} ->
      {field, type_to_json_schema(type)}
    end)
    |> Map.new()
    
    # Build the schema
    %{
      "type" => "object",
      "properties" => properties,
      "required" => Enum.map(required, &to_string/1)
    }
  end
  
  # Helper function to get required fields from an Ecto schema
  defp get_required_fields(schema_module) do
    # Get all fields from the schema
    fields = schema_module.__schema__(:fields)
    
    # Filter to only required fields (those without defaults)
    Enum.filter(fields, fn field ->
      # Check if the field has a default value
      case schema_module.__schema__(:field, field) do
        %{default: nil} -> true
        %{default: _} -> false
        _ -> true
      end
    end)
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
  
  # Helper function to infer type from a value
  defp infer_type(value) do
    cond do
      is_binary(value) -> %{"type" => "string"}
      is_integer(value) -> %{"type" => "integer"}
      is_float(value) -> %{"type" => "number"}
      is_boolean(value) -> %{"type" => "boolean"}
      is_map(value) -> %{"type" => "object"}
      is_list(value) -> 
        # Try to infer type from the first element
        if Enum.empty?(value) do
          %{"type" => "array", "items" => %{"type" => "string"}}
        else
          first = List.first(value)
          %{"type" => "array", "items" => infer_type(first)}
        end
      is_nil(value) -> %{"type" => "null"}
      true -> %{"type" => "string"} # Default to string
    end
  end
end
