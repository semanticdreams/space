# Add upload part

`POST` `/uploads/{upload_id}/parts`

Adds a [Part](/docs/api-reference/uploads/part-object) to an [Upload](/docs/api-reference/uploads/object) object. A Part represents a chunk of bytes from the file you are trying to upload. 

Each Part can be at most 64 MB, and you can add Parts until you hit the Upload maximum of 8 GB.

It is possible to add multiple Parts in parallel. You can decide the intended order of the Parts when you [complete the Upload](/docs/api-reference/uploads/complete).


## Parameters

### Path Parameters

| Name | Type | Required | Description |
| ---- | ---- | -------- | ----------- |
| `upload_id` | string | Yes | The ID of the Upload. <br>  |

## Request Body

### Content Type: `multipart/form-data`

**Type**: object (1 property)

#### Properties:

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `data` | string | Yes |  |  | The chunk of bytes for this Part. <br>  |
## Responses

### 200 - OK

#### Content Type: `application/json`

#### UploadPart

**Type**: object (4 properties)

The upload Part represents a chunk of bytes we can add to an Upload object.


#### Properties:

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `id` | string | Yes |  |  | The upload Part unique identifier, which can be referenced in API endpoints. |
| `created_at` | integer | Yes |  |  | The Unix timestamp (in seconds) for when the Part was created. |
| `upload_id` | string | Yes |  |  | The ID of the Upload object that this Part was added to. |
| `object` | string | Yes |  | `upload.part` | The object type, which is always `upload.part`. |
**Example:**

```json
{
    "id": "part_def456",
    "object": "upload.part",
    "created_at": 1719186911,
    "upload_id": "upload_abc123"
}

```

## Examples

### Request Examples

#### curl
```bash
curl https://api.openai.com/v1/uploads/upload_abc123/parts
  -F data="aHR0cHM6Ly9hcGkub3BlbmFpLmNvbS92MS91cGxvYWRz..."

```

### Response Example

```json
{
  "id": "part_def456",
  "object": "upload.part",
  "created_at": 1719185911,
  "upload_id": "upload_abc123"
}

```

