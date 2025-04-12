defmodule EmberEx.Benchmarks.JITBenchmarks do
  @moduledoc """
  Comprehensive benchmarks for measuring JIT optimization impact.
  
  This module provides tools for measuring and comparing the performance of
  JIT-optimized operators versus their non-optimized counterparts.
  """
  
  require Logger
  
  @type benchmark_result :: %{
    standard_execution_time_ms: float(),
    optimized_execution_time_ms: float(),
    speedup_percentage: float(),
    standard_memory_bytes: integer(),
    optimized_memory_bytes: integer(),
    memory_reduction_percentage: float(),
    runs: integer(),
    operator_type: String.t(),
    strategy: String.t() | nil
  }
  
  @doc """
  Run a benchmark comparing optimized and non-optimized versions of operators.
  
  Records execution time, memory usage, and throughput metrics.
  
  ## Parameters
  
  - operator: The operator to benchmark
  - inputs: The inputs to pass to the operator
  - options: Benchmark options
    - runs: Number of repetitions to run (default: 100)
    - warmup: Number of warmup runs to perform (default: 10)
    - strategy: JIT strategy to use (default: :auto)
  
  ## Returns
  
  Map containing performance metrics and comparison
  """
  @spec run_benchmark(
    EmberEx.Operators.Operator.t(), 
    map() | struct(), 
    keyword()
  ) :: benchmark_result()
  def run_benchmark(operator, inputs, options \\ []) do
    runs = Keyword.get(options, :runs, 100)
    warmup = Keyword.get(options, :warmup, 10)
    strategy = Keyword.get(options, :strategy, :auto)
    
    Logger.info("Running JIT benchmark with #{runs} runs and #{warmup} warmup cycles")
    
    # Get operator type for reporting
    operator_type = get_operator_type(operator)
    
    # Run warmup cycles
    Enum.each(1..warmup, fn _ ->
      EmberEx.Operators.Operator.call(operator, inputs)
    end)
    
    # Benchmark non-optimized
    {standard_time, {_result, standard_memory}} = :timer.tc(fn ->
      memory_before = :erlang.memory(:total)
      result = Enum.map(1..runs, fn _ ->
        EmberEx.Operators.Operator.call(operator, inputs)
      end)
      memory_after = :erlang.memory(:total)
      {result, memory_after - memory_before}
    end)
    
    # Apply JIT optimization
    jit_options = if strategy == :auto, do: [], else: [mode: strategy]
    optimized_operator = EmberEx.XCS.JIT.Core.jit(operator, jit_options)
    
    # Benchmark optimized
    {jit_time, {_result, jit_memory}} = :timer.tc(fn ->
      memory_before = :erlang.memory(:total)
      result = Enum.map(1..runs, fn _ ->
        if is_function(optimized_operator) do
          optimized_operator.(inputs)
        else
          EmberEx.Operators.Operator.call(optimized_operator, inputs)
        end
      end)
      memory_after = :erlang.memory(:total)
      {result, memory_after - memory_before}
    end)
    
    # Calculate performance metrics
    speedup = calculate_percentage_improvement(standard_time, jit_time)
    memory_reduction = calculate_percentage_improvement(standard_memory, jit_memory)
    
    # Return comprehensive metrics
    %{
      standard_execution_time_ms: standard_time / 1000,
      optimized_execution_time_ms: jit_time / 1000,
      speedup_percentage: speedup,
      standard_memory_bytes: standard_memory,
      optimized_memory_bytes: jit_memory,
      memory_reduction_percentage: memory_reduction,
      runs: runs,
      operator_type: operator_type,
      strategy: strategy
    }
  end
  
  @doc """
  Run benchmarks with multiple JIT strategies and compare results.
  
  ## Parameters
  
  - operator: The operator to benchmark
  - inputs: The inputs to pass to the operator
  - options: Benchmark options
    - runs: Number of repetitions to run (default: 50)
    - warmup: Number of warmup runs to perform (default: 5)
  
  ## Returns
  
  List of benchmark results for each strategy
  """
  @spec compare_strategies(
    EmberEx.Operators.Operator.t(), 
    map() | struct(), 
    keyword()
  ) :: [benchmark_result()]
  def compare_strategies(operator, inputs, options \\ []) do
    strategies = [:auto, :structural, :trace, :enhanced]
    
    # Reduce runs and warmup cycles to make this more efficient
    runs = Keyword.get(options, :runs, 50)
    warmup = Keyword.get(options, :warmup, 5)
    
    Logger.info("Comparing JIT strategies for #{get_operator_type(operator)}")
    
    # Run benchmark for each strategy
    Enum.map(strategies, fn strategy ->
      result = run_benchmark(operator, inputs, [
        runs: runs,
        warmup: warmup,
        strategy: strategy
      ])
      
      Logger.info("Strategy #{strategy}: #{result.speedup_percentage}% speedup")
      result
    end)
  end
  
  @doc """
  Run a comprehensive benchmark suite on common operator types.
  
  This creates and tests various operators with different complexity
  levels to measure JIT performance across use cases.
  
  ## Parameters
  
  - options: Benchmark options
    - runs: Number of repetitions to run (default: 100)
    - warmup: Number of warmup runs to perform (default: 10)
  
  ## Returns
  
  Map of operator types to benchmark results
  """
  @spec benchmark_suite(keyword()) :: %{optional(String.t()) => benchmark_result()}
  def benchmark_suite(options \\ []) do
    # Create test operators
    map_op = create_test_map_operator()
    sequence_op = create_test_sequence_operator()
    parallel_op = create_test_parallel_operator()
    complex_op = create_test_complex_operator()
    
    # Test inputs
    inputs = %{value: 10, text: "hello world"}
    
    # Run benchmarks
    operators = [
      {"MapOperator", map_op},
      {"SequenceOperator", sequence_op},
      {"ParallelOperator", parallel_op},
      {"ComplexOperator", complex_op}
    ]
    
    Logger.info("Running comprehensive benchmark suite")
    
    operators
    |> Enum.map(fn {name, op} ->
      Logger.info("Benchmarking #{name}...")
      {name, run_benchmark(op, inputs, options)}
    end)
    |> Enum.into(%{})
  end
  
  @doc """
  Generate a detailed report from benchmark results.
  
  ## Parameters
  
  - results: Benchmark results from run_benchmark/3 or benchmark_suite/1
  
  ## Returns
  
  String containing a formatted report
  """
  @spec generate_report(benchmark_result() | [benchmark_result()] | %{optional(String.t()) => benchmark_result()}) :: String.t()
  def generate_report(results) when is_map(results) and not is_struct(results) do
    # Handle results from benchmark_suite/1
    header = """
    ## EmberEx JIT Optimization Benchmark Report
    
    | Operator | Strategy | Execution Time | Memory Usage | Speedup | Memory Reduction |
    |----------|----------|---------------|-------------|---------|-----------------|
    """
    
    rows = Enum.map(results, fn {name, result} ->
      strategy_name = format_strategy(result.strategy)
      "| #{name} | #{strategy_name} | " <>
      "#{format_time(result.optimized_execution_time_ms)} | " <>
      "#{format_bytes(result.optimized_memory_bytes)} | " <>
      "#{format_percentage(result.speedup_percentage)} | " <>
      "#{format_percentage(result.memory_reduction_percentage)} |"
    end)
    
    header <> Enum.join(rows, "\n")
  end
  
  def generate_report(results) when is_list(results) do
    # Handle results from compare_strategies/3
    header = """
    ## EmberEx JIT Strategy Comparison Report
    
    | Strategy | Execution Time | Memory Usage | Speedup | Memory Reduction |
    |----------|---------------|-------------|---------|-----------------|
    """
    
    rows = Enum.map(results, fn result ->
      strategy_name = if is_atom(result.strategy), do: result.strategy, else: (result.strategy || "auto")
      "| #{strategy_name} | " <>
      "#{format_time(result.optimized_execution_time_ms)} | " <>
      "#{format_bytes(result.optimized_memory_bytes)} | " <>
      "#{format_percentage(result.speedup_percentage)} | " <>
      "#{format_percentage(result.memory_reduction_percentage)} |"
    end)
    
    header <> Enum.join(rows, "\n")
  end
  
  def generate_report(result) do
    # Handle single result from run_benchmark/3
    """
    ## EmberEx JIT Optimization Report
    
    ### Operator: #{result.operator_type}
    ### Strategy: #{format_strategy(result.strategy)}
    
    | Metric | Non-optimized | JIT-optimized | Improvement |
    |--------|--------------|--------------|------------|
    | Execution Time | #{format_time(result.standard_execution_time_ms)} | #{format_time(result.optimized_execution_time_ms)} | #{format_percentage(result.speedup_percentage)} |
    | Memory Usage | #{format_bytes(result.standard_memory_bytes)} | #{format_bytes(result.optimized_memory_bytes)} | #{format_percentage(result.memory_reduction_percentage)} |
    
    Benchmark ran with #{result.runs} iterations.
    """
  end
  
  # Helper functions
  
  defp calculate_percentage_improvement(standard, optimized) do
    case standard do
      0 -> 0.0
      _ -> (standard - optimized) / standard * 100
    end
  end
  
  defp get_operator_type(operator) do
    operator.__struct__
    |> Atom.to_string()
    |> String.split(".")
    |> List.last()
  end
  
  defp format_time(milliseconds) do
    cond do
      milliseconds < 1 -> "#{Float.round(milliseconds * 1000, 2)} µs"
      milliseconds < 1000 -> "#{Float.round(milliseconds, 2)} ms"
      true -> "#{Float.round(milliseconds / 1000, 2)} s"
    end
  end
  
  defp format_bytes(bytes) do
    cond do
      bytes < 1024 -> "#{bytes} B"
      bytes < 1024 * 1024 -> "#{Float.round(bytes / 1024, 2)} KB"
      bytes < 1024 * 1024 * 1024 -> "#{Float.round(bytes / 1024 / 1024, 2)} MB"
      true -> "#{Float.round(bytes / 1024 / 1024 / 1024, 2)} GB"
    end
  end
  
  defp format_percentage(percentage) do
    "#{Float.round(percentage, 2)}%"
  end
  
  # Helper function to safely format strategy values
  defp format_strategy(strategy) do
    cond do
      is_nil(strategy) -> "auto"
      is_atom(strategy) -> Atom.to_string(strategy)
      true -> strategy
    end
  end
  
  # Test operator creation helpers
  
  defp create_test_map_operator do
    EmberEx.Operators.MapOperator.new(fn inputs ->
      %{value: inputs.value * 2, text: String.upcase(inputs.text)}
    end)
  end
  
  defp create_test_sequence_operator do
    EmberEx.Operators.SequenceOperator.new([
      EmberEx.Operators.MapOperator.new(fn inputs -> %{value: inputs.value + 1} end),
      EmberEx.Operators.MapOperator.new(fn inputs -> %{value: inputs.value * 2} end),
      EmberEx.Operators.MapOperator.new(fn inputs -> %{value: inputs.value - 3} end)
    ])
  end
  
  defp create_test_parallel_operator do
    EmberEx.Operators.ParallelOperator.new([
      EmberEx.Operators.MapOperator.new(fn inputs -> %{value_doubled: inputs.value * 2} end),
      EmberEx.Operators.MapOperator.new(fn inputs -> %{value_squared: inputs.value * inputs.value} end),
      EmberEx.Operators.MapOperator.new(fn inputs -> %{text_upper: String.upcase(inputs.text)} end)
    ])
  end
  
  defp create_test_complex_operator do
    # Create a more complex operator graph with nested operators
    parallel_op1 = EmberEx.Operators.ParallelOperator.new([
      EmberEx.Operators.MapOperator.new(fn inputs -> %{value_a: inputs.value + 5} end),
      EmberEx.Operators.MapOperator.new(fn inputs -> %{value_b: inputs.value * 3} end)
    ])
    
    parallel_op2 = EmberEx.Operators.ParallelOperator.new([
      EmberEx.Operators.MapOperator.new(fn inputs -> %{value_c: inputs.value - 2} end),
      EmberEx.Operators.MapOperator.new(fn inputs -> %{value_d: inputs.value / 2} end)
    ])
    
    EmberEx.Operators.SequenceOperator.new([
      parallel_op1,
      EmberEx.Operators.MapOperator.new(fn inputs ->
        %{combined: inputs.value_a + inputs.value_b}
      end),
      parallel_op2,
      EmberEx.Operators.MapOperator.new(fn inputs ->
        %{final: inputs.combined + inputs.value_c + inputs.value_d}
      end)
    ])
  end
end
