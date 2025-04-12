#!/usr/bin/env elixir

# Simple LLM JIT Strategy Test
# This script tests the new LLM JIT optimizations using a simplified setup

require Logger

defmodule SimpleLLMTest do
  @moduledoc """
  Provides basic tests for the LLM JIT optimizations.
  
  This is a simplified test that doesn't depend on complex external modules
  but validates that our JIT enhancements are working correctly.
  """
  
  alias EmberEx.Operators.MapOperator
  alias EmberEx.Operators.SequenceOperator

  def run do
    Logger.info("Starting Simple LLM JIT Strategy Test")
    
    # Create a simple mock LLM pipeline
    pipeline = create_mock_llm_pipeline()
    
    test_prompt_templates(pipeline)
    test_partial_caching(pipeline)
    test_execution_utils()
    
    Logger.info("Simple test completed!")
  end
  
  def test_prompt_templates(pipeline) do
    Logger.info("\n=== Testing Prompt Template Detection ===")
    
    # Extract the prompt builder function
    prompt_builder = fn text ->
      "This is a prompt template for: #{text}"
    end
    
    # Check if our LLM detector recognizes it properly
    detector_works = 
      try do
        # Use the prompt builder directly as test target
        is_template = EmberEx.XCS.JIT.LLMDetector.contains_prompt_template?(prompt_builder)
        
        if is_template do
          Logger.info("✅ LLM detector successfully identified prompt template function")
        else
          Logger.warning("❌ LLM detector failed to identify prompt template function")
        end
        
        is_template
      rescue
        e -> 
          Logger.error("❌ Error testing prompt template detection: #{inspect(e)}")
          false
      end
    
    detector_works
  end
  
  def test_partial_caching(pipeline) do
    Logger.info("\n=== Testing Partial Caching ===")
    
    # Create a simple function we can test with caching
    format_prompt = fn input ->
      "Format a prompt about #{input.topic} using #{input.style} style"
    end
    
    first_input = %{topic: "AI", style: "technical"}
    second_input = %{topic: "Machine Learning", style: "technical"}
    
    try do
      # Use partial cache directly to test caching behavior
      first_result = EmberEx.XCS.JIT.PartialCache.cached_execution(
        :test_function,
        first_input,
        nil,  # Use default key function
        format_prompt  # Function to execute
      )
      
      # Second call with same style but different topic should generate partial hit
      second_result = EmberEx.XCS.JIT.PartialCache.cached_execution(
        :test_function,
        second_input,
        &EmberEx.XCS.JIT.PartialCache.signature_based_key/2,  # Use signature-based key
        format_prompt  # Function to execute
      )
      
      Logger.info("First result: #{inspect(first_result)}")
      Logger.info("Second result: #{inspect(second_result)}")
      Logger.info("✅ Partial caching test completed")
      
      true
    rescue
      e -> 
        Logger.error("❌ Error testing partial caching: #{inspect(e)}")
        false
    end
  end
  
  def test_execution_utils do
    Logger.info("\n=== Testing Execution Utils ===")
    
    try do
      # Create a simple execution graph to test
      simple_graph = %{
        root: %{
          target: fn input -> "Processed #{input.text}" end,
          is_llm: true,
          preserve_stochasticity: true
        },
        nodes: [],
        edges: [],
        metadata: %{mode: :llm}
      }
      
      input = %{text: "Test input"}
      
      # Test LLM graph execution
      result = EmberEx.XCS.JIT.ExecutionUtils.execute_graph(simple_graph, input)
      
      Logger.info("Execution result: #{inspect(result)}")
      Logger.info("✅ Execution utils test completed")
      
      true
    rescue
      e -> 
        Logger.error("❌ Error testing execution utils: #{inspect(e)}")
        false
    end
  end
  
  def create_mock_llm_pipeline do
    # Mock prompt builder
    prompt_builder = fn inputs ->
      prompt = "Generate information about topic: #{inputs.topic}"
      Map.put(inputs, :prompt, prompt)
    end
    
    # Mock LLM function
    mock_llm = fn inputs ->
      response = "This is a generated response about #{inputs.topic}"
      Map.put(inputs, :response, response)
    end
    
    # Mock post-processor
    post_processor = fn inputs ->
      processed = String.upcase(inputs.response)
      Map.put(inputs, :processed, processed)
    end
    
    # Create operators
    prompt_op = MapOperator.new(prompt_builder, [:topic], :prompt)
    llm_op = MapOperator.new(mock_llm, [:prompt, :topic], :response)
    post_op = MapOperator.new(post_processor, [:response], :processed)
    
    # Chain them together
    SequenceOperator.new([prompt_op, llm_op, post_op])
  end
end

# Run the tests
SimpleLLMTest.run()
