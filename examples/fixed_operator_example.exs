#!/usr/bin/env elixir
# Fixed LLMOperator example with Ecto Schemas for EmberEx
#
# This example shows how to use the LLMOperator with correct Ecto schema definitions
# and proper adapter between the model callable and operator system.

Mix.install([
  {:ember_ex, path: Path.expand("../", __DIR__)}
])

defmodule EmberEx.Examples.FixedOperatorExample do
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
    IO.puts("=== EmberEx Fixed Operator Example ===\n")
    
    # Set up the OpenAI API key
    setup_api_key()
    
    # Run the fixed example
    fixed_llm_example()
    
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
      
      # Return the response in the format LLMOperator expects
      # (it expects a raw value, not wrapped in {:ok, _})
      %{result: response.content}
    end
  end
  
  @doc """
  Example of a basic LLM operator with proper Ecto schemas and model adapter
  """
  def fixed_llm_example do
    IO.puts("\n=== Fixed LLM Operator Example ===")
    
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
EmberEx.Examples.FixedOperatorExample.run()
