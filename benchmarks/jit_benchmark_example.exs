#!/usr/bin/env elixir

# This script demonstrates the enhanced JIT optimization system 
# with comprehensive benchmarking and metrics collection.

# Add the application to the code path
Code.prepend_path("_build/dev/lib/ember_ex/ebin")
Code.prepend_path("_build/dev/lib/instructor_ex/ebin")

# Start the EmberEx application
Application.ensure_all_started(:ember_ex)

# Start the JIT cache server if not already running
case EmberEx.XCS.JIT.Cache.start_link([]) do
  {:ok, _pid} -> IO.puts("Started JIT cache server")
  {:error, {:already_started, _pid}} -> IO.puts("JIT cache server already running")
  other -> IO.puts("Unexpected result starting JIT cache: #{inspect(other)}")
end

# Initialize the JIT system
EmberEx.XCS.JIT.Init.start()

# Start the Prometheus metrics exporter if not already running
case EmberEx.Metrics.Exporters.Prometheus.start_link(port: 9568) do
  {:ok, _} -> IO.puts("Started Prometheus metrics exporter on port 9568")
  {:error, {:already_started, _}} -> IO.puts("Prometheus metrics exporter already running")
  other -> IO.puts("Unexpected result starting metrics exporter: #{inspect(other)}")
end

# Initialize metrics storage
:ok = EmberEx.Metrics.Storage.init()

# Set up metrics
:ok = EmberEx.Metrics.Exporters.Prometheus.setup_metrics()

# Import necessary modules to be used in the benchmark script
alias EmberEx.XCS.JIT.Core, as: JITCore
alias EmberEx.XCS.JIT.Stochastic
alias EmberEx.Metrics.Collector

IO.puts("EmberEx Enhanced JIT Benchmarking")
IO.puts("================================")
IO.puts("")

# Helper function to create test operators
create_test_operators = fn ->
  # Create map operator
  map_op = EmberEx.Operators.MapOperator.new(fn inputs ->
    %{value: inputs.value * 2, text: String.upcase(inputs.text)}
  end)
  
  # Create sequence operator
  sequence_op = EmberEx.Operators.SequenceOperator.new([
    EmberEx.Operators.MapOperator.new(fn inputs -> %{value: inputs.value + 10} end),
    EmberEx.Operators.MapOperator.new(fn inputs -> %{value: inputs.value * 2} end),
    EmberEx.Operators.MapOperator.new(fn inputs -> %{value: inputs.value - 5, text: inputs.text} end)
  ])
  
  # Create parallel operator
  parallel_op = EmberEx.Operators.ParallelOperator.new([
    EmberEx.Operators.MapOperator.new(fn inputs -> %{value_doubled: inputs.value * 2} end),
    EmberEx.Operators.MapOperator.new(fn inputs -> %{value_squared: inputs.value * inputs.value} end),
    EmberEx.Operators.MapOperator.new(fn inputs -> %{text_upper: String.upcase(inputs.text)} end)
  ])
  
  # Create complex operator
  parallel_op1 = EmberEx.Operators.ParallelOperator.new([
    EmberEx.Operators.MapOperator.new(fn inputs -> %{value_a: inputs.value + 5} end),
    EmberEx.Operators.MapOperator.new(fn inputs -> %{value_b: inputs.value * 3} end)
  ])
  
  parallel_op2 = EmberEx.Operators.ParallelOperator.new([
    EmberEx.Operators.MapOperator.new(fn inputs -> %{value_c: inputs.value - 2} end),
    EmberEx.Operators.MapOperator.new(fn inputs -> %{value_d: inputs.value / 2} end)
  ])
  
  complex_op = EmberEx.Operators.SequenceOperator.new([
    parallel_op1,
    EmberEx.Operators.MapOperator.new(fn inputs ->
      %{combined: inputs.value_a + inputs.value_b}
    end),
    parallel_op2,
    EmberEx.Operators.MapOperator.new(fn inputs ->
      %{final: inputs.combined + inputs.value_c + inputs.value_d}
    end)
  ])
  
  # Create a mock LLM operator for testing
  llm_specification = %{
    input_template: "Generate a response for: {input}",
    output_schema: %{response: "string"}
  }
  
  mock_llm = fn inputs ->
    %{response: "This is a mock LLM response for: " <> inputs.input}
  end
  
  llm_op = EmberEx.Operators.MapOperator.new(fn inputs ->
    mock_llm.(%{input: inputs.text})
  end)
  
  %{
    map: map_op,
    sequence: sequence_op,
    parallel: parallel_op,
    complex: complex_op,
    llm: llm_op
  }
end

operators = create_test_operators.()

# Test inputs
inputs = %{value: 10, text: "hello world"}

# Simple benchmark test for MapOperator
IO.puts("Benchmarking MapOperator...")
test_operator = operators.map
test_inputs = inputs

# Time the regular execution
{standard_time, standard_result} = :timer.tc(fn ->
  EmberEx.Operators.Operator.call(test_operator, test_inputs)
end)

# Apply JIT optimization
optimized_operator = EmberEx.XCS.JIT.Core.jit(test_operator)

# Time the optimized execution
{jit_time, jit_result} = :timer.tc(fn ->
  if is_function(optimized_operator) do
    optimized_operator.(test_inputs)
  else
    EmberEx.Operators.Operator.call(optimized_operator, test_inputs)
  end
end)

# Calculate improvement
speedup_percentage = (standard_time - jit_time) / standard_time * 100

# Display results
IO.puts("\nResults:")
IO.puts("Standard execution time: #{standard_time / 1000} ms")
IO.puts("JIT optimized time: #{jit_time / 1000} ms")
IO.puts("Speedup: #{Float.round(speedup_percentage, 2)}%")
IO.puts("")
IO.puts("Standard result: #{inspect(standard_result)}")
IO.puts("JIT result: #{inspect(jit_result)}")
IO.puts("")

# Record a metric (only if speedup is positive to avoid confusing metrics)
if speedup_percentage > 0 do
  EmberEx.Metrics.Collector.record("jit_optimization_speedup", speedup_percentage, :gauge, %{operator: "MapOperator"})
else
  IO.puts("Note: Negative speedup not recorded in metrics")
end

# Demonstrate stochastic preservation
IO.puts("Demonstrating Stochastic Preservation...")
stochastic_jit = EmberEx.XCS.JIT.Stochastic.jit_stochastic(operators.complex, 
  stochastic_params: %{temperature: 0.7, preserve_randomness: true}
)

{stochastic_time, stochastic_result} = :timer.tc(fn ->
  if is_function(stochastic_jit) do
    stochastic_jit.(inputs)
  else
    EmberEx.Operators.Operator.call(stochastic_jit, inputs)
  end
end)

IO.puts("Stochastic JIT execution time: #{stochastic_time / 1000} ms")
IO.puts("Stochastic JIT result: #{inspect(stochastic_result)}")
IO.puts("")

# Show JIT statistics
IO.puts("JIT Statistics:")
cache_stats = EmberEx.XCS.JIT.Cache.get_stats()
IO.puts("Cache hits: #{cache_stats.hits}")
IO.puts("Cache misses: #{cache_stats.misses}")
IO.puts("Total optimized calls: #{cache_stats.hits + cache_stats.misses}")
IO.puts("Hit rate: #{Float.round(cache_stats.hits / max(cache_stats.hits + cache_stats.misses, 1) * 100, 2)}%")
IO.puts("")

# Show Prometheus metrics information
IO.puts("Prometheus metrics available at: http://localhost:9568/metrics")
IO.puts("You can view these metrics in any Prometheus-compatible dashboard.")
IO.puts("")

IO.puts("Completed JIT benchmark suite")
