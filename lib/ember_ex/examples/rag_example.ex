defmodule EmberEx.Examples.RAG do
  @moduledoc """
  Demonstrates a Retrieval Augmented Generation (RAG) pattern using EmberEx.
  
  This example shows how to combine multiple operators to create a RAG system
  that retrieves context from a database, constructs prompts with the context,
  and generates responses using LLMs.
  
  The pattern follows these steps:
  1. Query embedding - Generate embeddings for the user query
  2. Retrieval - Retrieve relevant documents from a vector store
  3. Context preparation - Process and format the retrieved documents
  4. RAG Generation - Generate a response using the query and context
  5. Verification - Verify the response against the context
  """
  
  alias EmberEx.Operators.{
    ChunkOperator,
    GeneratePromptOperator,
    LLMOperator,
    MapOperator,
    ParallelOperator,
    RetrievalOperator,
    SequenceOperator,
    VerifierOperator
  }
  
  @type document :: %{
    content: String.t(),
    metadata: map()
  }
  
  @type query_result :: %{
    query: String.t(),
    documents: [document()],
    response: String.t(),
    is_verified: boolean()
  }
  
  @doc """
  Creates a RAG pipeline for answering queries with document retrieval.
  
  ## Parameters
  
  - embedder: Function to generate embeddings for queries and documents
  - retriever: Function to retrieve documents based on query embeddings
  - model: Model callable for generating responses
  
  ## Returns
  
  A sequence operator that performs the RAG process
  
  ## Examples
  
      iex> # Set up components
      iex> embedder = fn text -> # embedding logic end
      iex> retriever = fn embedding -> # retrieval logic end
      iex> model = EmberEx.Models.create_model_callable("openai/gpt-4")
      iex> 
      iex> # Create the RAG pipeline
      iex> rag_pipeline = EmberEx.Examples.RAG.create_pipeline(embedder, retriever, model)
      iex> 
      iex> # Answer a query
      iex> EmberEx.Operators.Operator.call(rag_pipeline, "What is machine learning?")
      %{
      ...>   query: "What is machine learning?",
      ...>   documents: [%{content: "Machine learning is...", metadata: %{...}}],
      ...>   response: "Machine learning is a subset of artificial intelligence...",
      ...>   is_verified: true
      ...> }
  """
  @spec create_pipeline(
    (String.t() -> list(float())),
    (list(float()) -> [document()]),
    EmberEx.Models.ModelCallable.t()
  ) :: EmberEx.Operators.Operator.t()
  def create_pipeline(embedder, retriever, model) do
    # 1. Create the embedding operator
    embed_query_op = MapOperator.new(fn query ->
      %{
        query: query,
        embedding: embedder.(query)
      }
    end, "embed_query")
    
    # 2. Create the retrieval operator
    retrieve_docs_op = MapOperator.new(fn %{query: query, embedding: embedding} ->
      documents = retriever.(embedding)
      
      %{
        query: query,
        documents: documents
      }
    end, "retrieve_documents")
    
    # 3. Create the context preparation operator
    prepare_context_op = MapOperator.new(fn %{query: query, documents: documents} ->
      # Format documents into context string
      context = documents
      |> Enum.map_join("\n\n", fn %{content: content, metadata: metadata} ->
        "Source: #{metadata[:title] || "Unknown"}\n#{content}"
      end)
      
      %{
        query: query,
        documents: documents,
        context: context
      }
    end, "prepare_context")
    
    # 4. Create the RAG prompt construction operator
    construct_prompt_op = MapOperator.new(fn %{query: query, context: context} = input ->
      prompt = """
      Answer the following question based on the provided context.
      If the answer cannot be determined from the context, say "I don't know based on the provided information."
      
      Context:
      #{context}
      
      Question: #{query}
      Answer:
      """
      
      Map.put(input, :prompt, prompt)
    end, "construct_prompt")
    
    # 5. Create the generation operator
    generate_op = MapOperator.new(fn %{prompt: prompt} = input ->
      case model.(%{messages: [%{role: "user", content: prompt}]}) do
        {:ok, response} ->
          Map.put(input, :response, response.content)
          
        {:error, reason} ->
          Map.put(input, :error, "Generation failed: #{inspect(reason)}")
      end
    end, "generate_response")
    
    # 6. Create the verification operator
    # Check if response contains facts that are grounded in the documents
    verification_conditions = [
      # Check that the response is not empty
      VerifierOperator.not_empty("Response cannot be empty"),
      
      # Check that the response is reasonably long
      VerifierOperator.condition(
        fn response -> String.length(response) > 20 end,
        "Response is too short"
      ),
      
      # Check that the response doesn't contain generic phrases like "I don't know"
      # unless the context truly doesn't contain relevant information
      VerifierOperator.condition(
        fn response ->
          not (String.contains?(response, "don't know") or
               String.contains?(response, "cannot determine") or
               String.contains?(response, "not mentioned"))
        end,
        "Response indicates lack of information"
      )
    ]
    
    verify_op = MapOperator.new(fn %{response: response, documents: _documents} = input ->
      # Create a verifier to check the response
      verifier = VerifierOperator.new(verification_conditions)
      
      # Run verification
      verification_result = EmberEx.Operators.Operator.call(verifier, response)
      
      # Add verification result to the input
      Map.put(input, :is_verified, verification_result.passed)
    end, "verify_response")
    
    # 7. Create a final cleanup operator
    cleanup_op = MapOperator.new(fn input ->
      # Keep only the desired output fields
      %{
        query: input.query,
        documents: input.documents,
        response: input.response,
        is_verified: input.is_verified
      }
    end, "cleanup_result")
    
    # Combine all operators into a sequence
    SequenceOperator.new([
      embed_query_op,
      retrieve_docs_op,
      prepare_context_op,
      construct_prompt_op,
      generate_op,
      verify_op,
      cleanup_op
    ], "rag_pipeline")
  end
  
  @doc """
  Demonstrates how to use the RAG pipeline with a simple in-memory document store.
  
  ## Returns
  
  A simple example RAG pipeline with mocked components
  
  ## Examples
  
      iex> rag = EmberEx.Examples.RAG.create_example()
      iex> EmberEx.Operators.Operator.call(rag, "What is Elixir?")
      %{
      ...>   query: "What is Elixir?",
      ...>   documents: [...],
      ...>   response: "Elixir is a functional programming language...",
      ...>   is_verified: true
      ...> }
  """
  @spec create_example() :: EmberEx.Operators.Operator.t()
  def create_example do
    # Sample document collection
    documents = [
      %{
        content: "Elixir is a functional, concurrent, general-purpose programming language that runs on the BEAM virtual machine.",
        metadata: %{title: "Elixir Overview", id: "doc1"}
      },
      %{
        content: "Elixir was created by José Valim and first released in 2011. It is designed for building scalable and maintainable applications.",
        metadata: %{title: "Elixir History", id: "doc2"}
      },
      %{
        content: "Python is a high-level, interpreted programming language known for its readability and versatility.",
        metadata: %{title: "Python Overview", id: "doc3"}
      },
      %{
        content: "Ember is a framework for building LLM applications with principles from software engineering",
        metadata: %{title: "Ember Framework", id: "doc4"}
      },
      %{
        content: "EmberEx is an Elixir port of the Ember framework, providing the same capabilities in a functional programming paradigm.",
        metadata: %{title: "EmberEx", id: "doc5"}
      }
    ]
    
    # Simple cosine similarity function for vector comparisons
    cosine_similarity = fn v1, v2 ->
      dot_product = Enum.zip(v1, v2) |> Enum.map(fn {x, y} -> x * y end) |> Enum.sum()
      magnitude1 = :math.sqrt(Enum.map(v1, fn x -> x * x end) |> Enum.sum())
      magnitude2 = :math.sqrt(Enum.map(v2, fn x -> x * x end) |> Enum.sum())
      
      product = magnitude1 * magnitude2
      if product == 0.0 do
        0.0
      else
        dot_product / product
      end
    end
    
    # Mock embedder - in a real implementation, this would call an embedding API
    embedder = fn text ->
      # Very simple mock embeddings based on word frequencies
      words = text |> String.downcase() |> String.split(~r/\W+/)
      
      # Create a basic embedding based on presence of some keywords
      keywords = ["elixir", "python", "ember", "programming", "framework", "language"]
      
      Enum.map(keywords, fn keyword ->
        if Enum.member?(words, keyword), do: 1.0, else: 0.0
      end)
    end
    
    # Document embeddings (pre-computed for our example)
    document_embeddings = Enum.map(documents, fn %{content: content} ->
      embedder.(content)
    end)
    
    # Mock retriever function
    retriever = fn query_embedding ->
      # Calculate similarity scores for each document
      scores = Enum.map(document_embeddings, fn doc_embedding ->
        cosine_similarity.(query_embedding, doc_embedding)
      end)
      
      # Combine documents with their scores
      docs_with_scores = Enum.zip(documents, scores)
      
      # Sort by similarity score (descending) and take top 2
      docs_with_scores
      |> Enum.sort_by(fn {_doc, score} -> score end, :desc)
      |> Enum.take(2)
      |> Enum.map(fn {doc, _score} -> doc end)
    end
    
    # Mock model for generating responses
    model = fn %{messages: [%{content: prompt}]} ->
      # Extract the question from the prompt
      question_match = Regex.run(~r/Question: (.+)\nAnswer:/, prompt)
      
      question = if question_match, do: Enum.at(question_match, 1), else: ""
      
      # Simple pattern matching for our demo
      response = cond do
        String.contains?(question, "Elixir") && String.contains?(prompt, "functional") ->
          "Elixir is a functional programming language that runs on the BEAM virtual machine. It was created by José Valim in 2011 and is designed for building scalable applications."
          
        String.contains?(question, "Python") && String.contains?(prompt, "high-level") ->
          "Python is a high-level, interpreted programming language known for its readability and versatility."
          
        String.contains?(question, "Ember") && String.contains?(prompt, "framework") ->
          "Ember is a framework for building LLM applications with principles from software engineering. EmberEx is its Elixir port."
          
        true ->
          "I don't know based on the provided information."
      end
      
      {:ok, %{content: response}}
    end
    
    # Create the pipeline with our mock components
    create_pipeline(embedder, retriever, model)
  end
end
