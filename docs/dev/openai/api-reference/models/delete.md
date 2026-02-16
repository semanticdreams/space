# Delete a fine-tuned model

`DELETE` `/models/{model}`

Delete a fine-tuned model. You must have the Owner role in your organization to delete a model.

## Parameters

### Path Parameters

| Name | Type | Required | Description |
| ---- | ---- | -------- | ----------- |
| `model` | string | Yes | The model to delete |

## Responses

### 200 - OK

#### Content Type: `application/json`

**Type**: object (3 properties)

#### Properties:

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `id` | string | Yes |  |  |  |
| `deleted` | boolean | Yes |  |  |  |
| `object` | string | Yes |  |  |  |
## Examples

### Request Examples

#### curl
```bash
curl https://api.openai.com/v1/models/ft:gpt-4o-mini:acemeco:suffix:abc123 \
  -X DELETE \
  -H "Authorization: Bearer $OPENAI_API_KEY"

```

#### python
```python
from openai import OpenAI
client = OpenAI()

client.models.delete("ft:gpt-4o-mini:acemeco:suffix:abc123")

```

#### node.js
```javascript
import OpenAI from "openai";

const openai = new OpenAI();

async function main() {
  const model = await openai.models.del("ft:gpt-4o-mini:acemeco:suffix:abc123");

  console.log(model);
}
main();
```

#### csharp
```csharp
using System;
using System.ClientModel;

using OpenAI.Models;

OpenAIModelClient client = new(
    apiKey: Environment.GetEnvironmentVariable("OPENAI_API_KEY")
);

ClientResult success = client.DeleteModel("ft:gpt-4o-mini:acemeco:suffix:abc123");
Console.WriteLine(success);

```

### Response Example

```json
{
  "id": "ft:gpt-4o-mini:acemeco:suffix:abc123",
  "object": "model",
  "deleted": true
}

```

