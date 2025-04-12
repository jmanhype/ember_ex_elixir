#!/usr/bin/env elixir
# Simple OpenAI integration example with EmberEx
#
# This example demonstrates a minimal working implementation 
# using properly structured Ecto schemas

Mix.install([
  {:ember_ex, path: Path.expand("../", __DIR__)}
])

defmodule EmberEx.Examples.SimpleOpenAIExample do
  @moduledoc """
  A simplified example showing how to use OpenAI with EmberEx.
  """
  
  alias EmberEx.Operators.LLMOperator
  require Logger
  
  # Define a simple Ecto schema for poem output
  defmodule PoemSchema do
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
    IO.puts("=== EmberEx Simple OpenAI Integration Example ===\n")
    
    # Configure the OpenAI API key
    setup_api_key()
    
    # Create a specification using the Ecto schema
    spec = EmberEx.Specifications.EctoSpecification.new(
      "Generate a short poem about {topic}.",
      nil,  # No input schema for simplicity
      PoemSchema
    )
    
    # Create the model callable
    model = EmberEx.Models.create_model_callable("gpt-3.5-turbo")
    
    # Create the LLM operator
    llm_op = LLMOperator.new(spec, model, %{temperature: 0.7})
    
    # Call the operator
    IO.puts("Calling LLM operator with input...\n")
    result = EmberEx.Operators.Operator.call(llm_op, %{topic: "functional programming"})
    
    # Display the result
    IO.puts("Result:")
    IO.puts("------------------------------")
    # Handle different response formats
    poem_text = cond do
      Map.has_key?(result, :poem) -> result.poem
      Map.has_key?(result, :content) -> result.content
      true -> inspect(result)
    end
    IO.puts(poem_text)
    IO.puts("------------------------------\n")
  end
  
  @doc """
  Set up the OpenAI API key
  """
  def setup_api_key do
    IO.puts("Setting up OpenAI API key...")
    
    # Set the API key in the configuration
    api_key = System.get_env("OPENAI_API_KEY")
    EmberEx.Config.put_in([:models, :providers, :openai, :api_key], api_key)
    
    # Load config from environment variables
    EmberEx.Config.load_from_env()
    
    IO.puts("Configuration complete.\n")
  end
end

# Run the example
if System.get_env("OPENAI_API_KEY") do
  EmberEx.Examples.SimpleOpenAIExample.run()
else
  IO.puts("""
  This example requires an OpenAI API key.
  Please set the OPENAI_API_KEY environment variable and run the script again.
  
  Example usage:
    OPENAI_API_KEY=your-api-key elixir examples/simple_openai_example.exs
  """)
end
