# List run steps

`GET` `/threads/{thread_id}/runs/{run_id}/steps`

Returns a list of run steps belonging to a run.

## Parameters

### Path Parameters

| Name | Type | Required | Description |
| ---- | ---- | -------- | ----------- |
| `thread_id` | string | Yes | The ID of the thread the run and run steps belong to. |
| `run_id` | string | Yes | The ID of the run the run steps belong to. |

### Query Parameters

| Name | Type | Required | Description |
| ---- | ---- | -------- | ----------- |
| `limit` | integer | No | A limit on the number of objects to be returned. Limit can range between 1 and 100, and the default is 20. <br>  |
| `order` | string | No | Sort order by the `created_at` timestamp of the objects. `asc` for ascending order and `desc` for descending order. <br>  |
| `after` | string | No | A cursor for use in pagination. `after` is an object ID that defines your place in the list. For instance, if you make a list request and receive 100 objects, ending with obj_foo, your subsequent call can include after=obj_foo in order to fetch the next page of the list. <br>  |
| `before` | string | No | A cursor for use in pagination. `before` is an object ID that defines your place in the list. For instance, if you make a list request and receive 100 objects, starting with obj_foo, your subsequent call can include before=obj_foo in order to fetch the previous page of the list. <br>  |
| `include[]` | array of string | No | A list of additional fields to include in the response. Currently the only supported value is `step_details.tool_calls[*].file_search.results[*].content` to fetch the file search result content. <br>  <br> See the [file search tool documentation](/docs/assistants/tools/file-search#customizing-file-search-settings) for more information. <br>  |

## Responses

### 200 - OK

#### Content Type: `application/json`

#### Properties:

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `object` | string | Yes |  |  |  |
| `data` | array of object (16 properties) | Yes |  |  |  |
| `first_id` | string | Yes |  |  |  |
| `last_id` | string | Yes |  |  |  |
| `has_more` | boolean | Yes |  |  |  |


### Items in `data` array

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `id` | string | Yes |  |  | The identifier of the run step, which can be referenced in API endpoints. |
| `object` | string | Yes |  | `thread.run.step` | The object type, which is always `thread.run.step`. |
| `created_at` | integer | Yes |  |  | The Unix timestamp (in seconds) for when the run step was created. |
| `assistant_id` | string | Yes |  |  | The ID of the [assistant](/docs/api-reference/assistants) associated with the run step. |
| `thread_id` | string | Yes |  |  | The ID of the [thread](/docs/api-reference/threads) that was run. |
| `run_id` | string | Yes |  |  | The ID of the [run](/docs/api-reference/runs) that this run step is a part of. |
| `type` | string | Yes |  | `message_creation`, `tool_calls` | The type of run step, which can be either `message_creation` or `tool_calls`. |
| `status` | string | Yes |  | `in_progress`, `cancelled`, `failed`, `completed`, `expired` | The status of the run step, which can be either `in_progress`, `cancelled`, `failed`, `completed`, or `expired`. |
| `step_details` | object | Yes |  |  | The details of the run step. |
| `last_error` | object (2 properties) | Yes |  |  | The last error associated with this run step. Will be `null` if there are no errors. |
| `expired_at` | integer | Yes |  |  | The Unix timestamp (in seconds) for when the run step expired. A step is considered expired if the parent run is expired. |
| `cancelled_at` | integer | Yes |  |  | The Unix timestamp (in seconds) for when the run step was cancelled. |
| `failed_at` | integer | Yes |  |  | The Unix timestamp (in seconds) for when the run step failed. |
| `completed_at` | integer | Yes |  |  | The Unix timestamp (in seconds) for when the run step completed. |
| `metadata` | map | Yes |  |  | Set of 16 key-value pairs that can be attached to an object. This can be <br> useful for storing additional information about the object in a structured <br> format, and querying for objects via API or the dashboard.  <br>  <br> Keys are strings with a maximum length of 64 characters. Values are strings <br> with a maximum length of 512 characters. <br>  |
|   ↳ (additional properties) | string | - | - | - | Additional properties of this object |
| `usage` | object (3 properties) | Yes |  |  | Usage statistics related to the run step. This value will be `null` while the run step's status is `in_progress`. |
|   ↳ `total_tokens` | integer | Yes |  |  | Total number of tokens used (prompt + completion). |
## Examples

### Request Examples

#### curl
```bash
curl https://api.openai.com/v1/threads/thread_abc123/runs/run_abc123/steps \
  -H "Authorization: Bearer $OPENAI_API_KEY" \
  -H "Content-Type: application/json" \
  -H "OpenAI-Beta: assistants=v2"

```

#### python
```python
from openai import OpenAI
client = OpenAI()

run_steps = client.beta.threads.runs.steps.list(
    thread_id="thread_abc123",
    run_id="run_abc123"
)

print(run_steps)

```

#### node.js
```javascript
import OpenAI from "openai";
const openai = new OpenAI();

async function main() {
  const runStep = await openai.beta.threads.runs.steps.list(
    "thread_abc123",
    "run_abc123"
  );
  console.log(runStep);
}

main();

```

### Response Example

```json
{
  "object": "list",
  "data": [
    {
      "id": "step_abc123",
      "object": "thread.run.step",
      "created_at": 1699063291,
      "run_id": "run_abc123",
      "assistant_id": "asst_abc123",
      "thread_id": "thread_abc123",
      "type": "message_creation",
      "status": "completed",
      "cancelled_at": null,
      "completed_at": 1699063291,
      "expired_at": null,
      "failed_at": null,
      "last_error": null,
      "step_details": {
        "type": "message_creation",
        "message_creation": {
          "message_id": "msg_abc123"
        }
      },
      "usage": {
        "prompt_tokens": 123,
        "completion_tokens": 456,
        "total_tokens": 579
      }
    }
  ],
  "first_id": "step_abc123",
  "last_id": "step_abc456",
  "has_more": false
}

```

