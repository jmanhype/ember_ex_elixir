# EmberEx

EmberEx is an Elixir port of the [Ember framework](https://github.com/pyember/ember), providing a functional programming approach to building AI applications with language models. It focuses on composition, reusability, and performance optimization for AI workflows.

## Architecture

EmberEx is built around several key architectural components:

1. **Operator System**: The fundamental computational unit in EmberEx, implementing a functional programming approach with strong typing, validation, and composition patterns.
2. **Model System**: A clean interface for interacting with language models from various providers, supporting multiple invocation patterns.
3. **Specification Pattern**: Separates input/output contracts from implementation logic.
4. **XCS (Execution Engine)**: Provides graph-based execution with parallelization capabilities.
5. **JIT Optimization System**: Just-In-Time compilation and optimization for operators, with specialized strategies for language model operations.

## Installation

Add EmberEx to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:ember_ex, "~> 0.1.0"}
  ]
end
```

## Usage

### Basic Example

```elixir
# Create a simple operator that uppercases text
uppercase_op = EmberEx.Operators.MapOperator.new(&String.upcase/1, :text, :uppercase_text)

# Call the operator with inputs
result = EmberEx.Operators.Operator.call(uppercase_op, %{text: "hello world"})
# => %{uppercase_text: "HELLO WORLD"}
```

### Language Model Example

```elixir
# Create an LLM operator
llm_op = EmberEx.Operators.LLMOperator.new(
  "gpt-4o",
  "Translate the following text to French: {input}",
  :text,
  :french_text
)

# Call the operator with inputs
result = EmberEx.Operators.Operator.call(llm_op, %{text: "Hello, world!"})
# => %{french_text: "Bonjour, monde!"}
```

### Composing Operators

```elixir
# Create multiple operators
translate_op = EmberEx.Operators.LLMOperator.new(
  "gpt-4o",
  "Translate the following text to French: {input}",
  :text,
  :french_text
)

uppercase_op = EmberEx.Operators.MapOperator.new(&String.upcase/1, :french_text, :uppercase_french)

# Compose them in sequence
sequence_op = EmberEx.Operators.SequenceOperator.new([translate_op, uppercase_op])

# Call the sequence
result = EmberEx.Operators.Operator.call(sequence_op, %{text: "Hello, world!"})
# => %{text: "Hello, world!", french_text: "Bonjour, monde!", uppercase_french: "BONJOUR, MONDE!"}
```

### Parallel Execution

```elixir
# Create multiple operators
translate_to_french = EmberEx.Operators.LLMOperator.new(
  "gpt-4o",
  "Translate the following text to French: {input}",
  :text,
  :french_text
)

translate_to_spanish = EmberEx.Operators.LLMOperator.new(
  "gpt-4o",
  "Translate the following text to Spanish: {input}",
  :text,
  :spanish_text
)

# Execute them in parallel
parallel_op = EmberEx.Operators.ParallelOperator.new([translate_to_french, translate_to_spanish])

# Call the parallel operator
result = EmberEx.Operators.Operator.call(parallel_op, %{text: "Hello, world!"})
# => %{text: "Hello, world!", french_text: "Bonjour, monde!", spanish_text: "¡Hola, mundo!"}
```

### Graph-based Execution

```elixir
# Define a graph of operators
graph = %{
  "translate_to_french" => %{
    operator: EmberEx.Operators.LLMOperator.new(
      "gpt-4o",
      "Translate the following text to French: {input}",
      :text,
      :french_text
    ),
    inputs: %{text: "text"},
    dependencies: []
  },
  "uppercase_french" => %{
    operator: EmberEx.Operators.MapOperator.new(&String.upcase/1, :french_text, :uppercase_french),
    inputs: %{french_text: "translate_to_french.french_text"},
    dependencies: ["translate_to_french"]
  }
}

# Execute the graph
result = EmberEx.XCS.ExecutionEngine.execute(graph, %{text: "Hello, world!"})
# => %{
#      "text" => "Hello, world!",
#      "translate_to_french.french_text" => "Bonjour, monde!",
#      "uppercase_french.uppercase_french" => "BONJOUR, MONDE!"
#    }
```

## JIT Optimization System

EmberEx features a sophisticated Just-In-Time (JIT) optimization system that automatically improves the performance of operator chains:

### Optimization Strategies

- **Trace-based JIT**: Analyzes execution patterns to optimize frequently used paths
- **Structural JIT**: Optimizes operators based on their structure without requiring execution
- **Enhanced JIT**: Combines structural and trace-based approaches for maximum performance
- **LLM-specialized JIT**: Optimizes language model operations with special attention to:
  - Function composition optimization (pre/post-processing around LLM calls)
  - Partial caching of deterministic components with intelligent signature-based keys
  - Preservation of stochastic behavior where needed through content-aware detection
  - Parallel processing with adaptive batch sizing and similarity grouping

### Usage Example

```elixir
# Optimize an operator using the JIT system
optimized_op = EmberEx.XCS.JIT.Core.jit(complex_operator)

# Optimize with LLM-specific strategy
llm_optimized_op = EmberEx.XCS.JIT.Core.jit(
  llm_operator,
  mode: :llm,
  optimize_prompt: true,
  optimize_postprocess: true,
  preserve_llm_call: true
)

# Run the optimized operator
result = EmberEx.Operators.Operator.call(optimized_op, inputs)
```
## Benefits of the Elixir Port

- **Concurrency and Scalability**: Elixir's BEAM VM provides lightweight processes that can handle millions of concurrent operations efficiently.
- **Fault Tolerance**: Elixir's "let it crash" philosophy and supervisor trees make EmberEx more resilient.
- **Low Latency**: Elixir's soft real-time capabilities reduce response times for operations.
- **Distributed Computing**: Elixir's distributed nature allows EmberEx to easily scale across multiple nodes.
- **Hot Code Swapping**: The ability to update code without stopping the system is valuable for long-running AI services.
- **JIT Optimization**: Automatic performance improvements for operator chains, with special handling for LLM operations.

## Development

### Prerequisites

- Elixir 1.14 or later
- Erlang/OTP 25 or later

### Setup

```bash
# Clone the repository
git clone https://github.com/yourusername/ember_ex.git
cd ember_ex

# Install dependencies
mix deps.get

# Run tests
mix test
```

## Advanced Features

### Recent Enhancements

**April 2025 Updates**:

- **Execution Engine Enhancement**: Improved handling of specialized LLM graphs that preserves stochastic operations while optimizing surrounding deterministic functions
- **Analysis Overhead Reduction**: Profiling infrastructure to identify and minimize computational costs during optimization phases
- **Intelligent Partial Caching**: Smart caching strategies that identify cacheable components based on determinism analysis
- **Real-world LLM Patterns**: Enhanced detection of prompt templates, result parsers, and actual LLM operations in complex pipelines
- **Adaptive Batch Processing**: Dynamic batch sizing that balances parallelism with overhead costs

### Benchmarking

EmberEx includes comprehensive benchmarking tools to measure and compare the performance of different JIT optimization strategies. Example benchmark scripts are located in the `scripts/` directory:

```bash
# Run basic JIT benchmark
mix run scripts/jit_benchmark_example.exs

# Run LLM-focused benchmark
mix run scripts/llm_jit_benchmark.exs

# Run specialized LLM optimization benchmark
mix run scripts/llm_specialized_benchmark.exs

# Test with real-world LLM patterns
mix run scripts/real_world_llm_benchmark.exs
```

### Metrics and Monitoring

The framework includes built-in metrics collection and Prometheus integration for monitoring:

```elixir
# Get JIT cache statistics
EmberEx.XCS.JIT.Cache.get_stats()
# => %{hits: 350, misses: 42, hit_rate: 89.3, total_calls: 392}
```
## License

This project is licensed under the MIT License - see the LICENSE file for details.
