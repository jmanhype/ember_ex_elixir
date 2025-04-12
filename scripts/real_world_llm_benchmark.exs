#!/usr/bin/env elixir

# Real-world LLM Optimization Benchmark
# Tests the performance of the JIT optimization system with actual LLM operations
# rather than simulated ones, where prompt construction and parsing are more complex

# Ensure the application is started
Application.ensure_all_started(:ember_ex)

require Logger

defmodule RealWorldLLMBenchmark do
  @moduledoc """
  Benchmarks real-world LLM operations with JIT optimizations.
  
  This script tests the performance of various JIT strategies on
  real-world LLM operations, including:
  
  1. Complex prompt construction with multiple context inputs
  2. Actual LLM API calls (or simulated ones if no API keys)
  3. Sophisticated response parsing
  4. Multi-stage pipelines combining multiple LLM operations
  """
  
  alias EmberEx.XCS.JIT.Core, as: JIT
  alias EmberEx.XCS.JIT.Profiler, as: Profiler
  alias EmberEx.XCS.JIT.Cache, as: Cache
  alias EmberEx.XCS.JIT.Strategies.LLMStrategy, as: LLMStrategy
  alias EmberEx.XCS.JIT.Strategies.Enhanced, as: EnhancedStrategy
  alias EmberEx.Operators.Operator
  alias EmberEx.Operators.LLMOperator
  alias EmberEx.Operators.MapOperator
  alias EmberEx.Operators.SequenceOperator
  
  @doc """
  Runs the benchmark tests.
  """
  def run do
    Logger.info("Starting Real-World LLM Optimization Benchmark")
    
    # Clear cache before starting
    Cache.clear()
    
    # Test with various optimization strategies
    benchmark_strategies()
    
    # Test partial caching scenarios
    benchmark_partial_caching()
    
    # Test a complex multi-stage pipeline
    benchmark_multi_stage_pipeline()
    
    # Display cache statistics
    display_cache_stats()
    
    Logger.info("Benchmark completed")
  end
  
  @doc """
  Benchmarks different strategies on the same LLM operation.
  """
  def benchmark_strategies do
    Logger.info("=== Testing JIT Strategies ===")
    
    # Create a sophisticated LLM operation pipeline
    Logger.info("Creating complex LLM operation pipeline")
    pipeline = create_complex_llm_pipeline()
    
    # Create test inputs
    inputs = %{
      topic: "Sustainable urban transportation",
      context: "Policy document for city council",
      tone: "Professional and data-driven",
      word_limit: 500
    }
    
    # Test with no optimization (baseline)
    {baseline_result, baseline_time} = Profiler.profile("baseline_execution", fn ->
      Operator.call(pipeline, inputs)
    end)
    
    Logger.info("Baseline execution time: #{Float.round(baseline_time, 2)}ms")
    
    # Test with enhanced optimization
    enhanced_strategy = EnhancedStrategy.new()
    
    {enhanced_op, enhanced_compile_time} = Profiler.profile("enhanced_compilation", fn ->
      JIT.jit(pipeline, strategy: enhanced_strategy)
    end)
    
    {enhanced_result, enhanced_time} = Profiler.profile("enhanced_execution", fn ->
      Operator.call(enhanced_op, inputs)
    end)
    
    Logger.info("Enhanced strategy - Compilation: #{Float.round(enhanced_compile_time, 2)}ms, Execution: #{Float.round(enhanced_time, 2)}ms")
    Logger.info("Enhanced speedup: #{Float.round(baseline_time / enhanced_time, 2)}x")
    
    # Test with LLM-specialized optimization
    llm_strategy = LLMStrategy.new()
    
    {llm_op, llm_compile_time} = Profiler.profile("llm_compilation", fn ->
      JIT.jit(pipeline, strategy: llm_strategy, mode: :llm)
    end)
    
    {llm_result, llm_time} = Profiler.profile("llm_execution", fn ->
      Operator.call(llm_op, inputs)
    end)
    
    Logger.info("LLM strategy - Compilation: #{Float.round(llm_compile_time, 2)}ms, Execution: #{Float.round(llm_time, 2)}ms")
    Logger.info("LLM speedup: #{Float.round(baseline_time / llm_time, 2)}x")
    
    # Verify results are consistent
    verify_results(baseline_result, enhanced_result, llm_result)
  end
  
  @doc """
  Benchmarks the effectiveness of partial caching strategies.
  """
  def benchmark_partial_caching do
    Logger.info("=== Testing Partial Caching ===")
    
    # Create a pipeline with deterministic and non-deterministic parts
    Logger.info("Creating pipeline with mixed deterministic/non-deterministic parts")
    pipeline = create_mixed_determinism_pipeline()
    
    # Create multiple similar inputs to test caching effectiveness
    base_inputs = [
      %{query: "Renewable energy trends", context: "Global market report 2025"},
      %{query: "Renewable energy technologies", context: "Global market report 2025"},
      %{query: "Renewable energy investments", context: "Global market report 2025"},
      %{query: "Renewable energy policy", context: "Global market report 2025"}
    ]
    
    # Optimize with LLM strategy
    llm_strategy = LLMStrategy.new()
    optimized_pipeline = JIT.jit(pipeline, strategy: llm_strategy, mode: :llm)
    
    # Reset cache statistics
    Cache.clear()
    
    # Run first to warm up cache
    Logger.info("Warming up cache")
    Operator.call(optimized_pipeline, Enum.at(base_inputs, 0))
    
    # Run the rest to test cache hits
    Logger.info("Testing subsequent calls with similar inputs")
    
    # Aggregate results
    cache_metrics = Enum.map(Enum.slice(base_inputs, 1, 3), fn inputs ->
      # Clear metrics for this run
      start_metrics = Cache.get_metrics()
      
      {_, time} = Profiler.profile("cached_execution", fn ->
        Operator.call(optimized_pipeline, inputs)
      end)
      
      end_metrics = Cache.get_metrics()
      hits = end_metrics.cache_hit_count - start_metrics.cache_hit_count
      
      %{time: time, cache_hits: hits}
    end)
    
    # Calculate average metrics
    avg_time = cache_metrics |> Enum.map(& &1.time) |> Enum.sum() / length(cache_metrics)
    avg_hits = cache_metrics |> Enum.map(& &1.cache_hits) |> Enum.sum() / length(cache_metrics)
    
    Logger.info("Average execution time with partial caching: #{Float.round(avg_time, 2)}ms")
    Logger.info("Average cache hits per execution: #{Float.round(avg_hits, 2)}")
  end
  
  @doc """
  Benchmarks a multi-stage LLM pipeline with multiple model calls.
  """
  def benchmark_multi_stage_pipeline do
    Logger.info("=== Testing Multi-stage Pipeline ===")
    
    # Create a multi-stage pipeline with multiple LLM calls
    Logger.info("Creating multi-stage pipeline")
    pipeline = create_multi_stage_pipeline()
    
    inputs = %{
      user_query: "What are the latest advancements in quantum computing?",
      user_expertise: "Beginner",
      max_length: 1000
    }
    
    # Test baseline performance
    {_, baseline_time} = Profiler.profile("baseline_multi_stage", fn ->
      Operator.call(pipeline, inputs)
    end)
    
    Logger.info("Baseline multi-stage execution time: #{Float.round(baseline_time, 2)}ms")
    
    # Test with batch optimization
    llm_strategy = LLMStrategy.new(batch_size: 2) # Enable batch processing
    
    {optimized_pipeline, _} = Profiler.profile("optimized_multi_compilation", fn ->
      JIT.jit(pipeline, strategy: llm_strategy, mode: :llm, optimize_batch: true)
    end)
    
    {_, optimized_time} = Profiler.profile("optimized_multi_stage", fn ->
      Operator.call(optimized_pipeline, inputs)
    end)
    
    Logger.info("Optimized multi-stage execution time: #{Float.round(optimized_time, 2)}ms")
    Logger.info("Multi-stage speedup: #{Float.round(baseline_time / optimized_time, 2)}x")
  end
  
  @doc """
  Creates a complex LLM pipeline for testing.
  
  This pipeline simulates:
  1. Prompt preparation with multiple inputs
  2. LLM call
  3. Complex result parsing
  """
  def create_complex_llm_pipeline do
    # Create prompt preparation function
    prepare_prompt = fn inputs ->
      prompt = """
      Write a #{inputs.tone} summary on #{inputs.topic} for a #{inputs.context}.
      Keep it under #{inputs.word_limit} words.
      
      Your response should be well-structured and include:
      - Key points supported by data
      - Policy recommendations
      - Implementation timeline
      """
      
      Map.put(inputs, :prompt, prompt)
    end
    
    # Create result parsing function
    parse_result = fn inputs ->
      response = inputs.llm_response
      
      # Simulated parsing logic
      parsed = %{
        summary: response,
        word_count: String.split(response, ~r/\s+/) |> length(),
        key_sections: [
          "Introduction",
          "Key Points",
          "Recommendations",
          "Timeline"
        ]
      }
      
      Map.put(inputs, :parsed_result, parsed)
    end
    
    # Create format output function
    format_output = fn inputs ->
      result = inputs.parsed_result
      
      formatted = %{
        topic: inputs.topic,
        content: result.summary,
        metadata: %{
          word_count: result.word_count,
          sections: result.key_sections,
          context: inputs.context
        }
      }
      
      formatted
    end
    
    # Build the pipeline
    prompt_op = MapOperator.new(prepare_prompt, [:topic, :context, :tone, :word_limit], :prompt)
    
    # Use a mock LLM when no API key is available
    llm_op = if System.get_env("OPENAI_API_KEY") do
      LLMOperator.new(
        "gpt-3.5-turbo",
        "{prompt}",
        :prompt,
        :llm_response
      )
    else
      # Mock LLM implementation
      MapOperator.new(
        fn inputs ->
          # Simulate LLM response
          "This is a simulated response about #{inputs.topic}. " <>
          "Sustainable urban transportation requires integrated planning " <>
          "and investment in multiple modes of transport. Cities should focus on " <>
          "expanding public transit, creating safe cycling infrastructure, and " <>
          "implementing congestion pricing. Data shows that cities with diverse " <>
          "transportation options have lower emissions and better economic outcomes. " <>
          "We recommend phased implementation over a 5-year period, beginning with " <>
          "policy reforms in year 1, infrastructure investments in years 2-4, and " <>
          "full integration of digital tools by year 5."
        end,
        [:prompt, :topic],
        :llm_response
      )
    end
    
    parsing_op = MapOperator.new(parse_result, [:llm_response], :parsed_result)
    format_op = MapOperator.new(format_output, [:parsed_result, :topic, :context], :result)
    
    # Compose the full pipeline
    SequenceOperator.new([
      prompt_op,
      llm_op,
      parsing_op,
      format_op
    ])
  end
  
  @doc """
  Creates a pipeline with mixed deterministic and non-deterministic components.
  """
  def create_mixed_determinism_pipeline do
    # Deterministic prompt builder
    prompt_builder = fn inputs ->
      base_prompt = "Please provide information about #{inputs.query} in the context of #{inputs.context}."
      
      %{
        prompt: base_prompt,
        system_message: "You are a helpful assistant providing information about #{inputs.context}."
      }
    end
    
    # Non-deterministic LLM call
    llm_call = fn inputs ->
      # Mock LLM call with some randomness to simulate non-determinism
      response = "Information about #{inputs.prompt}: " <>
                "This is a simulated response with some random elements " <>
                "#{:rand.uniform(1000)}."
                
      Map.put(inputs, :response, response)
    end
    
    # Deterministic post-processor
    post_processor = fn inputs ->
      response = inputs.response
      
      # Extract key points (deterministic transformation)
      %{
        original_query: inputs.query,
        context: inputs.context,
        result: response,
        word_count: String.split(response, ~r/\s+/) |> length()
      }
    end
    
    # Build the pipeline
    prompt_op = MapOperator.new(prompt_builder, [:query, :context], [:prompt, :system_message])
    llm_op = MapOperator.new(llm_call, [:prompt, :system_message], :response)
    post_op = MapOperator.new(post_processor, [:response, :query, :context], :result)
    
    SequenceOperator.new([prompt_op, llm_op, post_op])
  end
  
  @doc """
  Creates a multi-stage pipeline with multiple LLM calls.
  """
  def create_multi_stage_pipeline do
    # Stage 1: Generate search queries from user question
    generate_queries = fn inputs ->
      # Mock function to generate search queries from user query
      query = inputs.user_query
      
      # This would normally be an LLM call to generate search queries
      search_queries = [
        "latest advancements quantum computing",
        "quantum computing breakthroughs 2024",
        "quantum computing for beginners"
      ]
      
      Map.put(inputs, :search_queries, search_queries)
    end
    
    # Stage 2: Generate answers for each search query
    generate_answers = fn inputs ->
      # Mock function to generate answers for each search query
      queries = inputs.search_queries
      expertise = inputs.user_expertise
      
      # This would normally be multiple LLM calls to generate answers
      answers = Enum.map(queries, fn query ->
        "Answer for '#{query}': This is a simulated response about quantum computing " <>
        "tailored for a #{expertise} level of expertise. Recent advancements include " <>
        "improvements in qubit stability and error correction."
      end)
      
      Map.put(inputs, :individual_answers, answers)
    end
    
    # Stage 3: Synthesize a final answer from individual results
    synthesize_answer = fn inputs ->
      # Mock function to synthesize a final answer
      answers = inputs.individual_answers
      query = inputs.user_query
      expertise = inputs.user_expertise
      
      # This would normally be an LLM call to synthesize answers
      final_answer = """
      Based on your question: "#{query}"
      
      Here's what you should know about recent quantum computing advancements:
      
      #{Enum.join(answers, "\n\n")}
      
      This explanation is tailored for a #{expertise} level of understanding.
      """
      
      %{final_answer: final_answer}
    end
    
    # Build the multi-stage pipeline
    query_op = MapOperator.new(generate_queries, [:user_query, :user_expertise], :search_queries)
    answer_op = MapOperator.new(generate_answers, [:search_queries, :user_expertise], :individual_answers)
    synthesis_op = MapOperator.new(
      synthesize_answer, 
      [:individual_answers, :user_query, :user_expertise], 
      :final_answer
    )
    
    SequenceOperator.new([query_op, answer_op, synthesis_op])
  end
  
  @doc """
  Verify that the optimization doesn't change the functional result.
  """
  def verify_results(baseline, enhanced, llm) do
    # Check for deep equality - in real code, we might need more sophisticated comparison
    # that allows for inconsequential differences
    if baseline == enhanced && enhanced == llm do
      Logger.info("✅ All results are consistent")
    else
      Logger.error("❌ Results differ between optimization strategies!")
      Logger.error("Baseline: #{inspect(baseline, pretty: true)}")
      Logger.error("Enhanced: #{inspect(enhanced, pretty: true)}")
      Logger.error("LLM: #{inspect(llm, pretty: true)}")
    end
  end
  
  @doc """
  Display cache statistics at the end of the benchmark.
  """
  def display_cache_stats do
    stats = Cache.get_stats()
    
    Logger.info("=== Cache Statistics ===")
    Logger.info("Total cache hits: #{stats.hits}")
    Logger.info("Total cache misses: #{stats.misses}")
    Logger.info("Cache hit rate: #{Float.round(stats.hit_rate, 2)}%")
    Logger.info("Total calls: #{stats.total_calls}")
  end
end

# Run the benchmark
RealWorldLLMBenchmark.run()
