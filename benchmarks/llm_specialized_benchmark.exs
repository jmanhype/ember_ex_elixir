#!/usr/bin/env elixir

# Specialized LLM JIT Benchmarking script
# This script demonstrates the specialized optimizations for LLM operations
# including partial caching, function composition, and parallel batch processing

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
alias EmberEx.XCS.JIT.LLMDetector
alias EmberEx.Metrics.Collector
alias EmberEx.Operators.{MapOperator, SequenceOperator, ParallelOperator}

IO.puts("EmberEx Specialized LLM JIT Benchmarking")
IO.puts("========================================")
IO.puts("")

# Helper to create test LLM pipelines that demonstrate different optimization opportunities
create_test_pipelines = fn ->
  # 1. Function composition pipeline: prep -> LLM -> postprocess
  #    Tests optimization of functions before/after LLM call
  #------------------------------------------------
  
  # Prompt preparation function - good candidate for optimization
  prompt_prep = fn input ->
    # Simulate complex template rendering with string manipulations
    system_prompt = "You are a helpful assistant that provides information about #{input.topic}."
    user_template = "Tell me about #{input.subtopic || input.topic} in the context of #{input.context}. Please be #{input.style}."
    examples = ["Example 1", "Example 2"]
      |> Enum.map(fn ex -> "#{ex} for #{input.topic}" end)
      |> Enum.join("\n")
      
    formatted_prompt = """
    #{system_prompt}
    
    User query: #{user_template}
    
    Examples:
    #{examples}
    """
    
    # Add some artificial delay to represent computation time
    Process.sleep(5)
    
    %{prompt: formatted_prompt, input: input}
  end
  
  # Mock LLM call - this should be preserved for stochasticity
  llm_call = fn input ->
    prompt = input.prompt
    
    # Simulate LLM call with random response and variable timing
    wait_time = (String.length(prompt) / 50) * (1.0 + :rand.uniform() * 0.2)
    Process.sleep(trunc(wait_time))
    
    response = "This is a response about #{input.input.topic}. " <>
               "The response is #{:rand.uniform(1000)} words long and covers #{input.input.subtopic || input.input.topic}."
    
    %{
      response: response,
      input: input.input,
      usage: %{
        prompt_tokens: div(String.length(prompt), 4),
        completion_tokens: 150,
        total_tokens: div(String.length(prompt), 4) + 150
      }
    }
  end
  
  # Post-processing function - good candidate for optimization
  postprocess = fn result ->
    # Simulate complex result processing
    response = result.response
    words = String.split(response)
    word_count = length(words)
    
    # Extract key information (artificial delay for computation)
    Process.sleep(8)
    
    %{
      content: response,
      summary: "Summary with #{word_count} words about #{result.input.topic}",
      metadata: %{
        topic: result.input.topic,
        subtopic: result.input.subtopic,
        style: result.input.style,
        tokens: result.usage.total_tokens
      }
    }
  end
  
  # Create sequence pipeline connecting these functions
  composition_pipeline = SequenceOperator.new([
    MapOperator.new(prompt_prep),
    MapOperator.new(llm_call),
    MapOperator.new(postprocess)
  ])
  
  # 2. Partial caching pipeline: deterministic prep with branching paths -> LLM
  #    Tests caching of deterministic subgraphs while preserving stochastic parts
  #------------------------------------------------
  
  # Complex but deterministic data preparation
  data_prep = fn input ->
    # Simulate computationally intensive but deterministic preparation
    # This should be highly cacheable
    Process.sleep(20)  # Simulate expensive computation
    
    # Process topic data
    topic_data = String.upcase(input.topic)
    context_data = input.context
      |> String.split(" ")
      |> Enum.map(&String.capitalize/1)
      |> Enum.join(" ")
      
    style_modifier = case input.style do
      "concise" -> "Keep it brief and to the point."
      "detailed" -> "Please provide comprehensive details."
      "simple" -> "Explain as if to a beginner."
      _ -> "Standard explanation."
    end
    
    %{
      processed_topic: topic_data,
      processed_context: context_data,
      style_directive: style_modifier,
      original: input
    }
  end
  
  # Decision function that branches processing based on input
  # This tests handling of complex control flow
  branch_processor = fn input ->
    # This should benefit from partial caching since the branches are deterministic
    # but each might be taken depending on input
    Process.sleep(10)  # Simulate decision making
    
    branch = cond do
      String.contains?(input.original.topic, "history") -> 
        %{branch: "history", template: "Historical perspective on #{input.processed_topic}"}
        
      String.contains?(input.original.topic, "science") -> 
        %{branch: "science", template: "Scientific explanation of #{input.processed_topic}"}
        
      String.contains?(input.original.topic, "art") -> 
        %{branch: "art", template: "Artistic analysis of #{input.processed_topic}"}
        
      true ->
        %{branch: "general", template: "General information about #{input.processed_topic}"}
    end
    
    Map.merge(input, branch)
  end
  
  # Final prompt assembly before LLM
  prompt_assembly = fn input ->
    # Combines all the processed information into a final prompt
    # Should be heavily optimizable and cacheable
    Process.sleep(15)  # Simulate complex template rendering
    
    prompt = """
    Topic: #{input.processed_topic}
    Context: #{input.processed_context}
    Branch: #{input.branch}
    
    #{input.template} within the context of #{input.processed_context}.
    
    #{input.style_directive}
    """
    
    %{
      prompt: prompt,
      metadata: %{
        branch: input.branch,
        topic: input.original.topic
      }
    }
  end
  
  # The LLM call - should be preserved
  cached_llm_call = fn input ->
    # Similar to previous LLM call but with different output format
    prompt = input.prompt
    
    # Simulate variable timing
    wait_time = (String.length(prompt) / 40) * (1.0 + :rand.uniform() * 0.3)
    Process.sleep(trunc(wait_time))
    
    # Stochastic response
    branch_prefix = case input.metadata.branch do
      "history" -> "From a historical perspective, "
      "science" -> "Scientifically speaking, "
      "art" -> "From an artistic viewpoint, "
      _ -> ""
    end
    
    response = "#{branch_prefix}here is information about #{input.metadata.topic}. " <>
               "This response contains #{:rand.uniform(800) + 200} words of analysis."
    
    %{
      response: response,
      branch: input.metadata.branch,
      topic: input.metadata.topic
    }
  end
  
  # Create sequence pipeline for partial caching test
  partial_caching_pipeline = SequenceOperator.new([
    MapOperator.new(data_prep),
    MapOperator.new(branch_processor),
    MapOperator.new(prompt_assembly),
    MapOperator.new(cached_llm_call)
  ])
  
  # 3. Batch processing pipeline: process multiple similar requests in parallel
  #    Tests parallel optimization for multiple LLM requests
  #------------------------------------------------
  
  # Simple prompt formatter that will be duplicated for batch processing
  simple_prompt = fn input ->
    # Basic prompt formatting
    prompt = "Tell me about #{input.topic} in a #{input.style} way."
    Process.sleep(3)
    %{prompt: prompt, metadata: input}
  end
  
  # LLM call for batch processing
  batch_llm_call = fn input ->
    # Simulate longer processing for batch items
    Process.sleep(10 + :rand.uniform(10))
    
    %{
      response: "Information about #{input.metadata.topic} presented #{input.metadata.style}ly.",
      topic: input.metadata.topic
    }
  end
  
  # Handler for processing a single batch item
  process_batch_item = fn item ->
    # Format prompt for this item
    prompt_result = simple_prompt.(item)
    # Call LLM with the prepared prompt
    batch_llm_call.(prompt_result)
  end
  
  # Single prompt + LLM pipeline for batch processing
  batch_item_pipeline = MapOperator.new(process_batch_item)
  
  # Return all test pipelines
  %{
    composition: composition_pipeline,
    partial_caching: partial_caching_pipeline,
    batch_item: batch_item_pipeline
  }
end

# Create test pipelines
pipelines = create_test_pipelines.()

# Test inputs for different scenarios
composition_input = %{
  topic: "machine learning",
  subtopic: "neural networks",
  context: "modern AI development",
  style: "comprehensive"
}

partial_caching_inputs = [
  %{topic: "history of computing", context: "technological evolution", style: "detailed"},
  %{topic: "science of quantum physics", context: "modern understanding", style: "simple"},
  %{topic: "art of impressionism", context: "19th century movement", style: "concise"},
  %{topic: "general knowledge", context: "everyday applications", style: "conversational"}
]

batch_inputs = [
  %{topic: "Python programming", style: "concise"},
  %{topic: "JavaScript frameworks", style: "detailed"},
  %{topic: "Database design", style: "simple"},
  %{topic: "Web security", style: "technical"},
  %{topic: "User experience", style: "friendly"},
  %{topic: "Mobile development", style: "practical"},
  %{topic: "Cloud computing", style: "business"},
  %{topic: "Artificial intelligence", style: "educational"}
]

# Helper for running benchmark with different JIT strategies
run_specialized_benchmark = fn {name, pipeline, input, description} ->
  IO.puts("\n=== Benchmarking #{name} ===")
  IO.puts(description)
  
  # Number of runs for each benchmark
  runs = 5
  warmup = 2
  
  # Warm up
  IO.puts("\nWarming up...")
  Enum.each(1..warmup, fn _ ->
    EmberEx.Operators.Operator.call(pipeline, input)
  end)
  
  # Benchmark without optimization
  IO.puts("\nRunning without optimization...")
  {standard_time, _} = :timer.tc(fn ->
    Enum.map(1..runs, fn i ->
      IO.write(".")
      result = EmberEx.Operators.Operator.call(pipeline, input)
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
    {"Enhanced JIT", fn op -> JITCore.jit(op, mode: :enhanced) end},
    {"LLM-specialized JIT", fn op -> 
      JITCore.jit(op, mode: :llm, 
        optimize_prompt: true,
        optimize_postprocess: true,
        preserve_llm_call: true
      )
    end}
  ]
  
  # Results collection
  all_results = Enum.map(optimization_strategies, fn {strategy_name, optimize_fn} ->
    IO.puts("\nRunning with #{strategy_name}...")
    optimized_op = optimize_fn.(pipeline)
    
    # First run for compilation
    first_run_result = if is_function(optimized_op) do
      optimized_op.(input)
    else
      EmberEx.Operators.Operator.call(optimized_op, input)
    end
    
    # Benchmark optimized version
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
      Collector.record("specialized_llm_jit_speedup", speedup, :gauge, %{
        pipeline: name,
        strategy: strategy_name
      })
    end
    
    IO.puts("Average time with #{strategy_name}: #{Float.round(avg_optimized_time, 2)} ms")
    IO.puts("Speedup: #{Float.round(speedup, 2)}%")
    
    # Return results for this strategy
    %{
      strategy: strategy_name,
      standard_time: avg_standard_time,
      optimized_time: avg_optimized_time,
      speedup: speedup
    }
  end)
  
  # Return all results
  all_results
end

# Run benchmarks for different scenarios

IO.puts("\n---- Function Composition Optimization Benchmark ----")
IO.puts("Testing optimization of pre and post-processing functions around LLM calls")
composition_results = run_specialized_benchmark.({
  "Function Composition Pipeline", 
  pipelines.composition, 
  composition_input,
  "This pipeline has separate prompt preparation and result processing functions that\ncan be optimized while preserving the stochastic LLM call in the middle."
})

IO.puts("\n---- Partial Caching Optimization Benchmark ----")
IO.puts("Testing caching of deterministic subgraphs with multiple execution paths")

# Run partial caching benchmark with each input type to test different branches
partial_caching_all_results = Enum.map(partial_caching_inputs, fn input ->
  branch_name = cond do
    String.contains?(input.topic, "history") -> "Historical Branch"
    String.contains?(input.topic, "science") -> "Scientific Branch" 
    String.contains?(input.topic, "art") -> "Artistic Branch"
    true -> "General Branch"
  end
  
  run_specialized_benchmark.({
    "Partial Caching Pipeline (#{branch_name})",
    pipelines.partial_caching,
    input,
    "Testing optimization of deterministic preprocessing with a complex branching structure,\nwhile preserving the stochastic LLM call at the end."
  })
end)

# Calculate average results across all branches
partial_caching_results = %{
  strategy_results: Enum.map(["Standard JIT", "Enhanced JIT", "LLM-specialized JIT"], fn strategy_name ->
    # Find all results for this strategy across branches
    strategy_runs = Enum.flat_map(partial_caching_all_results, fn branch_results ->
      Enum.filter(branch_results, fn result -> result.strategy == strategy_name end)
    end)
    
    # Calculate averages
    avg_standard = Enum.reduce(strategy_runs, 0, fn r, acc -> acc + r.standard_time end) / length(strategy_runs)
    avg_optimized = Enum.reduce(strategy_runs, 0, fn r, acc -> acc + r.optimized_time end) / length(strategy_runs)
    avg_speedup = Enum.reduce(strategy_runs, 0, fn r, acc -> acc + r.speedup end) / length(strategy_runs)
    
    %{
      strategy: strategy_name,
      avg_standard_time: avg_standard,
      avg_optimized_time: avg_optimized,
      avg_speedup: avg_speedup
    }
  end)
}

IO.puts("\n---- Batch Processing Optimization Benchmark ----")
IO.puts("Testing parallel optimization for multiple similar LLM requests")

# For batch processing benchmarks, we'll use a single item first to establish baseline
# and then compare with batch processing performance
batch_single_input = batch_inputs |> List.first()

# Create a batch request with multiple similar items
batch_request = %{
  items: batch_inputs,
  model: "test-model",
  parameters: %{temperature: 0.7}
}

# Test with single item first for baseline
single_batch_results = run_specialized_benchmark.({
  "Single Item Processing",
  pipelines.batch_item,
  batch_single_input,
  "Baseline performance with a single item for comparison."
})

# Create a batch processor that maps over all items
batch_processor = fn batch_input ->
  # Extract individual items
  items = batch_input.items
  
  # Process each item and collect results
  results = Enum.map(items, fn item ->
    # Call our item processor on each item
    EmberEx.Operators.Operator.call(pipelines.batch_item, item)
  end)
  
  # Return results along with original metadata
  Map.put(batch_input, :results, results)
end

# Create a batch pipeline
batch_pipeline = MapOperator.new(batch_processor)

# For batch processing, we'll use a different benchmarking approach
# to highlight the parallel processing capabilities
IO.puts("\nRunning batch processing benchmark...")
IO.puts("This tests processing multiple items in parallel vs. serially")

# First measure serial processing (baseline)
IO.puts("\nRunning with serial processing...")
{serial_time, _} = :timer.tc(fn ->
  batch_processor.(batch_request)
end)
avg_serial_time = serial_time / 1000
IO.puts("Serial processing time: #{Float.round(avg_serial_time, 2)} ms")

# Measure with specialized LLM JIT optimization (parallel)
IO.puts("\nRunning with LLM-specialized JIT (parallel processing)...")
optimized_batch_processor = JITCore.jit(batch_processor, 
  mode: :llm, 
  parallel_requests: true,
  batch_size: 4
)
{optimized_time, _} = :timer.tc(fn ->
  optimized_batch_processor.(batch_request)
end)
avg_optimized_time = optimized_time / 1000
speedup = (avg_serial_time - avg_optimized_time) / avg_serial_time * 100
IO.puts("Parallel processing time: #{Float.round(avg_optimized_time, 2)} ms")
IO.puts("Parallelization speedup: #{Float.round(speedup, 2)}%")

# Store batch results
batch_processing_results = [
  %{
    strategy: "Serial Processing",
    standard_time: avg_serial_time,
    optimized_time: avg_serial_time,
    speedup: 0
  },
  %{
    strategy: "LLM-specialized JIT (Parallel)",
    standard_time: avg_serial_time, 
    optimized_time: avg_optimized_time,
    speedup: speedup
  }
]

# Show overall statistics
IO.puts("\n==== Overall Statistics ====\n")

cache_stats = EmberEx.XCS.JIT.Cache.get_stats()
IO.puts("Cache hits: #{cache_stats.hits}")
IO.puts("Cache misses: #{cache_stats.misses}")
IO.puts("Total calls: #{cache_stats.total_calls || (cache_stats.hits + cache_stats.misses)}")
IO.puts("Hit rate: #{Float.round(cache_stats.hit_rate, 2)}%")

# Print final summary
IO.puts("\n==== Specialized LLM JIT Optimization Summary ====")
IO.puts("1. Function Composition Optimization:")
best_composition = Enum.max_by(composition_results, fn r -> r.speedup end)
IO.puts("   Best strategy: #{best_composition.strategy} with #{Float.round(best_composition.speedup, 2)}% speedup")

IO.puts("\n2. Partial Caching with Branching Paths:")
best_partial_caching = Enum.max_by(
  partial_caching_results.strategy_results, 
  fn r -> r.avg_speedup end
)
IO.puts("   Best strategy: #{best_partial_caching.strategy} with #{Float.round(best_partial_caching.avg_speedup, 2)}% speedup")

IO.puts("\n3. Batch Processing Optimization:")
parallel_result = Enum.find(batch_processing_results, fn r -> r.strategy == "LLM-specialized JIT (Parallel)" end)
IO.puts("   Parallel processing speedup: #{Float.round(parallel_result.speedup, 2)}%")

IO.puts("\nSpecialized LLM JIT benchmark completed successfully.")
