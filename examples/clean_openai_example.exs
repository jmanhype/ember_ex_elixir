#!/usr/bin/env elixir
# Clean OpenAI Example for EmberEx
#
# This example works with the existing EmberEx architecture without requiring
# any modifications to the core library.

Mix.install([
  {:ember_ex, path: Path.expand("../", __DIR__)}
])

defmodule EmberEx.Examples.CleanOpenAIExample do
  @moduledoc """
  A clean example of using OpenAI integration with EmberEx.
  
  This example avoids modifying any core library files and works with the existing
  EmberEx architecture.
  """
  
  alias EmberEx.Operators.{LLMOperator, MapOperator, SequenceOperator}
  alias EmberEx.Specifications.BasicSpecification
  
  # Define a schema for structured output
  defmodule PoemSchema do
    @moduledoc """
    Schema for poem generation output.
    """
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
  Run the example.
  """
  def run do
    IO.puts("=== EmberEx Clean OpenAI Example ===\n")
    
    # Set up OpenAI
    setup_api_key()
    
    # Run with direct models API
    run_direct_api_example()
    
    # Run with adapter for operator system
    run_operator_example()
    
    :ok
  end
  
  @doc """
  Set up the OpenAI API key.
  """
  def setup_api_key do
    IO.puts("Setting up OpenAI API key...")
    
    # Get the API key from environment
    api_key = System.get_env("OPENAI_API_KEY")
    if !api_key do
      IO.puts("Error: OPENAI_API_KEY environment variable not set.")
      System.halt(1)
    end
    
    # Configure EmberEx with the API key
    EmberEx.Config.put_in([:models, :providers, :openai, :api_key], api_key)
    EmberEx.Config.load_from_env()
    
    IO.puts("Configuration complete.\n")
  end
  
  @doc """
  Run an example that directly uses the EmberEx.Models API.
  """
  def run_direct_api_example do
    IO.puts("\n=== Direct Models API Example ===")
    
    # Create a model callable
    IO.puts("Creating model callable...")
    model_fn = EmberEx.Models.model("gpt-3.5-turbo", [temperature: 0.7])
    
    # Define a prompt
    prompt = "Generate a short poem about functional programming."
    IO.puts("Calling model with prompt: #{prompt}")
    
    # Call the model
    response = model_fn.(prompt)
    
    # Display the result
    IO.puts("\nResult:")
    IO.puts("------------------------------")
    IO.puts(response.content)
    IO.puts("------------------------------")
    IO.puts("Model: #{response.metadata.model_id}")
    IO.puts("Provider: #{response.metadata.provider}")
    IO.puts("\n")
  end
  
  @doc """
  Run an example that uses the operator system with an adapter.
  """
  def run_operator_example do
    IO.puts("\n=== Operator System Example ===")
    
    # Create a specification using BasicSpecification
    spec = BasicSpecification.new(
      "Generate a short poem about {topic}.",
      nil,  # No input schema for simplicity
      %{
        "type" => "object",
        "properties" => %{
          "poem" => %{"type" => "string"}
        },
        "required" => ["poem"]
      }
    )
    
    # Create an adapter function that bridges between LLMOperator and EmberEx.Models
    adapter = fn model_args ->
      try do
        # Extract prompt from model_args
        prompt = case model_args do
          %{messages: [%{content: content} | _]} -> content
          %{messages: messages} when is_list(messages) ->
            user_message = Enum.find(messages, fn msg -> Map.get(msg, :role) == "user" end)
            Map.get(user_message || %{}, :content, "")
          _ -> inspect(model_args)
        end
        
        # Call EmberEx.Models.model directly
        model_fn = EmberEx.Models.model("gpt-3.5-turbo", [temperature: 0.7])
        response = model_fn.(prompt)
        
        # Return structured response in the format LLMOperator expects
        {:ok, %{poem: response.content}}
      rescue
        e -> {:error, Exception.message(e)}
      end
    end
    
    # Create the LLM operator with our adapter
    llm_op = LLMOperator.new(spec, adapter)
    
    # Create a preprocessing operator
    preprocessor = MapOperator.new(fn input ->
      IO.puts("Preprocessing input: #{inspect(input)}")
      # Add a timestamp to the input
      Map.put(input, :timestamp, DateTime.utc_now())
    end)
    
    # Create a postprocessing operator
    postprocessor = MapOperator.new(fn result ->
      IO.puts("Postprocessing result")
      # Add metadata to the result
      Map.put(result, :processed_at, DateTime.utc_now())
    end)
    
    # Create a pipeline
    pipeline = SequenceOperator.new([
      preprocessor,
      llm_op,
      postprocessor
    ])
    
    # Call the pipeline
    IO.puts("Calling operator pipeline...")
    result = EmberEx.Operators.Operator.call(pipeline, %{
      topic: "functional programming in Elixir"
    })
    
    # Display the result
    IO.puts("\nResult:")
    IO.puts("------------------------------")
    IO.puts(result.poem)
    IO.puts("------------------------------")
    IO.puts("Processed at: #{result.processed_at}")
    IO.puts("\n")
  end
end

# Run the example
EmberEx.Examples.CleanOpenAIExample.run()
