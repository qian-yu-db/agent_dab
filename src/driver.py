# Databricks notebook source
# MAGIC %md
# MAGIC #Tool-calling Agent
# MAGIC
# MAGIC This is an auto-generated notebook created by an AI playground export. In this notebook, you will:
# MAGIC - Author a tool-calling [MLflow's `ResponsesAgent`](https://mlflow.org/docs/latest/api_reference/python_api/mlflow.pyfunc.html#mlflow.pyfunc.ResponsesAgent) that uses the OpenAI client
# MAGIC - Manually test the agent's output
# MAGIC - Evaluate the agent with Mosaic AI Agent Evaluation
# MAGIC - Log and deploy the agent
# MAGIC
# MAGIC This notebook should be run on serverless or a cluster with DBR<17.
# MAGIC
# MAGIC  **_NOTE:_**  This notebook uses the OpenAI SDK, but AI Agent Framework is compatible with any agent authoring framework, including LlamaIndex or LangGraph. To learn more, see the [Authoring Agents](https://docs.databricks.com/generative-ai/agent-framework/author-agent) Databricks documentation.
# MAGIC
# MAGIC ## Prerequisites
# MAGIC
# MAGIC - Address all `TODO`s in this notebook.

# COMMAND ----------

# MAGIC %pip install -U -qqqq backoff databricks-openai uv databricks-agents mlflow-skinny[databricks]
# MAGIC dbutils.library.restartPython()

# COMMAND ----------
dbutils.widgets.text("catalog_name", "fins_genai")
dbutils.widgets.text("schema_name", "agents")

# COMMAND ----------
catalog = dbutils.widgets.get("catalog_name")
schema = dbutils.widgets.get("schema_name")

# COMMAND ----------
# MAGIC %md
# MAGIC ## Read and update config.yaml
# COMMAND ----------
import yaml 

with open("config.yaml", "r") as f:
    config = yaml.safe_load(f)

databricks_config = config.get("databricks_configs", {})
print(f"current catalog: {databricks_config.get('catalog')}, schema: {databricks_config.get('schema')}")

databricks_config["catalog"] = catalog
databricks_config["schema"] = schema

print(f"updated catalog: {databricks_config.get('catalog')}, schema: {databricks_config.get('schema')}")

config["databricks_configs"] = databricks_config
with open("config.yaml", "w") as f:
    yaml.dump(config, f)

# COMMAND ----------
# MAGIC %run ./agent
# COMMAND ----------

AGENT.predict({"input": [{"role": "user", "content": "what is 4*3 in python"}]})

# COMMAND ----------

for chunk in AGENT.predict_stream(
    {"input": [{"role": "user", "content": "What is 4*3 in Python?"}]}
):
    print(chunk.model_dump(exclude_none=True))

# COMMAND ----------

# MAGIC %md
# MAGIC ### Log the `agent` as an MLflow model
# MAGIC Determine Databricks resources to specify for automatic auth passthrough at deployment time
# MAGIC - **TODO**: If your Unity Catalog Function queries a [vector search index](https://docs.databricks.com/generative-ai/agent-framework/unstructured-retrieval-tools.html) or leverages [external functions](https://docs.databricks.com/generative-ai/agent-framework/external-connection-tools.html), you need to include the dependent vector search index and UC connection objects, respectively, as resources. See [docs](https://docs.databricks.com/generative-ai/agent-framework/log-agent.html#specify-resources-for-automatic-authentication-passthrough) for more details.
# MAGIC
# MAGIC Log the agent as code from the `agent.py` file. See [MLflow - Models from Code](https://mlflow.org/docs/latest/models.html#models-from-code).

# COMMAND ----------

# Determine Databricks resources to specify for automatic auth passthrough at deployment time
import mlflow
import os
from mlflow.models.resources import DatabricksFunction, DatabricksServingEndpoint
from pkg_resources import get_distribution

resources = [DatabricksServingEndpoint(endpoint_name=LLM_ENDPOINT_NAME)]
for tool in VECTOR_SEARCH_TOOLS:
    resources.extend(tool.resources)

for tool_name in UC_TOOL_NAMES:
    resources.append(DatabricksFunction(function_name=tool_name))

input_example = {
    "input": [
        {
            "role": "user",
            "content": "Calculate the 15th Fibonacci number"
        }
    ]
}

with mlflow.start_run():
    logged_agent_info = mlflow.pyfunc.log_model(
        name="agent",
        python_model=os.path.join(os.getcwd(), "agent"),
        model_config=os.path.join(os.getcwd(), "config.yaml"),
        input_example=input_example,
        pip_requirements=[
            "databricks-openai",
            "backoff",
            f"databricks-connect=={get_distribution('databricks-connect').version}",
        ],
        resources=resources,
    )

# COMMAND ----------

# MAGIC %md
# MAGIC ## Register the model to Unity Catalog
# MAGIC
# MAGIC Update the `catalog`, `schema`, and `model_name` below to register the MLflow model to Unity Catalog.

# COMMAND ----------

mlflow.set_registry_uri("databricks-uc")

model_name = "agent_dab"
UC_MODEL_NAME = f"{catalog}.{schema}.{model_name}"

# register the model to UC
uc_registered_model_info = mlflow.register_model(
    model_uri=logged_agent_info.model_uri, name=UC_MODEL_NAME
)

# COMMAND ----------
# test deploy venv

mlflow.models.predict(
    model_uri=f"runs:/{logged_agent_info.run_id}/agent",
    input_data={"input": [{"role": "user", "content": "Hello!"}]},
    env_manager="uv",
)
# COMMAND ----------

# MAGIC %md
# MAGIC ## Deploy the agent

# COMMAND ----------

from databricks import agents
# NOTE: pass scale_to_zero=True to agents.deploy() to enable scale-to-zero for cost savings.
# This is not recommended for production workloads, as capacity is not guaranteed when scaled to zero.
# Scaled to zero endpoints may take extra time to respond when queried, while they scale back up.
agents.deploy(UC_MODEL_NAME, uc_registered_model_info.version, tags = {"endpointSource": "playground"})