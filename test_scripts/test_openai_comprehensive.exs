# Comprehensive test script for EmberEx with real OpenAI models
# 
# This script tests three key capabilities:
# 1. Summarization
# 2. Question Answering
# 3. Translation
#
# Types are annotated where possible within Elixir script constraints

# Import type definitions if we're in a context that supports typing
if Code.ensure_loaded?(Instructor) do
  alias EmberEx.Models.Response
  alias EmberEx.Operators.Operator
end

@doc """
Set up the environment and run all tests.

Returns:
  :ok | {:error, String.t()} - Result of the test execution
"""
defmodule OpenAITests do
  @moduledoc """
  Comprehensive tests for the EmberEx framework with real OpenAI models.
  
  This module implements tests for summarization, question answering, and
  translation to validate the full system pipeline.
  """
  
  @typedoc "Test result structure"
  @type test_result :: %{
    name: String.t(),
    success: boolean(),
    output: map() | nil,
    error: String.t() | nil
  }
  
  @doc """
  Run all tests and report results.
  
  Returns:
    :ok
  """
  @spec run_all() :: :ok
  def run_all do
    # Start the application
    Application.ensure_all_started(:ember_ex)
    
    # Check if API key is set
    api_key = System.get_env("OPENAI_API_KEY")
    
    if is_nil(api_key) || api_key == "" do
      IO.puts("⚠️ Warning: OPENAI_API_KEY environment variable not set.")
      IO.puts("Please set your API key in the environment before running tests.")
      IO.puts("You can use: export OPENAI_API_KEY=your_api_key")
      :error
    else
      # Define the model to use - use gpt-3.5-turbo for affordability during testing
      model_name = "gpt-3.5-turbo"
      
      IO.puts("\n🚀 Testing EmberEx with real OpenAI models")
      IO.puts("=========================================")
      
      # Run the tests
      results = [
        run_test("Summarization", fn -> test_summarization(model_name) end),
        run_test("Question Answering", fn -> test_question_answering(model_name) end),
        run_test("Translation", fn -> test_translation(model_name) end)
      ]
      
      # Report results
      report_results(results)
      
      :ok
    end
  end
  
  @doc """
  Run a single test and capture results.
  
  Args:
    name: String.t() - The name of the test
    test_fn: function - The test function to run
    
  Returns:
    test_result - A map containing test results
  """
  @spec run_test(String.t(), (-> map())) :: test_result()
  def run_test(name, test_fn) do
    IO.puts("\n🧪 Running test: #{name}")
    
    try do
      output = test_fn.()
      IO.puts("✅ Test '#{name}' succeeded")
      %{name: name, success: true, output: output, error: nil}
    rescue
      e ->
        IO.puts("❌ Test '#{name}' failed: #{Exception.message(e)}")
        %{name: name, success: false, output: nil, error: Exception.message(e)}
    end
  end
  
  @doc """
  Test the summarization capability.
  
  Args:
    model_name: String.t() - The model to use
    
  Returns:
    map() - The summarization result
  """
  @spec test_summarization(String.t()) :: map()
  def test_summarization(model_name) do
    IO.puts("Testing summarization with model: #{model_name}")
    
    # Create a simple MapOperator for summarization
    summarize_op = EmberEx.Operators.MapOperator.new_with_name(
      "summarize_op",
      nil,
      fn input ->
        model = EmberEx.Models.model(model_name)
        prompt = "Summarize this text in #{input.max_words} words or less: #{input.text}"
        response = model.(prompt)
        %{summary: response.content}
      end
    )
    
    # Test input
    input = %{
      text: "The Ember framework is a powerful tool for building AI applications using Language Models (LLMs). It provides a structured approach to building LLM applications with features like operators, graphs, and execution engines. This port to Elixir aims to bring the same capabilities to the Elixir ecosystem while leveraging the functional programming paradigm and concurrency features of the BEAM virtual machine. The framework defines core abstractions such as Operators, Specifications, and Execution Engines to provide a modular and extensible architecture.",
      max_words: 30
    }
    
    # Run the operator
    IO.puts("Running summarization with input length: #{String.length(input.text)} chars")
    result = EmberEx.Operators.Operator.call(summarize_op, input)
    
    # Display the result
    IO.puts("\n📝 Summarization Result:")
    IO.puts(result.summary)
    
    result
  end
  
  @doc """
  Test the question answering capability.
  
  Args:
    model_name: String.t() - The model to use
    
  Returns:
    map() - The question answering result
  """
  @spec test_question_answering(String.t()) :: map()
  def test_question_answering(model_name) do
    IO.puts("Testing question answering with model: #{model_name}")
    
    # Create a MapOperator for question answering
    qa_op = EmberEx.Operators.MapOperator.new_with_name(
      "qa_op",
      nil,
      fn input ->
        model = EmberEx.Models.model(model_name)
        prompt = """
        Answer this question based on the provided context.
        
        Context: #{input.context}
        
        Question: #{input.question}
        
        Provide a clear and concise answer.
        """
        response = model.(prompt)
        %{answer: response.content}
      end
    )
    
    # Test input
    input = %{
      context: "EmberEx is an Elixir port of the Ember framework, designed for building AI applications with language models. It features a graph-based execution engine that can run operations in parallel or sequentially. The framework includes operators like MapOperator, SequenceOperator, LLMOperator, and ParallelOperator. It supports OpenAI, Anthropic, and DeepMind models.",
      question: "What types of models does EmberEx support?"
    }
    
    # Run the operator
    IO.puts("Running question answering with context length: #{String.length(input.context)} chars")
    result = EmberEx.Operators.Operator.call(qa_op, input)
    
    # Display the result
    IO.puts("\n❓ Question Answering Result:")
    IO.puts("Q: #{input.question}")
    IO.puts("A: #{result.answer}")
    
    result
  end
  
  @doc """
  Test the translation capability.
  
  Args:
    model_name: String.t() - The model to use
    
  Returns:
    map() - The translation result
  """
  @spec test_translation(String.t()) :: map()
  def test_translation(model_name) do
    IO.puts("Testing translation with model: #{model_name}")
    
    # Create a MapOperator for translation
    translate_op = EmberEx.Operators.MapOperator.new_with_name(
      "translate_op",
      nil,
      fn input ->
        model = EmberEx.Models.model(model_name)
        prompt = """
        Translate the following text from #{input.source_language} to #{input.target_language}:
        
        #{input.text}
        
        Provide only the translated text without any additional explanations.
        """
        response = model.(prompt)
        %{translated_text: response.content}
      end
    )
    
    # Test input
    input = %{
      text: "Hello, I would like to test the translation capabilities of the EmberEx framework with a real OpenAI model.",
      source_language: "English",
      target_language: "French"
    }
    
    # Run the operator
    IO.puts("Running translation for text: \"#{input.text}\"")
    result = EmberEx.Operators.Operator.call(translate_op, input)
    
    # Display the result
    IO.puts("\n🌐 Translation Result:")
    IO.puts("Original (#{input.source_language}): #{input.text}")
    IO.puts("Translated (#{input.target_language}): #{result.translated_text}")
    
    result
  end
  
  @doc """
  Report test results summary.
  
  Args:
    results: [test_result()] - List of test results
    
  Returns:
    :ok
  """
  @spec report_results([test_result()]) :: :ok
  def report_results(results) do
    success_count = Enum.count(results, & &1.success)
    total_count = length(results)
    
    IO.puts("\n📊 Test Results Summary")
    IO.puts("=====================")
    IO.puts("Total tests: #{total_count}")
    IO.puts("Successful: #{success_count}")
    IO.puts("Failed: #{total_count - success_count}")
    
    if success_count == total_count do
      IO.puts("\n✅ All tests passed! The EmberEx framework is working correctly with real OpenAI models.")
    else
      IO.puts("\n⚠️ Some tests failed. Please check the individual test results above.")
    end
    
    :ok
  end
end

# Run all tests
OpenAITests.run_all()
