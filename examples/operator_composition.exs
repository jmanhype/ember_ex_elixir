#!/usr/bin/env elixir
# Example demonstrating operator composition patterns in EmberEx
#
# This example shows how to:
# 1. Create basic operators
# 2. Compose operators in different patterns (sequence, parallel, branch)
# 3. Work with operator inputs and outputs
# 4. Create reusable operator chains

Mix.install([
  {:ember_ex, path: Path.expand("../", __DIR__)}
])

defmodule EmberEx.Examples.OperatorComposition do
  @moduledoc """
  Example demonstrating various composition patterns with EmberEx operators.
  
  This example focuses on showing the functional programming approach to
  building AI applications with composable operators.
  """
  
  alias EmberEx.Operators.{
    MapOperator,
    SequenceOperator,
    ParallelOperator,
    BranchOperator,
    ContainerOperator
  }
  
  @doc """
  Run the example.
  """
  def run do
    IO.puts("=== EmberEx Operator Composition Example ===\n")
    
    # Example 1: Basic Sequence Composition
    IO.puts("EXAMPLE 1: Basic Sequence Composition")
    basic_sequence_example()
    
    # Example 2: Parallel Composition
    IO.puts("\nEXAMPLE 2: Parallel Composition")
    parallel_composition_example()
    
    # Example 3: Branching Logic
    IO.puts("\nEXAMPLE 3: Branching Logic")
    branching_logic_example()
    
    # Example 4: Nested Composition
    IO.puts("\nEXAMPLE 4: Nested Composition")
    nested_composition_example()
    
    # Example 5: Reusing Operators
    IO.puts("\nEXAMPLE 5: Reusing Operators")
    reusing_operators_example()
    
    :ok
  end
  
  @doc """
  Example of basic sequence composition.
  """
  def basic_sequence_example do
    # Create a pipeline of operators that process text
    
    # Step 1: Normalize text (lowercase)
    normalize_op = MapOperator.new(
      fn text -> String.downcase(text) end,
      :text,
      :normalized
    )
    
    # Step 2: Count words
    word_count_op = MapOperator.new(
      fn text -> 
        text |> String.split() |> length()
      end,
      :normalized,
      :word_count
    )
    
    # Step 3: Calculate reading time (assume 200 words per minute)
    reading_time_op = MapOperator.new(
      fn count -> 
        minutes = count / 200
        Float.round(minutes, 1)
      end,
      :word_count,
      :reading_time_minutes
    )
    
    # Compose them in sequence
    pipeline = SequenceOperator.new([
      normalize_op,
      word_count_op,
      reading_time_op
    ])
    
    # Execute the pipeline
    input = %{text: "EmberEx is a functional programming approach to building AI applications with language models. It focuses on composition, reusability, and performance optimization."}
    result = EmberEx.Operators.Operator.call(pipeline, input)
    
    IO.puts("Input: #{input.text}")
    IO.puts("Word count: #{result.word_count}")
    IO.puts("Estimated reading time: #{result.reading_time_minutes} minutes")
  end
  
  @doc """
  Example of parallel composition.
  """
  def parallel_composition_example do
    # Create multiple operators that will run in parallel
    
    # Operator 1: Count characters
    char_count_op = MapOperator.new(
      fn text -> String.length(text) end,
      :text,
      :char_count
    )
    
    # Operator 2: Count words
    word_count_op = MapOperator.new(
      fn text -> 
        text |> String.split() |> length()
      end,
      :text,
      :word_count
    )
    
    # Operator 3: Count sentences
    sentence_count_op = MapOperator.new(
      fn text -> 
        text 
          |> String.split(~r/[.!?]/) 
          |> Enum.reject(&(String.trim(&1) == "")) 
          |> length()
      end,
      :text,
      :sentence_count
    )
    
    # Execute them in parallel
    parallel_op = ParallelOperator.new([
      char_count_op,
      word_count_op,
      sentence_count_op
    ])
    
    # Execute the parallel operator
    input = %{text: "EmberEx is an Elixir port of the Ember framework. It provides a functional programming approach to building AI applications. The architecture focuses on composition!"}
    result = EmberEx.Operators.Operator.call(parallel_op, input)
    
    IO.puts("Input: #{input.text}")
    IO.puts("Character count: #{result.char_count}")
    IO.puts("Word count: #{result.word_count}")
    IO.puts("Sentence count: #{result.sentence_count}")
    
    # Now let's calculate text statistics with the results
    stats_op = MapOperator.new(
      fn inputs -> 
        # Using explicit Map.get to safely handle inputs
        char_count = Map.get(inputs, :char_count, 0)
        word_count = Map.get(inputs, :word_count, 0)
        sentence_count = Map.get(inputs, :sentence_count, 0)
        
        # Avoid division by zero
        avg_word_length = if word_count > 0, do: char_count / word_count, else: 0
        avg_words_per_sentence = if sentence_count > 0, do: word_count / sentence_count, else: 0
        
        %{
          avg_word_length: Float.round(avg_word_length, 2),
          avg_words_per_sentence: Float.round(avg_words_per_sentence, 2)
        }
      end,
      nil,
      :stats
    )
    
    # Combine parallel operation with the stats calculation
    pipeline = SequenceOperator.new([
      parallel_op,
      stats_op
    ])
    
    combined_result = EmberEx.Operators.Operator.call(pipeline, input)
    IO.puts("Average word length: #{combined_result.stats.avg_word_length} characters")
    IO.puts("Average words per sentence: #{combined_result.stats.avg_words_per_sentence} words")
  end
  
  @doc """
  Example of branching logic.
  """
  def branching_logic_example do
    # Create a branching operator that takes different paths based on a condition
    
    # Define two branches for processing - one for short text and one for long text
    short_text_path = MapOperator.new(
      fn text -> 
        "Short text (#{String.length(text)} chars). Direct processing applied."
      end,
      :text,
      :analysis
    )
    
    long_text_path = MapOperator.new(
      fn text -> 
        "Long text (#{String.length(text)} chars). Advanced processing required."
      end,
      :text,
      :analysis
    )
    
    # Define the branch condition function - returns true for long text, false for short text
    is_long_text = fn input ->
      text = input.text
      String.length(text) > 100
    end
    
    # Create the branching operator with the binary condition
    branch_op = BranchOperator.new(
      is_long_text,   # Predicate function - true if text is long
      long_text_path, # Branch to take if predicate returns true
      short_text_path # Branch to take if predicate returns false
    )
    
    # Test with different inputs - one short and one long
    test_inputs = [
      %{text: "Short input."},
      %{text: "This is a longer input that should exceed our 100 character threshold and therefore be processed by the long text branch operator. This text should definitely qualify as long by our standards."}
    ]
    
    Enum.each(test_inputs, fn input ->
      result = EmberEx.Operators.Operator.call(branch_op, input)
      IO.puts("Input (first 30 chars): \"#{String.slice(input.text, 0..29)}...\"")
      IO.puts("Input length: #{String.length(input.text)} characters")
      IO.puts("Result: #{result.analysis}")
      IO.puts("")
    end)
  end
  
  @doc """
  Example of nested composition with multiple levels.
  """
  def nested_composition_example do
    # Create a complex nested operator structure
    
    # Level 1: Text preprocessing
    text_preprocessing = SequenceOperator.new([
      # Normalize text
      MapOperator.new(
        fn text -> String.downcase(text) end,
        :text,
        :normalized
      ),
      
      # Remove punctuation
      MapOperator.new(
        fn text -> 
          String.replace(text, ~r/[^\w\s]/, "")
        end,
        :normalized,
        :cleaned
      )
    ])
    
    # Level 2: Parallel analysis
    parallel_analysis = ParallelOperator.new([
      # Word frequency
      MapOperator.new(
        fn text -> 
          text
            |> String.split()
            |> Enum.frequencies()
            |> Enum.sort_by(fn {_, count} -> -count end)
            |> Enum.take(5)
        end,
        :cleaned,
        :word_frequencies
      ),
      
      # Length stats
      MapOperator.new(
        fn text -> 
          words = String.split(text)
          total_words = length(words)
          total_length = words |> Enum.map(&String.length/1) |> Enum.sum()
          avg_length = total_length / max(total_words, 1)
          
          %{
            total_words: total_words,
            avg_length: avg_length
          }
        end,
        :cleaned,
        :length_stats
      )
    ])
    
    # Level 3: Result formatting
    result_formatter = MapOperator.new(
      fn inputs -> 
        # Get the word frequencies and length stats from the inputs
        frequencies = Map.get(inputs, :word_frequencies, [])
        stats = Map.get(inputs, :length_stats, %{total_words: 0, avg_length: 0})
        
        # Format the top words as a string
        top_words = frequencies
          |> Enum.map(fn {word, count} -> "#{word} (#{count})" end)
          |> Enum.join(", ")
        
        # Create a summary with the information we have
        %{
          top_words: top_words,
          word_count: Map.get(stats, :total_words, 0),
          avg_word_length: Float.round(Map.get(stats, :avg_length, 0), 2)
        }
      end,
      nil,
      :summary
    )
    
    # Combine everything into a nested pipeline
    nested_pipeline = SequenceOperator.new([
      text_preprocessing,
      parallel_analysis,
      result_formatter
    ])
    
    # Execute the nested pipeline
    input = %{text: "EmberEx is an Elixir port of the Ember framework. It provides a functional programming approach to building AI applications with language models. It focuses on composition, reusability, and performance optimization for AI workflows."}
    result = EmberEx.Operators.Operator.call(nested_pipeline, input)
    
    IO.puts("Original text: #{String.slice(input.text, 0..50)}...")
    IO.puts("Word count: #{result.summary.word_count}")
    IO.puts("Average word length: #{result.summary.avg_word_length} characters")
    
    # Check if we have top words before trying to output them
    if result.summary.top_words && result.summary.top_words != "" do
      IO.puts("Top words: #{result.summary.top_words}")
    else
      IO.puts("Top words: None found")
    end
  end
  
  @doc """
  Example of reusing operators.
  """
  def reusing_operators_example do
    # Create simple, composable operators
    
    # Text normalization - convert to lowercase
    normalize_text = MapOperator.new(
      fn input -> 
        # Extract text from input
        text = cond do
          is_binary(input) -> input
          is_map(input) and Map.has_key?(input, :text) -> input.text
          true -> ""
        end
        String.downcase(text)
      end,
      nil,
      :normalized_text
    )
    
    # Remove punctuation 
    remove_punctuation = MapOperator.new(
      fn input -> 
        # Get the normalized text from the input
        text = cond do
          is_binary(input) -> input
          is_map(input) and Map.has_key?(input, :normalized_text) -> input.normalized_text
          true -> ""
        end
        String.replace(text, ~r/[^\w\s]/, "")
      end,
      nil,
      :cleaned_text
    )
    
    # Create a text preprocessing container with these operations
    text_preprocessor = ContainerOperator.new(
      SequenceOperator.new([
        normalize_text,
        remove_punctuation
      ]),
      %{}, # No input transformations needed
      %{} # Let the default output pass through
    )
    
    # Count words in a text
    count_words = MapOperator.new(
      fn text -> text |> String.split() |> length() end,
      :text_to_count,
      :word_count
    )
    
    # Adapter to get text for counting from various inputs
    text_adapter = MapOperator.new(
      fn input -> 
        cond do
          is_binary(input) -> input
          is_map(input) and Map.has_key?(input, :cleaned_text) -> input.cleaned_text
          is_map(input) and Map.has_key?(input, :text) -> input.text
          true -> ""
        end
      end,
      nil,
      :text_to_count
    )
    
    # Very simplified sentiment analysis
    analyze_sentiment = MapOperator.new(
      fn text -> 
        # Define word lists
        positive_words = ~w(good great amazing excellent awesome easy)
        negative_words = ~w(bad terrible difficult complex hard)
        
        # Process input text
        words = text |> String.downcase() |> String.split()
        
        # Count positive and negative words
        positive_count = Enum.count(words, &(Enum.member?(positive_words, &1)))
        negative_count = Enum.count(words, &(Enum.member?(negative_words, &1)))
        
        # Determine sentiment
        sentiment = cond do
          positive_count > negative_count -> "positive"
          negative_count > positive_count -> "negative"
          true -> "neutral"
        end
        
        # Return the result
        %{
          sentiment: sentiment,
          score: positive_count - negative_count
        }
      end, 
      :sentiment_text,
      :sentiment_result
    )
    
    # Create a sentiment adapter similar to our text adapter
    sentiment_adapter = MapOperator.new(
      fn input -> 
        cond do
          is_binary(input) -> input
          is_map(input) and Map.has_key?(input, :cleaned_text) -> input.cleaned_text
          is_map(input) and Map.has_key?(input, :text) -> input.text
          true -> ""
        end
      end,
      nil,
      :sentiment_text
    )
    
    # Package sentiment analysis as a container
    sentiment_analyzer = ContainerOperator.new(
      SequenceOperator.new([
        sentiment_adapter,
        analyze_sentiment
      ]),
      %{}, # No input transformations needed
      %{} # Default output passing
    )
    
    # Create a pipeline for basic word counting
    count_pipeline = SequenceOperator.new([
      text_adapter,
      count_words
    ])
    
    # Create a pipeline for counting words in cleaned text
    clean_count_pipeline = SequenceOperator.new([
      text_preprocessor,
      text_adapter,
      count_words
    ])
    
    # Test the pipelines
    input = %{text: "EmberEx is an AMAZING framework! It makes building AI applications EASY."}
    
    raw_result = EmberEx.Operators.Operator.call(count_pipeline, input)
    cleaned_result = EmberEx.Operators.Operator.call(clean_count_pipeline, input)
    
    IO.puts("Original text: #{input.text}")
    IO.puts("Raw word count: #{raw_result.word_count}")
    IO.puts("Cleaned word count: #{cleaned_result.word_count}")
    
    # Create a comprehensive analysis pipeline using ContainerOperator.collecting
    analysis_pipeline = ContainerOperator.collecting([
      # Preprocess the text
      text_preprocessor,
      # Count words (with adapter)
      SequenceOperator.new([text_adapter, count_words]),
      # Analyze sentiment
      sentiment_analyzer
    ])
    
    # Test the analysis pipeline
    analysis_input = %{text: "EmberEx is an amazing framework! It makes building complex AI applications easy and straightforward."}
    analysis_result = EmberEx.Operators.Operator.call(analysis_pipeline, analysis_input)
    
    IO.puts("\nText analysis:")
    IO.puts("Input: #{analysis_input.text}")
    IO.puts("Word count: #{analysis_result.word_count}")
    IO.puts("Sentiment: #{analysis_result.sentiment_result.sentiment}")
    IO.puts("Sentiment score: #{analysis_result.sentiment_result.score}")
  end
end

# Run the example
EmberEx.Examples.OperatorComposition.run()
