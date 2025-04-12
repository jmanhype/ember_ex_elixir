#!/usr/bin/env elixir

# Enhanced JIT Benchmarking script focused on LLM operators
# This script demonstrates the performance improvements of JIT optimization 
# specifically for language model operations.

# Add the application to the code path
Code.prepend_path("_build/dev/lib/ember_ex/ebin")
Code.prepend_path("_build/dev/lib/instructor_ex/ebin")

# Start the EmberEx application
Application.ensure_all_started(:ember_ex)

# Initialize metrics storage and JIT system
:ok = EmberEx.Metrics.Storage.init()
case EmberEx.XCS.JIT.Cache.start_link([]) do
  {:ok, _pid} -> IO.puts("Started JIT cache server")
  {:error, {:already_started, _pid}} -> IO.puts("JIT cache server already running")
  other -> IO.puts("Unexpected result starting JIT cache: #{inspect(other)}")
end

# Initialize the JIT system
EmberEx.XCS.JIT.Init.start()

# Import necessary modules
alias EmberEx.XCS.JIT.Core, as: JITCore
alias EmberEx.XCS.JIT.Stochastic
alias EmberEx.XCS.JIT.Strategies.Providers.LLMStrategy
alias EmberEx.Metrics.Collector
alias EmberEx.Operators.{MapOperator, SequenceOperator, ParallelOperator}

IO.puts("EmberEx LLM-Focused JIT Benchmarking")
IO.puts("====================================")
IO.puts("")

# Helper to create mock LLM operators with different complexity levels
create_llm_operators = fn ->
  # Basic prompt template function
  basic_prompt_fn = fn input ->
    "Generate a response about #{input.topic} in the style of #{input.style}."
  end
  
  # Complex prompt with context, system instructions, and examples
  complex_prompt_fn = fn input ->
    """
    System: You are an assistant that helps users with their questions.
    
    Context:
    #{input.context}
    
    Question: #{input.question}
    
    Examples of good responses:
    #{Enum.join(input.examples, "\n\n")}
    
    Your response:
    """
  end
  
  # Create a mock LLM function to simulate actual LLM calls
  mock_llm_call = fn prompt, _options ->
    # Simulate different response times based on prompt length
    wait_time = Float.round(String.length(prompt) / 100, 2)
    :timer.sleep(trunc(wait_time * 10))
    
    # Calculate token counts
    prompt_tokens = div(String.length(prompt), 4)
    completion_tokens = 150
    total_tokens = prompt_tokens + completion_tokens
    
    # Simulate a model response
    %{
      response: "This is a simulated LLM response to: #{String.slice(prompt, 0, 50)}...",
      usage: %{
        prompt_tokens: prompt_tokens,
        completion_tokens: completion_tokens,
        total_tokens: total_tokens
      },
      model: "test-model"
    }
  end
  
  # Simple LLM Operator (single prompt template)
  simple_llm_op = MapOperator.new(fn input ->
    prompt = basic_prompt_fn.(input)
    mock_llm_call.(prompt, %{})
  end)
  
  # LLM Operator with preprocessing
  preprocessed_llm_op = SequenceOperator.new([
    # Preprocess input
    MapOperator.new(fn input ->
      %{
        topic: String.upcase(input.topic),
        style: input.style,
        formatted_topic: String.replace(input.topic, " ", "_")
      }
    end),
    # Generate prompt and call LLM
    MapOperator.new(fn input ->
      prompt = "Generate a detailed response about #{input.topic} in the style of #{input.style}."
      mock_llm_call.(prompt, %{})
    end)
  ])
  
  # Complex LLM chain with retrieval simulation
  complex_llm_chain = SequenceOperator.new([
    # Simulate document retrieval
    MapOperator.new(fn input ->
      # Simulate retrieving documents
      documents = [
        "Document 1 about #{input.topic}",
        "Document 2 with information on #{input.topic}",
        "Document 3 containing details about #{input.topic}"
      ]
      Map.put(input, :documents, documents)
    end),
    
    # Generate context from documents
    MapOperator.new(fn input ->
      context = Enum.join(input.documents, "\n\n")
      Map.put(input, :context, context)
    end),
    
    # Apply prompt template
    MapOperator.new(fn input ->
      Map.put(input, :examples, [
        "This is a comprehensive explanation of #{input.topic}.",
        "Here's what you need to know about #{input.topic}."
      ])
    end),
    
    # Generate final prompt and call LLM
    MapOperator.new(fn input ->
      prompt = complex_prompt_fn.(input)
      result = mock_llm_call.(prompt, %{temperature: 0.7})
      
      %{
        response: result.response,
        usage: result.usage,
        topic: input.topic
      }
    end)
  ])
  
  %{
    simple: simple_llm_op,
    preprocessed: preprocessed_llm_op,
    complex: complex_llm_chain
  }
end

llm_operators = create_llm_operators.()

# Test inputs
simple_input = %{topic: "artificial intelligence", style: "academic"}
complex_input = %{
  topic: "machine learning",
  style: "conversational",
  question: "How does neural machine translation work?"
}

# Run benchmarks with different JIT optimization strategies
run_llm_benchmark = fn {name, operator, input} ->
  IO.puts("\n==== Benchmarking #{name} LLM Operator ====")
  
  # Number of runs
  runs = 10
  warmup = 2
  
  # Warm up
  IO.puts("Warming up...")
  Enum.each(1..warmup, fn _ ->
    EmberEx.Operators.Operator.call(operator, input)
  end)
  
  # Benchmark without optimization
  IO.puts("\nRunning without optimization...")
  {standard_time, _} = :timer.tc(fn ->
    Enum.map(1..runs, fn i ->
      IO.write(".")
      result = EmberEx.Operators.Operator.call(operator, input)
      if i == runs, do: IO.puts("")
      result
    end)
  end)
  
  # Average time per call without optimization
  avg_standard_time = standard_time / runs / 1000
  IO.puts("Average time without optimization: #{Float.round(avg_standard_time, 2)} ms")
  
  # Test different optimization strategies
  optimization_strategies = [
    {"Standard JIT", fn op -> JITCore.jit(op) end},
    {"LLM-specific JIT", fn op -> JITCore.jit(op, mode: :llm) end},
    {"Stochastic JIT", fn op -> 
      Stochastic.jit_stochastic(op, stochastic_params: %{
        temperature: 0.7, 
        preserve_randomness: true
      })
    end}
  ]
  
  # Run benchmarks for each strategy
  results = Enum.map(optimization_strategies, fn {strategy_name, optimize_fn} ->
    IO.puts("\nRunning with #{strategy_name}...")
    optimized_op = optimize_fn.(operator)
    
    {optimized_time, _} = :timer.tc(fn ->
      Enum.map(1..runs, fn i ->
        IO.write(".")
        result = if is_function(optimized_op) do
          optimized_op.(input)
        else
          EmberEx.Operators.Operator.call(optimized_op, input)
        end
        if i == runs, do: IO.puts("")
        result
      end)
    end)
    
    # Average time per call with optimization
    avg_optimized_time = optimized_time / runs / 1000
    speedup = (avg_standard_time - avg_optimized_time) / avg_standard_time * 100
    
    # Record metric
    if speedup > 0 do
      Collector.record("llm_jit_speedup", speedup, :gauge, %{
        operator: name,
        strategy: strategy_name
      })
    end
    
    IO.puts("Average time with #{strategy_name}: #{Float.round(avg_optimized_time, 2)} ms")
    IO.puts("Speedup: #{Float.round(speedup, 2)}%")
    
    # Additional runs to test caching effects
    IO.puts("\nRunning again to measure caching effect...")
    {cached_time, _} = :timer.tc(fn ->
      Enum.map(1..runs, fn i ->
        IO.write(".")
        result = if is_function(optimized_op) do
          optimized_op.(input)
        else
          EmberEx.Operators.Operator.call(optimized_op, input)
        end
        if i == runs, do: IO.puts("")
        result
      end)
    end)
    
    # Average time per call with caching
    avg_cached_time = cached_time / runs / 1000
    cache_speedup = (avg_optimized_time - avg_cached_time) / avg_optimized_time * 100
    
    IO.puts("Average time with caching: #{Float.round(avg_cached_time, 2)} ms")
    IO.puts("Cache effect speedup: #{Float.round(cache_speedup, 2)}%")
    
    # Return results for this strategy
    %{
      strategy: strategy_name,
      standard_time: avg_standard_time,
      optimized_time: avg_optimized_time,
      cached_time: avg_cached_time,
      speedup: speedup,
      cache_speedup: cache_speedup
    }
  end)
  
  # Print summary table
  IO.puts("\n==== Summary for #{name} LLM Operator ====")
  IO.puts("| Strategy | Standard (ms) | Optimized (ms) | Cached (ms) | Speedup | Cache Effect |")
  IO.puts("|----------|---------------|----------------|-------------|---------|--------------|")
  
  Enum.each(results, fn result ->
    IO.puts("| #{result.strategy} | #{Float.round(result.standard_time, 2)} | " <>
            "#{Float.round(result.optimized_time, 2)} | " <>
            "#{Float.round(result.cached_time, 2)} | " <>
            "#{Float.round(result.speedup, 2)}% | " <>
            "#{Float.round(result.cache_speedup, 2)}% |")
  end)
  
  # Return all results
  results
end

# Run benchmarks for each operator type
IO.puts("\n---- Starting LLM Benchmark Suite ----\n")

# Simple LLM operator benchmark
simple_results = run_llm_benchmark.({"Simple", llm_operators.simple, simple_input})

# Preprocessed LLM operator benchmark
preprocessed_results = run_llm_benchmark.({"Preprocessed", llm_operators.preprocessed, simple_input})

# Complex LLM chain benchmark
complex_results = run_llm_benchmark.({"Complex", llm_operators.complex, complex_input})

# Show overall statistics
IO.puts("\n==== Overall Statistics ====\n")

cache_stats = EmberEx.XCS.JIT.Cache.get_stats()
IO.puts("Cache hits: #{cache_stats.hits}")
IO.puts("Cache misses: #{cache_stats.misses}")
IO.puts("Total calls: #{cache_stats.total_calls || (cache_stats.hits + cache_stats.misses)}")
IO.puts("Hit rate: #{Float.round(cache_stats.hit_rate, 2)}%")

# Print final summary
IO.puts("\n==== LLM JIT Optimization Conclusions ====")
IO.puts("1. Simple LLM operations: #{
  best_simple = Enum.max_by(simple_results, fn r -> r.speedup end)
  "Best strategy is #{best_simple.strategy} with #{Float.round(best_simple.speedup, 2)}% speedup"
}")

IO.puts("2. Preprocessed LLM operations: #{
  best_preprocessed = Enum.max_by(preprocessed_results, fn r -> r.speedup end)
  "Best strategy is #{best_preprocessed.strategy} with #{Float.round(best_preprocessed.speedup, 2)}% speedup"
}")

IO.puts("3. Complex LLM chains: #{
  best_complex = Enum.max_by(complex_results, fn r -> r.speedup end)
  "Best strategy is #{best_complex.strategy} with #{Float.round(best_complex.speedup, 2)}% speedup"
}")

IO.puts("\nLLM JIT benchmark completed successfully.")
