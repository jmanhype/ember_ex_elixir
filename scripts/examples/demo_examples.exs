#!/usr/bin/env elixir

# This script creates simplified versions of each example
# that can run with the current EmberEx implementation

IO.puts("\n\n=== EmberEx Examples Demonstration ===")

# Define a simple operator implementation
defmodule DemoOperator do
  defstruct [:name, :callable]
  
  # Create a new operator with a callable function
  def new(callable, name \\ nil) do
    %__MODULE__{
      callable: callable,
      name: name
    }
  end
  
  # Call the operator with an input
  def call(%__MODULE__{callable: callable}, input) do
    callable.(input)
  end
end

# Mock operators for RAG example
defmodule RAGDemo do
  def run do
    IO.puts("\n--- RAG Example ---")
    
    # Create a simple RAG pipeline
    rag_op = DemoOperator.new(fn query ->
      # Mock documents for retrieval
      documents = [
        %{content: "Elixir is a functional programming language that runs on the BEAM virtual machine."},
        %{content: "Elixir was created by José Valim in 2011."}
      ]
      
      # Simple response based on query
      response = if String.contains?(query, "Elixir") do
        "Elixir is a functional programming language that runs on the BEAM virtual machine. It was created by José Valim in 2011."
      else
        "I don't have information about that."
      end
      
      # Return structured result
      %{
        query: query,
        documents: documents,
        response: response,
        is_verified: true
      }
    end)
    
    # Run the RAG pipeline
    result = DemoOperator.call(rag_op, "What is Elixir?")
    
    IO.puts("Query: What is Elixir?")
    IO.puts("Response: #{result.response}")
    IO.puts("Is verified: #{result.is_verified}")
    
    result
  end
end

# Mock operators for Structured Extraction
defmodule StructuredExtractionDemo do
  def run do
    IO.puts("\n--- Structured Extraction Example ---")
    
    # Create a simple extraction operator
    extractor = DemoOperator.new(fn resume_text ->
      # Mock extraction of resume data
      %{
        personal_info: %{
          name: "John Smith",
          title: "Software Engineer"
        },
        experience: [
          %{
            company: "Tech Company",
            position: "Senior Developer",
            period: "2018-Present",
            responsibilities: [
              "Implemented microservices architecture",
              "Led team of 5 developers",
              "Reduced system latency by 30%"
            ]
          },
          %{
            company: "Startup",
            position: "Junior Developer",
            period: "2015-2018",
            responsibilities: [
              "Full-stack development with React and Node.js",
              "Implemented CI/CD pipeline"
            ]
          }
        ],
        education: [
          %{
            institution: "University of Technology",
            degree: "Computer Science",
            period: "2011-2015",
            achievements: [
              "GPA: 3.8/4.0",
              "Thesis: \"Optimizing Database Performance\""
            ]
          }
        ],
        skills: ["JavaScript", "Python", "Java", "Elixir", "Docker", "Kubernetes", "Git"]
      }
    end)
    
    # Run the extractor
    resume_text = """
    John Smith
    Software Engineer

    EXPERIENCE
    Senior Developer at Tech Company (2018-Present)
    - Implemented microservices architecture
    - Led team of 5 developers
    - Reduced system latency by 30%

    Junior Developer at Startup (2015-2018)
    - Full-stack development with React and Node.js
    - Implemented CI/CD pipeline

    EDUCATION
    Computer Science, University of Technology (2011-2015)
    - GPA: 3.8/4.0
    - Thesis: "Optimizing Database Performance"

    SKILLS
    Programming: JavaScript, Python, Java, Elixir
    Tools: Docker, Kubernetes, Git
    """
    
    result = DemoOperator.call(extractor, resume_text)
    
    IO.puts("Resume extraction results:")
    IO.puts("Name: #{result.personal_info.name}")
    IO.puts("Title: #{result.personal_info.title}")
    IO.puts("Experience entries: #{length(result.experience)}")
    IO.puts("Education entries: #{length(result.education)}")
    IO.puts("Skills: #{Enum.join(result.skills, ", ")}")
    
    result
  end
end

# Mock operators for Ensemble Reasoning
defmodule EnsembleReasoningDemo do
  def run do
    IO.puts("\n--- Ensemble Reasoning Example ---")
    
    # Create a simple ensemble operator with majority voting
    majority_ensemble = DemoOperator.new(fn query ->
      # Mock responses from different models
      responses = case query do
        "What is the capital of France?" -> 
          ["Paris", "Paris", "Paris"]
        "When was the Eiffel Tower built?" -> 
          ["1889", "1887", "1889"]
        "Who wrote Romeo and Juliet?" ->
          ["William Shakespeare", "Shakespeare", "William Shakespeare"]
        _ ->
          ["Unknown", "Unknown", "I don't know"]
      end
      
      # Find the most common response
      most_common = responses
        |> Enum.frequencies()
        |> Enum.max_by(fn {_, count} -> count end)
        |> elem(0)
        
      # Calculate confidence
      confidence = Enum.count(responses, fn r -> r == most_common end) / length(responses)
      
      %{answer: most_common, confidence: confidence}
    end)
    
    # Create a simple ensemble operator with judge selection
    judge_ensemble = DemoOperator.new(fn query ->
      # For simplicity, just return a predefined answer with confidence
      case query do
        "What is the capital of France?" -> 
          %{answer: "Paris", confidence: 1.0}
        "When was the Eiffel Tower built?" -> 
          %{answer: "1889", confidence: 0.9}
        "Who wrote Romeo and Juliet?" ->
          %{answer: "William Shakespeare", confidence: 0.9} 
        _ ->
          %{answer: "I don't have enough information", confidence: 0.5}
      end
    end)
    
    # Run both ensemble types
    majority_result = DemoOperator.call(majority_ensemble, "What is the capital of France?")
    IO.puts("Query: What is the capital of France?")
    IO.puts("Majority vote answer: #{majority_result.answer}")
    IO.puts("Confidence: #{majority_result.confidence}")
    
    judge_result = DemoOperator.call(judge_ensemble, "When was the Eiffel Tower built?")
    IO.puts("\nQuery: When was the Eiffel Tower built?")
    IO.puts("Judge selection answer: #{judge_result.answer}")
    IO.puts("Confidence: #{judge_result.confidence}")
    
    {majority_result, judge_result}
  end
end

# Mock operators for Instructor Validation
defmodule InstructorValidationDemo do
  def run do
    IO.puts("\n--- Instructor Validation Example ---")
    
    # Create a simple analyzer operator
    analyzer = DemoOperator.new(fn review_text ->
      # Extract product details based on review text
      {product_name, rating, sentiment} = cond do
        String.contains?(review_text, "SmartWatch") -> 
          {"SmartWatch X", 4, "positive"}
        String.contains?(review_text, "Headphones") -> 
          {"XYZ Headphones", 4, "positive"}
        String.contains?(review_text, "Laptop") -> 
          {"UltraBook Pro", 3, "neutral"}
        true -> 
          {"Unknown Product", 3, "neutral"}
      end
      
      # Extract pros and cons
      pros = if String.contains?(review_text, "battery") do
        ["Long battery life"]
      else
        ["Good quality"]
      end
      
      cons = if String.contains?(review_text, "clunky") do
        ["Clunky interface"]
      else
        ["No significant issues"]
      end
      
      # Create structured output
      %{
        review: %{
          product_name: product_name,
          rating: rating,
          pros: pros,
          cons: cons,
          summary: "Overall #{if rating >= 4, do: "good", else: "decent"} product with some strengths and weaknesses",
          sentiment: sentiment
        },
        key_points: ["#{String.capitalize(sentiment)} user experience", "#{Enum.at(pros, 0)}"],
        improvement_suggestions: ["Improve #{String.downcase(Enum.at(cons, 0))}"],
        audience: "Tech enthusiasts looking for quality #{if String.contains?(product_name, "Watch"), do: "wearables", else: "electronics"}"
      }
    end)
    
    # Run the analyzer
    review_text = "The SmartWatch X is great. Battery lasts 3 days and tracking is accurate. The app is a bit clunky though. 4/5."
    result = DemoOperator.call(analyzer, review_text)
    
    IO.puts("Review: #{review_text}")
    IO.puts("Extracted product: #{result.review.product_name}")
    IO.puts("Rating: #{result.review.rating}/5")
    IO.puts("Sentiment: #{result.review.sentiment}")
    IO.puts("Key points: #{inspect(result.key_points)}")
    IO.puts("Improvement suggestions: #{inspect(result.improvement_suggestions)}")
    IO.puts("Target audience: #{result.audience}")
    
    result
  end
end

# Run all demos
RAGDemo.run()
StructuredExtractionDemo.run()
EnsembleReasoningDemo.run()
InstructorValidationDemo.run()
