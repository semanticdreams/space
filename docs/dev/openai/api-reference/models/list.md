# List models

`GET` `/models`

Lists the currently available models, and provides basic information about each one such as the owner and availability.

## Responses

### 200 - OK

#### Content Type: `application/json`

**Type**: object (2 properties)

#### Properties:

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `object` | string | Yes |  | `list` |  |
| `data` | array of unknown | Yes |  |  |  |


### Items in `data` array

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `id` | string | Yes |  |  | The model identifier, which can be referenced in the API endpoints. |
| `created` | integer | Yes |  |  | The Unix timestamp (in seconds) when the model was created. |
| `object` | string | Yes |  | `model` | The object type, which is always "model". |
| `owned_by` | string | Yes |  |  | The organization that owns the model. |
## Examples

### Request Examples

#### curl
```bash
curl https://api.openai.com/v1/models \
  -H "Authorization: Bearer $OPENAI_API_KEY"

```

#### python
```python
from openai import OpenAI
client = OpenAI()

client.models.list()

```

#### node.js
```javascript
import OpenAI from "openai";

const openai = new OpenAI();

async function main() {
  const list = await openai.models.list();

  for await (const model of list) {
    console.log(model);
  }
}
main();
```

#### csharp
```csharp
using System;

using OpenAI.Models;

OpenAIModelClient client = new(
    apiKey: Environment.GetEnvironmentVariable("OPENAI_API_KEY")
);

foreach (var model in client.GetModels().Value)
{
    Console.WriteLine(model.Id);
}

```

### Response Example

```json
{
  "object": "list",
  "data": [
    {
      "id": "model-id-0",
      "object": "model",
      "created": 1686935002,
      "owned_by": "organization-owner"
    },
    {
      "id": "model-id-1",
      "object": "model",
      "created": 1686935002,
      "owned_by": "organization-owner",
    },
    {
      "id": "model-id-2",
      "object": "model",
      "created": 1686935002,
      "owned_by": "openai"
    },
  ],
  "object": "list"
}

```

