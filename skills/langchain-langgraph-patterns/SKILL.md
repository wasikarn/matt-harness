---
name: langchain-langgraph-patterns
description: "LangChain and LangGraph patterns: StateGraph agents, checkpointing, human-in-the-loop, tool calling, streaming, Pinecone RAG, and LangSmith tracing."
metadata:
  origin: kbg
  tathep_projects:
    - tathep-ai-agent-python
---

# LangChain / LangGraph Patterns

## When to Use Graph vs Chain

- **LangGraph `StateGraph`** — agents with branching, looping, or conditional routing. Use when the LLM decides what to do next.
- **LangChain LCEL chains** — deterministic pipelines. Use when the flow is fixed (prompt → model → parser).

## StateGraph — Agent Graphs

```python
from langgraph.graph import StateGraph, END
from langgraph.graph.message import add_messages
from typing import Annotated
from typing_extensions import TypedDict

class State(TypedDict):
    messages: Annotated[list, add_messages]  # Annotated reducer merges lists
    user_id: str

def call_model(state: State):
    response = model.invoke(state["messages"])
    return {"messages": [response]}

def should_continue(state: State):
    last = state["messages"][-1]
    return "tools" if last.tool_calls else END

graph = (
    StateGraph(State)
    .add_node("agent", call_model)
    .add_node("tools", tool_node)
    .add_edge("__start__", "agent")
    .add_conditional_edges("agent", should_continue, {"tools": "tools", END: END})
    .add_edge("tools", "agent")
    .compile(checkpointer=MemorySaver())
)
```

## State Design

Use `Annotated` reducers for fields that accumulate. Without a reducer, nodes overwrite the field:

```python
from operator import add

class State(TypedDict):
    messages: Annotated[list, add_messages]   # merges (deduplicates by message id)
    retrieved_docs: Annotated[list, add]      # plain list concat
    current_step: str                          # overwritten by each node
    errors: Annotated[list, add]
```

Never put mutable state (e.g., DB sessions) in `State`. State must be serializable for checkpointing.

## Checkpointing

Checkpointers enable: persistence across sessions, time-travel debugging, human-in-the-loop.

```python
from langgraph.checkpoint.postgres import PostgresSaver
from langgraph.checkpoint.memory import MemorySaver

# Dev
checkpointer = MemorySaver()

# Prod
with PostgresSaver.from_conn_string(DATABASE_URL) as checkpointer:
    checkpointer.setup()  # create tables once
    graph = builder.compile(checkpointer=checkpointer)

# Thread = conversation session
config = {"configurable": {"thread_id": "user-123-session-456"}}
result = graph.invoke({"messages": [HumanMessage("hello")]}, config=config)

# Resume the same thread
result = graph.invoke({"messages": [HumanMessage("continue")]}, config=config)
```

## Human-in-the-Loop

```python
from langgraph.types import interrupt

def review_node(state: State):
    # Pause and wait for human input
    approval = interrupt({
        "action": state["proposed_action"],
        "message": "Approve this action?",
    })
    if not approval["approved"]:
        return {"messages": [SystemMessage("Action cancelled by user")]}
    return execute_action(state)

# Resume after human responds
graph.invoke(Command(resume={"approved": True}), config=config)
```

## Tool Calling

```python
from langchain_core.tools import tool

@tool
def search_knowledge_base(query: str) -> str:
    """Search the internal knowledge base. Use when user asks about company policies."""
    return vector_store.similarity_search(query, k=3)

@tool
def create_ticket(title: str, description: str, priority: str) -> dict:
    """Create a support ticket. priority must be 'low', 'medium', or 'high'."""
    return ticket_system.create(title=title, description=description, priority=priority)

# Bind tools to model
model_with_tools = ChatOpenAI(model="gpt-4o").bind_tools([search_knowledge_base, create_ticket])

# ToolNode executes tools automatically
from langgraph.prebuilt import ToolNode
tool_node = ToolNode([search_knowledge_base, create_ticket])
```

## Streaming

```python
# Stream tokens
async for chunk in graph.astream(input, config=config, stream_mode="values"):
    print(chunk)

# Stream events (typed per-node)
async for event in graph.astream_events(input, config=config, version="v2"):
    if event["event"] == "on_chat_model_stream":
        print(event["data"]["chunk"].content, end="")
    elif event["event"] == "on_tool_end":
        print(f"Tool result: {event['data']['output']}")
```

## Pinecone RAG

```python
from langchain_pinecone import PineconeVectorStore
from langchain_openai import OpenAIEmbeddings

embeddings = OpenAIEmbeddings(model="text-embedding-3-small")
vector_store = PineconeVectorStore(index_name="my-index", embedding=embeddings)

# Upsert
vector_store.add_documents(documents, ids=[doc.metadata["id"] for doc in documents])

# Retrieve
retriever = vector_store.as_retriever(search_kwargs={"k": 5, "filter": {"source": "policy"}})
docs = retriever.invoke("vacation policy")

# In a graph node
def retrieve(state: State):
    docs = retriever.invoke(state["messages"][-1].content)
    return {"retrieved_docs": docs}
```

## LangSmith Tracing

```bash
LANGCHAIN_TRACING_V2=true
LANGCHAIN_API_KEY=ls__...
LANGCHAIN_PROJECT=tathep-ai-agent
```

No code changes needed — tracing is automatic when env vars are set. For custom spans:

```python
from langsmith import traceable

@traceable(name="custom-retrieval", run_type="retriever")
def my_retrieval(query: str) -> list:
    return vector_store.similarity_search(query)
```

## Common Pitfalls

- **`add_messages` reducer** — deduplicates by `message.id`. If you generate messages without IDs, LangGraph assigns them. Never manually set duplicate IDs.
- **`interrupt` requires checkpointer** — graphs compiled without a checkpointer cannot use `interrupt()`. Always compile with `checkpointer=` in prod.
- **Thread ID scope** — all nodes in one `invoke()` share the same thread. Different users MUST use different `thread_id`s.
- **Tool schema from docstring** — `@tool` extracts the JSON schema from the function signature and docstring. Missing or vague docstrings produce bad tool descriptions for the LLM.
- **Streaming vs async** — `graph.stream()` is sync; `graph.astream()` is async. In FastAPI/async contexts, always use the async variants.
- **`State` must be serializable** — checkpointers serialize state via JSON/pickle. Don't put raw DB connections, file handles, or unserializable objects in `State`.
