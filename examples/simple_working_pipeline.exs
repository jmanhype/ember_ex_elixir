#!/usr/bin/env elixir
# Simple Working Pipeline Example for EmberEx
#
# This example demonstrates a minimal but functional integration with OpenAI
# including proper Ecto schemas and error handling.

Mix.install([
  {:ember_ex, path: Path.expand("../", __DIR__)}
])

defmodule EmberEx.Examples.SimpleWorkingPipeline do
  @moduledoc """
  A simplified example of using EmberEx operators with OpenAI.
  
  This demonstrates:
  - Basic Ecto schema definitions
  - A simple model adapter
  - Error handling for all components
  """
  
  alias EmberEx.Operators.{LLMOperator, MapOperator, SequenceOperator}
  
  #############################################################
  # Schema Definitions
  #############################################################
  
  # Basic poem input schema
  defmodule PoemInput do
    @moduledoc """
    Input schema for generating poems.
    """
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
  
  # Basic poem output schema
  defmodule PoemOutput do
    @moduledoc """
    Output schema for poem generation results.
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
  
  #############################################################
  # Adapter for EmberEx.Models to LLMOperator
  #############################################################
  
  @doc """
  Create a basic adapter between EmberEx.Models and LLMOperator.
  """
  def create_model_adapter(model_name, opts \\ []) do
    # Create the base model callable
    base_model = EmberEx.Models.model(model_name, opts)
    
    # Create an adapter function that handles format conversion
    fn model_args ->
      try do
        # Extract prompt from the messages
        prompt = extract_prompt_from_args(model_args)
        
        # Call the base model with the extracted prompt
        IO.puts("Calling model with prompt: #{prompt}")
        response = base_model.(prompt)
        IO.puts("Received response content: #{response.content}")
        
        # Return the response in the correct format
        {:ok, %{poem: response.content}}
      rescue
        e ->
          # Log the error
          IO.puts("Error in model adapter: #{Exception.message(e)}")
          
          # Return an error
          {:error, "Error in model adapter: #{Exception.message(e)}"}
      end
    end
  end
  
  @doc """
  Extract a usable prompt from the model arguments.
  """
  def extract_prompt_from_args(model_args) do
    case model_args do
      %{messages: messages} when is_list(messages) ->
        # Extract content from user messages
        messages
        |> Enum.filter(fn msg -> 
          is_map(msg) && Map.get(msg, :role) == "user" 
        end)
        |> Enum.map(fn msg -> Map.get(msg, :content, "") end)
        |> Enum.join("\n\n")
        
      string when is_binary(string) ->
        # If it's already a string, use it directly
        string
        
      _ ->
        # Try to extract a prompt from other formats or use empty string
        inspect(model_args)
    end
  end
  
  #############################################################
  # Main Example
  #############################################################
  
  @doc """
  Run the example.
  """
  def run do
    IO.puts("=== EmberEx Simple Working Pipeline ===\n")
    
    # Setup
    setup_api_key()
    
    # Run the basic example
    simple_poem_example()
    
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
  Simple poem generation example.
  """
  def simple_poem_example do
    IO.puts("\n=== Simple Poem Example ===")
    
    # Create specification with Ecto schemas
    spec = EmberEx.Specifications.EctoSpecification.new(
      "Generate a short poem about {topic}.",
      PoemInput,
      PoemOutput
    )
    
    # Create model adapter
    adapter = create_model_adapter("gpt-3.5-turbo", [temperature: 0.7])
    
    # Create a pre-processing operator
    preprocessor = MapOperator.new(fn input ->
      IO.puts("Preprocessing input: #{inspect(input)}")
      input
    end)
    
    # Create LLMOperator
    llm_op = LLMOperator.new(spec, adapter)
    
    # Create a post-processing operator 
    postprocessor = MapOperator.new(fn result ->
      IO.puts("Post-processing result: #{inspect(result)}")
      # Add metadata
      Map.put(result, :timestamp, DateTime.utc_now())
    end)
    
    # Create a pipeline
    pipeline = SequenceOperator.new([
      preprocessor,
      llm_op, 
      postprocessor
    ])
    
    # Call the pipeline
    IO.puts("Calling the operator pipeline...")
    result = try do
      EmberEx.Operators.Operator.call(pipeline, %{topic: "functional programming"})
    rescue
      e -> 
        IO.puts("Error calling operator: #{Exception.message(e)}")
        %{poem: "Error: #{Exception.message(e)}", timestamp: DateTime.utc_now()}
    end
    
    # Display the result
    IO.puts("\nPoem:")
    IO.puts("------------------------------")
    IO.puts(result.poem)
    IO.puts("------------------------------")
    IO.puts("Timestamp: #{result.timestamp}")
    IO.puts("\n")
  end
end

# Run the example
EmberEx.Examples.SimpleWorkingPipeline.run()
