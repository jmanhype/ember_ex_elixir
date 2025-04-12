#!/usr/bin/env elixir

# This script demonstrates the JIT optimization system in EmberEx.
# It shows how operators can be optimized at runtime using the JIT compiler.

# Add the application to the code path
Code.prepend_path("_build/dev/lib/ember_ex/ebin")
Code.prepend_path("_build/dev/lib/instructor_ex/ebin")

# Start the EmberEx application
Application.ensure_all_started(:ember_ex)

# Explicitly start the JIT cache server
{:ok, _pid} = EmberEx.XCS.JIT.Cache.start_link([])

# Initialize the JIT system
EmberEx.XCS.JIT.Init.start()

alias EmberEx.Operator
alias EmberEx.Operators.{MapOperator}
alias EmberEx.XCS.JIT.Core, as: JIT

IO.puts("EmberEx JIT Optimization Example")
IO.puts("===============================\n")

# Define a simple map operator that doubles a number
double_op = MapOperator.new(fn inputs -> %{value: inputs.value * 2} end)

# Test input is a map with a value key
input = %{value: 10}

# Run the operator without JIT optimization
IO.puts("Running without JIT optimization...")
start_time = System.monotonic_time(:millisecond)
result = EmberEx.Operators.Operator.call(double_op, input)
end_time = System.monotonic_time(:millisecond)
elapsed = end_time - start_time

IO.puts("Input:")
IO.inspect(input)
IO.puts("Result:")
IO.inspect(result)
IO.puts("Time: #{elapsed} ms\n")

# Apply JIT optimization
IO.puts("Applying JIT optimization...")
optimized_op = JIT.jit(double_op)

# Run with JIT optimization
IO.puts("Running with JIT optimization...")
start_time = System.monotonic_time(:millisecond)
# If optimized_op is a function, call it normally, otherwise use Operator.call
optimized_result = if is_function(optimized_op) do
  optimized_op.(input)
else
  EmberEx.Operators.Operator.call(optimized_op, input)
end
end_time = System.monotonic_time(:millisecond)
optimized_elapsed = end_time - start_time

IO.puts("Input:")
IO.inspect(input)
IO.puts("Result:")
IO.inspect(optimized_result)
IO.puts("Time: #{optimized_elapsed} ms\n")

# Compare results
speedup = (elapsed - optimized_elapsed) / elapsed * 100
IO.puts("Performance improvement: #{Float.round(speedup, 2)}%")

# Show JIT statistics
IO.puts("\nJIT Statistics:")
IO.inspect(JIT.get_jit_stats(), pretty: true)
