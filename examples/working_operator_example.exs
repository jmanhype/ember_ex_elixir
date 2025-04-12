#!/usr/bin/env elixir
# Working LLMOperator example with Ecto Schemas for EmberEx
#
# This example shows how to use the LLMOperator with correct Ecto schema definitions
# and proper adapter between the model callable and operator system.

Mix.install([
  {:ember_ex, path: Path.expand("../", __DIR__)}
])

defmodule EmberEx.Examples.WorkingOperatorExample do
  @moduledoc """
  Example demonstrating proper use of EmberEx operators with Ecto schemas and model adapters.
  """
  
  alias EmberEx.Operators.{LLMOperator, MapOperator, SequenceOperator}
  
  # Define a schema for the poem input
  defmodule PoemInput do
    use Ecto.Schema
    import Ecto.Changeset
    
    @primary_key false
    embedded_schema do
      field :topic, :string
    end
    
    def changeset(schema, params) do
      schema
      |> cast(params, [:topic])
      |> validate_required([:topic])
    end
  end
  
  # Define a schema for the poem output
  defmodule PoemOutput do
    use Ecto.Schema
    import Ecto.Changeset
    
    @primary_key false
    embedded_schema do
      field :poem, :string
    end
    
    def changeset(schema, params) do
      schema
      |> cast(params, [:poem])
      |> validate_required([:poem])
    end
  end
  
  @doc """
  Run the example
  """
  def run do
    IO.puts("=== EmberEx Working Operator Example ===\n")
    
    # Set up the OpenAI API key
    setup_api_key()
    
    # Run the working example
    working_llm_example()
    
    :ok
  end
  
  @doc """
  Set up the OpenAI API key
  """
  def setup_api_key do
    IO.puts("Setting up OpenAI API key...")
    
    # Set the API key in the configuration
    api_key = System.get_env("OPENAI_API_KEY")
    if !api_key do
      IO.puts("Error: OPENAI_API_KEY environment variable not set.")
      System.halt(1)
    end
    
    EmberEx.Config.put_in([:models, :providers, :openai, :api_key], api_key)
    EmberEx.Config.load_from_env()
    
    IO.puts("Configuration complete.\n")
  end
  
  @doc """
  Create a model adapter that bridges between LLMOperator and EmberEx.Models
  
  This adapter takes the complex input that LLMOperator provides (with messages, etc.)
  and converts it to the simple string that EmberEx.Models.model expects.
  
  It also ensures the return value matches the format expected by the LLMOperator.
  """
  def create_model_adapter(model_name, opts \\ []) do
    # Create the base model callable
    base_model = EmberEx.Models.model(model_name, opts)
    
    # Create an adapter function that extracts the prompt from model_args
    fn model_args ->
      # Extract the prompt from the messages
      prompt = case model_args do
        %{messages: messages} when is_list(messages) ->
          # Extract content from the first user message
          user_message = Enum.find(messages, fn msg -> 
            is_map(msg) && Map.get(msg, :role) == "user" 
          end)
          
          if user_message, do: Map.get(user_message, :content), else: ""
          
        string when is_binary(string) ->
          # If it's just a string, use it directly
          string
          
        _ ->
          # Default case - try to extract a prompt
          ""
      end
      
      # Call the base model with the extracted prompt
      response = base_model.(prompt)
      
      # Extract response schema from model_args
      schema = Map.get(model_args, :response_model, %{})
      
      # Create an Ecto changeset for the PoemOutput schema (or any provided schema)
      # This simulates what Instructor would do for structured outputs
      changeset = case schema do
        PoemOutput ->
          # Create a new struct and generate a changeset
          %PoemOutput{}
          |> PoemOutput.changeset(%{poem: response.content})
        
        _ ->
          # For any other schema format, create a generic map
          # with schema-compliant keys
          required_fields = case schema do
            %{"required" => fields} when is_list(fields) -> fields
            _ -> []
          end
          
          # Create a map with the required fields
          # The operator expects the content to be in the field specified in the required list
          result = cond do
            # If "poem" is in the required fields, use that
            "poem" in required_fields ->
              %{"poem" => response.content}
              
            # Default to the first required field or a generic "result"
            length(required_fields) > 0 ->
              %{List.first(required_fields) => response.content}
              
            # Fallback
            true ->
              %{"result" => response.content}
          end
          
          # Return a map that matches what the operator expects
          result
      end
      
      # Return the data in the format LLMOperator expects - a tuple with :ok and the data
      {:ok, changeset}
    end
  end
  
  @doc """
  Example of a basic LLM operator with proper Ecto schemas and model adapter
  """
  def working_llm_example do
    IO.puts("\n=== Working LLM Operator Example ===")
    
    # Create a specification using the Ecto schemas
    spec = EmberEx.Specifications.EctoSpecification.new(
      "Generate a short poem about {topic}.",
      PoemInput,
      PoemOutput
    )
    
    # Create the model adapter that bridges between LLMOperator and EmberEx.Models
    model_adapter = create_model_adapter("gpt-3.5-turbo", [temperature: 0.7])
    
    # Create the LLM operator with our adapter
    llm_op = LLMOperator.new(spec, model_adapter)
    
    # Call the operator
    IO.puts("Calling LLM operator with input...")
    result = EmberEx.Operators.Operator.call(llm_op, %{topic: "functional programming"})
    
    # Display the result
    IO.puts("\nResult:")
    IO.puts("------------------------------")
    IO.puts(result.poem)
    IO.puts("------------------------------\n")
  end
end

# Run the example
EmberEx.Examples.WorkingOperatorExample.run()
