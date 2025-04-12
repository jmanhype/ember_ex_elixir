#!/usr/bin/env elixir
# Proper LLMOperator example with Ecto Schemas for EmberEx
#
# This example shows how to use the LLMOperator with correct Ecto schema definitions
# to enable the full power of the operator system.

Mix.install([
  {:ember_ex, path: Path.expand("../", __DIR__)}
])

defmodule EmberEx.Examples.ProperOperatorExample do
  @moduledoc """
  Example demonstrating proper use of EmberEx operators with Ecto schemas.
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
  
  # Define a schema for a more complex structured output
  defmodule AnalysisOutput do
    use Ecto.Schema
    import Ecto.Changeset
    
    @primary_key false
    embedded_schema do
      field :sentiment, :string
      field :score, :float
      field :themes, {:array, :string}
      field :summary, :string
    end
    
    def changeset(schema, params) do
      schema
      |> cast(params, [:sentiment, :score, :themes, :summary])
      |> validate_required([:sentiment, :score, :themes, :summary])
      |> validate_inclusion(:sentiment, ["positive", "negative", "neutral"])
      |> validate_number(:score, greater_than_or_equal_to: 0, less_than_or_equal_to: 1)
    end
  end
  
  @doc """
  Run the example
  """
  def run do
    IO.puts("=== EmberEx Proper Operator Example ===\n")
    
    # Set up the OpenAI API key
    setup_api_key()
    
    # Example 1: Basic LLM operator with proper schemas
    basic_llm_example()
    
    # Example 2: Composed operators with proper schemas
    composed_operators_example()
    
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
  Example of a basic LLM operator with proper Ecto schemas
  """
  def basic_llm_example do
    IO.puts("\n=== Basic LLM Operator Example ===")
    
    # Create a specification using the Ecto schemas
    spec = EmberEx.Specifications.EctoSpecification.new(
      "Generate a short poem about {topic}.",
      PoemInput,
      PoemOutput
    )
    
    # Create the model callable
    model = EmberEx.Models.model("gpt-3.5-turbo", [temperature: 0.7])
    
    # Create the LLM operator
    llm_op = LLMOperator.new(spec, model)
    
    # Call the operator
    IO.puts("Calling LLM operator with input...")
    result = EmberEx.Operators.Operator.call(llm_op, %{topic: "functional programming"})
    
    # Display the result
    IO.puts("\nResult:")
    IO.puts("------------------------------")
    IO.puts(result.poem)
    IO.puts("------------------------------\n")
  end
  
  @doc """
  Example of composed operators with proper schemas
  """
  def composed_operators_example do
    IO.puts("\n=== Composed Operators Example ===")
    
    # Create a text analysis operator
    analysis_spec = EmberEx.Specifications.EctoSpecification.new(
      "Analyze the sentiment and key themes of the following text: {text}",
      nil, # No input schema for simplicity
      AnalysisOutput
    )
    
    model = EmberEx.Models.model("gpt-3.5-turbo")
    analyzer_op = LLMOperator.new(analysis_spec, model)
    
    # Create a preprocessing operator
    preprocessor = MapOperator.new(fn input ->
      # Convert input to lowercase and add length information
      text = String.downcase(input.text)
      word_count = text |> String.split() |> length()
      
      # Return enhanced input
      Map.merge(input, %{
        text: text,
        metadata: %{
          word_count: word_count,
          timestamp: DateTime.utc_now()
        }
      })
    end)
    
    # Create a postprocessing operator
    postprocessor = MapOperator.new(fn result ->
      # Extract and enhance the themes
      themes_with_importance = result.themes
        |> Enum.with_index(1)
        |> Enum.map(fn {theme, idx} -> 
          %{theme: theme, importance: length(result.themes) - idx + 1}
        end)
      
      # Return enhanced result
      Map.put(result, :enhanced_themes, themes_with_importance)
    end)
    
    # Compose the operators in sequence
    pipeline = SequenceOperator.new([
      preprocessor,
      analyzer_op,
      postprocessor
    ])
    
    # Sample text to analyze
    sample_text = "EmberEx is an amazing framework that makes building AI applications with language models easy and efficient. The functional programming approach provides great composability and the JIT optimization system improves performance significantly."
    
    IO.puts("Processing text through operator pipeline...")
    result = EmberEx.Operators.Operator.call(pipeline, %{text: sample_text})
    
    # Display the result
    IO.puts("\nAnalysis Result:")
    IO.puts("------------------------------")
    IO.puts("Sentiment: #{result.sentiment}")
    IO.puts("Score: #{result.score}")
    IO.puts("Themes: #{Enum.join(result.themes, ", ")}")
    IO.puts("Summary: #{result.summary}")
    IO.puts("\nEnhanced Themes with Importance:")
    
    Enum.each(result.enhanced_themes, fn theme ->
      IO.puts("  - #{theme.theme} (Importance: #{theme.importance})")
    end)
    
    IO.puts("------------------------------\n")
  end
end

# Run the example
EmberEx.Examples.ProperOperatorExample.run()
