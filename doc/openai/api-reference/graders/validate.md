# Validate grader

`POST` `/fine_tuning/alpha/graders/validate`

Validate a grader.


## Request Body

### Content Type: `application/json`

### ValidateGraderRequest

**Type**: object (1 property)

#### Properties:

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `grader` | object | Yes |  |  | The grader used for the fine-tuning job. |
## Responses

### 200 - OK

#### Content Type: `application/json`

#### ValidateGraderResponse

**Type**: object (1 property)

#### Properties:

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `grader` | object | No |  |  | The grader used for the fine-tuning job. |
## Examples

### Request Examples

#### curl
```bash
curl https://api.openai.com/v1/fine_tuning/alpha/graders/validate \
  -H "Authorization: Bearer $OPENAI_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "grader": {
      "type": "string_check",
      "name": "Example string check grader",
      "input": "{{sample.output_text}}",
      "reference": "{{item.label}}",
      "operation": "eq"
    }
  }'

```

### Response Example

```json
{
  "grader": {
    "type": "string_check",
    "name": "Example string check grader",
    "input": "{{sample.output_text}}",
    "reference": "{{item.label}}",
    "operation": "eq"
  }
}

```

