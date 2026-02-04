# Retrieve model

`GET` `/models/{model}`

Retrieves a model instance, providing basic information about the model such as the owner and permissioning.

## Parameters

### Path Parameters

| Name | Type | Required | Description |
| ---- | ---- | -------- | ----------- |
| `model` | string | Yes | The ID of the model to use for this request |

## Responses

### 200 - OK

#### Content Type: `application/json`

#### Model

Describes an OpenAI model offering that can be used with the API.

#### Properties:

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `id` | string | Yes |  |  | The model identifier, which can be referenced in the API endpoints. |
| `created` | integer | Yes |  |  | The Unix timestamp (in seconds) when the model was created. |
| `object` | string | Yes |  | `model` | The object type, which is always "model". |
| `owned_by` | string | Yes |  |  | The organization that owns the model. |
**Example:**

```json
{
  "id": "VAR_chat_model_id",
  "object": "model",
  "created": 1686935002,
  "owned_by": "openai"
}

```

## Examples

### Request Examples

#### curl
```bash
curl https://api.openai.com/v1/models/VAR_chat_model_id \
  -H "Authorization: Bearer $OPENAI_API_KEY"

```

#### python
```python
from openai import OpenAI
client = OpenAI()

client.models.retrieve("VAR_chat_model_id")

```

#### node.js
```javascript
import OpenAI from "openai";

const openai = new OpenAI();

async function main() {
  const model = await openai.models.retrieve("VAR_chat_model_id");

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

ClientResult<OpenAIModel> model = client.GetModel("babbage-002");
Console.WriteLine(model.Value.Id);

```

### Response Example

```json
{
  "id": "VAR_chat_model_id",
  "object": "model",
  "created": 1686935002,
  "owned_by": "openai"
}

```

