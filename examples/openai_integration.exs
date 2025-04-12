#!/usr/bin/env elixir
# Example demonstrating OpenAI integration with EmberEx
#
# This example shows how to:
# 1. Configure EmberEx to use OpenAI
# 2. Create and use simple LLM operators
# 3. Create operators with structured output
# 4. Compose LLM operators together

Mix.install([
  {:ember_ex, path: Path.expand("../", __DIR__)}
])

defmodule EmberEx.Examples.OpenAIIntegration do
  @moduledoc """
  Example demonstrating OpenAI integration with EmberEx.
  
  Shows various ways to interact with OpenAI models through EmberEx's
  operator system.
  """
  
  alias EmberEx.Operators.{LLMOperator, MapOperator, SequenceOperator}
  
  @doc """
  Run the example.
  """
  def run do
    IO.puts("=== EmberEx OpenAI Integration Example ===\n")
    
    # Set up API key from environment variable or directly using the key value
    # Note: Using environment variables is more secure than hardcoding the key
    setup_api_key()
    
    # Example 1: Basic LLM operator
    basic_llm_example()
    
    # Example 2: LLM with structured output
    structured_output_example()
    
    # Example 3: Composed LLM operators
    composed_operators_example()
    
    :ok
  end
  
  @doc """
  Set up the OpenAI API key.
  """
  def setup_api_key do
    IO.puts("Setting up OpenAI API key...")
    
    # Option 1: Set via environment variable
    # System.put_env("EMBER_EX_MODELS_PROVIDERS_OPENAI_API_KEY", "your-api-key")
    
    # Option 2: Set directly in the configuration
    EmberEx.Config.put_in([:models, :providers, :openai, :api_key], System.get_env("OPENAI_API_KEY"))
    
    # Load config from environment variables
    EmberEx.Config.load_from_env()
    
    IO.puts("Configuration complete.\n")
  end
  
  @doc """
  Example of a basic LLM operator.
  """
  def basic_llm_example do
    IO.puts("\n=== Basic LLM Operator Example ===")
    
    # Create a simple LLM operator using the simplified interface
    llm_op = LLMOperator.from_prompt(
      "Generate a short poem about {topic}.",
      %{
        "type" => "object",
        "properties" => %{
          "poem" => %{"type" => "string"}
        },
        "required" => ["poem"]
      },
      "gpt-3.5-turbo",  # Use a less expensive model for examples
      %{temperature: 0.8}
    )
    
    IO.puts("Calling LLM operator with input...")
    result = EmberEx.Operators.Operator.call(llm_op, %{topic: "artificial intelligence"})
    
    IO.puts("\nResult:")
    IO.puts("------------------------------")
    IO.puts(result.poem)
    IO.puts("------------------------------\n")
  end
  
  @doc """
  Example of an LLM operator with structured output.
  """
  def structured_output_example do
    IO.puts("\n=== Structured Output Example ===")
    
    # Create an LLM operator that returns structured data
    analyzer_op = LLMOperator.from_prompt(
      "Analyze the sentiment and key themes of the following text: {text}",
      %{
        "type" => "object",
        "properties" => %{
          "sentiment" => %{
            "type" => "string",
            "enum" => ["positive", "negative", "neutral"]
          },
          "score" => %{
            "type" => "number",
            "minimum" => 0,
            "maximum" => 1
          },
          "themes" => %{
            "type" => "array",
            "items" => %{"type" => "string"},
            "maxItems" => 5
          },
          "summary" => %{"type" => "string", "maxLength" => 250}
        },
        "required" => ["sentiment", "score", "themes", "summary"]
      },
      "gpt-3.5-turbo"
    )
    
    IO.puts("Calling analyzer operator...")
    sample_text = "EmberEx is an amazing framework that makes building AI applications with language models easy and efficient. The functional programming approach provides great composability and the JIT optimization system improves performance significantly."
    
    result = EmberEx.Operators.Operator.call(analyzer_op, %{text: sample_text})
    
    IO.puts("\nAnalysis Result:")
    IO.puts("------------------------------")
    IO.puts("Sentiment: #{result.sentiment}")
    IO.puts("Score: #{result.score}")
    IO.puts("Themes: #{Enum.join(result.themes, ", ")}")
    IO.puts("Summary: #{result.summary}")
    IO.puts("------------------------------\n")
  end
  
  @doc """
  Example of composed LLM operators.
  """
  def composed_operators_example do
    IO.puts("\n=== Composed Operators Example ===")
    
    # First operator: Generate ideas
    idea_generator = LLMOperator.from_prompt(
      "Generate 3 creative startup ideas related to {industry}. Format as a comma-separated list.",
      %{
        "type" => "object",
        "properties" => %{
          "ideas" => %{"type" => "string"}
        },
        "required" => ["ideas"]
      },
      "gpt-3.5-turbo"
    )
    
    # Second operator: Split the comma-separated list into an array
    splitter = MapOperator.new(
      fn %{ideas: ideas} ->
        parsed_ideas = ideas
          |> String.split(",")
          |> Enum.map(&String.trim/1)
          |> Enum.filter(fn idea -> idea != "" end)
        
        %{ideas_list: parsed_ideas}
      end,
      :ideas,
      :ideas_list
    )
    
    # Third operator: Evaluate and rank the ideas
    evaluator = LLMOperator.from_prompt(
      "Evaluate and rank these startup ideas from most promising to least promising: {ideas_list}",
      %{
        "type" => "object",
        "properties" => %{
          "ranked_ideas" => %{
            "type" => "array",
            "items" => %{
              "type" => "object",
              "properties" => %{
                "idea" => %{"type" => "string"},
                "score" => %{"type" => "integer", "minimum" => 1, "maximum" => 10},
                "reasoning" => %{"type" => "string"}
              },
              "required" => ["idea", "score", "reasoning"]
            }
          }
        },
        "required" => ["ranked_ideas"]
      },
      "gpt-3.5-turbo"
    )
    
    # Compose the operators in sequence
    pipeline = SequenceOperator.new([
      idea_generator,
      splitter,
      evaluator
    ])
    
    IO.puts("Calling composed pipeline with 'AI healthcare' as the industry...")
    result = EmberEx.Operators.Operator.call(pipeline, %{industry: "AI healthcare"})
    
    IO.puts("\nRanked Ideas:")
    IO.puts("------------------------------")
    Enum.each(result.ranked_ideas, fn idea ->
      IO.puts("#{idea.idea} (Score: #{idea.score})")
      IO.puts("Reasoning: #{idea.reasoning}")
      IO.puts("")
    end)
    IO.puts("------------------------------\n")
  end
end

# Run the example
if System.get_env("OPENAI_API_KEY") do
  EmberEx.Examples.OpenAIIntegration.run()
else
  IO.puts("""
  This example requires an OpenAI API key.
  Please set the OPENAI_API_KEY environment variable and run the script again.
  
  Example usage:
    OPENAI_API_KEY=your-api-key elixir examples/openai_integration.exs
  """)
end
