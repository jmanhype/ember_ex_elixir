# EmberEx

EmberEx is an Elixir port of the [Ember framework](https://github.com/pyember/ember), providing a functional programming approach to building AI applications with language models.

## Architecture

EmberEx is built around several key architectural components:

1. **Operator System**: The fundamental computational unit in EmberEx, implementing a functional programming approach with strong typing, validation, and composition patterns.
2. **Model System**: A clean interface for interacting with language models from various providers, supporting multiple invocation patterns.
3. **Specification Pattern**: Separates input/output contracts from implementation logic.
4. **XCS (Execution Engine)**: Provides graph-based execution with parallelization capabilities.

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

## Benefits of the Elixir Port

- **Concurrency and Scalability**: Elixir's BEAM VM provides lightweight processes that can handle millions of concurrent operations efficiently.
- **Fault Tolerance**: Elixir's "let it crash" philosophy and supervisor trees make EmberEx more resilient.
- **Low Latency**: Elixir's soft real-time capabilities reduce response times for operations.
- **Distributed Computing**: Elixir's distributed nature allows EmberEx to easily scale across multiple nodes.
- **Hot Code Swapping**: The ability to update code without stopping the system is valuable for long-running AI services.

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

## License

This project is licensed under the MIT License - see the LICENSE file for details.
