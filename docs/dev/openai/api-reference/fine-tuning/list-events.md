# List fine-tuning events

`GET` `/fine_tuning/jobs/{fine_tuning_job_id}/events`

Get status updates for a fine-tuning job.


## Parameters

### Path Parameters

| Name | Type | Required | Description |
| ---- | ---- | -------- | ----------- |
| `fine_tuning_job_id` | string | Yes | The ID of the fine-tuning job to get events for. <br>  |

### Query Parameters

| Name | Type | Required | Description |
| ---- | ---- | -------- | ----------- |
| `after` | string | No | Identifier for the last event from the previous pagination request. |
| `limit` | integer | No | Number of events to retrieve. |

## Responses

### 200 - OK

#### Content Type: `application/json`

**Type**: object (3 properties)

#### Properties:

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `data` | array of object (7 properties) | Yes |  |  |  |
| `object` | string | Yes |  | `list` |  |
| `has_more` | boolean | Yes |  |  |  |


### Items in `data` array

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `object` | string | Yes |  | `fine_tuning.job.event` | The object type, which is always "fine_tuning.job.event". |
| `id` | string | Yes |  |  | The object identifier. |
| `created_at` | integer | Yes |  |  | The Unix timestamp (in seconds) for when the fine-tuning job was created. |
| `level` | string | Yes |  | `info`, `warn`, `error` | The log level of the event. |
| `message` | string | Yes |  |  | The message of the event. |
| `type` | string | No |  | `message`, `metrics` | The type of event. |
| `data` | object | No |  |  | The data associated with the event. |
## Examples

### Request Examples

#### curl
```bash
curl https://api.openai.com/v1/fine_tuning/jobs/ftjob-abc123/events \
  -H "Authorization: Bearer $OPENAI_API_KEY"

```

#### python
```python
from openai import OpenAI
client = OpenAI()

client.fine_tuning.jobs.list_events(
  fine_tuning_job_id="ftjob-abc123",
  limit=2
)

```

#### node.js
```javascript
import OpenAI from "openai";

const openai = new OpenAI();

async function main() {
  const list = await openai.fineTuning.list_events(id="ftjob-abc123", limit=2);

  for await (const fineTune of list) {
    console.log(fineTune);
  }
}

main();
```

### Response Example

```json
{
  "object": "list",
  "data": [
    {
      "object": "fine_tuning.job.event",
      "id": "ft-event-ddTJfwuMVpfLXseO0Am0Gqjm",
      "created_at": 1721764800,
      "level": "info",
      "message": "Fine tuning job successfully completed",
      "data": null,
      "type": "message"
    },
    {
      "object": "fine_tuning.job.event",
      "id": "ft-event-tyiGuB72evQncpH87xe505Sv",
      "created_at": 1721764800,
      "level": "info",
      "message": "New fine-tuned model created: ft:gpt-4o-mini:openai::7p4lURel",
      "data": null,
      "type": "message"
    }
  ],
  "has_more": true
}

```

