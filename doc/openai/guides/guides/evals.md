Evaluating model performance
============================

Test and improve model outputs through evaluations.

Evaluations (often called **evals**) test model outputs to ensure they meet style and content criteria that you specify. Writing evals to understand how your LLM applications are performing against your expectations, especially when upgrading or trying new models, is an essential component to building reliable applications.

In this guide, we will focus on **configuring evals programmatically using the [Evals API](/docs/api-reference/evals)**. If you prefer, you can also configure evals [in the OpenAI dashboard](/evaluations).

Broadly, there are three steps to build and run evals for your LLM application.

1.  Describe the task to be done as an eval
2.  Run your eval with test inputs (a prompt and input data)
3.  Analyze the results, then iterate and improve on your prompt

This process is somewhat similar to behavior-driven development (BDD), where you begin by specifying how the system should behave before implementing and testing the system. Let's see how we would complete each of the steps above using the [Evals API](/docs/api-reference/evals).

Create an eval for a task
-------------------------

Creating an eval begins by describing a task to be done by a model. Let's say that we would like to use a model to classify the contents of IT support tickets into one of three categories: `Hardware`, `Software`, or `Other`.

To implement this use case with the [Chat Completions API](/docs/api-reference/chat), you might write code like this that combines a [developer message](/docs/guides/text) with a user message containing the text of a support ticket.

Categorize IT support tickets

```bash
curl https://api.openai.com/v1/chat/completions \
    -H "Authorization: Bearer $OPENAI_API_KEY" \
    -d '{
        "model": "gpt-4.1",
        "messages": [
            {
                "role": "developer",
                "content": "Categorize the following support ticket into one of Hardware, Software, or Other."
            },
            {
                "role": "user",
                "content": "My monitor wont turn on - help!"
            }
        ]
    }'
```

```javascript
import OpenAI from "openai";
const client = new OpenAI();

const instructions = `
You are an expert in categorizing IT support tickets. Given the support 
ticket below, categorize the request into one of "Hardware", "Software", 
or "Other". Respond with only one of those words.
`;

const ticket = "My monitor won't turn on - help!";

const completion = await client.chat.completions.create({
    model: "gpt-4.1",
    messages: [
        { role: "developer", content: instructions },
        { role: "user", content: ticket },
    ],
});

console.log(completion.choices[0].message.content);
```

```python
from openai import OpenAI
client = OpenAI()

instructions = """
You are an expert in categorizing IT support tickets. Given the support 
ticket below, categorize the request into one of "Hardware", "Software", 
or "Other". Respond with only one of those words.
"""

ticket = "My monitor won't turn on - help!"

completion = client.chat.completions.create(
    model="gpt-4.1",
    messages=[
        {"role": "developer", "content": instructions},
        {"role": "user", "content": ticket}
    ]
)

print(completion.choices[0].message.content)
```

Let's set up an eval to test this behavior [via API](/docs/api-reference/evals). An eval needs two key ingredients:

*   `data_source_config`: A schema for the test data you will use along with the eval.
*   `testing_criteria`: The [graders](/docs/guides/graders) that determine if the model output is correct.

```bash
curl https://api.openai.com/v1/evals \
    -H "Authorization: Bearer $OPENAI_API_KEY" \
    -H "Content-Type: application/json" \
    -d '{
        "name": "IT Ticket Categorization",
        "data_source_config": {
            "type": "custom",
            "item_schema": {
                "type": "object",
                "properties": {
                    "ticket_text": { "type": "string" },
                    "correct_label": { "type": "string" }
                },
                "required": ["ticket_text", "correct_label"]
            },
            "include_sample_schema": true
        },
        "testing_criteria": [
            {
                "type": "string_check",
                "name": "Match output to human label",
                "input": "{{ sample.output_text }}",
                "operation": "eq",
                "reference": "{{ item.correct_label }}"
            }
        ]
    }'
```

Explanation: data\_source\_config parameter

Running this eval will require a test data set that represents the type of data you expect your prompt to work with (more on creating the test data set later in this guide). In our `data_source_config` parameter, we specify that each **item** in the data set will conform to a [JSON schema](https://json-schema.org/) with two properties:

*   `ticket_text`: a string of text with the contents of a support ticket
*   `correct_label`: a "ground truth" output that the model should match, provided by a human

Since we will be referencing a **sample** in our test criteria (the output generated by a model given our prompt), we also set `include_sample_schema` to `true`.

```json
{
    "type": "custom",
    "item_schema": {
        "type": "object",
        "properties": {
            "ticket": { "type": "string" },
            "category": { "type": "string" }
        },
        "required": ["ticket", "category"]
    },
    "include_sample_schema": true
}
```

Explanation: testing\_criteria parameter

In our `testing_criteria`, we define how we will conclude if the model output satisfies our requirements for each item in the data set. In this case, we just want the model to output one of three category strings based on the input ticket. The string it outputs should exactly match the human-labeled `correct_label` field in our test data. So in this case, we will want to use a `string_check` grader to evaluate the output.

In the test configuration, we will introduce template syntax, represented by the `{{` and `}}` brackets below. This is how we will insert dynamic content into the test for this eval.

*   `{{ item.correct_label }}` refers to the ground truth value in our test data.
*   `{{ sample.output_text }}` refers to the content we will generate from a model to evaluate our prompt - we'll show how to do that when we actually kick off the eval run.

```json
{
    "type": "string_check",
    "name": "Category string match",
    "input": "{{ sample.output_text }}",
    "operation": "eq",
    "reference": "{{ item.category }}"
}
```

After creating the eval, it will be assigned a UUID that you will need to address it later when kicking off a run.

```json
{
  "object": "eval",
  "id": "eval_67e321d23b54819096e6bfe140161184",
  "data_source_config": {
    "type": "custom",
    "schema": { ... omitted for brevity... }
  },
  "testing_criteria": [
    {
      "name": "Match output to human label",
      "id": "Match output to human label-c4fdf789-2fa5-407f-8a41-a6f4f9afd482",
      "type": "string_check",
      "input": "{{ sample.output_text }}",
      "reference": "{{ item.correct_label }}",
      "operation": "eq"
    }
  ],
  "name": "IT Ticket Categorization",
  "created_at": 1742938578,
  "metadata": {}
}
```

Now that we've created an eval that describes the desired behavior of our application, let's test a prompt with a set of test data.

Test a prompt with your eval
----------------------------

Now that we have defined how we want our app to behave in an eval, let's construct a prompt that reliably generates the correct output for a representative sample of test data.

### Uploading test data

There are several ways to provide test data for eval runs, but it may be convenient to upload a [JSONL](https://jsonlines.org/) file that contains data in the schema we specified when we created our eval. A sample JSONL file that conforms to the schema we set up is below:

```json
{ "item": { "ticket_text": "My monitor won't turn on!", "correct_label": "Hardware" } }
{ "item": { "ticket_text": "I'm in vim and I can't quit!", "correct_label": "Software" } }
{ "item": { "ticket_text": "Best restaurants in Cleveland?", "correct_label": "Other" } }
```

This data set contains both test inputs and ground truth labels to compare model outputs against.

Next, let's upload our test data file to the OpenAI platform so we can reference it later. You can upload files [in the dashboard here](/storage/files), but it's possible to [upload files via API](/docs/api-reference/files/create) as well. The samples below assume you are running the command in a directory where you saved the sample JSON data above to a file called `tickets.jsonl`:

Upload a test data file

```bash
curl https://api.openai.com/v1/files \
  -H "Authorization: Bearer $OPENAI_API_KEY" \
  -F purpose="evals" \
  -F file="@tickets.jsonl"
```

```javascript
import fs from "fs";
import OpenAI from "openai";

const openai = new OpenAI();

const file = await openai.files.create({
    file: fs.createReadStream("tickets.jsonl"),
    purpose: "evals",
});

console.log(file);
```

```python
from openai import OpenAI
client = OpenAI()

const file = client.files.create(
    file=open("tickets.jsonl", "rb"),
    purpose="evals"
)

print(file)
```

When you upload the file, make note of the unique `id` property in the response payload (also available in the UI if you uploaded via the browser) - we will need to reference that value later:

```json
{
    "object": "file",
    "id": "file-CwHg45Fo7YXwkWRPUkLNHW",
    "purpose": "evals",
    "filename": "tickets.jsonl",
    "bytes": 208,
    "created_at": 1742834798,
    "expires_at": null,
    "status": "processed",
    "status_details": null
}
```

### Creating an eval run

With our test data in place, let's evaluate a prompt and see how it performs against our test criteria. Via API, we can do this by [creating an eval run](/docs/api-reference/evals/createRun).

Make sure to replace `YOUR_EVAL_ID` and `YOUR_FILE_ID` with the unique IDs of the eval configuration and test data files you created in the steps above.

```bash
curl https://api.openai.com/v1/evals/YOUR_EVAL_ID/runs \
    -H "Authorization: Bearer $OPENAI_API_KEY" \
    -H "Content-Type: application/json" \
    -d '{
        "name": "Categorization text run",
        "data_source": {
            "type": "completions",
            "model": "gpt-4.1",
            "input": [
                {
                    "role": "developer",
                    "content": "You are an expert in categorizing IT support tickets. Given the support ticket below, categorize the request into one of \"Hardware\", \"Software\", or \"Other\". Respond with only one of those words."
                },
                {
                    "role": "user",
                    "content": "\{\{ item.ticket_text \}\}"
                }
            ],
            "source": {
                "type": "file_id",
                "id": "YOUR_FILE_ID"
            }
        }
    }'
```

When we create the run, we set up a [Chat Completions](/docs/guides/text?api-mode=chat) messages array with the prompt we would like to test. This prompt is used to generate a model response for every line of test data in your data set. We can use the double curly brace syntax to template in the dynamic variable `item.ticket_text`, which is drawn from the current test data item.

If the eval run is successfully created, you'll receive an API response that looks like this:

```json
{
    "object": "eval.run",
    "id": "evalrun_67e44c73eb6481909f79a457749222c7",
    "eval_id": "eval_67e44c5becec81909704be0318146157",
    "report_url": "https://platform.openai.com/evaluations/abc123",
    "status": "queued",
    "model": "gpt-4.1",
    "name": "Categorization text run",
    "created_at": 1743015028,
    "result_counts": { ... },
    "per_model_usage": null,
    "per_testing_criteria_results": null,
    "data_source": {
        "type": "completions",
        "source": {
            "type": "file_id",
            "id": "file-J7MoX9ToHXp2TutMEeYnwj"
        },
        "input_messages": {
            "type": "template",
            "template": [
                {
                    "type": "message",
                    "role": "developer",
                    "content": {
                        "type": "input_text",
                        "text": "You are an expert in...."
                    }
                },
                {
                    "type": "message",
                    "role": "user",
                    "content": {
                        "type": "input_text",
                        "text": "{{item.ticket_text}}"
                    }
                }
            ]
        },
        "model": "gpt-4.1",
        "sampling_params": null
    },
    "error": null,
    "metadata": {}
}
```

Your eval run has now been queued, and it will execute asynchronously as it processes every row in your data set. With our configuration, it will generate completions for testing with the prompt and model we specified.

Analyze the results
-------------------

Depending on the size of your dataset, the eval run may take some time to complete. You can view current status in the dashboard, but you can also [fetch the current status of an eval run via API](/docs/api-reference/evals/getRun):

```bash
curl https://api.openai.com/v1/evals/eval_abc123/runs/evalrun_abc123 \
    -H "Authorization: Bearer $OPENAI_API_KEY" \
    -H "Content-Type: application/json"
```

You'll need the UUID of both your eval and eval run to fetch its status. When you do, you'll see eval run data that looks like this:

```json
{
  "object": "eval.run",
  "id": "evalrun_67e44c73eb6481909f79a457749222c7",
  "eval_id": "eval_67e44c5becec81909704be0318146157",
  "report_url": "https://platform.openai.com/evaluations/xxx",
  "status": "completed",
  "model": "gpt-4.1",
  "name": "Categorization text run",
  "created_at": 1743015028,
  "result_counts": {
    "total": 3,
    "errored": 0,
    "failed": 0,
    "passed": 3
  },
  "per_model_usage": [
    {
      "model_name": "gpt-4o-2024-08-06",
      "invocation_count": 3,
      "prompt_tokens": 166,
      "completion_tokens": 6,
      "total_tokens": 172,
      "cached_tokens": 0
    }
  ],
  "per_testing_criteria_results": [
    {
      "testing_criteria": "Match output to human label-40d67441-5000-4754-ab8c-181c125803ce",
      "passed": 3,
      "failed": 0
    }
  ],
  "data_source": {
    "type": "completions",
    "source": {
      "type": "file_id",
      "id": "file-J7MoX9ToHXp2TutMEeYnwj"
    },
    "input_messages": {
      "type": "template",
      "template": [
        {
          "type": "message",
          "role": "developer",
          "content": {
            "type": "input_text",
            "text": "You are an expert in categorizing IT support tickets. Given the support ticket below, categorize the request into one of Hardware, Software, or Other. Respond with only one of those words."
          }
        },
        {
          "type": "message",
          "role": "user",
          "content": {
            "type": "input_text",
            "text": "{{item.ticket_text}}"
          }
        }
      ]
    },
    "model": "gpt-4.1",
    "sampling_params": null
  },
  "error": null,
  "metadata": {}
}
```

The API response contains granular information about test criteria results, API usage for generating model responses, and a `report_url` property that takes you to a page in the dashboard where you can explore the results visually.

In our simple test, the model reliably generated the content we wanted for a small test case sample. In reality, you will often have to run your eval with more criteria, different prompts, and different data sets. But the process above gives you all the tools you need to build robust evals for your LLM apps!

Video: evals in the dashboard
-----------------------------

The Evaulations tooling [in the OpenAI dashboard](/evaluations) evolves quickly and may not match exactly the UI shown below, but this video will give you a quick overview of how to set up and run evals using the browser-based UI.

Next steps
----------

Now you know how to create and run evals via API, and using the dashboard! Here are a few other resources that may be useful to you as you continue to improve your model results.

[

Cookbook: Detecting prompt regressions

Keep tabs on the performance of your prompts as you iterate on them.

](https://cookbook.openai.com/examples/evaluation/use-cases/regression)[

Cookbook: Bulk model and prompt experimentation

Compare the results of many different prompts and models at once.

](https://cookbook.openai.com/examples/evaluation/use-cases/bulk-experimentation)[

Cookbook: Monitoring stored completions

Examine stored completions to test for prompt regressions.

](https://cookbook.openai.com/examples/evaluation/use-cases/completion-monitoring)[

Fine-tuning

Improve a model's ability to generate responses tailored to your use case.

](/docs/guides/fine-tuning)[

Model distillation

Learn how to distill large model results to smaller, cheaper, and faster models.

](/docs/guides/distillation)